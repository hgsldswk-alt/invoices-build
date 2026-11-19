import SwiftUI

struct MilestoneCardView: View {
    var sentCount: Int
    var showAmount = false
    var amount = ""
    var body: some View {
        ShareCardArtwork(title: L.f("%d invoices sent", sentCount), subtitle: L.t("$0 in subscription fees"), detail: showAmount ? amount : L.t("Built on hard work. Kept on my iPhone."))
    }
}
struct InviteCardView: View {
    var body: some View { ShareCardArtwork(title: L.t("Unlimited invoices."), subtitle: L.t("No subscription."), detail: L.t("Your data stays on your iPhone.")) }
}
struct ShareCardArtwork: View {
    var title: String
    var subtitle: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Image(systemName: "receipt").font(.system(size: 34, weight: .medium)).foregroundStyle(.white).frame(width: 76, height: 76).background(Color(uiColor: PDFRenderer.color("1F5B4A")), in: RoundedRectangle(cornerRadius: 18))
            Text("Invoices & Estimates\nOffline").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color(uiColor: PDFRenderer.color("1F5B4A")))
            Spacer()
            Text(title).font(.system(size: 43, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 30, weight: .semibold)).foregroundStyle(Color(uiColor: PDFRenderer.color("1F5B4A")))
            Text(detail).font(.system(size: 19)).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Text(L.t("Made for people who work for themselves.")).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                if let url = AppLinks.store, let image = PDFRenderer.qr(url.absoluteString) { Image(uiImage: image).interpolation(.none).resizable().frame(width: 90, height: 90) }
            }
        }.padding(42).frame(width: 540, height: 675).background(Color(uiColor: PDFRenderer.color("F7F6F3"))).foregroundStyle(.black).environment(\.colorScheme, .light)
    }
}
struct ShareCardScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var milestone: Bool
    @State private var showAmount = false
    @State private var output: ExportPayload?
    private var count: Int { model.liveDocuments.filter { $0.kind == "invoice" && $0.sentAt != nil }.count }
    private var received: String {
        let currency = model.business.settings.currencyCode
        let value = model.liveDocuments.filter { $0.kind == "invoice" && $0.currencyCode == currency }.reduce(Decimal(0)) { $0 + $1.sortedPayments.filter { $0.sourcePaymentID == nil }.reduce(0) { $0 + $1.amount } }
        return Money.format(value, currency: currency)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card.scaleEffect(0.55).frame(width: 297, height: 372)
                    if milestone { Toggle(L.t("Show received amount"), isOn: $showAmount).accessibilityIdentifier("share.amount") }
                    Button(L.t("Share card")) {
                        let renderer = ImageRenderer(content: card); renderer.scale = 2
                        if let data = renderer.uiImage?.pngData() { output = ExportPayload(bytes: data, filename: milestone ? "Invoices-milestone.png" : "Invoices-invite.png") }
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("share.card")
                }.padding(24)
            }.pageBackground().navigationTitle(milestone ? L.t("Milestone") : L.t("Tell a fellow tradesperson"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("Close")) { dismiss() }.accessibilityIdentifier("ShareCards.button.58") } }
                .sheet(item: $output) { ActivitySheet(bytes: $0.bytes, filename: $0.filename, text: L.t("Unlimited invoices. No subscription. Your data stays on your iPhone.") + " #Invoices #SelfEmployed" + (AppLinks.store.map { " " + $0.absoluteString } ?? "")) }
        }
    }
    @ViewBuilder private var card: some View {
        if milestone { MilestoneCardView(sentCount: count, showAmount: showAmount, amount: received) }
        else { InviteCardView() }
    }
}
