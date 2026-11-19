import AppKit

/// 菜单栏弹出面板：状态 / 进度 / 启动停止 / 立即锁屏 / 提醒词多行快速编辑。
final class PopoverPanelController: NSViewController {
    private let engine: ReminderEngine
    private let onOpenSettings: () -> Void

    private let statusDot = NSView()
    private let phaseLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let startStopButton = NSButton(title: "启动提醒", target: nil, action: nil)
    private let settingsButton = NSButton(title: "设置…", target: nil, action: nil)
    private let previewButton = NSButton(title: "立即锁屏（预览）", target: nil, action: nil)
    private var wordTextView: NSTextView!
    private let saveWordButton = NSButton(title: "保存提醒词", target: nil, action: nil)
    private let footerLabel = NSTextField(wrappingLabelWithString: "")

    init(engine: ReminderEngine, onOpenSettings: @escaping () -> Void) {
        self.engine = engine
        self.onOpenSettings = onOpenSettings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view = content

        // 顶部：标题 + 状态点 + 状态名
        let title = NSTextField(labelWithString: "TimeLock")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10)
        ])

        phaseLabel.font = .systemFont(ofSize: 12, weight: .medium)
        phaseLabel.textColor = .secondaryLabelColor

        let headerRow = NSStackView(views: [title, makeSpacer(), statusDot, phaseLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.controlSize = .small

        startStopButton.bezelStyle = .rounded
        startStopButton.target = self
        startStopButton.action = #selector(startStopToggled)

        settingsButton.bezelStyle = .rounded
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)

        let buttonRow = NSStackView(views: [startStopButton, settingsButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        previewButton.bezelStyle = .rounded
        previewButton.controlSize = .small
        previewButton.target = self
        previewButton.action = #selector(previewClicked)

        let sep = NSBox()
        sep.boxType = .separator

        let wordCaption = NSTextField(labelWithString: "提醒词快速编辑（支持多行）")
        wordCaption.font = .systemFont(ofSize: 11)
        wordCaption.textColor = .secondaryLabelColor

        wordTextView = NSTextView()
        wordTextView.isRichText = false
        wordTextView.font = .systemFont(ofSize: 13)
        wordTextView.isVerticallyResizable = true
        wordTextView.textContainer?.widthTracksTextView = true
        wordTextView.autoresizingMask = [.width]
        wordTextView.string = SettingsStore.shared.current.reminderWord

        let wordScroll = NSScrollView()
        wordScroll.borderType = .bezelBorder
        wordScroll.hasVerticalScroller = true
        wordScroll.documentView = wordTextView
        wordScroll.translatesAutoresizingMaskIntoConstraints = false

        saveWordButton.bezelStyle = .rounded
        saveWordButton.controlSize = .small
        saveWordButton.target = self
        saveWordButton.action = #selector(saveWordClicked)

        let saveRow = NSStackView(views: [makeSpacer(), saveWordButton])
        saveRow.orientation = .horizontal
        saveRow.alignment = .centerY

        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [
            headerRow, detailLabel, progressBar, buttonRow, previewButton,
            sep, wordCaption, wordScroll, saveRow, footerLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: headerRow)
        stack.setCustomSpacing(14, after: sep)
        stack.setCustomSpacing(6, after: saveRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            wordScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            wordScroll.heightAnchor.constraint(equalToConstant: 72),
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        // view 是懒加载的：loadView 之前被调用时直接跳过（如 AppDelegate 初始化阶段）
        guard isViewLoaded, wordTextView != nil else { return }
        let phase = engine.phase
        statusDot.layer?.backgroundColor = Self.color(for: phase).cgColor
        phaseLabel.stringValue = Self.name(for: phase)
        detailLabel.stringValue = engine.statusText
        progressBar.doubleValue = engine.progress
        startStopButton.title = phase == .idle ? "启动提醒" : "停止提醒"

        if wordTextView.window?.firstResponder !== wordTextView {
            wordTextView.string = SettingsStore.shared.current.reminderWord
        }

        let s = SettingsStore.shared.current
        var lockInfo = ""
        if s.autoLockAfterBreak {
            lockInfo = SystemLock.accessibilityGranted ? "　真锁屏✅" : "　真锁屏⚠️未授权"
        }
        footerLabel.stringValue = "开机自启：\(LaunchAtLogin.isEnabled ? "开" : "关")　"
            + "锁屏后自动熄屏：\(s.autoLockAfterBreak ? "开" : "关")\(lockInfo)　"
            + "已完成：\(engine.completedCycles) 轮"
    }

    // MARK: - Actions

    @objc private func startStopToggled() {
        if engine.phase == .idle || engine.phase == .paused {
            engine.start()
        } else {
            engine.stop()
        }
        refresh()
    }

    @objc private func settingsClicked() {
        onOpenSettings()
    }

    @objc private func previewClicked() {
        engine.lockNow()
        refresh()
    }

    @objc private func saveWordClicked() {
        var s = SettingsStore.shared.current
        s.reminderWord = wordTextView.string
        SettingsStore.shared.update(s)
        refresh()
    }

    // MARK: - Helpers

    private func makeSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private static func color(for phase: ReminderEngine.Phase) -> NSColor {
        switch phase {
        case .idle: return .systemGray
        case .running: return .systemGreen
        case .resting: return .systemRed
        case .paused: return .systemOrange
        }
    }

    private static func name(for phase: ReminderEngine.Phase) -> String {
        switch phase {
        case .idle: return "未启动"
        case .running: return "运行中"
        case .resting: return "锁屏中"
        case .paused: return "已暂停"
        }
    }
}
