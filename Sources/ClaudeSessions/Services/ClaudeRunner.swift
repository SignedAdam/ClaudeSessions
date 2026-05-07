import Foundation

/// Spawns `claude -p --resume <id> '<prompt>'` against an open conversation
/// and waits for it to exit. The CLI does the work of reading the existing
/// JSONL, sending the new prompt, and appending the assistant's response —
/// FileWatcher (already wired) picks up the appended entries and the
/// conversation view updates live.
///
/// Threading: spawning + waitUntilExit happens off the main actor. The
/// async `run()` resumes on the calling actor with the result.
///
/// Cancellation: callers store the active runner instance and call
/// `cancel()` to send SIGINT, then SIGTERM after a grace period. The
/// in-flight `run()` returns with `.cancelled`.
final class ClaudeRunner: @unchecked Sendable {

    enum RunOutcome {
        case success(stdout: String)
        /// `claude` exited non-zero. Both streams are reported because
        /// `claude -p` often writes the actual error to stdout.
        case failure(exitCode: Int32, stderr: String, stdout: String)
        case cancelled
        case launchFailed(String)
    }

    /// Active process, if any. nil between runs.
    private var task: Process?
    private let queue = DispatchQueue(label: "claude-sessions.claude-runner",
                                      qos: .userInitiated)

    var isRunning: Bool { task?.isRunning ?? false }

    /// Run `claude -p --resume <sessionId> '<prompt>'` in `cwd`. Returns when
    /// the process exits.
    ///
    /// - parameter sessionId: must match an existing session file in the
    ///   project directory derived from `cwd`. Required for `--resume`.
    /// - parameter cwd: must equal the original session's cwd or `--resume`
    ///   won't find the file.
    func run(sessionId: String, prompt: String, cwd: String) async -> RunOutcome {
        // Resolve the binary. `claude` is usually in PATH; we shell out via
        // /usr/bin/env so we don't have to track its install location.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["claude", "-p", "--resume", sessionId, prompt]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        // Skip the 3-second stdin wait observed in P2.T01.
        proc.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Inherit env but ensure HOME and PATH are present (launchd / Xcode
        // sometimes hands the parent a stripped env).
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if env["PATH"] == nil || env["PATH"]?.isEmpty == true {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        proc.environment = env

        self.task = proc

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                do {
                    try proc.run()
                } catch {
                    self?.task = nil
                    continuation.resume(returning: .launchFailed(error.localizedDescription))
                    return
                }

                proc.waitUntilExit()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let code = proc.terminationStatus
                let reason = proc.terminationReason
                self?.task = nil

                if reason == .uncaughtSignal && (code == SIGINT.rawValue
                                                 || code == SIGTERM.rawValue) {
                    continuation.resume(returning: .cancelled)
                } else if code == 0 {
                    continuation.resume(returning: .success(stdout: stdout))
                } else {
                    continuation.resume(returning: .failure(exitCode: code,
                                                            stderr: stderr,
                                                            stdout: stdout))
                }
            }
        }
    }

    /// Send SIGINT, then SIGTERM after a 1s grace if still alive.
    /// Used by the upcoming Stop button (P2.T05).
    func cancel() {
        guard let p = task, p.isRunning else { return }
        p.interrupt()  // SIGINT
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) { [weak p] in
            guard let p, p.isRunning else { return }
            p.terminate()  // SIGTERM
        }
    }
}

private extension Int32 {
    /// Local-only: `Process.terminationStatus` returns the signal as an
    /// Int32, but the syscall constants are also Int32, so direct
    /// comparison works. We define `rawValue` to match enum-style usage
    /// in the comparison above.
    var rawValue: Int32 { self }
}
