// ServerController — resolves and owns the connection to the machine's
// harness backend.
//
// Adopt-over-spawn (the bb desktop pattern): the machine should run ONE
// harness host; browser tabs and the native window are both just clients.
// On start the controller probes candidate ports for an existing harness
// server and attaches to it. Only when none answers does it spawn an owned
// `node … web --no-open --port N` process. An attached server is never
// terminated by this app — we do not own it.

import Foundation

/// Connection states reported through `onStateChange` on the main queue.
enum ServerState: Equatable {
    /// Resolved configuration, process not started yet.
    case idle
    /// Process spawned (or attachment probe in flight); readiness in question.
    case starting(repoRoot: String, port: Int)
    /// A server — adopted or owned — is answering; the UI may load the URL.
    case running(URL)
    /// Startup probe timed out or the process exited before becoming ready.
    case failed(reason: String, logTail: [String])
    /// A previously running server exited on its own.
    case exited(status: Int32, logTail: [String])
}

final class ServerController: NSObject, @unchecked Sendable {

    /// The documented default port every harness web install answers on.
    static let preferredExternalPort = 3080
    static let readinessTimeout: TimeInterval = 180

    enum Mode: Equatable {
        /// Attached to a server this app did not start; never terminated.
        case attached
        /// Spawned by this app; terminated on quit/restart.
        case owned
    }

    /// Invoked on the main queue whenever the state changes.
    var onStateChange: ((ServerState) -> Void)?

    private(set) var state: ServerState = .idle
    private(set) var mode: Mode = .owned
    private(set) var port: Int = 0
    private(set) var repoRoot: String = ""

    private let logStore: ServerLogStore
    private let defaults: UserDefaults
    private var process: Process?
    private var probeTask: Task<Void, Never>?

    init(logStore: ServerLogStore = ServerLogStore(), defaults: UserDefaults = .standard) {
        self.logStore = logStore
        self.defaults = defaults
    }

    var logFilePath: String { logStore.filePath }

    /// UserDefaults key remembering the last owned-server port so a later
    /// launch can adopt it after the app quit but the server stayed up.
    static let lastOwnedPortKey = "DSHDesktopLastOwnedPort"

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
        NSLog("dsh-desktop server: using harness checkout at %@", repo)

        transition(.starting(repoRoot: repo, port: 0))
        let candidates = adoptionCandidates()

        probeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let adopted = await Self.firstHarnessServer(among: candidates) {
                DispatchQueue.main.async { self.attach(url: adopted, repoRoot: repo) }
                return
            }
            // Nothing to adopt: spawn an owned server from the resolved root.
            guard let node = NodeLocator.locate(
                environment: ProcessInfo.processInfo.environment,
                repoRoot: repo) else {
                DispatchQueue.main.async {
                    self.transition(.failed(
                        reason: "Node.js was not found on this machine.",
                        logTail: ["Install Node ^22.19 || >=24 (Homebrew: brew install node),",
                                  "or point \(NodeLocator.environmentKey) at a node binary."]))
                }
                return
            }
            DispatchQueue.main.async { self.spawnOwned(node: node, repoRoot: repo) }
        }
    }

    /// Ports worth probing, most likely first: the harness default, then the
    /// last port an owned server used (it may outlive the app).
    private func adoptionCandidates() -> [Int] {
        var ports = [Self.preferredExternalPort]
        let lastOwned = defaults.integer(forKey: Self.lastOwnedPortKey)
        if lastOwned > 0 && lastOwned != Self.preferredExternalPort {
            ports.append(lastOwned)
        }
        return ports
    }

    /// First candidate answered by a harness server, or nil.
    private static func firstHarnessServer(among ports: [Int]) async -> URL? {
        for port in ports {
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else { continue }
            if await ServerProbe.isHarnessServer(at: url) {
                return url
            }
        }
        return nil
    }

    /// Attach to an existing server: report it running without owning it.
    private func attach(url: URL, repoRoot: String) {
        mode = .attached
        port = url.port ?? Self.preferredExternalPort
        logStore.append("--- attached to existing harness server at \(url.absoluteString) ---\n")
        transition(.running(url))
    }

    /// Spawn an owned harness server on a fresh free port.
    private func spawnOwned(node: String, repoRoot: String) {
        let pickedPort = FreePortPicker.pickFreePort(defaultPort: Self.preferredExternalPort)
        port = pickedPort
        mode = .owned
        defaults.set(pickedPort, forKey: Self.lastOwnedPortKey)

        let args = ["--import", "tsx/esm",
                    RepoLocator.markerPath, "web",
                    "--no-open", "--port", String(pickedPort)]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = args
        proc.currentDirectoryPath = repoRoot
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

        logStore.append("--- spawning: \(node) \(args.joined(separator: " ")) (cwd: \(repoRoot)) ---\n")

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

    /// Terminate the owned server, if any. An attached server is never killed.
    func stop() {
        probeTask?.cancel()
        probeTask = nil
        if mode == .owned, let proc = process, proc.isRunning {
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
