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

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw ProcessRunnerError.timeout
            }
            usleep(20_000)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.terminated(process.terminationStatus, err.isEmpty ? out : err)
        }
        return out
    }
}
