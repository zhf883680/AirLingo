import SwiftUI
import AppKit
import Translation

@main
struct AirLingoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(ConfigStore.shared)
        } label: {
            Image(systemName: "character.bubble.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppController.shared.bootstrap()
        writeBootStatus()
        healAccessibilityRecord()
        healScreenRecord()
        MainActor.assumeIsolated {
            OCRService.shared.probeCaptureCapability()
        }

        // 离屏渲染界面快照，用于开发期自检：AirLingo --snapshot <path>
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            if index + 2 < CommandLine.arguments.count {
                DashboardView.initialPage = DashboardPage(rawValue: CommandLine.arguments[index + 2])
            }
            var height: CGFloat = 700
            if index + 3 < CommandLine.arguments.count, let value = Double(CommandLine.arguments[index + 3]) {
                height = CGFloat(value)
            }
            // 延到 1.4 秒：让页面里的异步状态检测（语言包、权限）跑完再截图
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                MainActor.assumeIsolated {
                    Self.renderSnapshot(to: path, height: height)
                }
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --hud-snapshot <目录>
        if let index = CommandLine.arguments.firstIndex(of: "--hud-snapshot"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { HUD.shared.debugSnapshot(to: dir) }
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --translate-snapshot <path>（带译文，检查主动翻译弹窗排版）
        if let index = CommandLine.arguments.firstIndex(of: "--translate-snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { Self.renderTranslateSnapshot(to: path) }
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --ui-record-test <目录>
        // 切到快捷键页 → 点第一个键位 → 真按一次 ⌥⌘K → 截图看是否录进去
        if let index = CommandLine.arguments.firstIndex(of: "--ui-record-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                DashboardWindowController.shared.show()
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let window = NSApp.windows.first(where: { $0.title == "AirLingo" }) else {
                    NSApp.terminate(nil)
                    return
                }
                let frame = window.frame
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                func cg(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint {
                    CGPoint(x: frame.minX + x, y: mainHeight - (frame.maxY - yFromTop))
                }
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(nanoseconds: 250_000_000)

                let source = CGEventSource(stateID: .hidSystemState)
                func click(_ point: CGPoint) {
                    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(90_000)
                    for _ in 0..<2 {
                        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        usleep(50_000)
                        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                        usleep(280_000)
                    }
                }

                click(cg(168, 148))            // 侧栏「快捷键」
                try? await Task.sleep(nanoseconds: 400_000_000)
                click(cg(877, 219))            // 第一行的键位按钮
                try? await Task.sleep(nanoseconds: 500_000_000)

                let flags: CGEventFlags = [.maskCommand, .maskAlternate]
                let down = CGEvent(keyboardEventSource: source, virtualKey: 40, keyDown: true)
                down?.flags = flags
                down?.post(tap: .cghidEventTap)
                usleep(60_000)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 40, keyDown: false)
                up?.flags = flags
                up?.post(tap: .cghidEventTap)

                try? await Task.sleep(nanoseconds: 700_000_000)
                Self.snapshotWindow(window, to: "\(dir)/ui-record.png")
                print("RECORD TEST done")
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --ui-click-test <目录>
        // 打开控制台窗口 → 在侧栏「快捷键」行的空白处真实点一下 → 截图看是否切过去了
        if let index = CommandLine.arguments.firstIndex(of: "--ui-click-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                DashboardWindowController.shared.show()
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let window = NSApp.windows.first(where: { $0.title == "AirLingo" }) else {
                    NSApp.terminate(nil)
                    return
                }
                Self.snapshotWindow(window, to: "\(dir)/ui-before.png")

                let frame = window.frame
                // 第二个侧栏行（快捷键）右侧的空白区域
                let localX: CGFloat = 168
                let localYFromTop: CGFloat = 148
                let nsPoint = NSPoint(x: frame.minX + localX, y: frame.maxY - localYFromTop)
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                let cgPoint = CGPoint(x: nsPoint.x, y: mainHeight - nsPoint.y)

                let source = CGEventSource(stateID: .hidSystemState)
                NSApp.activate(ignoringOtherApps: true)
                usleep(250_000)
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(120_000)
                // 第一次点击可能只是把窗口激活，所以点两次
                for _ in 0..<2 {
                    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(60_000)
                    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(320_000)
                }

                try? await Task.sleep(nanoseconds: 700_000_000)
                Self.snapshotWindow(window, to: "\(dir)/ui-after.png")
                print("CLICK at \(cgPoint) window=\(frame)")
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --translate-popup-test <目录>
        // 打开主动翻译弹窗 → ⌘V 粘贴 → ⌘↵ 翻译，检查译文和历史是否真的写入
        if let index = CommandLine.arguments.firstIndex(of: "--translate-popup-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                let startedAt = Date()
                TranslateWindowController.shared.show()
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let window = NSApp.windows.first(where: { $0 is FloatingPanel && $0.isVisible }) else {
                    NSApp.terminate(nil)
                    return
                }

                let sample = "保存策略占用了内存，需要确认影响范围。"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(sample, forType: .string)
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(nanoseconds: 300_000_000)

                let source = CGEventSource(stateID: .hidSystemState)
                func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
                    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
                    down?.flags = flags
                    down?.post(tap: .cghidEventTap)
                    usleep(60_000)
                    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
                    up?.flags = flags
                    up?.post(tap: .cghidEventTap)
                }

                press(9, flags: .maskCommand)                     // ⌘V
                try? await Task.sleep(nanoseconds: 400_000_000)
                Self.snapshotWindow(window, to: "\(dir)/translate-typed.png")

                press(36, flags: .maskCommand)                    // ⌘↵
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                Self.snapshotWindow(window, to: "\(dir)/translate-after.png")

                let fresh = HistoryStore.shared.items.filter { $0.date >= startedAt }
                if let item = fresh.first {
                    print("TRANSLATE_PAGE ok source=\(item.source) target=\(item.target)")
                } else {
                    print("TRANSLATE_PAGE no-history item=\(String(describing: HistoryStore.shared.items.first))")
                }
                // 自检产生的记录不留在用户历史里。
                fresh.forEach { HistoryStore.shared.remove($0.id) }

                press(53)                                         // Esc
                try? await Task.sleep(nanoseconds: 400_000_000)
                print("TRANSLATE_PAGE esc_closed=\(!window.isVisible)")
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --login-test（注册登录项再取消，检查 SMAppService 是否可用）
        if CommandLine.arguments.contains("--login-test") {
            print("初始状态: \(StartupService.statusText) / enabled=\(StartupService.isEnabled) / supported=\(StartupService.isSupported)")
            let registerError = StartupService.setEnabled(true)
            print("注册结果: \(registerError ?? "成功") -> enabled=\(StartupService.isEnabled) / \(StartupService.statusText)")
            let unregisterError = StartupService.setEnabled(false)
            print("取消结果: \(unregisterError ?? "成功") -> enabled=\(StartupService.isEnabled) / \(StartupService.statusText)")
            NSApp.terminate(nil)
            return
        }

        // 命令行自检：AirLingo --hotkey-test
        if CommandLine.arguments.contains("--hotkey-test") {
            let cases: [(String, UInt16, NSEvent.ModifierFlags)] = [
                ("Ctrl+O", 31, .control),
                ("Ctrl+Shift+O", 31, [.control, .shift]),
                ("Alt+Cmd+Space", 49, [.option, .command]),
                ("F3", 99, []),
                ("无修饰 A（应被拒）", 0, []),
                ("Alt+Left", 123, .option)
            ]
            for (label, code, flags) in cases {
                let spec = HotkeyRecorder.RecorderView.spec(keyCode: code, modifiers: flags)
                let parsed = spec.flatMap { HotkeyCenter.parse($0) }
                print("\(label) -> \(spec ?? "nil") | parse=\(parsed == nil ? "nil" : "ok") | 显示=\(spec.map(HotkeyCenter.describe) ?? "-")")
            }
            NSApp.terminate(nil)
            return
        }

        // 命令行自检：AirLingo --ocr-test <目录>
        // 造一个写着已知文字的窗口 → 用选区坐标去抓它 → 比对识别结果
        if let index = CommandLine.arguments.firstIndex(of: "--ocr-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                var log = ""
                func line(_ text: String) {
                    log += text + "\n"
                    print(text)
                }
                line("trusted=\(AXIsProcessTrusted()) preflight=\(CGPreflightScreenCaptureAccess()) effective=\(OCRService.shared.hasScreenPermission)")

                guard let screen = NSScreen.main else {
                    line("ERROR: 没有主屏")
                    NSApp.terminate(nil)
                    return
                }

                let window = NSWindow(contentRect: NSRect(x: 320, y: 320, width: 620, height: 220),
                                      styleMask: [.titled],
                                      backing: .buffered,
                                      defer: false)
                window.title = "OCR TEST"
                window.isReleasedWhenClosed = false
                window.level = .floating
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 220))
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.white.cgColor
                let label = NSTextField(labelWithString: "AIRLINGO OCR 12345")
                label.font = NSFont.systemFont(ofSize: 30, weight: .semibold)
                label.textColor = .black
                label.frame = NSRect(x: 30, y: 90, width: 560, height: 40)
                container.addSubview(label)
                window.contentView = container
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(nanoseconds: 700_000_000)

                // 1) 视图坐标 → 屏幕坐标 的镜像换算自检
                let prober = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                let selection = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
                prober.contentView = selection
                let viewRect = NSRect(x: 100, y: 100, width: 200, height: 60)
                let mapped = selection.screenRect(forViewRect: viewRect)
                let expected = NSRect(x: screen.frame.minX + 100,
                                      y: screen.frame.maxY - 160,
                                      width: 200,
                                      height: 60)
                line("map: view=\(viewRect) -> screen=\(mapped.map { "\($0)" } ?? "nil")")
                line("map expected=\(expected) ok=\(mapped.map { abs($0.minY - expected.minY) < 0.5 && abs($0.minX - expected.minX) < 0.5 } ?? false)")

                // 2) 抓取文字窗口所在区域
                let frame = window.frame
                let hitRect = NSRect(x: frame.minX + 20, y: frame.minY + 70,
                                     width: frame.width - 40, height: 90)
                let shot = NSRect(x: hitRect.minX, y: hitRect.minY, width: hitRect.width, height: hitRect.height)
                line("capture rect=\(shot) displayRect=\(OCRService.displayRect(for: shot, screen: screen))")
                do {
                    let text = try await OCRService.shared.debugRecognize(shot)
                    line("RESULT: \(text ?? "nil")")
                } catch {
                    line("ERROR: \(error.localizedDescription)")
                }

                // 3) 负样本：窗口下方空白区域，正常应该没有字
                let blankRect = NSRect(x: frame.minX + 20, y: max(0, frame.minY - 260), width: 400, height: 80)
                do {
                    let text = try await OCRService.shared.debugRecognize(blankRect)
                    line("BLANK RESULT: \(text ?? "nil")")
                } catch {
                    line("BLANK ERROR: \(error.localizedDescription)")
                }

                try? log.write(toFile: "\(dir)/ocr-test.txt", atomically: true, encoding: .utf8)
                window.close()
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --ocr-drag-test <目录>
        // 真走一遍「按快捷键 → 框选 → 取字 → 翻译」，验证坐标没有上下翻转
        if let index = CommandLine.arguments.firstIndex(of: "--ocr-drag-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Task { @MainActor in
                let window = NSWindow(contentRect: NSRect(x: 320, y: 320, width: 620, height: 220),
                                      styleMask: [.titled],
                                      backing: .buffered,
                                      defer: false)
                window.title = "OCR DRAG TEST"
                window.isReleasedWhenClosed = false
                window.level = .floating
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 220))
                container.wantsLayer = true
                container.layer?.backgroundColor = NSColor.white.cgColor
                let label = NSTextField(labelWithString: "AIRLINGO DRAG 67890")
                label.font = NSFont.systemFont(ofSize: 30, weight: .semibold)
                label.textColor = .black
                label.frame = NSRect(x: 30, y: 90, width: 560, height: 40)
                container.addSubview(label)
                window.contentView = container
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try? await Task.sleep(nanoseconds: 700_000_000)

                AppController.shared.ocrTranslate()
                try? await Task.sleep(nanoseconds: 800_000_000)

                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                func cg(_ x: CGFloat, _ appKitY: CGFloat) -> CGPoint {
                    CGPoint(x: x, y: mainHeight - appKitY)
                }
                let source = CGEventSource(stateID: .hidSystemState)
                let start = cg(350, 470)
                let end = cg(900, 395)
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(180_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(120_000)
                for step in 1...12 {
                    let t = CGFloat(step) / 12
                    let point = CGPoint(x: start.x + (end.x - start.x) * t,
                                        y: start.y + (end.y - start.y) * t)
                    CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    usleep(35_000)
                }
                CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)

                try? await Task.sleep(nanoseconds: 4_000_000_000)
                PopupController.shared.debugReport(to: dir)
                try? await Task.sleep(nanoseconds: 400_000_000)
                window.close()
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --compare-test <目录>
        if let index = CommandLine.arguments.firstIndex(of: "--compare-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let anchor = CGPoint(x: 700, y: 700)
            Task { @MainActor in
                print("compareEngines=\(ConfigStore.shared.compareEngines.map(\.name))")
                PopupController.shared.show(source: "保存策略的时候 占了 这个是部门策略的关系应该",
                                            engineID: "google",
                                            mode: .compare,
                                            anchor: anchor)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                PopupController.shared.debugReport(to: dir)
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --popup-apple-test <目录> —— 弹窗 + Apple 引擎真实翻译
        if let index = CommandLine.arguments.firstIndex(of: "--popup-apple-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let anchor = CGPoint(x: 700, y: 700)
            Task { @MainActor in
                PopupController.shared.show(source: "这是一段测试文字，用来检查翻译功能。",
                                            engineID: "apple",
                                            mode: .translate,
                                            anchor: anchor)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                PopupController.shared.debugReport(to: dir)
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --popup-live-test <目录>
        if let index = CommandLine.arguments.firstIndex(of: "--popup-live-test"),
           index + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[index + 1]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let anchor = CGPoint(x: 700, y: 700)
            Task { @MainActor in
                PopupController.shared.show(source: "保存策略的时候 占了 这个是部门策略的关系应该",
                                            engineID: "google",
                                            mode: .translate,
                                            anchor: anchor)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                PopupController.shared.debugReport(to: dir)
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --popup-snapshot <path> [--long]
        if let index = CommandLine.arguments.firstIndex(of: "--popup-snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            let long = CommandLine.arguments.contains("--long")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    Self.renderPopupSnapshot(to: path, long: long)
                }
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --apple-pairs [日志路径] —— 打印各语言对的语言包状态
        if CommandLine.arguments.contains("--apple-pairs") {
            let logPath = "/tmp/airlingo-apple-pairs.log"
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let handle = FileHandle(forWritingAtPath: logPath)
            func log(_ line: String) {
                handle?.write((line + "\n").data(using: .utf8)!)
                print(line)
            }
            Task { @MainActor in
                guard #available(macOS 15.0, *) else {
                    log("ERROR: 需要 macOS 15+")
                    NSApp.terminate(nil)
                    return
                }
                let pairs: [(String, String)] = [
                    ("en", "zh-Hans"), ("zh-Hans", "en"),
                    ("zh-Hant", "en"), ("ja", "zh-Hans"),
                    ("en", "ja"), ("fr", "en"), ("en", "fr")
                ]
                let availability = LanguageAvailability()
                for (from, to) in pairs {
                    let raw = await availability.status(from: Locale.Language(identifier: from),
                                                        to: Locale.Language(identifier: to))
                    let label: String
                    switch raw {
                    case .installed: label = "已安装"
                    case .supported: label = "系统支持但未下载"
                    case .unsupported: label = "不支持"
                    @unknown default: label = "未知"
                    }
                    log("PAIR \(from) -> \(to): \(label)")
                }
                let chinese = "这是一段测试文字，用来检查翻译功能。"
                log("DETECT: \(AppleTranslateService.detect(chinese) ?? "nil")")
                let traditional = "這是一段測試文字，用來檢查翻譯功能。"
                log("DETECT(繁): \(AppleTranslateService.detect(traditional) ?? "nil")")
                log("NAME(zh-Hant): \(AppLanguage.name(for: "zh-Hant")) / NAME(zh-Hans): \(AppLanguage.name(for: "zh-Hans"))")
                do {
                    let result = try await AppleTranslateService.shared.translate(chinese, to: "en")
                    log("ZH->EN RESULT: \(result.text)  (检测到 \(result.source ?? "nil"))")
                } catch {
                    log("ZH->EN ERROR: \(error.localizedDescription)")
                }

                // 故意挑一个没装语言包的方向，确认失败会被正确归类，且不会卡很久
                for target in ["fr", "th"] {
                    let started = Date()
                    do {
                        let result = try await AppleTranslateService.shared.translate(chinese, to: target)
                        log("ZH->\(target.uppercased()) RESULT: \(result.text)")
                    } catch {
                        let cost = String(format: "%.1f", Date().timeIntervalSince(started))
                        log("ZH->\(target.uppercased()) ERROR(\(cost)s): \(error.localizedDescription)")
                    }
                }

                // 失败后宿主被重建过，确认后续翻译仍然正常
                do {
                    let result = try await AppleTranslateService.shared.translate(chinese, to: "en")
                    log("RECHECK ZH->EN: \(result.text)")
                } catch {
                    log("RECHECK ZH->EN ERROR: \(error.localizedDescription)")
                }
                handle?.closeFile()
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --apple-test "Hello" [日志路径]
        if let index = CommandLine.arguments.firstIndex(of: "--apple-test"),
           index + 1 < CommandLine.arguments.count {
            let text = CommandLine.arguments[index + 1]
            let logPath = index + 2 < CommandLine.arguments.count
                ? CommandLine.arguments[index + 2]
                : "/tmp/airlingo-apple-test.log"
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let handle = FileHandle(forWritingAtPath: logPath)
            func log(_ line: String) {
                handle?.write((line + "\n").data(using: .utf8)!)
                NSLog("AirLingo probe: %@", line)
            }
            Task { @MainActor in
                guard #available(macOS 15.0, *) else {
                    log("ERROR: 需要 macOS 15 或更高版本")
                    handle?.closeFile()
                    NSApp.terminate(nil)
                    return
                }
                let st = await AppleTranslateService.shared.status(for: text, target: "zh-CN")
                log("STATUS: \(st.title)")
                do {
                    let result = try await AppleTranslateService.shared.translate(text, to: "zh-CN")
                    log("RESULT: \(result.text)")
                } catch {
                    log("TRANSLATE ERROR: \(error.localizedDescription)")
                }
                handle?.closeFile()
                NSApp.terminate(nil)
            }
            return
        }

        // 命令行自检：AirLingo --ax-check [日志路径] [--prompt]
        if CommandLine.arguments.contains("--ax-check") {
            let logPath = "/tmp/airlingo-ax.log"
            FileManager.default.createFile(atPath: logPath, contents: nil)
            let handle = FileHandle(forWritingAtPath: logPath)
            func log(_ line: String) {
                handle?.write((line + "\n").data(using: .utf8)!)
                NSLog("AirLingo ax-check: %@", line)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                log("TRUSTED: \(AXIsProcessTrusted())")
                log("BUNDLE: \(Bundle.main.bundlePath)")
                log("BUNDLE_ID: \(Bundle.main.bundleIdentifier ?? "nil")")
                log("EXEC: \(Bundle.main.executablePath ?? "nil")")
                log("PID: \(ProcessInfo.processInfo.processIdentifier)")
                if CommandLine.arguments.contains("--prompt") {
                    AccessibilityService.requestTrust()
                    log("PROMPTED: true")
                }
                handle?.closeFile()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NSApp.terminate(nil)
                }
            }
            return
        }

        // 没授权时直接把主界面摆出来，权限卡片上有重置/重授权入口。
        if !ConfigStore.shared.config.onboardingCompleted || !AccessibilityService.isTrusted {
            let firstRun = !ConfigStore.shared.config.onboardingCompleted
            ConfigStore.shared.config.onboardingCompleted = true
            DashboardWindowController.shared.show()
            if firstRun {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    AccessibilityService.requestTrust()
                }
            }
        }
    }

    // MARK: - 启动状态诊断

    /// 授权变更后重新拉起自己，让系统按新权限重新初始化进程。
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private static let statusPath = "/tmp/airlingo-status.txt"
    private static let fingerprintKey = "ax.signingFingerprint"
    private static let screenFingerprintKey = "screen.signingFingerprint"

    /// 重新签名后，系统里可能留着绑定旧签名的记录：开关是开的，但实际不授权。
    /// 启动时如果没拿到权限、且签名和上次记录的不一样，就主动清掉旧记录并重新申请。
    private func healAccessibilityRecord() {
        guard !AccessibilityService.isTrusted else {
            UserDefaults.standard.set(AccessibilityService.signingRequirement, forKey: Self.fingerprintKey)
            return
        }
        let current = AccessibilityService.signingRequirement
        guard UserDefaults.standard.string(forKey: Self.fingerprintKey) != current else { return }

        AccessibilityService.resetAuthorization()
        UserDefaults.standard.set(current, forKey: Self.fingerprintKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AccessibilityService.requestTrust()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AccessibilityService.openSettings()
        }
    }

    /// 屏幕录制同理：重新签名后旧记录会失效（开关开着但不生效），清掉再重新申请。
    private func healScreenRecord() {
        let granted = MainActor.assumeIsolated { OCRService.shared.hasScreenPermission }
        let current = AccessibilityService.signingRequirement
        if granted {
            UserDefaults.standard.set(current, forKey: Self.screenFingerprintKey)
            return
        }
        guard UserDefaults.standard.string(forKey: Self.screenFingerprintKey) != current else { return }

        AccessibilityService.resetTCC("ScreenCapture")
        UserDefaults.standard.set(current, forKey: Self.screenFingerprintKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            MainActor.assumeIsolated { OCRService.shared.requestScreenPermission() }
        }
    }

    private func writeBootStatus() {
        Self.dumpStatus(note: "launch")
        // 探针是异步的，稍后再写一次，把真实抓屏能力记录下来
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            Self.dumpStatus(note: "probe")
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            if AXIsProcessTrusted() != Self.lastTrusted {
                Self.dumpStatus(note: "changed")
            }
        }
    }

    private nonisolated(unsafe) static var lastTrusted = AXIsProcessTrusted()

    private static func dumpStatus(note: String) {
        let trusted = AXIsProcessTrusted()
        let screenEffective = MainActor.assumeIsolated { OCRService.shared.hasScreenPermission }
        lastTrusted = trusted
        if trusted {
            UserDefaults.standard.set(AccessibilityService.signingRequirement, forKey: fingerprintKey)
        }
        let text = """
        note=\(note)
        time=\(Date())
        trusted=\(trusted)
        screen_preflight=\(CGPreflightScreenCaptureAccess())
        screen_effective=\(screenEffective)
        bundle=\(Bundle.main.bundlePath)
        bundle_id=\(Bundle.main.bundleIdentifier ?? "nil")
        pid=\(ProcessInfo.processInfo.processIdentifier)
        args=\(CommandLine.arguments.dropFirst().joined(separator: " "))
        """
        try? text.write(toFile: statusPath, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func snapshotWindow(_ window: NSWindow, to path: String) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    private static func renderSnapshot(to path: String, height: CGFloat = 700) {
        let view = DashboardView()
            .environmentObject(ConfigStore.shared)
            .frame(width: 1020, height: height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1020, height: height)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            NSLog("AirLingo: 快照 rep 失败")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        NSLog("AirLingo: 快照已写入 \(path)")
    }

    @MainActor
    private static func renderPopupSnapshot(to path: String, long: Bool) {
        let model = PopupModel()
        model.engineName = "Google（免费）"
        model.detected = "zh-CN"
        model.targetName = "English"
        if long {
            model.source = String(repeating: "保存策略的时候占用了内存，这个是部门策略的关系，需要确认影响范围。", count: 6)
            model.output = String(repeating: "When saving the policy it occupies memory; this is a department policy matter and the impact scope needs to be confirmed. ", count: 8)
        } else {
            model.source = "保存策略的时候 占了 这个是部门策略的关系应该"
            model.output = "When saving the policy, it takes up memory — this should be a matter of department policy."
        }

        let view = PopupView(model: model, onClose: {}, onReplace: { _ in })
            .environmentObject(ConfigStore.shared)
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        let size = NSSize(width: max(PopupLayout.minWindowWidth, ceil(fit.width)),
                          height: max(PopupLayout.minWindowHeight, ceil(fit.height)))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("POPUP_SIZE \(Int(size.width))x\(Int(size.height)) -> \(path)")
    }

    @MainActor
    private static func renderTranslateSnapshot(to path: String) {
        let view = ZStack {
            Theme.bg
            TranslatePane(
                source: "保存策略的时候占用了内存，这个是部门策略的关系，需要确认影响范围。改完之后记得回归一下划词和截图两套流程。",
                output: "When saving the policy, memory usage spikes. This is related to the department policy, so the scope of impact needs to be confirmed. After the change, remember to regression-test both the selection and screenshot flows.",
                detected: "zh-CN",
                target: "en",
                engineID: "google"
            )
            .environmentObject(ConfigStore.shared)
        }
        .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: ceil(fit.width), height: ceil(fit.height)))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("TRANSLATE_SNAPSHOT \(Int(hosting.bounds.width))x\(Int(hosting.bounds.height)) -> \(path)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { DashboardWindowController.shared.show() }
        return true
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        Group {
            Button("主动翻译…") {
                TranslateWindowController.shared.show()
            }

            Divider()

            Button("划词翻译  \(HotkeyCenter.describe(store.config.shortcuts.translate))") {
                AppController.shared.translateSelection()
            }
            Button("静默替换  \(HotkeyCenter.describe(store.config.shortcuts.silent))") {
                AppController.shared.silentTranslate()
            }
            Button("截图翻译  \(HotkeyCenter.describe(store.config.shortcuts.ocr))") {
                AppController.shared.ocrTranslate()
            }
            Button("对比翻译  \(HotkeyCenter.describe(store.config.shortcuts.compare))") {
                AppController.shared.compareSelection()
            }

            Divider()

            if !HistoryStore.shared.items.isEmpty {
                Menu("最近翻译") {
                    ForEach(HistoryStore.shared.items.prefix(6)) { item in
                        Button(Self.preview(item)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.target, forType: .string)
                        }
                    }
                    Divider()
                    Button("清空历史") { HistoryStore.shared.clear() }
                }

                Divider()
            }

            Button("打开 AirLingo…") {
                DashboardWindowController.shared.show()
            }

            Divider()

            Button("退出 AirLingo") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private static func preview(_ item: HistoryItem) -> String {
        let source = item.source.replacingOccurrences(of: "\n", with: " ")
        let trimmed = source.count > 22 ? String(source.prefix(22)) + "…" : source
        return trimmed
    }
}

// MARK: - 控制台窗口

final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = DashboardView()
                .environmentObject(ConfigStore.shared)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "AirLingo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1020, height: 700))
            window.minSize = NSSize(width: 940, height: 640)
            window.center()
            window.backgroundColor = NSColor(Theme.bg)
            window.appearance = NSAppearance(named: .darkAqua)
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
