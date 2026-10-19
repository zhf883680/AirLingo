import SwiftUI
import AppKit
import Combine

enum PopupMode {
    case translate
    case ocr
    case compare
}

struct CompareRow: Identifiable {
    let id = UUID()
    var engine: String
    var text: String = ""
    var error: String?
}

enum PopupLayout {
    static let panelWidth: CGFloat = 440
    static let inset: CGFloat = 16
    static let outerPadding: CGFloat = 10
    static let minWindowWidth: CGFloat = panelWidth + outerPadding * 2
    static let minWindowHeight: CGFloat = 120
    static let sourceMaxHeight: CGFloat = 96
    static let outputMaxHeight: CGFloat = 260
    static let compareMaxHeight: CGFloat = 340
    static var textWidth: CGFloat { panelWidth - inset * 2 }
}

/// 用 TextKit 量文字高度：只用来判断「要不要滚」，量出来的值偏小也不会截断文字。
enum TextMetrics {
    static func height(_ text: String,
                       width: CGFloat,
                       size: CGFloat,
                       lineSpacing: CGFloat,
                       weight: NSFont.Weight = .regular) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .paragraphStyle: style
        ]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return ceil(rect.height)
    }
}

@MainActor
final class PopupModel: ObservableObject {
    @Published var source: String = ""
    @Published var output: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var engineID: String = "google"
    @Published var engineName: String = ""
    @Published var targetName: String = ""
    @Published var targetCode: String = ""
    @Published var detected: String?
    @Published var isFavorite: Bool = false
    @Published var rows: [CompareRow] = []

    var mode: PopupMode = .translate

    func load(source: String, engineID: String, mode: PopupMode) {
        self.source = source
        self.engineID = engineID
        self.mode = mode
        self.output = ""
        self.error = nil
        self.detected = nil
        self.rows = []
        self.isFavorite = false
        // 先把引擎名填上，首帧的标题就不会是空的
        self.engineName = ConfigStore.shared.config.engine(id: engineID)?.name ?? ""
        let target = ConfigStore.shared.targetLanguage(for: source)
        self.targetName = AppLanguage.name(for: target)
        self.targetCode = target
        Task { await run() }
    }

    func run() async {
        let store = ConfigStore.shared
        let target = store.targetLanguage(for: source)
        targetName = AppLanguage.name(for: target)
        targetCode = target
        isLoading = true
        error = nil

        if mode == .compare {
            await runCompare(store: store, target: target)
        } else {
            guard let profile = store.config.engine(id: engineID) ?? store.engine(for: .translate) else {
                error = "没有可用的翻译引擎"
                isLoading = false
                return
            }
            engineID = profile.id
            engineName = profile.name
            do {
                let result = try await Translator.translate(source, to: target, profile: profile)
                output = result.text
                engineName = result.engineName
                detected = result.detectedSource
                isFavorite = HistoryStore.shared.isFavorite(source: source, target: result.text)
                HistoryStore.shared.add(source: source,
                                        target: result.text,
                                        engine: result.engineName,
                                        from: result.detectedSource ?? "auto",
                                        to: target)
                if store.config.autoCopy {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func runCompare(store: ConfigStore, target: String) async {
        let profiles = store.compareEngines
        guard !profiles.isEmpty else {
            error = "没有可用的翻译引擎，先去设置里启用一个"
            return
        }
        rows = profiles.map { CompareRow(engine: $0.name) }
        if profiles.count < 2 {
            error = "只有一个可用引擎，没法对比。去「引擎 › 对比翻译引擎」里再勾一个。"
            rows = []
            return
        }
        let text = source

        await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for (index, profile) in profiles.enumerated() {
                group.addTask {
                    do {
                        let result = try await Translator.translate(text, to: target, profile: profile)
                        return (index, .success(result.text))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                guard index < rows.count else { continue }
                switch result {
                case .success(let text):
                    rows[index].text = text
                case .failure(let err):
                    rows[index].error = err.localizedDescription
                }
            }
        }
    }

    func switchEngine(to id: String) {
        engineID = id
        Task { await run() }
    }

    func toggleFavorite() {
        guard !output.isEmpty else { return }
        if let item = HistoryStore.shared.items.first(where: { $0.source == source && $0.target == output }) {
            HistoryStore.shared.toggleFavorite(item.id)
            isFavorite = !item.favorite
        } else if let item = HistoryStore.shared.add(source: source,
                                                      target: output,
                                                      engine: engineName,
                                                      from: detected ?? "auto",
                                                      to: targetCode,
                                                      force: true) {
            HistoryStore.shared.toggleFavorite(item.id)
            isFavorite = true
        }
    }
}

// MARK: - 视图

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @EnvironmentObject var store: ConfigStore

    var onClose: () -> Void
    var onReplace: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.config.showOriginal && !model.source.isEmpty {
                sourceBlock
            }

            content

            if model.mode == .compare {
                if !model.rows.isEmpty {
                    compareFooter
                }
            } else if !model.output.isEmpty && model.error == nil {
                footer
            }
        }
        .frame(width: PopupLayout.panelWidth)
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
        .padding(PopupLayout.outerPadding)
    }

    // MARK: 头部（同时是拖动区）

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [Theme.brandLite, Theme.brand],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: 7)

                Text(model.mode == .compare ? "对比翻译" : (model.engineName.isEmpty ? "翻译" : model.engineName))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)

                if let detected = model.detected, !detected.isEmpty, model.mode != .compare {
                    Text("·")
                        .foregroundStyle(Theme.fgSoft.opacity(0.5))
                    Text("\(AppLanguage.name(for: detected)) → \(model.targetName)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fgSoft.opacity(0.8))
                } else if model.mode == .compare {
                    Text("· \(max(model.rows.count, store.compareEngines.count)) 个引擎")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fgSoft.opacity(0.8))
                }

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
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, PopupLayout.inset)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private var sourceBlock: some View {
        VStack(spacing: 0) {
            limitedText(model.source, size: 12.5, lineSpacing: 3, color: Theme.fgSoft,
                        max: PopupLayout.sourceMaxHeight)
                .padding(.horizontal, PopupLayout.inset)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.mode == .compare {
            if let error = model.error {
                errorBlock(error)
            } else if model.rows.isEmpty {
                loadingBlock
            } else {
                compareList
            }
        } else if model.isLoading {
            loadingBlock
        } else if let error = model.error {
            errorBlock(error)
        } else {
            limitedText(model.output, size: 15.5, lineSpacing: 5, color: Theme.fg,
                        max: PopupLayout.outputMaxHeight)
                .padding(.horizontal, PopupLayout.inset)
                .padding(.vertical, 14)
        }
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.brandLite)
            Text("翻译中…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.fgSoft)
        }
        .padding(.horizontal, PopupLayout.inset)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBlock(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("翻译失败", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFB4A2))
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") { Task { await model.run() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.brandLite)
                .padding(.top, 2)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, PopupLayout.inset)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 短文本用原生 Text（高度精确、不会被裁），超长才套滚动容器并卡住最大高度。
    @ViewBuilder
    private func limitedText(_ text: String,
                             size: CGFloat,
                             lineSpacing: CGFloat,
                             color: Color,
                             max maxHeight: CGFloat) -> some View {
        let measured = TextMetrics.height(text, width: PopupLayout.textWidth, size: size, lineSpacing: lineSpacing)
        if measured > maxHeight {
            ScrollView(.vertical, showsIndicators: false) {
                styledText(text, size: size, lineSpacing: lineSpacing, color: color)
            }
            .frame(height: maxHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            styledText(text, size: size, lineSpacing: lineSpacing, color: color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func styledText(_ text: String, size: CGFloat, lineSpacing: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var compareList: some View {
        let measured = compareContentHeight
        return Group {
            if measured > PopupLayout.compareMaxHeight {
                ScrollView(.vertical, showsIndicators: false) { compareRows }
                    .frame(height: PopupLayout.compareMaxHeight)
            } else {
                compareRows
            }
        }
    }

    private var compareRows: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(row.engine)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.brandLite.opacity(0.9))
                        Spacer(minLength: 6)
                        if !row.text.isEmpty {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(row.text, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.fgSoft)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                            .help("复制这条译文")
                        }
                    }
                    if let error = row.error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: 0xFFB4A2))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if row.text.isEmpty {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini).tint(Theme.brandLite)
                            Text("翻译中…")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.fgSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(row.text)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.fg)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, PopupLayout.inset)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)

                if row.id != model.rows.last?.id {
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, PopupLayout.inset)
                }
            }
        }
        .padding(.top, 4)
    }

    /// 估算对比区高度，只有超过上限才套滚动，避免窗口被撑到屏幕外。
    private var compareContentHeight: CGFloat {
        var total: CGFloat = 4
        for row in model.rows {
            let text = row.error ?? (row.text.isEmpty ? "翻译中…" : row.text)
            let size: CGFloat = row.error == nil ? 14 : 12
            let textHeight = max(16, TextMetrics.height(text, width: PopupLayout.textWidth,
                                                        size: size, lineSpacing: 4))
            total += textHeight + 22 + 16 + 1
        }
        return total
    }

    private var compareFooter: some View {
        HStack(spacing: 6) {
            Button {
                let text = model.rows
                    .filter { !$0.text.isEmpty }
                    .map { "【\($0.engine)】\($0.text)" }
                    .joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("复制全部", systemImage: "doc.on.doc")
            }
            .buttonStyle(PopupButtonStyle())

            Text("\(model.rows.filter { !$0.text.isEmpty }.count)/\(model.rows.count) 已返回")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.fgSoft.opacity(0.7))

            Spacer(minLength: 6)
                .overlay(WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity))

            Button { onClose() } label: {
                Label("关闭", systemImage: "xmark")
            }
            .buttonStyle(PopupButtonStyle(prominent: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.output, forType: .string)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(PopupButtonStyle())

            Button {
                model.toggleFavorite()
            } label: {
                Label(model.isFavorite ? "已收藏" : "收藏",
                      systemImage: model.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(PopupButtonStyle(active: model.isFavorite))

            Button {
                Speaker.speak(model.output,
                              language: model.targetCode.isEmpty ? store.config.nativeLang : model.targetCode,
                              rate: store.config.speechRate)
            } label: {
                Label("朗读", systemImage: "speaker.wave.2")
            }
            .buttonStyle(PopupButtonStyle())

            Spacer(minLength: 6)
                .overlay(WindowDragArea().frame(maxWidth: .infinity, maxHeight: .infinity))

            if model.mode != .compare {
                Menu {
                    ForEach(store.config.engines) { engine in
                        Button {
                            model.switchEngine(to: engine.id)
                        } label: {
                            if engine.id == model.engineID {
                                Label(engine.name, systemImage: "checkmark")
                            } else if engine.isReady {
                                Text(engine.name)
                            } else {
                                Text("\(engine.name)（未配置）")
                            }
                        }
                        .disabled(!engine.isReady)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.fgSoft)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    onReplace(model.output)
                } label: {
                    Label("替换原文", systemImage: "arrow.turn.down.left")
                }
                .buttonStyle(PopupButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

// MARK: - 窗口拖动区

/// SwiftUI 内容铺满整窗时 `isMovableByWindowBackground` 不生效，
/// 所以给需要拖动的空白区压一个真正能响应鼠标的 NSView。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

struct PopupButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(prominent ? Color(hex: 0x0A0812) : (active ? Theme.brandLite : Theme.fgSoft))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(prominent
                               ? AnyShapeStyle(Color.white.opacity(0.88))
                               : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06)))
            )
            .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0 : 0.08), lineWidth: 1))
            .contentShape(Capsule())
    }
}

// MARK: - 浮窗控制

final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PopupController {
    static let shared = PopupController()

    private var panel: FloatingPanel?
    private let model = PopupModel()
    private var hosting: NSView?
    private var sizeObserver: AnyCancellable?
    private var clickMonitor: Any?
    /// 弹窗在光标上方时为 true：高度变化向上生长，底边贴住光标。
    private var growsUpward = true
    private var fitGeneration = 0

    func show(source: String, engineID: String, mode: PopupMode, anchor: CGPoint) {
        model.load(source: source, engineID: engineID, mode: mode)
        present(anchor: anchor)
    }

    func updateSource(_ text: String) {
        model.source = text
    }

    private func present(anchor: CGPoint) {
        let root = PopupView(
            model: model,
            onClose: { [weak self] in self?.hide() },
            onReplace: { [weak self] text in
                _ = AccessibilityService.replaceSelection(with: text)
                self?.hide()
            }
        ).environmentObject(ConfigStore.shared)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0,
                              width: PopupLayout.minWindowWidth,
                              height: PopupLayout.minWindowHeight)

        if panel == nil {
            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0,
                                    width: PopupLayout.minWindowWidth,
                                    height: PopupLayout.minWindowHeight),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .utilityWindow
            panel.onCancel = { [weak self] in self?.hide() }
            self.panel = panel
        }
        guard let panel else { return }

        panel.contentView = hosting
        self.hosting = hosting
        observeModel()

        let size = fittedSize()
        place(panel: panel, size: size, anchor: anchor)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        // SwiftUI 首帧排版有延迟，这里再补两次测量，避免第一次出现时高度不足把内容裁掉。
        scheduleFit(after: 0.02)
        scheduleFit(after: 0.18)
        installClickMonitor()
    }

    // MARK: 尺寸

    private func fittedSize() -> NSSize {
        guard let hosting else {
            return NSSize(width: PopupLayout.minWindowWidth, height: PopupLayout.minWindowHeight)
        }
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        var height = fitted.height.isFinite ? ceil(fitted.height) : 0
        var width = fitted.width.isFinite ? ceil(fitted.width) : 0
        height = max(PopupLayout.minWindowHeight, height)
        width = max(PopupLayout.minWindowWidth, width)
        if let vf = (panel?.screen ?? NSScreen.main)?.visibleFrame {
            height = min(height, max(PopupLayout.minWindowHeight, vf.height - 60))
        }
        return NSSize(width: width, height: height)
    }

    private func place(panel: NSPanel, size: NSSize, anchor: CGPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        var x = anchor.x - 20
        var y = anchor.y - size.height - 18
        growsUpward = true

        if let vf = screen?.visibleFrame {
            if x + size.width > vf.maxX { x = vf.maxX - size.width - 10 }
            if x < vf.minX { x = vf.minX + 10 }
            if y < vf.minY {
                // 光标下方放不下 → 改放到光标下面，此时向下生长
                y = anchor.y - 28
                growsUpward = false
            }
            if y + size.height > vf.maxY { y = vf.maxY - size.height - 10 }
            if y < vf.minY { y = vf.minY + 6 }
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func scheduleFit(after delay: TimeInterval) {
        fitGeneration += 1
        let generation = fitGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.fitGeneration == generation else { return }
            self.fitToContent()
        }
    }

    /// 内容变化后重新贴合，锚点保持不变（上方的弹窗向上长）。
    private func fitToContent() {
        guard let panel, panel.isVisible else { return }
        let size = fittedSize()
        var frame = panel.frame
        let heightChanged = abs(size.height - frame.height) > 0.5
        let widthChanged = abs(size.width - frame.width) > 0.5
        guard heightChanged || widthChanged else { return }

        if growsUpward {
            frame.origin.y = frame.maxY - size.height
        }
        frame.size = size
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if frame.maxY > vf.maxY - 6 { frame.origin.y = vf.maxY - 6 - frame.height }
            if frame.minY < vf.minY + 6 { frame.origin.y = vf.minY + 6 }
        }
        panel.setFrame(frame, display: true)
    }

    private func observeModel() {
        guard sizeObserver == nil else { return }
        sizeObserver = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange 在赋值之前发出，等一轮 runloop 再量才拿得到新内容
            Task { @MainActor in
                self?.fitToContent()
                try? await Task.sleep(nanoseconds: 60_000_000)
                self?.fitToContent()
            }
        }
    }

    // MARK: 点击外部关闭

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let point = NSEvent.mouseLocation
                if !panel.frame.insetBy(dx: -6, dy: -6).contains(point) {
                    self.hide()
                }
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: 开发期自检

    /// 把当前真实面板的尺寸和渲染结果写到磁盘，用来验证首次弹出时的高度是否正确。
    func debugReport(to directory: String) {
        guard let panel, let hosting else { return }
        let fit = hosting.fittingSize
        let h = panel.frame.height
        let samples: [(String, NSPoint)] = [
            ("header", NSPoint(x: 150, y: h - 26)),
            ("close", NSPoint(x: panel.frame.width - 30, y: h - 26)),
            ("output", NSPoint(x: 200, y: h - 130))
        ]
        let hits = samples.map { name, point in
            let view = hosting.hitTest(point)
            return "hit_\(name)=\(view.map { String(describing: type(of: $0)) } ?? "nil")"
        }.joined(separator: "\n")
        let info = """
        panel_frame=\(panel.frame)
        panel_size=\(panel.frame.size)
        content_fitting=\(fit)
        visible=\(panel.isVisible)
        output_length=\(model.output.count)
        output=\(model.output)
        error=\(model.error ?? "nil")
        \(hits)
        """
        try? info.write(toFile: directory + "/popup-live.txt", atomically: true, encoding: .utf8)

        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: directory + "/popup-live.png"))
        }
    }
}
