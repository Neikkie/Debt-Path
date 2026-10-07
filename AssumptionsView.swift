import SwiftUI

/// Explains how estimates are calculated and their limitations.
struct AssumptionsView: View {
    var body: some View {
        List {
            Section {
                Label {
                    Text("Debt Path is a planning tool, not financial advice. All dates, interest totals, and savings are estimates based on the information you enter.")
                } icon: {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
            }

            Section("How Estimates Are Calculated") {
                ForEach(Self.assumptions, id: \.title) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage).foregroundStyle(.tint)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Why Actual Results May Vary") {
                ForEach(Self.variations, id: \.self) { text in
                    Label(text, systemImage: "arrow.triangle.branch")
                }
            }

            Section {
                Text("Check your statements and lender terms for exact figures. Consider speaking with a qualified financial professional before making major financial decisions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Assumptions")
    }

    private static let assumptions: [(title: String, detail: String, systemImage: String)] = [
        ("Monthly interest", "Interest is estimated each month as balance × APR ÷ 12. Lenders that compound daily or use average daily balances will differ slightly.", "percent"),
        ("Fixed rates", "Each debt's APR stays the same for the whole plan unless you change it in the Simulator.", "lock"),
        ("On-time payments", "Every minimum payment is made in full and on time each month.", "calendar"),
        ("Fixed minimums", "Minimum payments stay the same. Many cards lower minimums as balances fall; paying the original amount is assumed.", "equal.circle"),
        ("Rollover", "When a debt is paid off, its minimum payment is added to the next debt in your priority order.", "arrow.turn.down.right"),
        ("Buy now, pay later", "Installments are converted to an estimated monthly payment (for example, every 2 weeks ≈ 2.17 payments a month). Late fees and rescheduled payments aren't included.", "bag"),
        ("No new debt", "No new charges, fees, penalties, or balance transfers are included.", "nosign"),
        ("Month timing", "Payments are grouped by month starting next month. Exact due dates within a month are not modeled.", "clock"),
    ]

    private static let variations = [
        "Lender rules for applying payments",
        "Fees, penalties, and late charges",
        "Variable or promotional interest rates",
        "Changes to minimum payments",
        "Missed, late, or partial payments",
        "New purchases or additional borrowing",
    ]
}

#Preview {
    NavigationStack { AssumptionsView() }
}
