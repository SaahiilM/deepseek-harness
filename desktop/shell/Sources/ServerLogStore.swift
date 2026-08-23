// ServerLogStore — durable server log with an in-memory tail.
//
// Every line is appended both to the log file under
// ~/Library/Application Support/DeepSeek Harness/ and to a bounded ring buffer
// the error page shows when startup fails. All access is thread-safe: writers
// run on URLSession reader threads, readers on the main queue.

import Foundation

final class ServerLogStore {

    /// Number of lines kept in memory for the error page.
    static let tailCapacity = 250

    let logFileURL: URL

    private let lock = NSLock()
    private var handle: FileHandle?
    private var tail: [String] = []

    /// Creates the support directory and opens the log file for appending.
    init(directory: URL? = nil) {
        let dir = directory ?? URL(fileURLWithPath: Self.defaultDirectory)
        logFileURL = dir.appendingPathComponent("server.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: logFileURL)
        handle?.seekToEndOfFile()
        append("--- session \(Date()) ---\n")
    }

    deinit {
        handle?.closeFile()
    }

    var filePath: String { logFileURL.path }

    /// Append raw text; embedded newlines split into separate tail lines, and
    /// a trailing newline terminates the final line rather than opening an
    /// empty one.
    func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        handle?.write(Data(text.utf8))
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") {
            lines.removeLast()
        }
        tail.append(contentsOf: lines)
        if tail.count > Self.tailCapacity {
            tail.removeFirst(tail.count - Self.tailCapacity)
        }
    }

    /// Copy of the buffered tail (oldest first), capped at `tailCapacity`.
    func snapshotTail() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(tail.suffix(Self.tailCapacity))
    }

    /// Default per-user log directory.
    static var defaultDirectory: String {
        NSHomeDirectory() + "/Library/Application Support/DeepSeek Harness"
    }
}
