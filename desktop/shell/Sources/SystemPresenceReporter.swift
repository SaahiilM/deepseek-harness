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

    /// The set of unanswered approval requests changed. Implementers diff
    /// against the previous set to notify about newly pending ones.
    func approvalsChanged(pending: [PendingApprovalInfo])
}

/// System implementation: dock badge for presence, UNUserNotificationCenter
/// for finish and approval notifications, dock bounce as a fallback when TCC
/// denies permission (the case for ad-hoc-signed builds).
///
/// Badge policy: pending approvals win over the running count — attention
/// ("!") outranks activity — then the running count, then no badge.
final class SystemPresenceReporter: AgentPresenceReporting {

    private var permissionRequested = false
    private var runningCount = 0
    private var pendingApprovalIds = Set<String>()

    func runningAgentCountChanged(_ count: Int) {
        runningCount = count
        renderBadge()
    }

    func agentFinished(id: String, title: String?) {
        postFinishedNotification(sessionId: id, title: title)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func approvalsChanged(pending: [PendingApprovalInfo]) {
        let newIds = pending.filter { !pendingApprovalIds.contains($0.id) }
        pendingApprovalIds = Set(pending.map(\.id))
        renderBadge()
        for info in newIds {
            postApprovalNotification(info)
        }
        if !pending.isEmpty {
            NSApp.requestUserAttention(.criticalRequest)
        }
    }

    private func renderBadge() {
        NSApp.dockTile.badgeLabel =
            !pendingApprovalIds.isEmpty ? "!"
            : (runningCount > 0 ? String(runningCount) : nil)
    }

    // MARK: - Notifications

    private func postFinishedNotification(sessionId: String, title: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Agent finished"
        content.body = title.flatMap { $0.isEmpty ? nil : $0 } ?? "A session completed its turn."
        post(content, identifier: "dsh.finished.\(sessionId)")
        bounceFallback()
    }

    private func postApprovalNotification(_ info: PendingApprovalInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Approval needed"
        content.body = "A session wants to run \(info.toolName). Approve it in the app."
        post(content, identifier: "dsh.approval.\(info.id)")
        bounceFallback()
    }

    private func post(_ content: UNMutableNotificationContent, identifier: String) {
        guard let center = authorizedCenter() else { return }
        content.sound = .default
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// TCC denies notifications to ad-hoc-signed builds; the dock bounce is
    /// the visible fallback there.
    private func bounceFallback() {
        NSApp.requestUserAttention(.informationalRequest)
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
