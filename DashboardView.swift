import SwiftUI

struct DashboardView: View {
    @Environment(DebtStore.self) private var store
    @Binding var selection: AppTab
    @State private var isConfirmingRestore = false
    @State private var isAddingDebt = false

    private func onAddDebt() { isAddingDebt = true }

    var body: some View {
        let plan = store.plan()

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.debts.isEmpty {
                        emptyState
                    } else {
                        heroCard(plan: plan)
                        statsGrid(plan: plan)
                        if let focus = store.focusDebt {
                            focusCard(focus)
                        }
                        upcomingCard
                        badgesStrip
                        EstimateFootnote()
                    }
                }
                .padding()
            }
            .appBackground(store.strategy.color)
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ReportPreviewView()
                    } label: {
                        Label("Payoff Report", systemImage: "doc.richtext")
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Debt", systemImage: "plus", action: onAddDebt)
                }
            }
            .sheet(isPresented: $isAddingDebt) {
                DebtEditorView(debt: nil) { store.upsert($0) }
            }
        }
    }

    // MARK: - Cards

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Start Your Debt Path", systemImage: "flag.checkered")
        } description: {
            Text("Log your first debt to see an estimated debt-free date and a month-by-month plan.")
        } actions: {
            VStack(spacing: 12) {
                Button("Add Your First Debt", systemImage: "plus", action: onAddDebt)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                if store.hasCloudBackup {
                    Button("Restore from iCloud", systemImage: "icloud.and.arrow.down") {
                        isConfirmingRestore = true
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(.top, 60)
        .confirmationDialog("Restore your iCloud backup?", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
            Button("Restore") { withAnimation { _ = store.restoreFromCloud() } }
        } message: {
            if let date = store.lastCloudBackup {
                Text("Your backup from \(date.formatted(date: .abbreviated, time: .shortened)) will be loaded onto this device.")
            }
        }
    }

    private func heroCard(plan: PayoffPlan) -> some View {
        NavigationLink {
            DebtProgressView()
        } label: {
            heroContent(plan: plan)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your progress charts and badges")
    }

    private func heroContent(plan: PayoffPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Debt")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(store.totalBalance.currency)
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                ZStack {
                    ProgressRing(progress: store.progress, lineWidth: 9, tint: .green)
                    Text(store.progress.percent)
                        .font(.caption.bold())
                        .monospacedDigit()
                }
                .frame(width: 64, height: 64)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(store.progress.percent) paid off")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated debt-free")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = plan.debtFreeDate {
                    Text(date.formatted(.dateTime.month(.wide).year()))
                        .font(.title2.bold())
                    Text("in \(plan.monthCount.durationDescription) with the \(store.strategy.title) strategy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not within 50 years")
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                    Text(store.debtsWithLowMinimums.isEmpty
                         ? "Add an extra monthly payment to get on track."
                         : "Some minimums don't cover their interest. See the Plan tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("View progress & badges")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .glassCard(cornerRadius: 30, tint: store.strategy.color)
    }

    private func statsGrid(plan: PayoffPlan) -> some View {
        VStack(spacing: 12) {
            AdaptiveStack {
                StatTile(title: "Progress", value: store.progress.percent, systemImage: "chart.pie.fill", tint: .green)
                StatTile(title: "Interest Left", value: plan.totalInterest.wholeCurrency, systemImage: "percent", tint: .pink)
            }
            AdaptiveStack {
                StatTile(title: "Monthly", value: (store.totalMinimums + store.extraMonthly).wholeCurrency, systemImage: "calendar", tint: .blue)
                StatTile(title: "Interest Saved", value: max(0, store.minimumOnlyPlan.totalInterest - plan.totalInterest).wholeCurrency, systemImage: "leaf.fill", tint: .teal)
            }
        }
    }

    private func focusCard(_ debt: Debt) -> some View {
        Button {
            selection = .plan
        } label: {
            HStack(spacing: 14) {
                KindIcon(kind: debt.kind, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Focus Debt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(debt.name)
                        .font(.headline)
                    Text(store.extraMonthly > 0
                         ? "Send your extra \(store.extraMonthly.wholeCurrency) here each month"
                         : "Add an extra payment in Plan to pay this off sooner")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(debt.balance.wholeCurrency)
                        .font(.headline.monospacedDigit())
                    Text(debt.apr.aprText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var upcomingCard: some View {
        let upcoming = store.openDebts.sorted { $0.nextDueDate < $1.nextDueDate }.prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Payments")
                    .font(.headline)
                Spacer()
                if !store.remindersEnabled {
                    Button("Remind Me", systemImage: "bell") { selection = .settings }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            ForEach(upcoming) { debt in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(debt.nextDueDate, format: .dateTime.month(.abbreviated))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(debt.kind.color)
                        Text(debt.nextDueDate, format: .dateTime.day())
                            .font(.title3.bold())
                    }
                    .frame(width: 40)
                    Text(debt.name)
                    Spacer()
                    Text(debt.minimumPayment.currency)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private var badgesStrip: some View {
        let earned = store.badges.filter(\.isEarned)

        return NavigationLink {
            DebtProgressView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Progress & Badges", systemImage: "chart.line.downtrend.xyaxis")
                        .font(.headline)
                    Spacer()
                    Text("\(earned.count) earned")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if earned.isEmpty {
                    Text("Log your first payment to earn a badge.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(earned.prefix(5)) { badge in
                            Image(systemName: badge.systemImage)
                                .font(.title3)
                                .foregroundStyle(badge.color.gradient)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.tint(badge.color.opacity(0.2)), in: .circle)
                                .accessibilityLabel(badge.title)
                        }
                    }
                }
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DashboardView(selection: .constant(.dashboard))
        .environment(DebtStore.preview)
}
