import SwiftUI
import Charts

/// Variables the user can adjust in the what-if simulator.
struct WhatIfSettings: Equatable {
    /// Nil means "use the extra monthly payment from the plan".
    var extraMonthly: Double?
    var oneTimePayment: Double = 0
    var aprAdjustment: Double = 0
    var startDelayMonths: Double = 0

    var isDefault: Bool { self == WhatIfSettings() }
}

struct SimulatorView: View {
    @Environment(DebtStore.self) private var store
    @State private var settings = WhatIfSettings()

    var body: some View {
        let baseline = store.plan()
        let whatIf = PayoffCalculator.makePlan(scenario(for: store.strategy))
        let strategyPlans = PayoffStrategy.allCases.map { PayoffCalculator.makePlan(scenario(for: $0)) }
        let minimumOnly = PayoffCalculator.makePlan(minimumOnlyScenario)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.openDebts.isEmpty {
                        ContentUnavailableView("Nothing to Simulate", systemImage: "slider.horizontal.3", description: Text("Add a debt to try what-if scenarios."))
                    } else {
                        slidersCard
                        resultsCard(baseline: baseline, whatIf: whatIf)
                        chartCard(baseline: baseline, whatIf: whatIf)
                        compareCard(plans: strategyPlans, minimumOnly: minimumOnly)
                        EstimateFootnote()
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .appBackground(.indigo)
            .navigationTitle("Simulator")
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        withAnimation(.snappy) { settings = WhatIfSettings() }
                    }
                    .disabled(settings.isDefault)
                }
            }
        }
    }

    // MARK: - Scenarios

    private func scenario(for strategy: PayoffStrategy) -> PlanScenario {
        var scenario = store.scenario(for: strategy)
        scenario.extraMonthly = settings.extraMonthly ?? store.extraMonthly
        scenario.oneTimePayment = settings.oneTimePayment
        scenario.aprAdjustment = settings.aprAdjustment
        scenario.startDelayMonths = Int(settings.startDelayMonths)
        return scenario
    }

    private var minimumOnlyScenario: PlanScenario {
        var scenario = store.scenario(for: .avalanche)
        scenario.extraMonthly = 0
        scenario.extraPayments = []
        scenario.aprAdjustment = settings.aprAdjustment
        scenario.rollsOverPayments = false
        return scenario
    }

    // MARK: - Sliders

    private var slidersCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("What If…", systemImage: "wand.and.stars")
                .font(.title3.bold())

            SliderRow(
                title: "Extra monthly payment",
                value: extraBinding,
                range: 0...max(2_000, (store.extraMonthly * 3).rounded()),
                step: 25,
                systemImage: "plus.circle",
                tint: .green,
                valueText: "\((settings.extraMonthly ?? store.extraMonthly).wholeCurrency)/mo",
                allowsTyping: true
            )
            SliderRow(
                title: "One-time payment",
                value: $settings.oneTimePayment,
                range: 0...min(max(1_000, store.totalBalance), 50_000),
                step: 100,
                systemImage: "gift",
                tint: .orange,
                valueText: settings.oneTimePayment.wholeCurrency,
                allowsTyping: true
            )
            SliderRow(
                title: "Interest rate change",
                value: $settings.aprAdjustment,
                range: -10...10,
                step: 0.5,
                systemImage: "percent",
                tint: .pink,
                valueText: aprText
            )
            SliderRow(
                title: "Plan start date",
                value: $settings.startDelayMonths,
                range: 0...24,
                step: 1,
                systemImage: "calendar",
                tint: .blue,
                valueText: settings.startDelayMonths == 0
                    ? "Next month"
                    : (Int(settings.startDelayMonths) + 1).monthsFromNow
            )

            Text("Drag a slider or tap an amount to type it. Before the plan starts, only minimum payments are made. Rate changes apply to every debt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var extraBinding: Binding<Double> {
        Binding {
            settings.extraMonthly ?? store.extraMonthly
        } set: {
            settings.extraMonthly = $0
        }
    }

    private var aprText: String {
        if settings.aprAdjustment == 0 { return "No change" }
        let sign = settings.aprAdjustment > 0 ? "+" : ""
        return "\(sign)\(settings.aprAdjustment.formatted(.number.precision(.fractionLength(0...1)))) pts"
    }

    // MARK: - Results

    private func resultsCard(baseline: PayoffPlan, whatIf: PayoffPlan) -> some View {
        let monthsDifference = baseline.monthCount - whatIf.monthCount
        let interestDifference = baseline.totalInterest - whatIf.totalInterest

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Estimated Result")
                    .font(.headline)
                Spacer()
                StatusCapsule(text: store.strategy.title, systemImage: store.strategy.systemImage, color: store.strategy.color)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    Text("Your Plan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("What-If").font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                }
                GridRow {
                    Text("Debt-free").foregroundStyle(.secondary)
                    Text(baseline.debtFreeDate?.monthYear ?? "50+ yrs")
                    Text(whatIf.debtFreeDate?.monthYear ?? "50+ yrs").bold()
                }
                GridRow {
                    Text("Interest").foregroundStyle(.secondary)
                    Text(baseline.totalInterest.wholeCurrency)
                    Text(whatIf.totalInterest.wholeCurrency).bold()
                }
                GridRow {
                    Text("Total paid").foregroundStyle(.secondary)
                    Text(baseline.totalPaid.wholeCurrency)
                    Text(whatIf.totalPaid.wholeCurrency).bold()
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .contentTransition(.numericText())

            if !settings.isDefault {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        DeltaChip(
                            value: monthsDifference == 0 ? "Same time" : abs(monthsDifference).durationDescription,
                            caption: monthsDifference >= 0 ? "sooner" : "later",
                            isGood: monthsDifference >= 0
                        )
                        DeltaChip(
                            value: abs(interestDifference).wholeCurrency,
                            caption: interestDifference >= 0 ? "less interest" : "more interest",
                            isGood: interestDifference >= 0
                        )
                    }
                }
                .transition(.blurReplace)
            }
        }
        .glassCard()
        .animation(.snappy, value: settings)
    }

    private func chartCard(baseline: PayoffPlan, whatIf: PayoffPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remaining Balance")
                .font(.headline)
            BalanceComparisonChart(series: [
                ("Your Plan", baseline, Color.secondary),
                ("What-If", whatIf, Color.indigo),
            ])
            .frame(height: 220)
        }
        .glassCard()
    }

    // MARK: - Strategy comparison

    private func compareCard(plans: [PayoffPlan], minimumOnly: PayoffPlan) -> some View {
        let lowestInterest = plans.map(\.totalInterest).min() ?? 0
        let fastest = plans.map(\.monthCount).min() ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            Text("Compare Strategies")
                .font(.headline)
            Text("Each plan uses the what-if settings above.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plans, id: \.strategy) { plan in
                StrategyComparisonRow(
                    title: plan.strategy.title,
                    systemImage: plan.strategy.systemImage,
                    color: plan.strategy.color,
                    plan: plan,
                    tags: tags(for: plan, lowestInterest: lowestInterest, fastest: fastest),
                    isSelected: plan.strategy == store.strategy
                ) {
                    withAnimation { store.strategy = plan.strategy }
                }
            }

            Divider()

            StrategyComparisonRow(
                title: "Minimums Only",
                systemImage: "tortoise.fill",
                color: .gray,
                plan: minimumOnly,
                tags: [],
                isSelected: false,
                onSelect: nil
            )

            if let best = plans.min(by: { $0.totalInterest < $1.totalInterest }), minimumOnly.totalInterest > best.totalInterest {
                Label("Est. \((minimumOnly.totalInterest - best.totalInterest).wholeCurrency) less interest than paying only minimums.", systemImage: "leaf.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .glassCard()
    }

    private func tags(for plan: PayoffPlan, lowestInterest: Double, fastest: Int) -> [String] {
        var tags: [String] = []
        if plan.totalInterest.roundedToCents <= lowestInterest.roundedToCents { tags.append("Lowest interest") }
        if plan.monthCount <= fastest { tags.append("Fastest") }
        if let first = plan.milestones.first { tags.append("1st payoff \(first.date.monthYear)") }
        return tags
    }
}

// MARK: - Components

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let systemImage: String
    let tint: Color
    let valueText: String
    /// When true, shows a field for typing an exact dollar amount instead of a static value.
    var allowsTyping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if allowsTyping {
                    HStack(spacing: 2) {
                        Text(Locale.current.currencySymbol ?? "$")
                            .foregroundStyle(.secondary)
                        TextField(title, value: typedValue, format: .number.precision(.fractionLength(0...2)), prompt: Text("0"))
                            .decimalKeyboard()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Text(valueText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                }
            }
            // Widen the slider if someone types a value beyond its default range.
            Slider(value: $value, in: range.lowerBound...max(range.upperBound, value), step: step)
                .tint(tint)
                .accessibilityValue(valueText)
        }
    }

    private var typedValue: Binding<Double?> {
        Binding {
            value
        } set: { newValue in
            value = max(range.lowerBound, newValue ?? 0)
        }
    }
}

private struct DeltaChip: View {
    let value: String
    let caption: String
    let isGood: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint((isGood ? Color.green : Color.red).opacity(0.25)), in: .rect(cornerRadius: 16))
    }
}

private struct StrategyComparisonRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let plan: PayoffPlan
    let tags: [String]
    let isSelected: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color.gradient, in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text("\(plan.debtFreeDate?.monthYear ?? "50+ yrs") · \(plan.totalInterest.wholeCurrency) interest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            StatusCapsule(text: tag, systemImage: nil, color: color)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let onSelect {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(color)
                        .accessibilityLabel("Current strategy")
                } else {
                    Button("Use") { onSelect() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Line chart comparing remaining balance over time for several plans.
struct BalanceComparisonChart: View {
    private struct Point: Identifiable {
        let series: String
        let date: Date
        let balance: Double
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    let series: [(name: String, plan: PayoffPlan, color: Color)]

    private var points: [Point] {
        series.flatMap { entry in
            [Point(series: entry.name, date: PlanCalendar.currentMonthStart, balance: entry.plan.startingBalance)]
                + entry.plan.months.map { Point(series: entry.name, date: $0.date, balance: $0.remainingBalance) }
        }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Balance", point.balance)
            )
            .foregroundStyle(by: .value("Plan", point.series))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
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
        .chartLegend(position: .top, alignment: .leading)
    }
}

#Preview {
    SimulatorView()
        .environment(DebtStore.preview)
}
