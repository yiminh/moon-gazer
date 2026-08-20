import SwiftUI

private struct BarColorModeKey: EnvironmentKey {
    static let defaultValue: BarColorMode = .accentRedHigh
}
extension EnvironmentValues {
    var barColorMode: BarColorMode {
        get { self[BarColorModeKey.self] }
        set { self[BarColorModeKey.self] = newValue }
    }
}

/// Dynamic theme facade backed by the live AppSettings (assigned once at launch).
/// Views observe `AppSettings`, so their bodies re-run on change and re-read these.
@MainActor
enum Theme {
    static var settings: AppSettings!

    private static var p: Palette { settings.palette }

    static var background: Color { p.bg }
    static var surface: Color { p.surface }
    static var divider: Color { p.divider }
    static var textPrimary: Color { p.textPrimary }
    static var textSecondary: Color { p.textSecondary }
    static var textTertiary: Color { p.textTertiary }
    static var claudeAccent: Color { p.claudeAccent }
    static var codexAccent: Color { p.codexAccent }
    static var omlxAccent: Color { p.omlxAccent }

    // Fixed status colours (pace direction / online dot) — intentionally not themable.
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.25)
    static let red = Color(red: 0.94, green: 0.35, blue: 0.30)
    static let green = Color(red: 0.30, green: 0.78, blue: 0.45)

    /// Body text font (respects the body-bold toggle by nudging the weight up).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        settings.bodyTypeface.font(size: size, weight: settings.bodyBold ? bolder(weight) : weight)
    }
    /// Big-number font (the hero digits); non-bold defaults to a light, elegant weight.
    static func num(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        settings.numberTypeface.font(size: size, weight: settings.numberBold ? .bold : weight)
    }
    private static func bolder(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight, .thin, .light, .regular, .medium: return .semibold
        case .semibold: return .bold
        default: return w
        }
    }

    static func barColor(_ percent: Double, accent: Color, mode: BarColorMode) -> Color {
        switch mode {
        case .accentRedHigh:
            return percent >= settings.dangerThreshold ? p.danger : accent
        case .ramp:
            if percent >= settings.dangerThreshold { return p.danger }
            if percent >= settings.warnThreshold { return p.warn }
            return accent
        case .accentOnly:
            return accent
        }
    }
}

/// The fixed 960×540 design canvas, scaled to fill whatever size the window is
/// (so full-screen on the dedicated display fills edge to edge, cleanly).
struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 960, geo.size.height / 540)
            canvas
                .frame(width: 960, height: 540)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(settings.palette.bg)
        .environment(\.colorScheme, settings.effectiveDark ? .dark : .light)
        .ignoresSafeArea()
    }

    private var panes: [Pane] { settings.visiblePanes(omlxConfigured: store.omlxEnabled) }

    private var canvas: some View {
        let pal = settings.palette
        return HStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element) { index, pane in
                if index > 0 { Rectangle().fill(pal.divider).frame(width: 1) }
                paneView(pane, palette: pal)
            }
        }
        .frame(width: 960, height: 540)
        .background(pal.bg)
        .environment(\.barColorMode, settings.barColorMode)
    }

    @ViewBuilder
    private func paneView(_ pane: Pane, palette pal: Palette) -> some View {
        switch pane {
        case .claude:
            ProviderColumn(snapshot: store.claude, tasks: store.claudeTasks,
                           accent: pal.claudeAccent, now: store.now, showPace: settings.showPace)
        case .codex:
            ProviderColumn(snapshot: store.codex, tasks: store.codexTasks,
                           accent: pal.codexAccent, now: store.now, showPace: settings.showPace)
        case .omlx:
            OMLXColumn(snapshot: store.omlx, accent: pal.omlxAccent, now: store.now)
        }
    }
}

struct ProviderColumn: View {
    let snapshot: ProviderSnapshot
    let tasks: [AgentTask]
    let accent: Color
    let now: Date
    let showPace: Bool

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
            // Session (5h) then any model sub-quotas (e.g. "5.3-Spark"), rendered with
            // one rhythm so the second row lines up across columns regardless of which
            // kind it is. Session keeps its "resets in"; sub-quotas share the weekly
            // reset so they drop it but keep the pace bar/caption.
            let sessionRows = [snapshot.secondary].compactMap { $0 }
            let secondaryRows = sessionRows + snapshot.extraWindows
            ForEach(Array(secondaryRows.enumerated()), id: \.offset) { idx, window in
                if idx > 0 { Spacer().frame(height: 12) }
                SmallWindowView(window: window, accent: accent, now: now,
                                showPace: showPace, showReset: idx < sessionRows.count)
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
        if working > 0 { text = "WORKING"; color = Theme.green }
        else if idle > 0 { text = "IDLE"; color = Theme.amber }
        else { text = "QUIET"; color = Theme.textTertiary }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(Theme.mono(12, .medium)).foregroundColor(color).lineLimit(1)
        }
        .fixedSize()
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
                    .font(Theme.num(58)).foregroundColor(Theme.textPrimary)
                    .lineLimit(1).fixedSize()
                Text("%").font(Theme.num(24)).foregroundColor(Theme.textSecondary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(window.label).font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                    if let resets = window.resetsAt { ResetText(resets: resets, now: now) }
                }
                .fixedSize()
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
    var showReset: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(window.label).font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if showReset, let resets = window.resetsAt { ResetText(resets: resets, now: now) }
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
@MainActor @ViewBuilder
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
        Text(remaining > 0 ? "reset \(shortDuration(remaining))" : "resetting…")
            .font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
            .lineLimit(1).fixedSize()
    }
}

/// Usage bar with an optional time-pace tick: a vertical marker at the fraction
/// of the window's time that has elapsed. Usage bar past the tick = burning
/// faster than the clock; short of it = you have headroom.
struct ProgressBar: View {
    @Environment(\.barColorMode) private var barColorMode
    let percent: Double
    let accent: Color
    let height: CGFloat
    var pace: Double? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(Theme.barColor(percent, accent: accent, mode: barColorMode))
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

/// Third pane: GPU / memory of a remote machine served by omlx-agent.
struct OMLXColumn: View {
    let snapshot: OMLXSnapshot
    let accent: Color
    let now: Date

    private var online: Bool {
        snapshot.fetchedAt != nil && (snapshot.error == nil || now.timeIntervalSince(snapshot.fetchedAt!) < 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 20)

            if let gpu = snapshot.gpuPercent {
                gpuHero(gpu)
                Spacer().frame(height: 18)
                if let mem = snapshot.memPercent { memoryRow(mem) }
            } else if snapshot.fetchedAt == nil {
                offlineState
            } else {
                // Reachable but GPU unavailable (e.g. non-Apple-Silicon) — still show MEM.
                if let mem = snapshot.memPercent {
                    memoryRow(mem, big: true)
                }
                Text("GPU% unavailable on this host")
                    .font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
                    .padding(.top, 10)
            }

            if let model = snapshot.model, snapshot.fetchedAt != nil {
                Spacer().frame(height: 20)
                Rectangle().fill(Theme.divider).frame(height: 1)
                Spacer().frame(height: 14)
                VStack(alignment: .leading, spacing: 6) {
                    Text("MODEL").font(Theme.mono(11, .semibold)).tracking(2).foregroundColor(Theme.textTertiary)
                    // Leading accent dot mirrors the TASKS bullets so the model name
                    // lines up with the task names (same 7 + 10 indent).
                    HStack(spacing: 10) {
                        Circle().fill(accent).frame(width: 7, height: 7)
                        Text(model).font(Theme.mono(14, .medium)).foregroundColor(accent).lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("OMLX").font(Theme.mono(18, .semibold)).tracking(4).foregroundColor(accent)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(online ? Theme.green : Theme.red).frame(width: 8, height: 8)
                    Text(online ? "ONLINE" : "OFFLINE")
                        .font(Theme.mono(12, .medium))
                        .foregroundColor(online ? Theme.green : Theme.red)
                }
            }
            Text(snapshot.host ?? "local model host")
                .font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
        }
    }

    private func gpuHero(_ gpu: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            // Big number + a two-line right block that mirrors the providers'
            // "Weekly 7d" / "resets in …": here it's the device and GPU descriptor.
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("\(Int(gpu.rounded()))")
                    .font(Theme.num(58)).foregroundColor(Theme.textPrimary)
                    .lineLimit(1).fixedSize()
                Text("%").font(Theme.num(24)).foregroundColor(Theme.textSecondary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.deviceName).font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                    Text(Self.gpuLabel).font(Theme.mono(12)).foregroundColor(Theme.textTertiary)
                }
                .fixedSize()
            }
            ProgressBar(percent: gpu, accent: accent, height: 9)
            // PP/TG on one line, occupying the same slot as the providers' pace
            // caption so the row below (MEM) lines up across all three columns.
            throughputLine.font(Theme.mono(12, .medium))
        }
    }

    /// Device + GPU descriptor shown at the OMLX hero's label position (the
    /// providers show "Weekly 7d" / "resets in …" there). The agent reports only
    /// the hostname, so name the hardware here.
    static let deviceName = "M3 Ultra"
    static let gpuLabel = "60-CORE GPU"

    /// "PP <n> tok/s · TG <n> tok/s" — labels in accent, numbers white, sat where a
    /// provider's pace line sits. Idle sides read "idle".
    private var throughputLine: Text {
        Text("PP ").foregroundColor(accent) + tpsValue(snapshot.ppTps)
            + Text("  ·  ").foregroundColor(Theme.textTertiary)
            + Text("TG ").foregroundColor(accent) + tpsValue(snapshot.tgTps)
    }

    private func tpsValue(_ v: Double?) -> Text {
        guard let v, v > 0 else { return Text("idle").foregroundColor(Theme.textTertiary) }
        let f = NumberFormatter(); f.numberStyle = .decimal
        let n = f.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))"
        return Text(n).foregroundColor(Theme.textPrimary)
            + Text(" tok/s").foregroundColor(Theme.textTertiary)
    }

    private func memoryRow(_ mem: Double, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: big ? 9 : 6) {
            HStack(alignment: big ? .lastTextBaseline : .firstTextBaseline) {
                if big {
                    Text("\(Int(mem.rounded()))")
                        .font(Theme.num(58)).foregroundColor(Theme.textPrimary)
                    Text("%").font(Theme.num(24)).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("MEM").font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                } else {
                    Text("MEM").font(Theme.mono(14, .medium)).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(mem.rounded()))%")
                        .font(Theme.mono(15, .medium)).foregroundColor(Theme.textPrimary)
                        .frame(minWidth: 46, alignment: .trailing)
                }
            }
            ProgressBar(percent: mem, accent: accent, height: big ? 9 : 6)
            // GB detail below the bar, in the providers' pace-caption slot (same size
            // and the "on pace" grey) so it lines up with their second row.
            if let used = snapshot.memUsedGB, let total = snapshot.memTotalGB {
                Text(String(format: "%.1f / %.0f GB", used, total))
                    .font(Theme.mono(12, .medium)).foregroundColor(Theme.textTertiary)
            }
        }
    }

    private var offlineState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 30)
            Text("--").font(Theme.mono(48, .light)).foregroundColor(Theme.textTertiary)
            Text(snapshot.error ?? "connecting…")
                .font(Theme.mono(13)).foregroundColor(Theme.amber)
            Text("start omlx-agent on the host")
                .font(Theme.mono(11)).foregroundColor(Theme.textTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetchedAt = snapshot.fetchedAt {
                let stale = now.timeIntervalSince(fetchedAt) > 30
                Text("updated \(timeString(fetchedAt))\(stale ? " (stale)" : "")")
                    .font(Theme.mono(11)).foregroundColor(stale ? Theme.amber : Theme.textTertiary)
            }
            if let error = snapshot.error, snapshot.fetchedAt != nil {
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
