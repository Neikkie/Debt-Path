import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The Settings tab: plan preferences, reminders, report export, and data.
struct SettingsView: View {
    @Environment(DebtStore.self) private var store
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var permissionDenied = false
    @State private var isConfirmingErase = false
    @State private var isConfirmingRestore = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    Picker("Strategy", systemImage: store.strategy.systemImage, selection: $store.strategy) {
                        ForEach(PayoffStrategy.allCases) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    MoneyField(title: "Extra each month", value: optionalExtraMonthly, prompt: "Optional")
                } header: {
                    Text("Payoff Plan")
                } footer: {
                    Text(store.strategy.summary)
                }

                Section {
                    Toggle("Payment Reminders", systemImage: "bell.badge.fill", isOn: remindersBinding)
                    if store.remindersEnabled {
                        Picker("Remind Me", systemImage: "clock", selection: $store.reminderDaysBefore) {
                            Text("On the due date").tag(0)
                            ForEach([1, 2, 3, 5, 7], id: \.self) { days in
                                Text("\(days) day\(days == 1 ? "" : "s") before").tag(days)
                            }
                        }
                    }
                    if permissionDenied {
                        Label("Notifications are turned off for Debt Path.", systemImage: "bell.slash.fill")
                            .foregroundStyle(.orange)
                        #if os(iOS)
                        Button("Open Settings", systemImage: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        #endif
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    if permissionDenied {
                        Text("Turn on notifications for Debt Path in the Settings app, then come back to turn on reminders.")
                    } else {
                        Text("Get a monthly notification at 9 AM before each debt's due date. For due dates after the 28th, reminders come on the 28th so they arrive every month.")
                    }
                }

                Section {
                    Toggle("Back Up to iCloud", systemImage: "icloud.fill", isOn: $store.iCloudBackupEnabled)
                    if let date = store.lastCloudBackup {
                        LabeledContent("Last backup", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if store.hasCloudBackup {
                        Button("Restore from iCloud", systemImage: "icloud.and.arrow.down") {
                            isConfirmingRestore = true
                        }
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Keeps a copy of your debts and payments in your iCloud account, so you can restore them after deleting the app or on a new iPhone.")
                }

                if store.remindersEnabled && !store.openDebts.isEmpty {
                    Section("Upcoming Due Dates") {
                        ForEach(store.openDebts.sorted { $0.nextDueDate < $1.nextDueDate }) { debt in
                            LabeledContent {
                                Text(debt.nextDueDate, format: .dateTime.month(.abbreviated).day())
                            } label: {
                                Label {
                                    Text(debt.name)
                                } icon: {
                                    KindIcon(kind: debt.kind, size: 28)
                                }
                            }
                        }
                    }
                }

                Section("Report") {
                    NavigationLink {
                        ReportPreviewView()
                    } label: {
                        Label("Export Payoff Report (PDF)", systemImage: "doc.richtext")
                    }
                    .disabled(store.debts.isEmpty)
                }

                Section {
                    Button("Show Welcome Screen", systemImage: "hand.wave") {
                        hasCompletedOnboarding = false
                    }
                    Button("Delete All Data", systemImage: "trash", role: .destructive) {
                        isConfirmingErase = true
                    }
                    .disabled(store.debts.isEmpty && store.payments.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text(store.iCloudBackupEnabled
                         ? "Your data is stored on this device and backed up to your iCloud account."
                         : "Your data is stored only on this device. Turn on iCloud backup to keep a copy.")
                }

                Section("About") {
                    NavigationLink {
                        AssumptionsView()
                    } label: {
                        Label("Assumptions & Estimates", systemImage: "info.circle")
                    }
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        Label("Version", systemImage: "number")
                    }
                }
            }
            .navigationTitle("Settings")
            .keyboardDoneButton()
            .confirmationDialog("Delete all data?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
                Button("Delete All Data", role: .destructive) {
                    store.eraseAllData()
                }
            } message: {
                Text(store.iCloudBackupEnabled
                     ? "This removes every debt, payment, and extra payment from this device and your iCloud backup. This can't be undone."
                     : "This permanently removes every debt, payment, and extra payment. This can't be undone.")
            }
            .confirmationDialog("Restore your iCloud backup?", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
                Button("Replace Data on This iPhone", role: .destructive) {
                    store.restoreFromCloud()
                }
            } message: {
                Text("The debts and payments on this device will be replaced with your backup\(store.lastCloudBackup.map { " from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "").")
            }
            .task {
                // Reflect the current notification permission, even if it changed in the Settings app.
                permissionDenied = await ReminderScheduler.isDenied()
                if permissionDenied && store.remindersEnabled {
                    store.remindersEnabled = false
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

    /// Requests notification permission when reminders are turned on.
    private var remindersBinding: Binding<Bool> {
        Binding {
            store.remindersEnabled
        } set: { isOn in
            guard isOn else {
                store.remindersEnabled = false
                return
            }
            Task {
                let granted = await ReminderScheduler.requestAuthorization()
                permissionDenied = !granted
                store.remindersEnabled = granted
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview {
    SettingsView()
        .environment(DebtStore.preview)
}
