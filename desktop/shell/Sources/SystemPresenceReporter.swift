// AgentPresenceReporting — how the session monitor surfaces live agent state
// outside the webview. The monitor decides *when*; implementers decide *how*
// (dock badge, notifications, bounce). The protocol keeps SessionMonitor
// testable without AppKit or notification permissions.

import AppKit
import Foundation
import UserNotifications

protocol AgentPresenceReporting: AnyObject {

    /// The count of running agents changed (0 clears any badge).
    func runningAgentCountChanged(_ count: Int)

    /// A previously running agent finished its turn while the user was
    /// looking elsewhere.
    func agentFinished(id: String, title: String?)
}

/// System implementation: dock badge for presence, UNUserNotificationCenter
/// for finish notifications, dock bounce as a fallback when TCC denies
/// permission (the case for ad-hoc-signed builds).
final class SystemPresenceReporter: AgentPresenceReporting {

    private var permissionRequested = false

    func runningAgentCountChanged(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    func agentFinished(id: String, title: String?) {
        postFinishedNotification(sessionId: id, title: title)
        NSApp.requestUserAttention(.informationalRequest)
    }

    // MARK: - Notifications

    private func postFinishedNotification(sessionId: String, title: String?) {
        guard let center = authorizedCenter() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Agent finished"
        content.body = title.flatMap { $0.isEmpty ? nil : $0 } ?? "A session completed its turn."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dsh.finished.\(sessionId)",
                                            content: content, trigger: nil)
        center.add(request)
    }

    /// Returns the notification center once permission has been resolved, or
    /// nil when unavailable. `UNUserNotificationCenter` aborts processes with
    /// no bundle identity (bare-binary dev runs), and ad-hoc-signed bundles
    /// are denied by TCC — both degrade to the dock-bounce fallback.
    private func authorizedCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("dsh-desktop presence: no bundle identity, notifications disabled")
            return nil
        }
        let center = UNUserNotificationCenter.current()
        if !permissionRequested {
            permissionRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    NSLog("dsh-desktop presence: authorization failed: %@", error.localizedDescription)
                }
                // declined is fine: badge and bounce still work
            }
        }
        return center
    }
}
