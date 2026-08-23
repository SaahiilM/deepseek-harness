// ServerController — owns the harness web-server process lifecycle.
//
// Responsibilities: resolve the checkout and node binary, pick a port, spawn
// `node --import tsx/esm apps/cli/src/bin.ts web --no-open --port N`, probe
// readiness, and report state transitions. Resolution, logging, port picking,
// and probing live in their own modules; this type only orchestrates them.

import Foundation

/// Connection states reported through `onStateChange` on the main queue.
enum ServerState: Equatable {
    /// Resolved configuration, process not started yet.
    case idle
    /// Process spawned; readiness probe in flight.
    case starting(repoRoot: String, port: Int)
    /// Server answered HTTP; the UI may load the URL.
    case running(URL)
    /// Startup probe timed out or the process exited before becoming ready.
    case failed(reason: String, logTail: [String])
    /// A previously running server exited on its own.
    case exited(status: Int32, logTail: [String])
}

final class ServerController: NSObject, @unchecked Sendable {

    static let defaultPort = 3080
    /// First boot after a fresh build can be slow; give it generous room.
    static let readinessTimeout: TimeInterval = 180

    /// Invoked on the main queue whenever the state changes.
    var onStateChange: ((ServerState) -> Void)?

    private(set) var state: ServerState = .idle
    private(set) var port: Int = 0
    private(set) var repoRoot: String = ""

    private let logStore: ServerLogStore
    private var process: Process?
    private var probeTask: Task<Void, Never>?

    init(logStore: ServerLogStore = ServerLogStore()) {
        self.logStore = logStore
    }

    var logFilePath: String { logStore.filePath }

    // MARK: - Lifecycle

    func start() {
        DispatchQueue.main.async { [weak self] in self?.startSync() }
    }

    private func startSync() {
        stop()

        guard let repo = RepoLocator.resolve() else {
            transition(.failed(
                reason: "Could not locate the DeepSeek Harness checkout.",
                logTail: ["Set it explicitly with:",
                          "defaults write ai.deepseek.harness.desktop \(RepoLocator.userDefaultsKey) '/path/to/deepseek-harness'",
                          "or launch with the env var \(RepoLocator.environmentKey)=/path/to/deepseek-harness"]))
            return
        }
        repoRoot = repo

        guard let node = NodeLocator.locate(environment: ProcessInfo.processInfo.environment) else {
            transition(.failed(
                reason: "Node.js was not found on this machine.",
                logTail: ["Install Node ^22.19 || >=24 (Homebrew: brew install node),",
                          "or point \(NodeLocator.environmentKey) at a node binary."]))
            return
        }

        let pickedPort = FreePortPicker.pickFreePort(defaultPort: Self.defaultPort)
        port = pickedPort

        let args = ["--import", "tsx/esm",
                    RepoLocator.markerPath, "web",
                    "--no-open", "--port", String(pickedPort)]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = args
        proc.currentDirectoryPath = repo
        proc.environment = childEnvironment()
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        [proc.standardOutput, proc.standardError].forEach { pipe in
            (pipe as? Pipe)?.fileHandleForReading.readabilityHandler = { [logStore] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                logStore.append(text)
            }
        }

        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.probeTask?.cancel()
            DispatchQueue.main.async {
                if case .running = self.state {
                    self.transition(.exited(status: proc.terminationStatus,
                                            logTail: self.logStore.snapshotTail()))
                }
                // startup failure path reports its own reason
            }
        }

        do {
            try proc.run()
        } catch {
            transition(.failed(reason: "Failed to launch node: \(error.localizedDescription)",
                               logTail: logStore.snapshotTail()))
            return
        }
        process = proc

        logStore.append("--- spawning: \(node) \(args.joined(separator: " ")) (cwd: \(repo)) ---\n")
        transition(.starting(repoRoot: repo, port: pickedPort))

        let url = URL(string: "http://127.0.0.1:\(pickedPort)/")!
        probeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let ready = await ReadinessProbe.waitUntilReady(url: url, timeout: Self.readinessTimeout)
            guard !Task.isCancelled, let self else { return }
            DispatchQueue.main.async {
                self.finishStartup(ready: ready, url: url, process: proc)
            }
        }
    }

    private func finishStartup(ready: Bool, url: URL, process: Process) {
        switch (ready, process.isRunning) {
        case (true, true):
            transition(.running(url))
        case (_, false):
            transition(.failed(
                reason: "The harness server exited during startup (status \(process.terminationStatus)).",
                logTail: logStore.snapshotTail()))
        case (false, _):
            transition(.failed(
                reason: "The harness server did not answer within \(Int(Self.readinessTimeout))s.",
                logTail: logStore.snapshotTail()))
        }
    }

    /// Terminate the server. Safe to call repeatedly.
    func stop() {
        probeTask?.cancel()
        probeTask = nil
        if let proc = process, proc.isRunning {
            // The harness installs its own shutdown handlers; SIGTERM lets it
            // tear down child processes itself.
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
    }

    // MARK: - Plumbing

    private func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // A GUI app inherits launchd's minimal PATH; hand the child whatever
        // the login shell would provide, falling back to a usable baseline.
        env["PATH"] = NodeLocator.loginShellPath()
            ?? env["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["DSH_DESKTOP_SHELL"] = "1"
        return env
    }

    private func transition(_ newState: ServerState) {
        state = newState
        onStateChange?(newState)
    }
}
