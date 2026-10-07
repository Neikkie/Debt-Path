import Foundation

/// Everything needed to simulate a payoff plan.
struct PlanScenario {
    var debts: [Debt]
    var strategy: PayoffStrategy
    /// Extra money paid every month on top of the minimums.
    var extraMonthly: Double
    /// Additional recurring or one-time payments.
    var extraPayments: [ExtraPayment] = []
    /// A lump sum applied in the first month of the plan (used by the what-if simulator).
    var oneTimePayment: Double = 0
    /// Percentage points added to (or subtracted from) every debt's APR.
    var aprAdjustment: Double = 0
    /// Months of minimum-only payments before extra payments begin.
    var startDelayMonths: Int = 0
    /// When false, payments freed up by paid-off debts are not rolled over and no
    /// extra is paid. This models a "minimum payments only" baseline.
    var rollsOverPayments: Bool = true
}

/// The result of simulating a scenario month by month.
struct PayoffPlan {
    struct Month: Identifiable {
        let number: Int
        let payments: [UUID: Double]
        let interest: Double
        let remainingBalance: Double

        var id: Int { number }
        var totalPayment: Double { payments.values.reduce(0, +) }
        var date: Date { PlanCalendar.date(forMonth: number) }
    }

    struct Milestone: Identifiable {
        let debt: Debt
        let month: Int
        let interestPaid: Double

        var id: UUID { debt.id }
        var date: Date { PlanCalendar.date(forMonth: month) }
    }

    let strategy: PayoffStrategy
    let startingBalance: Double
    let months: [Month]
    /// Debts in the order they are paid off.
    let milestones: [Milestone]
    /// Debts in the order they receive extra payments.
    let priorityOrder: [Debt]
    let totalInterest: Double
    let totalPaid: Double
    /// False when the debts can't be paid off within the simulation limit.
    let isComplete: Bool

    var monthCount: Int { months.count }
    var debtFreeDate: Date? { isComplete ? PlanCalendar.date(forMonth: monthCount) : nil }
    var firstMonthPayment: Double { months.first?.totalPayment ?? 0 }
}

enum PayoffCalculator {
    /// Upper bound on the simulation (50 years) so an insufficient payment can't loop forever.
    static let maxMonths = 600

    static func makePlan(_ scenario: PlanScenario) -> PayoffPlan {
        let ordered = scenario.strategy.prioritized(scenario.debts.filter { $0.balance > 0 })
        var balances = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0.balance) })
        let scheduledMinimums = ordered.reduce(0) { $0 + $1.minimumPayment }
        var interestByDebt: [UUID: Double] = [:]
        var months: [PayoffPlan.Month] = []
        var milestones: [PayoffPlan.Milestone] = []
        var totalInterest = 0.0
        var totalPaid = 0.0

        while balances.values.contains(where: { $0 > 0 }) && months.count < maxMonths {
            let monthNumber = months.count + 1
            let planIsActive = monthNumber > scenario.startDelayMonths
            var monthInterest = 0.0
            var payments: [UUID: Double] = [:]

            // 1. Accrue one month of interest on every open balance.
            for debt in ordered {
                let balance = balances[debt.id, default: 0]
                guard balance > 0 else { continue }
                let rate = max(0, debt.apr + scenario.aprAdjustment)
                let interest = (balance * rate / 100 / 12).roundedToCents
                balances[debt.id] = balance + interest
                interestByDebt[debt.id, default: 0] += interest
                monthInterest += interest
            }

            // 2. Pay the minimum on every open debt.
            var minimumsPaid = 0.0
            for debt in ordered {
                let balance = balances[debt.id, default: 0]
                guard balance > 0 else { continue }
                let payment = min(balance, debt.minimumPayment)
                balances[debt.id] = (balance - payment).roundedToCents
                payments[debt.id, default: 0] += payment
                minimumsPaid += payment
            }

            // 3. Once the plan is active, send extra money (plus minimums freed up by
            //    paid-off debts) to debts in priority order, rolling over as each is cleared.
            if planIsActive && scenario.rollsOverPayments {
                var available = scenario.extraMonthly
                    + extraPayments(in: monthNumber, from: scenario.extraPayments)
                    + max(0, scheduledMinimums - minimumsPaid)
                if monthNumber == scenario.startDelayMonths + 1 {
                    available += scenario.oneTimePayment
                }

                for debt in ordered where available > 0 {
                    let balance = balances[debt.id, default: 0]
                    guard balance > 0 else { continue }
                    let payment = min(balance, available)
                    balances[debt.id] = (balance - payment).roundedToCents
                    payments[debt.id, default: 0] += payment
                    available -= payment
                }
            }

            // 4. Record any debts that reached zero this month.
            for debt in ordered where balances[debt.id, default: 0] <= 0 {
                guard !milestones.contains(where: { $0.debt.id == debt.id }) else { continue }
                milestones.append(.init(debt: debt, month: monthNumber, interestPaid: interestByDebt[debt.id, default: 0]))
            }

            totalPaid += payments.values.reduce(0, +)
            totalInterest += monthInterest
            months.append(.init(
                number: monthNumber,
                payments: payments,
                interest: monthInterest,
                remainingBalance: max(0, balances.values.reduce(0, +))
            ))
        }

        return PayoffPlan(
            strategy: scenario.strategy,
            startingBalance: ordered.reduce(0) { $0 + $1.balance },
            months: months,
            milestones: milestones,
            priorityOrder: ordered,
            totalInterest: totalInterest,
            totalPaid: totalPaid,
            isComplete: !balances.values.contains(where: { $0 > 0 })
        )
    }

    /// Sum of the additional payments scheduled for a given plan month.
    private static func extraPayments(in month: Int, from extras: [ExtraPayment]) -> Double {
        extras.reduce(0) { total, extra in
            let startMonth = PlanCalendar.monthIndex(for: extra.startDate)
            switch extra.frequency {
            case .monthly:
                return month >= max(1, startMonth) ? total + extra.amount : total
            case .oneTime:
                // A one-time payment dated this calendar month lands in the first plan month.
                guard startMonth >= 0 else { return total }
                return month == max(1, startMonth) ? total + extra.amount : total
            }
        }
    }
}

/// Maps plan month numbers to calendar dates. Month 1 is next month.
enum PlanCalendar {
    static var currentMonthStart: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    static func date(forMonth month: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: month, to: currentMonthStart) ?? currentMonthStart
    }

    /// The number of calendar months between the current month and `date`.
    static func monthIndex(for date: Date) -> Int {
        let start = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
        return Calendar.current.dateComponents([.month], from: currentMonthStart, to: start).month ?? 0
    }
}

extension Double {
    var roundedToCents: Double { (self * 100).rounded() / 100 }
}
