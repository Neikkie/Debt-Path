import Foundation
import Observation
import SwiftUI

/// Holds the user's debts, payments, and plan settings, persisting them to UserDefaults.
@Observable
final class DebtStore {
    var debts: [Debt] { didSet { save() } }
    var payments: [PaymentRecord] { didSet { save() } }
    var extraPayments: [ExtraPayment] { didSet { save() } }
    var extraMonthly: Double { didSet { save() } }
    var strategy: PayoffStrategy { didSet { save() } }
    var remindersEnabled: Bool { didSet { save() } }
    var reminderDaysBefore: Int { didSet { save() } }

    private static let storageKey = "DebtPath.data.v1"

    /// The shape of the data written to disk.
    private struct SavedData: Codable {
        var debts: [Debt]
        var payments: [PaymentRecord]
        var extraPayments: [ExtraPayment]
        var extraMonthly: Double
        var strategy: PayoffStrategy
        var remindersEnabled: Bool
        var reminderDaysBefore: Int
    }

    /// Whether changes are written to disk. Previews use an in-memory store.
    private let persists: Bool

    /// Loads saved data. New users start with no debts; they log their own.
    init() {
        persists = true
        NSUbiquitousKeyValueStore.default.synchronize()
        let loaded = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(SavedData.self, from: $0) }
            ?? Self.emptyData
        let saved = Self.removingLegacySampleData(from: loaded)
        debts = saved.debts
        payments = saved.payments
        extraPayments = saved.extraPayments
        extraMonthly = saved.extraMonthly
        strategy = saved.strategy
        remindersEnabled = saved.remindersEnabled
        reminderDaysBefore = saved.reminderDaysBefore

        // Property observers don't run during init, so persist any cleanup explicitly.
        if saved.debts.count != loaded.debts.count {
            save()
        }
    }

    private init(inMemory data: SavedData) {
        persists = false
        debts = data.debts
        payments = data.payments
        extraPayments = data.extraPayments
        extraMonthly = data.extraMonthly
        strategy = data.strategy
        remindersEnabled = data.remindersEnabled
        reminderDaysBefore = data.reminderDaysBefore
    }

    /// An empty in-memory store for Xcode previews. Nothing is prefilled or saved.
    static var preview: DebtStore { DebtStore(inMemory: emptyData) }

    /// Earlier versions added example debts on first launch. Remove them once so only
    /// debts the user entered remain. Matches the exact example set so real debts are kept.
    private static func removingLegacySampleData(from data: SavedData) -> SavedData {
        let cleanupKey = "DebtPath.legacySampleCleanupDone"
        guard !UserDefaults.standard.bool(forKey: cleanupKey) else { return data }
        UserDefaults.standard.set(true, forKey: cleanupKey)

        let legacySamples: [(name: String, originalBalance: Double)] = [
            ("Visa Card", 6_750),
            ("Federal Student Loan", 18_900),
            ("Personal Loan", 3_400),
            ("Hospital Bill", 1_000),
        ]
        let matches = data.debts.filter { debt in
            legacySamples.contains { $0.name == debt.name && $0.originalBalance == debt.originalBalance }
        }
        guard matches.count == legacySamples.count else { return data }

        let sampleIDs = Set(matches.map(\.id))
        var cleaned = data
        cleaned.debts.removeAll { sampleIDs.contains($0.id) }
        cleaned.payments.removeAll { sampleIDs.contains($0.debtID) }
        if cleaned.debts.isEmpty && data.extraMonthly == 250 {
            cleaned.extraMonthly = 0
        }
        return cleaned
    }

    /// Removes every debt, payment, and setting.
    func eraseAllData() {
        debts = []
        payments = []
        extraPayments = []
        extraMonthly = 0
        strategy = .avalanche
        remindersEnabled = false
        reminderDaysBefore = 3
        pendingUndo = nil
    }

    private func save() {
        guard persists else { return }
        let data = SavedData(
            debts: debts,
            payments: payments,
            extraPayments: extraPayments,
            extraMonthly: extraMonthly,
            strategy: strategy,
            remindersEnabled: remindersEnabled,
            reminderDaysBefore: reminderDaysBefore
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)

        if iCloudBackupEnabled {
            let cloud = NSUbiquitousKeyValueStore.default
            let now = Date.now
            cloud.set(encoded, forKey: Self.cloudDataKey)
            cloud.set(now.timeIntervalSince1970, forKey: Self.cloudDateKey)
            lastCloudBackup = now
        }
    }

    // MARK: - iCloud backup

    private static let cloudDataKey = "DebtPath.backup.data"
    private static let cloudDateKey = "DebtPath.backup.date"
    private static let cloudEnabledKey = "DebtPath.backup.enabled"

    /// When on, every change is also copied to iCloud so data survives deleting the app.
    var iCloudBackupEnabled = UserDefaults.standard.bool(forKey: DebtStore.cloudEnabledKey) {
        didSet {
            UserDefaults.standard.set(iCloudBackupEnabled, forKey: Self.cloudEnabledKey)
            if iCloudBackupEnabled { save() }
        }
    }

    /// When data was last copied to iCloud, if ever.
    var lastCloudBackup: Date? = DebtStore.cloudBackupDate()

    private static func cloudBackupDate() -> Date? {
        let interval = NSUbiquitousKeyValueStore.default.double(forKey: cloudDateKey)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// Whether an iCloud backup exists that could be restored.
    var hasCloudBackup: Bool {
        NSUbiquitousKeyValueStore.default.data(forKey: Self.cloudDataKey) != nil
    }

    /// Replaces the data on this device with the iCloud backup. Returns false if there's no usable backup.
    @discardableResult
    func restoreFromCloud() -> Bool {
        NSUbiquitousKeyValueStore.default.synchronize()
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.cloudDataKey),
              let backup = try? JSONDecoder().decode(SavedData.self, from: data) else { return false }
        debts = backup.debts
        payments = backup.payments
        extraPayments = backup.extraPayments
        extraMonthly = backup.extraMonthly
        strategy = backup.strategy
        remindersEnabled = backup.remindersEnabled
        reminderDaysBefore = backup.reminderDaysBefore
        pendingUndo = nil
        lastCloudBackup = Self.cloudBackupDate()
        return true
    }

    // MARK: - Undo and celebrations (not saved)

    /// Something that was just deleted and can be restored.
    struct UndoAction: Identifiable {
        enum Item {
            case debt(Debt, index: Int, payments: [PaymentRecord])
            case payment(PaymentRecord)
        }

        let id = UUID()
        let item: Item
        let message: String
    }

    /// The most recent deletion, shown in an Undo banner for a few seconds.
    var pendingUndo: UndoAction?

    /// A debt that was just paid off, shown in a celebration.
    var celebratedDebt: Debt?

    /// Set to ask the Debts screen to open its Add Debt form (e.g. from the welcome screen).
    var addDebtRequested = false

    func undoLastDeletion() {
        guard let pendingUndo else { return }
        switch pendingUndo.item {
        case .debt(let debt, let index, let debtPayments):
            debts.insert(debt, at: min(index, debts.count))
            payments.append(contentsOf: debtPayments)
        case .payment(let payment):
            if let index = debts.firstIndex(where: { $0.id == payment.debtID }) {
                debts[index].balance = max(0, debts[index].balance - payment.amount).roundedToCents
                syncInstallments(at: index)
            }
            payments.append(payment)
        }
        self.pendingUndo = nil
    }

    // MARK: - Totals

    var openDebts: [Debt] { debts.filter { !$0.isPaidOff } }
    var totalBalance: Double { debts.reduce(0) { $0 + max(0, $1.balance) } }
    var totalOriginalBalance: Double { debts.reduce(0) { $0 + $1.originalBalance } }
    var totalMinimums: Double { openDebts.reduce(0) { $0 + $1.minimumPayment } }
    var totalLoggedPayments: Double { payments.reduce(0) { $0 + $1.amount } }

    /// Fraction of all original balances that has been paid off, from 0 to 1.
    var progress: Double {
        guard totalOriginalBalance > 0 else { return 0 }
        return min(1, max(0, 1 - totalBalance / totalOriginalBalance))
    }

    /// The debt currently receiving extra payments under the chosen strategy.
    var focusDebt: Debt? { strategy.prioritized(openDebts).first }

    // MARK: - Plans

    func scenario(for strategy: PayoffStrategy? = nil) -> PlanScenario {
        PlanScenario(
            debts: debts,
            strategy: strategy ?? self.strategy,
            extraMonthly: extraMonthly,
            extraPayments: extraPayments
        )
    }

    func plan(for strategy: PayoffStrategy? = nil) -> PayoffPlan {
        PayoffCalculator.makePlan(scenario(for: strategy))
    }

    /// Baseline where only minimums are paid and nothing rolls over.
    var minimumOnlyPlan: PayoffPlan {
        var baseline = scenario(for: .avalanche)
        baseline.extraMonthly = 0
        baseline.extraPayments = []
        baseline.rollsOverPayments = false
        return PayoffCalculator.makePlan(baseline)
    }

    // MARK: - Editing

    func upsert(_ debt: Debt) {
        var debt = debt
        debt.originalBalance = max(debt.originalBalance, debt.balance)
        if let index = debts.firstIndex(where: { $0.id == debt.id }) {
            debts[index] = debt
        } else {
            debts.append(debt)
        }
    }

    /// Deletes a debt and its payment history. Can be undone with `undoLastDeletion()`.
    func delete(_ debt: Debt) {
        guard let index = debts.firstIndex(where: { $0.id == debt.id }) else { return }
        let debtPayments = payments.filter { $0.debtID == debt.id }
        debts.remove(at: index)
        payments.removeAll { $0.debtID == debt.id }
        pendingUndo = UndoAction(item: .debt(debt, index: index, payments: debtPayments), message: "Deleted \(debt.name)")
    }

    /// Moves a debt one place up or down in the custom priority order (used by VoiceOver actions).
    func moveInPriority(_ debt: Debt, by offset: Int) {
        let open = openDebts
        guard let position = open.firstIndex(where: { $0.id == debt.id }),
              open.indices.contains(position + offset),
              let from = debts.firstIndex(where: { $0.id == debt.id }),
              let to = debts.firstIndex(where: { $0.id == open[position + offset].id }) else { return }
        debts.swapAt(from, to)
    }

    /// Open debts whose minimum payment doesn't cover the estimated monthly interest.
    var debtsWithLowMinimums: [Debt] {
        openDebts.filter { !$0.minimumCoversInterest }
    }

    func debt(withID id: UUID) -> Debt? {
        debts.first { $0.id == id }
    }

    /// Logs a payment and reduces the debt's balance by the same amount.
    func recordPayment(_ payment: PaymentRecord) {
        guard let index = debts.firstIndex(where: { $0.id == payment.debtID }) else { return }
        var payment = payment
        payment.amount = min(payment.amount, debts[index].balance)
        guard payment.amount > 0 else { return }
        debts[index].balance = (debts[index].balance - payment.amount).roundedToCents
        syncInstallments(at: index)
        payments.append(payment)
        if debts[index].isPaidOff {
            celebratedDebt = debts[index]
        }
    }

    /// Changes a logged payment's amount, date, or note and adjusts the balance by the difference.
    func updatePayment(_ updated: PaymentRecord) {
        guard let paymentIndex = payments.firstIndex(where: { $0.id == updated.id }),
              let debtIndex = debts.firstIndex(where: { $0.id == updated.debtID }) else { return }
        let original = payments[paymentIndex]
        let balanceBeforePayment = debts[debtIndex].balance + original.amount
        var updated = updated
        updated.amount = min(max(0, updated.amount), balanceBeforePayment).roundedToCents
        guard updated.amount > 0 else { return }

        let wasPaidOff = debts[debtIndex].isPaidOff
        debts[debtIndex].balance = (balanceBeforePayment - updated.amount).roundedToCents
        syncInstallments(at: debtIndex)
        payments[paymentIndex] = updated
        if !wasPaidOff && debts[debtIndex].isPaidOff {
            celebratedDebt = debts[debtIndex]
        }
    }

    /// Removes a logged payment and restores the amount to the debt's balance. Can be undone.
    func deletePayment(_ payment: PaymentRecord) {
        if let index = debts.firstIndex(where: { $0.id == payment.debtID }) {
            debts[index].balance = (debts[index].balance + payment.amount).roundedToCents
            syncInstallments(at: index)
        }
        payments.removeAll { $0.id == payment.id }
        pendingUndo = UndoAction(item: .payment(payment), message: "Payment deleted")
    }

    /// Keeps a buy now, pay later debt's installment count in step with its balance.
    private func syncInstallments(at index: Int) {
        guard var plan = debts[index].installmentPlan, plan.installmentAmount > 0 else { return }
        plan.installmentsRemaining = Int((debts[index].balance / plan.installmentAmount).rounded(.up))
        debts[index].installmentPlan = plan
    }

    func payments(for debt: Debt) -> [PaymentRecord] {
        payments.filter { $0.debtID == debt.id }.sorted { $0.date > $1.date }
    }

    func upsert(_ extra: ExtraPayment) {
        if let index = extraPayments.firstIndex(where: { $0.id == extra.id }) {
            extraPayments[index] = extra
        } else {
            extraPayments.append(extra)
        }
    }

    // MARK: - History

    struct BalancePoint: Identifiable {
        let date: Date
        let balance: Double
        let series: String
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    /// Total balance over time, reconstructed from logged payments.
    var balanceHistory: [BalancePoint] {
        let sorted = payments.sorted { $0.date < $1.date }
        var running = totalBalance + totalLoggedPayments
        var points: [BalancePoint] = []
        if let first = sorted.first {
            points.append(.init(date: Calendar.current.date(byAdding: .day, value: -1, to: first.date) ?? first.date, balance: running, series: "Actual"))
        }
        for payment in sorted {
            running -= payment.amount
            points.append(.init(date: payment.date, balance: max(0, running), series: "Actual"))
        }
        points.append(.init(date: .now, balance: totalBalance, series: "Actual"))
        return points
    }

    /// A value that changes whenever reminder notifications need rescheduling.
    var reminderSignature: [String] {
        [String(remindersEnabled), String(reminderDaysBefore)]
            + openDebts.map { "\($0.id)-\($0.name)-\($0.dueDay)-\($0.minimumPayment)" }
    }

    // MARK: - Initial data

    private static let emptyData = SavedData(
        debts: [],
        payments: [],
        extraPayments: [],
        extraMonthly: 0,
        strategy: .avalanche,
        remindersEnabled: false,
        reminderDaysBefore: 3
    )

}

// MARK: - Formatting helpers

extension Double {
    private static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    var currency: String {
        formatted(.currency(code: Self.currencyCode))
    }

    /// Currency without cents, for large headline figures.
    var wholeCurrency: String {
        formatted(.currency(code: Self.currencyCode).precision(.fractionLength(0)))
    }

    var percent: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    var aprText: String {
        "\(formatted(.number.precision(.fractionLength(0...2))))%"
    }
}

extension Date {
    var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
}

extension Int {
    /// The calendar month `self` months after the current month, e.g. "Mar 2028".
    var monthsFromNow: String { PlanCalendar.date(forMonth: self).monthYear }

    /// A human-readable duration such as "2 yr 3 mo".
    var durationDescription: String {
        let years = self / 12
        let months = self % 12
        switch (years, months) {
        case (0, _): return "\(months) mo"
        case (_, 0): return "\(years) yr"
        default: return "\(years) yr \(months) mo"
        }
    }

    /// An ordinal such as "1st" or "22nd".
    var ordinal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
