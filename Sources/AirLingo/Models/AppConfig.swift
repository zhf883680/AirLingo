import Foundation

// MARK: - 引擎

enum EngineKind: String, Codable, CaseIterable, Identifiable {
    case apple
    case google
    case openai
    case deepl
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple 系统翻译"
        case .google: return "Google 翻译"
        case .openai: return "OpenAI 兼容"
        case .deepl: return "DeepL"
        case .ollama: return "本地 Ollama"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: return "系统内置，全程离线不出本机"
        case .google: return "内置免费接口，无需配置"
        case .openai: return "OpenAI / DeepSeek / 通义 / Kimi 等"
        case .deepl: return "术语稳定，支持 Free 与 Pro"
        case .ollama: return "完全离线，本机模型"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .apple: return ""
        case .google: return "https://translate.googleapis.com"
        case .openai: return "https://api.openai.com/v1"
        case .deepl: return "https://api-free.deepl.com/v2"
        case .ollama: return "http://127.0.0.1:11434"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .ollama: return "qwen2.5:7b"
        default: return ""
        }
    }

    var needsKey: Bool {
        self == .openai || self == .deepl
    }

    var isLocal: Bool {
        self == .apple || self == .ollama
    }

    var iconName: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "globe"
        case .openai: return "sparkles"
        case .deepl: return "character.book.closed"
        case .ollama: return "desktopcomputer"
        }
    }
}

struct EngineProfile: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var kind: EngineKind
    var baseURL: String
    var apiKey: String
    var model: String
    var enabled: Bool

    init(id: String = UUID().uuidString,
         name: String,
         kind: EngineKind,
         baseURL: String? = nil,
         apiKey: String = "",
         model: String? = nil,
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.apiKey = apiKey
        self.model = model ?? kind.defaultModel
        self.enabled = enabled
    }

    var isReady: Bool {
        guard enabled else { return false }
        if kind == .apple {
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
        }
        if kind.needsKey && apiKey.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if kind == .openai && model.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    static var defaults: [EngineProfile] {
        [
            EngineProfile(id: "apple", name: "Apple 系统翻译", kind: .apple, enabled: true),
            EngineProfile(id: "google", name: "Google（免费）", kind: .google, enabled: true),
            EngineProfile(id: "openai", name: "OpenAI 兼容", kind: .openai, enabled: false),
            EngineProfile(id: "deepl", name: "DeepL", kind: .deepl, enabled: false),
            EngineProfile(id: "ollama", name: "本地 Ollama", kind: .ollama, enabled: false)
        ]
    }

    static var appleDefault: EngineProfile {
        EngineProfile(id: "apple", name: "Apple 系统翻译", kind: .apple, enabled: true)
    }
}

// MARK: - 快捷键

struct ShortcutMap: Codable, Equatable {
    var translate: String = "double:ctrl"
    var silent: String = "double:alt"
    var ocr: String = "Alt+Cmd+O"
    var compare: String = "Ctrl+T"

    static let labels: [(key: String, title: String, hint: String)] = [
        ("translate", "划词翻译", "选中文字后浮窗出译文"),
        ("silent", "静默替换", "译文直接写回输入框"),
        ("ocr", "截图翻译", "框选屏幕区域取字翻译"),
        ("compare", "对比翻译", "多引擎同时翻译")
    ]
}

// MARK: - 配置

struct AppConfig: Codable {
    var nativeLang: String = "zh-CN"
    var learnLang: String = "en"
    var theme: String = "system"
    var uiScale: Double = 1.0
    var shortcuts: ShortcutMap = ShortcutMap()
    var engines: [EngineProfile] = EngineProfile.defaults
    var translateEngineID: String = "google"
    var silentEngineID: String = "google"
    var ocrEngineID: String = "google"
    var compareEngineIDs: [String] = ["apple", "google"]
    var replaceInPlace: Bool = true
    var autoCopy: Bool = false
    var keepHistory: Bool = true
    var showOriginal: Bool = true
    var speechRate: Double = 1.0
    var onboardingCompleted: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case nativeLang, learnLang, theme, uiScale, shortcuts, engines
        case translateEngineID, silentEngineID, ocrEngineID, compareEngineIDs
        case replaceInPlace, autoCopy, keepHistory, showOriginal, speechRate, onboardingCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nativeLang = c.value(.nativeLang, "zh-CN")
        learnLang = c.value(.learnLang, "en")
        theme = c.value(.theme, "system")
        uiScale = c.value(.uiScale, 1.0)
        shortcuts = c.value(.shortcuts, ShortcutMap())
        engines = c.value(.engines, EngineProfile.defaults)
        translateEngineID = c.value(.translateEngineID, "google")
        silentEngineID = c.value(.silentEngineID, "google")
        ocrEngineID = c.value(.ocrEngineID, "google")
        compareEngineIDs = c.value(.compareEngineIDs, ["apple", "google"])
        replaceInPlace = c.value(.replaceInPlace, true)
        autoCopy = c.value(.autoCopy, false)
        keepHistory = c.value(.keepHistory, true)
        showOriginal = c.value(.showOriginal, true)
        speechRate = c.value(.speechRate, 1.0)
        onboardingCompleted = c.value(.onboardingCompleted, false)
    }

    func engine(id: String) -> EngineProfile? {
        engines.first(where: { $0.id == id })
    }

    func engine(for feature: Feature) -> EngineProfile? {
        switch feature {
        case .translate: return engine(id: translateEngineID)
        case .silent: return engine(id: silentEngineID)
        case .ocr: return engine(id: ocrEngineID)
        }
    }
}

enum Feature: String, CaseIterable {
    case translate, silent, ocr

    var title: String {
        switch self {
        case .translate: return "划词翻译"
        case .silent: return "静默替换"
        case .ocr: return "截图 OCR"
        }
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - 语言

struct AppLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [AppLanguage] = [
        .init(code: "zh-CN", name: "简体中文"),
        .init(code: "zh-TW", name: "繁體中文"),
        .init(code: "en", name: "English"),
        .init(code: "ja", name: "日本語"),
        .init(code: "ko", name: "한국어"),
        .init(code: "fr", name: "Français"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "es", name: "Español"),
        .init(code: "ru", name: "Русский"),
        .init(code: "pt", name: "Português"),
        .init(code: "it", name: "Italiano"),
        .init(code: "ar", name: "العربية"),
        .init(code: "th", name: "ไทย"),
        .init(code: "vi", name: "Tiếng Việt")
    ]

    static func name(for code: String) -> String {
        all.first(where: { $0.code == code })?.name ?? code
    }

    static func base(_ code: String) -> String {
        String(code.split(separator: "-").first ?? "")
    }
}

enum LanguageHint {
    /// 粗略判断文本主语言，用于决定译到母语还是学习语言。
    static func dominant(of text: String) -> String {
        let scalars = text.unicodeScalars
        var han = 0, kana = 0, hangul = 0, cyrillic = 0, latin = 0
        for s in scalars {
            switch s.value {
            case 0x4E00...0x9FFF: han += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF: hangul += 1
            case 0x0400...0x04FF: cyrillic += 1
            case 0x41...0x7A: latin += 1
            default: break
            }
        }
        if kana > 0 { return "ja" }
        if hangul > 0 { return "ko" }
        if han > latin { return "zh" }
        if cyrillic > 0 { return "ru" }
        if latin > 0 { return "en" }
        return "unknown"
    }
}
