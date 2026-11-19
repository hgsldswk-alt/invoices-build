import SwiftUI
import LocalAuthentication

@main struct InvoicesApp: App {
    @StateObject private var boot = Bootstrap()
    var body: some Scene {
        WindowGroup {
            Group {
                switch boot.state {
                case .loading:
                    ProgressView().tint(Design.accent).accessibilityIdentifier("startup.loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.background.ignoresSafeArea())
                case .ready(let model):
                    RootView().environmentObject(model).modelContainer(model.container)
                case .failed:
                    ContentUnavailableView(L.t("Storage could not be opened"), systemImage: "externaldrive.badge.exclamationmark", description: Text(L.t("Restart the app. Your existing files have not been removed.")))
                        .accessibilityIdentifier("startup.failed")
                }
            }.task { await boot.load() }
                .onOpenURL { boot.open($0) }
        }
    }
}
@MainActor final class Bootstrap: ObservableObject {
    enum State { case loading, ready(AppModel), failed }
    @Published private(set) var state = State.loading
    private let scheduler = ReminderScheduler()
    private var started = false
    private var pendingDocumentID: UUID?

    func load() async {
        guard !started else { return }
        started = true
        do {
            let model = try await AppModel.load(scheduler: scheduler)
            if let id = pendingDocumentID { selectDocument(id, in: model) }
            pendingDocumentID = nil
            state = .ready(model)
        } catch { state = .failed }
    }

    func open(_ url: URL) {
        guard url.scheme == "invoices", let id = UUID(uuidString: url.lastPathComponent) else { return }
        switch state {
        case .loading: pendingDocumentID = id
        case .ready(let model): selectDocument(id, in: model)
        case .failed: break
        }
    }

    private func selectDocument(_ id: UUID, in model: AppModel) {
        if let document = model.liveDocuments.first(where: { $0.id == id }) { model.selected = document }
    }
}
@MainActor final class LockManager: ObservableObject {
    @Published var locked = false
    @Published var covered = false
    @Published var authenticating = false
    private var shields: [UIWindow] = []
    func transition(_ phase: ScenePhase, enabled: Bool) {
        guard enabled else { locked = false; covered = false; refreshShield(); return }
        switch phase {
        case .background: covered = true; locked = true
        case .inactive: covered = true
        case .active: covered = false; if locked { Task { await unlock() } }
        @unknown default: break
        }
        refreshShield()
    }
    func unlock() async {
        guard !authenticating else { return }; authenticating = true; refreshShield()
        defer { authenticating = false; covered = false; refreshShield() }
        let context = LAContext()
        do { locked = !(try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L.t("Unlock your invoices"))) } catch { locked = true }
    }
    private func refreshShield() {
        if covered || locked {
            guard shields.isEmpty else { return }
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
                window.rootViewController = UIHostingController(rootView: LockShield(manager: self))
                window.isHidden = false
                shields.append(window)
            }
        } else {
            for window in shields { window.isHidden = true; window.rootViewController = nil }
            shields.removeAll()
        }
    }
}
struct LockShield: View {
    @ObservedObject var manager: LockManager
    var body: some View {
        ZStack {
            Design.background.ignoresSafeArea()
            if manager.locked {
                Button { Task { await manager.unlock() } } label: { Label(L.t("Unlock your invoices"), systemImage: "lock.fill") }
                    .buttonStyle(PrimaryButtonStyle()).padding(40).disabled(manager.authenticating).accessibilityIdentifier("lock.shield.unlock")
            }
        }
    }
}
