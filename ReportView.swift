import SwiftUI

/// Builds the payoff report as a list of blocks. Blocks are kept small (long tables are split
/// into chunks) so the PDF exporter can flow them across letter-size pages without cutting rows.
@MainActor
enum PayoffReport {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 40
    static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    static func blocks(for store: DebtStore) -> [AnyView] {
        let plan = store.plan()
        let comparisons = PayoffStrategy.allCases.map { store.plan(for: $0) }
        let minimumOnly = store.minimumOnlyPlan
        var blocks: [AnyView] = []

        // Header
        blocks.append(AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Debt Payoff Report")
                    .font(.largeTitle.bold())
                Text("Prepared \(Date.now.formatted(date: .long, time: .omitted)) · \(store.strategy.title) strategy")
                    .foregroundStyle(.secondary)
            }
        ))

        // Summary
        blocks.append(AnyView(
            section("Summary") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    row("Total balance", store.totalBalance.currency)
                    row("Paid off so far", "\(store.progress.percent) (\((store.totalOriginalBalance - store.totalBalance).currency))")
                    row("Monthly payment", (store.totalMinimums + store.extraMonthly).currency)
                    row("Est. debt-free date", plan.debtFreeDate?.monthYear ?? "Not within 50 years")
                    row("Est. interest remaining", plan.totalInterest.currency)
                    row("Est. interest saved vs. minimums", max(0, minimumOnly.totalInterest - plan.totalInterest).currency)
                }
            }
        ))

        // Debts, in chunks so long lists continue on the next page.
        for (index, chunk) in store.debts.chunked(into: 14).enumerated() {
            blocks.append(AnyView(
                section(index == 0 ? "Debts" : "Debts (continued)") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Debt").bold()
                            Text("Type").bold()
                            Text("Balance").bold()
                            Text("APR").bold()
                            Text("Minimum").bold()
                            Text("Est. Payoff").bold()
                        }
                        Divider().gridCellColumns(6)
                        ForEach(chunk) { debt in
                            GridRow {
                                Text(debt.name)
                                Text(debt.kind.title)
                                Text(debt.balance.currency)
                                Text(debt.apr.aprText)
                                Text(debt.minimumPayment.currency)
                                Text(debt.isPaidOff ? "Paid off" : (plan.milestones.first { $0.debt.id == debt.id }?.date.monthYear ?? "—"))
                            }
                        }
                    }
                    .font(.caption)
                }
            ))
        }

        // Strategy comparison
        blocks.append(AnyView(
            section("Strategy Comparison") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Strategy").bold()
                        Text("Est. Debt-Free").bold()
                        Text("Est. Interest").bold()
                        Text("Est. Total Paid").bold()
                    }
                    Divider().gridCellColumns(4)
                    ForEach(comparisons, id: \.strategy) { plan in
                        GridRow {
                            Text(plan.strategy.title)
                            Text(plan.debtFreeDate?.monthYear ?? "50+ yrs")
                            Text(plan.totalInterest.currency)
                            Text(plan.totalPaid.currency)
                        }
                    }
                    GridRow {
                        Text("Minimums only")
                        Text(minimumOnly.debtFreeDate?.monthYear ?? "50+ yrs")
                        Text(minimumOnly.totalInterest.currency)
                        Text(minimumOnly.totalPaid.currency)
                    }
                }
                .font(.caption)
            }
        ))

        // Year-end balances
        let yearEnds = plan.months.filter { Calendar.current.component(.month, from: $0.date) == 12 || $0.number == plan.monthCount }
        for (index, chunk) in yearEnds.chunked(into: 25).enumerated() {
            blocks.append(AnyView(
                section(index == 0 ? "Estimated Year-End Balances" : "Estimated Year-End Balances (continued)") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        ForEach(chunk) { month in
                            row(month.date.monthYear, month.remainingBalance.currency)
                        }
                    }
                    .font(.caption)
                }
            ))
        }

        // Recent payments
        let recent = Array(store.payments.sorted { $0.date > $1.date }.prefix(24))
        for (index, chunk) in recent.chunked(into: 12).enumerated() {
            blocks.append(AnyView(
                section(index == 0 ? "Recent Payments" : "Recent Payments (continued)") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        ForEach(chunk) { payment in
                            GridRow {
                                Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                                Text(store.debt(withID: payment.debtID)?.name ?? "Removed debt")
                                Text(payment.amount.currency)
                            }
                        }
                    }
                    .font(.caption)
                }
            ))
        }

        // Disclaimer
        blocks.append(AnyView(
            Text("This report shows estimates for planning purposes only and is not financial advice. Calculations assume fixed interest rates, monthly interest, on-time minimum payments, and no new charges or fees. Actual results may vary based on lender rules, fees, and changing interest rates.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        ))

        return blocks
    }

    private static func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            content()
        }
    }

    private static func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

/// The report laid out as a single scrolling page, for the on-screen preview.
struct PayoffReportView: View {
    let store: DebtStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(PayoffReport.blocks(for: store).enumerated()), id: \.offset) { _, block in
                block
            }
        }
        .padding(PayoffReport.margin)
        .frame(width: PayoffReport.pageSize.width, alignment: .leading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

enum ReportExporter {
    /// Renders the report as a multi-page, letter-size PDF in the temporary directory.
    /// Each block is placed on the current page, or starts a new page if it doesn't fit.
    @MainActor
    static func makePDF(for store: DebtStore) -> URL? {
        let url = URL.temporaryDirectory.appending(path: "Debt Payoff Report.pdf")
        let pageSize = PayoffReport.pageSize
        let margin = PayoffReport.margin
        let spacing: CGFloat = 22
        let footerHeight: CGFloat = 20

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        var pageNumber = 0
        var cursorY: CGFloat = 0  // Distance from the top of the page.

        func beginPage() {
            if pageNumber > 0 {
                drawFooter(page: pageNumber)
                context.endPDFPage()
            }
            context.beginPDFPage(nil)
            pageNumber += 1
            cursorY = margin
        }

        func drawFooter(page: Int) {
            let footer = ImageRenderer(content:
                Text("Debt Path · Estimates only · Page \(page)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .environment(\.colorScheme, .light)
            )
            footer.render { size, draw in
                context.saveGState()
                context.translateBy(x: (pageSize.width - size.width) / 2, y: margin / 2)
                draw(context)
                context.restoreGState()
            }
        }

        beginPage()
        for block in PayoffReport.blocks(for: store) {
            let renderer = ImageRenderer(content:
                block
                    .frame(width: PayoffReport.contentWidth, alignment: .leading)
                    .environment(\.colorScheme, .light)
            )
            renderer.render { size, draw in
                let bottomLimit = pageSize.height - margin - footerHeight
                if cursorY + size.height > bottomLimit && cursorY > margin {
                    beginPage()
                }
                // Core Graphics puts the origin at the bottom-left, so flip the top-down cursor.
                context.saveGState()
                context.translateBy(x: margin, y: pageSize.height - cursorY - size.height)
                draw(context)
                context.restoreGState()
                cursorY += size.height + spacing
            }
        }
        drawFooter(page: pageNumber)
        context.endPDFPage()
        context.closePDF()
        return url
    }
}

private extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// Previews the report and offers it for sharing as a PDF.
struct ReportPreviewView: View {
    @Environment(DebtStore.self) private var store
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            PayoffReportView(store: store)
                .clipShape(.rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding()
        }
        .background(Color.gray.opacity(0.12))
        .navigationTitle("Payoff Report")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let pdfURL {
                    ShareLink(item: pdfURL, preview: SharePreview("Debt Payoff Report", image: Image(systemName: "doc.richtext"))) {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            pdfURL = ReportExporter.makePDF(for: store)
        }
    }
}

#Preview {
    NavigationStack { ReportPreviewView() }
        .environment(DebtStore.preview)
}
