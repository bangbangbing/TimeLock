import AppKit
import Darwin

private let launchAgentLabel = "com.zhougj.timelock"

private var singleInstanceLockDescriptor: Int32 = -1

/// 文件锁保证单实例（登录项/直接启动路径会绕过 LSMultipleInstancesProhibited）。
private func acquireSingleInstanceLock() -> Bool {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(launchAgentLabel).lock")
    let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
    guard descriptor >= 0 else { return true }
    if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
        close(descriptor)
        return false
    }
    singleInstanceLockDescriptor = descriptor
    return true
}

private func activateRunningInstance() {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let existing = NSRunningApplication
        .runningApplications(withBundleIdentifier: launchAgentLabel)
        .first { $0.processIdentifier != currentPID }
    if #available(macOS 14.0, *) {
        existing?.activate()
    } else {
        existing?.activate(options: [.activateIgnoringOtherApps])
    }
}

let application = NSApplication.shared
private let appDelegate = AppDelegate()

if !acquireSingleInstanceLock() {
    activateRunningInstance()
    exit(0)
}

application.setActivationPolicy(.accessory)
application.delegate = appDelegate
application.run()
