import SwiftUI
import PhotosUI

struct DocumentEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: Document
    @State private var editingLine: LineItem?
    @State private var clientPicker = false
    @State private var paymentSheet = false
    @State private var editingPayment: Payment?
    @State private var preview = false
    @State private var deposit = false
    @State private var signature = false
    @State private var camera = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var send: SendPayload?
    @State private var saveTask: Task<Void, Never>?
    @State private var saved = true
    @State private var ownNameNeeded = false
    @FocusState private var clientFocused: Bool
    private var d: Document { document }
    private var record: DocumentRecord { var v = DocumentRecord(d); v.updatedAt = v.createdAt; return v }
    private var t: MoneyResult { d.totals }
    private func amount(_ n: Decimal) -> String { Money.format(n, currency: d.currencyCode) }
    private var duplicateNumber: Bool { Numbering.isDuplicate(d.number, id: d.id, documents: model.documents.map { ($0.id,$0.number) }) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    TextField(L.t("Number"), text: $document.number).font(.largeTitle.bold()).accessibilityIdentifier("editor.number")
                    StatusBadge(status: d.computedStatus())
                }
                if duplicateNumber { Text(L.t("This number is already used. Choose a different number before sending.")).font(.caption).foregroundStyle(Design.red) }
                parties
                dates
                lines
                totals
                payments
                options
            }.padding(20)
        }
        .pageBackground().navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(L.t("Close")) { model.ensureClient(d); flush(); model.selected = nil; dismiss() }.accessibilityIdentifier("editor.close") }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) { Circle().fill(Design.accent).frame(width: 5, height: 5); Text(saved ? L.t("Saved") : L.t("Saving…")).font(.caption).foregroundStyle(Design.muted) }.accessibilityIdentifier("editor.saved")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L.t("Done")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("keyboard.done") }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button { flush(); preview = true } label: { Image(systemName: "doc.text.magnifyingglass").frame(width: 50, height: 50).background(Design.card, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel(L.t("Preview")).accessibilityIdentifier("editor.preview")
                Button(L.t("Send")) { sendDocument() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("editor.send")
                    .contextMenu {
                        Button(L.t("Email")) { sendDocument(method: "email") }.accessibilityIdentifier("DocumentEditor.button.57")
                        Button(L.t("Message")) { sendDocument(method: "message") }.accessibilityIdentifier("DocumentEditor.button.58")
                        Button(L.t("Share…")) { sendDocument(method: "share") }.accessibilityIdentifier("DocumentEditor.button.59")
                        Button(L.t("Print")) { sendDocument(method: "print") }.accessibilityIdentifier("DocumentEditor.button.60")
                        Button(L.t("Save PDF")) { sendDocument(method: "save") }.accessibilityIdentifier("DocumentEditor.button.61")
                    }
            }.padding(.horizontal, 20).padding(.vertical, 12).background(Design.background)
        }
        .sheet(isPresented: $clientPicker) { ClientPicker(document: d).environmentObject(model) }
        .sheet(item: $editingLine) { LineEditor(line: $0, currency: d.currencyCode).environmentObject(model) }
        .sheet(isPresented: $paymentSheet) { PaymentEditor(document: d, payment: editingPayment).environmentObject(model) }
        .sheet(isPresented: $preview) { PreviewView(document: d).environmentObject(model) }
        .sheet(isPresented: $deposit) { DepositSheet(document: d).environmentObject(model) }
        .sheet(isPresented: $signature) { SignatureSheet(title: L.t("Client signature")) { bytes in d.clientSignature = bytes; d.signedAt = Date(); flush() } }
        .sheet(isPresented: $camera) { CameraPicker { bytes in addPhoto(bytes) } }
        .sheet(item: $send) { payload in SendSheet(payload: payload) { success in if success && payload.marksSent { model.sent(d) } } }
        .onChange(of: record) { old, _ in
            saved = false; saveTask?.cancel()
            undoManager?.registerUndo(withTarget: model) { target in old.apply(to: d, context: target.context, clients: target.clients); target.save() }
            saveTask = Task { try? await Task.sleep(nanoseconds: 500_000_000); guard !Task.isCancelled else { return }; flush() }
        }
        .onChange(of: model.business.name) { _, _ in model.save() }
        .onChange(of: photos) { _, selection in Task { for photo in selection { if let data = try? await photo.loadTransferable(type: Data.self) { addPhoto(data) } }; photos = [] } }
        .onChange(of: model.pendingReminder) { _, id in if id == d.id { model.pendingReminder = nil; sendDocument(reminder: true) } }
        .onDisappear { model.ensureClient(d); flush() }
        .onAppear {
            ownNameNeeded = model.business.name.isEmpty
            clientFocused = d.clientName.isEmpty
            if ProcessInfo.processInfo.arguments.contains("-preview") { preview = true }
            if model.pendingReminder == d.id { model.pendingReminder = nil; sendDocument(reminder: true) }
        }
        .background(ShakeUndoView { undoManager?.undo() }.frame(width: 0, height: 0))
    }
    private var parties: some View {
        Card {
            if ownNameNeeded || model.business.name.isEmpty {
                HStack { Text(L.t("From")).foregroundStyle(Design.muted); TextField(L.t("Your business name"), text: $model.business.name).multilineTextAlignment(.trailing).accessibilityIdentifier("editor.business") }.padding(.vertical, 8)
                Divider()
            }
            HStack {
                Text(L.t("Bill to")).foregroundStyle(Design.muted)
                TextField(L.t("Client name"), text: Binding(get: { d.clientName }, set: { model.editClientName($0, for: d) })).multilineTextAlignment(.trailing).focused($clientFocused).accessibilityIdentifier("editor.clientName")
                Button { clientPicker = true } label: { Image(systemName: "chevron.right") }.accessibilityLabel(L.t("Choose client")).accessibilityIdentifier("editor.chooseClient")
            }.padding(.vertical, 8)
            if !d.clientName.isEmpty {
                Divider()
                TextField(L.t("Client email"), text: $document.clientEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).padding(.vertical, 8).accessibilityIdentifier("editor.clientEmail")
                TextField(L.t("Client address"), text: $document.clientAddress, axis: .vertical).font(.subheadline).accessibilityIdentifier("editor.clientAddress")
            }
        }
    }
    private var dates: some View {
        DisclosureGroup {
            DatePicker(L.t("Issued"), selection: $document.issueDate, displayedComponents: .date).accessibilityIdentifier("editor.issued")
            Picker(L.t("Payment terms"), selection: $document.terms) { ForEach([0,7,14,30], id: \.self) { Text(L.term($0)).tag($0) }; Text(L.t("Custom")).tag(-1) }.accessibilityIdentifier("editor.terms")
                .onChange(of: d.terms) { _, days in if days >= 0 { d.dueDate = Calendar.current.date(byAdding: .day, value: days, to: d.issueDate); model.reschedule(request: true) } }
            DatePicker(L.t("Due"), selection: Binding(get: { d.dueDate ?? d.issueDate }, set: { d.dueDate = $0; model.reschedule(request: true) }), displayedComponents: .date).accessibilityIdentifier("editor.due")
            Picker(L.t("Title"), selection: $document.title) { ForEach(d.kind == "invoice" ? ["Invoice","Tax Invoice","Bill"] : ["Estimate","Quote"], id: \.self) { Text(L.t($0)).tag($0) } }.accessibilityIdentifier("editor.title")
            CurrencyPicker(value: $document.currencyCode)
        } label: { HStack { Text(L.t("Issued · Due")).foregroundStyle(Design.muted); Spacer(); Text(L.date(d.issueDate) + " · " + L.term(d.terms)).font(.subheadline) } }
        .padding(14).background(Design.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private var lines: some View {
        Card {
            ForEach(d.orderedLines) { line in
                Button { editingLine = line } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) { Text(line.name.isEmpty ? L.t("Item") : line.name).font(.subheadline.weight(.semibold)); Spacer(); Text(amount(Money.round(line.moneyLine.quantity * line.unitPrice - line.moneyLine.discount.amount(on: line.quantity * line.unitPrice), currency: d.currencyCode))).monospacedDigit() }
                        HStack { Text("\(line.quantity) " + line.unit + " × " + amount(line.unitPrice)); Spacer(); Text(line.taxable ? L.t("Taxable") : L.t("No tax")) }.font(.caption).foregroundStyle(Design.muted)
                    }.padding(.vertical, 12)
                }.buttonStyle(.plain).accessibilityIdentifier("line." + line.id.uuidString)
                    .contextMenu {
                        Button(L.t("Move up")) { move(line, delta: -1) }.accessibilityIdentifier("DocumentEditor.button.129")
                        Button(L.t("Move down")) { move(line, delta: 1) }.accessibilityIdentifier("DocumentEditor.button.130")
                        Button(L.t("Delete")) { model.context.delete(line); d.lines = (d.lines ?? []).filter { $0.id != line.id }; flush() }.accessibilityIdentifier("DocumentEditor.button.131")
                    }
                    .draggable(line.id.uuidString)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let source = d.orderedLines.first(where: { $0.id.uuidString == ids.first }), let from = d.orderedLines.firstIndex(where: { $0.id == source.id }), let to = d.orderedLines.firstIndex(where: { $0.id == line.id }) else { return false }
                        var all = d.orderedLines; let moved = all.remove(at: from); all.insert(moved, at: to); for (i,l) in all.enumerated() { l.order = i }; flush(); return true
                    }
                Divider()
            }
            Button { editingLine = model.appendLine(d) } label: { Label(L.t("Add item"), systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.vertical, 12) }.accessibilityIdentifier("editor.addItem")
        }
    }
    private var totals: some View {
        Card {
            AmountRow(title: L.t("Subtotal"), amount: amount(t.subtotal))
            DisclosureGroup(L.t("Discount, tax & shipping")) {
                Picker(L.t("Discount type"), selection: $document.discountKind) { Text(L.t("Percent")).tag("percent"); Text(L.t("Amount")).tag("amount") }
                HStack { Text(L.t("Discount")); DecimalField(title: L.t("Discount"), value: $document.discountValue).accessibilityIdentifier("editor.discount") }
                taxFields(first: true)
                taxFields(first: false)
                Toggle(L.t("Compound second tax"), isOn: $document.tax2Compound)
                Toggle(L.t("Prices include tax"), isOn: $document.pricesIncludeTax)
                HStack { Text(L.t("Shipping")); DecimalField(title: L.t("Shipping"), value: $document.shipping) }
            }.font(.subheadline).padding(.vertical, 6)
            if t.discount > 0 { AmountRow(title: L.t("Discount"), amount: "−" + amount(t.discount)) }
            AmountRow(title: d.tax1Name + " \(d.tax1Rate)%", amount: amount(t.tax1))
            if d.tax2Rate > 0 { AmountRow(title: d.tax2Name + " \(d.tax2Rate)%", amount: amount(t.tax2)) }
            if t.shipping > 0 { AmountRow(title: L.t("Shipping"), amount: amount(t.shipping)) }
            AmountRow(title: L.t("Total"), amount: amount(t.total))
            if t.paid > 0 { AmountRow(title: L.t("Payment received"), amount: "−" + amount(t.paid)) }
            Divider(); AmountRow(title: L.t("Balance due"), amount: amount(t.balance), bold: true)
        }
    }
    private func taxFields(first: Bool) -> some View {
        HStack {
            TextField(first ? L.t("Tax name") : L.t("Second tax name"), text: first ? $document.tax1Name : $document.tax2Name)
            DecimalField(title: L.t("Tax rate"), value: first ? $document.tax1Rate : $document.tax2Rate); Text("%")
        }.padding(.vertical, 5)
    }
    @ViewBuilder private var payments: some View {
        if d.kind == "invoice" {
            Card {
                HStack { Text(L.t("Payments")).font(.headline); Spacer(); if t.balance > 0 { Button(L.t("Mark paid")) { model.markPaid(d) }.accessibilityIdentifier("editor.markPaid") } }.padding(.bottom, 10)
                ForEach(d.sortedPayments) { p in
                    Button { editingPayment = p; paymentSheet = true } label: {
                        AmountRow(title: L.date(p.date) + " · " + L.method(p.method), amount: amount(p.amount))
                    }.accessibilityIdentifier("payment." + p.id.uuidString).disabled(p.sourcePaymentID != nil)
                }
                Button(L.t("Add payment")) { editingPayment = nil; paymentSheet = true }.padding(.vertical, 9).accessibilityIdentifier("editor.addPayment")
                Button(L.t("Request deposit")) { deposit = true }.padding(.vertical, 9).accessibilityIdentifier("editor.deposit")
                if t.paid > 0 { Button(L.t("Send receipt")) { sendDocument(receipt: true) }.padding(.vertical, 9).accessibilityIdentifier("editor.receipt") }
            }
        } else {
            Card {
                Picker(L.t("Status"), selection: $document.status) { ForEach(["draft","sent","accepted","declined","converted"], id: \.self) { Text(L.status($0)).tag($0) } }.accessibilityIdentifier("estimate.status")
                Button(L.t("Convert to invoice")) { flush(); model.convert(d) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("estimate.convert")
            }
        }
    }
    private var options: some View {
        VStack(spacing: 14) {
            Card { Toggle(L.t("Pay links"), isOn: $document.showPayLinks).accessibilityIdentifier("editor.payLinks") }
            Card {
                DisclosureGroup(L.t("Notes & terms")) {
                    TextField(L.t("Notes"), text: $document.notes, axis: .vertical).padding(.vertical, 10).accessibilityIdentifier("editor.notes")
                    TextField(L.t("Terms"), text: $document.termsText, axis: .vertical).accessibilityIdentifier("editor.termsText")
                }
            }
            Card {
                DisclosureGroup(L.t("Photos")) {
                    ForEach((d.attachments ?? []).sorted { $0.order < $1.order }) { a in AttachmentRow(attachment: a) { model.context.delete(a); d.attachments = (d.attachments ?? []).filter { $0.id != a.id }; flush() } }
                    if model.entitlement.canAttachPhotos {
                        PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) { Label(L.t("Add photos"), systemImage: "photo") }.accessibilityIdentifier("editor.photos")
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { Button(L.t("Take photo")) { camera = true }.padding(.top, 8).accessibilityIdentifier("editor.camera") }
                    } else { Button(L.t("Add photos")) { model.showPaywall = true }.accessibilityIdentifier("editor.photos") }
                }
            }
            Card {
                DisclosureGroup(L.t("Signatures")) {
                    Toggle(L.t("Use my signature"), isOn: $document.showOwnSignature).padding(.vertical, 10)
                    if let bytes = d.clientSignature, let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(height: 70); Button(L.t("Remove signature")) { d.clientSignature = nil; d.signedAt = nil }.accessibilityIdentifier("DocumentEditor.button.211") }
                    Button(L.t("Client signature")) { model.require(model.entitlement.canClientSign) { signature = true } }.accessibilityIdentifier("editor.clientSignature")
                }
            }
            if d.kind == "invoice" {
                Card {
                    DisclosureGroup(L.t("Recurring")) {
                        Picker(L.t("Repeat"), selection: Binding(get: { d.recurrence }, set: { value in model.require(model.entitlement.canUseRecurring) { d.recurrence = value; if value == "none" { d.recurrenceNext = nil } else if d.recurrenceNext == nil { d.recurrenceNext = ReminderPlan.next(d.issueDate, period: value) }; model.reschedule(request: true) } })) {
                            Text(L.t("Never")).tag("none"); Text(L.t("Weekly")).tag("weekly"); Text(L.t("Monthly")).tag("monthly"); Text(L.t("Quarterly")).tag("quarterly")
                        }.accessibilityIdentifier("editor.recurrence")
                        if d.recurrence != "none" { DatePicker(L.t("Next draft"), selection: Binding(get: { d.recurrenceNext ?? Date() }, set: { d.recurrenceNext = $0 }), displayedComponents: .date); Text(L.t("Only drafts and reminders. Nothing is sent automatically.")).font(.caption).foregroundStyle(Design.muted) }
                    }
                }
            }
            if let id = d.linkedDocumentID, let linked = model.liveDocuments.first(where: { $0.id == id }) { Button(linked.number) { flush(); model.selected = linked }.accessibilityIdentifier("editor.linked") }
        }
    }
    private func flush() { saveTask?.cancel(); d.updatedAt = Date(); model.save(); saved = model.error == nil }
    private func move(_ line: LineItem, delta: Int) {
        var values = d.orderedLines; guard let i = values.firstIndex(where: { $0.id == line.id }), values.indices.contains(i + delta) else { return }
        values.swapAt(i, i + delta); for (j,l) in values.enumerated() { l.order = j }; flush()
    }
    private func addPhoto(_ bytes: Data) {
        guard model.entitlement.canAttachPhotos, let image = UIImage(data: bytes), let compressed = image.preparedPhoto()?.jpegData(compressionQuality: 0.82) else { return }
        let attachment = Attachment(data: compressed); attachment.order = (d.attachments ?? []).count
        model.context.insert(attachment); var all = d.attachments ?? []; all.append(attachment); d.attachments = all; flush()
    }
    private func sendDocument(method: String? = nil, receipt: Bool = false, reminder: Bool = false) {
        model.ensureClient(d); flush()
        guard !duplicateNumber, !d.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, d.orderedLines.contains(where: { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { model.error = L.t("Add a client and an item, and use a unique document number."); return }
        let selectedMethod = method ?? model.business.settings.sendMethod
        if ["email","message","share"].contains(selectedMethod) { model.business.settings.sendMethod = selectedMethod; model.save() }
        send = SendPayload.make(d, model: model, method: selectedMethod, receipt: receipt, reminder: reminder)
        model.reschedule(request: true)
    }
}
struct AttachmentRow: View {
    @Bindable var attachment: Attachment
    var remove: () -> Void
    var body: some View {
        VStack {
            if let bytes = attachment.data, let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 160) }
            TextField(L.t("Photo caption"), text: $attachment.caption, axis: .vertical)
            Button(L.t("Remove photo"), action: remove).accessibilityIdentifier("photo.remove." + attachment.id.uuidString)
        }.padding(.vertical, 10)
    }
}
struct CurrencyPicker: View {
    @Binding var value: String
    var body: some View { Picker(L.t("Currency"), selection: $value) { ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("currency.picker") }
}
extension UIImage {
    func preparedPhoto() -> UIImage? {
        let ratio = min(1, 2000 / max(size.width, size.height))
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
