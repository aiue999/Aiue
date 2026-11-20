import SwiftUI
import UserNotifications

@main
struct PitaLocApp: App {
    @StateObject private var pairing = PairingStore()
    @StateObject private var spoof = SpoofController()
    @AppStorage("pitaloc.setupDone") private var setupDone = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if setupDone && pairing.hasPairingFile {
                    MapScreen()
                } else {
                    SetupView()
                }
            }
            .environmentObject(pairing)
            .environmentObject(spoof)
            .onOpenURL { url in
                // ファイル(ペアリング)を「このアプリで開く」と渡された場合
                if url.isFileURL {
                    do { try pairing.importFile(from: url) }
                    catch { spoof.errorMessage = error.localizedDescription }
                }
                // pitaloc:// で LocalDevVPN から戻ってきた場合(接続完了まで少し待って再確認)
                spoof.refreshVPN()
                for delay in [1.5, 4.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { spoof.refreshVPN() }
                }
            }
            .onAppear {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { Provisioning.scheduleReminders() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    spoof.refreshVPN()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { spoof.refreshVPN() }
                }
            }
        }
    }
}
