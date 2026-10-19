import AppKit
import ApplicationServices

/// 通过系统辅助功能接口读取选中文字、定位控件、把译文写回。
enum AccessibilityService {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 清掉系统里本应用的辅助功能记录。
    /// 开发期重新签名后，系统可能还留着绑定旧签名的失效记录（开关是开的但实际不授权），
    /// 这种情况必须重置后再重新授权。
    @discardableResult
    static func resetAuthorization() -> Bool {
        resetTCC("Accessibility")
    }

    /// 清掉某个隐私服务里本应用的记录（Accessibility / ScreenCapture）。
    @discardableResult
    static func resetTCC(_ service: String) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 应用当前的指定要求（designated requirement），用来判断授权是否绑在当前这份构建上。
    static var signingRequirement: String {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "-r-", path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "未知"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") where line.contains("designated") {
            return String(line).trimmingCharacters(in: .whitespaces)
        }
        return "未签名"
    }

    // MARK: - 焦点元素

    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        if let text = string(element, kAXSelectedTextAttribute), !text.isEmpty {
            return text
        }
        return nil
    }

    static func value() -> String? {
        guard let element = focusedElement() else { return nil }
        return string(element, kAXValueAttribute)
    }

    static func selectedRange() -> NSRange? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// 焦点控件的屏幕位置，用于把浮窗贴到选区旁边。
    static func focusedFrame() -> CGRect? {
        guard let element = focusedElement() else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }

        // AX 坐标系原点在主屏左上角，转成 NSScreen 的底部原点坐标。
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let rect = CGRect(x: point.x, y: screenHeight - point.y - size.height, width: size.width, height: size.height)
        return rect
    }

    // MARK: - 读取选区（AX 失败时退回剪贴板）

    static func readSelection() async -> String? {
        if let text = selectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return await copySelectionViaKeyboard()
    }

    private static func copySelectionViaKeyboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let backup = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        } ?? []
        let previousChangeCount = pasteboard.changeCount

        postCommandKey(8) // C
        try? await Task.sleep(nanoseconds: 140_000_000)

        var text: String?
        if pasteboard.changeCount != previousChangeCount {
            text = pasteboard.string(forType: .string)
        }

        if !backup.isEmpty {
            pasteboard.clearContents()
            let items = backup.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    // MARK: - 写回

    @discardableResult
    static func replaceSelection(with text: String) -> Bool {
        guard let element = focusedElement() else { return false }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                return true
            }
        }

        // 退化方案：拿到整段文本和选区，替换后整体写回。
        if let value = string(element, kAXValueAttribute),
           let range = selectedRange(),
           let swiftRange = Range(range, in: value) {
            let updated = value.replacingCharacters(in: swiftRange, with: text)
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef) == .success {
                return true
            }
        }

        // 最后兜底：粘帖板 + Cmd+V。
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandKey(9) // V
        return true
    }

    @discardableResult
    static func insertText(_ text: String) -> Bool {
        replaceSelection(with: text)
    }

    private static func postCommandKey(_ code: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
