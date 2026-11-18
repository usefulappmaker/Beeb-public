// SPDX-License-Identifier: GPL-3.0-or-later
// PKCS#12 import container built locally; no external executable or crypto dependency.
import Foundation
import Security
import CryptoKit
import CommonCrypto

enum NativeIdentityPackage {
    static func der(_ tag: UInt8, _ value: Data) -> Data {
        let count = value.count
        var length = Data()
        if count < 128 { length.append(UInt8(count)) }
        else {
            var n = count; var bytes = [UInt8]()
            while n > 0 { bytes.insert(UInt8(n & 255), at: 0); n >>= 8 }
            length.append(0x80 | UInt8(bytes.count)); length.append(contentsOf: bytes)
        }
        return Data([tag]) + length + value
    }
    static func seq(_ values: Data...) -> Data { der(0x30, values.reduce(Data(), +)) }
    static func oid(_ values: UInt8...) -> Data { der(0x06, Data(values)) }
    static func integer(_ n: Int) -> Data {
        var n = n; var bytes = [UInt8]()
        repeat { bytes.insert(UInt8(n & 255), at: 0); n >>= 8 } while n > 0
        if bytes[0] >= 128 { bytes.insert(0, at: 0) }
        return der(2, Data(bytes))
    }
    static let dataOID = oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,1)
    static func content(_ data: Data) -> Data { seq(dataOID, der(0xa0, der(4, data))) }
    static func key(_ password: String, salt: Data, iterations: Int) -> Data {
        let d = Data(repeating: 3, count: 64)
        var p = Data()
        for unit in password.utf16 { p.append(UInt8(unit >> 8)); p.append(UInt8(unit & 255)) }
        p.append(contentsOf: [0,0])
        func repeatToBlock(_ value: Data) -> Data {
            guard !value.isEmpty else { return Data() }
            return Data((0..<(64 * ((value.count + 63) / 64))).map { value[$0 % value.count] })
        }
        // SHA-1 has a 20-byte digest; a single PKCS#12 derivation block supplies the MAC key.
        let input = d + repeatToBlock(salt) + repeatToBlock(p)
        var a = Data(Insecure.SHA1.hash(data: input))
        for _ in 1..<iterations { a = Data(Insecure.SHA1.hash(data: a)) }
        return a
    }
    static func encryptedKey(_ plaintext: Data, password: String) throws -> Data {
        var salt = Data(count: 16), iv = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault,16,$0.baseAddress!) }) == errSecSuccess,
              iv.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault,16,$0.baseAddress!) }) == errSecSuccess else { throw NSError(domain:"NativeIdentity",code:1) }
        var secret = Data(count:32)
        let passwordBytes = Array(password.utf8)
        let derived = secret.withUnsafeMutableBytes { target in salt.withUnsafeBytes { salt in
            passwordBytes.withUnsafeBytes { bytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),bytes.baseAddress!.assumingMemoryBound(to:CChar.self),passwordBytes.count,salt.baseAddress!.assumingMemoryBound(to:UInt8.self),salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),10000,target.baseAddress!.assumingMemoryBound(to:UInt8.self),32)
            }
        } }
        guard derived == kCCSuccess else { throw NSError(domain:"NativeIdentity",code:Int(derived)) }
        defer { secret.resetBytes(in:0..<secret.count) }
        var encrypted=Data(count:plaintext.count+16), written=0
        let capacity=encrypted.count
        let status=encrypted.withUnsafeMutableBytes { output in plaintext.withUnsafeBytes { input in secret.withUnsafeBytes { key in iv.withUnsafeBytes { iv in
            CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),key.baseAddress,32,iv.baseAddress,input.baseAddress,plaintext.count,output.baseAddress,capacity,&written)
        } } } }
        guard status == kCCSuccess else { throw NSError(domain:"NativeIdentity",code:Int(status)) }
        encrypted.count=written
        let prf=seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,2,9),der(5,Data()))
        let pbkdf=seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,5,12),seq(der(4,salt),integer(10000),integer(32),prf))
        let aes=seq(oid(0x60,0x86,0x48,1,0x65,3,4,1,42),der(4,iv))
        let algorithm=seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,5,13),seq(pbkdf,aes))
        return seq(algorithm,der(4,encrypted))
    }
    static func create(pkcs8: Data, certificate: Data, password: String) throws -> Data {
        let localID = Data(Insecure.SHA1.hash(data: certificate))
        let attrs = der(0x31, seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,9,21), der(0x31, der(4, localID))))
        let cert = seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,9,22,1), der(0xa0, der(4, certificate)))
        let certBag = seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,12,10,1,3),der(0xa0,cert),attrs)
        let keyBag = try seq(oid(0x2a,0x86,0x48,0x86,0xf7,0x0d,1,12,10,1,2),der(0xa0,encryptedKey(pkcs8,password:password)),attrs)
        let authenticatedSafe = seq(content(seq(certBag, keyBag)))
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw NSError(domain: "NativeIdentity", code: Int(status)) }
        let iterations = 2048
        let mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: authenticatedSafe, using: SymmetricKey(data: key(password,salt:salt,iterations:iterations))))
        let digest = seq(seq(oid(0x2b,0x0e,3,2,26), der(5,Data())), der(4,mac))
        return seq(integer(3), content(authenticatedSafe), seq(digest,der(4,salt),integer(iterations)))
    }
}
