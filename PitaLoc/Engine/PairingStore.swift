import Foundation
import UIKit
import UniformTypeIdentifiers

/// RPPairing ファイル(idevice_pair で作る)をアプリ内に保存する
@MainActor
final class PairingStore: ObservableObject {
    @Published private(set) var hasPairingFile = false

    static let importTypes: [UTType] = {
        var types: [UTType] = [.propertyList, .xml, .data, .item]
        for ext in ["plist", "rppairing", "mobiledevicepairing"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }()

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent("rp_pairing_file.plist") }
    var path: String { fileURL.path }

    init() { refresh() }

    func refresh() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hasPairingFile = FileManager.default.fileExists(atPath: fileURL.path)
        if !hasPairingFile { importFromDocumentsFolder() }
    }

    /// Windows の「Apple デバイス」/iTunes のファイル共有でアプリの書類フォルダに
    /// 置かれたペアリングファイルを自動で取り込む
    private func importFromDocumentsFolder() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        for url in files where ["plist", "rppairing", "mobiledevicepairing"].contains(url.pathExtension.lowercased()) {
            if let data = try? Data(contentsOf: url), (try? install(data)) != nil {
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
    }

    func importFile(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try install(Data(contentsOf: url))
    }

    func importFromClipboard() throws {
        let board = UIPasteboard.general
        if let url = board.url, url.isFileURL {
            try importFile(from: url)
            return
        }
        let candidates: [Data?] = [
            board.data(forPasteboardType: UTType.propertyList.identifier),
            board.data(forPasteboardType: UTType.xml.identifier),
            board.string?.data(using: .utf8),
        ]
        guard let data = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw PairingError.emptyClipboard
        }
        try install(data)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        refresh()
    }

    private func install(_ data: Data) throws {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              obj is [String: Any] else {
            throw PairingError.invalid
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: fileURL)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        refresh()
    }
}

enum PairingError: LocalizedError {
    case emptyClipboard
    case invalid

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "クリップボードが空です。ペアリングファイルの中身をコピーしてからもう一度お試しください。"
        case .invalid:
            return "ペアリングファイルではないようです。idevice_pair で作った RPPairing ファイルを選んでください。"
        }
    }
}
