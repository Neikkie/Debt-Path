import SwiftUI

struct PlanView: View {
    @Environment(DebtStore.self) private var store
    @State private var editingExtra: ExtraPayment?
    @State private var isAddingExtra = false
    @State private var showsFullSchedule = false

    var body: some View {
        @Bindable var store = store
        let plan = store.plan()

        NavigationStack {
            List {
                if store.openDebts.isEmpty {
                    ContentUnavailableView("No Active Debts", systemImage: "list.number", description: Text("Add debts to build a payoff plan."))
                } else {
                    summarySection(plan)
                    extraPaymentsSection
                    if store.strategy == .custom {
                        prioritySection
                    }
                    payoffOrderSection(plan)
                    scheduleSection(plan)
                    Section {
                        EstimateFootnote()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .reorderContainer(for: Debt.self) { difference in
                // Drag-to-reorder in the custom priority list updates the stored debt order,
                // which the custom strategy uses as its priority.
                difference.apply(to: &store.debts)
            }
            .navigationTitle("Payoff Plan")
            .keyboardDoneButton()
            .safeAreaBar(edge: .top) {
                strategyPicker
            }
            .sheet(item: $editingExtra) { extra in
                ExtraPaymentEditor(extra: extra) { store.upsert($0) }
            }
            .sheet(isPresented: $isAddingExtra) {
                ExtraPaymentEditor(extra: nil) { store.upsert($0) }
            }
        }
    }

    private var strategyPicker: some View {
        @Bindable var store = store
        return VStack(spacing: 6) {
            Picker("Strategy", selection: $store.strategy.animation()) {
                ForEach(PayoffStrategy.allCases) { strategy in
                    Label(strategy.title, systemImage: strategy.systemImage).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            Text(store.strategy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Sections

    private func summarySection(_ plan: PayoffPlan) -> some View {
        Section {
            if plan.isComplete {
                LabeledContent("Est. debt-free date", value: plan.monthCount.monthsFromNow)
                LabeledContent("Time to payoff", value: plan.monthCount.durationDescription)
            } else {
                Label("At these payments, your debts won't be paid off within \(PayoffCalculator.maxMonths / 12) years. Try adding an extra monthly payment.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            // Point to the specific debts whose minimums can't keep up with interest.
            ForEach(store.debtsWithLowMinimums) { debt in
                NavigationLink {
                    DebtDetailView(debtID: debt.id)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(debt.name): minimum too low")
                                .font(.subheadline.weight(.semibold))
                            Text("\(debt.minimumPayment.currency) doesn't cover about \(debt.estimatedMonthlyInterest.currency) of monthly interest.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            LabeledContent("Monthly payment", value: (store.totalMinimums + store.extraMonthly).currency)
            LabeledContent("Est. total interest", value: plan.totalInterest.currency)
        } header: {
            Text("Summary")
        }
    }

    private var extraPaymentsSection: some View {
        @Bindable var store = store
        return Section {
            MoneyField(title: "Extra every month", value: optionalExtraMonthly, prompt: "Optional")
            ForEach(store.extraPayments) { extra in
                Button {
                    editingExtra = extra
                } label: {
                    HStack {
                        Image(systemName: extra.frequency == .monthly ? "repeat" : "gift.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(extra.name)
                            Text(extra.frequency == .monthly
                                 ? "Monthly from \(extra.startDate.monthYear)"
                                 : "One time in \(extra.startDate.monthYear)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(extra.amount.currency)
                            .monospacedDigit()
                    }
                }
                .tint(.primary)
            }
            .onDelete { store.extraPayments.remove(atOffsets: $0) }

            Button("Add Recurring or One-Time Payment", systemImage: "plus.circle.fill") {
                isAddingExtra = true
            }
        } header: {
            Text("Extra Payments")
        } footer: {
            Text("Extra money goes to your top-priority debt. When a debt is paid off, its minimum rolls over to the next one.")
        }
    }

    private var prioritySection: some View {
        Section {
            ForEach(store.openDebts) { debt in
                HStack(spacing: 12) {
                    Text("\((store.openDebts.firstIndex { $0.id == debt.id } ?? 0) + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    KindIcon(kind: debt.kind, size: 30)
                    Text(debt.name)
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                // VoiceOver users can reorder with actions instead of dragging.
                .accessibilityElement(children: .combine)
                .accessibilityHint("Use actions to move up or down in priority")
                .accessibilityAction(named: "Move Up") {
                    withAnimation { store.moveInPriority(debt, by: -1) }
                }
                .accessibilityAction(named: "Move Down") {
                    withAnimation { store.moveInPriority(debt, by: 1) }
                }
            }
            .reorderable()
        } header: {
            Text("Your Priority")
        } footer: {
            Text("Touch and hold a debt, then drag to change the order extra money is applied.")
        }
    }

    private func payoffOrderSection(_ plan: PayoffPlan) -> some View {
        Section {
            payoffOrderRows(plan)
        } header: {
            Text("Estimated Payoff Order")
        } footer: {
            if store.strategy != .custom {
                Button("Want a different order? Choose your own", systemImage: "hand.draw") {
                    withAnimation { store.strategy = .custom }
                }
                .font(.footnote)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func payoffOrderRows(_ plan: PayoffPlan) -> some View {
            ForEach(Array(plan.milestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(spacing: 12) {
                    KindIcon(kind: milestone.debt.kind, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(milestone.debt.name)")
                            .font(.headline)
                        Text("\(milestone.interestPaid.currency) est. interest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(milestone.date.monthYear)
                            .font(.subheadline.weight(.semibold))
                        Text("Month \(milestone.month)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }

    private func scheduleSection(_ plan: PayoffPlan) -> some View {
        let visibleMonths = showsFullSchedule ? plan.months : Array(plan.months.prefix(12))

        return Section("Monthly Payment Schedule") {
            ForEach(visibleMonths) { month in
                DisclosureGroup {
                    ForEach(plan.priorityOrder) { debt in
                        if let payment = month.payments[debt.id], payment > 0 {
                            LabeledContent {
                                Text(payment.currency).monospacedDigit()
                            } label: {
                                Label {
                                    Text(debt.name)
                                } icon: {
                                    Circle().fill(debt.kind.color).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                    LabeledContent("Est. interest charged", value: month.interest.currency)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(month.date.monthYear)
                            Text("Pay \(month.totalPayment.currency)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(month.remainingBalance.currency)
                            .font(.body.monospacedDigit())
                    }
                }
            }
            if plan.months.count > 12 {
                Button(showsFullSchedule ? "Show First Year" : "Show All \(plan.months.count) Months") {
                    withAnimation { showsFullSchedule.toggle() }
                }
            }
        }
    }

    /// Shows an empty field instead of "$0.00" when no extra payment is set.
    private var optionalExtraMonthly: Binding<Double?> {
        Binding {
            store.extraMonthly > 0 ? store.extraMonthly : nil
        } set: {
            store.extraMonthly = max(0, $0 ?? 0)
        }
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
}

/// Adds or edits a recurring or one-time extra payment. New payments start with an empty form.
struct ExtraPaymentEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let existing: ExtraPayment?
    @State private var name: String
    @State private var amount: Double?
    @State private var frequency: ExtraPayment.Frequency?
    @State private var startDate: Date
    let onSave: (ExtraPayment) -> Void

    init(extra: ExtraPayment?, onSave: @escaping (ExtraPayment) -> Void) {
        self.existing = extra
        self.onSave = onSave
        _name = State(initialValue: extra?.name ?? "")
        _amount = State(initialValue: extra?.amount)
        _frequency = State(initialValue: extra?.frequency)
        _startDate = State(initialValue: extra?.startDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Side hustle, Tax refund"))
                Picker("Frequency", selection: $frequency) {
                    if frequency == nil {
                        Text("Choose").tag(ExtraPayment.Frequency?.none)
                    }
                    ForEach(ExtraPayment.Frequency.allCases) { frequency in
                        Text(frequency.title).tag(Optional(frequency))
                    }
                }
                MoneyField(title: "Amount", value: $amount)
                DatePicker(frequency == .oneTime ? "Month" : "Starting", selection: $startDate, displayedComponents: .date)
            }
            .navigationTitle("Extra Payment")
            .inlineNavigationTitle()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let extra = madeExtra {
                            onSave(extra)
                            dismiss()
                        }
                    }
                    .disabled(madeExtra == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// The payment built from the form, or nil if a required field is missing.
    private var madeExtra: ExtraPayment? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let amount, amount > 0, let frequency else { return nil }
        return ExtraPayment(id: existing?.id ?? UUID(), name: trimmed, amount: amount, frequency: frequency, startDate: startDate)
    }
}

#Preview {
    PlanView()
        .environment(DebtStore.preview)
}
