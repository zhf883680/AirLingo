import SwiftUI
import AppKit

// MARK: - 历史

struct HistoryPane: View {
    @ObservedObject private var history = HistoryStore.shared
    @State private var query = ""

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter {
            $0.source.localizedCaseInsensitiveContains(query) ||
            $0.target.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.fgSoft)
                    TextField("搜索原文或译文", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.fg)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))

                Spacer()

                Text("\(history.items.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgSoft)

                Button("清空") { history.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .disabled(history.items.isEmpty)
            }

            if filtered.isEmpty {
                EmptyState(icon: "clock", title: "还没有记录", detail: "翻译过的内容会自动留在这里，只存在本机。")
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered) { item in
                        ItemRow(item: item)
                        if item.id != filtered.last?.id {
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .glassCard(padding: 6)
            }
        }
    }
}

// MARK: - 收藏

struct FavoritesPane: View {
    @ObservedObject private var history = HistoryStore.shared

    private var favorites: [HistoryItem] { history.favorites }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(favorites.count) 条收藏")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.fgSoft)
                Spacer()
                Button("全部取消收藏") { history.clearFavorites() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.fgSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .disabled(favorites.isEmpty)
            }

            if favorites.isEmpty {
                EmptyState(icon: "star", title: "还没有收藏", detail: "浮窗右下角点星标，单词和句子都能收进来。")
            } else {
                VStack(spacing: 0) {
                    ForEach(favorites) { item in
                        ItemRow(item: item, showSpeak: true)
                        if item.id != favorites.last?.id {
                            Divider().overlay(Theme.line)
                        }
                    }
                }
                .glassCard(padding: 6)
            }
        }
    }
}

private struct ItemRow: View {
    let item: HistoryItem
    var showSpeak: Bool = false
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.source)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fgSoft)
                    .lineLimit(2)
                Text(item.target)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(item.engine)
                    Text("·")
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.fgSoft.opacity(0.6))
            }
            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if showSpeak {
                    iconButton("speaker.wave.2") {
                        Speaker.speak(item.target, language: ConfigStore.shared.config.nativeLang)
                    }
                }
                iconButton(item.favorite ? "star.fill" : "star", active: item.favorite) {
                    history.toggleFavorite(item.id)
                }
                iconButton("doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.target, forType: .string)
                }
                iconButton("trash") { history.remove(item.id) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func iconButton(_ name: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 10.5))
                .foregroundStyle(active ? Theme.brandLite : Theme.fgSoft.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.fgSoft.opacity(0.55))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fg)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.fgSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .glassCard(padding: 0)
    }
}

// MARK: - 关于

struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "AirLingo 1.0.0", subtitle: "Trancy Air 的独立复刻实现，原生 SwiftUI，本地优先。") {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("技术栈", "SwiftUI + AppKit + Carbon 热键 + ScreenCaptureKit + Vision")
                    Divider().overlay(Theme.line)
                    HStack(alignment: .top, spacing: 12) {
                        infoRow("数据位置", ConfigStore.shared.storageDirectory.path)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.shared.storageDirectory])
                        } label: {
                            Text("在 Finder 中显示")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.brandLite)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().overlay(Theme.line)
                    infoRow("网络", "只在你触发翻译时请求所选引擎；不经过任何中间服务器")
                    Divider().overlay(Theme.line)
                    infoRow("凭据", "API Key 只写在本机 Application Support 下的 config.json，不会上传")
                }
            }

            Panel(title: "已实现", subtitle: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(featureList) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(item.done ? Color(hex: 0x4ADE80) : Theme.fgSoft.opacity(0.5))
                                .padding(.top, 1)
                            Text(item.title)
                                .font(.system(size: 11.5))
                                .foregroundStyle(item.done ? Theme.fg : Theme.fgSoft)
                        }
                    }
                }
            }

            Panel(title: "边界", subtitle: nil) {
                Text("""
                这是一个独立实现：界面与交互参考 Trancy Air，代码、资源全部重新编写，不包含原版任何二进制、素材或私有接口。
                原版的 AI 释义、语法分析、跟读评测走 Trancy 自家服务，本版本不做对接；对应位置用系统能力与所选引擎替代。
                请仅用于个人研究与自用，不要把复刻品作为商业替代品分发。
                """)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.fgSoft)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct FeatureItem: Identifiable {
        let id = UUID()
        let title: String
        let done: Bool

        init(_ title: String, _ done: Bool) {
            self.title = title
            self.done = done
        }
    }

    private var featureList: [FeatureItem] {
        [
            FeatureItem("双击修饰键 / 组合键触发全局翻译", true),
            FeatureItem("快捷键按键录制：按下即生效，带冲突校验", true),
            FeatureItem("划词浮窗：原文、译文、引擎切换、复制、收藏、朗读", true),
            FeatureItem("静默翻译：译文原地替换输入框内容", true),
            FeatureItem("截图翻译：框选 → Vision 取字 → 翻译，失败有提示", true),
            FeatureItem("多引擎：Apple 系统翻译 / Google / OpenAI 兼容 / DeepL / Ollama", true),
            FeatureItem("对比翻译：多个引擎并排展示，逐条可复制", true),
            FeatureItem("翻译历史与收藏（本地 JSON），菜单栏可回看最近翻译", true),
            FeatureItem("开机自动启动（系统登录项）", true),
            FeatureItem("句句对齐、AI 语法分析、跟读打分", false),
            FeatureItem("浅色主题与界面缩放（当前固定深色）", false)
        ]
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.fgSoft)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
