import Foundation
import UserNotifications

@MainActor final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((UUID, String) -> Void)?
    var pendingOpen: (UUID, String)?
    var denied = false
    private var generation = 0
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func schedule(_ candidates: [ReminderCandidate], enabled: Bool, request: Bool, ephemeral: Bool) async {
        guard !ephemeral else { return }
        generation += 1; let ticket = generation
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if enabled && request && settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert,.badge,.sound]); settings = await center.notificationSettings()
        }
        denied = settings.authorizationStatus == .denied
        guard ticket == generation else { return }
        center.removeAllPendingNotificationRequests()
        guard enabled, [.authorized,.provisional,.ephemeral].contains(settings.authorizationStatus) else { return }
        for plan in ReminderPlan.make(candidates, now: Date()) {
            guard ticket == generation else { return }
            let content = UNMutableNotificationContent()
            content.title = plan.kind == "recurring" ? L.f("Invoice for %@ is ready", plan.title) : L.t("Invoice payment reminder")
            content.body = plan.kind == "recurring" ? L.t("Open to create a draft. Nothing is sent automatically.") : plan.title
            content.sound = .default; content.userInfo = ["id": plan.documentID.uuidString, "kind": plan.kind]
            let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: plan.date)
            try? await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let string = info["id"] as? String, let id = UUID(uuidString: string) {
            let kind = info["kind"] as? String ?? "reminder"
            Task { @MainActor in if let open = self.onOpen { open(id, kind) } else { self.pendingOpen = (id, kind) } }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner,.sound]) }
}
