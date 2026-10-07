import SwiftUI

enum AppTab: Hashable {
    case dashboard, debts, plan, simulator, settings
}

struct ContentView: View {
    @Environment(DebtStore.self) private var store
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: AppTab = .dashboard
    @State private var isLoggingPayment = false
    /// Set when the user chooses "Add Your First Debt" so the form opens after the welcome screen closes.
    @State private var addsDebtAfterWelcome = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: .dashboard) {
                DashboardView(selection: $selection)
            }
            Tab("Debts", systemImage: "creditcard", value: .debts) {
                DebtListView()
            }
            Tab("Plan", systemImage: "list.number", value: .plan) {
                PlanView()
            }
            Tab("Simulator", systemImage: "slider.horizontal.3", value: .simulator) {
                SimulatorView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .phoneTabBarEnhancements(
            showsAccessory: !store.openDebts.isEmpty,
            debtFreeText: store.plan().debtFreeDate?.monthYear ?? "50+ yrs"
        ) {
            isLoggingPayment = true
        }
        .sheet(isPresented: $isLoggingPayment) {
            LogPaymentView(preselectedDebtID: nil)
        }
        .welcomePresentation(isPresented: showsWelcome) {
            // Only after the welcome screen has fully closed, ask the Debts screen to open
            // its own Add Debt form. Presenting from here while the cover dismisses is unreliable.
            if addsDebtAfterWelcome {
                addsDebtAfterWelcome = false
                store.addDebtRequested = true
            }
        } content: {
            WelcomeView {
                addsDebtAfterWelcome = true
                selection = .debts
                hasCompletedOnboarding = true
            } onExplore: {
                hasCompletedOnboarding = true
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = store.pendingUndo {
                UndoBanner(undo: undo) {
                    withAnimation(.snappy) { store.undoLastDeletion() }
                } onExpire: {
                    withAnimation(.snappy) {
                        if store.pendingUndo?.id == undo.id { store.pendingUndo = nil }
                    }
                }
                // Sit above the tab bar and its accessory.
                .padding(.bottom, store.openDebts.isEmpty ? 96 : 140)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let debt = store.celebratedDebt {
                CelebrationView(debt: debt, remainingCount: store.openDebts.count) {
                    withAnimation { store.celebratedDebt = nil }
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: store.pendingUndo?.id)
        .animation(.easeInOut, value: store.celebratedDebt?.id)
        .onChange(of: store.widgetSnapshot, initial: true) { _, snapshot in
            WidgetSync.publish(snapshot)
        }
        .task(id: store.reminderSignature) {
            await ReminderScheduler.reschedule(
                debts: store.debts,
                enabled: store.remindersEnabled,
                daysBefore: store.reminderDaysBefore
            )
        }
    }

    private var showsWelcome: Binding<Bool> {
        Binding {
            !hasCompletedOnboarding
        } set: { isPresented in
            if !isPresented { hasCompletedOnboarding = true }
        }
    }
}

private extension View {
    /// On iPhone and iPad: a minimizing Liquid Glass tab bar with a quick "Log Payment" accessory.
    @ViewBuilder
    func phoneTabBarEnhancements(showsAccessory: Bool, debtFreeText: String, onLogPayment: @escaping () -> Void) -> some View {
        #if os(iOS)
        self
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: showsAccessory) {
                PaymentAccessory(debtFreeText: debtFreeText, onLogPayment: onLogPayment)
            }
        #else
        self
        #endif
    }

    /// Full-screen on iPhone and iPad; a non-dismissible sheet elsewhere.
    @ViewBuilder
    func welcomePresentation(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().interactiveDismissDisabled()
        }
        #endif
    }
}

#if os(iOS)
/// The bottom accessory above the tab bar. Shows a compact version when the tab bar minimizes.
private struct PaymentAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let debtFreeText: String
    let onLogPayment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.tint)
            if placement == .inline {
                Text(debtFreeText)
                    .font(.subheadline.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Est. debt-free")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(debtFreeText)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Spacer()
            Button(action: onLogPayment) {
                if placement == .inline {
                    Image(systemName: "plus.circle.fill")
                } else {
                    Label("Log Payment", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .accessibilityLabel("Log Payment")
        }
        .padding(.horizontal, 16)
    }
}
#endif

#Preview {
    ContentView()
        .environment(DebtStore.preview)
}
