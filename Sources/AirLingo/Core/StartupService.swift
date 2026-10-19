import Foundation
import ServiceManagement

/// 开机自启：交给系统登录项管理（macOS 13+ SMAppService）。
enum StartupService {
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已在登录时自动启动"
        case .requiresApproval: return "等待你在「系统设置 › 通用 › 登录项」里允许"
        case .notRegistered: return "未开启"
        case .notFound: return isSupported ? "未开启" : "未开启（需要应用放在「应用程序」文件夹）"
        @unknown default: return "状态未知"
        }
    }

    /// 返回 nil 表示成功，否则是可读的失败原因。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isSupported else {
            return "把 AirLingo 放到「应用程序」文件夹后才能设置开机启动"
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
