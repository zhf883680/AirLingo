import Foundation
import Combine

struct HistoryItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var source: String
    var target: String
    var engine: String
    var from: String
    var to: String
    var date: Date = Date()
    var favorite: Bool = false
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []

    private let fileURL: URL
    private let limit = 800

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AirLingo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        }
    }

    @discardableResult
    func add(source: String, target: String, engine: String, from: String, to: String, force: Bool = false) -> HistoryItem? {
        guard force || ConfigStore.shared.config.keepHistory else { return nil }
        // 一分钟内重复翻译同一句（比如点「重新翻译」）不重复记录
        if !force, let first = items.first, first.source == source, first.target == target,
           first.engine == engine, Date().timeIntervalSince(first.date) < 60 {
            return first
        }
        let item = HistoryItem(source: source, target: target, engine: engine, from: from, to: to)
        items.insert(item, at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
        save()
        return item
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].favorite.toggle()
        save()
    }

    func isFavorite(source: String, target: String) -> Bool {
        items.contains { $0.favorite && $0.source == source && $0.target == target }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func clearFavorites() {
        for index in items.indices { items[index].favorite = false }
        save()
    }

    var favorites: [HistoryItem] {
        items.filter(\.favorite)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("AirLingo: 历史保存失败 \(error.localizedDescription)")
        }
    }
}
