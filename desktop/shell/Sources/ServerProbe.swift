// ServerProbe — identifies a running DeepSeek Harness server by its API.
//
// The desktop app prefers adopting an already-running harness server over
// spawning its own (the bb desktop pattern): one backend per machine, many
// clients — browser tab, native window, CLI. The fingerprint is the
// `session.list` RPC: only a harness host answers it with the documented
// server-response envelope, so an unrelated service on the port is rejected.

import Foundation

enum ServerProbe {

    /// True when `data` is a structurally valid harness `session.list`
    /// response (ok envelope with an items array; empty is still a harness).
    static func isHarnessEnvelope(_ data: Data) -> Bool {
        SessionListWire.parseSnapshots(from: data) != nil
    }

    /// Probe `base` (e.g. http://127.0.0.1:3080/) and report whether a
    /// harness server is listening there.
    static func isHarnessServer(
        at base: URL,
        timeout: TimeInterval = 2.0,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("api/session.list"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = timeout
        request.httpBody = SessionListWire.makeRequestBody(rpcId: "probe-\(UUID().uuidString)")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return isHarnessEnvelope(data)
    }
}
