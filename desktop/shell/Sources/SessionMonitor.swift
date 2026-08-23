// SessionMonitor — diffing brain of the Codex-style presence feature.
//
// Polls the harness `session.list` API on a fixed cadence and reports state
// transitions to an injected `AgentPresenceReporting` implementation:
//   - running-agent count changes → badge
//   - running→idle transitions → finish notifications
//
// All AppKit/UserNotifications knowledge lives in the reporter; this type is
// testable with a spy. Poll failures log once per distinct reason so a
// persistent problem stays visible without flooding the unified log.

import Foundation

final class SessionMonitor {

    static let pollInterval: TimeInterval = 3.0

    private let presence: AgentPresenceReporting
    /// True while the user is looking at the app (finish notifications are
    /// suppressed). Injected so tests stay AppKit-free.
    private let isFrontmost: () -> Bool
    private var timer: Timer?
    private var baseURL: URL?

    /// Sessions observed as `running` in the previous successful poll.
    private var runningSessions: Set<String> = []
    private let session = URLSession(configuration: .ephemeral)
    private var lastPollFailure: String?
    private var loggedFirstSuccess = false

    init(presence: AgentPresenceReporting, isFrontmost: @escaping () -> Bool = { false }) {
        self.presence = presence
        self.isFrontmost = isFrontmost
    }

    // MARK: - Lifecycle

    func start(baseURL: URL) {
        stop()
        self.baseURL = baseURL
        NSLog("dsh-desktop session monitor: started against %@", baseURL.absoluteString)
        scheduleTimer()
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        baseURL = nil
        runningSessions = []
        lastPollFailure = nil
        loggedFirstSuccess = false
        presence.runningAgentCountChanged(0)
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    // MARK: - Polling

    func poll() {
        guard let base = baseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("api/session.list"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 5
        request.httpBody = SessionListWire.makeRequestBody(rpcId: UUID().uuidString)

        session.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResponse(data: data, response: response, error: error)
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            logPollFailure("request failed: \(error.localizedDescription)")
            return
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            logPollFailure("non-200 response from /api/session.list")
            return
        }
        guard let data else {
            logPollFailure("empty body")
            return
        }
        guard let snapshots = SessionListWire.parseSnapshots(from: data) else {
            logPollFailure("unparsable body")
            return
        }
        if lastPollFailure != nil {
            NSLog("dsh-desktop session monitor: recovered")
        }
        lastPollFailure = nil
        noteFirstSuccess(itemCount: snapshots.count)
        apply(snapshots: snapshots)
    }

    // MARK: - Diffing

    private func apply(snapshots: [SessionSummarySnapshot]) {
        let nowRunning = Set(snapshots.filter(\.running).map(\.id))
        var titles = [String: String]()
        for snapshot in snapshots {
            if let title = snapshot.title { titles[snapshot.id] = title }
        }

        presence.runningAgentCountChanged(nowRunning.count)

        // Finished turns: were running last poll, idle now — suppressed while
        // the user is already watching.
        let finished = runningSessions.subtracting(nowRunning)
        if !finished.isEmpty && !isFrontmost() {
            for id in finished.prefix(4) {
                presence.agentFinished(id: id, title: titles[id])
            }
        }
        runningSessions = nowRunning
    }

    // MARK: - Diagnostics

    private func logPollFailure(_ reason: String) {
        guard reason != lastPollFailure else { return }
        lastPollFailure = reason
        NSLog("dsh-desktop session monitor: %@", reason)
    }

    /// Logged once on the first successful poll after start.
    private func noteFirstSuccess(itemCount: Int) {
        guard !loggedFirstSuccess else { return }
        loggedFirstSuccess = true
        NSLog("dsh-desktop session monitor: poll ok, %d item(s)", itemCount)
    }
}
