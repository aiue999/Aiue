import MapKit
import SwiftUI

/// 地名・住所・「35.68, 139.76」形式の座標で検索
struct SearchSheet: View {
    var onSelect: (String, CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    @State private var note: String?

    struct SearchResult: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            List {
                if let coord = Self.parseCoordinate(query) {
                    Button {
                        choose(String(format: "%.5f, %.5f", coord.latitude, coord.longitude), coord)
                    } label: {
                        Label("座標 \(String(format: "%.5f, %.5f", coord.latitude, coord.longitude)) を選ぶ",
                              systemImage: "scope")
                    }
                }
                ForEach(results) { r in
                    Button { choose(r.name, r.coordinate) } label: {
                        VStack(alignment: .leading) {
                            Text(r.name).foregroundStyle(.primary)
                            if !r.detail.isEmpty {
                                Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if searching { ProgressView() }
                if let note { Text(note).foregroundStyle(.secondary) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "例:大阪大学、東京駅、35.68, 139.76")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("場所を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func choose(_ name: String, _ c: CLLocationCoordinate2D) {
        onSelect(name, c)
        dismiss()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, Self.parseCoordinate(q) == nil else { return }
        searching = true
        note = nil
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map {
                SearchResult(name: $0.name ?? q,
                       detail: $0.placemark.title ?? "",
                       coordinate: $0.placemark.coordinate)
            }
            if results.isEmpty { note = "見つかりませんでした。" }
        } catch {
            results = []
            note = "見つかりませんでした。"
        }
    }

    /// "35.6812, 139.7671" や "35.6812 139.7671" を座標として読む
    static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text
            .replacingOccurrences(of: "、", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
}
