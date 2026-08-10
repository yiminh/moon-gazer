import Foundation

/// Fetches Claude quota/usage by reusing the Claude Code CLI's OAuth credentials.
/// Credential ladder: ~/.claude/.credentials.json → Keychain (via /usr/bin/security,
/// which is whitelisted on the item's ACL so no prompt) → CLAUDE_CODE_OAUTH_TOKEN.
final class ClaudeService {
    private struct Credentials {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Double?      // ms epoch
        var subscriptionType: String?
        var clientID: String?       // per-credential OAuth client id (Electron entries carry their own)
        var source: Source
        var fullData: [String: Any]

        enum Source { case file, keychain, electron, environment }
    }

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let keychainService = "Claude Code-credentials"
    private static let refreshBufferMs: Double = 5 * 60 * 1000

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var credentialsFileURL: URL { home.appendingPathComponent(".claude/.credentials.json") }

    func fetch() async -> ProviderSnapshot {
        do {
            guard var credentials = loadCredentials() else {
                return .failed(.claude, "Not signed in — run `claude` and log in")
            }

            // The Electron (Claude Desktop) source is read-only: refreshing would
            // rotate a token Claude Desktop owns and could log the user out of it.
            let mayRefresh = credentials.refreshToken != nil
                && credentials.source != .environment
                && credentials.source != .electron

            if needsRefresh(credentials) {
                if mayRefresh {
                    credentials = try await refresh(credentials)
                } else if credentials.source == .electron {
                    return .failed(.claude, "Claude Desktop session expired — open Claude Desktop, or run `claude` to log in")
                }
            }

            var (data, status) = try await requestUsage(token: credentials.accessToken)
            if (status == 401 || status == 403) {
                if mayRefresh {
                    credentials = try await refresh(credentials)
                    (data, status) = try await requestUsage(token: credentials.accessToken)
                } else if credentials.source == .electron {
                    return .failed(.claude, "Claude Desktop token can't read usage — run `claude` to log in")
                }
            }
            guard status == 200 else {
                return .failed(.claude, "Usage endpoint HTTP \(status)")
            }
            return parse(data, credentials: credentials)
        } catch {
            return .failed(.claude, error.localizedDescription)
        }
    }

    // MARK: - Credentials

    private func loadCredentials() -> Credentials? {
        if let fromFile = loadFromJSON(try? Data(contentsOf: credentialsFileURL), source: .file) {
            return fromFile
        }
        if let output = try? ProcessRunner.runSync(
            "/usr/bin/security", ["find-generic-password", "-s", Self.keychainService, "-w"], timeout: 5),
           let fromKeychain = loadFromJSON(output.data(using: .utf8), source: .keychain) {
            return fromKeychain
        }
        if let entry = ClaudeElectronToken.load() {
            return Credentials(
                accessToken: entry.accessToken,
                refreshToken: entry.refreshToken,
                expiresAt: entry.expiresAt,
                subscriptionType: entry.subscriptionType,
                clientID: entry.clientID,
                source: .electron,
                fullData: [:])
        }
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return Credentials(accessToken: token, refreshToken: nil, expiresAt: nil,
                               subscriptionType: nil, source: .environment, fullData: [:])
        }
        return nil
    }

    private func loadFromJSON(_ data: Data?, source: Credentials.Source) -> Credentials? {
        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return makeCredentials(from: oauth, source: source, fullData: root)
    }

    private func makeCredentials(from oauth: [String: Any], source: Credentials.Source,
                                 fullData: [String: Any] = [:]) -> Credentials? {
        guard let rawToken = oauth["accessToken"] as? String else { return nil }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        var expiresAt: Double?
        switch oauth["expiresAt"] {
        case let n as Double: expiresAt = n
        case let n as Int: expiresAt = Double(n)
        case let s as String: expiresAt = Double(s)
        default: break
        }

        return Credentials(
            accessToken: token,
            refreshToken: (oauth["refreshToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            clientID: nil,
            source: source,
            fullData: fullData
        )
    }

    private func needsRefresh(_ credentials: Credentials) -> Bool {
        guard let expiresAt = credentials.expiresAt else { return false }
        return Date().timeIntervalSince1970 * 1000 + Self.refreshBufferMs >= expiresAt
    }

    private func refresh(_ credentials: Credentials) async throws -> Credentials {
        guard let refreshToken = credentials.refreshToken else { return credentials }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": credentials.clientID ?? Self.clientID,
            "scope": "user:profile user:inference user:sessions:claude_code",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty
        else {
            throw ProcessRunnerError.terminated(1, "Claude session expired — run `claude` and log in again")
        }

        var updated = credentials
        updated.accessToken = accessToken
        if let newRefresh = json["refresh_token"] as? String { updated.refreshToken = newRefresh }
        if let expiresIn = json["expires_in"] as? Int {
            updated.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }
        save(updated)
        return updated
    }

    /// Writes refreshed tokens back to where they came from so the CLI stays in sync.
    private func save(_ credentials: Credentials) {
        var root = credentials.fullData
        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = credentials.accessToken
        if let r = credentials.refreshToken { oauth["refreshToken"] = r }
        if let e = credentials.expiresAt { oauth["expiresAt"] = e }
        root["claudeAiOauth"] = oauth

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }

        switch credentials.source {
        case .file:
            try? data.write(to: credentialsFileURL, options: .atomic)
        case .keychain:
            guard let json = String(data: data, encoding: .utf8) else { return }
            _ = try? ProcessRunner.runSync("/usr/bin/security",
                ["delete-generic-password", "-s", Self.keychainService], timeout: 5)
            _ = try? ProcessRunner.runSync("/usr/bin/security",
                ["add-generic-password", "-s", Self.keychainService, "-w", json], timeout: 5)
        case .electron, .environment:
            break   // Claude Desktop / env tokens are owned elsewhere; don't write back.
        }
    }

    // MARK: - Usage

    private func requestUsage(token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: Self.usageURL)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.32", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func parse(_ data: Data, credentials: Credentials) -> ProviderSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(.claude, "Invalid usage JSON")
        }

        func window(_ key: String, label: String, seconds: Int) -> RateWindow? {
            guard let w = json[key] as? [String: Any] else { return nil }
            let percent = (w["utilization"] as? Double) ?? Double(w["utilization"] as? Int ?? 0)
            return RateWindow(id: key, label: label, usedPercent: percent,
                              resetsAt: parseISODate(w["resets_at"] as? String),
                              windowSeconds: seconds)
        }

        // Per-model weekly windows arrive as seven_day_<model> keys.
        var extraWindows: [RateWindow] = []
        for key in json.keys.sorted() where key.hasPrefix("seven_day_") {
            let model = key.replacingOccurrences(of: "seven_day_", with: "").capitalized
            if let w = window(key, label: "\(model) 7d", seconds: 604_800) { extraWindows.append(w) }
        }

        var extra: ExtraUsage?
        if let e = json["extra_usage"] as? [String: Any], (e["is_enabled"] as? Bool) == true {
            let used = ((e["used_credits"] as? Double) ?? 0) / 100
            let limit = ((e["monthly_limit"] as? Double) ?? Double(e["monthly_limit"] as? Int ?? 0)) / 100
            extra = ExtraUsage(text: String(format: "Extra $%.2f / $%.0f", used, limit))
        }

        return ProviderSnapshot(
            provider: .claude,
            plan: planLabel(credentials.subscriptionType),
            account: accountEmail(),
            // Weekly is the hero (unified with Codex); session is the secondary row.
            primary: window("seven_day", label: "Weekly 7d", seconds: 604_800),
            secondary: window("five_hour", label: "Session 5h", seconds: 18_000),
            extraWindows: extraWindows,
            extra: extra,
            fetchedAt: Date(),
            error: nil
        )
    }

    private func planLabel(_ raw: String?) -> String? {
        switch raw?.lowercased() {
        case "claude_max", "max": return "Max"
        case "claude_pro", "pro": return "Pro"
        case "api", "claude_api": return "API"
        default: return raw
        }
    }

    private func accountEmail() -> String? {
        let configURL = home.appendingPathComponent(".claude.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = json["oauthAccount"] as? [String: Any]
        else { return nil }
        return account["emailAddress"] as? String
    }
}
