import SwiftUI
import AppKit

/// 按键录制：把「手打 double:ctrl 这种字符串」换成真按一次。
/// 按下组合键录成 `Alt+Cmd+O`，连续点两下修饰键录成 `double:ctrl`。
struct HotkeyRecorder: NSViewRepresentable {
    var onCapture: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }

    final class RecorderView: NSView {
        var onCapture: ((String) -> Void)?
        var onCancel: (() -> Void)?

        private var lastModifierTap: (name: String, time: TimeInterval)?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // 别让菜单快捷键把按键截走
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {          // Esc 取消
                onCancel?()
                return
            }
            guard let spec = Self.spec(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
                NSSound.beep()
                return
            }
            onCapture?(spec)
        }

        /// 把一次按键翻译成 HotkeyCenter 认识的写法。
        static func spec(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
            guard let name = keyName(keyCode: keyCode) else { return nil }

            let flags = modifiers.intersection(.deviceIndependentFlagsMask)
            var parts: [String] = []
            if flags.contains(.control) { parts.append("Ctrl") }
            if flags.contains(.option) { parts.append("Alt") }
            if flags.contains(.shift) { parts.append("Shift") }
            if flags.contains(.command) { parts.append("Cmd") }

            let isFunctionKey = name.hasPrefix("F") && name.count <= 3
            if parts.isEmpty && !isFunctionKey { return nil }
            parts.append(name)

            let spec = parts.joined(separator: "+")
            return HotkeyCenter.parse(spec) == nil ? nil : spec
        }

        override func flagsChanged(with event: NSEvent) {
            guard let name = Self.modifierName(for: event) else { return }
            // 只有「按下」这一帧才计数
            let isDown: Bool
            switch name {
            case "ctrl": isDown = event.modifierFlags.contains(.control)
            case "alt": isDown = event.modifierFlags.contains(.option)
            case "shift": isDown = event.modifierFlags.contains(.shift)
            case "cmd", "rcmd": isDown = event.modifierFlags.contains(.command)
            default: isDown = false
            }
            guard isDown else { return }

            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastModifierTap, last.name == name, now - last.time < 0.45 {
                lastModifierTap = nil
                onCapture?("double:\(name)")
            } else {
                lastModifierTap = (name, now)
            }
        }

        // MARK: 键名

        static func modifierName(for event: NSEvent) -> String? {
            switch event.keyCode {
            case 59, 62: return "ctrl"
            case 58, 61: return "alt"
            case 54: return "rcmd"
            case 55: return "cmd"
            case 56, 60: return "shift"
            default: return nil
            }
        }

        static func keyName(keyCode: UInt16) -> String? {
            // 用 keyCode 反查，避免 Ctrl+字母被系统转成控制字符
            guard let token = reverseKeyCodes[keyCode] else { return nil }
            return token.uppercased()
        }

        private static let reverseKeyCodes: [UInt16: String] = {
            var map: [UInt16: String] = [:]
            for (token, code) in HotkeyCenter.keyCodes {
                map[UInt16(code)] = token
            }
            return map
        }()
    }
}
