import SwiftUI

struct DebtDetailView: View {
    @Environment(DebtStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID

    @State private var isEditing = false
    @State private var isLoggingPayment = false
    @State private var isConfirmingDelete = false
    @State private var editingPayment: PaymentRecord?

    var body: some View {
        if let debt = store.debt(withID: debtID) {
            content(for: debt)
        } else {
            ContentUnavailableView("Debt Removed", systemImage: "trash")
        }
    }

    private func content(for debt: Debt) -> some View {
        let plan = store.plan()
        let milestone = plan.milestones.first { $0.debt.id == debt.id }
        let history = store.payments(for: debt)

        return List {
            Section {
                header(for: debt)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Details") {
                LabeledContent("Type", value: debt.kind.title)
                LabeledContent("Interest rate", value: "\(debt.apr.aprText) APR")
                if let plan = debt.installmentPlan {
                    LabeledContent("Installments", value: "\(plan.installmentsRemaining) × \(plan.installmentAmount.currency)")
                    LabeledContent("Frequency", value: plan.frequency.title)
                    LabeledContent("Est. monthly payment", value: debt.minimumPayment.currency)
                } else {
                    LabeledContent("Minimum payment", value: debt.minimumPayment.currency)
                }
                LabeledContent("Due date", value: debt.dueDay > 28
                               ? "\(debt.dueDay.ordinal) (or last day of the month)"
                               : "\(debt.dueDay.ordinal) of each month")
                LabeledContent("Starting balance", value: debt.originalBalance.currency)
            }

            if !debt.minimumCoversInterest && !debt.isPaidOff {
                Section {
                    Label {
                        Text("The minimum payment doesn't cover the estimated \(debt.estimatedMonthlyInterest.currency) of monthly interest, so this balance would keep growing. Check the amount with your lender, or add extra payments in Plan.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Edit Minimum Payment", systemImage: "pencil") { isEditing = true }
                }
            }

            if !debt.isPaidOff {
                Section {
                    if let milestone {
                        LabeledContent("Est. payoff", value: milestone.date.monthYear)
                        LabeledContent("Est. interest remaining", value: milestone.interestPaid.currency)
                    } else {
                        Label("Not paid off within \(PayoffCalculator.maxMonths / 12) years at current payments.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if let position = plan.priorityOrder.firstIndex(where: { $0.id == debt.id }) {
                        LabeledContent("Priority", value: "#\(position + 1) in \(store.strategy.title)")
                    }
                } header: {
                    Text("Projection")
                } footer: {
                    Text("Estimated using your \(store.strategy.title.lowercased()) plan. Actual results may vary.")
                }
            }

            Section {
                if history.isEmpty {
                    Text("No payments logged yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(history) { payment in
                    Button {
                        editingPayment = payment
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(payment.date, format: .dateTime.month(.abbreviated).day().year())
                                if !payment.note.isEmpty {
                                    Text(payment.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(payment.amount.currency)
                                .monospacedDigit()
                                .foregroundStyle(.green)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityHint("Edit this payment")
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            withAnimation { store.deletePayment(payment) }
                        }
                    }
                }
            } header: {
                Text("Payment History")
            } footer: {
                if !history.isEmpty {
                    Text("Tap a payment to edit it. Swipe left to delete.")
                }
            }
        }
        .navigationTitle(debt.name)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Edit Debt", systemImage: "pencil") { isEditing = true }
                    Button("Delete Debt", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            DebtEditorView(debt: debt) { store.upsert($0) }
        }
        .sheet(isPresented: $isLoggingPayment) {
            LogPaymentView(preselectedDebtID: debt.id)
        }
        .sheet(item: $editingPayment) { payment in
            LogPaymentView(editing: payment)
        }
        .confirmationDialog("Delete \(debt.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Debt", role: .destructive) {
                dismiss()
                store.delete(debt)
            }
        } message: {
            Text(history.isEmpty
                 ? "You can undo this for a few seconds."
                 : "This also deletes \(history.count) logged payment\(history.count == 1 ? "" : "s"). You can undo this for a few seconds.")
        }
    }

    private func header(for debt: Debt) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: debt.progress, lineWidth: 10, tint: debt.kind.color)
                    KindIcon(kind: debt.kind, size: 44)
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(debt.balance.currency)
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(debt.progress.percent) paid off")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(debt.kind.color)
                }
                Spacer(minLength: 0)
            }

            if !debt.isPaidOff {
                Button {
                    isLoggingPayment = true
                } label: {
                    Label("Log Payment", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(debt.kind.color)
            }
        }
        .glassCard(tint: debt.kind.color)
    }
}

#Preview {
    NavigationStack {
        DebtDetailView(debtID: UUID())
    }
    .environment(DebtStore.preview)
}
