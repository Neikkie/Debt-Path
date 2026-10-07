import SwiftUI

/// Records a manual payment against a debt, or edits one that was already logged.
struct LogPaymentView: View {
    @Environment(DebtStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The payment being edited, or nil when logging a new one.
    private let existing: PaymentRecord?
    @State private var debtID: UUID?
    @State private var amount: Double?
    @State private var date: Date
    @State private var note: String

    /// Logs a new payment. Pass a debt ID to preselect it (for example, from a debt's detail screen).
    init(preselectedDebtID: UUID?) {
        existing = nil
        _debtID = State(initialValue: preselectedDebtID)
        _amount = State(initialValue: nil)
        _date = State(initialValue: .now)
        _note = State(initialValue: "")
    }

    /// Edits a payment that was already logged.
    init(editing payment: PaymentRecord) {
        existing = payment
        _debtID = State(initialValue: payment.debtID)
        _amount = State(initialValue: payment.amount)
        _date = State(initialValue: payment.date)
        _note = State(initialValue: payment.note)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing && store.openDebts.isEmpty {
                    ContentUnavailableView("Nothing to Pay", systemImage: "checkmark.seal", description: Text("All of your debts are paid off."))
                } else {
                    Section {
                        if isEditing, let selected {
                            LabeledContent("Debt") {
                                Label(selected.name, systemImage: selected.kind.systemImage)
                            }
                        } else {
                            Picker("Debt", selection: $debtID) {
                                if debtID == nil {
                                    Text("Choose a debt").tag(UUID?.none)
                                }
                                ForEach(store.openDebts) { debt in
                                    Label(debt.name, systemImage: debt.kind.systemImage).tag(Optional(debt.id))
                                }
                            }
                        }
                        if let selected {
                            LabeledContent(isEditing ? "Balance before this payment" : "Balance", value: maximumAmount(for: selected).currency)
                        }
                    }

                    Section {
                        MoneyField(title: "Amount", value: $amount)
                            .font(.title3.weight(.semibold))
                        if let selected {
                            quickAmounts(for: selected)
                        }
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        TextField("Note (optional)", text: $note)
                    } footer: {
                        if let selected, let amount, amount > maximumAmount(for: selected) {
                            Text("Amount is more than the balance. Only \(maximumAmount(for: selected).currency) will be applied.")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Payment" : "Log Payment")
            .inlineNavigationTitle()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(selected == nil || (amount ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selected: Debt? {
        debtID.flatMap(store.debt(withID:))
    }

    /// The most that can be applied: the current balance, plus this payment's amount when editing.
    private func maximumAmount(for debt: Debt) -> Double {
        (debt.balance + (existing?.amount ?? 0)).roundedToCents
    }

    private func quickAmounts(for debt: Debt) -> some View {
        let maximum = maximumAmount(for: debt)
        let options: [(String, Double)] = [
            ("Minimum", min(debt.minimumPayment, maximum)),
            ("Pay Off", maximum),
        ]
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    Button(option.0) { amount = option.1 }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }

    private func save() {
        guard let debtID, let amount else { return }
        if let existing {
            store.updatePayment(PaymentRecord(id: existing.id, debtID: debtID, amount: amount, date: date, note: note))
        } else {
            store.recordPayment(PaymentRecord(debtID: debtID, amount: amount, date: date, note: note))
        }
        dismiss()
    }
}

#Preview {
    LogPaymentView(preselectedDebtID: nil)
        .environment(DebtStore.preview)
}
