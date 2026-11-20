import MapKit
import SwiftUI

/// メイン画面:地図をタップ → 「ここに固定」 → 「解除」
struct MapScreen: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var spoof: SpoofController

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pin: CLLocationCoordinate2D?
    @State private var pinName: String?
    @State private var showSearch = false
    @State private var showFavorites = false
    @State private var showSettings = false
    @State private var showSaveFavorite = false
    @State private var favoriteName = ""

    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if let pin {
                        Annotation(pinName ?? "", coordinate: pin, anchor: .bottom) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.white, spoof.isFixed ? Color.red : Color.blue)
                                .shadow(radius: 3)
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { point in
                    guard !spoof.isFixed, let c = proxy.convert(point, from: .local) else { return }
                    pin = c
                    pinName = nil
                }
            }
            .ignoresSafeArea()

            topBar
        }
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .sheet(isPresented: $showSearch) {
            SearchSheet { name, coordinate in
                select(coordinate, name: name)
            }
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesSheet { place in
                select(place.coordinate, name: place.name)
                Task { await spoof.fix(at: place.coordinate, pairing: pairing) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("お気に入りに追加", isPresented: $showSaveFavorite) {
            TextField("名前(例:自宅)", text: $favoriteName)
            Button("保存") {
                if let c = pin ?? spoof.fixedCoordinate {
                    spoof.addFavorite(name: favoriteName, coordinate: c)
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("うまくいきませんでした",
               isPresented: Binding(get: { spoof.errorMessage != nil },
                                    set: { if !$0 { spoof.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spoof.errorMessage ?? "")
        }
        .onAppear {
            spoof.keepAlive.startLocation()
            if let c = spoof.fixedCoordinate { pin = c }
        }
    }

    // MARK: - 上部

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { showSearch = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("場所・住所・座標で検索")
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.regularMaterial, in: Capsule())
            }
            .disabled(spoof.isFixed)

            circleButton("star.fill") { showFavorites = true }
            circleButton("gearshape.fill") { showSettings = true }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.regularMaterial, in: Circle())
        }
    }

    // MARK: - 下部パネル

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if !spoof.vpnConnected {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("LocalDevVPN が未接続です").font(.subheadline)
                    Spacer()
                    Button("VPNを接続") { LocalDevVPN.connect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            statusRow

            if spoof.isFixed {
                bigButton("固定を解除", icon: "location.slash.fill", color: .red) {
                    Task { await spoof.release() }
                }
            } else {
                bigButton(pin == nil ? "地図をタップして場所を選ぶ" : "ここに固定",
                          icon: "location.fill", color: .blue) {
                    guard let pin else { return }
                    Task { await spoof.fix(at: pin, pairing: pairing) }
                }
                .disabled(pin == nil || spoof.isBusy)

                if spoof.fixedCoordinate == nil, pin == nil, let last = spoof.lastFixed {
                    Button("前回の場所をもう一度固定") {
                        select(last, name: "前回の場所")
                        Task { await spoof.fix(at: last, pairing: pairing) }
                    }
                    .font(.footnote)
                }
            }

            if pin != nil || spoof.fixedCoordinate != nil {
                Button {
                    favoriteName = pinName ?? ""
                    showSaveFavorite = true
                } label: {
                    Label("この場所をお気に入りに追加", systemImage: "star")
                        .font(.footnote)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 10) {
            switch spoof.state {
            case .idle:
                Circle().fill(.gray).frame(width: 10, height: 10)
                Text("固定していません(本当の位置)")
            case .connecting:
                ProgressView()
                Text("接続中…")
            case .fixed:
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("固定中:\(label(for: spoof.fixedCoordinate))")
            case .reconnecting:
                ProgressView()
                Text("再接続中…")
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("固定が切れた可能性があります。もう一度「解除」→「固定」してください。")
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .lineLimit(2)
    }

    private func bigButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
    }

    // MARK: - helpers

    private func select(_ coordinate: CLLocationCoordinate2D, name: String?) {
        pin = coordinate
        pinName = name
        withAnimation {
            camera = .region(MKCoordinateRegion(center: coordinate,
                                                latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
    }

    private func label(for c: CLLocationCoordinate2D?) -> String {
        if let pinName, !pinName.isEmpty { return pinName }
        guard let c else { return "" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
