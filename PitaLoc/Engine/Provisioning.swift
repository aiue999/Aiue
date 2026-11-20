import Foundation
import UserNotifications

/// アプリの署名期限(無料 Apple ID だと 7 日)を読み、期限前に通知する
enum Provisioning {
    /// 埋め込まれた embedded.mobileprovision の ExpirationDate
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return nil }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = xml.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// 残り日数(小数)。わからなければ nil
    static var daysLeft: Double? {
        expirationDate.map { $0.timeIntervalSinceNow / 86_400 }
    }

    static var label: String {
        guard let date = expirationDate else { return "不明" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 H:mm"
        let days = max(0, Int(floor(daysLeft ?? 0)))
        return "\(f.string(from: date))まで(あと\(days)日)"
    }

    /// 期限の 1 日前と 3 時間前に通知を予約する
    static func scheduleReminders() {
        guard let expiry = expirationDate else { return }
        let center = UNUserNotificationCenter.current()
        let ids = ["pitaloc.expiry.1d", "pitaloc.expiry.3h"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let plans: [(String, TimeInterval, String)] = [
            (ids[0], 86_400, "PitaLoc の期限があと1日です"),
            (ids[1], 10_800, "PitaLoc の期限があと3時間です"),
        ]
        for (id, before, title) in plans {
            let fire = expiry.addingTimeInterval(-before)
            guard fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "LocalDevVPN を接続して SideStore を開き、「Refresh All」を押すと延長できます。"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
