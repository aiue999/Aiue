import CoreLocation
import Foundation
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

/// 「固定」「解除」とお気に入りを管理する
@MainActor
final class SpoofController: ObservableObject {
    @Published private(set) var state: SpoofState = .idle
    @Published private(set) var fixedCoordinate: CLLocationCoordinate2D?
    @Published var errorMessage: String?
    @Published private(set) var favorites: [Place] = []
    @Published private(set) var vpnConnected = false

    let keepAlive = KeepAlive()
    private let engine = LocationEngine.shared
    private var resendTimer: Timer?
    private var failureCount = 0
    private var busy = false

    private static let favoritesKey = "pitaloc.favorites"
    private static let lastFixedKey = "pitaloc.lastFixed"

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

    var isBusy: Bool { state == .connecting }

    func refreshVPN() {
        vpnConnected = LocalDevVPN.isConnected
    }

    // MARK: - 固定 / 解除

    func fix(at coordinate: CLLocationCoordinate2D, pairing: PairingStore) async {
        guard pairing.hasPairingFile else {
            errorMessage = "先にペアリングファイルを読み込んでください(設定 ⚙︎)。"
            return
        }
        refreshVPN()
        guard vpnConnected else {
            errorMessage = "LocalDevVPN が接続されていません。下の「VPNを接続」を押してから、もう一度お試しください。"
            return
        }
        state = .connecting
        errorMessage = nil
        let result = await engine.set(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                      pairingPath: pairing.path, deviceIP: LocalDevVPN.targetIP)
        switch result {
        case .success:
            fixedCoordinate = coordinate
            state = .fixed
            failureCount = 0
            saveLastFixed(coordinate)
            keepAlive.startAll()
            startResend(pairing: pairing)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .failure(let e):
            state = fixedCoordinate == nil ? .idle : .failed(e.localizedDescription)
            errorMessage = e.localizedDescription
        }
    }

    func release() async {
        stopResend()
        state = .connecting
        let result = await engine.clear()
        keepAlive.stopAudio()
        fixedCoordinate = nil
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

    // MARK: - 維持(定期的に同じ座標を送り直す。切れていたら自動で張り直す)

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.resendTick(pairing: pairing) }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func resendTick(pairing: PairingStore) async {
        guard let c = fixedCoordinate, !busy, state != .connecting else { return }
        busy = true
        defer { busy = false }
        refreshVPN()
        let result = await engine.set(latitude: c.latitude, longitude: c.longitude,
                                      pairingPath: pairing.path, deviceIP: LocalDevVPN.targetIP)
        // 解除が押されていたら何もしない
        guard fixedCoordinate != nil else { return }
        switch result {
        case .success:
            failureCount = 0
            state = .fixed
        case .failure(let e):
            failureCount += 1
            state = .reconnecting
            if failureCount == 3 {
                state = .failed(e.localizedDescription)
                notifyDropped(e.localizedDescription)
            }
        }
    }

    private func notifyDropped(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "位置の固定が切れた可能性があります"
        content.body = "PitaLoc を開いて確認してください。LocalDevVPN が切れていないかも確認してください。"
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
