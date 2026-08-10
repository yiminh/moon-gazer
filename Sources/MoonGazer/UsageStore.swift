import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderSnapshot(provider: .claude)
    @Published var codex = ProviderSnapshot(provider: .codex)
    @Published var claudeTasks: [AgentTask] = []
    @Published var codexTasks: [AgentTask] = []
    @Published var omlx = OMLXSnapshot.unconfigured
    @Published var now = Date()

    var omlxEnabled: Bool { omlxService.isConfigured }
    @Published var showPace: Bool = UserDefaults.standard.object(forKey: "showPace") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPace, forKey: "showPace") }
    }
    @Published var barColorMode: BarColorMode =
        UserDefaults.standard.string(forKey: "barColorMode").flatMap(BarColorMode.init) ?? .accentRedHigh {
        didSet { UserDefaults.standard.set(barColorMode.rawValue, forKey: "barColorMode") }
    }

    private let claudeService = ClaudeService()
    private let codexService = CodexService()
    private let sessionMonitor = SessionMonitor()
    private let omlxService = OMLXService()

    private var usageTimer: Timer?
    private var sessionTimer: Timer?
    private var omlxTimer: Timer?
    private var clockTimer: Timer?

    private let usageInterval: TimeInterval = 300
    private let sessionInterval: TimeInterval = 5
    private let omlxInterval: TimeInterval = 4

    func start() {
        refreshUsage()
        refreshSessions()
        refreshOMLX()

        usageTimer = Timer.scheduledTimer(withTimeInterval: usageInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSessions() }
        }
        if omlxService.isConfigured {
            omlxTimer = Timer.scheduledTimer(withTimeInterval: omlxInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshOMLX() }
            }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    func refreshUsage() {
        Task {
            let snapshot = await claudeService.fetch()
            // Keep last good data visible on transient failures; surface the error alongside.
            if snapshot.error != nil, claude.fetchedAt != nil {
                claude.error = snapshot.error
            } else {
                claude = snapshot
            }
        }
        Task {
            let snapshot = await codexService.fetch()
            if snapshot.error != nil, codex.fetchedAt != nil {
                codex.error = snapshot.error
            } else {
                codex = snapshot
            }
        }
    }

    func refreshOMLX() {
        guard omlxService.isConfigured else { return }
        Task {
            let snapshot = await omlxService.fetch()
            if snapshot.error != nil, omlx.fetchedAt != nil {
                omlx.error = snapshot.error   // keep last good data, flag the error
            } else {
                omlx = snapshot
            }
        }
    }

    private func refreshSessions() {
        Task.detached { [sessionMonitor] in
            let result = sessionMonitor.scan()
            await MainActor.run {
                self.claudeTasks = result.claude
                self.codexTasks = result.codex
                self.now = Date()
            }
        }
    }
}
