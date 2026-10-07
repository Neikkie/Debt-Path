import SwiftUI
import Charts

/// Charts of balance reduction and interest saved, plus milestones and badges.
struct DebtProgressView: View {
    @Environment(DebtStore.self) private var store

    var body: some View {
        let plan = store.plan()
        let minimumOnly = store.minimumOnlyPlan

        // Pushed from the Dashboard, so it shares the Dashboard's navigation stack.
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                balanceChartCard(plan: plan)
                interestSavedCard(plan: plan, minimumOnly: minimumOnly)
                debtProgressCard
                milestonesCard(plan: plan)
                badgesCard
                EstimateFootnote()
            }
            .padding()
        }
        .appBackground(.green)
        .navigationTitle("Progress")
    }

    // MARK: - Cards

    private var heroCard: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: store.progress, lineWidth: 16, tint: .green)
                VStack(spacing: 0) {
                    Text(store.progress.percent)
                        .font(.title.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("paid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paid so far").font(.caption).foregroundStyle(.secondary)
                    Text((store.totalOriginalBalance - store.totalBalance).wholeCurrency)
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining").font(.caption).foregroundStyle(.secondary)
                    Text(store.totalBalance.wholeCurrency)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .glassCard(tint: .green)
    }

    private func balanceChartCard(plan: PayoffPlan) -> some View {
        let actual = store.balanceHistory
        let projected = [DebtStore.BalancePoint(date: .now, balance: store.totalBalance, series: "Projected")]
            + plan.months.map { DebtStore.BalancePoint(date: $0.date, balance: $0.remainingBalance, series: "Projected") }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Balance Reduction")
                .font(.headline)
            Text("Logged payments so far, then your estimated path to zero.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(projected) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
                        .foregroundStyle(.linearGradient(colors: [.green.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance), series: .value("Series", "Projected"))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(actual) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance), series: .value("Series", "Actual"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                RuleMark(x: .value("Today", Date.now))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Today").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let balance = value.as(Double.self) {
                            Text(balance, format: .currency(code: Locale.current.currency?.identifier ?? "USD").notation(.compactName))
                        }
                    }
                }
            }
            .frame(height: 220)

            HStack(spacing: 16) {
                Label("Actual", systemImage: "line.diagonal").foregroundStyle(.primary)
                Label("Estimated", systemImage: "line.diagonal").foregroundStyle(.green)
            }
            .font(.caption)
        }
        .glassCard()
    }

    private func interestSavedCard(plan: PayoffPlan, minimumOnly: PayoffPlan) -> some View {
        let saved = max(0, minimumOnly.totalInterest - plan.totalInterest)
        let bars: [(String, Double, Color)] = [
            ("Minimums only", minimumOnly.totalInterest, .gray),
            ("Your plan", plan.totalInterest, .green),
        ]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Interest Saved")
                    .font(.headline)
                Spacer()
                Text(saved.wholeCurrency)
                    .font(.title2.bold())
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            Text("Estimated interest compared with paying only the minimums\(minimumOnly.isComplete ? "" : " (which wouldn't pay off within 50 years)").")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(bars, id: \.0) { bar in
                BarMark(x: .value("Interest", bar.1), y: .value("Plan", bar.0))
                    .foregroundStyle(bar.2.gradient)
                    .cornerRadius(8)
                    .annotation(position: .trailing) {
                        Text(bar.1.wholeCurrency)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: 110)
        }
        .glassCard()
    }

    private var debtProgressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Debt")
                .font(.headline)
            ForEach(store.debts) { debt in
                HStack(spacing: 12) {
                    KindIcon(kind: debt.kind, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(debt.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(debt.progress.percent)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: debt.progress)
                            .tint(debt.kind.color)
                    }
                }
            }
        }
        .glassCard()
    }

    private func milestonesCard(plan: PayoffPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Milestones")
                .font(.headline)
            ForEach(store.goalMilestones(using: plan)) { milestone in
                HStack(spacing: 12) {
                    Image(systemName: milestone.isReached ? "checkmark.circle.fill" : milestone.systemImage)
                        .font(.title3)
                        .foregroundStyle(milestone.isReached ? .green : milestone.color)
                        .frame(width: 28)
                    Text(milestone.title)
                        .font(.subheadline)
                        .strikethrough(false)
                    Spacer()
                    if milestone.isReached {
                        StatusCapsule(text: "Reached", systemImage: "checkmark", color: .green)
                    } else if let date = milestone.estimatedDate {
                        Text("Est. \(date.monthYear)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .glassCard()
    }

    private var badgesCard: some View {
        let badges = store.badges
        let earned = badges.filter(\.isEarned).count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Badges")
                    .font(.headline)
                Spacer()
                Text("\(earned) of \(badges.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(badges) { badge in
                        BadgeView(badge: badge)
                    }
                }
            }
        }
        .glassCard()
    }
}

struct BadgeView: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: badge.systemImage)
                .font(.title)
                .foregroundStyle(badge.isEarned ? AnyShapeStyle(badge.color.gradient) : AnyShapeStyle(.tertiary))
                .symbolEffect(.bounce, value: badge.isEarned)
            Text(badge.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(badge.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .glassEffect(badge.isEarned ? .regular.tint(badge.color.opacity(0.25)) : .regular, in: .rect(cornerRadius: 20))
        .opacity(badge.isEarned ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(badge.isEarned ? "Earned" : "Not earned yet")
    }
}

#Preview {
    NavigationStack { DebtProgressView() }
        .environment(DebtStore.preview)
}
