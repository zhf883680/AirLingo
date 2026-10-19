import AppKit
import Combine

@MainActor
final class AppController {
    static let shared = AppController()

    private var cancellables: Set<AnyCancellable> = []
    private var bootstrapped = false

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        NSApp.setActivationPolicy(.accessory)
        registerHotkeys()

        ConfigStore.shared.$config
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.registerHotkeys() }
            .store(in: &cancellables)
    }

    func registerHotkeys() {
        let shortcuts = ConfigStore.shared.config.shortcuts
        HotkeyCenter.shared.configure(shortcuts: [
            (shortcuts.translate, { [weak self] in Task { @MainActor in self?.translateSelection() } }),
            (shortcuts.silent, { [weak self] in Task { @MainActor in self?.silentTranslate() } }),
            (shortcuts.ocr, { [weak self] in Task { @MainActor in self?.ocrTranslate() } }),
            (shortcuts.compare, { [weak self] in Task { @MainActor in self?.compareSelection() } })
        ])
    }

    // MARK: - 划词翻译

    func translateSelection() {
        guard ensureAccessibility() else { return }
        Task {
            guard let text = await readSelectionOrWarn() else { return }
            let engineID = ConfigStore.shared.config.translateEngineID
            PopupController.shared.show(source: text,
                                        engineID: engineID,
                                        mode: .translate,
                                        anchor: NSEvent.mouseLocation)
        }
    }

    func compareSelection() {
        guard ensureAccessibility() else { return }
        Task {
            guard let text = await readSelectionOrWarn() else { return }
            PopupController.shared.show(source: text,
                                        engineID: ConfigStore.shared.config.translateEngineID,
                                        mode: .compare,
                                        anchor: NSEvent.mouseLocation)
        }
    }

    // MARK: - 静默替换

    func silentTranslate() {
        guard ensureAccessibility() else { return }
        Task {
            guard let text = await readSelectionOrWarn() else { return }
            guard let profile = ConfigStore.shared.engine(for: .silent) else {
                HUD.shared.toast("没有可用的翻译引擎，先去设置里启用一个")
                return
            }
            let target = ConfigStore.shared.targetLanguage(for: text)
            do {
                let result = try await Translator.translate(text, to: target, profile: profile)
                HistoryStore.shared.add(source: text,
                                        target: result.text,
                                        engine: result.engineName,
                                        from: result.detectedSource ?? "auto",
                                        to: target)
                if !AccessibilityService.replaceSelection(with: result.text) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    HUD.shared.toast("这个输入框不允许写入，译文已复制到剪贴板")
                }
            } catch {
                NSSound.beep()
                HUD.shared.toast("静默替换没成功，已改用浮窗显示")
                PopupController.shared.show(source: text,
                                            engineID: profile.id,
                                            mode: .translate,
                                            anchor: NSEvent.mouseLocation)
                NSLog("AirLingo: 静默翻译失败 \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 截图翻译

    func ocrTranslate() {
        OCRService.shared.captureRegion { result in
            switch result {
            case .text(let text):
                guard !text.isEmpty else { return }
                Task { @MainActor in
                    PopupController.shared.show(source: text,
                                                engineID: ConfigStore.shared.config.ocrEngineID,
                                                mode: .ocr,
                                                anchor: NSEvent.mouseLocation)
                }
            case .cancelled:
                break
            case .denied:
                HUD.shared.toast("截图翻译需要屏幕录制权限，去「系统设置 › 隐私与安全性 › 屏幕录制」打开后重启应用")
            case .empty:
                HUD.shared.toast("没识别到文字，换个范围再框一次")
            case .failed(let message):
                HUD.shared.toast("截图失败：\(message)")
            }
        }
    }

    // MARK: - 权限

    @discardableResult
    private func ensureAccessibility() -> Bool {
        if AccessibilityService.isTrusted { return true }
        AccessibilityService.requestTrust()
        HUD.shared.toast("划词需要辅助功能权限，去「隐私与安全性 › 辅助功能」打开后重启应用")
        return false
    }

    /// 读不到选中文字时给出具体原因，不再只响一声。
    private func readSelectionOrWarn() async -> String? {
        let text = await AccessibilityService.readSelection()
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            HUD.shared.toast("没读到选中的文字：先用鼠标选中一段文字再按快捷键")
            return nil
        }
        return text
    }
}
