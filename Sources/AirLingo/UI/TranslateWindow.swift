import AppKit
import SwiftUI

/// 主动翻译的悬浮窗口：和划词浮窗一样贴在所有应用之上，但可以输入和快捷键翻译。
@MainActor
final class TranslateWindowController {
    static let shared = TranslateWindowController()

    private var panel: FloatingPanel?
    private var hosting: NSView?
    private var positioned = false
    private var keyMonitor: Any?

    func show() {
        installKeyMonitor()
        let root = TranslatePane(onClose: { [weak self] in self?.hide() })
            .environmentObject(ConfigStore.shared)
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 460)

        if panel == nil {
            let panel = FloatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .utilityWindow
            panel.isReleasedWhenClosed = false
            panel.onCancel = { [weak self] in self?.hide() }
            self.panel = panel
        }
        guard let panel else { return }

        panel.contentView = hosting
        self.hosting = hosting

        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let size = NSSize(width: max(620, ceil(fitted.width.isFinite ? fitted.width : 620)),
                          height: max(430, ceil(fitted.height.isFinite ? fitted.height : 460)))

        var frame = panel.frame
        frame.size = size
        if !positioned, let vf = screenUnderMouse()?.visibleFrame {
            frame.origin = NSPoint(x: vf.midX - size.width / 2,
                                   y: vf.midY - size.height / 2 + 24)
            positioned = true
        }
        if let vf = (screenUnderMouse() ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            frame.origin.y = min(max(frame.origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        }
        panel.setFrame(frame, display: true)

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .airLingoFocusTranslateInput, object: nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// TextEditor 有焦点时会吞掉 ⌘↵ / Esc，这里在窗口级别兜底。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  panel.isVisible,
                  panel.isKeyWindow else { return event }

            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(name: .airLingoTriggerTranslate, object: nil)
                return nil
            }
            return event
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }
}
