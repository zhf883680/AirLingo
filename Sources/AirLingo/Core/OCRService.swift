import AppKit
import ScreenCaptureKit
import Vision

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// 框选取字的结果，区分「用户取消」和「识别失败」，上层才能给出对的提示。
enum OCRResult {
    case text(String)
    case cancelled
    case denied
    case empty
    case failed(String)
}

struct OCRError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 框选屏幕区域 → Vision 取字。
@MainActor
final class OCRService {
    static let shared = OCRService()

    private var overlay: NSWindow?
    private var completion: ((OCRResult) -> Void)?
    /// CGPreflightScreenCaptureAccess 在授权后可能仍返回 false（进程内缓存），
    /// 所以再实际试一次抓取能力作为兜底判断。
    private var captureProbePassed = false

    var hasScreenPermission: Bool {
        CGPreflightScreenCaptureAccess() || captureProbePassed
    }

    func requestScreenPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// 用真正的抓取请求探测权限是否已生效（不依赖缓存的那个布尔值）。
    func probeCaptureCapability() {
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                captureProbePassed = true
            } catch {
                captureProbePassed = false
            }
        }
    }

    func captureRegion(completion: @escaping (OCRResult) -> Void) {
        guard hasScreenPermission else {
            _ = CGRequestScreenCaptureAccess()
            completion(.denied)
            return
        }
        self.completion = completion

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let screen else {
            completion(.failed("找不到可用的显示器"))
            return
        }

        let window = NSWindow(contentRect: screen.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onCancel = { [weak self] in self?.finish(.cancelled) }
        view.onSelect = { [weak self] rect in
            guard let self else { return }
            self.finishWithCapture(rect: rect, screen: screen)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        overlay = window
    }

    private func finish(_ result: OCRResult) {
        overlay?.orderOut(nil)
        overlay = nil
        completion?(result)
        completion = nil
    }

    /// 选区结束：先撤掉遮罩，等合成器把这一帧刷掉再抓屏；空结果再补一次。
    private func finishWithCapture(rect: NSRect, screen: NSScreen) {
        overlay?.orderOut(nil)
        overlay = nil
        let done = completion
        completion = nil

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            var lastError: Error?
            for attempt in 0..<2 {
                do {
                    let text = try await self.captureAndRecognize(rect: rect, screen: screen)
                    if let text, !text.isEmpty {
                        done?(.text(text))
                        return
                    }
                } catch {
                    lastError = error
                    NSLog("AirLingo: 截图取字失败(第 \(attempt + 1) 次) \(error.localizedDescription)")
                }
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 260_000_000)
                }
            }
            if let lastError {
                done?(.failed(lastError.localizedDescription))
            } else {
                done?(.empty)
            }
        }
    }

    /// `rect` 是屏幕坐标（y 向上）。
    private func captureAndRecognize(rect: NSRect, screen: NSScreen) async throws -> String? {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw OCRError(message: "拿不到屏幕画面，去「隐私与安全性 › 屏幕录制」确认 AirLingo 已打开后重启应用")
        }
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID })
                ?? content.displays.first else {
            throw OCRError(message: "找不到这块显示器")
        }

        // 屏幕坐标（左下origin、y 向上）→ 显示器坐标（左上origin、y 向下，单位 pt）
        var local = NSRect(x: rect.minX - screen.frame.minX,
                           y: screen.frame.maxY - rect.maxY,
                           width: max(1, rect.width),
                           height: max(1, rect.height))
        let bounds = NSRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        local = local.intersection(bounds)
        guard local.width >= 1, local.height >= 1 else {
            throw OCRError(message: "框选区域超出屏幕范围")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        let scale = max(1, screen.backingScaleFactor)
        configuration.width = Int(local.width * scale)
        configuration.height = Int(local.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.scalesToFit = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return await recognize(image)
    }

    private func recognize(_ image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
                if let supported = try? request.supportedRecognitionLanguages() {
                    let usable = preferred.filter { supported.contains($0) }
                    if !usable.isEmpty { request.recognitionLanguages = usable }
                }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let observations = (request.results ?? []).sorted { lhs, rhs in
                        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                            return lhs.boundingBox.midY > rhs.boundingBox.midY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    let lines = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text.isEmpty ? nil : text)
                } catch {
                    NSLog("AirLingo: Vision 识别失败 \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - 开发期自检

    /// 直接对屏幕上一块区域取字（跳过框选 UI），用来验证坐标映射。
    func debugRecognize(_ screenRect: NSRect) async throws -> String? {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) }) ?? NSScreen.main
        guard let screen else { return nil }
        return try await captureAndRecognize(rect: screenRect, screen: screen)
    }

    /// 把显示器坐标反算回屏幕坐标，自检里用来打印映射结果。
    nonisolated static func displayRect(for screenRect: NSRect, screen: NSScreen) -> NSRect {
        NSRect(x: screenRect.minX - screen.frame.minX,
               y: screen.frame.maxY - screenRect.maxY,
               width: screenRect.width,
               height: screenRect.height)
    }
}

// MARK: - 框选视图

final class SelectionView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        context.fill(bounds)

        if let rect = selectionRect {
            context.setBlendMode(.clear)
            context.fill(rect)
            context.setBlendMode(.normal)

            context.setStrokeColor(NSColor(red: 0.65, green: 0.5, blue: 1, alpha: 1).cgColor)
            context.setLineWidth(1.5)
            context.stroke(rect)

            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attributes)
            let origin = NSPoint(x: rect.minX + 6, y: rect.minY + 6)
            let background = NSRect(x: origin.x - 4, y: origin.y - 2, width: size.width + 8, height: size.height + 4)
            context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            context.fill(background)
            label.draw(at: origin, withAttributes: attributes)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(x: min(startPoint.x, currentPoint.x),
                      y: min(startPoint.y, currentPoint.y),
                      width: abs(startPoint.x - currentPoint.x),
                      height: abs(startPoint.y - currentPoint.y))
    }

    /// 视图坐标（isFlipped，y 从顶往下）→ 屏幕坐标（y 向上）。
    /// 关键点：`convert(_:to: nil)` 会先把翻转坐标换成窗口基准坐标，
    /// 直接用 `window.convertToScreen` 会把上下镜像，导致抓到的是另一块屏幕。
    func screenRect(forViewRect rect: NSRect) -> NSRect? {
        guard let window else { return nil }
        let inWindow = convert(rect, to: nil)
        return window.convertToScreen(inWindow)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }
        guard let rect = selectionRect, rect.width > 4, rect.height > 4 else {
            onCancel?()
            return
        }
        guard let screenRect = screenRect(forViewRect: rect) else {
            onCancel?()
            return
        }
        onSelect?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
