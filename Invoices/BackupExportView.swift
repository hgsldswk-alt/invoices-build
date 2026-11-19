import SwiftUI
import UniformTypeIdentifiers

struct ExportPayload: Identifiable { var id = UUID(); var bytes: Data; var filename: String }
struct BackupExportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var output: ExportPayload?
    @State private var importing = false
    @State private var pending: BackupData?
    @State private var replacing = false
    var body: some View {
        Form {
            Section {
                Button(L.t("Export backup")) { do { output = ExportPayload(bytes: try Backup.export(model.backup), filename: "Invoices-" + Date().formatted(.iso8601.year().month().day()) + ".invoicesbackup") } catch { model.error = L.t("The backup could not be created. Try exporting fewer photos.") } }.accessibilityIdentifier("backup.export")
                Button(L.t("Restore backup")) { importing = true }.accessibilityIdentifier("backup.import")
                Button(L.t("Export CSV")) {
                    do { let b = model.backup; output = ExportPayload(bytes: try ZipStore.archive(CSV.exports(documents: b.documents, clients: b.clients, items: b.items)), filename: "Invoices-CSV.zip") }
                    catch { model.error = L.t("The export could not be created.") }
                }.accessibilityIdentifier("backup.csv")
            } footer: { Text(L.t("Backup includes all documents, clients, items, photos, logo and signatures. Store it somewhere safe.")) }
            if let backup = pending {
                Section(L.t("Backup preview")) {
                    Text(L.f("%d documents · %d clients · %d items", backup.documents.count, backup.clients.count, backup.items.count)).accessibilityIdentifier("backup.preview")
                    Button(L.t("Merge · keep existing IDs")) { restore(backup, replace: false) }.accessibilityIdentifier("backup.merge")
                    if replacing {
                        Text(L.t("Replace removes all current documents, clients and items. Export a backup first.")).foregroundStyle(Design.red)
                        Button(L.t("Replace all data now"), role: .destructive) { restore(backup, replace: true) }.accessibilityIdentifier("backup.replaceConfirm")
                        Button(L.t("Cancel")) { replacing = false }.accessibilityIdentifier("backup.cancel")
                    } else { Button(L.t("Replace all data")) { replacing = true }.accessibilityIdentifier("backup.replace") }
                }
            }
        }.pageBackground().navigationTitle(L.t("Backup & export"))
            .sheet(item: $output) { ExportPicker(bytes: $0.bytes, filename: $0.filename) { output = nil } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pending = try Backup.preview(Backup.readFile(url)); replacing = false
                } catch { model.error = L.t("The backup is invalid, too large or from a newer version.") }
            }
    }
    private func restore(_ backup: BackupData, replace: Bool) { do { try model.restore(backup, replace: replace); pending = nil; replacing = false; model.notify(L.t("Backup restored")) } catch { model.error = L.t("Restore failed. Your previous data was kept.") } }
}
struct CSVImportView: View {
    @EnvironmentObject private var model: AppModel
    var kind: String
    @State private var importing = false
    @State private var preview: CSV.ImportPreview?
    var body: some View {
        Form {
            Button(L.t("Choose CSV")) { model.require(model.entitlement.canImportCSV) { importing = true } }.accessibilityIdentifier("csv.choose")
            if let value = preview {
                Text(L.f("%d rows found", value.count)).accessibilityIdentifier("csv.count")
                Section(L.t("First 5 rows")) {
                    Text(value.headers.joined(separator: " · ")).font(.caption.bold())
                    ForEach(Array(value.firstFive.enumerated()), id: \.offset) { _, row in Text(row.joined(separator: " · ")).font(.caption) }
                }
                Button(L.t("Import")) {
                    guard model.entitlement.canImportCSV else { model.showPaywall = true; return }
                    if kind == "clients" { for client in value.clients() { model.context.insert(client) } }
                    else { for item in value.items() { model.context.insert(item) } }
                    model.save(); preview = nil; model.notify(L.t("CSV imported"))
                }.accessibilityIdentifier("csv.import")
            }
        }.pageBackground().navigationTitle(kind == "clients" ? L.t("Import clients CSV") : L.t("Import items CSV"))
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    preview = try CSV.preview(Backup.readFile(url, limit: 20_000_000))
                } catch { model.error = L.t("Use a UTF-8 CSV with a Name or Description column.") }
            }
    }
}
