import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var spoof: SpoofController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pitaloc.tunnelIP") private var tunnelIP = LocalDevVPN.defaultIP
    @AppStorage("pitaloc.setupDone") private var setupDone = false
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("ペアリングファイル") {
                    LabeledContent("状態", value: pairing.hasPairingFile ? "読み込み済み" : "未設定")
                    Button("ファイルを選び直す") { showImporter = true }
                    Button("クリップボードから貼り付け") {
                        do { try pairing.importFromClipboard(); message = "読み込みました。" }
                        catch { message = error.localizedDescription }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    LabeledContent("状態", value: spoof.vpnConnected ? "接続済み" : "未接続")
                    Button("LocalDevVPN を開く") { LocalDevVPN.connect() }
                    HStack {
                        Text("トンネルIP")
                        TextField(LocalDevVPN.defaultIP, text: $tunnelIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("LocalDevVPN")
                } footer: {
                    Text("トンネルIPは通常 10.7.0.1 のままで大丈夫です。")
                }

                Section {
                    Button("最初の準備画面をもう一度見る") {
                        setupDone = false
                        dismiss()
                    }
                } footer: {
                    Text("iOSをアップデートした後に動かなくなったら、Windows の idevice_pair でペアリングファイルを作り直してください。")
                }

                Section("このアプリについて") {
                    Text("位置の固定には、Apple が開発者向けに用意している位置シミュレーション機能を使います。iPhoneを再起動すると必ず本当の位置に戻ります。")
                        .font(.footnote)
                    Text("ゲームや出退勤アプリなどで使うと、利用規約違反になることがあります。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("使用ライブラリ:idevice (MIT, jkcoxson)。接続方法は Locus (MIT) を参考にしています。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        spoof.refreshVPN()
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PairingStore.importTypes) { result in
            switch result {
            case .success(let url):
                do {
                    try pairing.importFile(from: url)
                    message = "読み込みました。"
                    Task { await LocationEngine.shared.disconnect() }
                } catch { message = error.localizedDescription }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }
}
