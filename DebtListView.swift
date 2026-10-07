import SwiftUI

struct DebtListView: View {
    @Environment(DebtStore.self) private var store
    @State private var isAddingDebt = false
    @State private var pendingDeletion: Debt?
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            List {
                if !store.debts.isEmpty {
                    Section {
                        summary
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    let focusID = store.focusDebt?.id
                    Section("Active · \(store.openDebts.count)") {
                        ForEach(store.openDebts) { debt in
                            NavigationLink(value: debt.id) {
                                DebtRow(debt: debt, isFocus: debt.id == focusID)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                deleteButton(for: debt)
                            }
                        }
                    }

                    let paidOff = store.debts.filter(\.isPaidOff)
                    if !paidOff.isEmpty {
                        Section("Paid Off · \(paidOff.count)") {
                            ForEach(paidOff) { debt in
                                NavigationLink(value: debt.id) {
                                    DebtRow(debt: debt, isFocus: false)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    deleteButton(for: debt)
                                }
                            }
                        }
                    }
                }
            }
            // The empty state sits over the list rather than in a row, so its button keeps its normal size.
            .overlay {
                if store.debts.isEmpty {
                    ContentUnavailableView {
                        Label("No Debts Yet", systemImage: "creditcard")
                    } description: {
                        Text("Add a credit card, loan, medical bill, or buy now, pay later plan to build your payoff plan.")
                    } actions: {
                        Button("Add Debt", systemImage: "plus") { startAdding() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                }
            }
            .onChange(of: store.addDebtRequested, initial: true) {
                if store.addDebtRequested {
                    store.addDebtRequested = false
                    startAdding()
                }
            }
            .navigationTitle("Debts")
            .navigationDestination(for: UUID.self) { id in
                DebtDetailView(debtID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Debt", systemImage: "plus") { startAdding() }
                        .matchedTransitionSource(id: "add-debt", in: namespace)
                }
            }
            .sheet(isPresented: $isAddingDebt) {
                DebtEditorView(debt: nil) { store.upsert($0) }
                    .zoomTransition(sourceID: "add-debt", in: namespace)
            }
            .confirmationDialog(
                "Delete \(pendingDeletion?.name ?? "debt")?",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { debt in
                Button("Delete Debt", role: .destructive) {
                    withAnimation { store.delete(debt) }
                }
            } message: { debt in
                let count = store.payments(for: debt).count
                Text(count == 0
                     ? "You can undo this for a few seconds."
                     : "This also deletes \(count) logged payment\(count == 1 ? "" : "s"). You can undo this for a few seconds.")
            }
        }
    }

    private func deleteButton(for debt: Debt) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            pendingDeletion = debt
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            pendingDeletion != nil
        } set: { isPresented in
            if !isPresented { pendingDeletion = nil }
        }
    }

    private var summary: some View {
        AdaptiveStack {
            StatTile(title: "Total Balance", value: store.totalBalance.wholeCurrency, systemImage: "sum", tint: .accentColor)
            StatTile(title: "Minimums", value: "\(store.totalMinimums.wholeCurrency)/mo", systemImage: "calendar", tint: .orange)
        }
    }

    private func startAdding() {
        isAddingDebt = true
    }
}

struct DebtRow: View {
    let debt: Debt
    let isFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            KindIcon(kind: debt.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(debt.name.isEmpty ? "Untitled" : debt.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: debt.progress)
                    .tint(debt.kind.color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(debt.balance.currency)
                    .font(.body.weight(.semibold).monospacedDigit())
                status
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let plan = debt.installmentPlan, !debt.isPaidOff {
            let count = plan.installmentsRemaining
            return "\(count) payment\(count == 1 ? "" : "s") of \(plan.installmentAmount.currency) left"
        }
        return "\(debt.apr.aprText) APR · \(debt.minimumPayment.wholeCurrency) min"
    }

    @ViewBuilder
    private var status: some View {
        if debt.isPaidOff {
            StatusCapsule(text: "Paid Off", systemImage: "checkmark", color: .green)
        } else if !debt.minimumCoversInterest {
            StatusCapsule(text: "Min Too Low", systemImage: "exclamationmark.triangle.fill", color: .orange)
        } else if isFocus {
            StatusCapsule(text: "Focus", systemImage: "scope", color: .accentColor)
        } else {
            StatusCapsule(text: "Due \(debt.nextDueDate.formatted(.dateTime.month(.abbreviated).day()))", systemImage: nil, color: .secondary)
        }
    }
}

struct StatusCapsule: View {
    let text: String
    let systemImage: String?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .capsule)
    }
}

#Preview {
    DebtListView()
        .environment(DebtStore.preview)
}
