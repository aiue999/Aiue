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
                // pitaloc:// で LocalDevVPN から戻ってきた場合
                spoof.refreshVPN()
            }
            .onAppear {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { spoof.refreshVPN() }
            }
        }
    }
}
