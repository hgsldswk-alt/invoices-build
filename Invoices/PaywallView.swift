import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if !Launch.isFree {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(L.t("Invoices Pro")).font(.largeTitle.bold()).accessibilityIdentifier("paywall.title")
                            Text(L.t("One purchase. No subscription.")).font(.title3)
                            Text(L.t("Extra templates, payment QR codes, photos, client signatures, reminders, recurring drafts, reports, statements, iCloud, Face ID and widgets."))
                            Text(L.t("Your invoices stay available. Always.")).font(.headline)
                            Text(L.t("Keep creating, editing, sending and exporting unlimited documents, even after the trial ends."))
                            Text(L.f("%d days left in your 30-day trial", model.entitlement.remainingDays(at: model.now))).foregroundStyle(Design.muted)
                            ForEach(model.purchases.products.sorted { $0.id < $1.id }, id: \.id) { product in
                                Button { Task { await model.purchases.purchase(product) } } label: {
                                    Text(product.id.hasSuffix(".pro") ? L.f("Buy once · %@", product.displayPrice) : L.t("Claim 30-day trial"))
                                }.buttonStyle(PrimaryButtonStyle()).disabled(model.purchases.busy).accessibilityIdentifier(product.id.hasSuffix(".pro") ? "paywall.buy" : "paywall.trial")
                            }
                            if model.purchases.products.isEmpty { Text(L.t("Connect to the App Store to load purchase options.")).font(.caption) }
                            Text(L.t("No automatic renewal or charge when the trial ends.")).font(.caption).foregroundStyle(Design.muted)
                            Button(L.t("Restore purchases")) { Task { await model.purchases.restore() } }.disabled(model.purchases.busy).accessibilityIdentifier("paywall.restore")
                            if let error = model.purchases.error { Text(error).foregroundStyle(Design.red).font(.caption) }
                            if model.entitlement.purchasedPro { Text(L.t("Purchase restored. All features are unlocked.")).foregroundStyle(Design.accent) }
                        }.padding(24)
                    }.pageBackground().toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("paywall.close") } }
                }
            }
        }
    }
}
