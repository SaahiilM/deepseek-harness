// ApprovalStream — consumes the host's mux WebSocket for approval requests.
//
// When a tool needs permission the host pushes a server-request frame whose
// payload type is `approval/requested`; the answer travels out-of-band
// (POST /api/respond from the web UI), and the resolution is broadcast as an
// `approval/resolved` payload. The shell only observes: it never answers.
// On every (re)connect the host replays still-pending requests with their
// original rpcIds, so the pending set self-heals after drops and restarts.

import Foundation

/// One unanswered approval request, as observed on the mux stream.
struct PendingApprovalInfo: Equatable {
    let id: String
    let toolName: String
}

/// Decoded mux events this stream cares about; everything else is ignored.
enum MuxApprovalEvent: Equatable {
    case requested(PendingApprovalInfo)
    case resolved(id: String)
}

final class ApprovalStream {

    /// Reconnect delays grow to this cap; the host replays pending state on
    /// every connect, so backoff only trades latency for quietness.
    static let maxReconnectDelay: TimeInterval = 30.0

    private let presence: AgentPresenceReporting
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var baseURL: URL?

    /// All state lives on this serial queue; callbacks reach the app on main.
    private let queue = DispatchQueue(label: "dsh-desktop.approval-stream")
    private var pending: [String: PendingApprovalInfo] = [:]
    private var reconnectAttempt = 0

    init(presence: AgentPresenceReporting) {
        self.presence = presence
        session = URLSession(configuration: .ephemeral)
    }

    /// The loopback base URL reported by ServerState.running (http or https).
    func start(baseURL: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.baseURL = baseURL
            self.reconnectAttempt = 0
            self.connect()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.baseURL = nil
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            if !self.pending.isEmpty {
                self.pending = [:]
                DispatchQueue.main.async { [presence] in
                    presence.approvalsChanged(pending: [])
                }
            }
        }
    }

    // MARK: - Connection lifecycle (runs on `queue`)

    private func connect() {
        guard let base = baseURL,
              let wsURL = Self.webSocketURL(for: base) else { return }
        NSLog("dsh-desktop approvals: connecting to %@", wsURL.absoluteString)
        let task = session.webSocketTask(with: wsURL)
        self.task = task
        task.resume()
        receiveNext(on: task)
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            self?.queue.async { self?.handleReceive(result, task: task) }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, task: URLSessionWebSocketTask) {
        guard task === self.task else { return } // superseded connection
        switch result {
        case .success(let message):
            if let event = Self.event(from: message) {
                apply(event)
            }
            receiveNext(on: task)
        case .failure(let error):
            NSLog("dsh-desktop approvals: stream ended (%@)", error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard baseURL != nil else { return }
        reconnectAttempt += 1
        let delay = min(Double(reconnectAttempt), Self.maxReconnectDelay)
        task = nil
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.baseURL != nil else { return }
            self.connect()
        }
    }

    // MARK: - State application

    private func apply(_ event: MuxApprovalEvent) {
        switch event {
        case .requested(let info):
            pending[info.id] = info
        case .resolved(let id):
            pending.removeValue(forKey: id)
        }
        let snapshot = Array(pending.values).sorted { $0.id < $1.id }
        DispatchQueue.main.async { [presence] in
            presence.approvalsChanged(pending: snapshot)
        }
    }

    // MARK: - Pure decoding

    /// The mux WebSocket path served by the host's connection plugin.
    static let muxEventsPath = "/api/events.mux"

    /// http(s) → ws(s) on the same authority, pointed at the mux path.
    static func webSocketURL(for base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http", nil: components.scheme = "ws"
        default: return nil
        }
        components.path = muxEventsPath
        return components.url
    }

    /// Decode one websocket message into an approval event, or nil when the
    /// frame is unrelated, malformed, or missing required fields.
    static func event(from message: URLSessionWebSocketTask.Message) -> MuxApprovalEvent? {
        switch message {
        case .string(let text): return event(fromText: text)
        case .data(let data): return event(fromData: data)
        default: return nil
        }
    }

    static func event(fromData data: Data) -> MuxApprovalEvent? {
        Self.event(fromText: String(decoding: data, as: UTF8.self))
    }

    static func event(fromText text: String) -> MuxApprovalEvent? {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data),
              let frame = envelope as? [String: Any],
              let payload = frame["payload"] as? [String: Any],
              let type = payload["type"] as? String else { return nil }

        switch type {
        case "approval/requested":
            guard let id = stringField(payload["approvalId"]),
                  stringField(payload["sessionId"]) != nil,
                  let toolName = stringField(payload["toolName"]) else { return nil }
            return .requested(PendingApprovalInfo(id: id, toolName: toolName))
        case "approval/resolved":
            guard let id = stringField(payload["approvalId"]) else { return nil }
            return .resolved(id: id)
        default:
            return nil
        }
    }

    private static func stringField(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
