import SwiftUI

enum SettingsRoute: String, CaseIterable, Identifiable {
    case business, defaults, payments, style, reminders, cloud, lock, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .business: return L.t("Business")
        case .defaults: return L.t("Invoice defaults")
        case .payments: return L.t("Payment options")
        case .style: return L.t("Template & style")
        case .reminders: return L.t("Reminders")
        case .cloud: return L.t("iCloud sync")
        case .lock: return L.t("Face ID lock")
        case .about: return L.t("About")
        }
    }
}
struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var reports = false
    var body: some View {
        List {
            Section {
                NavigationLink(L.t("Items")) { ItemsView() }.accessibilityIdentifier("more.items")
                NavigationLink(L.t("Reports")) { ReportsView() }.accessibilityIdentifier("more.reports")
                NavigationLink(L.t("Recently Deleted")) { RecentlyDeletedView() }.accessibilityIdentifier("more.deleted")
            }
            Section {
                ForEach(SettingsRoute.allCases.filter { $0 != .about }) { route in NavigationLink(route.title) { SettingsPage(route: route) }.accessibilityIdentifier("more." + route.rawValue) }
                NavigationLink(L.t("Backup & export")) { BackupExportView() }.accessibilityIdentifier("more.backup")
            }
            Section {
                Button(L.t("Tell a fellow tradesperson")) { model.showInvite = true }.accessibilityIdentifier("more.invite")
                if let url = AppLinks.store { Link(L.t("Rate"), destination: url).accessibilityIdentifier("more.rate") }
                NavigationLink(L.t("About")) { SettingsPage(route: .about) }.accessibilityIdentifier("more.about")
                if !Launch.isFree { Button(L.t("Pro")) { model.showPaywall = true }.accessibilityIdentifier("more.pro") }
            }
        }.pageBackground().navigationTitle(L.t("More"))
            .navigationDestination(isPresented: $reports) { ReportsView() }
            .onAppear { if ProcessInfo.processInfo.arguments.contains("-reports") { reports = true } }
    }
}
struct RecentlyDeletedView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Text(L.t("Deleted documents can be restored for 30 days.")).font(.caption).foregroundStyle(Design.muted)
            ForEach(model.documents.filter { $0.deletedAt != nil }) { d in HStack { VStack(alignment: .leading) { Text(d.number); Text(d.clientName).font(.caption) }; Spacer(); Button(L.t("Restore")) { d.deletedAt = nil; model.syncDepositPayments(); model.save() }.accessibilityIdentifier("restore." + d.number) } }
        }.pageBackground().navigationTitle(L.t("Recently Deleted"))
    }
}
