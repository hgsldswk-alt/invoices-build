import SwiftUI
import MessageUI
import UniformTypeIdentifiers

struct SendPayload: Identifiable {
    var id = UUID()
    var bytes: Data
    var filename: String
    var email: String
    var phone: String
    var subject: String
    var body: String
    var method: String
    var marksSent = true
    @MainActor static func make(_ d: Document, model: AppModel, method: String, receipt: Bool = false, reminder: Bool = false) -> SendPayload {
        let kind = L.t(receipt ? "Receipt" : d.title)
        let subject = reminder ? L.f("Payment reminder: %@", d.number) : L.f("%@ %@ from %@", kind, d.number, model.business.name)
        let body = reminder ? L.f("Hello %@,\n\nA friendly reminder that %@ is outstanding for %@. The PDF is attached. Thank you.", d.clientName, Money.format(d.totals.balance, currency: d.currencyCode), d.number) : L.f("Hello %@,\n\nPlease find your %@ attached. Thank you for your business.\n\n%@", d.clientName, kind.lowercased(), model.business.name)
        return SendPayload(bytes: PDFRenderer.render(document: DocumentRecord(d), business: BusinessRecord(model.business), entitlement: model.entitlement, receipt: receipt), filename: PDFRenderer.filename(DocumentRecord(d), receipt: receipt), email: d.clientEmail, phone: d.clientPhone, subject: subject, body: body, method: method, marksSent: !receipt && !reminder)
    }
}
struct SendSheet: View {
    @Environment(\.dismiss) private var dismiss
    var payload: SendPayload
    var completed: (Bool) -> Void
    var body: some View {
        Group {
            if payload.method == "email" && MFMailComposeViewController.canSendMail() {
                MailComposer(payload: payload) { success in completed(success); dismiss() }
            } else if payload.method == "message" && MFMessageComposeViewController.canSendText() && MFMessageComposeViewController.canSendAttachments() {
                MessageComposer(payload: payload) { success in completed(success); dismiss() }
            } else if payload.method == "save" {
                ExportPicker(bytes: payload.bytes, filename: payload.filename) { dismiss() }
            } else if payload.method == "print" {
                PrintScreen(bytes: payload.bytes, name: payload.filename) { dismiss() }
            } else {
                ActivitySheet(bytes: payload.bytes, filename: payload.filename, text: payload.body) { success in completed(success); dismiss() }
            }
        }.ignoresSafeArea()
    }
}
struct MailComposer: UIViewControllerRepresentable {
    var payload: SendPayload
    var completed: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController(); controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(payload.email.isEmpty ? [] : [payload.email]); controller.setSubject(payload.subject); controller.setMessageBody(payload.body, isHTML: false)
        controller.addAttachmentData(payload.bytes, mimeType: "application/pdf", fileName: payload.filename); return controller
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var completed: (Bool) -> Void
        init(completed: @escaping (Bool) -> Void) { self.completed = completed }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { completed(result == .sent && error == nil) }
    }
}
struct MessageComposer: UIViewControllerRepresentable {
    var payload: SendPayload
    var completed: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController(); controller.messageComposeDelegate = context.coordinator
        controller.recipients = payload.phone.isEmpty ? [] : [payload.phone]; controller.body = payload.body
        controller.addAttachmentData(payload.bytes, typeIdentifier: UTType.pdf.identifier, filename: payload.filename); return controller
    }
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var completed: (Bool) -> Void
        init(completed: @escaping (Bool) -> Void) { self.completed = completed }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { completed(result == .sent) }
    }
}
enum ExportFile {
    static func write(_ bytes: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("invoices-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return url
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    var bytes: Data
    var filename: String
    var text = ""
    var completed: (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []
        if !text.isEmpty { items.append(text) }
        if let url = try? ExportFile.write(bytes, filename: filename) { items.append(url); context.coordinator.url = url }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, success, _, _ in
            let isSending = success && activity != .saveToCameraRoll && activity != .print && activity != .copyToPasteboard && activity?.rawValue != "com.apple.DocumentManagerUICore.SaveToFiles"
            completed(isSending)
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    final class Coordinator { var url: URL?; deinit { if let url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } } }
}
struct ExportPicker: UIViewControllerRepresentable {
    var bytes: Data
    var filename: String
    var completed: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let urls: [URL]
        if let url = try? ExportFile.write(bytes, filename: filename) { urls = [url]; context.coordinator.url = url } else { urls = [] }
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completed: () -> Void; var url: URL?
        init(completed: @escaping () -> Void) { self.completed = completed }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completed() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completed() }
        deinit { if let url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
    }
}
struct PrintScreen: UIViewControllerRepresentable {
    var bytes: Data
    var name: String
    var completed: () -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            let printController = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil); info.jobName = name; info.outputType = .general
            printController.printInfo = info; printController.printingItem = bytes
            if UIDevice.current.userInterfaceIdiom == .pad { printController.present(from: CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1), in: controller.view, animated: true) { _, _, _ in completed() } }
            else { printController.present(animated: true) { _, _, _ in completed() } }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
