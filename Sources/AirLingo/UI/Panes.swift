import SwiftUI
import AppKit

// MARK: - 快捷键

private struct ShortcutRow: Identifiable {
    let id: String
    let title: String
    let hint: String
    let value: Binding<String>
}

struct ShortcutsPane: View {
    @EnvironmentObject var store: ConfigStore
    @State private var editing: String?
    @State private var manual: String?
    @State private var draft = ""
    @State private var notice: String?

    private var bindings: [ShortcutRow] {
        [
            ShortcutRow(id: "translate", title: "划词翻译", hint: "选中文字后浮窗出译文", value: $store.config.shortcuts.translate),
            ShortcutRow(id: "silent", title: "静默替换", hint: "译文直接写回输入框", value: $store.config.shortcuts.silent),
            ShortcutRow(id: "ocr", title: "截图翻译", hint: "框选屏幕区域取字翻译", value: $store.config.shortcuts.ocr),
            ShortcutRow(id: "compare", title: "对比翻译", hint: "多引擎同时翻译", value: $store.config.shortcuts.compare)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "快捷键",
                  subtitle: "点键位直接录制：按下组合键，或者连着点两下修饰键录成「双击 ⌃」。Esc 取消，录制失败可以改用手动输入。") {
                VStack(spacing: 0) {
                    ForEach(bindings) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.fg)
                                    Text(item.hint)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.fgSoft)
                                }
                                Spacer()

                                if manual == item.id {
                                    TextField("例如 Alt+Cmd+O", text: $draft)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(Theme.fg)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .frame(width: 150)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.brandLite.opacity(0.6), lineWidth: 1))
                                        .onSubmit { commit(item, draft, manualInput: true) }

                                    Button("保存") { commit(item, draft, manualInput: true) }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.brandLite)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.07)))
                                        .contentShape(Capsule())
                                } else if editing == item.id {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Theme.brandLite.opacity(0.7), lineWidth: 1)
                                        Text("按下组合键…")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.brandLite)
                                        HotkeyRecorder(
                                            onCapture: { spec in commit(item, spec) },
                                            onCancel: { editing = nil }
                                        )
                                    }
                                    .frame(width: 150, height: 26)

                                    Button {
                                        draft = item.value.wrappedValue
                                        editing = nil
                                        manual = item.id
                                    } label: {
                                        Text("手动")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(Theme.fgSoft)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.white.opacity(0.05)))
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        notice = nil
                                        manual = nil
                                        editing = item.id
                                    } label: {
                                        KeyCap(text: HotkeyCenter.describe(item.value.wrappedValue))
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .help("点击重新录制")
                                }
                            }

                            if manual == item.id {
                                Text("支持写法：Ctrl / Alt / Shift / Cmd + 字母，双击修饰键写 double:ctrl。")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.fgSoft.opacity(0.75))
                            }
                        }
                        .padding(.vertical, 9)

                        if item.id != bindings.last?.id {
                            Divider().overlay(Theme.line)
                        }
                    }
                }
            }

            if let notice {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xF5C451))
                        .padding(.top, 1)
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.fgSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }

            Panel(title: "运行状态", subtitle: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AccessibilityService.isTrusted ? Color(hex: 0x4ADE80) : Color(hex: 0xFBBF24))
                            .frame(width: 6, height: 6)
                        Text(AccessibilityService.isTrusted
                             ? "辅助功能已授权，全局快捷键与划词可用"
                             : "辅助功能未授权，快捷键无效。授权后需重启应用生效")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.fgSoft)
                    }

                    if !HotkeyCenter.shared.failedSpecs.isEmpty {
                        Text("这些键已经被系统或别的应用占用，注册没成功：\(HotkeyCenter.shared.failedSpecs.joined(separator: "、"))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0xFFB4A2))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("双击修饰键只识别单击后松开的情况；如果和系统手势冲突，换成组合键即可。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fgSoft.opacity(0.8))

                    Button {
                        store.config.shortcuts = ShortcutMap()
                        editing = nil
                        manual = nil
                        notice = "已恢复默认快捷键"
                    } label: {
                        Text("恢复默认快捷键")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.brandLite)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func commit(_ row: ShortcutRow, _ raw: String, manualInput: Bool = false) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }

        if value.hasPrefix("double:") {
            let allowed = ["ctrl", "alt", "cmd", "rcmd", "shift"]
            guard allowed.contains(String(value.dropFirst("double:".count)).lowercased()) else {
                notice = "双击修饰键只支持 double:ctrl / double:alt / double:cmd / double:rcmd / double:shift"
                return
            }
        } else if HotkeyCenter.parse(value) == nil {
            notice = "「\(value)」不是合法的组合键，至少要有 Ctrl / Alt / Shift / Cmd 里的一个"
            return
        }

        if let duplicate = bindings.first(where: {
            $0.id != row.id && $0.value.wrappedValue.lowercased() == value.lowercased()
        }) {
            notice = "「\(duplicate.title)」已经用了 \(HotkeyCenter.describe(value))，换一个"
            return
        }

        row.value.wrappedValue = value
        editing = nil
        manual = nil
        draft = ""
        notice = nil
    }
}

// MARK: - 引擎

struct EnginesPane: View {
    @EnvironmentObject var store: ConfigStore
    @State private var tests: [String: String] = [:]
    @State private var testing: Set<String> = []
    @State private var showKey: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "功能分配", subtitle: "不同场景用不同引擎：划词要快、截图取字要准、对比要多家。") {
                VStack(spacing: 0) {
                    featureRow(.translate, selection: $store.config.translateEngineID)
                    Divider().overlay(Theme.line)
                    featureRow(.silent, selection: $store.config.silentEngineID)
                    Divider().overlay(Theme.line)
                    featureRow(.ocr, selection: $store.config.ocrEngineID)
                }
            }

            Panel(title: "对比翻译引擎", subtitle: "选中哪些引擎，对比浮窗里就并排展示哪些（至少两个才会真的对比）。") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.config.engines) { engine in
                        Toggle(isOn: Binding(
                            get: { store.config.compareEngineIDs.contains(engine.id) },
                            set: { newValue in
                                if newValue {
                                    if !store.config.compareEngineIDs.contains(engine.id) {
                                        store.config.compareEngineIDs.append(engine.id)
                                    }
                                } else {
                                    store.config.compareEngineIDs.removeAll { $0 == engine.id }
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: engine.kind.iconName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.fgSoft)
                                Text(engine.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(engine.isReady ? Theme.fg : Theme.fgSoft.opacity(0.6))
                                if !engine.isReady {
                                    Text("未配置")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(Theme.fgSoft.opacity(0.7))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.white.opacity(0.06)))
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .tint(Theme.brand)
                    }
                }
            }

            ForEach($store.config.engines) { $engine in
                engineCard(engine: $engine)
            }
        }
    }

    private func featureRow(_ feature: Feature, selection: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.fg)
                Text(featureHint(feature))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSoft)
            }
            Spacer()
            Picker("", selection: selection) {
                ForEach(store.config.engines) { engine in
                    Text(engine.name).tag(engine.id)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .tint(Theme.brandLite)
        }
        .padding(.vertical, 8)
    }

    private func featureHint(_ feature: Feature) -> String {
        switch feature {
        case .translate: return "划词 / 划句浮窗"
        case .silent: return "输入框原地替换"
        case .ocr: return "截图取字后翻译"
        }
    }

    private func engineCard(engine: Binding<EngineProfile>) -> some View {
        let profile = engine.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: profile.kind.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.brandLite)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                    Text(profile.kind.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.fgSoft)
                }
                Spacer()

                Button {
                    Task { await test(profile) }
                } label: {
                    HStack(spacing: 5) {
                        if testing.contains(profile.id) {
                            ProgressView().controlSize(.mini).tint(Theme.brandLite)
                        }
                        Text(testing.contains(profile.id) ? "测试中" : "测试")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.brandLite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Toggle("", isOn: engine.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.brand)
            }

            if let message = tests[profile.id] {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(message.hasPrefix("✓") ? Color(hex: 0x4ADE80) : Color(hex: 0xFFB4A2))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if profile.kind == .apple {
                AppleEngineDetail(native: store.config.nativeLang, learn: store.config.learnLang)
            } else if profile.kind != .google {
                VStack(alignment: .leading, spacing: 8) {
                    fieldRow(label: "接口地址", text: engine.baseURL, placeholder: profile.kind.defaultBaseURL)

                    if profile.kind == .openai || profile.kind == .ollama {
                        fieldRow(label: "模型", text: engine.model, placeholder: profile.kind.defaultModel)
                    }

                    if profile.kind.needsKey {
                        HStack(spacing: 8) {
                            Text("API Key")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.fgSoft)
                                .frame(width: 58, alignment: .leading)
                            Group {
                                if showKey[profile.id] == true {
                                    TextField("粘贴密钥", text: engine.apiKey)
                                } else {
                                    SecureField("粘贴密钥", text: engine.apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))

                            Button {
                                showKey[profile.id] = !(showKey[profile.id] ?? false)
                            } label: {
                                Image(systemName: showKey[profile.id] == true ? "eye.slash" : "eye")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.fgSoft)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("内置免费接口，不需要密钥。长句质量一般，重要内容建议换 AI 引擎。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSoft.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func fieldRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.fgSoft)
                .frame(width: 58, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func test(_ profile: EngineProfile) async {
        testing.insert(profile.id)
        defer { testing.remove(profile.id) }
        do {
            let result = try await Translator.translate("Hello, world.", to: "zh-CN", profile: profile)
            tests[profile.id] = "✓ \(result.text)"
        } catch {
            tests[profile.id] = "✗ \(error.localizedDescription)"
        }
    }
}

// MARK: - Apple 系统翻译状态

private struct AppleEngineDetail: View {
    let native: String
    let learn: String

    @State private var status: AppleLanguageStatus = .unknown
    @State private var missing: [String] = []
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSoft)

                Spacer()

                Button {
                    Task { await prepare() }
                } label: {
                    HStack(spacing: 5) {
                        if busy { ProgressView().controlSize(.mini).tint(Theme.brandLite) }
                        Text(busy ? "安装中" : "安装语言包")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.brandLite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    Task { await recheck() }
                } label: {
                    Text("重新检测")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.fgSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    if #available(macOS 15.0, *) {
                        AppleTranslateService.shared.openLanguageSettings()
                    }
                } label: {
                    Text("系统设置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.fgSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(message.hasPrefix("✓") ? Color(hex: 0x4ADE80) : Color(hex: 0xFFB4A2))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("由 macOS 本机模型翻译，不联网、不需要密钥。首次使用某语种时，需要系统里已安装该语言包；点「安装语言包」或到系统设置手动添加。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.fgSoft.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: native + learn) { await refresh() }
    }

    private var dotColor: Color {
        switch status {
        case .installed: return Color(hex: 0x4ADE80)
        case .supported: return Color(hex: 0xF5C451)
        case .unsupported: return Color(hex: 0xFF7A6B)
        case .unknown: return Theme.fgSoft.opacity(0.5)
        }
    }

    private var statusText: String {
        let pair = "\(AppLanguage.name(for: native)) ⇄ \(AppLanguage.name(for: learn))"
        switch status {
        case .installed:
            return "\(pair) 双向语言包已就绪"
        case .supported:
            return missing.isEmpty ? "\(pair) 语言包未安装" : "\(pair) 还缺\(missing.joined(separator: "、"))的语言包"
        case .unsupported:
            return "当前系统暂不支持\(pair)"
        case .unknown:
            return "正在检查系统语言包…"
        }
    }

    private func refresh() async {
        guard #available(macOS 15.0, *) else {
            status = .unsupported
            return
        }
        let service = AppleTranslateService.shared
        let forward = await service.status(from: native, to: learn)    // 母语 → 学习语言
        let backward = await service.status(from: learn, to: native)   // 学习语言 → 母语

        var lacking: [String] = []
        if forward != .installed { lacking.append(AppLanguage.name(for: learn)) }
        if backward != .installed { lacking.append(AppLanguage.name(for: native)) }
        missing = Array(NSOrderedSet(array: lacking)) as? [String] ?? lacking

        if forward == .unsupported || backward == .unsupported {
            status = .unsupported
        } else if !lacking.isEmpty {
            status = .supported
        } else {
            status = .installed
        }
    }

    /// 用户装完语言包后不用重启应用：丢掉旧的翻译会话再查一次。
    private func recheck() async {
        guard #available(macOS 15.0, *) else { return }
        busy = true
        message = nil
        defer { busy = false }
        AppleTranslateService.shared.resetHost()
        await refresh()
        if status == .installed {
            message = "✓ 语言包已就绪，可以直接使用"
        } else {
            message = "系统仍未报告就绪。点「安装语言包」让系统补装，或重启 AirLingo 后再看"
        }
    }

    private func prepare() async {
        guard #available(macOS 15.0, *) else {
            message = "✗ 系统翻译需要 macOS 15 或更高版本"
            return
        }
        busy = true
        message = nil
        defer { busy = false }
        var lastError: Error?
        for pair in [(native, learn), (learn, native)] {
            do {
                try await AppleTranslateService.shared.prepare(source: pair.0, target: pair.1)
            } catch {
                lastError = error
            }
        }
        await refresh()
        if status == .installed {
            message = "✓ 语言包已准备好，可以直接使用"
        } else if let lastError {
            message = "✗ \(lastError.localizedDescription)"
        } else {
            message = "系统没有自动安装，请到「系统设置 › 通用 › 语言与地区 › 翻译语言」手动添加"
        }
    }
}
