import Foundation

enum ProcessRunnerError: Error, LocalizedError {
    case terminated(Int32, String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .terminated(let code, let output): return "exit \(code): \(output)"
        case .timeout: return "process timed out"
        }
    }
}

enum ProcessRunner {
    /// Runs an executable synchronously and returns stdout. Throws on non-zero exit.
    @discardableResult
    static func runSync(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        // Drain both pipes on background queues WHILE the child runs. Reading only
        // after it exits deadlocks when output exceeds the ~64KB pipe buffer — e.g.
        // `ps -axo command=` with thousands of long command lines — because the child
        // blocks on a full pipe and never exits, silently timing out. (This is why
        // live session/process detection always came back empty.)
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let readQueue = DispatchQueue(label: "ProcessRunner.read", attributes: .concurrent)
        group.enter()
        readQueue.async { outData = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        readQueue.async { errData = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                timedOut = true
                break
            }
            usleep(20_000)
        }
        group.wait()  // pipes reach EOF once the process exits or is terminated

        if timedOut { throw ProcessRunnerError.timeout }
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.terminated(process.terminationStatus, err.isEmpty ? out : err)
        }
        return out
    }
}
