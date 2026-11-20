import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
import UserNotifications

struct Place: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum SpoofState: Equatable {
    case idle
    case connecting
    case fixed
    case reconnecting
    case failed(String)
}

/// 移動シミュレーションの手段
enum TravelMode: String, CaseIterable, Identifiable {
    case walk, bike, car

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "徒歩"
        case .bike: return "自転車"
        case .car: return "車"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .bike: return "bicycle"
        case .car: return "car.fill"
        }
    }

    /// 平均速度 (m/s)
    var speed: Double {
        switch self {
        case .walk: return 1.4   // 約5 km/h
        case .bike: return 4.2   // 約15 km/h
        case .car: return 11.0   // 約40 km/h
        }
    }

    var transportType: MKDirectionsTransportType {
        self == .car ? .automobile : .walking
    }
}

/// 「固定」「解除」「移動」「自動解除」「揺らぎ」とお気に入りを管理する
@MainActor
final class SpoofController: ObservableObject {
    @Published private(set) var state: SpoofState = .idle
    /// 今いることになっている場所(揺らぎを足す前の中心。移動中は刻々と変わる)
    @Published private(set) var fixedCoordinate: CLLocationCoordinate2D?
    @Published var errorMessage: String?
    @Published private(set) var favorites: [Place] = []
    @Published private(set) var vpnConnected = false

    // 移動シミュレーション
    @Published private(set) var isMoving = false
    @Published private(set) var isPreparingRoute = false
    @Published private(set) var moveProgress: Double = 0
    @Published private(set) var moveRemainingSeconds: Double = 0
    @Published private(set) var routeLine: [CLLocationCoordinate2D] = []
    @Published var travelMode: TravelMode = .walk

    // 自動解除
    @Published private(set) var releaseAt: Date?

    // 揺らぎ(設定画面の @AppStorage と同じキーを毎回読む)
    nonisolated static let jitterEnabledKey = "pitaloc.jitterEnabled"
    nonisolated static let jitterMetersKey = "pitaloc.jitterMeters"
    private var jitterEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.jitterEnabledKey) as? Bool ?? true
    }
    private var jitterMeters: Double {
        UserDefaults.standard.object(forKey: Self.jitterMetersKey) as? Double ?? 5
    }

    let keepAlive = KeepAlive()
    private let engine = LocationEngine.shared
    private var tickTimer: Timer?
    private var moveTask: Task<Void, Never>?
    private var pairing: PairingStore?
    private var failureCount = 0
    private var busy = false
    private var jitterOffset = (east: 0.0, north: 0.0)

    private static let favoritesKey = "pitaloc.favorites"
    private static let lastFixedKey = "pitaloc.lastFixed"
    private static let tickInterval: TimeInterval = 3

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let list = try? JSONDecoder().decode([Place].self, from: data) {
            favorites = list
        }
        refreshVPN()
    }

    var isFixed: Bool {
        switch state {
        case .fixed, .reconnecting: return true
        default: return false
        }
    }

    var isBusy: Bool { state == .connecting || isPreparingRoute }

    func refreshVPN() {
        vpnConnected = LocalDevVPN.isConnected
    }

    // MARK: - 固定 / 解除

    func fix(at coordinate: CLLocationCoordinate2D, pairing: PairingStore) async {
        guard pairing.hasPairingFile else {
            errorMessage = "先にペアリングファイルを読み込んでください(設定 ⚙︎)。"
            return
        }
        self.pairing = pairing
        stopMoving()
        refreshVPN()  // 表示用。判定がずれていても接続自体は試す
        state = .connecting
        errorMessage = nil
        jitterOffset = (0, 0)
        let result = await send(coordinate, pairing: pairing)
        switch result {
        case .success:
            fixedCoordinate = coordinate
            state = .fixed
            failureCount = 0
            saveLastFixed(coordinate)
            keepAlive.startAll()
            startTicking()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .failure(let e):
            state = fixedCoordinate == nil ? .idle : .failed(e.localizedDescription)
            errorMessage = e.localizedDescription
        }
    }

    func release() async {
        stopMoving()
        stopTicking()
        cancelReleaseTimer()
        state = .connecting
        let result = await engine.clear()
        keepAlive.stopAudio()
        fixedCoordinate = nil
        routeLine = []
        UserDefaults.standard.removeObject(forKey: Self.lastFixedKey)
        state = .idle
        if case .failure(let e) = result, e != .notConnected {
            errorMessage = e.localizedDescription
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// 前回固定していた地点(アプリが落ちた後の再固定用)
    var lastFixed: CLLocationCoordinate2D? {
        guard let a = UserDefaults.standard.array(forKey: Self.lastFixedKey) as? [Double], a.count == 2 else { return nil }
        return .init(latitude: a[0], longitude: a[1])
    }

    private func saveLastFixed(_ c: CLLocationCoordinate2D) {
        UserDefaults.standard.set([c.latitude, c.longitude], forKey: Self.lastFixedKey)
    }

    /// 揺らぎを足して送る
    private func send(_ center: CLLocationCoordinate2D, pairing: PairingStore) async -> Result<Void, EngineError> {
        let c = Geo.offset(center, east: jitterOffset.east, north: jitterOffset.north)
        return await engine.set(latitude: c.latitude, longitude: c.longitude,
                                pairingPath: pairing.path, deviceIP: LocalDevVPN.targetIP)
    }

    // MARK: - 維持(数秒ごとに送り直す。揺らぎ・自動解除の確認もここで行う)

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() async {
        // 自動解除
        if let releaseAt, Date() >= releaseAt {
            await release()
            notify(title: "位置の固定を自動で解除しました", body: "本当の位置に戻っています。")
            return
        }
        // 移動中は移動タスクが送信する
        guard let c = fixedCoordinate, let pairing, !isMoving, !busy, state != .connecting else { return }
        busy = true
        defer { busy = false }
        refreshVPN()
        updateJitter()
        let result = await send(c, pairing: pairing)
        guard fixedCoordinate != nil else { return }  // 途中で解除された
        handleSendResult(result)
    }

    private func handleSendResult(_ result: Result<Void, EngineError>) {
        switch result {
        case .success:
            failureCount = 0
            state = .fixed
        case .failure(let e):
            failureCount += 1
            state = .reconnecting
            if failureCount == 3 {
                state = .failed(e.localizedDescription)
                notify(title: "位置の固定が切れた可能性があります",
                       body: "PitaLoc を開いて確認してください。LocalDevVPN が切れていないかも確認してください。")
            }
        }
    }

    /// 静止した GPS のように、中心のまわりを少しずつランダムに漂わせる
    private func updateJitter() {
        guard jitterEnabled, jitterMeters > 0 else {
            jitterOffset = (0, 0)
            return
        }
        let r = jitterMeters
        var e = jitterOffset.east + Double.random(in: -r...r) * 0.4
        var n = jitterOffset.north + Double.random(in: -r...r) * 0.4
        let d = hypot(e, n)
        if d > r { e *= r / d; n *= r / d }
        jitterOffset = (e, n)
    }

    // MARK: - 自動解除タイマー

    func setReleaseTimer(minutes: Int?) {
        cancelReleaseTimer()
        guard let minutes, minutes > 0 else { return }
        releaseAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func cancelReleaseTimer() {
        releaseAt = nil
    }

    // MARK: - 移動シミュレーション

    /// 今の場所から destination まで、道路に沿って(道が見つからなければ直線で)移動する
    func move(to destination: CLLocationCoordinate2D, pairing: PairingStore) async {
        guard let start = fixedCoordinate else {
            await fix(at: destination, pairing: pairing)
            return
        }
        self.pairing = pairing
        stopMoving()
        isPreparingRoute = true
        let path = await Self.routePath(from: start, to: destination, mode: travelMode)
        isPreparingRoute = false
        guard path.count >= 2 else { return }

        routeLine = path
        isMoving = true
        moveProgress = 0
        let mode = travelMode
        moveTask = Task { [weak self] in
            await self?.runMove(path: path, mode: mode, pairing: pairing)
        }
    }

    func stopMoving() {
        moveTask?.cancel()
        moveTask = nil
        isMoving = false
        isPreparingRoute = false
        moveProgress = 0
        moveRemainingSeconds = 0
    }

    private func runMove(path: [CLLocationCoordinate2D], mode: TravelMode, pairing: PairingStore) async {
        // 区間ごとの累積距離
        var cumulative: [Double] = [0]
        for i in 1..<path.count {
            cumulative.append(cumulative[i - 1] + Geo.distance(path[i - 1], path[i]))
        }
        let total = max(cumulative.last ?? 0, 0.1)
        var travelled = 0.0
        let step: TimeInterval = 1.0
        jitterOffset = (0, 0)

        while travelled < total, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            if Task.isCancelled { break }
            let speed = mode.speed * Double.random(in: 0.85...1.15)
            travelled = min(total, travelled + speed * step)
            let point = Geo.point(along: path, cumulative: cumulative, distance: travelled)
            fixedCoordinate = point
            moveProgress = travelled / total
            moveRemainingSeconds = (total - travelled) / mode.speed
            let result = await engine.set(latitude: point.latitude, longitude: point.longitude,
                                          pairingPath: pairing.path, deviceIP: LocalDevVPN.targetIP)
            handleSendResult(result)
        }

        if !Task.isCancelled, let last = path.last {
            fixedCoordinate = last
            saveLastFixed(last)
            notify(title: "目的地に着きました", body: "その場所で固定しています。")
        } else if let c = fixedCoordinate {
            saveLastFixed(c)
        }
        isMoving = false
        moveProgress = 0
        moveRemainingSeconds = 0
        routeLine = []
    }

    private static func routePath(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                                  mode: TravelMode) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = mode.transportType
        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            let polyline = route.polyline
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                  count: polyline.pointCount)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
            if coords.count >= 2 { return [from] + coords + [to] }
        }
        return [from, to]  // 道が見つからないときは直線
    }

    // MARK: - 通知

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - お気に入り

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty
            ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            : trimmed
        favorites.insert(Place(name: label, latitude: coordinate.latitude, longitude: coordinate.longitude), at: 0)
        saveFavorites()
    }

    func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }

    func moveFavorites(from: IndexSet, to: Int) {
        favorites.move(fromOffsets: from, toOffset: to)
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }
}

/// 距離計算などの小道具
enum Geo {
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func offset(_ c: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        guard east != 0 || north != 0 else { return c }
        let earth = 6_378_137.0
        let dLat = north / earth * 180 / .pi
        let dLon = east / (earth * cos(c.latitude * .pi / 180)) * 180 / .pi
        return .init(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    static func point(along path: [CLLocationCoordinate2D], cumulative: [Double],
                      distance d: Double) -> CLLocationCoordinate2D {
        guard let last = path.last else { return kCLLocationCoordinate2DInvalid }
        for i in 1..<path.count where cumulative[i] >= d {
            let segment = cumulative[i] - cumulative[i - 1]
            let t = segment > 0 ? (d - cumulative[i - 1]) / segment : 1
            let a = path[i - 1], b = path[i]
            return .init(latitude: a.latitude + (b.latitude - a.latitude) * t,
                         longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        return last
    }
}
