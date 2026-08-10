import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var claude = ProviderSnapshot(provider: .claude)
    @Published var codex = ProviderSnapshot(provider: .codex)
    @Published var claudeTasks: [AgentTask] = []
    @Published var codexTasks: [AgentTask] = []
    @Published var now = Date()
    @Published var showPace: Bool = UserDefaults.standard.object(forKey: "showPace") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPace, forKey: "showPace") }
    }

    private let claudeService = ClaudeService()
    private let codexService = CodexService()
    private let sessionMonitor = SessionMonitor()

    private var usageTimer: Timer?
    private var sessionTimer: Timer?
    private var clockTimer: Timer?

    private let usageInterval: TimeInterval = 300
    private let sessionInterval: TimeInterval = 5

    func start() {
        refreshUsage()
        refreshSessions()

        usageTimer = Timer.scheduledTimer(withTimeInterval: usageInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSessions() }
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
