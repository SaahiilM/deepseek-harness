// LanAddress — the machine's LAN-reachable IPv4 address, for pairing URLs.
//
// Enumerates getifaddrs and prefers hardware interfaces over virtual ones so
// the QR code carries an address a phone on the same network can actually
// reach. Pure helpers are separated for testability.

import Foundation

enum LanAddress {

    /// Interface prefixes that are hardware ports on macOS, best-first.
    static let preferredPrefixes = ["en", "bridge"]

    /// Prefixes that never host the LAN the phone is on.
    static let ignoredPrefixes = ["lo", "utun", "apfw", "awdl", "llw", "bridge100"]

    static func isPreferredInterface(_ name: String) -> Bool {
        preferredPrefixes.contains { prefix in
            name.hasPrefix(prefix) && name.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
    }

    static func isIgnoredInterface(_ name: String) -> Bool {
        ignoredPrefixes.contains { name.hasPrefix($0) }
    }

    /// Every configured IPv4 address outside loopback/virtual interfaces,
    /// preferred hardware interfaces first, then everything else.
    static func candidateAddresses() -> [String] {
        var addresses: [(name: String, ip: String)] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_RUNNING) == IFF_RUNNING else { continue }
            guard let sockaddr = entry.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !isIgnoredInterface(name) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len),
                                     &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let ip = String(cString: host)
            if ip != "127.0.0.1" {
                addresses.append((name, ip))
            }
        }
        return addresses.sorted { lhs, rhs in
            let lhsPreferred = isPreferredInterface(lhs.name)
            let rhsPreferred = isPreferredInterface(rhs.name)
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.name < rhs.name
        }.map(\.ip)
    }

    /// Best single guess for the pairing URL host, or nil when offline.
    static func primaryAddress() -> String? {
        candidateAddresses().first
    }
}
