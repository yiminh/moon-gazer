import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.07)
    static let panel = Color.white.opacity(0.03)
    static let divider = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.34)
    static let claudeAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codexAccent = Color(red: 0.06, green: 0.64, blue: 0.50)
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.25)
    static let red = Color(red: 0.94, green: 0.35, blue: 0.30)
    static let green = Color(red: 0.30, green: 0.78, blue: 0.45)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func barColor(_ percent: Double, accent: Color) -> Color {
        if percent >= 90 { return red }
        if percent >= 70 { return amber }
        return accent
    }
}

/// The fixed 960×540 design canvas, scaled to fill whatever size the window is
/// (so full-screen on the dedicated display fills edge to edge, cleanly).
struct DashboardView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 960, geo.size.height / 540)
            canvas
                .frame(width: 960, height: 540)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private var canvas: some View {
        HStack(spacing: 0) {
            ProviderColumn(snapshot: store.claude, tasks: store.claudeTasks,
                           accent: Theme.claudeAccent, now: store.now, showPace: store.showPace)
            Rectangle().fill(Theme.divider).frame(width: 1)
            ProviderColumn(snapshot: store.codex, tasks: store.codexTasks,
                           accent: Theme.codexAccent, now: store.now, showPace: store.showPace)
        }
        .frame(width: 960, height: 540)
        .background(Theme.background)
    }
}

struct ProviderColumn: View {
    let snapshot: ProviderSnapshot
    let tasks: [AgentTask]
    let accent: Color
    let now: Date
    let showPace: Bool

    /// True when no window shorter than 6h is present (Codex idle → weekly only).
    private var missingSession: Bool {
        let all = [snapshot.primary, snapshot.secondary].compactMap { $0 } + snapshot.extraWindows
        return !all.contains { $0.isSessionWindow }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 20)

            if let primary = snapshot.primary {
                BigWindowView(window: primary, accent: accent, now: now, showPace: showPace)
                Spacer().frame(height: 18)
            }
            // Session (5h) row directly under the weekly hero — or a placeholder when
            // the provider isn't currently reporting a session window (e.g. idle Codex).
            if let secondary = snapshot.secondary {
                SmallWindowView(window: secondary, accent: accent, now: now, showPace: showPace)
            } else if snapshot.primary != nil, missingSession {
                placeholderRow
            }
            ForEach(snapshot.extraWindows) { window in
                Spacer().frame(height: 12)
                SmallWindowView(window: window, accent: accent, now: now, showPace: showPace)
            }
            if let extra = snapshot.extra {
                Spacer().frame(height: 14)
                Text(extra.text).font(Theme.mono(14)).foregroundColor(Theme.textSecondary)
            }
            if snapshot.primary == nil, let error = snapshot.error {
                errorState(error)
            }

            Spacer().frame(height: 22)
            Rectangle().fill(Theme.divider).frame(height: 1)
            Spacer().frame(height: 14)
            taskSection
            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(snapshot.provider.rawValue)
                    .font(Theme.mono(18, .semibold))
                    .tracking(4)
                    .foregroundColor(accent)
                if let plan = snapshot.plan {
                    Text(plan.uppercased())
                        .font(Theme.mono(11, .semibold))
                        .tracking(1)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
                }
                Spacer()
                overallStatus
            }
            if let account = snapshot.account {
                Text(account).font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
            }
        }
    }

    private var overallStatus: some View {
        let working = tasks.filter { $0.state == .working }.count
        let idle = tasks.filter { $0.state == .idle }.count
        let text: String
        let color: Color
        if working > 0 { text = "WORKING ×\(working)"; color = Theme.green }
        else if idle > 0 { text = "IDLE ×\(idle)"; color = Theme.amber }
        else { text = "QUIET"; color = Theme.textTertiary }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(Theme.mono(12, .medium)).foregroundColor(color)
        }
    }

    private var placeholderRow: some View {
        HStack {
            Text("Session 5h").font(Theme.mono(14, .medium)).foregroundColor(Theme.textTertiary)
            Spacer()
            Text("no active window").font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
        }
        .opacity(0.7)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TASKS").font(Theme.mono(12, .semibold)).tracking(2).foregroundColor(Theme.textTertiary)
            if tasks.isEmpty {
                Text("no recent activity").font(Theme.mono(13)).foregroundColor(Theme.textTertiary)
            } else {
                ForEach(tasks.prefix(6)) { TaskRow(task: $0, accent: accent) }
                if tasks.count > 6 {
                    Text("+ \(tasks.count - 6) more").font(Theme.mono(13)).foregroundColor(Theme.textTertiary)
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 30)
            Text("--").font(Theme.mono(48, .light)).foregroundColor(Theme.textTertiary)
            Text(message).font(Theme.mono(13)).foregroundColor(Theme.amber).lineLimit(3)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetchedAt = snapshot.fetchedAt {
                let stale = now.timeIntervalSince(fetchedAt) > 660
                Text("updated \(timeString(fetchedAt))\(stale ? " (stale)" : "")")
                    .font(Theme.mono(11)).foregroundColor(stale ? Theme.amber : Theme.textTertiary)
            }
            if snapshot.fetchedAt != nil, let error = snapshot.error {
                Text("⚠ \(error)").font(Theme.mono(11)).foregroundColor(Theme.amber).lineLimit(1)
            }
            Spacer()
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct BigWindowView: View {
    let window: RateWindow
    let accent: Color
    let now: Date
    let showPace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(Int(window.usedPercent.rounded()))")
                    .font(Theme.mono(58, .light)).foregroundColor(Theme.textPrimary)
                Text("%").font(Theme.mono(24, .light)).foregroundColor(Theme.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(window.label).font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                    if let resets = window.resetsAt { ResetText(resets: resets, now: now) }
                }
            }
            ProgressBar(percent: window.usedPercent, accent: accent, height: 9,
                        pace: showPace ? window.paceFraction(now: now) : nil)
            if showPace {
                paceCaption(window, now: now)
            }
        }
    }
}

struct SmallWindowView: View {
    let window: RateWindow
    let accent: Color
    let now: Date
    let showPace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label).font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                Spacer()
                if let resets = window.resetsAt { ResetText(resets: resets, now: now) }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(Theme.mono(15, .medium)).foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 46, alignment: .trailing)
            }
            ProgressBar(percent: window.usedPercent, accent: accent, height: 6,
                        pace: showPace ? window.paceFraction(now: now) : nil)
            if showPace {
                paceCaption(window, now: now)
            }
        }
    }
}

/// "▲ n% over pace" (amber/red) or "▼ n% under pace" (green) or "● on pace".
@ViewBuilder
func paceCaption(_ window: RateWindow, now: Date) -> some View {
    if let delta = window.paceDelta(now: now) {
        let rounded = Int(delta.rounded())
        if delta > 8 {
            Text("▲ \(rounded)% over pace")
                .font(Theme.mono(12, .medium))
                .foregroundColor(delta > 18 ? Theme.red : Theme.amber)
        } else if delta < -8 {
            Text("▼ \(-rounded)% under pace")
                .font(Theme.mono(12, .medium)).foregroundColor(Theme.green)
        } else {
            Text("● on pace").font(Theme.mono(12, .medium)).foregroundColor(Theme.textTertiary)
        }
    }
}

struct ResetText: View {
    let resets: Date
    let now: Date
    var body: some View {
        let remaining = resets.timeIntervalSince(now)
        Text(remaining > 0 ? "resets in \(shortDuration(remaining))" : "resetting…")
            .font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
    }
}

/// Usage bar with an optional time-pace tick: a vertical marker at the fraction
/// of the window's time that has elapsed. Usage bar past the tick = burning
/// faster than the clock; short of it = you have headroom.
struct ProgressBar: View {
    let percent: Double
    let accent: Color
    let height: CGFloat
    var pace: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(Theme.barColor(percent, accent: accent))
                    .frame(width: max(height, geo.size.width * min(percent, 100) / 100))
                if let pace {
                    // Flush with the bar height, centered on the elapsed-time fraction.
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: height)
                        .offset(x: geo.size.width * min(max(pace, 0), 1) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

struct TaskRow: View {
    let task: AgentTask
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            switch task.state {
            case .working:
                Circle().fill(Theme.green).frame(width: 7, height: 7)
            case .idle:
                Circle().stroke(Theme.amber, lineWidth: 1.3).frame(width: 7, height: 7)
            case .finished:
                Text("✓").font(Theme.mono(11, .bold)).foregroundColor(Theme.textTertiary).frame(width: 7)
            }
            Text(task.name)
                .font(Theme.mono(14, task.state == .finished ? .regular : .medium))
                .foregroundColor(task.state == .finished ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(task.detail).font(Theme.mono(13)).foregroundColor(Theme.textTertiary)
        }
    }
}
