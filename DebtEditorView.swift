import SwiftUI

/// Form values for adding or editing a debt. Every field starts empty for a new debt.
private struct DebtDraft {
    var name = ""
    var kind: DebtKind?
    var balance: Double?
    var apr: Double?
    var minimumPayment: Double?
    var dueDay: Int?
    // Buy now, pay later
    var installmentAmount: Double?
    var installmentsRemaining: Int?
    var installmentFrequency: InstallmentPlan.Frequency?

    init() {}

    init(_ debt: Debt) {
        name = debt.name
        kind = debt.kind
        balance = debt.balance
        apr = debt.apr
        minimumPayment = debt.minimumPayment
        dueDay = debt.dueDay
        installmentAmount = debt.installmentPlan?.installmentAmount
        installmentsRemaining = debt.installmentPlan?.installmentsRemaining
        installmentFrequency = debt.installmentPlan?.frequency
    }

    var isInstallmentPlan: Bool { kind == .buyNowPayLater }

    var installmentPlan: InstallmentPlan? {
        guard let installmentAmount, installmentAmount > 0,
              let installmentsRemaining, installmentsRemaining > 0,
              let installmentFrequency else { return nil }
        return InstallmentPlan(installmentAmount: installmentAmount, installmentsRemaining: installmentsRemaining, frequency: installmentFrequency)
    }

    /// Balance and monthly payment, derived from installments for buy now, pay later.
    var resolvedBalance: Double? { isInstallmentPlan ? installmentPlan?.remainingBalance : balance }
    var resolvedMinimum: Double? { isInstallmentPlan ? installmentPlan?.estimatedMonthlyPayment : minimumPayment }

    /// The estimated monthly interest when the entered minimum doesn't cover it, otherwise nil.
    var uncoveredMonthlyInterest: Double? {
        guard let balance = resolvedBalance, balance > 0,
              let apr, apr > 0,
              let minimum = resolvedMinimum else { return nil }
        let interest = (balance * apr / 100 / 12).roundedToCents
        return minimum <= interest ? interest : nil
    }

    /// Builds a debt from the form, or nil if a required field is missing.
    func makeDebt(updating existing: Debt?) -> Debt? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let kind,
              let balance = resolvedBalance, balance > 0,
              let apr, apr >= 0,
              let minimum = resolvedMinimum, minimum > 0,
              let dueDay else { return nil }

        return Debt(
            id: existing?.id ?? UUID(),
            name: trimmedName,
            kind: kind,
            balance: balance,
            originalBalance: existing.map { max($0.originalBalance, balance) },
            apr: apr,
            minimumPayment: minimum,
            dueDay: dueDay,
            installmentPlan: isInstallmentPlan ? installmentPlan : nil
        )
    }
}

/// The Add / Edit Debt form.
struct DebtEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DebtDraft
    private let existing: Debt?
    let onSave: (Debt) -> Void

    /// Pass `nil` to add a new debt with an empty form.
    init(debt: Debt?, onSave: @escaping (Debt) -> Void) {
        self.existing = debt
        self.onSave = onSave
        if let debt {
            _draft = State(initialValue: DebtDraft(debt))
        } else {
            _draft = State(initialValue: DebtDraft())
        }
    }

    private var isNew: Bool { existing == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Debt name", text: $draft.name, prompt: Text(namePrompt))
                    Picker("Type", selection: $draft.kind) {
                        if draft.kind == nil {
                            Text("Choose a type").tag(DebtKind?.none)
                        }
                        ForEach(DebtKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(Optional(kind))
                        }
                    }
                } header: {
                    HStack {
                        Spacer()
                        headerIcon
                            .padding(.bottom, 8)
                        Spacer()
                    }
                }

                if draft.isInstallmentPlan {
                    installmentSection
                } else {
                    Section("Balance & Payment") {
                        MoneyField(title: "Current balance", value: $draft.balance)
                        MoneyField(title: "Minimum payment", value: $draft.minimumPayment)
                    }
                }

                Section {
                    LabeledContent("Interest rate (APR %)") {
                        TextField("Required", value: $draft.apr, format: .number.precision(.fractionLength(0...2)))
                            .decimalKeyboard()
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Due date", selection: $draft.dueDay) {
                        if draft.dueDay == nil {
                            Text("Choose a day").tag(Int?.none)
                        }
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day.ordinal) of the month").tag(Optional(day))
                        }
                    }
                } header: {
                    Text("Terms")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if draft.isInstallmentPlan {
                            Text("Many pay-in-4 plans charge 0% APR. Check your plan's terms. Enter 0 if there's no interest.")
                        } else {
                            Text("Enter 0 for interest-free debts, such as many medical bills.")
                        }
                        if let dueDay = draft.dueDay, dueDay > 28 {
                            Text("In shorter months, the due date is the last day of the month.")
                        }
                    }
                }

                if let interest = draft.uncoveredMonthlyInterest {
                    Section {
                        Label {
                            Text("This minimum doesn't cover the estimated \(interest.currency) of interest charged each month, so the balance would keep growing. Check the amount, or plan to pay more.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.subheadline)
                    }
                }

                if let existing {
                    Section {
                        LabeledContent("Starting balance", value: existing.originalBalance.currency)
                    } footer: {
                        Text("Progress is measured from the starting balance. Log payments from the debt's detail screen to track progress.")
                    }
                }
            }
            .navigationTitle(isNew ? "Add Debt" : "Edit Debt")
            .inlineNavigationTitle()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let debt = draft.makeDebt(updating: existing) {
                            onSave(debt)
                            dismiss()
                        }
                    }
                    .disabled(draft.makeDebt(updating: existing) == nil)
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerIcon: some View {
        if let kind = draft.kind {
            KindIcon(kind: kind, size: 64)
        } else {
            Image(systemName: "questionmark")
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .glassEffect(.regular, in: .rect(cornerRadius: 19))
        }
    }

    private var installmentSection: some View {
        Section {
            MoneyField(title: "Installment amount", value: $draft.installmentAmount)
            LabeledContent("Payments left") {
                TextField("Required", value: $draft.installmentsRemaining, format: .number)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
            }
            Picker("Frequency", selection: $draft.installmentFrequency) {
                if draft.installmentFrequency == nil {
                    Text("Choose").tag(InstallmentPlan.Frequency?.none)
                }
                ForEach(InstallmentPlan.Frequency.allCases) { frequency in
                    Text(frequency.title).tag(Optional(frequency))
                }
            }
            if let plan = draft.installmentPlan {
                LabeledContent("Remaining balance", value: plan.remainingBalance.currency)
                LabeledContent("Est. monthly payment", value: plan.estimatedMonthlyPayment.currency)
            }
        } header: {
            Text("Installments")
        } footer: {
            Text("The balance and an estimated monthly payment are calculated from your installments. Late fees aren't included.")
        }
    }

    private var namePrompt: String {
        switch draft.kind {
        case .creditCard: "e.g. Visa Card"
        case .studentLoan: "e.g. Federal Student Loan"
        case .personalLoan: "e.g. Bank Loan"
        case .medical: "e.g. Hospital Bill"
        case .buyNowPayLater: "e.g. Klarna – Laptop"
        case .auto: "e.g. Car Loan"
        case .other, nil: "Debt name"
        }
    }
}

#Preview("Add") {
    DebtEditorView(debt: nil) { _ in }
}
