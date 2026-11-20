import Darwin
import Foundation
import idevice

/// idevice FFI 経由で Apple の開発者向け位置シミュレーション (DVT) を呼び出す。
/// 接続手順は Locus (MIT) の LocationEngine を参考にしている。
enum EngineError: LocalizedError, Equatable {
    case invalidIP
    case pairingRead(String)
    case tunnel(String)
    case remoteServer(String)
    case simulation(String)
    case setFailed(String)
    case clearFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidIP:
            return "トンネルIPの形式が正しくありません(通常は 10.7.0.1)。"
        case .pairingRead(let m):
            return "ペアリングファイルを読み込めませんでした。idevice_pair で「RPPairing」形式を作り直してください。\n(\(m))"
        case .tunnel(let m):
            return "iPhone内部への接続に失敗しました。LocalDevVPN が「接続済み」になっているか、Wi‑Fi に繋がっているか確認してください。\n(\(m))"
        case .remoteServer(let m):
            return "接続はできましたが、開発者サービスとのやり取りに失敗しました。デベロッパモードがオンか確認してください。\n(\(m))"
        case .simulation(let m):
            return "位置シミュレーション機能を開けませんでした。\n(\(m))"
        case .setFailed(let m):
            return "位置の設定に失敗しました。\n(\(m))"
        case .clearFailed(let m):
            return "位置の解除に失敗しました。iPhoneを再起動すると確実に元に戻ります。\n(\(m))"
        case .notConnected:
            return "接続されていません。"
        }
    }
}

final class LocationEngine: @unchecked Sendable {
    static let shared = LocationEngine()

    /// RemotePairing のポート(LocalDevVPN のループバック先)
    private static let rpPort: UInt16 = 49152

    private let queue = DispatchQueue(label: "pitaloc.engine", qos: .userInitiated)

    // queue 上でのみ触る
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var simulation: OpaquePointer?

    private init() {}

    // MARK: - Public (async)

    func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, EngineError> {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: self.setLocked(latitude: latitude, longitude: longitude,
                                                      pairingPath: pairingPath, deviceIP: deviceIP))
            }
        }
    }

    func clear() async -> Result<Void, EngineError> {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.clearLocked()) }
        }
    }

    /// 接続を捨てる(次回 set で再接続される)
    func disconnect() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                self.cleanup()
                cont.resume()
            }
        }
    }

    // MARK: - Locked

    private func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, EngineError> {
        // 既存セッションがあればそのまま送る
        if let simulation {
            if let err = location_simulation_set(simulation, latitude, longitude) {
                idevice_error_free(err)
                cleanup() // 切れていたので張り直す
            } else {
                return .success(())
            }
        }

        if let failure = connectLocked(pairingPath: pairingPath, deviceIP: deviceIP) {
            cleanup()
            return .failure(failure)
        }

        if let err = location_simulation_set(simulation, latitude, longitude) {
            let m = Self.message(err)
            cleanup()
            return .failure(.setFailed(m))
        }
        return .success(())
    }

    private func clearLocked() -> Result<Void, EngineError> {
        guard let simulation else { return .failure(.notConnected) }
        let err = location_simulation_clear(simulation)
        cleanup()
        if let err {
            return .failure(.clearFailed(Self.message(err)))
        }
        return .success(())
    }

    /// 成功なら nil
    private func connectLocked(pairingPath: String, deviceIP: String) -> EngineError? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.rpPort.bigEndian
        let ok = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard ok == 1 else { return .invalidIP }

        var pairing: OpaquePointer?
        if let err = pairingPath.withCString({ rp_pairing_file_read($0, &pairing) }) {
            return .pairingRead(Self.message(err))
        }
        guard let pairing else { return .pairingRead("null") }
        defer { rp_pairing_file_free(pairing) }

        let tunnelErr: UnsafeMutablePointer<IdeviceFfiError>? = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                tunnel_create_rppairing(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    "PitaLoc",
                    pairing,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let tunnelErr { return .tunnel(Self.message(tunnelErr)) }

        if let err = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            return .remoteServer(Self.message(err))
        }
        if let err = location_simulation_new(remoteServer, &simulation) {
            return .simulation(Self.message(err))
        }
        return nil
    }

    /// 生成と逆順に解放する。LocationSimulation は RemoteServer を借用しているので先に解放。
    private func cleanup() {
        if let simulation { location_simulation_free(simulation); self.simulation = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }

    /// エラーメッセージを取り出して解放する
    private static func message(_ err: UnsafeMutablePointer<IdeviceFfiError>) -> String {
        let code = err.pointee.code
        var text = "code \(code)"
        if let m = err.pointee.message {
            text = "\(String(cString: m)) / code \(code)"
        }
        idevice_error_free(err)
        return text
    }
}
