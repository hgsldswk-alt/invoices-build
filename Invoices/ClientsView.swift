import SwiftUI

struct ClientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var adding = false
    @State private var name = ""
    var body: some View {
        List {
            if adding {
                TextField(L.t("Client name"), text: $name).accessibilityIdentifier("clients.name").onSubmit { create() }
                Button(L.t("Save")) { create() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("clients.save")
            }
            ForEach(model.clients.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { c in
                NavigationLink { ClientDetail(client: c) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.name).font(.headline)
                        let docs = model.receivableDocuments.filter { $0.client?.id == c.id }
                        ForEach(Set(docs.map(\.currencyCode)).sorted(), id: \.self) { currency in
                            let balance = docs.filter { $0.currencyCode == currency }.reduce(0) { $0 + max(0,$1.totals.balance) }
                            Text(L.f("%@ outstanding", Money.format(balance, currency: currency))).font(.caption).foregroundStyle(Design.muted).monospacedDigit()
                        }
                    }
                }.accessibilityIdentifier("clients." + c.id.uuidString)
            }
            NavigationLink(L.t("Import clients CSV")) { CSVImportView(kind: "clients") }.accessibilityIdentifier("clients.import")
        }.pageBackground().navigationTitle(L.t("Clients")).searchable(text: $query, prompt: L.t("Search clients"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding.toggle() } label: { Image(systemName: "plus") }.accessibilityLabel(L.t("Add client")).accessibilityIdentifier("clients.add") } }
    }
    private func create() { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty else { return }; model.context.insert(Client(name: n)); model.save(); name = ""; adding = false }
}
struct ClientDetail: View {
    @EnvironmentObject private var model: AppModel
    @Bindable var client: Client
    @State private var send: SendPayload?
    @State private var saveTask: Task<Void, Never>?
    private var docs: [Document] { model.liveDocuments.filter { $0.client?.id == client.id } }
    var body: some View {
        Form {
            Section(L.t("Contact details")) {
                TextField(L.t("Name"), text: $client.name).accessibilityIdentifier("client.name")
                TextField(L.t("Email"), text: $client.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).accessibilityIdentifier("client.email")
                TextField(L.t("Phone"), text: $client.phone).keyboardType(.phonePad).accessibilityIdentifier("client.phone")
                TextField(L.t("Address"), text: $client.address, axis: .vertical).accessibilityIdentifier("client.address")
                TextField(L.t("Notes"), text: $client.notes, axis: .vertical).accessibilityIdentifier("client.notes")
            }
            Section(L.t("Defaults")) {
                CurrencyPicker(value: Binding(get: { client.currencyCode ?? model.business.settings.currencyCode }, set: { client.currencyCode = $0 }))
                Stepper(L.term(client.defaultTerms ?? model.business.settings.defaultTerms), value: Binding(get: { client.defaultTerms ?? model.business.settings.defaultTerms }, set: { client.defaultTerms = $0 }), in: 0...365).accessibilityIdentifier("client.terms")
                TextField(L.t("Tax name"), text: Binding(get: { client.defaultTax?.name ?? model.business.settings.defaultTax1.name }, set: { var tax = client.defaultTax ?? model.business.settings.defaultTax1; tax.name = $0; client.defaultTax = tax }))
                HStack { Text(L.t("Tax rate")); DecimalField(title: L.t("Tax rate"), value: Binding(get: { client.defaultTax?.rate ?? model.business.settings.defaultTax1.rate }, set: { var tax = client.defaultTax ?? model.business.settings.defaultTax1; tax.rate = max(0,$0); client.defaultTax = tax })) }
            }
            Section(L.t("Paid total")) {
                ForEach(Set(docs.map(\.currencyCode)).sorted(), id: \.self) { currency in
                    let total = docs.filter { $0.currencyCode == currency && $0.kind == "invoice" }.reduce(0) { $0 + $1.sortedPayments.filter { $0.sourcePaymentID == nil }.reduce(0) { $0 + $1.amount } }
                    AmountRow(title: currency, amount: Money.format(total, currency: currency))
                }
                Button(L.t("Send statement")) {
                    model.require(model.entitlement.canUseStatement) {
                        send = SendPayload(bytes: PDFRenderer.statement(client: ClientRecord(client), documents: model.documents.map(DocumentRecord.init), business: BusinessRecord(model.business)), filename: "Statement.pdf", email: client.email, phone: client.phone, subject: L.t("Statement"), body: L.t("Please find your statement attached. Thank you."), method: model.business.settings.sendMethod)
                    }
                }.accessibilityIdentifier("client.statement")
            }
            Section(L.t("Document history")) { ForEach(docs) { d in Button { model.selected = d } label: { DocumentRow(document: d) }.accessibilityIdentifier("client.document." + d.number) } }
        }.pageBackground().navigationTitle(client.name)
            .onChange(of: ClientRecord(client)) { _, _ in saveTask?.cancel(); saveTask = Task { try? await Task.sleep(nanoseconds: 500_000_000); guard !Task.isCancelled else { return }; model.save() } }
            .onDisappear { saveTask?.cancel(); model.save() }
            .sheet(item: $send) { SendSheet(payload: $0) { _ in } }
    }
}
struct ItemsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var editing: Item?
    var body: some View {
        List {
            ForEach(model.items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.lastUsed > $1.lastUsed }) { i in
                Button { editing = i } label: { AmountRow(title: i.name, amount: Money.format(i.unitPrice, currency: model.business.settings.currencyCode)) }.accessibilityIdentifier("items." + i.id.uuidString)
                    .swipeActions { Button(L.t("Delete")) { model.context.delete(i); model.save() }.accessibilityIdentifier("ClientsView.button.79").tint(Design.red) }
            }
            NavigationLink(L.t("Import items CSV")) { CSVImportView(kind: "items") }.accessibilityIdentifier("items.import")
        }.pageBackground().navigationTitle(L.t("Items")).searchable(text: $query, prompt: L.t("Search items"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { let item = Item(); model.context.insert(item); model.save(); editing = item } label: { Image(systemName: "plus") }.accessibilityLabel(L.t("Add item")).accessibilityIdentifier("items.add") } }
            .sheet(item: $editing) { ItemEditor(item: $0).environmentObject(model) }
    }
}
struct ItemEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: Item
    var body: some View {
        NavigationStack {
            Form {
                TextField(L.t("Name"), text: $item.name).accessibilityIdentifier("item.name")
                TextField(L.t("Description"), text: $item.details, axis: .vertical)
                DecimalField(title: L.t("Unit price"), value: $item.unitPrice).accessibilityIdentifier("item.price")
                TextField(L.t("Unit"), text: $item.unit)
                Toggle(L.t("Taxable"), isOn: $item.taxable)
            }.pageBackground().navigationTitle(L.t("Item")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("Done")) { model.save(); dismiss() }.accessibilityIdentifier("item.done") } }.onDisappear { model.save() }
        }
    }
}
