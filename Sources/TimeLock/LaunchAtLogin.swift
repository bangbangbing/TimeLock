import Foundation
import ServiceManagement

/// 开机自启：
/// - macOS 13+ 使用 SMAppService（需 .app 位于 /Applications 效果最佳）
/// - 旧版回退 ~/Library/LaunchAgents plist
enum LaunchAtLogin {
    private static let launchAgentLabel = "com.zhougj.timelock"

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// 返回 nil 表示成功；否则返回错误描述用于 UI 展示。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    switch service.status {
                    case .enabled:
                        break
                    case .requiresApproval:
                        return "macOS 正在等待授权：请到 系统设置 › 通用 › 登录项与扩展 中允许 TimeLock"
                    default:
                        try service.register()
                        if service.status == .requiresApproval {
                            return "macOS 正在等待授权：请到 系统设置 › 通用 › 登录项与扩展 中允许 TimeLock"
                        }
                        if service.status != .enabled {
                            return "系统未能启用登录项（状态码：\(service.status.rawValue)）"
                        }
                    }
                } else if service.status != .notRegistered {
                    try service.unregister()
                }
            } catch {
                return error.localizedDescription
            }
            return nil
        } else {
            return setLegacyLaunchAgent(enabled)
        }
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

    private static func setLegacyLaunchAgent(_ enabled: Bool) -> String? {
        do {
            if enabled {
                let executable = Bundle.main.executableURL?.path
                    ?? "\(Bundle.main.bundlePath)/Contents/MacOS/TimeLock"
                let plist: [String: Any] = [
                    "Label": launchAgentLabel,
                    "ProgramArguments": [executable],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive",
                    "LimitLoadToSessionType": "Aqua"
                ]
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist, format: .xml, options: 0
                )
                try FileManager.default.createDirectory(
                    at: launchAgentURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: launchAgentURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }
}
