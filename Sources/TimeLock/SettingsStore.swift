import Foundation

struct AppSettings {
    var intervalMinutes: Int
    var lockSeconds: Int
    var reminderWord: String
    var autoStartAtLogin: Bool
    var autoLockAfterBreak: Bool
}

/// 设置存储：UserDefaults 持久化，onChange 通知 UI 与引擎。
final class SettingsStore {
    static let shared = SettingsStore()

    /// 任何设置变更后触发（主线程调用）。
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    private enum Key {
        static let intervalMinutes = "intervalMinutes"
        static let lockSeconds = "lockSeconds"
        static let reminderWord = "reminderWord"
        static let autoStartAtLogin = "autoStartAtLogin"
        static let autoLockAfterBreak = "autoLockAfterBreak"
    }

    static let defaultSettings = AppSettings(
        intervalMinutes: 25,
        lockSeconds: 10,
        reminderWord: "站起来喝水",
        autoStartAtLogin: false,
        autoLockAfterBreak: false
    )

    private init() {
        defaults.register(defaults: [
            Key.intervalMinutes: Self.defaultSettings.intervalMinutes,
            Key.lockSeconds: Self.defaultSettings.lockSeconds,
            Key.reminderWord: Self.defaultSettings.reminderWord,
            Key.autoStartAtLogin: Self.defaultSettings.autoStartAtLogin,
            Key.autoLockAfterBreak: Self.defaultSettings.autoLockAfterBreak
        ])
    }

    var current: AppSettings {
        AppSettings(
            intervalMinutes: Self.clamp(defaults.integer(forKey: Key.intervalMinutes), 1, 999),
            lockSeconds: Self.clamp(defaults.integer(forKey: Key.lockSeconds), 5, 3600),
            reminderWord: Self.normalizedWord(defaults.string(forKey: Key.reminderWord)),
            autoStartAtLogin: defaults.bool(forKey: Key.autoStartAtLogin),
            autoLockAfterBreak: defaults.bool(forKey: Key.autoLockAfterBreak)
        )
    }

    func update(_ newSettings: AppSettings) {
        defaults.set(Self.clamp(newSettings.intervalMinutes, 1, 999), forKey: Key.intervalMinutes)
        defaults.set(Self.clamp(newSettings.lockSeconds, 5, 3600), forKey: Key.lockSeconds)
        defaults.set(Self.normalizedWord(newSettings.reminderWord), forKey: Key.reminderWord)
        defaults.set(newSettings.autoStartAtLogin, forKey: Key.autoStartAtLogin)
        defaults.set(newSettings.autoLockAfterBreak, forKey: Key.autoLockAfterBreak)
        onChange?()
    }

    static func clamp(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
        return max(minValue, min(maxValue, value))
    }

    /// 仅去除首尾空白；保留内部换行（提醒词支持多行）。
    private static func normalizedWord(_ word: String?) -> String {
        let trimmed = (word ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSettings.reminderWord : String(trimmed.prefix(500))
    }
}
