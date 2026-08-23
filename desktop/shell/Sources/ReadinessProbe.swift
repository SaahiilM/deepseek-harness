// ReadinessProbe — polls a server URL until any HTTP response arrives.
//
// Any status counts as ready: the probe proves the listener accepts and
// answers, which is the shell's contract for loading the UI. Connection
// failures throw inside URLSession and keep the loop polling.

import Foundation

enum ReadinessProbe {

    /// Poll every 400ms until a response arrives or `timeout` lapses.
    static func waitUntilReady(
        url: URL,
        timeout: TimeInterval,
        session: URLSession = URLSession(configuration: Self.config)
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
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

    private static var config: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        return config
    }
}
