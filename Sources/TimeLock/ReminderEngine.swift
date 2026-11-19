import AppKit
import Foundation

/// 提醒引擎：状态机 idle → running → resting → (可选 system lock) → running …
final class ReminderEngine: NSObject {
    enum Phase {
        case idle      // 未启动
        case running   // 倒计时中
        case resting   // 强制锁屏覆盖层显示中
        case paused    // 系统休眠/锁定，自动暂停
    }

    private(set) var phase: Phase = .idle
    private(set) var completedCycles = 0

    /// 状态变化通知（UI 刷新）。
    var onStatusChange: (() -> Void)?

    private let overlay = OverlayController()
    private var intervalTimer: Timer?
    private var nextReminderDate: Date?
    private var intervalSeconds = 0
    /// 真锁屏触发后的确认看门狗：6 秒内 session 未失活则视为锁屏未生效，自愈重排。
    private var lockWatchdogTimer: Timer?
    private var lockPermissionNotified = false

    var statusText: String {
        switch phase {
        case .idle:
            return "点击「启动提醒」开始计时"
        case .running:
            guard let next = nextReminderDate else { return "运行中" }
            let seconds = max(0, Int(ceil(next.timeIntervalSinceNow)))
            return "下次锁屏 \(Self.format(seconds))"
        case .resting:
            return "强制锁屏中 · \(overlay.remainingSeconds)s 后结束"
        case .paused:
            return "系统休眠或锁定中，唤醒后自动恢复"
        }
    }

    var progress: Double {
        switch phase {
        case .running:
            guard let next = nextReminderDate, intervalSeconds > 0 else { return 0 }
            let remaining = max(0, next.timeIntervalSinceNow)
            return min(1, max(0, 1 - remaining / Double(intervalSeconds)))
        case .resting:
            return 1
        default:
            return 0
        }
    }

    // MARK: - 对外控制

    func start() {
        guard phase == .idle || phase == .paused else { return }
        phase = .running
        scheduleNextReminder()
    }

    func stop() {
        phase = .idle
        intervalTimer?.invalidate()
        intervalTimer = nil
        nextReminderDate = nil
        lockWatchdogTimer?.invalidate()
        lockWatchdogTimer = nil
        overlay.close(notifyCompletion: false)
        onStatusChange?()
    }

    /// 「立即锁屏」：运行中则立刻进入锁屏阶段；否则以预览模式显示覆盖层。
    func lockNow() {
        if phase == .running {
            beginRest()
        } else {
            let s = SettingsStore.shared.current
            overlay.show(word: s.reminderWord, duration: s.lockSeconds,
                         autoLockOnFinish: s.autoLockAfterBreak) { requested in
                guard requested else { return }
                switch SystemLock.lockScreen() {
                case .realLockTriggered:
                    break // 预览场景：真锁屏生效与否由系统事件驱动，无需看门狗
                case .displaySleepOnly(let reason), .failed(let reason):
                    UserNotifier.post(title: "TimeLock 自动锁屏", body: reason)
                }
            }
            onStatusChange?()
        }
    }

    /// 设置变更：运行中按新间隔重排（锁屏覆盖层保持不受影响）。
    func settingsDidChange() {
        guard phase == .running else { return }
        scheduleNextReminder()
    }

    /// 显示器配置变化。
    func screensChanged() {
        overlay.refreshScreens()
    }

    // MARK: - 系统休眠/锁定（AppDelegate 转发）

    func pauseForSystem() {
        guard phase == .running || phase == .resting else { return }
        lockWatchdogTimer?.invalidate()
        lockWatchdogTimer = nil
        overlay.close(notifyCompletion: false)
        intervalTimer?.invalidate()
        intervalTimer = nil
        nextReminderDate = nil
        phase = .paused
        onStatusChange?()
    }

    func resumeAfterSystem() {
        guard phase == .paused else { return }
        phase = .running
        scheduleNextReminder()
        onStatusChange?()
    }

    // MARK: - 内部流转

    private func scheduleNextReminder() {
        guard phase == .running else { return }
        intervalTimer?.invalidate()
        let minutes = SettingsStore.shared.current.intervalMinutes
        intervalSeconds = minutes * 60
        nextReminderDate = Date().addingTimeInterval(TimeInterval(intervalSeconds))

        let timer = Timer(timeInterval: TimeInterval(intervalSeconds), repeats: false) { [weak self] _ in
            self?.beginRest()
        }
        RunLoop.main.add(timer, forMode: .common)
        intervalTimer = timer
        onStatusChange?()
    }

    private func beginRest() {
        intervalTimer?.invalidate()
        intervalTimer = nil
        nextReminderDate = nil
        phase = .resting

        let s = SettingsStore.shared.current
        overlay.show(word: s.reminderWord, duration: s.lockSeconds,
                     autoLockOnFinish: s.autoLockAfterBreak) { [weak self] requested in
            guard let self else { return }
            self.completedCycles += 1
            self.phase = .running
            if requested {
                self.beginSystemLock()
            } else {
                self.scheduleNextReminder()
            }
            self.onStatusChange?()
        }
        onStatusChange?()
    }

    /// 倒计时结束后的自动锁屏流转。
    /// - realLockTriggered：等待 session 失活（pause）→ 解锁后恢复（resume）重排；
    ///   6 秒看门狗兜底，锁屏未生效则提示用户并直接继续下一轮。
    /// - displaySleepOnly / failed：立即继续下一轮，并提示原因与授权方法。
    private func beginSystemLock() {
        let result = SystemLock.lockScreen()
        switch result {
        case .realLockTriggered:
            startLockWatchdog()
        case .displaySleepOnly(let reason):
            notifyLockIssue(
                title: "已熄屏，但未真正锁屏",
                body: reason + "。如需真锁屏：系统设置 › 隐私与安全性 › 辅助功能，添加并勾选 TimeLock。",
                once: true)
            scheduleNextReminder()
        case .failed(let reason):
            notifyLockIssue(title: "自动锁屏失败", body: reason + " 本轮将继续下一轮提醒。")
            scheduleNextReminder()
        }
        onStatusChange?()
    }

    /// 真锁屏看门狗：锁屏生效时 sessionDidResignActive 会把 phase 置为 .paused；
    /// 若 6 秒后仍处于 .running 且未重排计时器，说明系统没有响应，自愈继续循环。
    private func startLockWatchdog() {
        lockWatchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lockWatchdogTimer = nil
            guard self.phase == .running, self.nextReminderDate == nil else { return }
            self.notifyLockIssue(
                title: "系统锁屏未生效",
                body: "已尝试触发锁屏，但系统没有响应（快捷键可能被修改或权限被收回）。"
                    + "请到 系统设置 › 隐私与安全性 › 辅助功能 检查 TimeLock 是否已勾选。本轮继续下一轮提醒。")
            self.scheduleNextReminder()
        }
        RunLoop.main.add(timer, forMode: .common)
        lockWatchdogTimer = timer
    }

    /// 锁屏异常的用户提示（once：每次运行只提示一次，避免轰炸）。
    private func notifyLockIssue(title: String, body: String, once: Bool = false) {
        if once && lockPermissionNotified { return }
        lockPermissionNotified = true
        UserNotifier.post(title: title, body: body)
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
