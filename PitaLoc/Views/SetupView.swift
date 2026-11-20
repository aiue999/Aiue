import CoreLocation
import SwiftUI

/// 初回だけ表示する3ステップの準備画面
struct SetupView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var spoof: SpoofController
    @AppStorage("pitaloc.setupDone") private var setupDone = false
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("最初の準備は1回だけです。上から順に進めてください。")
                        .foregroundStyle(.secondary)

                    StepCard(number: 1, title: "デベロッパモードをオン", done: nil) {
                        Text("設定 → プライバシーとセキュリティ → デベロッパモード をオンにして再起動します。(PCでのペアリング前に済ませておく必要があります)")
                    }

                    StepCard(number: 2, title: "ペアリングファイルを読み込む", done: pairing.hasPairingFile) {
                        Text("Windows の idevice_pair で作った「RPPairing」ファイルを、メールや iCloud Drive でこの iPhone に送り、下のボタンで選びます。")
                        HStack {
                            Button { showImporter = true } label: {
                                Label("ファイルを選ぶ", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                do { try pairing.importFromClipboard(); message = nil }
                                catch { message = error.localizedDescription }
                            } label: {
                                Label("貼り付け", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    StepCard(number: 3, title: "LocalDevVPN を接続", done: spoof.vpnConnected) {
                        Text("App Store の無料アプリ「LocalDevVPN」を入れて接続します。iPhone が自分自身と通信するためのもので、外部には通信しません。")
                        Button {
                            LocalDevVPN.connect()
                        } label: {
                            Label(LocalDevVPN.isInstalled ? "VPNを接続" : "App Storeで入手", systemImage: "network")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("状態を再確認") { spoof.refreshVPN() }
                            .font(.footnote)
                    }

                    StepCard(number: 4, title: "位置情報を許可", done: nil) {
                        Text("固定中にアプリが止まらないよう、位置情報を使います。「Appの使用中は許可」を選んでください。")
                        Button("許可する") { spoof.keepAlive.requestPermission() }
                            .buttonStyle(.bordered)
                    }

                    if let message {
                        Text(message).foregroundStyle(.red).font(.footnote)
                    }

                    Button {
                        setupDone = true
                    } label: {
                        Text("はじめる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!pairing.hasPairingFile)
                    .padding(.top, 8)

                    if !pairing.hasPairingFile {
                        Text("ステップ2が終わると押せるようになります。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("PitaLoc の準備")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PairingStore.importTypes) { result in
            switch result {
            case .success(let url):
                do { try pairing.importFile(from: url); message = nil }
                catch { message = error.localizedDescription }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .onAppear { spoof.refreshVPN() }
    }
}

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    /// nil = 自動判定できない項目
    let done: Bool?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(number)")
                    .font(.headline)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(done == true ? Color.green : Color.accentColor))
                    .foregroundStyle(.white)
                Text(title).font(.headline)
                Spacer()
                if done == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if done == false {
                    Text("未完了").font(.caption).foregroundStyle(.orange)
                }
            }
            content
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
