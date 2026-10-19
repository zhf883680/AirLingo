import SwiftUI
import AppKit

enum DashboardPage: String, CaseIterable, Identifiable {
    case general, shortcuts, engines, history, favorites, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .shortcuts: return "快捷键"
        case .engines: return "翻译引擎"
        case .history: return "翻译历史"
        case .favorites: return "收藏"
        case .about: return "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .shortcuts: return "command"
        case .engines: return "cpu"
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "star"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "语言偏好、行为开关与系统权限"
        case .shortcuts: return "每个功能都可以改成顺手的键"
        case .engines: return "翻译引擎、模型与凭据"
        case .history: return "译过的内容都留在这里"
        case .favorites: return "收藏的单词与句子"
        case .about: return "版本、边界与实现说明"
        }
    }
}

struct DashboardView: View {
    static var initialPage: DashboardPage?
    @EnvironmentObject var store: ConfigStore
    @State private var selection: DashboardPage = DashboardView.initialPage ?? .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 940, minHeight: 640)
        .background(
            ZStack {
                Theme.bg
                Theme.bgGlow.opacity(0.55)
                    .frame(maxWidth: .infinity, maxHeight: 500, alignment: .top)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                LogoMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("AirLingo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.fg)
                    Text("复刻版 · 本地优先")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.fgSoft.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(DashboardPage.allCases) { page in
                    SidebarItem(page: page, isSelected: selection == page) {
                        selection = page
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                PermissionDot()
                Text("⌃⌃ 双击 Control 划词翻译")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.fgSoft.opacity(0.75))
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.fgSoft.opacity(0.45))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 212)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.03), .clear], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
    }

    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.fg)
                        .tracking(-0.4)
                    Text(selection.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.fgSoft)
                }
                .padding(.top, 30)

                switch selection {
                case .general: GeneralPane()
                case .shortcuts: ShortcutsPane()
                case .engines: EnginesPane()
                case .history: HistoryPane()
                case .favorites: FavoritesPane()
                case .about: AboutPane()
                }
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 侧栏

private struct SidebarItem: View {
    let page: DashboardPage
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 16)
                Text(page.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? Theme.fg : Theme.fgSoft)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.07)
                          : (hovering ? Color.white.opacity(0.04) : Color.clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.brandLite)
                        .frame(width: 2, height: 14)
                        .offset(x: -1)
                }
            }
            // 整行都算点击区域：不加这句时只有文字那几十个点能点中
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct LogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x7C3AED), Color(hex: 0x3B1D8F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct PermissionDot: View {
    @State private var trusted = AccessibilityService.isTrusted
    @State private var screenOK = OCRService.shared.hasScreenPermission

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(trusted ? Color(hex: 0x4ADE80) : Color(hex: 0xFBBF24))
                .frame(width: 6, height: 6)
            Text(trusted ? "辅助功能已授权" : "辅助功能未授权")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.fgSoft)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = AccessibilityService.isTrusted
            screenOK = OCRService.shared.hasScreenPermission
        }
    }
}

// MARK: - 通用

private struct GeneralPane: View {
    @EnvironmentObject var store: ConfigStore
    @State private var launchAtLogin = StartupService.isEnabled
    @State private var startupNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PermissionCard()

            Panel(title: "语言", subtitle: "决定译文往哪边翻。选中文本与母语同语种时，自动译到学习语言。") {
                VStack(spacing: 0) {
                    HStack {
                        Text("我的母语")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.fg)
                        Spacer()
                        Picker("", selection: $store.config.nativeLang) {
                            ForEach(AppLanguage.all) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .tint(Theme.brandLite)
                    }
                    .padding(.vertical, 8)

                    Divider().overlay(Theme.line)

                    HStack {
                        Text("正在学习")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.fg)
                        Spacer()
                        Picker("", selection: $store.config.learnLang) {
                            ForEach(AppLanguage.all) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .tint(Theme.brandLite)
                    }
                    .padding(.vertical, 8)
                }
            }

            Panel(title: "行为", subtitle: nil) {
                VStack(spacing: 0) {
                    ToggleRow(title: "浮窗显示原文", detail: "关掉只看译文，卡片更紧凑", isOn: $store.config.showOriginal)
                    Divider().overlay(Theme.line)
                    ToggleRow(title: "翻译后自动复制", detail: "译文直接进剪贴板", isOn: $store.config.autoCopy)
                    Divider().overlay(Theme.line)
                    ToggleRow(title: "保留翻译历史", detail: "只存在本机，随时可清空", isOn: $store.config.keepHistory)
                    Divider().overlay(Theme.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("开机自动启动")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.fg)
                            Text(startupNote ?? StartupService.statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(startupNote == nil ? Theme.fgSoft : Color(hex: 0xFFB4A2))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in toggleStartup(newValue) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.brand)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleStartup(!launchAtLogin) }

                    Divider().overlay(Theme.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("朗读语速")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.fg)
                            Text("跟读与朗读共用")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.fgSoft)
                        }
                        Spacer()
                        Slider(value: $store.config.speechRate, in: 0.5...1.6)
                            .frame(width: 140)
                            .tint(Theme.brand)
                        Text(String(format: "%.1f×", store.config.speechRate))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.fgSoft)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear { launchAtLogin = StartupService.isEnabled }
    }

    private func toggleStartup(_ enabled: Bool) {
        if let error = StartupService.setEnabled(enabled) {
            startupNote = "设置失败：\(error)"
        } else {
            startupNote = nil
        }
        launchAtLogin = StartupService.isEnabled
    }

    private struct ToggleRow: View {
        let title: String
        let detail: String
        @Binding var isOn: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.fg)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.fgSoft)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.brand)
            }
            .padding(.vertical, 9)
            // 整行可点：点文字也能切换
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
        }
    }
}

private struct PermissionCard: View {
    @State private var trusted = AccessibilityService.isTrusted
    @State private var screenOK = OCRService.shared.hasScreenPermission
    @State private var resetNote: String?

    var body: some View {
        Panel(title: "系统权限", subtitle: "划词和写回要辅助功能；截图翻译要屏幕录制。用不到的可以不授权。") {
            VStack(spacing: 0) {
                row(title: "辅助功能",
                    detail: "读取选中文字、把译文写回输入框",
                    granted: trusted,
                    actionTitle: trusted ? "已开启" : "去开启") {
                    AccessibilityService.requestTrust()
                    AccessibilityService.openSettings()
                }
                Divider().overlay(Theme.line)
                row(title: "屏幕录制",
                    detail: "截图翻译需要抓取屏幕区域",
                    granted: screenOK,
                    actionTitle: screenOK ? "已开启" : "去开启") {
                    OCRService.shared.requestScreenPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }

                if !trusted || !screenOK {
                    Divider().overlay(Theme.line)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0xF5C451))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(resetNote ?? "开关已经是打开状态但仍显示未开启？这是旧版本遗留的失效记录，重置后重新授权即可。屏幕录制授权后还需要重开应用才生效。")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.fgSoft)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                if !trusted {
                                    Button {
                                        let ok = AccessibilityService.resetAuthorization()
                                        resetNote = ok
                                            ? "辅助功能记录已清空。请在系统设置里重新勾选 AirLingo，然后点「重启应用」。"
                                            : "重置失败，可以手动在系统设置里用「−」移除 AirLingo 再重新添加。"
                                        AccessibilityService.requestTrust()
                                        AccessibilityService.openSettings()
                                    } label: {
                                        Text("重置辅助功能授权")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Theme.brandLite)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.white.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }

                                if !screenOK {
                                    Button {
                                        let ok = AccessibilityService.resetTCC("ScreenCapture")
                                        resetNote = ok
                                            ? "屏幕录制记录已清空。请在系统设置里重新勾选 AirLingo，然后点「重启应用」。"
                                            : "重置失败，可以手动在系统设置里用「−」移除 AirLingo 再重新添加。"
                                        OCRService.shared.requestScreenPermission()
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        Text("重置屏幕录制授权")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Theme.brandLite)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.white.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    AppDelegate.relaunch()
                                } label: {
                                    Text("重启应用")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.fgSoft)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.04)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = AccessibilityService.isTrusted
            screenOK = OCRService.shared.hasScreenPermission
        }
    }

    private func row(title: String, detail: String, granted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Color(hex: 0x4ADE80) : Theme.fgSoft)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.fg)
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.fgSoft)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(granted ? Theme.fgSoft : Theme.brandLite)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 通用容器

struct Panel<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.fgSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 18)
    }
}
