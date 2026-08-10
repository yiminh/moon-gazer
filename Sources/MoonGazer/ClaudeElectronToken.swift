import Foundation
import CommonCrypto

/// Reads Claude Desktop's OAuth token from its Electron `safeStorage` config.
/// `~/Library/Application Support/Claude/config.json` → `oauth:tokenCache` /
/// `oauth:tokenCacheV2` is a base64 "v10" + AES-128-CBC blob. The key is
/// PBKDF2(password, "saltysalt", 1003, SHA1, 16) where password is the Keychain
/// generic-password item service="Claude Safe Storage" — read via /usr/bin/security
/// (a Keychain-ACL-trusted caller, so no prompt). IV is 16 spaces.
///
/// The decrypted payload is a map keyed by "<clientId>:<orgId>:<url>:<scopes>",
/// each value = {token, refreshToken, expiresAt(ms), subscriptionType, rateLimitTier}.
/// We pick the newest entry that carries `user:inference` scope.
enum ClaudeElectronToken {
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    private static let v10 = Data([0x76, 0x31, 0x30])

    struct Entry {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Double?      // ms epoch
        let subscriptionType: String?
        let clientID: String?
    }

    private static var configPath: String {
        let home: String
        if let pw = getpwuid(getuid()) { home = String(cString: pw.pointee.pw_dir) }
        else { home = NSHomeDirectory() }
        return home + "/Library/Application Support/Claude/config.json"
    }

    static func load() -> Entry? {
        guard
            let data = FileManager.default.contents(atPath: configPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let encrypted = (json["oauth:tokenCache"] as? String)
            ?? (json["oauth:tokenCacheV2"] as? String)
        guard let encrypted, !encrypted.isEmpty,
              let key = deriveKey(),
              let plaintext = decrypt(encrypted, key: key),
              let payload = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any]
        else { return nil }

        return bestEntry(from: payload)
    }

    /// The public OAuth client id Claude Code uses; the /api/oauth/usage endpoint
    /// is scoped to it, so prefer entries issued to this client.
    private static let claudeCodeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Choose the best OAuth entry for reading usage. The endpoint needs the
    /// `user:sessions:claude_code` scope and is tied to the Claude Code client id.
    /// This path is read-only (we never refresh Claude Desktop's token — it owns
    /// that), so a still-valid token is strongly preferred over an expired one.
    /// Rank by (not-expired, has-claude_code-scope, is-claude-code-client, newest).
    private static func bestEntry(from payload: [String: Any]) -> Entry? {
        let nowMs = Date().timeIntervalSince1970 * 1000
        var ranked: [(entry: Entry, valid: Bool, codeScope: Bool, codeClient: Bool)] = []
        for (compositeKey, value) in payload {
            guard let entry = value as? [String: Any] else { continue }
            let token = (entry["token"] as? String) ?? (entry["accessToken"] as? String)
            guard let token, !token.isEmpty else { continue }
            guard compositeKey.contains("user:inference") else { continue }

            let expiresAt = doubleValue(entry["expiresAt"])
            let clientID = compositeKey.split(separator: ":").first.map(String.init)
            ranked.append((
                Entry(
                    accessToken: token,
                    refreshToken: entry["refreshToken"] as? String,
                    expiresAt: expiresAt,
                    subscriptionType: entry["subscriptionType"] as? String,
                    clientID: clientID),
                (expiresAt ?? 0) > nowMs,
                compositeKey.contains("user:sessions:claude_code"),
                clientID == claudeCodeClientID))
        }
        return ranked.sorted { lhs, rhs in
            if lhs.valid != rhs.valid { return lhs.valid }
            if lhs.codeScope != rhs.codeScope { return lhs.codeScope }
            if lhs.codeClient != rhs.codeClient { return lhs.codeClient }
            return (lhs.entry.expiresAt ?? 0) > (rhs.entry.expiresAt ?? 0)
        }.first?.entry
    }

    private static func doubleValue(_ v: Any?) -> Double? {
        switch v {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func deriveKey() -> Data? {
        guard let password = try? ProcessRunner.runSync(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Claude Safe Storage", "-w"], timeout: 5)
            .trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
        else { return nil }

        var derived = [UInt8](repeating: 0, count: keyLength)
        let saltBytes = Array("saltysalt".utf8)
        let passwordBytes = Array(password.utf8)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            iterations,
            &derived, keyLength)
        return status == kCCSuccess ? Data(derived) : nil
    }

    private static func decrypt(_ base64: String, key: Data) -> Data? {
        guard let raw = Data(base64Encoded: base64), raw.prefix(3) == v10 else { return nil }
        let ciphertext = raw.dropFirst(3)
        guard ciphertext.count >= kCCBlockSizeAES128 else { return nil }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var outLength = 0
        let status = ciphertext.withUnsafeBytes { ctPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, keyLength,
                        ivPtr.baseAddress,
                        ctPtr.baseAddress, ciphertext.count,
                        &out, out.count, &outLength)
                }
            }
        }
        return status == kCCSuccess ? Data(out.prefix(outLength)) : nil
    }
}
