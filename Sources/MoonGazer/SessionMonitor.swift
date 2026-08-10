import Foundation

/// Detects running / recently finished Claude Code and Codex CLI sessions.
/// Running: `ps` scan for claude/codex processes + `lsof` for their working dirs.
/// Activity: newest transcript mtime (~/.claude/projects, ~/.codex/sessions) —
/// a transcript touched in the last 2 minutes means the agent is actively working.
final class SessionMonitor {
    private let workingThreshold: TimeInterval = 120
    private let finishedWindow: TimeInterval = 30 * 60

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    struct RunningProcess {
        let pid: Int
        let elapsed: TimeInterval
        let provider: Provider
        var cwd: String?
    }

    func scan() -> (claude: [AgentTask], codex: [AgentTask]) {
        let running = runningProcesses()
        let claudeTasks = claudeTaskList(running.filter { $0.provider == .claude })
        let codexTasks = codexTaskList(running.filter { $0.provider == .codex })
        return (claudeTasks, codexTasks)
    }

    // MARK: - Process scan

    private func runningProcesses() -> [RunningProcess] {
        guard let output = try? ProcessRunner.runSync("/bin/ps", ["-axo", "pid=,etime=,command="], timeout: 5) else {
            return []
        }
        var processes: [RunningProcess] = []
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]) else { continue }
            let command = String(parts[2])
            guard let provider = classify(command) else { continue }
            processes.append(RunningProcess(pid: pid, elapsed: parseEtime(String(parts[1])),
                                            provider: provider, cwd: nil))
        }
        guard !processes.isEmpty else { return [] }

        // Batch-resolve working directories.
        let pidList = processes.map { String($0.pid) }.joined(separator: ",")
        if let output = try? ProcessRunner.runSync("/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-Fn"], timeout: 5) {
            var currentPid: Int?
            for line in output.split(separator: "\n") {
                if line.hasPrefix("p") { currentPid = Int(line.dropFirst()) }
                else if line.hasPrefix("n"), let pid = currentPid,
                        let index = processes.firstIndex(where: { $0.pid == pid }) {
                    processes[index].cwd = String(line.dropFirst())
                }
            }
        }
        return processes
    }

    private func classify(_ command: String) -> Provider? {
        let tokens = command.split(separator: " ").prefix(2).map(String.init)
        for token in tokens {
            let base = (token as NSString).lastPathComponent
            if base == "claude" { return .claude }
            if base == "codex" { return .codex }
        }
        return nil
    }

    private func parseEtime(_ etime: String) -> TimeInterval {
        // [[dd-]hh:]mm:ss
        var days = 0, rest = etime
        if let dash = etime.firstIndex(of: "-") {
            days = Int(etime[..<dash]) ?? 0
            rest = String(etime[etime.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").compactMap { Int($0) }
        var seconds = 0
        for part in parts { seconds = seconds * 60 + part }
        return TimeInterval(days * 86400 + seconds)
    }

    // MARK: - Claude tasks

    private func claudeTaskList(_ running: [RunningProcess]) -> [AgentTask] {
        let projectsDir = home.appendingPathComponent(".claude/projects")
        var tasks: [AgentTask] = []
        var runningProjectDirs = Set<String>()

        for process in running {
            let name = process.cwd.map { ($0 as NSString).lastPathComponent } ?? "claude"
            let projectDir = process.cwd.map { encodeClaudeProjectDir($0) }
            if let projectDir { runningProjectDirs.insert(projectDir) }

            let state: TaskState
            if let projectDir,
               let mtime = newestFileDate(in: projectsDir.appendingPathComponent(projectDir), suffix: ".jsonl"),
               Date().timeIntervalSince(mtime) < workingThreshold {
                state = .working
            } else {
                state = .idle
            }
            tasks.append(AgentTask(id: "claude-\(process.pid)", name: name,
                                   state: state, detail: shortDuration(process.elapsed)))
        }

        // Recently finished: project transcript touched recently, no live process there.
        if let projectDirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir.path) {
            for dir in projectDirs where !runningProjectDirs.contains(dir) {
                guard let mtime = newestFileDate(in: projectsDir.appendingPathComponent(dir), suffix: ".jsonl") else { continue }
                let age = Date().timeIntervalSince(mtime)
                guard age < finishedWindow else { continue }
                let name = decodeProjectName(dir)
                tasks.append(AgentTask(id: "claude-done-\(dir)", name: name,
                                       state: .finished, detail: "done \(shortDuration(age)) ago"))
            }
        }
        return sorted(tasks)
    }

    /// Claude encodes a project cwd by replacing "/" and "." with "-".
    private func encodeClaudeProjectDir(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func decodeProjectName(_ encoded: String) -> String {
        // Best effort: recover the last path component from a transcript's cwd field.
        let dirURL = home.appendingPathComponent(".claude/projects").appendingPathComponent(encoded)
        if let cwd = cwdFromTranscript(in: dirURL) {
            return (cwd as NSString).lastPathComponent
        }
        return encoded.split(separator: "-").last.map(String.init) ?? encoded
    }

    private func cwdFromTranscript(in directory: URL, suffix: String = ".jsonl") -> String? {
        guard let newest = newestFile(in: directory, suffix: suffix),
              let handle = FileHandle(forReadingAtPath: newest.path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384),
              let text = String(data: data, encoding: .utf8) else { return nil }
        guard let range = text.range(of: "\"cwd\":\"") else { return nil }
        let after = text[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<end])
    }

    // MARK: - Codex tasks

    private func codexTaskList(_ running: [RunningProcess]) -> [AgentTask] {
        var tasks: [AgentTask] = []
        let sessionsDir = home.appendingPathComponent(".codex/sessions")
        let recentRollouts = recentFiles(in: sessionsDir, suffix: ".jsonl", depth: 3, within: finishedWindow)

        var runningCwds = Set<String>()
        // Codex may spawn a child `codex` per session; dedupe by cwd.
        var seenCwds = Set<String>()
        for process in running {
            if let cwd = process.cwd {
                runningCwds.insert(cwd)
                if seenCwds.contains(cwd) { continue }
                seenCwds.insert(cwd)
            }
            let name = process.cwd.map { ($0 as NSString).lastPathComponent } ?? "codex"
            let active = recentRollouts.contains {
                Date().timeIntervalSince($0.mtime) < workingThreshold
            }
            tasks.append(AgentTask(id: "codex-\(process.pid)", name: name,
                                   state: active ? .working : .idle,
                                   detail: shortDuration(process.elapsed)))
        }

        // Recently finished rollouts (session meta's cwd not among running processes).
        for rollout in recentRollouts {
            guard let cwd = cwdFromFileHead(rollout.url), !runningCwds.contains(cwd) else { continue }
            let age = Date().timeIntervalSince(rollout.mtime)
            tasks.append(AgentTask(id: "codex-done-\(rollout.url.lastPathComponent)",
                                   name: (cwd as NSString).lastPathComponent,
                                   state: .finished, detail: "done \(shortDuration(age)) ago"))
        }
        return sorted(tasks)
    }

    private func cwdFromFileHead(_ url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8_192),
              let text = String(data: data, encoding: .utf8),
              let range = text.range(of: "\"cwd\":\"") else { return nil }
        let after = text[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<end])
    }

    // MARK: - File helpers

    private func newestFile(in directory: URL, suffix: String) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles) else { return nil }
        return entries
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
            .max { date(of: $0) ?? .distantPast < date(of: $1) ?? .distantPast }
    }

    private func newestFileDate(in directory: URL, suffix: String) -> Date? {
        newestFile(in: directory, suffix: suffix).flatMap { date(of: $0) }
    }

    private struct RecentFile { let url: URL; let mtime: Date }

    private func recentFiles(in directory: URL, suffix: String, depth: Int, within: TimeInterval) -> [RecentFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var results: [RecentFile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(suffix), let mtime = date(of: url) else { continue }
            if Date().timeIntervalSince(mtime) < within {
                results.append(RecentFile(url: url, mtime: mtime))
            }
        }
        return results.sorted { $0.mtime > $1.mtime }
    }

    private func date(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func sorted(_ tasks: [AgentTask]) -> [AgentTask] {
        let order: (TaskState) -> Int = { state in
            switch state {
            case .working: return 0
            case .idle: return 1
            case .finished: return 2
            }
        }
        return tasks.sorted { order($0.state) < order($1.state) }
    }
}
