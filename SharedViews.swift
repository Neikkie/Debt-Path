import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liquid Glass building blocks

extension View {
    /// A padded content card rendered with Liquid Glass.
    func glassCard(cornerRadius: CGFloat = 26, tint: Color? = nil) -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.18)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// A soft color wash behind scrolling content so Liquid Glass has something to refract.
    func appBackground(_ tint: Color = .accentColor) -> some View {
        background {
            LinearGradient(
                colors: [tint.opacity(0.35), tint.opacity(0.10), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

/// A rounded icon tile tinted by a debt's category.
struct KindIcon: View {
    let kind: DebtKind
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.color.gradient, in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// A compact labeled value used in stat grids.
struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .glassCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

/// A circular progress ring.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = .green

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)
        }
    }
}

/// A small note reminding people that figures are estimates.
struct EstimateFootnote: View {
    var body: some View {
        NavigationLink {
            AssumptionsView()
        } label: {
            Label("Estimates only. See assumptions", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Input

/// A labeled money entry field. Uses a plain number format with the currency symbol shown
/// beside it, so typing "500" works without entering "$".
struct MoneyField: View {
    let title: String
    @Binding var value: Double?
    var prompt = "Required"

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(Locale.current.currencySymbol ?? "$")
                    .foregroundStyle(.secondary)
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)), prompt: Text(prompt))
                    .decimalKeyboard()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
        }
    }
}

extension View {
    /// Adds a "Done" button above the keyboard, since number pads have no return key,
    /// and lets people dismiss the keyboard by scrolling.
    func keyboardDoneButton() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
    }
}

@MainActor
func dismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

// MARK: - Layout

/// Lays out content side by side, or stacked vertically at accessibility text sizes.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content }
    }
}

// MARK: - Undo banner

/// A floating Liquid Glass banner offering to undo the latest deletion.
struct UndoBanner: View {
    let undo: DebtStore.UndoAction
    let onUndo: () -> Void
    let onExpire: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(undo.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .task(id: undo.id) {
            try? await Task.sleep(for: .seconds(6))
            onExpire()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Undo", onUndo)
    }
}

// MARK: - Celebration

/// Shown when a debt reaches a zero balance.
struct CelebrationView: View {
    let debt: Debt
    let remainingCount: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var isDebtFree: Bool { remainingCount == 0 }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            if !reduceMotion {
                ConfettiView()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 16) {
                Image(systemName: isDebtFree ? "trophy.fill" : "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isDebtFree ? Color.yellow.gradient : debt.kind.color.gradient)
                    .symbolEffect(.bounce, value: hasAppeared)
                    .accessibilityHidden(true)

                Text(isDebtFree ? "You're Debt-Free!" : "Debt Paid Off!")
                    .font(.title.bold())

                Text(isDebtFree
                     ? "You paid off \(debt.name), your last debt. Amazing work!"
                     : "You paid off \(debt.name). \(remainingCount) to go. Keep the momentum!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("Keep Going")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(32)
            .scaleEffect(hasAppeared ? 1 : 0.85)
            .opacity(hasAppeared ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) { hasAppeared = true }
        }
        .sensoryFeedback(.success, trigger: hasAppeared)
    }
}

/// Simple falling confetti made of colored shapes.
private struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let duration: Double
        let spin: Double
        let color: Color
        let size: CGFloat
    }

    @State private var isFalling = false
    @State private var pieces: [Piece] = (0..<36).map { index in
        Piece(
            id: index,
            x: .random(in: 0...1),
            delay: .random(in: 0...0.6),
            duration: .random(in: 1.8...3.2),
            spin: .random(in: 180...720),
            color: [Color.yellow, .green, .blue, .pink, .orange, .purple, .mint].randomElement() ?? .yellow,
            size: .random(in: 6...12)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 1.6)
                    .rotationEffect(.degrees(isFalling ? piece.spin : 0))
                    .position(x: piece.x * proxy.size.width,
                              y: isFalling ? proxy.size.height + 40 : -40)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: isFalling)
            }
        }
        .ignoresSafeArea()
        .onAppear { isFalling = true }
    }
}

// MARK: - Platform helpers

extension View {
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Zooms a sheet out of the view that presented it.
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        #else
        self
        #endif
    }
}

extension ReorderDifference where CollectionID == ReorderableSingleCollectionIdentifier {
    /// Applies a drag-to-reorder move to an array of identifiable items.
    func apply<C>(to collection: inout C)
        where C: RangeReplaceableCollection, C.Element: Identifiable, C.Element.ID == ItemID
    {
        let moving = Set(sources)
        guard !moving.isEmpty else { return }

        var moved: [C.Element] = []
        collection.removeAll { element in
            guard moving.contains(element.id) else { return false }
            moved.append(element)
            return true
        }

        switch destination.position {
        case .before(let id):
            let index = collection.firstIndex { $0.id == id } ?? collection.endIndex
            collection.insert(contentsOf: moved, at: index)
        case .end:
            collection.append(contentsOf: moved)
        }
    }
}
