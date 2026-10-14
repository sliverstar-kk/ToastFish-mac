import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter?

    override init() {
        // Calling current() outside an app bundle can raise an Objective-C exception.
        if Bundle.main.bundleIdentifier != nil {
            center = UNUserNotificationCenter.current()
        } else {
            center = nil
        }
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        guard let center else {
            Self.log("未从应用包运行，通知将输出到 stderr。")
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.log("通知授权失败：\(error.localizedDescription)")
            } else if !granted {
                Self.log("通知权限未开启，请在系统设置中允许 ToastFish 通知。")
            }
        }
    }

    func post(title: String, body: String) {
        guard let center else {
            Self.log("\(title)：\(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        center.add(request) { error in
            if let error {
                Self.log("发送通知失败：\(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("ToastFish: \(message)\n".utf8))
    }
}
