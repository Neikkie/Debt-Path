import SwiftUI

/// Shown on first launch to introduce the app before the user logs their debts.
struct WelcomeView: View {
    let onAddDebt: () -> Void
    let onExplore: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
                            FeatureRow(feature: feature)
                                // Animate only the fade and slide, not the row's layout.
                                .animation(.spring(duration: 0.6).delay(0.15 + Double(index) * 0.08)) { row in
                                    row
                                        .opacity(hasAppeared ? 1 : 0)
                                        .offset(y: hasAppeared ? 0 : 16)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .appBackground(.blue)
            .safeAreaBar(edge: .bottom) {
                footer
            }
            .onAppear { hasAppeared = true }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .background(.blue.gradient, in: .rect(cornerRadius: 30))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
                .animation(.spring(duration: 0.7, bounce: 0.4)) { icon in
                    icon.scaleEffect(hasAppeared ? 1 : 0.6)
                }
                .accessibilityHidden(true)

            Text("Welcome to Debt Path")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Log your debts, choose a payoff strategy, and see an estimated path to becoming debt-free.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Figures are estimates, not financial advice.")
                NavigationLink("Learn more") {
                    AssumptionsView()
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button(action: onAddDebt) {
                Text("Add Your First Debt")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button(action: onExplore) {
                Text("Explore First")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    fileprivate struct Feature {
        let title: String
        let detail: String
        let systemImage: String
        let color: Color
    }

    private static let features: [Feature] = [
        Feature(title: "Log every debt",
                detail: "Credit cards, student loans, personal loans, medical bills, and buy now, pay later plans.",
                systemImage: "list.bullet.clipboard.fill", color: .purple),
        Feature(title: "Choose your strategy",
                detail: "Avalanche, snowball, or your own custom order, with a month-by-month schedule.",
                systemImage: "mountain.2.fill", color: .blue),
        Feature(title: "Try what-ifs",
                detail: "See how extra or one-time payments could change your estimated debt-free date.",
                systemImage: "slider.horizontal.3", color: .indigo),
        Feature(title: "Track your progress",
                detail: "Log payments, reach milestones, and earn badges along the way.",
                systemImage: "chart.line.downtrend.xyaxis", color: .green),
        Feature(title: "Stay on time",
                detail: "Optional reminders before each payment is due.",
                systemImage: "bell.badge.fill", color: .orange),
    ]
}

private struct FeatureRow: View {
    let feature: WelcomeView.Feature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.systemImage)
                .font(.title2)
                .foregroundStyle(feature.color.gradient)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onAddDebt: {}, onExplore: {})
}
