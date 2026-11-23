// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Canonicalizes the single-track CMAF layout used by BBC UHD. Some fragments
/// have unreferenced bytes before their first sample; AVPlayer's HLS demuxer
/// rejects those even though the DASH trun points past them correctly.
enum FMP4Normalizer {
    private struct Box { let start: Int; let size: Int; let header: Int; let type: String; var end: Int { start + size } }
    static func normalize(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func uint(_ offset: Int, _ count: Int) throws -> UInt64 {
            guard offset >= 0, count <= 8, offset <= bytes.count - count else { throw BBCError.message("Truncated UHD media fragment.") }
            return bytes[offset..<offset+count].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func boxes(_ start: Int, _ end: Int) throws -> [Box] {
            var result = [Box](), offset = start
            while offset < end {
                guard end - offset >= 8 else { throw BBCError.message("Truncated UHD media box.") }
                let short = try uint(offset, 4), header = short == 1 ? 16 : 8
                let length = short == 1 ? try uint(offset + 8, 8) : (short == 0 ? UInt64(end - offset) : short)
                guard length >= header, length <= end - offset else { throw BBCError.message("Invalid UHD media box size.") }
                result.append(Box(start: offset, size: Int(length), header: header, type: String(decoding: bytes[offset+4..<offset+8], as: UTF8.self)))
                offset += Int(length)
            }
            return result
        }
        let top = try boxes(0, bytes.count)
        let moofs = top.filter { $0.type == "moof" }, mdats = top.filter { $0.type == "mdat" }
        guard moofs.count == 1, mdats.count == 1, let moof = moofs.first, let mdat = mdats.first, moof.end <= mdat.start else {
            throw BBCError.message("Unsupported UHD fragment layout.")
        }
        let trafs = try boxes(moof.start + moof.header, moof.end).filter { $0.type == "traf" }
        guard trafs.count == 1, let traf = trafs.first else { throw BBCError.message("Unsupported UHD fragment tracks.") }
        let children = try boxes(traf.start + traf.header, traf.end)
        guard let tfhd = children.first(where: { $0.type == "tfhd" }), tfhd.size >= tfhd.header + 8,
              let trun = children.first(where: { $0.type == "trun" }), children.filter({ $0.type == "trun" }).count == 1, trun.size >= trun.header + 12 else {
            throw BBCError.message("Missing UHD fragment sample addressing.")
        }
        let tfhdFlags = try uint(tfhd.start + tfhd.header, 4) & 0xffffff
        let trunFlags = try uint(trun.start + trun.header, 4) & 0xffffff
        guard tfhdFlags & 0x020000 != 0, tfhdFlags & 1 == 0, trunFlags & 1 != 0 else {
            throw BBCError.message("Unsupported UHD fragment data offset.")
        }
        let offsetPosition = trun.start + trun.header + 8
        let rawOffset = try uint(offsetPosition, 4)
        let offset = Int(Int32(bitPattern: UInt32(rawOffset)))
        let payloadStart = mdat.start + mdat.header
        let padding = moof.start + offset - payloadStart
        guard padding >= 0, padding <= 4096, padding < mdat.size - mdat.header else { throw BBCError.message("Invalid UHD sample padding.") }
        guard padding > 0 else { return data }
        // Restrict rewriting to the BBC layout: one moof followed by its final
        // mdat. No subsequent indexes or absolute byte offsets need updating.
        guard mdat.end == bytes.count else { throw BBCError.message("Unsupported padded UHD fragment layout.") }
        var output = data
        func replaceUInt(_ position: Int, _ count: Int, _ value: UInt64) {
            let encoded = (0..<count).map { UInt8(truncatingIfNeeded: value >> ((count - 1 - $0) * 8)) }
            output.replaceSubrange(position..<position+count, with: encoded)
        }
        replaceUInt(offsetPosition, 4, UInt64(offset - padding))
        if mdat.header == 16 { replaceUInt(mdat.start + 8, 8, UInt64(mdat.size - padding)) }
        else if try uint(mdat.start, 4) != 0 { replaceUInt(mdat.start, 4, UInt64(mdat.size - padding)) }
        output.removeSubrange(payloadStart..<payloadStart+padding)
        return output
    }
}

/// BBC UHD carries HLG with backwards-compatible signalling: each HEVC sequence parameter set declares
/// the SDR-compatible BT.2020 transfer function (14), and only a supplemental message names HLG (18).
/// macOS and tvOS obey the parameter sets and treat the picture as SDR, whatever the playlist's VIDEO-RANGE
/// says: a Mac shows it without extended range, and an Apple TV switches the television to HLG but fills
/// that mode with a picture processed as SDR. For a stream already verified as HLG, this declares HLG in
/// the parameter sets themselves.
enum HLGSignalling {
    private struct Unsupported: Error {}
    private struct BitReader {
        let bytes: [UInt8]
        var position = 0
        mutating func bits(_ count: Int) throws -> Int {
            guard count >= 0, count <= 32, position + count <= bytes.count * 8 else { throw Unsupported() }
            var value = 0
            for _ in 0..<count { value = (value << 1) | Int((bytes[position >> 3] >> UInt8(7 - (position & 7))) & 1); position += 1 }
            return value
        }
        mutating func flag() throws -> Bool { try bits(1) == 1 }
        mutating func skip(_ count: Int) throws {
            guard count >= 0, position + count <= bytes.count * 8 else { throw Unsupported() }
            position += count
        }
        /// Exp-Golomb, unsigned and signed.
        mutating func ue() throws -> Int {
            var zeros = 0
            while try bits(1) == 0 { zeros += 1; guard zeros <= 30 else { throw Unsupported() } }
            let rest = try bits(zeros)
            return (1 << zeros) - 1 + rest
        }
        mutating func se() throws -> Int { let code = try ue(); return code & 1 == 1 ? (code + 1) / 2 : -(code / 2) }
    }
    /// Every in-band sequence parameter set in a video fragment is rewritten in place. Media data is read
    /// as four-byte length-prefixed HEVC units up to the first bytes that are not one: BBC's packager
    /// leaves a short unreferenced tail after the last sample of some fragments.
    static func promote(_ fragment: Data) -> Data {
        let bytes = [UInt8](fragment)
        func uint(_ offset: Int, _ count: Int) -> Int { bytes[offset..<offset+count].reduce(0) { ($0 << 8) | Int($1) } }
        var patches = [(Int, [UInt8])](), offset = 0
        while bytes.count - offset >= 8 {
            let short = uint(offset, 4), extended = short == 1
            guard !extended || bytes.count - offset >= 16 else { return fragment }
            let header = extended ? 16 : 8
            let size = extended ? uint(offset + 8, 8) : (short == 0 ? bytes.count - offset : short)
            guard size >= header, size <= bytes.count - offset else { return fragment }
            if bytes[offset+4..<offset+8].elementsEqual("mdat".utf8) {
                var unit = offset + header
                let end = offset + size
                while end - unit >= 6 {
                    let length = uint(unit, 4)
                    guard length >= 2, length <= end - unit - 4, bytes[unit + 4] & 0x80 == 0 else { break }
                    if (bytes[unit + 4] >> 1) & 0x3f == 33, let patched = promote(sequenceParameterSet: Array(bytes[unit+4..<unit+4+length])) {
                        patches.append((unit + 4, patched))
                    }
                    unit += 4 + length
                }
            }
            offset += size
        }
        guard offset == bytes.count, !patches.isEmpty else { return fragment }
        var output = bytes
        for (position, unit) in patches { output.replaceSubrange(position..<position+unit.count, with: unit) }
        return Data(output)
    }
    /// The same parameter set declaring HLG, or nil when it does not declare BT.2020 primaries with the
    /// SDR-compatible transfer function, cannot be read, or would change length.
    static func promote(sequenceParameterSet unit: [UInt8]) -> [UInt8]? {
        // Emulation prevention: a 3 after two zero bytes is padding, not payload.
        var payload = [UInt8](), zeros = 0
        payload.reserveCapacity(unit.count)
        for byte in unit {
            if zeros >= 2 && byte == 3 { zeros = 0; continue }
            zeros = byte == 0 ? zeros + 1 : 0
            payload.append(byte)
        }
        func escaped(_ payload: [UInt8]) -> [UInt8] {
            var result = [UInt8](), zeros = 0
            result.reserveCapacity(payload.count + 4)
            for byte in payload {
                if zeros >= 2 && byte <= 3 { result.append(3); zeros = 0 }
                zeros = byte == 0 ? zeros + 1 : 0
                result.append(byte)
            }
            return result
        }
        guard escaped(payload) == unit, let position = try? transferFunctionPosition(payload) else { return nil }
        for bit in 0..<8 {
            let index = (position + bit) >> 3, mask = UInt8(0x80) >> UInt8((position + bit) & 7)
            if 18 & (0x80 >> bit) != 0 { payload[index] |= mask } else { payload[index] &= ~mask }
        }
        let result = escaped(payload)
        return result.count == unit.count ? result : nil
    }
    /// Bit position of transfer_characteristics when the parameter set declares BT.2020 primaries (9)
    /// with the SDR-compatible transfer function (14); nil when it declares anything else.
    private static func transferFunctionPosition(_ payload: [UInt8]) throws -> Int? {
        var reader = BitReader(bytes: payload)
        // Unit header: a base-layer sequence parameter set.
        guard try reader.bits(1) == 0, try reader.bits(6) == 33, try reader.bits(6) == 0 else { throw Unsupported() }
        try reader.skip(3 + 4)
        let subLayers = try reader.bits(3)
        try reader.skip(1 + 96) // nesting flag, general profile, tier and level
        var profiles = [Bool](), levels = [Bool]()
        for _ in 0..<subLayers { profiles.append(try reader.flag()); levels.append(try reader.flag()) }
        if subLayers > 0 { try reader.skip(2 * (8 - subLayers)) }
        for layer in 0..<subLayers { try reader.skip((profiles[layer] ? 88 : 0) + (levels[layer] ? 8 : 0)) }
        _ = try reader.ue()
        if try reader.ue() == 3 { try reader.skip(1) } // chroma format, separate colour planes
        _ = try reader.ue(); _ = try reader.ue() // width, height
        if try reader.flag() { for _ in 0..<4 { _ = try reader.ue() } } // conformance window
        _ = try reader.ue(); _ = try reader.ue() // bit depths
        let orderCountBits = try reader.ue() + 4
        guard orderCountBits <= 16 else { throw Unsupported() }
        let everyLayer = try reader.flag()
        for _ in (everyLayer ? 0 : subLayers)...subLayers { for _ in 0..<3 { _ = try reader.ue() } }
        for _ in 0..<6 { _ = try reader.ue() } // coding and transform block sizes
        if try reader.flag(), try reader.flag() { // scaling lists
            for size in 0..<4 {
                for _ in stride(from: 0, to: 6, by: size == 3 ? 3 : 1) {
                    if try !reader.flag() { _ = try reader.ue(); continue }
                    if size > 1 { _ = try reader.se() }
                    for _ in 0..<min(64, 1 << (4 + (size << 1))) { _ = try reader.se() }
                }
            }
        }
        try reader.skip(2) // asymmetric partitions, sample adaptive offset
        if try reader.flag() { try reader.skip(8); _ = try reader.ue(); _ = try reader.ue(); try reader.skip(1) } // PCM
        // Short-term reference picture sets. A set predicted from the previous one has as many flags
        // as that set has pictures, so each set's picture counts have to be derived.
        let sets = try reader.ue()
        guard sets <= 64 else { throw Unsupported() }
        var before = [Int](), after = [Int]()
        for set in 0..<sets {
            var nextBefore = [Int](), nextAfter = [Int]()
            if set > 0, try reader.flag() {
                let negative = try reader.flag(), magnitude = try reader.ue() + 1
                let delta = negative ? -magnitude : magnitude
                var use = [Bool]()
                for _ in 0...(before.count + after.count) {
                    let used = try reader.flag()
                    use.append(used ? true : try reader.flag())
                }
                for index in after.indices.reversed() where after[index] + delta < 0 && use[before.count + index] { nextBefore.append(after[index] + delta) }
                if delta < 0 && use[before.count + after.count] { nextBefore.append(delta) }
                for index in before.indices where before[index] + delta < 0 && use[index] { nextBefore.append(before[index] + delta) }
                for index in before.indices.reversed() where before[index] + delta > 0 && use[index] { nextAfter.append(before[index] + delta) }
                if delta > 0 && use[before.count + after.count] { nextAfter.append(delta) }
                for index in after.indices where after[index] + delta > 0 && use[before.count + index] { nextAfter.append(after[index] + delta) }
            } else {
                let negatives = try reader.ue(), positives = try reader.ue()
                guard negatives <= 16, positives <= 16 else { throw Unsupported() }
                var count = 0
                for _ in 0..<negatives { count -= try reader.ue() + 1; nextBefore.append(count); try reader.skip(1) }
                count = 0
                for _ in 0..<positives { count += try reader.ue() + 1; nextAfter.append(count); try reader.skip(1) }
            }
            guard nextBefore.count + nextAfter.count <= 32 else { throw Unsupported() }
            before = nextBefore; after = nextAfter
        }
        if try reader.flag() { // long-term reference pictures
            let pictures = try reader.ue()
            guard pictures <= 32 else { throw Unsupported() }
            try reader.skip(pictures * (orderCountBits + 1))
        }
        try reader.skip(2) // temporal motion vectors, strong intra smoothing
        guard try reader.flag() else { return nil } // video usability information
        if try reader.flag(), try reader.bits(8) == 255 { try reader.skip(32) } // aspect ratio
        if try reader.flag() { try reader.skip(1) } // overscan
        guard try reader.flag() else { return nil } // video signal type
        try reader.skip(3 + 1) // format, full range
        guard try reader.flag(), try reader.bits(8) == 9 else { return nil } // colour description, BT.2020 primaries
        let position = reader.position
        return try reader.bits(8) == 14 ? position : nil
    }
}
