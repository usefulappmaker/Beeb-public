// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security
import CryptoKit

/// On-device UHD setup. Never executes upstream code or writes its private key to a file.
enum TwinVineDirectSetup {
    static let configurationURL = URL(string: "https://git.gay/Vinefeeder/twinvine-services/raw/branch/main/iP/config.yaml")!
    static let maximumSize = 131072
    enum SetupError: LocalizedError {
        case invalidConfiguration, unsupportedKey, expiredCertificate, mismatchedKey, downloadFailed
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: "The UHD setup configuration could not be read. Your existing UHD setup has been kept."
            case .unsupportedKey: "This BBC UHD setup identity uses a key format that direct setup does not support. Please try again after the upstream configuration is updated."
            case .expiredCertificate: "The UHD setup certificate is expired or not valid yet. Your existing UHD setup has been kept."
            case .mismatchedKey: "The UHD setup certificate and private key do not match. Your existing UHD setup has been kept."
            case .downloadFailed: "Could not download The UHD setup configuration. Check your connection and try again."
            }
        }
    }
    static func prepare() async throws -> UHDBootstrap {
        let data = try await ConfigurationDownload().retrieve()
        try Task.checkCancellation()
        return try package(data)
    }
    /// Supports only the two literal scalar fields needed by Beeb, not general YAML evaluation.
    static func fields(_ data: Data) throws -> (pem: Data, agent: String) {
        guard data.count <= maximumSize, let text = String(data: data, encoding: .utf8) else { throw SetupError.invalidConfiguration }
        let lines = text.components(separatedBy: .newlines)
        func field(_ name: String) throws -> String {
            let matches = lines.indices.filter { lines[$0].hasPrefix(name + ":") }
            guard matches.count == 1, let start = matches.first else { throw SetupError.invalidConfiguration }
            let scalar = String(lines[start].dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            if ["|", "|-", "|+", ">", ">-"].contains(scalar) {
                var values = [String]()
                for line in lines.dropFirst(start + 1) {
                    if line.isEmpty { continue }
                    guard line.first == " " || line.first == "\t" else { break }
                    let value = line.trimmingCharacters(in: .whitespaces)
                    if !value.hasPrefix("#") { values.append(value) }
                }
                return values.joined(separator: name == "certificate" ? "" : "\n")
            }
            if scalar.hasPrefix("\"") {
                guard let bytes = scalar.data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: bytes) else { throw SetupError.invalidConfiguration }
                return value
            }
            if scalar.hasPrefix("'") {
                guard scalar.count >= 2, scalar.hasSuffix("'") else { throw SetupError.invalidConfiguration }
                return String(scalar.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            guard !scalar.hasPrefix("!"), !scalar.hasPrefix("*"), !scalar.hasPrefix("&") else { throw SetupError.invalidConfiguration }
            return scalar.components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces)
        }
        let agent = try field("user_agent"), encoded = try field("certificate")
        guard !agent.isEmpty, agent.utf8.count < 2048, !agent.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let pem = Data(base64Encoded: encoded), pem.count < maximumSize else { throw SetupError.invalidConfiguration }
        return (pem, agent)
    }
    static func package(_ data: Data, now: Date = Date()) throws -> UHDBootstrap {
        let values = try fields(data)
        let certificate = try block("CERTIFICATE", in: values.pem)
        let pkcs8: Data, pkcs1: Data
        if let raw = try? block("PRIVATE KEY", in: values.pem) {
            let parts = try DER.one(raw, tag: 0x30).children()
            guard parts.count == 3, parts[0].tag == 2, parts[1].tag == 0x30, parts[2].tag == 4,
                  parts[1].encoded == NativeIdentityPackage.seq(NativeIdentityPackage.oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,1), NativeIdentityPackage.der(5, Data())) else { throw SetupError.unsupportedKey }
            pkcs8 = raw; pkcs1 = parts[2].value
        } else {
            pkcs1 = try block("RSA PRIVATE KEY", in: values.pem)
            pkcs8 = NativeIdentityPackage.seq(NativeIdentityPackage.integer(0), NativeIdentityPackage.seq(NativeIdentityPackage.oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,1), NativeIdentityPackage.der(5, Data())), NativeIdentityPackage.der(4, pkcs1))
        }
        guard let cert = SecCertificateCreateWithData(nil, certificate as CFData), let publicKey = SecCertificateCopyKey(cert),
              let privateKey = SecKeyCreateWithData(pkcs1 as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, nil),
              let derived = SecKeyCopyPublicKey(privateKey),
              let expected = SecKeyCopyExternalRepresentation(publicKey, nil), let actual = SecKeyCopyExternalRepresentation(derived, nil), expected as Data == actual as Data else { throw SetupError.mismatchedKey }
        let root = try DER.one(certificate, tag: 0x30).children()
        guard let tbs = root.first, tbs.tag == 0x30 else { throw SetupError.invalidConfiguration }
        let tbsFields = try tbs.children(), validityIndex = tbsFields.first?.tag == 0xa0 ? 4 : 3
        guard tbsFields.count > validityIndex else { throw SetupError.invalidConfiguration }
        let dates = try tbsFields[validityIndex].children()
        guard dates.count == 2 else { throw SetupError.invalidConfiguration }
        let start = try dates[0].date(), end = try dates[1].date()
        guard start <= now, now < end else { throw SetupError.expiredCertificate }
        var random = Data(count: 24)
        guard random.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 24, $0.baseAddress!) }) == errSecSuccess else { throw SetupError.invalidConfiguration }
        let password = random.map { String(format: "%02x", $0) }.joined()
        let package = try NativeIdentityPackage.create(pkcs8: pkcs8, certificate: certificate, password: password)
        return UHDBootstrap(p12: package.base64EncodedString(), password: password, userAgent: values.agent)
    }
    static func block(_ label: String, in data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw SetupError.invalidConfiguration }
        let begin = "-----BEGIN \(label)-----", end = "-----END \(label)-----"
        guard text.components(separatedBy: begin).count == 2, let start = text.range(of: begin), let finish = text.range(of: end, range: start.upperBound..<text.endIndex),
              let value = Data(base64Encoded: text[start.upperBound..<finish.lowerBound].filter { !$0.isWhitespace }), !value.isEmpty else { throw SetupError.invalidConfiguration }
        return value
    }
    struct DER {
        let tag: UInt8
        let value: Data
        let encoded: Data
        func children() throws -> [DER] { try Self.read(value) }
        static func one(_ data: Data, tag: UInt8) throws -> DER {
            let nodes = try read(data)
            guard nodes.count == 1, nodes[0].tag == tag else { throw SetupError.invalidConfiguration }
            return nodes[0]
        }
        static func read(_ data: Data) throws -> [DER] {
            let bytes = [UInt8](data); var offset = 0, result = [DER]()
            while offset < bytes.count {
                let start = offset
                guard offset + 2 <= bytes.count else { throw SetupError.invalidConfiguration }
                let tag = bytes[offset]; offset += 1
                let prefix = bytes[offset]; offset += 1
                var length = Int(prefix)
                if prefix >= 128 {
                    let count = Int(prefix & 127)
                    guard count > 0, count <= 4, offset + count <= bytes.count else { throw SetupError.invalidConfiguration }
                    length = 0
                    for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                }
                guard length <= bytes.count - offset else { throw SetupError.invalidConfiguration }
                let end = offset + length
                result.append(DER(tag: tag, value: Data(bytes[offset..<end]), encoded: Data(bytes[start..<end])))
                offset = end
            }
            return result
        }
        func date() throws -> Date {
            guard (tag == 0x17 && value.count == 13) || (tag == 0x18 && value.count == 15), let text = String(data: value, encoding: .ascii), text.hasSuffix("Z") else { throw SetupError.invalidConfiguration }
            let full: String
            if tag == 0x17 {
                guard let year = Int(text.prefix(2)) else { throw SetupError.invalidConfiguration }
                full = (year >= 50 ? "19" : "20") + text
            } else { full = text }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false; formatter.dateFormat = "yyyyMMddHHmmss'Z'"
            guard let date = formatter.date(from: full) else { throw SetupError.invalidConfiguration }
            return date
        }
    }
    private final class ConfigurationDownload: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func retrieve() async throws -> Data {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 40; config.urlCache = nil
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(from: configurationURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == configurationURL,
                  response.expectedContentLength <= Int64(maximumSize) else { throw SetupError.downloadFailed }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumSize else { throw SetupError.downloadFailed }
                data.append(byte)
            }
            return data
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
