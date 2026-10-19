import SwiftUI
import AppKit

/// 底部临时浮标：轻提示。贴在屏幕底部居中，不抢焦点。
@MainActor
final class HUD {
    static let shared = HUD()

    private var toastPanel: NSPanel?
    private var toastToken = 0
    private var started = false

    func start() {
        guard !started else { return }
        started = true
    }

    // MARK: - 轻提示

    func toast(_ message: String) {
        toastToken += 1
        let token = toastToken

        let hosting = NSHostingView(rootView: ToastView(message: message))
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = max(220, size.width)
        hosting.frame = NSRect(origin: .zero, size: size)

        if toastPanel == nil {
            let panel = HUDWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered,
                                  defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            toastPanel = panel
        }
        guard let panel = toastPanel else { return }
        panel.contentView = hosting
        panel.setContentSize(size)
        position(panel, bottomOffset: 42)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.toastToken == token, let panel = self.toastPanel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func position(_ panel: NSPanel, bottomOffset: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + bottomOffset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: 开发期自检

    func debugSnapshot(to directory: String) {
        let hosting = NSHostingView(rootView: ToastView(message: "截图翻译需要屏幕录制权限，去「系统设置 › 隐私与安全性 › 屏幕录制」打开后重启应用"))
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        let size = NSSize(width: max(1, fit.width), height: max(1, fit.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "\(directory)/hud-toast.png"))
        }
        print("HUD toast size=\(Int(size.width))x\(Int(size.height))")
    }
}

/// HUD 面板不参与应用激活。
final class HUDWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - 轻提示视图

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.brandLite)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(Theme.panel.opacity(0.97))
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .padding(8)
    }
}
