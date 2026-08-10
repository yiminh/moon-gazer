import Foundation

struct OMLXSnapshot: Equatable {
    var configured: Bool = false
    var host: String? = nil
    var gpuPercent: Double? = nil
    var memUsedGB: Double? = nil
    var memTotalGB: Double? = nil
    var memPercent: Double? = nil
    var model: String? = nil
    var ppTps: Double? = nil   // prompt processing tokens/sec
    var tgTps: Double? = nil   // text generation tokens/sec
    var fetchedAt: Date? = nil
    var error: String? = nil

    static let unconfigured = OMLXSnapshot(configured: false)
    static func failed(_ message: String) -> OMLXSnapshot {
        OMLXSnapshot(configured: true, error: message)
    }
}

/// Polls an omlx-agent metrics endpoint (see agent/omlx-agent.py) for the GPU and
/// memory usage of another machine on the LAN. The URL is resolved from, in order:
///   1. the MOONGAZER_OMLX_URL environment variable
///   2. ~/.config/moongazer/config.json  →  { "omlxUrl": "http://host:8082/metrics" }
/// When no URL is set the pane is hidden.
final class OMLXService {
    let url: URL?
    /// Optional display name that overrides the host the agent reports (which can be
    /// an ugly munged system hostname). From MOONGAZER_OMLX_LABEL or config `omlxLabel`.
    let label: String?

    init() {
        let config = Self.loadConfig()
        self.url = Self.resolveURL(config)
        self.label = Self.resolveLabel(config)
    }

    var isConfigured: Bool { url != nil }

    private static func loadConfig() -> [String: Any] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moongazer/config.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    static func resolveURL(_ config: [String: Any]) -> URL? {
        if let env = ProcessInfo.processInfo.environment["MOONGAZER_OMLX_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty,
           let url = URL(string: env) {
            return url
        }
        guard
            let raw = (config["omlxUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty, let url = URL(string: raw)
        else { return nil }
        return url
    }

    static func resolveLabel(_ config: [String: Any]) -> String? {
        if let env = ProcessInfo.processInfo.environment["MOONGAZER_OMLX_LABEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        let raw = (config["omlxLabel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty ?? true) ? nil : raw
    }

    func fetch() async -> OMLXSnapshot {
        guard let url else { return .unconfigured }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failed("HTTP \(status)") }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed("Invalid JSON")
            }
            func dbl(_ key: String) -> Double? {
                switch json[key] {
                case let n as Double: return n
                case let n as Int: return Double(n)
                default: return nil
                }
            }
            return OMLXSnapshot(
                configured: true,
                host: label ?? (json["host"] as? String),
                gpuPercent: dbl("gpu"),
                memUsedGB: dbl("mem_used_gb"),
                memTotalGB: dbl("mem_total_gb"),
                memPercent: dbl("mem_pct"),
                model: json["model"] as? String,
                ppTps: dbl("pp_tps"),
                tgTps: dbl("tg_tps"),
                fetchedAt: Date(),
                error: nil)
        } catch {
            return .failed("unreachable")
        }
    }
}
