import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period = "month"
    @State private var date = Date()
    @State private var currency = "USD"
    @State private var output: ExportPayload?
    private var interval: DateInterval { Reports.interval(containing: date, period: period) }
    private var report: ReportResult { Reports.calculate(model.liveDocuments.map(DocumentRecord.init), currency: currency, interval: interval) }
    private var currencies: [String] { Set(model.liveDocuments.map(\.currencyCode) + [model.business.settings.currencyCode]).sorted() }
    var body: some View {
        Group {
            if model.entitlement.canSeeReports {
                List {
                    Picker(L.t("Period"), selection: $period) { Text(L.t("Month")).tag("month"); Text(L.t("Quarter")).tag("quarter"); Text(L.t("Year")).tag("year") }.pickerStyle(.segmented).accessibilityIdentifier("reports.period")
                    DatePicker(L.t("Date"), selection: $date, displayedComponents: .date)
                    Picker(L.t("Currency"), selection: $currency) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }
                    AmountRow(title: L.t("Received"), amount: Money.format(report.received, currency: currency), bold: true)
                    AmountRow(title: L.t("Outstanding · all dates"), amount: Money.format(report.outstanding, currency: currency))
                    Chart(report.months) { item in BarMark(x: .value(L.t("Month"), item.month, unit: .month), y: .value(L.t("Received"), NSDecimalNumber(decimal: item.amount).doubleValue)).foregroundStyle(Design.accent) }.frame(height: 170).accessibilityIdentifier("reports.chart")
                    Section(L.t("Collected taxes · cash basis")) { ForEach(report.taxes.keys.sorted(), id: \.self) { tax in if report.taxes[tax, default: 0] != 0 { AmountRow(title: tax, amount: Money.format(report.taxes[tax, default: 0], currency: currency)) } } }
                    Section(L.t("By client")) { ForEach(report.clients) { AmountRow(title: $0.name, amount: Money.format($0.amount, currency: currency)) } }
                    Section {
                        Button(L.t("Export report CSV")) { exportCSV() }.accessibilityIdentifier("reports.csv")
                        Button(L.t("Export this year's PDFs")) { exportPDFs() }.accessibilityIdentifier("reports.pdfs")
                    }
                    Text(L.t("Each currency is reported separately. No exchange rates are applied.")).font(.caption).foregroundStyle(Design.muted)
                }
            } else { PaywallView() }
        }.pageBackground().navigationTitle(L.t("Reports")).onAppear { currency = model.business.settings.currencyCode }
            .sheet(item: $output) { ExportPicker(bytes: $0.bytes, filename: $0.filename) { output = nil } }
    }
    private func exportCSV() {
        var rows = [["Currency","Period start","Period end","Metric","Name","Amount"]]
        let prefix = [currency,interval.start.formatted(.iso8601),interval.end.formatted(.iso8601)]
        rows.append(prefix + ["received","","\(report.received)"]); rows.append(prefix + ["outstanding-all-dates","","\(report.outstanding)"])
        for name in report.taxes.keys.sorted() { rows.append(prefix + ["collected-tax",name,"\(report.taxes[name, default: 0])"]) }
        for rank in report.clients { rows.append(prefix + ["client",rank.name,"\(rank.amount)"]) }
        output = ExportPayload(bytes: CSV.encode(rows), filename: "Invoices-report.csv")
    }
    private func exportPDFs() {
        do {
            let year = Calendar.current.component(.year, from: date)
            let files = model.liveDocuments.filter { Calendar.current.component(.year, from: $0.issueDate) == year }.map { d -> (String, Data) in
                let record = DocumentRecord(d)
                return (String(d.id.uuidString.prefix(8)) + "-" + PDFRenderer.filename(record), PDFRenderer.render(document: record, business: BusinessRecord(model.business), entitlement: model.entitlement))
            }
            output = ExportPayload(bytes: try ZipStore.archive(files), filename: "Invoices-\(year).zip")
        } catch { model.error = L.t("The export could not be created.") }
    }
}
