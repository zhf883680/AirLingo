import Foundation
import Combine

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var config: AppConfig {
        didSet { scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AirLingo", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: support.appendingPathComponent("config.json")),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }
        migrate()
    }

    /// 老配置文件里没有新加的引擎，补上，避免升级后看不到 Apple 系统翻译。
    private func migrate() {
        let missing = EngineProfile.defaults.filter { fallback in
            !config.engines.contains(where: { $0.id == fallback.id })
        }
        if !missing.isEmpty {
            config.engines.append(contentsOf: missing)
        }
        // 对比翻译至少要两个引擎，只勾了一个（或历史默认只有一个）时自动补齐。
        let configured = config.compareEngineIDs.filter { id in
            config.engine(id: id)?.isReady == true
        }
        if configured.count < 2 {
            let ready = config.engines.filter(\.isReady).prefix(3).map(\.id)
            if ready.count > configured.count {
                config.compareEngineIDs = Array(ready)
            }
        }
    }

    /// 对比翻译实际使用的引擎：勾选且可用的；不足两个就退化为全部可用引擎。
    var compareEngines: [EngineProfile] {
        let chosen = config.compareEngineIDs
            .compactMap { config.engine(id: $0) }
            .filter(\.isReady)
        if chosen.count >= 2 { return chosen }
        return Array(usableEngines.prefix(4))
    }

    func scheduleSave() {
        saveTask?.cancel()
        let snapshot = config
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("AirLingo: 配置保存失败 \(error.localizedDescription)")
            }
        }
    }

    var usableEngines: [EngineProfile] {
        config.engines.filter { $0.isReady }
    }

    func engine(for feature: Feature) -> EngineProfile? {
        guard let profile = config.engine(for: feature), profile.isReady else {
            return usableEngines.first ?? config.engines.first
        }
        return profile
    }

    func setEngine(_ id: String, for feature: Feature) {
        switch feature {
        case .translate: config.translateEngineID = id
        case .silent: config.silentEngineID = id
        case .ocr: config.ocrEngineID = id
        }
    }

    func targetLanguage(for text: String) -> String {
        let dominant = LanguageHint.dominant(of: text)
        if dominant == AppLanguage.base(config.nativeLang) {
            return config.learnLang
        }
        return config.nativeLang
    }

    var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AirLingo", isDirectory: true)
    }
}
