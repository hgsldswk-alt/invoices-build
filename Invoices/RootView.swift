import SwiftUI
import StoreKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    @StateObject private var lock = LockManager()
    @State private var started = false
    var body: some View {
        ZStack {
            if sizeClass == .regular { tablet } else { phone }
            if lock.covered || lock.locked {
                Design.background.ignoresSafeArea()
                Button { Task { await lock.unlock() } } label: { Label(L.t("Unlock your invoices"), systemImage: "lock.fill") }.buttonStyle(PrimaryButtonStyle()).padding(40).accessibilityIdentifier("unlock")
            }
        }
        .tint(Design.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) { if !lock.covered && !lock.locked { toast } }
        .sheet(isPresented: $model.showPaywall) { if !Launch.isFree { PaywallView().environmentObject(model) } }
        .sheet(isPresented: $model.showMilestone) { ShareCardScreen(milestone: true).environmentObject(model) }
        .sheet(isPresented: $model.showInvite) { ShareCardScreen(milestone: false).environmentObject(model) }
        .alert(L.t("Could not complete this action"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button(L.t("OK"), role: .cancel) { model.error = nil }.accessibilityIdentifier("RootView.button.24") } message: { Text(model.error ?? "") }
        .onChange(of: phase) { _, value in
            if value != .active { model.save() } else { model.now = Date(); try? model.reload(); model.reschedule(); model.updateSnapshot() }
            lock.transition(value, enabled: model.faceLock && model.entitlement.canUseFaceID)
        }
        .onChange(of: model.shouldReview) { _, value in if value && !model.ephemeral { requestReview(); model.shouldReview = false } }
        .task {
            guard !started else { return }; started = true
            if model.faceLock && model.entitlement.canUseFaceID { lock.locked = true; await lock.unlock() }
            model.reschedule()
            if !model.ephemeral || ProcessInfo.processInfo.arguments.contains("-paywall") { await model.purchases.start() }
        }
    }
    private var phone: some View {
        NavigationStack {
            TabView(selection: $model.section) {
                DocumentListView(kind: "invoice").tabItem { Label(L.t("Invoices"), systemImage: "receipt") }.tag("invoices")
                DocumentListView(kind: "estimate").tabItem { Label(L.t("Estimates"), systemImage: "doc.text") }.tag("estimates")
                ClientsView().tabItem { Label(L.t("Clients"), systemImage: "person") }.tag("clients")
                MoreView().tabItem { Label(L.t("More"), systemImage: "ellipsis") }.tag("more")
            }
            .navigationDestination(item: $model.selected) { document in DocumentEditor(document: document) }
        }
    }
    private var tablet: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(get: { model.section }, set: { if let value = $0 { model.section = value } })) {
                Label(L.t("Invoices"), systemImage: "receipt").tag("invoices").accessibilityIdentifier("tab.invoices")
                Label(L.t("Estimates"), systemImage: "doc.text").tag("estimates").accessibilityIdentifier("tab.estimates")
                Label(L.t("Clients"), systemImage: "person").tag("clients").accessibilityIdentifier("tab.clients")
                Label(L.t("More"), systemImage: "ellipsis").tag("more").accessibilityIdentifier("tab.more")
            }.navigationTitle(L.t("Invoices")).pageBackground()
        } content: {
            NavigationStack {
                Group {
                    switch model.section {
                    case "estimates": DocumentListView(kind: "estimate")
                    case "clients": ClientsView()
                    case "more": MoreView()
                    default: DocumentListView(kind: "invoice")
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let d = model.selected { DocumentEditor(document: d).id(d.id) }
                else { ContentUnavailableView(L.t("Select a document"), systemImage: "doc.text") }
            }
        }
    }
    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(message).font(.subheadline.bold()).accessibilityIdentifier("paid.toast")
                    if model.milestone != nil { Button(L.t("Share card")) { model.showMilestone = true }.font(.caption).accessibilityIdentifier("milestone.share") }
                }
                Spacer()
                if model.undoAction != nil { Button(L.t("Undo")) { model.undoToast() }.accessibilityIdentifier("toast.undo") }
            }.padding(18).foregroundStyle(.white).background(Color(uiColor: .darkGray), in: RoundedRectangle(cornerRadius: 18)).padding(12)
        }
    }
}
