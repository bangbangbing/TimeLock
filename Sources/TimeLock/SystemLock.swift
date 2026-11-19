import AppKit
import ApplicationServices
import Foundation

/// 锁屏触发结果。
enum LockResult: CustomStringConvertible {
    /// 已触发系统级真锁屏（等待 sessionDidResignActive 确认）。
    case realLockTriggered
    /// 仅熄灭显示器，未真正锁屏（附带原因说明）。
    case displaySleepOnly(String)
    /// 全部候选方式均失败。
    case failed(String)

    var description: String {
        switch self {
        case .realLockTriggered:
            return "realLockTriggered"
        case .displaySleepOnly(let reason):
            return "displaySleepOnly(\(reason))"
        case .failed(let reason):
            return "failed(\(reason))"
        }
    }
}

/// 系统级锁屏（用于「锁屏完毕后自动熄屏锁定」勾选项）。
///
/// 候选链（按优先级依次尝试）：
/// 1. CGSession -suspend —— 旧版 macOS 的真锁屏工具（macOS 26 已移除，存在即优先使用，无需授权）
/// 2. CGEvent 模拟 Control+Command+Q —— 现代 macOS 真锁屏，需辅助功能权限（无子进程、无挂起风险）
/// 3. 兜底：弹出授权引导对话框 + pmset displaysleepnow 仅熄屏（未真正锁屏）
///
/// 注意：pmset displaysleepnow 只是熄屏。若系统未开启「退出睡眠后要求密码」，
/// 唤醒后直接回到桌面，等效于没有锁屏。因此熄屏只是兜底，真锁屏依赖前两种方式。
enum SystemLock {

    /// 当前运行环境是否已获辅助功能授权（真锁屏的前提）。
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统锁屏，返回结果供引擎决定后续流转。
    static func lockScreen() -> LockResult {
        // 1) 旧版 macOS：CGSession -suspend（存在即可用，真锁屏）
        if runCommand(at: cgSessionPath, arguments: ["-suspend"]) {
            return .realLockTriggered
        }

        // 2) 已授权辅助功能：直接投递 Control+Command+Q 键盘事件（真锁屏）
        if accessibilityGranted, postLockShortcut() {
            return .realLockTriggered
        }

        // 3) 兜底：弹出系统授权引导（首次会指向 系统设置 › 隐私与安全性 › 辅助功能），熄屏保底
        promptForAccessibilityIfNeeded()
        if runCommand(at: "/usr/bin/pmset", arguments: ["displaysleepnow"]) {
            return .displaySleepOnly("未授予辅助功能权限，只能熄屏、无法真正锁屏")
        }
        return .failed("所有锁屏方式均不可用（CGSession 缺失、无辅助功能权限、pmset 失败）")
    }

    /// 诊断信息（无副作用，不弹对话框、不触发任何锁屏动作）。
    static func diagnosticDescription() -> String {
        [
            "AXIsProcessTrusted=\(AXIsProcessTrusted())",
            "CGSession存在=\(FileManager.default.isExecutableFile(atPath: cgSessionPath))",
            "pmset可用=\(FileManager.default.isExecutableFile(atPath: "/usr/bin/pmset"))"
        ].joined(separator: " ")
    }

    // MARK: - 私有实现

    private static let cgSessionPath =
        "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

    /// 模拟 Control+Command+Q（kVK_ANSI_Q = 12）触发系统「锁定屏幕」快捷键。
    /// 需要辅助功能权限；事件经 HID 事件 tap 投递，由系统全局快捷键接管。
    private static func postLockShortcut() -> Bool {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)
        else { return false }
        keyDown.flags = [.maskControl, .maskCommand]
        keyUp.flags = [.maskControl, .maskCommand]
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// 未授权时弹一次系统引导对话框（指向 系统设置 › 隐私与安全性 › 辅助功能）。
    private static func promptForAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func runCommand(at path: String, arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
