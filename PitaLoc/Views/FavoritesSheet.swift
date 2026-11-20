import SwiftUI

/// お気に入り一覧:タップするとその場所にすぐ固定
struct FavoritesSheet: View {
    var onPick: (Place) -> Void
    @EnvironmentObject private var spoof: SpoofController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if spoof.favorites.isEmpty {
                    ContentUnavailableView("お気に入りはまだありません",
                                           systemImage: "star",
                                           description: Text("地図で場所を選んで「お気に入りに追加」を押すと、ここからワンタップで固定できます。"))
                } else {
                    List {
                        Section {
                            ForEach(spoof.favorites) { place in
                                Button {
                                    onPick(place)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                        VStack(alignment: .leading) {
                                            Text(place.name).foregroundStyle(.primary)
                                            Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .disabled(spoof.isFixed)
                            }
                            .onDelete { spoof.deleteFavorites(at: $0) }
                            .onMove { spoof.moveFavorites(from: $0, to: $1) }
                        } footer: {
                            Text("タップするとその場所に固定します。左にスワイプで削除。")
                        }
                    }
                }
            }
            .navigationTitle("お気に入り")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                if !spoof.favorites.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
            .safeAreaInset(edge: .top) {
                if spoof.isFixed {
                    Text("固定中は選べません。先にメイン画面で「固定を解除」してください。")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
        }
    }
}
