//
//  BridgeNetworkUtils.swift
//  Axon
//
//  LAN address discovery and WebSocket URL building utilities for the Bridge.
//

import Foundation

// MARK: - Network Address

struct BridgeNetworkAddress: Identifiable, Equatable, Sendable {
    let id = UUID()
    let interfaceName: String
    let ipAddress: String
    let isPrimary: Bool

    static func == (lhs: BridgeNetworkAddress, rhs: BridgeNetworkAddress) -> Bool {
        lhs.interfaceName == rhs.interfaceName && lhs.ipAddress == rhs.ipAddress
    }
}

// MARK: - Network Utils

enum BridgeNetworkUtils {

    /// Returns all IPv4 LAN addresses available on this device.
    /// Filters out loopback (127.x) and link-local (169.254.x) addresses.
    static func getLocalIPv4Addresses() -> [BridgeNetworkAddress] {
        var addresses: [BridgeNetworkAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                socklen_t(0),
                NI_NUMERICHOST
            )
            let ip = String(cString: hostname)

            // Skip loopback and link-local
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }

            // en0 is typically WiFi on Apple devices
            let isPrimary = name == "en0"
            addresses.append(BridgeNetworkAddress(
                interfaceName: name,
                ipAddress: ip,
                isPrimary: isPrimary
            ))
        }

        // Sort: primary first, then by interface name
        return addresses.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            return a.interfaceName < b.interfaceName
        }
    }

    /// Returns the primary LAN IP address (en0/WiFi), or the first available.
    static func primaryLANAddress() -> String? {
        let all = getLocalIPv4Addresses()
        return all.first(where: { $0.isPrimary })?.ipAddress ?? all.first?.ipAddress
    }

    /// Builds a WebSocket URL string from components.
    static func buildWebSocketURL(host: String, port: UInt16, tlsEnabled: Bool) -> String {
        let scheme = tlsEnabled ? "wss" : "ws"
        return "\(scheme)://\(host):\(port)"
    }
}
