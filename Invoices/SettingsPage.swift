import SwiftUI
import PhotosUI

struct SettingsPage: View {
    @EnvironmentObject private var model: AppModel
    var route: SettingsRoute
    @State private var logo: PhotosPickerItem?
    @State private var signature = false
    @State private var saveTask: Task<Void, Never>?
    @State private var color = Color(uiColor: PDFRenderer.color("1F5B4A"))
    @State private var code = ""
    @State private var sharedCode = ""
    @State private var pasteCount = -1
    @State private var hasPaste = false
    @State private var share: TextShare?
    private var settings: BusinessSettings { model.business.settings }
    var body: some View {
        Form {
            switch route {
            case .business: businessFields
            case .defaults: defaultFields
            case .payments: paymentFields
            case .style: styleFields
            case .reminders: reminderFields
            case .cloud: cloudFields
            case .lock: lockFields
            case .about: aboutFields
            }
        }.pageBackground().navigationTitle(route.title)
            .onChange(of: BusinessRecord(model.business)) { _, _ in
                saveTask?.cancel(); saveTask = Task { try? await Task.sleep(nanoseconds: 500_000_000); guard !Task.isCancelled else { return }; model.save() }
            }
            .onDisappear { saveTask?.cancel(); model.save(); model.reschedule() }
            .onChange(of: logo) { _, value in Task { if let bytes = try? await value?.loadTransferable(type: Data.self), let image = UIImage(data: bytes) { model.business.logo = image.preparedPhoto()?.pngData(); model.save() } } }
            .onChange(of: color) { _, value in if let rgb = UIColor(value).cgColor.components, rgb.count >= 3 { model.business.settings.accentColorHex = String(format: "%02X%02X%02X", Int(rgb[0] * 255), Int(rgb[1] * 255), Int(rgb[2] * 255)) } }
            .onAppear { color = Color(uiColor: PDFRenderer.color(settings.accentColorHex)); refreshPaste() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refreshPaste() }
            .sheet(isPresented: $signature) { SignatureSheet(title: L.t("My signature")) { bytes in model.business.signature = bytes; model.save() } }
            .sheet(item: $share) { StyleCodeScreen(code: $0.text) }
    }
    private var businessFields: some View {
        Group {
            TextField(L.t("Business name"), text: $model.business.name).accessibilityIdentifier("business.name")
            TextField(L.t("Email"), text: $model.business.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            TextField(L.t("Phone"), text: $model.business.phone).keyboardType(.phonePad)
            TextField(L.t("Address"), text: $model.business.address, axis: .vertical)
            TextField(L.t("Website"), text: $model.business.website).keyboardType(.URL).textInputAutocapitalization(.never)
            TextField(L.t("Tax ID label"), text: $model.business.taxIDLabel)
            TextField(L.t("Tax ID"), text: $model.business.taxID)
            Section(L.t("Logo")) {
                if let data = model.business.logo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(height: 80); Button(L.t("Remove logo")) { model.business.logo = nil }.accessibilityIdentifier("SettingsPage.button.51") }
                PhotosPicker(selection: $logo, matching: .images) { Text(L.t("Choose logo")) }.accessibilityIdentifier("business.logo")
            }
            Section(L.t("My signature")) {
                if let bytes = model.business.signature, let image = UIImage(data: bytes) { Image(uiImage: image).resizable().scaledToFit().frame(height: 70) }
                Button(L.t("Draw signature")) { signature = true }.accessibilityIdentifier("business.signature")
            }
        }
    }
    private var defaultFields: some View {
        Group {
            CurrencyPicker(value: $model.business.settings.currencyCode)
            Picker(L.t("Paper size"), selection: $model.business.settings.paperSize) { Text("Letter").tag("letter"); Text("A4").tag("a4") }
            Picker(L.t("PDF language"), selection: $model.business.settings.pdfLanguage) { Text("English").tag("en"); Text(L.t("Simplified Chinese")).tag("zh-Hans"); Text(L.t("Traditional Chinese")).tag("zh-Hant") }.accessibilityIdentifier("defaults.pdfLanguage")
            Picker(L.t("Invoice title"), selection: $model.business.settings.invoiceTitle) { ForEach(["Invoice","Tax Invoice","Bill"], id: \.self) { Text(L.t($0)).tag($0) } }
            Picker(L.t("Estimate wording"), selection: $model.business.settings.estimateWord) { Text(L.t("Estimate")).tag("Estimate"); Text(L.t("Quote")).tag("Quote") }
            Section(L.t("Numbering")) {
                TextField(L.t("Invoice prefix"), text: $model.business.settings.invoicePrefix)
                Stepper(L.f("Next invoice: %d", settings.nextInvoiceNumber), value: $model.business.settings.nextInvoiceNumber, in: 1...999999)
                TextField(L.t("Estimate prefix"), text: $model.business.settings.estimatePrefix)
                Stepper(L.f("Next estimate: %d", settings.nextEstimateNumber), value: $model.business.settings.nextEstimateNumber, in: 1...999999)
            }
            Section(L.t("Payment terms")) { Stepper(L.term(settings.defaultTerms), value: $model.business.settings.defaultTerms, in: 0...365) }
            Section(L.t("Taxes")) {
                TextField(L.t("Tax name"), text: $model.business.settings.defaultTax1.name)
                DecimalField(title: L.t("Tax rate"), value: $model.business.settings.defaultTax1.rate)
                TextField(L.t("Second tax name"), text: $model.business.settings.defaultTax2.name)
                DecimalField(title: L.t("Second tax rate"), value: $model.business.settings.defaultTax2.rate)
                Toggle(L.t("Compound second tax"), isOn: $model.business.settings.defaultTax2.compound)
                Toggle(L.t("Prices include tax"), isOn: $model.business.settings.pricesIncludeTax)
            }
            TextField(L.t("Default notes"), text: $model.business.settings.defaultNotes, axis: .vertical)
            TextField(L.t("Default terms"), text: $model.business.settings.defaultTermsText, axis: .vertical)
        }
    }
    private var paymentFields: some View {
        Group {
            TextField(L.t("Payment instructions"), text: $model.business.settings.payInstructions, axis: .vertical).accessibilityIdentifier("payments.instructions")
            Section(L.t("Payment links · up to 3")) {
                ForEach(settings.payLinks) { link in
                    TextField(L.t("Link title"), text: linkBinding(link.id, \.title))
                    TextField(L.t("HTTPS URL"), text: linkBinding(link.id, \.url)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if link.validURL == nil && !link.url.isEmpty { Text(L.t("Enter a valid HTTPS link.")).font(.caption).foregroundStyle(Design.red) }
                    Button(L.t("Remove link")) { model.business.settings.payLinks.removeAll { $0.id == link.id } }.accessibilityIdentifier("payments.remove." + link.id.uuidString)
                }
                if settings.payLinks.count < 3 { Button(L.t("Add link")) { model.business.settings.payLinks.append(PayLink()) }.accessibilityIdentifier("payments.addLink") }
            }
            Picker(L.t("Default send method"), selection: $model.business.settings.sendMethod) { Text(L.t("Email")).tag("email"); Text(L.t("Message")).tag("message"); Text(L.t("Share…")).tag("share") }
            Text(L.t("Links open your own payment provider. The app never handles money.")).font(.caption).foregroundStyle(Design.muted)
        }
    }
    private func linkBinding(_ id: UUID, _ path: WritableKeyPath<PayLink, String>) -> Binding<String> {
        Binding(get: { settings.payLinks.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in var links = settings.payLinks; if let i = links.firstIndex(where: { $0.id == id }) { links[i][keyPath: path] = value; model.business.settings.payLinks = links } })
    }
    private var styleFields: some View {
        Group {
            Picker(L.t("Template"), selection: Binding(get: { settings.template }, set: { template in model.require(model.entitlement.canUseTemplate(template)) { model.business.settings.template = template } })) { ForEach(ShareCode.templates, id: \.self) { Text(L.t($0)).tag($0) } }.accessibilityIdentifier("style.template")
            ColorPicker(L.t("Accent color"), selection: $color, supportsOpacity: false).accessibilityIdentifier("style.color")
            TextField(L.t("Hex color"), text: $model.business.settings.accentColorHex).textInputAutocapitalization(.characters)
            Picker(L.t("Font"), selection: $model.business.settings.font) { Text(L.t("System")).tag("System"); Text(L.t("Serif")).tag("Serif") }
            Toggle(L.t("Made with footer"), isOn: Binding(get: { settings.showMadeWith }, set: { value in model.require(value || model.entitlement.canHideMadeWith) { model.business.settings.showMadeWith = value } })).accessibilityIdentifier("style.madeWith")
            Section {
                Button(L.t("Share my template")) { do { let value = StyleCode(template: settings.template, accent: settings.accentColorHex, font: settings.font, notes: settings.defaultNotes, terms: settings.defaultTermsText, estimateWord: settings.estimateWord); sharedCode = try ShareCode.encode(value); share = TextShare(text: sharedCode) } catch { model.error = L.t("Could not create a style code.") } }.accessibilityIdentifier("style.share")
                Text(L.t("Only style, notes and terms are shared. Review that text before sharing.")).font(.caption).foregroundStyle(Design.muted)
                TextField(L.t("Invoices style code"), text: $code, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("style.code")
                if hasPaste { PasteButton(payloadType: String.self) { strings in code = strings.first ?? "" }.accessibilityIdentifier("style.paste") }
                Button(L.t("Import style")) { importStyle() }.disabled(code.isEmpty).accessibilityIdentifier("style.import")
            }
        }
    }
    private var reminderFields: some View {
        Group {
            Toggle(L.t("Payment reminders"), isOn: Binding(get: { settings.remindersOn }, set: { value in model.require(!value || model.entitlement.canUseReminders) { model.business.settings.remindersOn = value; model.reschedule(request: value) } })).accessibilityIdentifier("reminders.enabled")
            Text(L.t("Reminders arrive at 9:00 on the due date, then 3 and 7 days later. Only you receive them.")).font(.caption).foregroundStyle(Design.muted)
            if model.scheduler.denied { Button(L.t("Notifications are off · Open Settings")) { openSystemSettings() }.accessibilityIdentifier("reminders.settings") }
        }
    }
    private var cloudFields: some View {
        Group {
            Toggle(L.t("iCloud sync"), isOn: Binding(get: { model.cloudEnabled }, set: { value in model.require(!value || model.entitlement.canUseICloud) { model.preferences.set(value, forKey: "cloudEnabled"); model.objectWillChange.send() } })).accessibilityIdentifier("cloud.enabled")
            Text(model.cloudStatus).font(.caption)
            Text(L.t("Changes to this switch take effect the next time you open the app.")).font(.caption).foregroundStyle(Design.muted)
        }
    }
    private var lockFields: some View {
        Group {
            Toggle(L.t("Face ID lock"), isOn: Binding(get: { model.faceLock }, set: { value in model.require(!value || model.entitlement.canUseFaceID) { model.preferences.set(value, forKey: "faceLock"); model.objectWillChange.send() } })).accessibilityIdentifier("lock.enabled")
            Text(L.t("Use Face ID, Touch ID or your device passcode. The app is covered in the app switcher.")).font(.caption).foregroundStyle(Design.muted)
        }
    }
    private var aboutFields: some View {
        Group {
            Text("Invoices & Estimates Offline").font(.headline)
            Text(L.t("No account. No servers. Your data stays on your iPhone and your own iCloud."))
            Text(L.t("Unlimited invoices. No subscription."))
            Text(L.t("This app creates business documents. It does not issue government tax receipts or submit electronic invoices."))
            Text("1.0").foregroundStyle(Design.muted)
        }
    }
    private func refreshPaste() { let paste = UIPasteboard.general; guard paste.changeCount != pasteCount else { return }; pasteCount = paste.changeCount; hasPaste = paste.hasStrings }
    private func importStyle() {
        do {
            let style = try ShareCode.decode(code)
            guard model.entitlement.canUseTemplate(style.template) else { model.showPaywall = true; return }
            model.business.settings.template = style.template; model.business.settings.accentColorHex = style.accent; model.business.settings.font = style.font ?? "System"
            model.business.settings.defaultNotes = style.notes; model.business.settings.defaultTermsText = style.terms; model.business.settings.estimateWord = style.estimateWord
            color = Color(uiColor: PDFRenderer.color(style.accent)); model.save(); model.notify(L.t("Style imported"))
        } catch { model.error = L.t("That style code is invalid or from a newer version.") }
    }
    private func openSystemSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
}
struct TextShare: Identifiable { var id = UUID(); var text: String }
struct TextActivitySheet: UIViewControllerRepresentable {
    var text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct StyleCodeScreen: View {
    @Environment(\.dismiss) private var dismiss
    var code: String
    @State private var share = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let qr = PDFRenderer.qr(code) { Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 250).padding().background(.white) }
                    Text(code).font(.caption.monospaced()).textSelection(.enabled)
                    Button(L.t("Share my template")) { share = true }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("style.shareCode")
                }.padding(24)
            }.pageBackground().navigationTitle(L.t("Invoices style code"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("style.closeCode") } }
                .sheet(isPresented: $share) { TextActivitySheet(text: code) }
        }
    }
}
