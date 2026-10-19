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
            return "系统还没安装\(language)语言包，请在「系统设置 › 通用 › 语言与地区 › 翻译语言」里添加后重试"
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
        if raw.hasPrefix("zh") { return "zh" }
        return AppLanguage.base(raw)
    }

    private static func isSameLanguage(_ detected: String, _ target: String) -> Bool {
        AppLanguage.base(detected).lowercased() == AppLanguage.base(target).lowercased()
    }

    // MARK: 可用性

    func status(for text: String?, target: String) async -> AppleLanguageStatus {
        guard #available(macOS 15.0, *) else { return .unsupported }
        let targetLang = Self.localeLanguage(target)
        let availability = LanguageAvailability()
        let raw: LanguageAvailability.Status
        if let text, !text.isEmpty {
            raw = (try? await availability.status(for: text, to: targetLang)) ?? .unsupported
        } else {
            let source = Self.localeLanguage(ConfigStore.shared.config.nativeLang)
            raw = await availability.status(from: source, to: targetLang)
        }
        switch raw {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
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

        if await status(for: text, target: targetCode) != .installed {
            // 先给系统一次安静安装的机会（已装好或系统愿意静默下载时会直接成功）。
            _ = try? await run(text: "", source: sourceLang, target: target,
                               prepareOnly: true, timeout: 12)
            if await status(for: text, target: targetCode) != .installed {
                throw AppleTranslateError.needsDownload(AppLanguage.name(for: targetCode))
            }
        }

        let result = try await run(text: text, source: sourceLang, target: target,
                                   prepareOnly: false, timeout: 60)
        return (result, detected)
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
