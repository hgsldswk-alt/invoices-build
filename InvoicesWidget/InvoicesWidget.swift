import SwiftUI
import WidgetKit

struct InvoiceEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot }
struct InvoiceProvider: TimelineProvider {
    func placeholder(in context: Context) -> InvoiceEntry { InvoiceEntry(date: Date(), snapshot: WidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (InvoiceEntry) -> Void) { completion(InvoiceEntry(date: Date(), snapshot: WidgetSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<InvoiceEntry>) -> Void) { completion(Timeline(entries: [InvoiceEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .after(Date().addingTimeInterval(1800)))) }
}
struct InvoiceWidgetView: View {
    var entry: InvoiceEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if !entry.snapshot.entitlement.canUseWidget {
                Text(L.t("Open Invoices to unlock widgets.")).font(.caption)
            } else if family == .accessoryInline {
                Text(L.f("%@ outstanding · %d overdue", entry.snapshot.balances.first?.amount ?? "—", entry.snapshot.overdue))
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading) { Text(L.t("Outstanding")).font(.caption); Text(entry.snapshot.balances.map(\.amount).joined(separator: " · ")).bold().minimumScaleFactor(0.6); Text(L.f("%d overdue", entry.snapshot.overdue)).font(.caption) }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t("Outstanding")).font(.caption).foregroundStyle(.secondary)
                    if entry.snapshot.balances.isEmpty { Text("—").font(.title2.bold()) }
                    ForEach(entry.snapshot.balances.prefix(3)) { b in Text(b.amount).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1) }
                    Text(L.f("%d overdue", entry.snapshot.overdue)).font(.caption)
                    if family == .systemMedium {
                        ForEach(entry.snapshot.invoices) { d in
                            Link(destination: URL(string: "invoices:document/" + d.id.uuidString)!) { HStack { Text(d.name).lineLimit(1); Spacer(); Text(d.amount).monospacedDigit() }.font(.caption) }
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }.widgetURL(URL(string: "invoices:home")).tint(Color(red: 0.12, green: 0.36, blue: 0.29))
    }
}
@main struct InvoicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InvoicesOutstanding", provider: InvoiceProvider()) { InvoiceWidgetView(entry: $0) }
            .configurationDisplayName(L.t("Outstanding invoices")).description(L.t("Your balance due and overdue documents."))
            .supportedFamilies([.systemSmall,.systemMedium,.accessoryInline,.accessoryRectangular])
    }
}
