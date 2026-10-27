import SwiftUI
import AppKit

/// 主动翻译弹窗：不依赖选中文字，直接把想翻的内容粘进来。
struct TranslatePane: View {
    static let panelWidth: CGFloat = 600
    static let outerPadding: CGFloat = 10

    @EnvironmentObject private var store: ConfigStore
    @ObservedObject private var history = HistoryStore.shared

    @State private var source = ""
    @State private var output = ""
    @State private var sourceLang = "auto"
    @State private var targetLang = "auto"
    @State private var engineID = ""
    @State private var detected: String?
    @State private var resultTarget = ""
    @State private var translating = false
    @State private var error: String?
    @State private var lastHistoryID: UUID?
    @State private var copied = false
    @FocusState private var sourceFocused: Bool

    private let onClose: () -> Void

    /// 带预置内容的分支主要给离屏渲染用，检查有译文时的排版。
    init(onClose: @escaping () -> Void = {},
         source: String = "",
         output: String = "",
         detected: String? = nil,
         target: String = "",
         engineID: String = "") {
        self.onClose = onClose
        _source = State(initialValue: source)
        _output = State(initialValue: output)
        _detected = State(initialValue: detected)
        _resultTarget = State(initialValue: target)
        _engineID = State(initialValue: engineID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                languageRow
                sourceBlock
                outputBlock
            }
            .padding(16)

            Rectangle().fill(Theme.line).frame(height: 1)
            footer
        }
        .frame(width: Self.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panel.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 28, y: 14)
        .padding(Self.outerPadding)
        .preferredColorScheme(.dark)
        .onAppear {
            syncEngine(force: true)
            sourceFocused = true
        }
        .onChange(of: store.usableEngines.map(\.id)) { _, _ in
            syncEngine()
        }
        .onReceive(NotificationCenter.default.publisher(for: .airLingoFocusTranslateInput)) { _ in
            sourceFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .airLingoTriggerTranslate)) { _ in
            run()
        }
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.brandLite, Theme.brand],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: 7)

                Text("主动翻译")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)

                Text("· 粘贴文字，⌘↵ 翻译")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSoft.opacity(0.7))

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.fgSoft)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭（Esc）")
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    // MARK: - 语言与引擎

    private var languageRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            languageField(title: "原文",
                          selection: $sourceLang,
                          autoTitle: "自动检测",
                          width: 126)

            Button(action: swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("交换语言（有译文时连文字一起交换）")
            .padding(.bottom, 1)

            languageField(title: "译文",
                          selection: $targetLang,
                          autoTitle: "自动（偏好）",
                          width: 126)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text("引擎")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.fgSoft.opacity(0.75))

                Picker("", selection: $engineID) {
                    ForEach(store.usableEngines) { engine in
                        Text(engine.name).tag(engine.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 162)
                .tint(Theme.brandLite)
                .disabled(store.usableEngines.isEmpty)
            }
        }
    }

    private func languageField(title: String,
                               selection: Binding<String>,
                               autoTitle: String,
                               width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.fgSoft.opacity(0.75))

            Picker("", selection: selection) {
                Text(autoTitle).tag("auto")
                ForEach(AppLanguage.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: width)
            .tint(Theme.brandLite)
        }
    }

    // MARK: - 原文

    private var sourceBlock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("原文")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
                Text("\(source.count) 字")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.fgSoft.opacity(0.55))
                Spacer()
                if !source.isEmpty {
                    Button {
                        clearAll()
                    } label: {
                        Text("清空")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.fgSoft.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 3)

            TextEditor(text: $source)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.fg)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .background(HideTextEditorScroller())
                .focused($sourceFocused)
                .frame(height: 88)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .overlay(alignment: .topLeading) {
                    if source.isEmpty {
                        Text("把要翻译的文字粘贴到这里…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.fgSoft.opacity(0.5))
                            .padding(.leading, 13)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - 译文

    private var outputBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("译文")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)

                if !resultTarget.isEmpty {
                    Text(languagePairText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.fgSoft.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                iconButton(symbol: copied ? "checkmark" : "doc.on.doc",
                           tint: copied ? Color(hex: 0x4ADE80) : Theme.fgSoft,
                           help: "复制译文") {
                    copyOutput()
                }
                .disabled(output.isEmpty)

                iconButton(symbol: "speaker.wave.2", help: "朗读译文") {
                    Speaker.speak(output, language: resultTarget, rate: store.config.speechRate)
                }
                .disabled(output.isEmpty)

                iconButton(symbol: isFavorite ? "star.fill" : "star",
                           tint: isFavorite ? Color(hex: 0xF5C451) : Theme.fgSoft,
                           help: isFavorite ? "取消收藏" : "收藏这条译文") {
                    toggleFavorite()
                }
                .disabled(output.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 5)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if translating {
                        loadingBlock
                    } else if let error {
                        errorBlock(error)
                    } else if output.isEmpty {
                        emptyBlock
                    } else {
                        Text(output)
                            .font(.system(size: 13.5))
                            .lineSpacing(5)
                            .foregroundStyle(Theme.fg)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(height: 104)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private var loadingBlock: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.brandLite)
            Text("正在翻译…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgSoft)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("翻译失败", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFB4A2))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.fgSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") { run() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.brandLite)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("译文会出现在这里")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.fgSoft.opacity(0.55))
            Text("⌘↵ 或点右下角「翻译」")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.fgSoft.opacity(0.4))
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 底部操作

    private var footer: some View {
        HStack(spacing: 10) {
            statusText
                .lineLimit(1)

            Spacer(minLength: 8)

            if translating {
                Text("请稍候")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.fgSoft.opacity(0.6))
            } else {
                Text("⌘↵")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.fgSoft.opacity(0.45))
            }

            Button(action: run) {
                HStack(spacing: 6) {
                    if translating {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    Text(translating ? "翻译中" : "翻译")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(LinearGradient(colors: [Theme.brand, Color(hex: 0x9B6BFF)],
                                                  startPoint: .leading,
                                                  endPoint: .trailing))
                )
                .opacity(canTranslate ? 1 : 0.45)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canTranslate)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        if let error {
            Label(error, systemImage: "xmark.octagon")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(hex: 0xFFB4A2))
        } else if !resultTarget.isEmpty, !output.isEmpty {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.brandLite, Theme.brand],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 6)
                Text(selectedEngine?.name ?? "翻译引擎")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.fgSoft)
                Text("· \(languagePairText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.fgSoft.opacity(0.65))
            }
        } else {
            Text(store.usableEngines.isEmpty
                 ? "没有可用引擎，先去「翻译引擎」页启用一个"
                 : "支持整段文字，换行会保留")
                .font(.system(size: 10.5))
                .foregroundStyle(store.usableEngines.isEmpty ? Color(hex: 0xFFB4A2) : Theme.fgSoft.opacity(0.65))
        }
    }

    // MARK: - 状态与动作

    private var selectedEngine: EngineProfile? {
        store.config.engine(id: engineID) ?? store.usableEngines.first
    }

    private var canTranslate: Bool {
        !translating
            && selectedEngine != nil
            && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFavorite: Bool {
        guard let lastHistoryID else { return false }
        return history.items.first(where: { $0.id == lastHistoryID })?.favorite ?? false
    }

    private var languagePairText: String {
        let from = detected.map(AppLanguage.name(for:)) ?? "原文"
        return "\(from) → \(AppLanguage.name(for: resultTarget))"
    }

    private func syncEngine(force: Bool = false) {
        let usable = store.usableEngines
        guard force || !usable.contains(where: { $0.id == engineID }) else { return }
        engineID = usable.first(where: { $0.id == store.config.translateEngineID })?.id
            ?? usable.first?.id
            ?? ""
    }

    private func run() {
        guard canTranslate, let profile = selectedEngine else { return }
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetLang == "auto" ? store.targetLanguage(for: text) : targetLang

        translating = true
        error = nil
        copied = false

        Task {
            do {
                let result = try await Translator.translate(text, to: target, profile: profile)
                output = result.text
                detected = result.detectedSource ?? (sourceLang == "auto" ? nil : sourceLang)
                resultTarget = target
                lastHistoryID = HistoryStore.shared.add(
                    source: text,
                    target: result.text,
                    engine: result.engineName,
                    from: result.detectedSource ?? (sourceLang == "auto" ? "auto" : sourceLang),
                    to: target
                )?.id
            } catch {
                output = ""
                detected = nil
                resultTarget = ""
                lastHistoryID = nil
                self.error = error.localizedDescription
            }
            translating = false
        }
    }

    private func clearAll() {
        source = ""
        output = ""
        detected = nil
        resultTarget = ""
        lastHistoryID = nil
        error = nil
        copied = false
        sourceFocused = true
    }

    private func swap() {
        let oldSource = source
        let oldOutput = output

        // 「自动」时按当前内容推一对具体语言：检测到的语言 → 偏好里的另一种语言。
        let resolvedFrom = concrete(sourceLang)
        let resolvedTo = resultTarget.isEmpty
            ? (targetLang == "auto" ? store.targetLanguage(for: source) : targetLang)
            : resultTarget

        if !oldOutput.isEmpty, !resolvedTo.isEmpty {
            source = oldOutput
            output = oldSource
            detected = resolvedTo
            resultTarget = resolvedFrom
            lastHistoryID = nil
        }
        if !resolvedTo.isEmpty { sourceLang = resolvedTo }
        if !resolvedFrom.isEmpty { targetLang = resolvedFrom }
        error = nil
        sourceFocused = true
    }

    /// 把「自动」解析成具体语种；解析不出来就返回空串。
    private func concrete(_ code: String) -> String {
        if code != "auto" { return code }
        if let detected, !detected.isEmpty { return detected }
        let hint = LanguageHint.dominant(of: source)
        switch hint {
        case "zh":
            return store.config.nativeLang.hasPrefix("zh") ? store.config.nativeLang : "zh-CN"
        case "unknown", "auto":
            return ""
        default:
            return hint
        }
    }

    private func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }

    private func toggleFavorite() {
        guard !output.isEmpty else { return }
        if lastHistoryID == nil {
            lastHistoryID = HistoryStore.shared.add(
                source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                target: output,
                engine: selectedEngine?.name ?? "翻译引擎",
                from: detected ?? "auto",
                to: resultTarget,
                force: true
            )?.id
        }
        if let lastHistoryID {
            HistoryStore.shared.toggleFavorite(lastHistoryID)
        }
    }

    private func iconButton(symbol: String,
                            tint: Color = Theme.fgSoft,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 21, height: 21)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension Notification.Name {
    /// 弹窗每次显示时重新聚焦输入框。
    static let airLingoFocusTranslateInput = Notification.Name("AirLingoFocusTranslateInput")
    /// 窗口级 ⌘↵：文本框有焦点时 SwiftUI 的 keyboardShortcut 偶尔会被 NSTextView 吃掉。
    static let airLingoTriggerTranslate = Notification.Name("AirLingoTriggerTranslate")
}

/// SwiftUI 的 TextEditor 不认 scrollIndicators(.hidden)：
/// 系统设置成「始终显示滚动条」时，右侧会露出一条灰色轨道。这里找到底层的 NSScrollView 直接关掉。
private struct HideTextEditorScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let content = view.window?.contentView {
                Self.hide(in: content)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let content = nsView.window?.contentView {
                Self.hide(in: content)
            }
        }
    }

    private static func hide(in view: NSView) {
        if let scroll = view as? NSScrollView, scroll.documentView is NSTextView {
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
        }
        for sub in view.subviews {
            hide(in: sub)
        }
    }
}
