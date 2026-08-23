// FreePortPicker — discovers a free loopback TCP port by binding an ephemeral
// socket and releasing it. The small TOCTOU race between close and spawn is
// accepted for a local app; the harness server fails loudly on a collision.

import Foundation

enum FreePortPicker {

    /// Bind an ephemeral socket to discover a free port; `defaultPort` is
    /// returned when the discovery socket calls fail (the harness then binds
    /// its configured default and reports collisions itself).
    static func pickFreePort(defaultPort: Int) -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return defaultPort }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return defaultPort }
        guard listen(fd, 1) == 0 else { return defaultPort }

        var resolved = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard nameResult == 0 else { return defaultPort }
        return Int(CFSwapInt16BigToHost(resolved.sin_port))
    }
}
