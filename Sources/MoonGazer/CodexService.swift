import Foundation

/// Fetches Codex quota/usage by reusing the Codex CLI's OAuth tokens (~/.codex/auth.json).
/// Refreshed access tokens are kept in memory only — auth.json stays CLI-owned.
final class CodexService {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private var authPath: String {
        (ProcessInfo.processInfo.environment["CODEX_HOME"].map { "\($0)/auth.json" })
            ?? (NSString(string: "~/.codex/auth.json").expandingTildeInPath)
    }
    private var accessToken = ""
    private var refreshToken = ""

    func fetch() async -> ProviderSnapshot {
        guard loadAuth() else {
            return .failed(.codex, "Not signed in — run `codex login`")
        }
        do {
            var (data, status) = try await requestUsage()
            if status == 401 {
                guard try await refresh() else {
                    return .failed(.codex, "Sign-in expired — run `codex login`")
                }
                (data, status) = try await requestUsage()
            }
            guard status == 200 else {
                return .failed(.codex, "Usage endpoint HTTP \(status)")
            }
            return parse(data)
        } catch {
            return .failed(.codex, error.localizedDescription)
        }
    }

    private func loadAuth() -> Bool {
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String, !access.isEmpty
        else { return false }
        // Keep an in-memory refreshed token if we already have one for this auth file.
        if accessToken.isEmpty || refreshToken != (tokens["refresh_token"] as? String ?? "") {
            accessToken = access
            refreshToken = (tokens["refresh_token"] as? String) ?? ""
        }
        return true
    }

    private func requestUsage() async throws -> (Data, Int) {
        var request = URLRequest(url: Self.usageURL)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func refresh() async throws -> Bool {
        guard !refreshToken.isEmpty else { return false }
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String
        else { return false }
        accessToken = access
        if let newRefresh = json["refresh_token"] as? String { refreshToken = newRefresh }
        return true
    }

    private func parse(_ data: Data) -> ProviderSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(.codex, "Invalid usage JSON")
        }

        func windowLabel(_ seconds: Int) -> String {
            switch seconds {
            case ..<21_600: return "Session \(max(1, seconds / 3600))h"
            case ..<172_800: return "Daily 24h"
            case ..<1_209_600: return "Weekly 7d"
            default: return "Limit \(seconds / 86_400)d"
            }
        }

        func window(_ raw: [String: Any]?, id: String, name: String? = nil) -> RateWindow? {
            guard let raw else { return nil }
            let percent: Double
            if let p = raw["used_percent"] as? Double { percent = p }
            else if let p = raw["used_percent"] as? Int { percent = Double(p) }
            else { return nil }
            let seconds = (raw["limit_window_seconds"] as? Int) ?? 0
            var resets: Date?
            if let ts = raw["reset_at"] as? Double { resets = Date(timeIntervalSince1970: ts) }
            else if let ts = raw["reset_at"] as? Int { resets = Date(timeIntervalSince1970: TimeInterval(ts)) }
            let label = name.map { "\($0) \(windowLabel(seconds))" } ?? windowLabel(seconds)
            return RateWindow(id: id, label: label, usedPercent: percent, resetsAt: resets,
                              windowSeconds: seconds > 0 ? seconds : nil)
        }

        let rateLimit = json["rate_limit"] as? [String: Any]
        let primary = window(rateLimit?["primary_window"] as? [String: Any], id: "primary")
        let secondary = window(rateLimit?["secondary_window"] as? [String: Any], id: "secondary")

        var extraWindows: [RateWindow] = []
        if let additional = json["additional_rate_limits"] as? [[String: Any]] {
            for (index, entry) in additional.enumerated() {
                guard let name = entry["limit_name"] as? String else { continue }
                let rl = entry["rate_limit"] as? [String: Any]
                if let w = window(rl?["primary_window"] as? [String: Any], id: "extra-\(index)", name: name) {
                    extraWindows.append(w)
                }
            }
        }

        var extra: ExtraUsage?
        if let credits = json["credits"] as? [String: Any] {
            if (credits["unlimited"] as? Bool) == true {
                extra = ExtraUsage(text: "Credits: unlimited")
            } else {
                let balance = (credits["balance"] as? String).flatMap(Int.init)
                    ?? (credits["balance"] as? Int) ?? 0
                if balance > 0 || (credits["has_credits"] as? Bool) == true {
                    extra = ExtraUsage(text: "Credits: \(balance)")
                }
            }
        }

        let planRaw = (json["plan_type"] as? String) ?? ""
        return ProviderSnapshot(
            provider: .codex,
            plan: planRaw.isEmpty ? nil : planRaw.capitalized,
            account: accountEmail(),
            primary: primary,
            secondary: secondary,
            extraWindows: extraWindows,
            extra: extra,
            fetchedAt: Date(),
            error: nil
        )
    }

    private func accountEmail() -> String? {
        // The id_token in auth.json is a JWT whose payload carries the account email.
        guard
            let data = FileManager.default.contents(atPath: authPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String
        else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard
            let decoded = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
        else { return nil }
        return claims["email"] as? String
    }
}
