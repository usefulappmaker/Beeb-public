// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security
import CryptoKit

struct UHDBootstrap: Codable { let p12: String; let password: String; let userAgent: String }
enum UHDIdentityVault {
    private static let fingerprintKey = "bbcUHDIdentityFingerprint-v1"
    private static let agentKey = "bbcUHDUserAgent-v1"
    private struct StoredSetup: Codable {
        let fingerprint: String
        let userAgent: String
        var bootstrap: UHDBootstrap? = nil
    }
    private static var setupQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.beebplayer.Beeb.uhd-setup",
         kSecAttrAccount as String: "setup-v1"]
    }
    private static func storedSetup() -> StoredSetup? {
        var query = setupQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSetup.self, from: data)
    }
    private static func saveSetup(_ setup: StoredSetup) throws {
        let data = try JSONEncoder().encode(setup)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(setupQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var query = setupQuery; attributes.forEach { query[$0.key] = $0.value }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw BBCError.message("Could not retain UHD setup in Keychain (\(status)).") }
        } else if update != errSecSuccess { throw BBCError.message("Could not update UHD setup in Keychain (\(update)).") }
    }
    static var userAgent: String { storedSetup()?.userAgent ?? UserDefaults.standard.string(forKey: agentKey) ?? "" }
    private static func fingerprint(of identity: SecIdentity) -> String? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return nil }
        return SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
    }
    static var isConfigured: Bool { identity() != nil && !userAgent.isEmpty }
    static func importIdentity(_ data: Data, password: String) throws -> SecIdentity {
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        #if os(macOS)
        if #available(macOS 15.0, *) { options[kSecImportToMemoryOnly as String] = true }
        #endif
        var result: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &result)
        guard status == errSecSuccess, let first = (result as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String] else { throw BBCError.message("Could not import the UHD identity (\(status)).") }
        return value as! SecIdentity
    }
    private static func label(_ fingerprint: String) -> String { "BeebHD.BBC.UHD." + fingerprint }
    private static func query(_ fingerprint: String) -> [String: Any] {
        [kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: label(fingerprint)]
    }
    static func identity() -> SecIdentity? {
        let setup = storedSetup()
        guard let expected = setup?.fingerprint ?? UserDefaults.standard.string(forKey: fingerprintKey) else { return nil }
        func found(_ identity: SecIdentity) -> SecIdentity {
            if setup == nil, let agent = UserDefaults.standard.string(forKey: agentKey), !agent.isEmpty {
                try? saveSetup(StoredSetup(fingerprint: expected, userAgent: agent))
            }
            return identity
        }
        var attributes = query(expected); attributes[kSecReturnRef as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess, let result {
            let identity = result as! SecIdentity
            if fingerprint(of: identity) == expected { return found(identity) }
        }
        // Identity labels are not a reliable identity index across PKCS#12 imports/updates.
        // Match the actual certificate, without depending on its Keychain label.
        let all: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecReturnRef as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var matches: CFTypeRef?
        if SecItemCopyMatching(all as CFDictionary, &matches) == errSecSuccess, let identities = matches as? [SecIdentity],
           let identity = identities.first(where: { fingerprint(of: $0) == expected }) { return found(identity) }
        // The encrypted setup package itself is retained only in this device's Keychain.
        // Recreate a missing identity reference after an update if its package is still accessible.
        if let bootstrap = setup?.bootstrap, let data = Data(base64Encoded: bootstrap.p12),
           let identity = try? importIdentity(data, password: bootstrap.password), fingerprint(of: identity) == expected { return identity }
        return nil
    }
    static func install(_ bootstrap: UHDBootstrap) throws {
        guard let data = Data(base64Encoded: bootstrap.p12), data.count < 131072,
              !bootstrap.userAgent.isEmpty, bootstrap.userAgent.count < 2048,
              !bootstrap.userAgent.contains("\n"), !bootstrap.userAgent.contains("\r") else { throw BBCError.message("Invalid UHD setup data.") }
        let identity = try importIdentity(data, password: bootstrap.password)
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { throw BBCError.message("UHD identity has no certificate.") }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        var attributes = query(fingerprint); attributes[kSecValueRef as String] = identity
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw BBCError.message("Could not store the UHD identity in Keychain (\(status)).") }
        let old = storedSetup()?.fingerprint ?? UserDefaults.standard.string(forKey: fingerprintKey)
        // Keep the import package and its metadata together in protected, device-only Keychain storage.
        try saveSetup(StoredSetup(fingerprint: fingerprint, userAgent: bootstrap.userAgent, bootstrap: bootstrap))
        UserDefaults.standard.set(fingerprint, forKey: fingerprintKey); UserDefaults.standard.set(bootstrap.userAgent, forKey: agentKey)
        guard self.identity() != nil else { throw BBCError.message("The imported UHD identity could not be read back from Keychain.") }
        if let old, old != fingerprint { SecItemDelete(query(old) as CFDictionary) }
    }
    static func remove() {
        if let fingerprint = storedSetup()?.fingerprint ?? UserDefaults.standard.string(forKey: fingerprintKey) { SecItemDelete(query(fingerprint) as CFDictionary) }
        SecItemDelete(setupQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fingerprintKey); UserDefaults.standard.removeObject(forKey: agentKey)
    }
}
final class BBCSecureSession: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let identity: SecIdentity
    private let agent: String
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    init(identity: SecIdentity, userAgent: String) { self.identity = identity; agent = userAgent }
    static func configured() throws -> BBCSecureSession {
        guard let identity = UHDIdentityVault.identity(), !UHDIdentityVault.userAgent.isEmpty else { throw BBCError.message("Choose Enable BBC UHD in Settings to set up UHD playback.") }
        return BBCSecureSession(identity: identity, userAgent: UHDIdentityVault.userAgent)
    }
    func fetch(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host == "securegate.iplayer.bbc.co.uk" else { throw BBCError.message("Unexpected UHD authentication destination.") }
        var request = URLRequest(url: url); request.timeoutInterval = 25; request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw BBCError.message("BBC could not authorise the UHD request. The episode may be unavailable or the configured identity may no longer be accepted.") }
        return data
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            guard challenge.protectionSpace.host == "securegate.iplayer.bbc.co.uk", challenge.previousFailureCount == 0 else { completionHandler(.cancelAuthenticationChallenge, nil); return }
            completionHandler(.useCredential, URLCredential(identity: identity, certificates: nil, persistence: .forSession))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
    func invalidate() { session.invalidateAndCancel() }
}
final class UHDProvisioningClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    private let fingerprint: String
    private let token: String
    private let endpoint: URL
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    init(link: String) throws {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), components.scheme == "https", let host = components.host,
              components.path == "/identity", let fragment = components.fragment else { throw BBCError.message("Paste the complete setup URL printed on your Mac.") }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        let local = octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } && (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
        guard local, components.port != nil else { throw BBCError.message("The setup URL must point to your Mac on the local network.") }
        let fields = URLComponents(string: "https://setup.invalid/?" + fragment)?.queryItems ?? []
        guard let pin = fields.first(where: { $0.name == "fp" })?.value, pin.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let token = fields.first(where: { $0.name == "token" })?.value, token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw BBCError.message("The setup URL is missing its pairing code or certificate fingerprint.") }
        var clean = components; clean.fragment = nil; clean.query = nil; clean.user = nil; clean.password = nil
        self.host = host; fingerprint = pin; self.token = token; endpoint = clean.url!
    }
    func retrieve() async throws -> UHDBootstrap {
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint); request.timeoutInterval = 25; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 131072 else { throw BBCError.message("Setup failed or the one-time link has expired. Run the setup helper again.") }
        return try JSONDecoder().decode(UHDBootstrap.self, from: data)
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let actual = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard actual == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
