import AppKit

/// 设置窗口：提醒间隔(分钟) / 锁屏时长(秒) / 提醒词(多行) / 开机自启 / 锁屏后自动熄屏。
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    private let engine: ReminderEngine

    private let intervalField = NSTextField()
    private let intervalStepper = NSStepper()
    private let lockField = NSTextField()
    private let lockStepper = NSStepper()
    private var wordTextView: NSTextView!
    private let autoStartCheck = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)
    private let autoLockCheck = NSButton(checkboxWithTitle: "锁屏完毕后自动熄屏锁定", target: nil, action: nil)
    private let explainLabel = NSTextField(wrappingLabelWithString: "")
    private let lockPermissionLabel = NSTextField(wrappingLabelWithString: "")
    private let testButton = NSButton(title: "测试提醒", target: nil, action: nil)
    private let startStopButton = NSButton(title: "停止提醒", target: nil, action: nil)
    private var isRefreshing = false

    init(engine: ReminderEngine) {
        self.engine = engine
        super.init(window: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TimeLock 设置"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        buildUI()
        refreshFromStore()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "TimeLock 设置")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let intervalLabel = fieldLabel("提醒间隔(分钟)")
        configureNumberField(intervalField, width: 70)
        configureStepper(intervalStepper, min: 1, max: 999,
                         action: #selector(intervalStepperChanged))
        let intervalRow = numberRow(field: intervalField, stepper: intervalStepper)

        let lockLabel = fieldLabel("锁屏时长(秒)")
        configureNumberField(lockField, width: 70)
        configureStepper(lockStepper, min: 5, max: 3600,
                         action: #selector(lockStepperChanged))
        let lockRow = numberRow(field: lockField, stepper: lockStepper)

        let wordLabel = fieldLabel("提醒词（锁屏时显示，支持多行）")

        wordTextView = NSTextView()
        wordTextView.isRichText = false
        wordTextView.font = .systemFont(ofSize: 13)
        wordTextView.isVerticallyResizable = true
        wordTextView.textContainer?.widthTracksTextView = true
        wordTextView.autoresizingMask = [.width]
        wordTextView.delegate = self

        let wordScroll = NSScrollView()
        wordScroll.borderType = .bezelBorder
        wordScroll.hasVerticalScroller = true
        wordScroll.documentView = wordTextView
        wordScroll.translatesAutoresizingMaskIntoConstraints = false

        for check in [autoStartCheck, autoLockCheck] {
            check.target = self
            check.font = .systemFont(ofSize: 13)
        }
        autoStartCheck.action = #selector(autoStartToggled)
        autoLockCheck.action = #selector(autoLockToggled)

        explainLabel.stringValue = "勾选「锁屏完毕后自动熄屏锁定」：锁屏倒计时结束后自动触发系统级锁屏，"
            + "需输入密码解锁后继续提醒循环。不勾选：覆盖层自动消失，回到锁屏前状态并开始下一轮。"
        explainLabel.font = .systemFont(ofSize: 11)
        explainLabel.textColor = .secondaryLabelColor

        lockPermissionLabel.font = .systemFont(ofSize: 11)
        lockPermissionLabel.textColor = .secondaryLabelColor

        let sep = NSBox()
        sep.boxType = .separator

        testButton.bezelStyle = .rounded
        testButton.target = self
        testButton.action = #selector(testClicked)

        startStopButton.bezelStyle = .rounded
        startStopButton.target = self
        startStopButton.action = #selector(startStopToggled)

        let buttonRow = NSStackView(views: [testButton, startStopButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            title, intervalLabel, intervalRow, lockLabel, lockRow,
            wordLabel, wordScroll, autoStartCheck, autoLockCheck,
            explainLabel, lockPermissionLabel, sep, buttonRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: title)
        stack.setCustomSpacing(16, after: intervalRow)
        stack.setCustomSpacing(16, after: lockRow)
        stack.setCustomSpacing(14, after: wordScroll)
        stack.setCustomSpacing(20, after: explainLabel)
        stack.setCustomSpacing(14, after: sep)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            wordScroll.widthAnchor.constraint(equalToConstant: 410),
            wordScroll.heightAnchor.constraint(equalToConstant: 90),
            explainLabel.widthAnchor.constraint(equalToConstant: 410),
            lockPermissionLabel.widthAnchor.constraint(equalToConstant: 410)
        ])
    }

    // MARK: - 数据绑定

    func refreshFromStore() {
        isRefreshing = true
        defer { isRefreshing = false }

        let s = SettingsStore.shared.current
        if intervalField.currentEditor() == nil {
            intervalField.integerValue = s.intervalMinutes
        }
        if lockField.currentEditor() == nil {
            lockField.integerValue = s.lockSeconds
        }
        intervalStepper.integerValue = intervalField.integerValue
        lockStepper.integerValue = lockField.integerValue
        if wordTextView.window?.firstResponder !== wordTextView {
            wordTextView.string = s.reminderWord
        }
        autoStartCheck.state = LaunchAtLogin.isEnabled ? .on : .off
        autoLockCheck.state = s.autoLockAfterBreak ? .on : .off

        let axGranted = SystemLock.accessibilityGranted
        if s.autoLockAfterBreak {
            lockPermissionLabel.stringValue = axGranted
                ? "✅ 真锁屏已就绪：倒计时结束将直接进入系统锁屏，输入密码解锁后继续循环。"
                : "⚠️ 未授予辅助功能权限：倒计时结束将仅熄屏（唤醒后无需密码）。请到 系统设置 › 隐私与安全性 › 辅助功能，添加并勾选 TimeLock。"
            lockPermissionLabel.textColor = axGranted ? .systemGreen : .systemOrange
        } else {
            lockPermissionLabel.stringValue = "未勾选自动锁屏。"
            lockPermissionLabel.textColor = .secondaryLabelColor
        }

        startStopButton.title = (engine.phase == .idle) ? "启动提醒" : "停止提醒"
    }

    private func applyFromFields() {
        guard !isRefreshing else { return }
        var s = SettingsStore.shared.current
        s.intervalMinutes = intervalField.integerValue
        s.lockSeconds = lockField.integerValue
        s.reminderWord = wordTextView.string
        s.autoLockAfterBreak = autoLockCheck.state == .on
        SettingsStore.shared.update(s)
        intervalStepper.integerValue = intervalField.integerValue
        lockStepper.integerValue = lockField.integerValue
    }

    // MARK: - Actions

    @objc private func intervalStepperChanged() {
        intervalField.integerValue = intervalStepper.integerValue
        applyFromFields()
    }

    @objc private func lockStepperChanged() {
        lockField.integerValue = lockStepper.integerValue
        applyFromFields()
    }

    @objc private func autoLockToggled() {
        applyFromFields()
    }

    @objc private func autoStartToggled() {
        let wantsEnabled = autoStartCheck.state == .on
        if let error = LaunchAtLogin.setEnabled(wantsEnabled) {
            autoStartCheck.state = wantsEnabled ? .off : .on
            let alert = NSAlert()
            alert.messageText = "开机自启设置失败"
            alert.informativeText = error
            alert.runModal()
        }
        var s = SettingsStore.shared.current
        s.autoStartAtLogin = LaunchAtLogin.isEnabled
        SettingsStore.shared.update(s)
    }

    @objc private func testClicked() {
        engine.lockNow()
    }

    @objc private func startStopToggled() {
        if engine.phase == .idle || engine.phase == .paused {
            engine.start()
        } else {
            engine.stop()
        }
        refreshFromStore()
    }

    // MARK: - Delegate

    func controlTextDidChange(_ obj: Notification) {
        applyFromFields()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        refreshFromStore()
    }

    func textDidChange(_ notification: Notification) {
        applyFromFields()
    }

    // MARK: - Builders

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configureNumberField(_ field: NSTextField, width: CGFloat) {
        field.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        field.alignment = .right
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func configureStepper(_ stepper: NSStepper, min: Double, max: Double, action: Selector) {
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    private func numberRow(field: NSTextField, stepper: NSStepper) -> NSStackView {
        let row = NSStackView(views: [field, stepper])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }
}
