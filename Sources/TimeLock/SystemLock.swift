import Foundation

/// 系统级锁屏 / 熄屏（用于「锁屏完毕后自动熄屏锁定」勾选项）。
///
/// 候选链（按优先级依次尝试，任一成功即返回）：
/// 1. CGSession -suspend        —— 旧版 macOS 的真锁屏私有工具（macOS 26 已移除）
/// 2. pmset displaysleepnow     —— 立即熄灭显示器；若系统设置了「退出睡眠后要求密码」即等效锁屏
/// 3. osascript Ctrl+Cmd+Q      —— 通过 AppleScript 模拟锁屏快捷键（需辅助功能权限）
enum SystemLock {
    static func lockScreen() -> Bool {
        let cgSessionPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if runCommand(at: cgSessionPath, arguments: ["-suspend"]) { return true }
        if runCommand(at: "/usr/bin/pmset", arguments: ["displaysleepnow"]) { return true }
        return lockScreenViaAppleScript()
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

    /// 模拟系统快捷键 Control+Command+Q 触发锁屏。
    /// 需要在 系统设置 › 隐私与安全性 › 辅助功能 中授权运行环境。
    private static func lockScreenViaAppleScript() -> Bool {
        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = [
            "-e",
            "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        ]
        return runProcess(osascript)
    }

    private static func runProcess(_ process: Process) -> Bool {
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
