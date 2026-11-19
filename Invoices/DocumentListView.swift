import SwiftUI

struct DocumentListView: View {
    @EnvironmentObject private var model: AppModel
    var kind: String
    @State private var filter = ""
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    private var all: [Document] { model.liveDocuments.filter { $0.kind == kind } }
    private var currencies: [String] { Set(all.map(\.currencyCode)).sorted() }
    private var receivables: [Document] { kind == "invoice" ? model.receivableDocuments : all }
    private var filtered: [Document] {
        all.filter { d in
            let state = d.computedStatus(at: model.now)
            let matchFilter = filter.isEmpty || (filter == "outstanding" && d.totals.balance > 0) || (filter == "overdue" && state == "overdue") || (filter == "paid" && !paymentsThisMonth(d).isEmpty)
            let haystack = ([d.clientName,d.number,"\(d.totals.total)",Money.format(d.totals.total, currency: d.currencyCode)] + d.orderedLines.map(\.name)).joined(separator: " ")
            return matchFilter && (query.isEmpty || haystack.localizedCaseInsensitiveContains(query))
        }.sorted { $0.issueDate > $1.issueDate }
    }
    private func paymentsThisMonth(_ d: Document) -> [Payment] { d.sortedPayments.filter { Calendar.current.isDate($0.date, equalTo: model.now, toGranularity: .month) && $0.sourcePaymentID == nil } }
    var body: some View {
        List {
            if searching {
                TextField(L.t("Search clients, numbers, items or amounts"), text: $query).focused($searchFocused).accessibilityIdentifier("documents.search").listRowBackground(Design.card)
            }
            if kind == "invoice" && !all.isEmpty { summary.listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0)).listRowBackground(Color.clear).listRowSeparator(.hidden) }
            if all.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L.t("Your first invoice takes about a minute.")).foregroundStyle(Design.muted)
                    Button(L.t("New document")) { create() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("empty.new")
                }.padding(.vertical, 30).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                group(title: L.t("This week"), docs: filtered.filter { Calendar.current.isDate($0.issueDate, equalTo: model.now, toGranularity: .weekOfYear) })
                group(title: L.t("Earlier"), docs: filtered.filter { !Calendar.current.isDate($0.issueDate, equalTo: model.now, toGranularity: .weekOfYear) })
            }
            if !model.cloudEnabled && model.liveDocuments.count >= 10 { Text(L.t("Your invoices live only on this iPhone — turn on iCloud or export a backup.")).font(.caption).foregroundStyle(Design.muted).listRowBackground(Color.clear) }
            Color.clear.frame(height: 70).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped).pageBackground()
        .navigationTitle(kind == "invoice" ? L.t("Invoices") : L.t(model.business.settings.estimateWord == "Quote" ? "Quotes" : "Estimates"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { searching.toggle(); searchFocused = searching } label: { Image(systemName: "magnifyingglass") }.accessibilityIdentifier("search.toggle") }
        }
        .overlay(alignment: .bottomTrailing) { Button { create() } label: { Label(L.t("New"), systemImage: "plus").font(.headline).foregroundStyle(.white).padding(.horizontal, 22).frame(minHeight: 56).background(Design.accent, in: Capsule()) }.padding(22).accessibilityIdentifier("document.new").keyboardShortcut("n", modifiers: .command) }
        .background(Button("") { searching = true; searchFocused = true }.accessibilityIdentifier("DocumentListView.button.46").keyboardShortcut("f", modifiers: .command).hidden())
    }
    private func create() { model.selected = model.newDocument(kind: kind) }
    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            summaryCell(L.t("Outstanding"), key: "outstanding", color: .white, filled: true) { currency in receivables.filter { $0.currencyCode == currency }.reduce(0) { $0 + max(0, $1.totals.balance) } }
            summaryCell(L.f("Overdue · %d", receivables.filter { $0.computedStatus(at: model.now) == "overdue" }.count), key: "overdue", color: Design.red) { currency in receivables.filter { $0.currencyCode == currency && $0.computedStatus(at: model.now) == "overdue" }.reduce(0) { $0 + $1.totals.balance } }
            summaryCell(L.t("Paid · This month"), key: "paid", color: Design.ink) { currency in all.filter { $0.currencyCode == currency }.reduce(0) { $0 + paymentsThisMonth($1).reduce(0) { $0 + $1.amount } } }
        }
    }
    private func summaryCell(_ title: String, key: String, color: Color, filled: Bool = false, value: @escaping (String) -> Decimal) -> some View {
        Button { filter = filter == key ? "" : key } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.caption2).foregroundStyle(filled ? .white.opacity(0.75) : Design.muted)
                ForEach(currencies, id: \.self) { currency in Text(Money.format(value(currency), currency: currency)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.65).lineLimit(1) }
            }.frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(11).background(filled ? Design.accent : Design.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(filter == key ? Design.accent : Design.line, lineWidth: filter == key ? 2 : 0.5))
        }.buttonStyle(.plain).accessibilityIdentifier("summary." + key)
    }
    @ViewBuilder private func group(title: String, docs: [Document]) -> some View {
        if !docs.isEmpty {
            Section(title) {
                ForEach(docs) { d in
                    Button { model.selected = d } label: { DocumentRow(document: d) }.buttonStyle(.plain).accessibilityIdentifier("document." + d.number)
                        .listRowBackground(Design.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if kind == "invoice" && d.totals.balance > 0 { Button { model.markPaid(d) } label: { Label(L.t("Mark paid"), systemImage: "checkmark") }.tint(Design.accent).accessibilityIdentifier("paid." + d.number) }
                            else if kind == "estimate" && d.status != "converted" { Button { d.status = "accepted"; model.save() } label: { Label(L.t("Mark accepted"), systemImage: "checkmark") }.tint(Design.accent).accessibilityIdentifier("accept." + d.number) }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { model.selected = model.duplicate(d) } label: { Label(L.t("Duplicate"), systemImage: "doc.on.doc") }.tint(Design.accent).accessibilityIdentifier("duplicate." + d.number)
                            Button { model.delete(d) } label: { Label(L.t("Delete"), systemImage: "trash") }.tint(Design.red).accessibilityIdentifier("delete." + d.number)
                        }
                        .contextMenu {
                            Button(L.t("Duplicate")) { model.selected = model.duplicate(d) }.accessibilityIdentifier("DocumentListView.button.79")
                            Button(L.t("Duplicate as revision")) { model.selected = model.duplicate(d, revision: true) }.accessibilityIdentifier("DocumentListView.button.80")
                            Button(L.t("Delete")) { model.delete(d) }.accessibilityIdentifier("DocumentListView.button.81")
                        }
                }
            }
        }
    }
}
struct DocumentRow: View {
    var document: Document
    private var d: Document { document }
    private var state: String { d.computedStatus() }
    private var initials: String { d.clientName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    private var detail: String {
        if state == "overdue", let due = d.dueDate { return L.f("%d days overdue", max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: due), to: Calendar.current.startOfDay(for: Date())).day ?? 1)) }
        if state == "paid", let date = d.sortedPayments.last?.date { return L.f("Paid %@", L.date(date)) }
        return d.dueDate.map { L.f("Due %@", L.date($0)) } ?? L.status(state)
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(initials).font(.caption.weight(.semibold)).frame(width: 36, height: 36).background(Design.background, in: Circle()).foregroundStyle(Design.ink)
            VStack(alignment: .leading, spacing: 4) {
                Text(d.clientName.isEmpty ? L.t("Client name") : d.clientName).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Design.ink)
                Text(d.number + " · " + detail).font(.caption).foregroundStyle(Design.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(d.totals.total, currency: d.currencyCode)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Design.ink)
                StatusBadge(status: state, label: state == "partial" ? L.f("%@ due", Money.format(d.totals.balance, currency: d.currencyCode)) : nil)
            }
        }.padding(.vertical, 4)
    }
}
