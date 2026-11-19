import Foundation
import UserNotifications

/// 系统通知助手：自动锁屏异常时的用户提示。首次使用时请求通知授权。
/// 未打包成 .app 运行（无 bundle id）时退化为 stdout 打印。
enum UserNotifier {
    private static var authorizationResolved = false
    private static var authorized = false

    static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[TimeLock 通知] \(title)：\(body)")
            fflush(stdout)
            return
        }

        let center = UNUserNotificationCenter.current()
        guard authorizationResolved else {
            center.requestAuthorization(options: [.alert]) { granted, _ in
                DispatchQueue.main.async {
                    authorizationResolved = true
                    authorized = granted
                    if granted { deliver(center, title: title, body: body) }
                }
            }
            return
        }
        if authorized {
            deliver(center, title: title, body: body)
        }
    }

    private static func deliver(_ center: UNUserNotificationCenter, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
