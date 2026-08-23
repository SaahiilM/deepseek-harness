// ShellTests — a minimal assertion harness plus behavior tests for the
// shell's pure logic. Deliberately not XCTest: the build is a plain swiftc
// invocation with no package graph, so tests are an executable that exits
// nonzero on the first failure.

import Foundation

var failures = 0
var checks = 0

func expectTrue(_ condition: Bool, _ name: String) {
    checks += 1
    if condition {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    checks += 1
    if actual == expected {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): expected \(expected), got \(actual)")
    }
}

// MARK: - SessionListWire

func testSessionListWire() {
    let body = SessionListWire.makeRequestBody(rpcId: "r-1").flatMap {
        String(data: $0, encoding: .utf8)
    }
    expectTrue(body?.contains("\"method\":\"session.list\"") == true, "wire: request carries session.list method")
    expectTrue(body?.contains("\"rpcId\":\"r-1\"") == true, "wire: request echoes rpcId")

    // Golden envelope captured from a live server (shape per sessions.schema.ts).
    let golden = """
    {"type":"server-response","rpcId":"probe","result":{"ok":true,"value":{"items":[
      {"sessionId":"session-1","updatedAt":1787456671408,"running":true,"blank":false,
       "cwd":"/tmp","agentPreset":"standard",
       "projections":{"asOfSeq":5,"values":{"title":"ship the app"}}},
      {"sessionId":"session-2","updatedAt":1787456671409,"running":false,"blank":true}
    ]}}}
    """.data(using: .utf8)!
    let snapshots = SessionListWire.parseSnapshots(from: golden)
    expectEqual(snapshots?.count, 2, "wire: parses both rows")
    expectEqual(snapshots?[0], SessionSummarySnapshot(id: "session-1", running: true, title: "ship the app"),
                "wire: first row keeps running flag and title")
    expectEqual(snapshots?[1].title, nil, "wire: missing projections parse as untitled")

    expectTrue(SessionListWire.parseSnapshots(from: Data("not json".utf8)) == nil,
               "wire: non-JSON body returns nil")
    expectTrue(SessionListWire.parseSnapshots(from: Data(#"{"result":{"ok":false}}"#.utf8)) == nil,
               "wire: error envelope returns nil")
    expectTrue(SessionListWire.parseSnapshots(from: Data(#"{"result":{"ok":true,"value":{"items":[{"nope":1}]}}}"#.utf8))?.isEmpty == true,
               "wire: row without sessionId is dropped, not fatal")
}

// MARK: - LifecyclePages

func testLifecyclePages() {
    let starting = LifecyclePages.starting()
    expectTrue(starting.contains("Starting DeepSeek Harness"), "pages: starting page names the state")
    expectTrue(starting.contains("spinner"), "pages: starting page animates")

    let error = LifecyclePages.error(reason: "node <missing>", logTail: ["line one", "<tag>"])
    expectTrue(error.contains("node &lt;missing&gt;"), "pages: reason is HTML-escaped")
    expectTrue(error.contains("&lt;tag&gt;"), "pages: log tail is HTML-escaped")
}

// MARK: - ServerLogStore

func testServerLogStore() {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("dsh-logstore-\(UUID().uuidString)")
    let store = ServerLogStore(directory: dir)
    for index in 0..<(ServerLogStore.tailCapacity + 50) {
        store.append("line \(index)\n")
    }
    let tail = store.snapshotTail()
    expectEqual(tail.count, ServerLogStore.tailCapacity, "logstore: tail is capped at capacity")
    expectTrue(tail.last?.hasPrefix("line \(ServerLogStore.tailCapacity + 49)") == true,
               "logstore: tail keeps the newest lines")
    expectTrue(FileManager.default.fileExists(atPath: store.filePath),
               "logstore: file created on init")
}

// MARK: - NodeLocator version rules

func testNodeVersionRules() {
    expectTrue(NodeLocator.isSupportedVersionString("v22.19.0"), "node: 22.19.0 is supported (engines lower bound)")
    expectTrue(NodeLocator.isSupportedVersionString("v22.22.2"), "node: 22.22.2 is supported")
    expectFalse(NodeLocator.isSupported(major: 22, minor: 18), "node: 22.18 is below engines floor")
    expectTrue(NodeLocator.isSupportedVersionString("v24.14.1"), "node: 24.x is supported")
    expectFalse(NodeLocator.isSupportedVersionString("v16.16.0"), "node: 16.x is rejected")
    expectFalse(NodeLocator.isSupportedVersionString("garbage"), "node: garbage version rejected")
    expectEqual(NodeLocator.parseVersionDirectoryName("v24.14.1")?.major, 24, "node: nvm directory name parses")
    expectTrue(NodeLocator.parseVersionDirectoryName("current") == nil, "node: non-version directory ignored")
}

// MARK: - RepoLocator marker rules

func testRepoMarkerRules() {
    var existing: Set<String> = []
    func fakeExists(_ path: String) -> Bool { existing.contains(path) }

    existing = ["/repo/apps/cli/src/bin.ts"]
    expectTrue(RepoLocator.isValidRepo("/repo", fileExists: fakeExists), "repo: valid when marker present")
    expectFalse(RepoLocator.isValidRepo("/other", fileExists: fakeExists), "repo: invalid without marker")

    expectEqual(
        RepoLocator.locateByWalkingUp(fromPath: "/repo/desktop/dist/App.app/Contents/MacOS/bin", fileExists: fakeExists),
        "/repo",
        "repo: walk-up finds root from bundle path")
    expectTrue(
        RepoLocator.locateByWalkingUp(fromPath: "/usr/local/bin/app", fileExists: fakeExists) == nil,
        "repo: walk-up gives up outside a checkout")
}

func expectFalse(_ condition: Bool, _ name: String) {
    expectTrue(!condition, name)
}

// MARK: - Run

testSessionListWire()
testLifecyclePages()
testServerLogStore()
testNodeVersionRules()
testRepoMarkerRules()

print("")
if failures > 0 {
    print("\(failures)/\(checks) failed")
    exit(1)
}
print("all \(checks) checks passed")
