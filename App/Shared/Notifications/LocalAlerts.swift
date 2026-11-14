import Foundation
import SwiftUI
import UserNotifications

/// Posts the poller's alerts as local notifications.
struct LocalAlertCenter: AlertSink {
    func post(_ alerts: [LocalAlert]) async {
        let center = UNUserNotificationCenter.current()
        for a in alerts {
            let content = UNMutableNotificationContent()
            content.title = a.title
            content.subtitle = a.subtitle
            content.body = a.body
            content.threadIdentifier = a.threadID
            content.sound = .default
            content.userInfo = a.userInfo
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

/// Which PR the person tapped a notification for (local or push). RootView observes `pending`, opens the PR and clears it.
@MainActor
final class NotificationRouter: ObservableObject {
    @Published var pending: NotificationPayload?
    func open(_ payload: NotificationPayload) { pending = payload }
}

/// Shows alerts while the app is in front and turns taps into `NotificationRouter.open`. A plain NSObject, set as the
/// center's delegate at launch, separate from the app delegate.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: NotificationRouter
    init(router: NotificationRouter) { self.router = router }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        let router = self.router
        DispatchQueue.main.async {
            if let payload { MainActor.assumeIsolated { router.open(payload) } }
            completionHandler()
        }
    }
}

enum NotificationAuthorization {
    /// Asks once (the system remembers the answer) and returns whether alerts are allowed.
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
