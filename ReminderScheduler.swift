import Foundation
import UserNotifications

/// Schedules a repeating monthly local notification ahead of each debt's due date.
enum ReminderScheduler {
    private static let identifierPrefix = "payment-reminder-"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// True when the person has turned off notifications for the app in the Settings app.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func reschedule(debts: [Debt], enabled: Bool, daysBefore: Int) async {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        guard enabled else { return }

        for debt in debts where !debt.isPaidOff {
            let content = UNMutableNotificationContent()
            content.title = "\(debt.name) payment coming up"
            content.body = daysBefore == 0
                ? "Your \(debt.minimumPayment.currency) minimum payment is due today."
                : "Your \(debt.minimumPayment.currency) minimum payment is due on the \(debt.dueDay.ordinal)."
            content.sound = .default

            var components = DateComponents()
            components.day = reminderDay(dueDay: debt.dueDay, daysBefore: daysBefore)
            components.hour = 9

            let request = UNNotificationRequest(
                identifier: identifierPrefix + debt.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
    }

    /// The day of the month to remind on. Days are capped at 28 so the reminder fires in every
    /// month (a repeating trigger for the 31st would skip shorter months), and wrap into the
    /// previous month when the reminder falls before the 1st.
    private static func reminderDay(dueDay: Int, daysBefore: Int) -> Int {
        var day = dueDay - daysBefore
        if day < 1 { day += 28 }
        return min(max(day, 1), 28)
    }
}
