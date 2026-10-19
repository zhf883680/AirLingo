import AppKit
import Carbon.HIToolbox

/// 全局快捷键：组合键走 Carbon，双击修饰键走 flagsChanged 监听。
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var combos: [UInt32: (String, () -> Void)] = [:]
    private var doubles: [String: () -> Void] = [:]
    private var tapTimes: [UInt16: TimeInterval] = [:]
    private var monitors: [Any] = []
    private var nextID: UInt32 = 1
    /// 注册失败的写法，设置页里提示用户换一个。
    private(set) var failedSpecs: [String] = []

    private init() {}

    func configure(shortcuts: [(spec: String, action: () -> Void)]) {
        unregisterAll()
        failedSpecs = []
        for entry in shortcuts {
            let spec = entry.spec.trimmingCharacters(in: .whitespaces)
            guard !spec.isEmpty else { continue }
            if spec.hasPrefix("double:") {
                let modifier = String(spec.dropFirst("double:".count)).lowercased()
                doubles[modifier] = entry.action
            } else if let parsed = Self.parse(spec) {
                registerCombo(keyCode: parsed.keyCode, modifiers: parsed.modifiers, spec: spec, action: entry.action)
            }
        }
        installFlagsMonitor()
    }

    func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        combos.removeAll()
        doubles.removeAll()

        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    // MARK: - 组合键

    private func installCarbonHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                center.combos[hotKeyID.id]?.1()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func registerCombo(keyCode: UInt32, modifiers: UInt32, spec: String, action: @escaping () -> Void) {
        installCarbonHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4149524C), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("AirLingo: 快捷键注册失败 \(spec) status=\(status)")
            failedSpecs.append(spec)
            return
        }
        hotKeyRefs.append(ref)
        combos[id] = (spec, action)
    }

    // MARK: - 双击修饰键

    private func installFlagsMonitor() {
        guard !doubles.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        if let global { monitors.append(global) }
        if let local { monitors.append(local) }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let code = event.keyCode
        let pressed: Bool
        switch code {
        case 59, 62: pressed = event.modifierFlags.contains(.control)
        case 58, 61: pressed = event.modifierFlags.contains(.option)
        case 55, 54: pressed = event.modifierFlags.contains(.command)
        case 56, 60: pressed = event.modifierFlags.contains(.shift)
        default: return
        }

        let modifier: String?
        switch code {
        case 59, 62: modifier = "ctrl"
        case 58, 61: modifier = "alt"
        case 54: modifier = "rcmd"
        case 55: modifier = "cmd"
        case 56, 60: modifier = "shift"
        default: modifier = nil
        }
        guard let modifier, doubles[modifier] != nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if pressed {
            if let last = tapTimes[code], now - last < 0.45 {
                tapTimes[code] = nil
                doubles[modifier]?()
            } else {
                tapTimes[code] = now
            }
        }
    }

    // MARK: - 解析

    static func parse(_ spec: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = spec.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let key = parts.last, let keyCode = keyCodes[key] else { return nil }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "alt", "option", "opt", "⌥": modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        return (keyCode, modifiers)
    }

    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "return": 36, "tab": 48, "esc": 53, "delete": 51,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]

    static func describe(_ spec: String) -> String {
        if spec.hasPrefix("double:") {
            switch String(spec.dropFirst("double:".count)).lowercased() {
            case "ctrl": return "双击 ⌃"
            case "alt": return "双击 ⌥"
            case "rcmd": return "双击 ⌘（右）"
            case "cmd": return "双击 ⌘"
            case "shift": return "双击 ⇧"
            default: return "双击修饰键"
            }
        }

        let parts = spec.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for (index, part) in parts.enumerated() {
            let lower = part.lowercased()
            if index < parts.count - 1 {
                switch lower {
                case "cmd", "command", "⌘": out.append("⌘")
                case "alt", "option", "opt", "⌥": out.append("⌥")
                case "ctrl", "control", "⌃": out.append("⌃")
                case "shift", "⇧": out.append("⇧")
                default: out.append(part)
                }
            } else {
                switch lower {
                case "space": out.append("Space")
                case "return": out.append("↩")
                case "tab": out.append("⇥")
                case "esc": out.append("⎋")
                case "delete": out.append("⌫")
                case "left": out.append("←")
                case "right": out.append("→")
                case "up": out.append("↑")
                case "down": out.append("↓")
                default: out.append(part.uppercased())
                }
            }
        }
        return out.joined(separator: " ")
    }
}
