import AppKit

/// 全屏边框窗口（borderless 默认无法成为 key window，需重写）。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 覆盖层内容视图：深色背景 + 提醒词（支持多行）+ 倒计时。
/// 故意不实现任何鼠标/键盘关闭逻辑 —— 强制锁屏期间不可关闭。
final class OverlayView: NSView {
    private let countdownLabel: NSTextField

    init(word: String, autoLockOnFinish: Bool) {
        countdownLabel = NSTextField(labelWithString: "")

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1).cgColor

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let caption = NSTextField(labelWithString: "强制休息 · REMINDER")
        caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.textColor = NSColor.white.withAlphaComponent(0.45)

        let wordLabel = NSTextField(wrappingLabelWithString: word)
        wordLabel.alignment = .center
        wordLabel.font = .systemFont(ofSize: 44, weight: .semibold)
        wordLabel.textColor = .white
        wordLabel.maximumNumberOfLines = 0

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        countdownLabel.textColor = NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)

        let note = NSTextField(labelWithString: autoLockOnFinish
            ? "结束后将自动熄屏锁定，解锁后继续提醒循环"
            : "结束后自动回到锁屏前状态")
        note.font = .systemFont(ofSize: 12)
        note.textColor = NSColor.white.withAlphaComponent(0.35)

        let hint = NSTextField(labelWithString: "此窗口不可关闭")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = NSColor.white.withAlphaComponent(0.2)

        let stack = NSStackView(views: [spinner, caption, wordLabel, countdownLabel, note, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(8, after: spinner)
        stack.setCustomSpacing(24, after: wordLabel)
        stack.setCustomSpacing(6, after: countdownLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
            wordLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCountdown(_ seconds: Int) {
        countdownLabel.stringValue = "\(seconds)s"
    }
}

/// 全屏覆盖层控制器：为每块显示器创建一个 .screenSaver 级窗口。
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private var timer: Timer?
    private var completion: ((Bool) -> Void)?
    private var endDate: Date?
    private var currentWord = ""
    private var currentAutoLock = false

    var isShowing: Bool { !windows.isEmpty }

    var remainingSeconds: Int {
        guard let endDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    /// 显示覆盖层。倒计时结束后回调 onFinished(autoLockRequested)。
    func show(word: String, duration: Int, autoLockOnFinish: Bool,
              onFinished: @escaping (Bool) -> Void) {
        close(notifyCompletion: false)
        currentWord = word
        currentAutoLock = autoLockOnFinish
        completion = onFinished
        endDate = Date().addingTimeInterval(TimeInterval(max(1, duration)))
        createWindows()
        updateCountdown()

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 显示器配置变化时重建窗口（保留剩余时间）。
    func refreshScreens() {
        guard isShowing else { return }
        closeWindows()
        createWindows()
        updateCountdown()
    }

    /// 关闭覆盖层。notifyCompletion 为 true 时触发完成回调。
    func close(notifyCompletion: Bool) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        closeWindows()
        let callback = completion
        completion = nil
        if notifyCompletion {
            callback?(currentAutoLock)
        }
    }

    private func tick() {
        if remainingSeconds == 0 {
            let requested = currentAutoLock
            let callback = completion
            completion = nil
            close(notifyCompletion: false)
            callback?(requested)
        } else {
            updateCountdown()
        }
    }

    private func updateCountdown() {
        let seconds = remainingSeconds
        views.forEach { $0.updateCountdown(seconds) }
    }

    private func createWindows() {
        for screen in NSScreen.screens {
            let view = OverlayView(word: currentWord, autoLockOnFinish: currentAutoLock)
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: false)
            window.contentView = view
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }

        if let window = windows.first {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
    }
}
