import Darwin
import Foundation
import UIKit

/// LocalDevVPN(App Store の無料アプリ)の状態確認と起動
enum LocalDevVPN {
    static let defaultIP = "10.7.0.1"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!
    private static let schemeURL = URL(string: "localdevvpn://")!
    /// 接続したあと pitaloc:// でこのアプリに戻ってくる
    private static let enableURL = URL(string: "localdevvpn://enable?scheme=pitaloc")!

    static var targetIP: String {
        let s = UserDefaults.standard.string(forKey: "pitaloc.tunnelIP")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? defaultIP : s
    }

    @MainActor static var isInstalled: Bool { UIApplication.shared.canOpenURL(schemeURL) }

    /// VPN が繋がると 10.7.0.x のアドレスがインターフェースに現れる
    static var isConnected: Bool {
        let target = targetIP
        let parts = target.split(separator: ".")
        let prefix = parts.count == 4 ? parts.dropLast().joined(separator: ".") + "." : target
        return interfaceAddresses().contains { $0 == target || $0.hasPrefix(prefix) }
    }

    @MainActor static func connect() {
        UIApplication.shared.open(isInstalled ? enableURL : appStoreURL)
    }

    private static func interfaceAddresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [String] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(MemoryLayout<sockaddr_in>.size), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result.append(String(cString: host))
                }
            }
            p = cur.pointee.ifa_next
        }
        return result
    }
}
