import Foundation

struct ReportBucket: Identifiable { var month: Date; var amount: Decimal; var id: Date { month } }
struct ClientRank: Identifiable { var name: String; var amount: Decimal; var id: String { name } }
struct ReportResult {
    var received: Decimal = 0
    var outstanding: Decimal = 0
    var taxes: [String: Decimal] = [:]
    var months: [ReportBucket] = []
    var clients: [ClientRank] = []
}
enum Reports {
    static func interval(containing date: Date, period: String, calendar: Calendar = .current) -> DateInterval {
        if period == "quarter" {
            let year = calendar.component(.year, from: date), month = calendar.component(.month, from: date)
            let start = calendar.date(from: DateComponents(year: year, month: ((month - 1) / 3) * 3 + 1, day: 1)) ?? date
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 3, to: start) ?? date)
        }
        return calendar.dateInterval(of: period == "month" ? .month : .year, for: date) ?? DateInterval(start: date, duration: 1)
    }
    static func calculate(_ documents: [DocumentRecord], currency: String, interval: DateInterval, calendar: Calendar = .current) -> ReportResult {
        var report = ReportResult(), monthly: [Date: Decimal] = [:], clients: [String: Decimal] = [:]
        let liveIDs = Set(documents.filter { $0.deletedAt == nil }.map(\.id))
        for d in documents where d.kind == "invoice" && d.deletedAt == nil && d.currency == currency {
            let standalone = d.depositParentID.map { !liveIDs.contains($0) } ?? true
            if standalone { report.outstanding += max(0, d.totals.balance) }
            let inPeriod = d.payments.filter { $0.date >= interval.start && $0.date < interval.end }
            let received = inPeriod.filter { $0.sourcePaymentID == nil }
            for p in received {
                report.received += p.amount; clients[d.clientName, default: 0] += p.amount
                let start = calendar.dateInterval(of: .month, for: p.date)?.start ?? p.date; monthly[start, default: 0] += p.amount
            }
            if standalone && d.totals.total > 0 {
                var collected: Decimal = 0, priorTax1: Decimal = 0, priorTax2: Decimal = 0
                for payment in d.payments.sorted(by: { $0.date < $1.date }) {
                    collected = min(d.totals.total, collected + max(0, payment.amount))
                    let tax1 = Money.round(d.totals.tax1 * collected / d.totals.total, currency: currency)
                    let tax2 = Money.round(d.totals.tax2 * collected / d.totals.total, currency: currency)
                    if payment.date >= interval.start && payment.date < interval.end {
                        report.taxes[d.tax1.name, default: 0] += tax1 - priorTax1
                        report.taxes[d.tax2.name, default: 0] += tax2 - priorTax2
                    }
                    priorTax1 = tax1; priorTax2 = tax2
                }
            }
        }
        report.months = monthly.keys.sorted().map { ReportBucket(month: $0, amount: monthly[$0, default: 0]) }
        report.clients = clients.map { ClientRank(name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
        return report
    }
}
