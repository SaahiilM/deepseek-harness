// ServerController — owns the harness web-server process lifecycle.
//
// The desktop app is a thin native shell over the DSH Web GUI. This controller:
//   1. resolves the repository checkout that backs the app,
//   2. locates a Node binary able to run the harness source launch,
//   3. picks a free TCP port,
//   4. spawns `node --import tsx/esm apps/cli/src/bin.ts web --no-open --port N`,
//   5. polls HTTP readiness and reports state changes to its delegate.
//
// Output is teed to ~/Library/Application Support/DeepSeek Harness/server.log and
// an in-memory tail used by the error page when startup fails.

import Foundation

/// Connection states reported through `onStateChange`.
enum ServerState: Equatable {
    /// Resolved configuration, process not started yet.
    case idle
    /// Process spawned; readiness probe in flight.
    case starting(repoRoot: String, port: Int)
    /// Server answered HTTP; the webview may load the URL.
    case running(URL)
    /// Startup probe timed out or the process exited before becoming ready.
    case failed(reason: String, logTail: [String])
    /// A previously running server exited on its own.
    case exited(status: Int32, logTail: [String])
}

final class ServerController: NSObject, @unchecked Sendable {

    /// Invoked on the main queue whenever the state changes.
    var onStateChange: ((ServerState) -> Void)?

    private(set) var state: ServerState = .idle
    private(set) var port: Int = 0
    private(set) var repoRoot: String = ""

    private var process: Process?
    private var probeTask: Task<Void, Never>?
    private var logFileHandle: FileHandle?
    private let logTailLock = NSLock()
    private var logTail: [String] = []

    private static let logDirectory = NSHomeDirectory()
        + "/Library/Application Support/DeepSeek Harness"
    private static let maxTailLines = 250
    /// First boot after a fresh build can be slow; give it generous room.
    private static let readinessTimeout: TimeInterval = 180

    // MARK: - Lifecycle

    func start() {
        DispatchQueue.main.async { [weak self] in self?.startSync() }
    }

    private func startSync() {
        stop(killOnly: true)

        guard let repo = Self.resolveRepoRoot() else {
            transition(.failed(
                reason: "Could not locate the DeepSeek Harness checkout.",
                logTail: ["Set it explicitly with:",
                          "defaults write ai.deepseek.harness.desktop DSHDesktopRepoPath '/path/to/deepseek-harness'",
                          "or launch with the env var DSH_DESKTOP_REPO=/path/to/deepseek-harness"]))
            return
        }
        repoRoot = repo

        guard let node = Self.locateNode() else {
            transition(.failed(
                reason: "Node.js was not found on this machine.",
                logTail: ["Install Node ^22.19 || >=24 (Homebrew: brew install node),",
                          "or point DSH_DESKTOP_NODE at a node binary."]))
            return
        }

        let pickedPort = Self.pickFreePort(defaultPort: 3080)
        port = pickedPort

        let args = ["--import", "tsx/esm",
                    "apps/cli/src/bin.ts", "web",
                    "--no-open",
                    "--port", String(pickedPort)]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: node)
        proc.arguments = args
        proc.currentDirectoryPath = repo

        var env = ProcessInfo.processInfo.environment
        // A GUI app inherits launchd's minimal PATH; hand the child a usable one
        // plus whatever the login shell would provide.
        env["PATH"] = Self.loginShellPath() ?? env["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["DSH_DESKTOP_SHELL"] = "1"
        proc.environment = env

        prepareLogFile()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        [stdoutPipe, stderrPipe].forEach { pipe in
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self?.recordLog(text)
            }
        }

        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.probeTask?.cancel()
            DispatchQueue.main.async {
                switch self.state {
                case .running:
                    self.transition(.exited(status: proc.terminationStatus,
                                            logTail: self.tailSnapshot()))
                default:
                    break // startup failure path reports its own reason
                }
            }
        }

        do {
            try proc.run()
        } catch {
            transition(.failed(reason: "Failed to launch node: \(error.localizedDescription)",
                               logTail: tailSnapshot()))
            return
        }
        process = proc

        appendLog("--- spawning: \(node) \(args.joined(separator: " ")) (cwd: \(repo)) ---\n")
        transition(.starting(repoRoot: repo, port: pickedPort))

        let url = URL(string: "http://127.0.0.1:\(pickedPort)/")!
        probeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let ready = await Self.waitUntilReady(url: url, timeout: Self.readinessTimeout)
            guard !Task.isCancelled, let self else { return }
            DispatchQueue.main.async {
                if ready && proc.isRunning {
                    self.transition(.running(url))
                } else if proc.isRunning {
                    self.transition(.failed(
                        reason: "The harness server did not answer within \(Int(Self.readinessTimeout))s.",
                        logTail: self.tailSnapshot()))
                } else {
                    self.transition(.failed(
                        reason: "The harness server exited during startup (status \(proc.terminationStatus)).",
                        logTail: self.tailSnapshot()))
                }
            }
        }
    }

    /// Terminate the server. Safe to call repeatedly.
    func stop(killOnly: Bool = false) {
        probeTask?.cancel()
        probeTask = nil
        if let proc = process, proc.isRunning {
            // The harness installs its own shutdown handlers; SIGTERM lets it
            // tear down child processes itself.
            proc.terminate()
            _ = killOnly // reserved: force-kill escalation lands here
            proc.waitUntilExit()
        }
        process = nil
        logFileHandle?.closeFile()
        logFileHandle = nil
    }

    // MARK: - State plumbing

    private func transition(_ newState: ServerState) {
        state = newState
        onStateChange?(newState)
    }

    // MARK: - Logging

    private func prepareLogFile() {
        let dir = URL(fileURLWithPath: Self.logDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("server.log")
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
        logFileHandle = try? FileHandle(forWritingTo: path)
        logFileHandle?.seekToEndOfFile()
        appendLog("\n===== session \(Date()) =====\n")
    }

    private func appendLog(_ text: String) {
        logFileHandle?.write(Data(text.utf8))
        logTailLock.lock()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            logTail.append(String(line))
        }
        if logTail.count > Self.maxTailLines {
            logTail.removeFirst(logTail.count - Self.maxTailLines)
        }
        logTailLock.unlock()
    }

    private func recordLog(_ text: String) {
        logTailLock.lock(); defer { logTailLock.unlock() }
        logFileHandle?.write(Data(text.utf8))
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            logTail.append(String(line))
        }
        if logTail.count > Self.maxTailLines {
            logTail.removeFirst(logTail.count - Self.maxTailLines)
        }
    }

    func tailSnapshot() -> [String] {
        logTailLock.lock(); defer { logTailLock.unlock() }
        return logTail.suffix(Self.maxTailLines).map { $0 }
    }

    var logFilePath: String { Self.logDirectory + "/server.log" }

    // MARK: - Resolution helpers

    /// Order: DSH_DESKTOP_REPO env, user default DSHDesktopRepoPath, then walking
    /// up from the executable looking for the harness CLI marker file.
    static func resolveRepoRoot() -> String? {
        let fm = FileManager.default
        func isRepo(_ path: String) -> Bool {
            fm.fileExists(atPath: path + "/apps/cli/src/bin.ts")
        }
        if let env = ProcessInfo.processInfo.environment["DSH_DESKTOP_REPO"], isRepo(env) {
            return env
        }
        if let stored = UserDefaults.standard.string(forKey: "DSHDesktopRepoPath"), isRepo(stored) {
            return stored
        }
        var url = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = url.path
            if isRepo(candidate) { return candidate }
            if url.path == "/" { break }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// Locate a usable node binary (engines: ^22.19 || >=24). Order:
    /// DSH_DESKTOP_NODE, newest qualifying nvm install, common locations, then
    /// the user's login-shell PATH. Every candidate is validated by running it.
    static func locateNode() -> String? {
        let fm = FileManager.default
        if let pinned = ProcessInfo.processInfo.environment["DSH_DESKTOP_NODE"],
           fm.isExecutableFile(atPath: pinned), isSupportedNode(at: pinned) {
            return pinned
        }

        var candidates: [String] = []
        // nvm keeps one directory per version; prefer the newest supported one.
        let nvmVersions = NSHomeDirectory() + "/.nvm/versions/node"
        if let entries = try? fm.contentsOfDirectory(atPath: nvmVersions) {
            let sorted = entries
                .compactMap { entry -> (major: Int, minor: Int, patch: Int)? in
                    // "v22.19.0" -> (22, 19, 0)
                    let parts = entry.dropFirst().split(separator: ".")
                    guard parts.count == 3,
                          let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
                    else { return nil }
                    return (major, minor, patch)
                }
                .filter { ($0.major == 22 && $0.minor >= 19) || $0.major >= 24 }
                .sorted { ($0.major, $0.minor, $0.patch) > ($1.major, $1.minor, $1.patch) }
            candidates.append(contentsOf: sorted.map {
                "\(nvmVersions)/v\($0.major).\($0.minor).\($0.patch)/bin/node"
            })
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/node",
            "/opt/homebrew/opt/node/bin/node",
            "/usr/local/opt/node/bin/node",
            "/usr/local/bin/node",
            NSHomeDirectory() + "/.volta/bin/node",
        ])
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) && isSupportedNode(at: $0) }) {
            return found
        }

        guard let path = loginShellPath() else { return nil }
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = dir + "/node"
            if fm.isExecutableFile(atPath: candidate), isSupportedNode(at: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Run `node --version` and check the harness engines range (^22.19 || >=24).
    /// A binary present on disk but too old must not be picked silently.
    static func isSupportedNode(at path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        proc.standardOutput = Pipe()
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        let data = (proc.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        // "v22.22.2"
        let parts = version.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        let (major, minor) = (parts[0], parts[1])
        return (major == 22 && minor >= 19) || major >= 24
    }

    /// PATH as the user's login shell computes it (GUI apps get launchd's minimal one).
    static func loginShellPath() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8), !path.isEmpty else { return nil }
        return path
    }

    /// Bind an ephemeral socket to discover a free port, then release it. The
    /// small TOCTOU race between close and spawn is accepted for a local app.
    static func pickFreePort(defaultPort: Int) -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return defaultPort }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return defaultPort }
        guard listen(fd, 1) == 0 else { return defaultPort }

        var resolved = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameResult == 0 else { return defaultPort }
        return Int(CFSwapInt16BigToHost(resolved.sin_port))
    }

    /// Poll the server URL until any HTTP response arrives or the timeout lapses.
    static func waitUntilReady(url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        while Date() < deadline {
            if Task.isCancelled { return false }
            // Any HTTP response (any status) proves the server is listening;
            // connection failures throw and keep the loop polling.
            if (try? await session.data(for: request)) != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }
}
