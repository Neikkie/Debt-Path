import Foundation
import SwiftUI

/// The category of a debt, used for icons, colors, and grouping.
enum DebtKind: String, Codable, CaseIterable, Identifiable {
    case creditCard
    case studentLoan
    case personalLoan
    case medical
    case buyNowPayLater
    case auto
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditCard: "Credit Card"
        case .studentLoan: "Student Loan"
        case .personalLoan: "Personal Loan"
        case .medical: "Medical Debt"
        case .buyNowPayLater: "Buy Now, Pay Later"
        case .auto: "Auto Loan"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .creditCard: "creditcard.fill"
        case .studentLoan: "graduationcap.fill"
        case .personalLoan: "banknote.fill"
        case .medical: "cross.case.fill"
        case .buyNowPayLater: "bag.fill"
        case .auto: "car.fill"
        case .other: "square.stack.fill"
        }
    }

    var color: Color {
        switch self {
        case .creditCard: .purple
        case .studentLoan: .blue
        case .personalLoan: .orange
        case .medical: .pink
        case .buyNowPayLater: .mint
        case .auto: .teal
        case .other: .gray
        }
    }
}

/// Installment details for a buy now, pay later purchase (e.g. "pay in 4").
struct InstallmentPlan: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case weekly
        case biweekly
        case monthly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekly: "Every Week"
            case .biweekly: "Every 2 Weeks"
            case .monthly: "Every Month"
            }
        }

        /// Average number of installments per month, used to estimate a monthly payment.
        var paymentsPerMonth: Double {
            switch self {
            case .weekly: 52.0 / 12.0
            case .biweekly: 26.0 / 12.0
            case .monthly: 1
            }
        }
    }

    var installmentAmount: Double
    var installmentsRemaining: Int
    var frequency: Frequency

    var remainingBalance: Double { (installmentAmount * Double(installmentsRemaining)).roundedToCents }

    /// The estimated amount due per month across all installments.
    var estimatedMonthlyPayment: Double { (installmentAmount * frequency.paymentsPerMonth).roundedToCents }
}

/// A single debt the user wants to pay off.
struct Debt: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: DebtKind
    /// The current balance. Logged payments reduce this value.
    var balance: Double
    /// The balance when the debt was added, used to measure progress.
    var originalBalance: Double
    /// Annual percentage rate, expressed as a percent (e.g. 19.99).
    var apr: Double
    var minimumPayment: Double
    /// Day of the month the payment is due (1–31).
    var dueDay: Int
    /// Installment details, for buy now, pay later debts.
    var installmentPlan: InstallmentPlan?

    init(
        id: UUID = UUID(),
        name: String,
        kind: DebtKind,
        balance: Double,
        originalBalance: Double? = nil,
        apr: Double,
        minimumPayment: Double,
        dueDay: Int,
        installmentPlan: InstallmentPlan? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.balance = balance
        self.originalBalance = originalBalance ?? balance
        self.apr = apr
        self.minimumPayment = minimumPayment
        self.dueDay = dueDay
        self.installmentPlan = installmentPlan
    }

    var isPaidOff: Bool { balance <= 0 }

    /// Fraction of the original balance that has been paid, from 0 to 1.
    var progress: Double {
        guard originalBalance > 0 else { return 0 }
        return min(1, max(0, 1 - balance / originalBalance))
    }

    /// Estimated interest charged next month at the current balance.
    var estimatedMonthlyInterest: Double { (max(0, balance) * apr / 100 / 12).roundedToCents }

    /// False when the minimum payment doesn't cover monthly interest, so the balance would never go down.
    var minimumCoversInterest: Bool { apr <= 0 || minimumPayment > estimatedMonthlyInterest }

    /// The next calendar date this debt's payment is due. Due days past the end of a
    /// short month (e.g. the 31st in April) fall on that month's last day.
    var nextDueDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func dueDate(inMonthOf date: Date) -> Date? {
            guard let month = calendar.dateInterval(of: .month, for: date),
                  let days = calendar.range(of: .day, in: .month, for: date) else { return nil }
            return calendar.date(byAdding: .day, value: min(dueDay, days.count) - 1, to: month.start)
        }

        if let thisMonth = dueDate(inMonthOf: today), thisMonth >= today { return thisMonth }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        return dueDate(inMonthOf: nextMonth) ?? nextMonth
    }
}

/// The order in which extra money is directed at debts.
enum PayoffStrategy: String, CaseIterable, Identifiable, Codable {
    case avalanche
    case snowball
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avalanche: "Avalanche"
        case .snowball: "Snowball"
        case .custom: "Custom"
        }
    }

    var summary: String {
        switch self {
        case .avalanche: "Highest interest rate first. Minimizes total interest."
        case .snowball: "Smallest balance first. Builds momentum with quick wins."
        case .custom: "You choose the order. Drag debts to set your priority."
        }
    }

    var systemImage: String {
        switch self {
        case .avalanche: "mountain.2.fill"
        case .snowball: "snowflake"
        case .custom: "hand.draw.fill"
        }
    }

    var color: Color {
        switch self {
        case .avalanche: .blue
        case .snowball: .cyan
        case .custom: .indigo
        }
    }

    /// Returns debts in the priority order used to receive extra payments.
    /// The custom strategy keeps the order the debts are given in.
    func prioritized(_ debts: [Debt]) -> [Debt] {
        switch self {
        case .avalanche:
            debts.sorted { lhs, rhs in
                lhs.apr != rhs.apr ? lhs.apr > rhs.apr : lhs.balance < rhs.balance
            }
        case .snowball:
            debts.sorted { lhs, rhs in
                lhs.balance != rhs.balance ? lhs.balance < rhs.balance : lhs.apr > rhs.apr
            }
        case .custom:
            debts
        }
    }
}

/// A payment the user made and logged manually.
struct PaymentRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var debtID: UUID
    var amount: Double
    var date: Date
    var note: String = ""
}

/// An additional payment on top of the regular extra monthly amount,
/// such as a side-hustle contribution or a tax refund.
struct ExtraPayment: Identifiable, Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case monthly
        case oneTime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .monthly: "Every Month"
            case .oneTime: "One Time"
            }
        }
    }

    var id = UUID()
    var name: String
    var amount: Double
    var frequency: Frequency
    /// For monthly payments, the first month it applies. For one-time payments, the month it's made.
    var startDate: Date
}
