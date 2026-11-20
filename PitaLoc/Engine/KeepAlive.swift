import AVFoundation
import CoreLocation
import Foundation

/// 固定中にアプリが止められないようにする(無音オーディオ + 位置情報のバックグラウンド更新)。
/// 接続が切れると位置が元に戻るため。仕組みは Locus (MIT) を参考にしている。
final class KeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var player: AVAudioPlayer?
    private(set) var lastCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startLocation() {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
    }

    func startAll() {
        startLocation()
        startAudio()
    }

    func stopAudio() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastCoordinate = locations.last?.coordinate
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        }
    }

    private func startAudio() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: Self.silentWAV())
            p.numberOfLoops = -1
            p.volume = 0.0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            NSLog("[PitaLoc] keep-alive audio failed: \(error)")
        }
    }

    /// 0.5秒の無音 WAV を作る
    private static func silentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pitaloc-silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let rate = 8000
        let samples = rate / 2
        let dataSize = UInt32(samples * 2)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        try d.write(to: url, options: .atomic)
        return url
    }
}
