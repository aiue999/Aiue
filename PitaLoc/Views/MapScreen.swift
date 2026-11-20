import MapKit
import SwiftUI

/// メイン画面
/// - 未固定: 地図をタップ → 「ここに固定」
/// - 固定中: 地図をタップ → 「ここへ移動」(徒歩/自転車/車) か 「瞬間移動」
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
    @State private var showCustomTimer = false
    @State private var customMinutes = 90

    /// 固定中に地図をタップして選んだ移動先
    private var destination: CLLocationCoordinate2D? {
        guard spoof.isFixed, let pin, let current = spoof.fixedCoordinate,
              Geo.distance(pin, current) > 5 else { return nil }
        return pin
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if spoof.routeLine.count >= 2 {
                        MapPolyline(coordinates: spoof.routeLine)
                            .stroke(.orange, lineWidth: 5)
                    }
                    if let current = spoof.fixedCoordinate {
                        Annotation("", coordinate: current, anchor: .bottom) {
                            pinImage(color: .red)
                        }
                    }
                    if let p = spoof.isFixed ? destination : pin {
                        Annotation(pinName ?? "", coordinate: p, anchor: .bottom) {
                            pinImage(color: spoof.isFixed ? .orange : .blue)
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { point in
                    guard !spoof.isMoving, let c = proxy.convert(point, from: .local) else { return }
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
                if let c = destination ?? pin ?? spoof.fixedCoordinate {
                    spoof.addFavorite(name: favoriteName, coordinate: c)
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("自動解除までの時間(分)", isPresented: $showCustomTimer) {
            TextField("分", value: $customMinutes, format: .number)
                .keyboardType(.numberPad)
            Button("設定") { spoof.setReleaseTimer(minutes: customMinutes) }
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
        .onChange(of: spoof.isFixed) { _, fixed in
            // 固定した/解除したら、移動先のピンはいったん消す
            if fixed, let c = spoof.fixedCoordinate { pin = c } else if !fixed { pin = nil }
        }
    }

    private func pinImage(color: Color) -> some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 40))
            .foregroundStyle(Color.white, color)
            .shadow(radius: 3)
    }

    // MARK: - 上部

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { showSearch = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(spoof.isFixed ? "移動先を検索" : "場所・住所・座標で検索")
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.regularMaterial, in: Capsule())
            }
            .disabled(spoof.isMoving)

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

            if spoof.isMoving {
                movingControls
            } else if spoof.isFixed {
                fixedControls
            } else {
                idleControls
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // 未固定
    @ViewBuilder
    private var idleControls: some View {
        bigButton(pin == nil ? "地図をタップして場所を選ぶ" : "ここに固定",
                  icon: "location.fill", color: .blue) {
            guard let pin else { return }
            Task { await spoof.fix(at: pin, pairing: pairing) }
        }
        .disabled(pin == nil || spoof.isBusy)

        HStack {
            if pin == nil, let last = spoof.lastFixed {
                Button("前回の場所をもう一度固定") {
                    select(last, name: "前回の場所")
                    Task { await spoof.fix(at: last, pairing: pairing) }
                }
            }
            Spacer()
            if pin != nil { favoriteButton }
        }
        .font(.footnote)
    }

    // 固定中
    @ViewBuilder
    private var fixedControls: some View {
        if let dest = destination {
            Picker("移動手段", selection: $spoof.travelMode) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                bigButton("ここへ移動", icon: spoof.travelMode.icon, color: .orange) {
                    Task { await spoof.move(to: dest, pairing: pairing) }
                }
                .disabled(spoof.isBusy)
                Button {
                    Task { await spoof.fix(at: dest, pairing: pairing) }
                } label: {
                    Label("瞬間移動", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(spoof.isBusy)
            }
            Text("約\(Int(Geo.distance(spoof.fixedCoordinate ?? dest, dest)))m 先(直線距離)。ピンを外すには「固定を解除」か、今の場所をタップ。")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("地図をタップすると、そこへ移動できます。")
                .font(.caption).foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
            timerMenu
            bigButton("固定を解除", icon: "location.slash.fill", color: .red) {
                Task { await spoof.release() }
            }
        }
        HStack {
            Spacer()
            favoriteButton
        }
        .font(.footnote)
    }

    // 移動中
    @ViewBuilder
    private var movingControls: some View {
        ProgressView(value: spoof.moveProgress)
            .tint(.orange)
        HStack(spacing: 10) {
            bigButton("ここで止まる", icon: "pause.fill", color: .orange) {
                spoof.stopMoving()
            }
            timerMenu
        }
    }

    private var timerMenu: some View {
        Menu {
            if spoof.releaseAt != nil {
                Button("タイマーを取り消す", role: .destructive) { spoof.cancelReleaseTimer() }
            }
            ForEach([15, 30, 60, 120, 180], id: \.self) { m in
                Button(m < 60 ? "\(m)分後に解除" : "\(m / 60)時間後に解除") {
                    spoof.setReleaseTimer(minutes: m)
                }
            }
            Button("時間を指定…") { showCustomTimer = true }
        } label: {
            Image(systemName: spoof.releaseAt == nil ? "timer" : "timer.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 48)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var favoriteButton: some View {
        Button {
            favoriteName = pinName ?? ""
            showSaveFavorite = true
        } label: {
            Label("お気に入りに追加", systemImage: "star")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                switch spoof.state {
                case .idle:
                    Circle().fill(.gray).frame(width: 10, height: 10)
                    Text("固定していません(本当の位置)")
                case .connecting:
                    ProgressView()
                    Text("接続中…")
                case .fixed:
                    Circle().fill(spoof.isMoving ? Color.orange : Color.red).frame(width: 10, height: 10)
                    if spoof.isMoving {
                        Text("\(spoof.travelMode.title)で移動中(あと約\(minutesText(spoof.moveRemainingSeconds)))")
                    } else {
                        Text("固定中:\(label(for: spoof.fixedCoordinate))")
                    }
                case .reconnecting:
                    ProgressView()
                    Text("再接続中…")
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text("固定が切れた可能性があります。もう一度「解除」→「固定」してください。")
                }
                Spacer(minLength: 0)
            }
            if spoof.isPreparingRoute {
                Text("ルートを検索しています…").font(.caption).foregroundStyle(.secondary)
            }
            if let releaseAt = spoof.releaseAt {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(releaseAt, style: .relative)
                    Text("後に自動で解除(\(releaseAt.formatted(date: .omitted, time: .shortened)))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
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
        if let pinName, !pinName.isEmpty, destination == nil { return pinName }
        guard let c else { return "" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    private func minutesText(_ seconds: Double) -> String {
        let m = Int(ceil(seconds / 60))
        return m < 60 ? "\(m)分" : "\(m / 60)時間\(m % 60)分"
    }
}
