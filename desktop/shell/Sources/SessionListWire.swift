// SessionListWire — the one slice of the harness HTTP API the shell consumes.
//
// Wire contract (packages/host/apiproxy/src/api/sessions.schema.ts):
//   POST /api/session.list  {type:"client-request", rpcId, method, payload:{}}
//   → 200 {type:"server-response", rpcId,
//          result:{ok:true, value:{items:[{sessionId, updatedAt, running,
//          blank, cwd?, projections?:{values?:{title?:string}}}]}}}
//
// Decoding is deliberately lenient: the shell reads three fields per row and
// must survive any widening of the wire schema. Structural failure returns
// nil; rows with missing optional fields still parse.

import Foundation

/// One session row reduced to what the shell's presence features need.
struct SessionSummarySnapshot: Equatable {
    let id: String
    let running: Bool
    let title: String?
}

enum SessionListWire {

    /// Build a `session.list` request body.
    static func makeRequestBody(rpcId: String) -> Data? {
        let payload: [String: Any] = [
            "type": "client-request",
            "rpcId": rpcId,
            "method": "session.list",
            "payload": [String: Any](),
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Parse a successful response body into snapshots. Returns nil when the
    /// envelope or its `value.items` array is structurally missing.
    static func parseSnapshots(from data: Data) -> [SessionSummarySnapshot]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              result["ok"] as? Bool == true,
              let value = result["value"] as? [String: Any],
              let items = value["items"] as? [[String: Any]] else { return nil }

        return items.compactMap { item in
            guard let id = item["sessionId"] as? String else { return nil }
            let title = ((item["projections"] as? [String: Any])?["values"]
                as? [String: Any])?["title"] as? String
            return SessionSummarySnapshot(id: id,
                                          running: item["running"] as? Bool ?? false,
                                          title: title)
        }
    }
}
