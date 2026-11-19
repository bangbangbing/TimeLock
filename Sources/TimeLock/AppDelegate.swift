import AppKit

/// 应用主协调者：菜单栏图标 + 弹出面板 + 系统事件监听 + 设置窗口。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = ReminderEngine()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var panelController: PopoverPanelController?
    private var settingsController: SettingsWindowController?
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.onChange = { [weak self] in self?.settingsChanged() }

        let panel = PopoverPanelController(engine: engine, onOpenSettings: { [weak self] in
            self?.showSettings()
        })
        panelController = panel

        let popoverController = NSPopover()
        popoverController.behavior = .transient
        popoverController.contentViewController = panel
        popover = popoverController

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "TimeLock")
                button.image?.isTemplate = true
            } else {
                button.title = "⏱"
            }
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item

        engine.onStatusChange = { [weak self] in self?.panelController?.refresh() }
        panel.refresh()

        observeSystemEvents()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.panelController?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer

        // 启动即开始计时（与原型一致）
        engine.start()

        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.runSmokeTest()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--lock-test") {
            let perform = ProcessInfo.processInfo.arguments.contains("--lock-test-go")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.runLockTest(perform: perform)
            }
        }
    }

    /// 锁屏诊断：打印辅助功能授权状态与候选工具情况；--lock-test-go 时实际触发锁屏链。
    private func runLockTest(perform: Bool) {
        print("LOCK_TEST \(SystemLock.diagnosticDescription())")
        if perform {
            let result = SystemLock.lockScreen()
            print("LOCK_TEST result=\(result)")
        } else {
            print("LOCK_TEST dry-run（追加 --lock-test-go 可实际触发锁屏）")
        }
        fflush(stdout)
        exit(0)
    }

    /// 自动化冒烟测试：触发覆盖层，验证窗口覆盖所有屏幕且层级正确。
    private func runSmokeTest() {
        let expectedFrames = NSScreen.screens.map { $0.frame }
        engine.lockNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { exit(1) }
            let overlayWindows = NSApp.windows.filter { ($0 is OverlayWindow) && $0.isVisible }
            let frames = overlayWindows.map { $0.frame }
            self.engine.stop()
            let coversAll = expectedFrames.allSatisfy { expected in
                frames.contains { NSEqualRects($0, expected) }
            }
            let levelOk = overlayWindows.allSatisfy { $0.level == .screenSaver }
            let countOk = overlayWindows.count == expectedFrames.count
            let passed = coversAll && levelOk && countOk
            print("SMOKE_TEST passed=\(passed) screens=\(expectedFrames.count) "
                + "overlayWindows=\(overlayWindows.count) coversAll=\(coversAll) levelOk=\(levelOk)")
            fflush(stdout)
            exit(passed ? 0 : 1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        engine.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - UI 事件

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            panelController?.refresh()
        }
    }

    private func showSettings() {
        popover?.performClose(nil)
        if settingsController == nil {
            settingsController = SettingsWindowController(engine: engine)
        }
        settingsController?.refreshFromStore()
        settingsController?.showWindow(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func settingsChanged() {
        engine.settingsDidChange()
        panelController?.refresh()
        settingsController?.refreshFromStore()
    }

    // MARK: - 系统事件

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(systemSleeping),
                                    name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemWoke),
                                    name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemSleeping),
                                    name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemWoke),
                                    name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    @objc private func systemSleeping() {
        engine.pauseForSystem()
    }

    @objc private func systemWoke() {
        engine.resumeAfterSystem()
    }

    @objc private func screensChanged() {
        engine.screensChanged()
    }
}
