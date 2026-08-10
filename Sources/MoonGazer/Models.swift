import Foundation

enum Provider: String {
    case claude = "CLAUDE"
    case codex = "CODEX"
}

/// One metered rate-limit window (5h session, 7d weekly, per-model, …).
struct RateWindow: Identifiable, Equatable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    var windowSeconds: Int? = nil   // full window length, for time-pace comparison

    /// Fraction (0…1) of this window's time that has elapsed, if computable.
    func paceFraction(now: Date) -> Double? {
        guard let resetsAt, let windowSeconds, windowSeconds > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        let elapsed = Double(windowSeconds) - remaining
        return min(max(elapsed / Double(windowSeconds), 0), 1)
    }

    /// Usage relative to the linear time pace. Positive = burning faster than time.
    func paceDelta(now: Date) -> Double? {
        guard let fraction = paceFraction(now: now) else { return nil }
        return usedPercent - fraction * 100
    }

    var isSessionWindow: Bool { (windowSeconds ?? Int.max) < 21_600 }
}

/// Pay-as-you-go / credits info, shown as a single footer line.
struct ExtraUsage: Equatable {
    let text: String
}

struct ProviderSnapshot: Equatable {
    var provider: Provider
    var plan: String? = nil
    var account: String? = nil
    var primary: RateWindow? = nil
    var secondary: RateWindow? = nil
    var extraWindows: [RateWindow] = []
    var extra: ExtraUsage? = nil
    var fetchedAt: Date? = nil
    var error: String? = nil

    static func failed(_ provider: Provider, _ message: String) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, plan: nil, account: nil,
                         primary: nil, secondary: nil, extraWindows: [],
                         extra: nil, fetchedAt: nil, error: message)
    }
}

enum TaskState: Equatable {
    case working      // process running, transcript active recently
    case idle         // process running, waiting for input
    case finished     // process gone, transcript recently modified
}

struct AgentTask: Identifiable, Equatable {
    let id: String
    let name: String          // project folder basename
    let state: TaskState
    let detail: String        // "12m" elapsed, or "done 5m ago"
}

func shortDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
}

func parseISODate(_ isoString: String?) -> Date? {
    guard let isoString else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: isoString) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: isoString)
}
