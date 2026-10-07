import Foundation
import WidgetKit

/// A small summary of the user's progress that the Home Screen widget reads.
///
/// The widget extension has its own copy of this type (`DebtPathWidget/WidgetSnapshot.swift`).
/// Keep the two in sync so the JSON stays compatible.
struct WidgetSnapshot: Codable, Equatable {
    struct Bill: Codable, Equatable {
        var name: String
        var dueDay: Int
        var minimumPayment: Double
    }

    var totalBalance: Double
    var progress: Double
    var debtFreeDate: Date?
    var openDebtCount: Int
    var focusDebtName: String?
    var bills: [Bill]
    var currencyCode: String

    static let appGroupID = "group.JBF268KK9R.debtpath"
    static let storageKey = "DebtPath.widgetSnapshot.v1"
}

extension DebtStore {
    /// The current summary for the widget.
    var widgetSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            totalBalance: totalBalance,
            progress: progress,
            debtFreeDate: openDebts.isEmpty ? nil : plan().debtFreeDate,
            openDebtCount: openDebts.count,
            focusDebtName: focusDebt?.name,
            bills: openDebts.map { .init(name: $0.name, dueDay: $0.dueDay, minimumPayment: $0.minimumPayment) },
            currencyCode: Locale.current.currency?.identifier ?? "USD"
        )
    }
}

enum WidgetSync {
    /// Sorted keys keep the output stable so unchanged snapshots compare equal.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Writes the snapshot to the shared App Group and asks WidgetKit to refresh, only if it changed.
    static func publish(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
              let encoded = try? encoder.encode(snapshot) else { return }
        guard defaults.data(forKey: WidgetSnapshot.storageKey) != encoded else { return }
        defaults.set(encoded, forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
