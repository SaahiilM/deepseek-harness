// SessionMonitor — Codex-style presence: polls the harness API for session
// activity and surfaces it natively.
//
// Patterns adopted from the reference products (get-bb/bb, pingdotgg/t3code,
// OpenAI Codex): the desktop shell reflects live agent state outside the
// webview — a dock badge with the number of running agents and a system
// notification when an agent finishes a turn while the window is elsewhere.
//
// Wire contract (packages/host/apiproxy/src/api/sessions.schema.ts):
//   POST /api/session.list  {type:"client-request", rpcId, method, payload:{}}
//   → 200 {type:"server-response", rpcId, result:{ok:true, value:{items:[{
//         sessionId, updatedAt, running, blank, cwd,
//         projections?:{values?:{title?:string}}}]}}}

import Foundation
import UserNotifications
import AppKit

final class SessionMonitor: NSObject {

    private var baseURL: URL?
    private var timer: Timer?
    /// Sessions observed as `running` in the previous successful poll.
    private var runningSessions: Set<String> = []
    private let session = URLSession(configuration: .ephemeral)

    func start(baseURL: URL) {
        stop()
        self.baseURL = baseURL
        NSLog("dsh-desktop session monitor: started against %@", baseURL.absoluteString)
        requestNotificationPermissionOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        baseURL = nil
        runningSessions = []
        DispatchQueue.main.async { NSApp.dockTile.badgeLabel = nil }
    }

    // MARK: - Polling

    /// Last poll failure logged, so a persistent problem logs once instead of
    /// every 3 seconds.
    private var lastPollFailure: String?

    private func logPollFailure(_ reason: String) {
        guard reason != lastPollFailure else { return }
        lastPollFailure = reason
        NSLog("dsh-desktop session monitor: %@", reason)
    }

    private func poll() {
        guard let base = baseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("api/session.list"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 5
        let rpcId = UUID().uuidString
        request.httpBody = #"{"type":"client-request","rpcId":"\#(rpcId)","method":"session.list","payload":{}}"#
            .data(using: .utf8)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.logPollFailure("request failed: \(error.localizedDescription)")
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.logPollFailure("non-HTTP response")
                return
            }
            guard http.statusCode == 200 else {
                self.logPollFailure("HTTP \(http.statusCode) from /api/session.list")
                return
            }
            guard let data else {
                self.logPollFailure("empty body")
                return
            }
            if self.lastPollFailure != nil {
                NSLog("dsh-desktop session monitor: recovered")
            }
            self.lastPollFailure = nil
            self.consume(data: data)
        }.resume()
    }

    /// Logged once on the first successful poll after start.
    private var loggedFirstSuccess = false

    private func noteFirstSuccess(itemCount: Int) {
        guard !loggedFirstSuccess else { return }
        loggedFirstSuccess = true
        NSLog("dsh-desktop session monitor: poll ok, %d item(s)", itemCount)
    }

    private struct Snapshot {
        let id: String
        let running: Bool
        let title: String?
    }

    private func consume(data: Data) {
        // Lenient decode: the shell only reads three fields and must survive
        // any widening of the wire schema.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              result["ok"] as? Bool == true,
              let value = result["value"] as? [String: Any],
              let items = value["items"] as? [[String: Any]] else { return }

        let snapshots = items.compactMap { item -> Snapshot? in
            guard let id = item["sessionId"] as? String else { return nil }
            let title = ((item["projections"] as? [String: Any])?["values"]
                as? [String: Any])?["title"] as? String
            return Snapshot(id: id, running: item["running"] as? Bool ?? false, title: title)
        }
        noteFirstSuccess(itemCount: snapshots.count)

        DispatchQueue.main.async { [weak self] in
            self?.apply(snapshots: snapshots)
        }
    }

    private func apply(snapshots: [Snapshot]) {
        let nowRunning = Set(snapshots.filter(\.running).map(\.id))
        var titles = [String: String]()
        for snapshot in snapshots {
            if let title = snapshot.title { titles[snapshot.id] = title }
        }

        // Finished turns: were running last poll, idle now → notify (Codex's
        // "your task is done" affordance). Suppressed while the app is
        // frontmost — the user is already watching. Dock bounce backs the
        // notification up for installs where TCC denies permission
        // (ad-hoc signed builds).
        let finished = runningSessions.subtracting(nowRunning)
        if !finished.isEmpty && !NSApp.isActive {
            for id in finished.prefix(4) {
                postFinishedNotification(sessionId: id, title: titles[id])
            }
            NSApp.requestUserAttention(.informationalRequest)
        }
        runningSessions = nowRunning

        let count = nowRunning.count
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    // MARK: - Notifications

    private var permissionRequested = false

    private func requestNotificationPermissionOnce() {
        guard !permissionRequested else { return }
        permissionRequested = true
        // UNUserNotificationCenter aborts the process when the binary has no
        // bundle identity (bare-binary dev runs); notifications are then
        // simply unavailable.
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("dsh-desktop session monitor: no bundle identity, notifications disabled")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("dsh-desktop: notification authorization failed: %@", error.localizedDescription)
            }
            _ = granted // declined is fine: badge still works
        }
    }

    private func postFinishedNotification(sessionId: String, title: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Agent finished"
        content.body = title.flatMap { $0.isEmpty ? nil : $0 } ?? "A session completed its turn."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dsh.finished.\(sessionId)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
