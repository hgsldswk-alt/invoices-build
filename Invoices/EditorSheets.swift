import SwiftUI
import ContactsUI
import PencilKit

struct LineEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Bindable var line: LineItem
    var currency: String
    @State private var saveToItems = false
    private var suggestions: [Item] { model.items.filter { line.name.isEmpty || $0.name.localizedCaseInsensitiveContains(line.name) }.sorted { $0.lastUsed > $1.lastUsed } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.t("Item name"), text: $line.name).accessibilityIdentifier("line.name")
                    TextField(L.t("Description"), text: $line.details, axis: .vertical).accessibilityIdentifier("line.details")
                    HStack { Text(L.t("Quantity")); DecimalField(title: L.t("Quantity"), value: $line.quantity).accessibilityIdentifier("line.quantity") }
                    TextField(L.t("Unit"), text: $line.unit).accessibilityIdentifier("line.unit")
                    HStack { Text(L.t("Unit price")); DecimalField(title: L.t("Unit price"), value: $line.unitPrice).accessibilityIdentifier("line.price") }
                    Picker(L.t("Discount type"), selection: $line.discountKind) { Text(L.t("Percent")).tag("percent"); Text(L.t("Amount")).tag("amount") }
                    HStack { Text(L.t("Discount")); DecimalField(title: L.t("Discount"), value: $line.discountValue) }
                    Toggle(L.t("Taxable"), isOn: $line.taxable).accessibilityIdentifier("line.taxable")
                    if !line.name.isEmpty && !model.items.contains(where: { $0.name.caseInsensitiveCompare(line.name) == .orderedSame }) { Toggle(L.t("Save to items"), isOn: $saveToItems).accessibilityIdentifier("line.saveToItems") }
                }
                if !suggestions.isEmpty {
                    Section(L.t("From your items")) {
                        ForEach(suggestions.prefix(8)) { item in
                            Button { line.name = item.name; line.details = item.details; line.unitPrice = item.unitPrice; line.unit = item.unit; line.taxable = item.taxable; item.lastUsed = Date() } label: { AmountRow(title: item.name, amount: Money.format(item.unitPrice, currency: currency)) }.accessibilityIdentifier("item.suggestion." + item.id.uuidString)
                        }
                    }
                }
            }.pageBackground().navigationTitle(L.t("Item"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("Done")) { finish(); dismiss() }.accessibilityIdentifier("line.done") } }
                .onDisappear { finish() }
        }
    }
    private func finish() {
        line.quantity = max(0, line.quantity); line.unitPrice = max(0, line.unitPrice); line.discountValue = max(0, line.discountValue)
        if saveToItems && !line.name.isEmpty && !model.items.contains(where: { $0.name.caseInsensitiveCompare(line.name) == .orderedSame }) {
            let item = Item(name: line.name, price: line.unitPrice, unit: line.unit); item.details = line.details; item.taxable = line.taxable; model.context.insert(item); saveToItems = false
        }
        model.save()
    }
}
struct ClientPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var document: Document
    @State private var query = ""
    @State private var contacts = false
    var body: some View {
        NavigationStack {
            List {
                TextField(L.t("Client name"), text: $query).accessibilityIdentifier("client.search").onSubmit { create() }
                if !query.isEmpty { Button(L.f("Use %@", query)) { create() }.accessibilityIdentifier("client.create") }
                Button(L.t("From Contacts")) { contacts = true }.accessibilityIdentifier("client.contacts")
                Section(L.t("Recent clients")) {
                    ForEach(model.clients.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.lastUsed > $1.lastUsed }) { c in
                        Button(c.name) { model.pick(c, for: document); dismiss() }.accessibilityIdentifier("client.pick." + c.id.uuidString)
                    }
                }
            }.pageBackground().navigationTitle(L.t("Bill to")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("EditorSheets.button.63") } }
                .sheet(isPresented: $contacts) { ContactPicker { contact in
                    let c = Client(name: CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName)
                    c.email = contact.emailAddresses.first.map { String($0.value) } ?? ""
                    c.phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                    if let address = contact.postalAddresses.first?.value { c.address = CNPostalAddressFormatter.string(from: address, style: .mailingAddress) }
                    model.context.insert(c); model.pick(c, for: document); dismiss()
                } }
        }
    }
    private func create() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }
        let c = model.clients.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? Client(name: name)
        if c.modelContext == nil { model.context.insert(c) }; model.pick(c, for: document); dismiss()
    }
}
struct ContactPicker: UIViewControllerRepresentable {
    var selected: (CNContact) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController { let picker = CNContactPickerViewController(); picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let selected: (CNContact) -> Void
        init(selected: @escaping (CNContact) -> Void) { self.selected = selected }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { selected(contact) }
    }
}
struct PaymentEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var document: Document
    var payment: Payment?
    @State private var amount: Decimal
    @State private var date: Date
    @State private var method: String
    @State private var note: String
    init(document: Document, payment: Payment?) {
        self.document = document; self.payment = payment
        _amount = State(initialValue: payment?.amount ?? max(0, document.totals.balance)); _date = State(initialValue: payment?.date ?? Date())
        _method = State(initialValue: payment?.method ?? "cash"); _note = State(initialValue: payment?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                HStack { Text(L.t("Amount")); DecimalField(title: L.t("Amount"), value: $amount).accessibilityIdentifier("payment.amount") }
                DatePicker(L.t("Date"), selection: $date, displayedComponents: .date).accessibilityIdentifier("payment.date")
                Picker(L.t("Method"), selection: $method) { ForEach(Payment.methods, id: \.self) { Text(L.method($0)).tag($0) } }.accessibilityIdentifier("payment.method")
                TextField(L.t("Note"), text: $note, axis: .vertical).accessibilityIdentifier("payment.note")
                if let p = payment {
                    Button(L.t("Delete payment"), role: .destructive) { model.context.delete(p); document.payments = (document.payments ?? []).filter { $0.id != p.id }; model.syncDepositPayments(); model.save(); dismiss() }.accessibilityIdentifier("payment.delete")
                }
            }.pageBackground().navigationTitle(L.t("Payment"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("EditorSheets.button.116") }
                    ToolbarItem(placement: .confirmationAction) { Button(L.t("Save")) {
                        if let p = payment { p.amount = Money.round(amount, currency: document.currencyCode); p.date = date; p.method = method; p.note = note; model.syncDepositPayments(); model.save() }
                        else { model.addPayment(document, amount: amount, method: method, date: date, note: note) }
                        dismiss()
                    }.disabled(amount <= 0).accessibilityIdentifier("payment.save") }
                }.onAppear { if payment == nil { method = model.business.settings.lastPaymentMethod } }
        }
    }
}
struct DepositSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var document: Document
    @State private var kind = "percent"
    @State private var value: Decimal = 50
    var body: some View {
        NavigationStack {
            Form {
                Picker(L.t("Deposit type"), selection: $kind) { Text(L.t("Percent")).tag("percent"); Text(L.t("Amount")).tag("amount") }
                HStack { Text(L.t("Deposit")); DecimalField(title: L.t("Deposit"), value: $value) }
                Button(L.t("Create deposit invoice")) { let invoice = model.depositInvoice(from: document, percent: kind == "percent" ? value : nil, amount: kind == "amount" ? value : nil); model.selected = invoice; dismiss() }.disabled(value <= 0).accessibilityIdentifier("deposit.create")
            }.pageBackground().navigationTitle(L.t("Request deposit")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("EditorSheets.button.138") } }
        }
    }
}
struct SignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var completed: (Data) -> Void
    @State private var canvas = PKCanvasView()
    var body: some View {
        NavigationStack {
            VStack {
                SignatureCanvas(canvas: canvas).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).padding(20)
                Button(L.t("Clear")) { canvas.drawing = PKDrawing() }.accessibilityIdentifier("signature.clear").padding()
            }.pageBackground().navigationTitle(title).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("EditorSheets.button.153") }
                ToolbarItem(placement: .confirmationAction) { Button(L.t("Save")) {
                    let bounds = canvas.drawing.bounds.insetBy(dx: -12, dy: -12)
                    if !canvas.drawing.strokes.isEmpty, let bytes = canvas.drawing.image(from: bounds, scale: 2).pngData() { completed(bytes); dismiss() }
                }.accessibilityIdentifier("signature.save") }
            }
        }
    }
}
struct SignatureCanvas: UIViewRepresentable {
    var canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView { canvas.tool = PKInkingTool(.pen, color: .black, width: 2); canvas.drawingPolicy = .anyInput; canvas.backgroundColor = .white; canvas.overrideUserInterfaceStyle = .light; return canvas }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var completed: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let bytes = (info[.originalImage] as? UIImage)?.preparedPhoto()?.jpegData(compressionQuality: 0.85) { parent.completed(bytes) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
struct ShakeUndoView: UIViewRepresentable {
    var undo: () -> Void
    func makeUIView(context: Context) -> ShakeView { let view = ShakeView(); view.undo = undo; return view }
    func updateUIView(_ uiView: ShakeView, context: Context) { uiView.undo = undo }
    final class ShakeView: UIView {
        var undo: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() { super.didMoveToWindow(); becomeFirstResponder() }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) { if motion == .motionShake { undo?() } }
    }
}
