import AppKit
import Foundation
import NaturalLanguage
import SwiftUI
import Translation

// MARK: - 错误

enum AppleTranslateError: LocalizedError {
    case unsupportedOS
    case needsDownload(String)
    case timeout
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "系统翻译需要 macOS 15 或更高版本"
        case .needsDownload(let language):
            return "系统里还没就绪\(language)的语言包。请到「系统设置 › 通用 › 语言与地区 › 翻译语言」添加；如果已经装过，点弹窗上的「重试」或重启 AirLingo 让它重新加载"
        case .timeout:
            return "系统翻译超时，请重试"
        case .failed(let detail):
            return "系统翻译失败：\(detail)"
        }
    }
}

enum AppleLanguageStatus: Equatable {
    case installed
    case supported      // 系统支持，但语言包还没下载
    case unsupported
    case unknown

    var title: String {
        switch self {
        case .installed: return "已就绪"
        case .supported: return "待安装语言包"
        case .unsupported: return "不支持"
        case .unknown: return "检测中"
        }
    }
}

// MARK: - 离屏会话宿主

/// `TranslationSession` 没有公开构造器（macOS 26 的 installedSource 初始化要求语言包已安装），
/// 所以用一个 1×1 的透明窗口承载 `.translationTask`，从闭包里拿到会话。
@available(macOS 15.0, *)
@MainActor
final class AppleTranslationHostModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    var handler: ((TranslationSession) async -> Void)?
}

@available(macOS 15.0, *)
private struct AppleTranslationHostView: View {
    @ObservedObject var model: AppleTranslationHostModel

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .translationTask(model.configuration) { session in
                        await model.handler?(session)
                    }
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }
}

// MARK: - 服务

@available(macOS 15.0, *)
@MainActor
final class AppleTranslateService {
    static let shared = AppleTranslateService()

    private struct Job {
        let id: UUID
        let text: String
        let source: Locale.Language?
        let target: Locale.Language
        let prepareOnly: Bool
        let timeout: TimeInterval
        let completion: (Result<String, Error>) -> Void
    }

    private let hostModel = AppleTranslationHostModel()
    private var hostWindow: NSWindow?
    private var queue: [Job] = []
    private var current: Job?
    private var watchdog: Task<Void, Never>?

    /// 最近一次失败的原始描述，用来在设置页显示真实原因而不是笼统的「失败」。
    private(set) var lastFailure: String?

    private init() {}

    // MARK: 语言

    static func localeLanguage(_ code: String) -> Locale.Language {
        switch code {
        case "zh-CN", "zh-Hans", "zh": return Locale.Language(identifier: "zh-Hans")
        case "zh-TW", "zh-Hant": return Locale.Language(identifier: "zh-Hant")
        default: return Locale.Language(identifier: code)
        }
    }

    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let raw = language.rawValue
        // 中文要保留简繁：繁體和簡體是两套独立的语言包，混为一谈会报「语言包未安装」。
        if raw.lowercased().hasPrefix("zh") {
            let lower = raw.lowercased()
            if lower.contains("hant") || lower.contains("tw") || lower.contains("hk") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        return AppLanguage.base(raw)
    }

    private static func isSameLanguage(_ detected: String, _ target: String) -> Bool {
        AppLanguage.base(detected).lowercased() == AppLanguage.base(target).lowercased()
    }

    // MARK: 可用性

    private static func map(_ raw: LanguageAvailability.Status) -> AppleLanguageStatus {
        switch raw {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
    }

    /// 指定语言对的包状态（不带文本，不依赖自动识别）。
    func status(from source: String, to target: String) async -> AppleLanguageStatus {
        guard #available(macOS 15.0, *) else { return .unsupported }
        let availability = LanguageAvailability()
        let raw = await availability.status(from: Self.localeLanguage(source),
                                            to: Self.localeLanguage(target))
        return Self.map(raw)
    }

    func status(for text: String?, target: String) async -> AppleLanguageStatus {
        guard #available(macOS 15.0, *) else { return .unsupported }
        let targetLang = Self.localeLanguage(target)
        let availability = LanguageAvailability()
        var raw: LanguageAvailability.Status?
        if let text, !text.isEmpty {
            // 用文本自动识别源语言；识别不出来（例如只有数字、单个符号）时退回语言对判断，
            // 不能让「识别失败」直接变成「不支持」。
            raw = try? await availability.status(for: text, to: targetLang)
        }
        if raw == nil {
            let source = Self.localeLanguage(ConfigStore.shared.config.nativeLang)
            raw = await availability.status(from: source, to: targetLang)
        }
        return Self.map(raw ?? .unsupported)
    }

    /// 打开系统设置里的「语言与地区」，用户在那里安装翻译语言包。
    func openLanguageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.universalaccess?Languages"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// 显式请求安装语言包（用户点了按钮才会走到这里）。
    func prepare(source: String?, target: String) async throws {
        guard #available(macOS 15.0, *) else { throw AppleTranslateError.unsupportedOS }
        NSApp.activate(ignoringOtherApps: true)
        if current == nil { resetHost() }
        let sourceLang = source.map { Self.localeLanguage($0) }
        _ = try await run(text: "",
                          source: sourceLang,
                          target: Self.localeLanguage(target),
                          prepareOnly: true,
                          timeout: 300)
    }

    // MARK: 翻译

    func translate(_ text: String, to targetCode: String) async throws -> (text: String, source: String?) {
        guard #available(macOS 15.0, *) else { throw AppleTranslateError.unsupportedOS }

        let detected = Self.detect(text)
        if let detected, Self.isSameLanguage(detected, targetCode) {
            return (text, detected)
        }

        let sourceLang = detected.map { Self.localeLanguage($0) }
        let target = Self.localeLanguage(targetCode)
        let state = await status(for: text, target: targetCode)

        if state == .installed {
            // 状态说已就绪 → 直接翻
            if let output = try? await run(text: text, source: sourceLang, target: target,
                                           prepareOnly: false, timeout: 20) {
                lastFailure = nil
                return (output, detected)
            }
            // 失败一次：重建承载 .translationTask 的宿主窗口再试
            resetHost()
            if let output = try? await run(text: text, source: sourceLang, target: target,
                                           prepareOnly: false, timeout: 20) {
                lastFailure = nil
                return (output, detected)
            }
            lastFailure = "会话已重建仍失败"
            throw AppleTranslateError.failed(lastFailure ?? "未知错误")
        }

        // 状态说「没装」。但这个判断在进程内会缓存——用户不重启应用就装了语言包时它仍是旧值，
        // 所以不能直接报错，先用短超时真刀真枪试一次（真装了的话通常 1 秒内就返回）。
        if let output = try? await run(text: text, source: sourceLang, target: target,
                                       prepareOnly: false, timeout: 6) {
            lastFailure = nil
            return (output, detected)
        }
        resetHost()
        if let output = try? await run(text: text, source: sourceLang, target: target,
                                       prepareOnly: false, timeout: 12) {
            lastFailure = nil
            return (output, detected)
        }

        lastFailure = "语言包未就绪"
        NSLog("AirLingo: 系统翻译不可用 \(targetCode)，状态 \(state.title)")
        throw AppleTranslateError.needsDownload(AppLanguage.name(for: targetCode))
    }

    /// 丢掉宿主窗口与缓存，让下一次翻译重新建立 TranslationSession。
    func resetHost() {
        hostWindow?.orderOut(nil)
        hostWindow = nil
        hostModel.handler = nil
        hostModel.configuration = nil
        queue.removeAll()
    }

    // MARK: 任务队列

    private func run(text: String,
                     source: Locale.Language?,
                     target: Locale.Language,
                     prepareOnly: Bool,
                     timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var fired = false
            let job = Job(id: UUID(), text: text, source: source, target: target,
                          prepareOnly: prepareOnly, timeout: timeout) { result in
                guard !fired else { return }
                fired = true
                continuation.resume(with: result)
            }
            queue.append(job)
            pump()
        }
    }

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        current = job
        ensureHost()

        var config = TranslationSession.Configuration(source: job.source, target: job.target)
        config.invalidate()

        hostModel.handler = { [weak self] session in
            await self?.execute(job, session: session)
        }
        hostModel.configuration = config

        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(job.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == job.id else { return }
                self.finish(job, .failure(AppleTranslateError.timeout))
            }
        }
    }

    private func execute(_ job: Job, session: TranslationSession) async {
        do {
            if job.prepareOnly {
                try await session.prepareTranslation()
                finish(job, .success(""))
            } else {
                let response = try await session.translate(job.text)
                let output = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty {
                    finish(job, .failure(TranslationError.emptyResult))
                } else {
                    finish(job, .success(output))
                }
            }
        } catch {
            finish(job, .failure(error))
        }
    }

    private func finish(_ job: Job, _ result: Result<String, Error>) {
        guard current?.id == job.id else { return }
        current = nil
        watchdog?.cancel()
        watchdog = nil
        job.completion(result)
        DispatchQueue.main.async { [weak self] in self?.pump() }
    }

    // MARK: 宿主窗口

    private func ensureHost() {
        if let window = hostWindow {
            if !window.isVisible { window.orderFrontRegardless() }
            return
        }
        let hosting = NSHostingView(rootView: AppleTranslationHostView(model: hostModel))
        hosting.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        // 窗口必须真的“出现在屏幕上”，`.translationTask` 才会被触发；
        // 尺寸 1×1、背景透明，肉眼不可见。
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = .normal
        window.orderFrontRegardless()

        hostWindow = window
    }
}
