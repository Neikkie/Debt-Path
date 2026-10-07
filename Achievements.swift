import Foundation
import SwiftUI

/// A progress badge earned from real activity (logged payments and cleared debts).
struct Badge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let isEarned: Bool
}

/// A checkpoint on the way to being debt-free, with an estimated date.
struct GoalMilestone: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let color: Color
    let isReached: Bool
    /// Estimated date the milestone is reached, if it hasn't been already.
    let estimatedDate: Date?
}

extension DebtStore {
    var badges: [Badge] {
        let paidOffCount = debts.filter { $0.isPaidOff && $0.originalBalance > 0 }.count
        let paymentMonths = Set(payments.map { Calendar.current.dateComponents([.year, .month], from: $0.date) })

        return [
            Badge(id: "first-payment", title: "First Step", detail: "Log your first payment",
                  systemImage: "shoe.fill", color: .green, isEarned: !payments.isEmpty),
            Badge(id: "streak", title: "Consistent", detail: "Pay in 3 different months",
                  systemImage: "calendar.badge.checkmark", color: .blue, isEarned: paymentMonths.count >= 3),
            Badge(id: "one-k", title: "$1K Crusher", detail: "Log $1,000 in payments",
                  systemImage: "bolt.fill", color: .orange, isEarned: totalLoggedPayments >= 1_000),
            Badge(id: "first-payoff", title: "Debt Slayer", detail: "Pay off a debt",
                  systemImage: "checkmark.seal.fill", color: .purple, isEarned: paidOffCount >= 1),
            Badge(id: "quarter", title: "25% Free", detail: "Pay off 25% of your debt",
                  systemImage: "chart.pie.fill", color: .teal, isEarned: progress >= 0.25),
            Badge(id: "half", title: "Halfway", detail: "Pay off 50% of your debt",
                  systemImage: "flag.fill", color: .indigo, isEarned: progress >= 0.5),
            Badge(id: "planner", title: "Planner", detail: "Add an extra payment",
                  systemImage: "sparkles", color: .pink, isEarned: extraMonthly > 0 || !extraPayments.isEmpty),
            Badge(id: "free", title: "Debt Free", detail: "Pay off every debt",
                  systemImage: "trophy.fill", color: .yellow, isEarned: !debts.isEmpty && openDebts.isEmpty),
        ]
    }

    /// Percentage checkpoints plus each debt's payoff, with estimated dates from the current plan.
    func goalMilestones(using plan: PayoffPlan) -> [GoalMilestone] {
        let original = totalOriginalBalance
        var milestones: [GoalMilestone] = []

        for threshold in [0.25, 0.5, 0.75] {
            let targetBalance = original * (1 - threshold)
            let month = plan.months.first { $0.remainingBalance <= targetBalance }
            milestones.append(GoalMilestone(
                id: "pct-\(threshold)",
                title: "\(threshold.percent) paid off",
                systemImage: "chart.pie.fill",
                color: .teal,
                isReached: progress >= threshold,
                estimatedDate: month?.date
            ))
        }

        for milestone in plan.milestones {
            milestones.append(GoalMilestone(
                id: "debt-\(milestone.id)",
                title: "\(milestone.debt.name) paid off",
                systemImage: milestone.debt.kind.systemImage,
                color: milestone.debt.kind.color,
                isReached: false,
                estimatedDate: milestone.date
            ))
        }

        for debt in debts where debt.isPaidOff {
            milestones.append(GoalMilestone(
                id: "debt-\(debt.id)", title: "\(debt.name) paid off",
                systemImage: debt.kind.systemImage, color: debt.kind.color,
                isReached: true, estimatedDate: nil
            ))
        }

        milestones.append(GoalMilestone(
            id: "free", title: "Debt-free", systemImage: "trophy.fill", color: .yellow,
            isReached: !debts.isEmpty && openDebts.isEmpty, estimatedDate: plan.debtFreeDate
        ))

        // Reached milestones first, then upcoming ones by date.
        return milestones.sorted { lhs, rhs in
            if lhs.isReached != rhs.isReached { return lhs.isReached }
            return (lhs.estimatedDate ?? .distantFuture) < (rhs.estimatedDate ?? .distantFuture)
        }
    }
}
