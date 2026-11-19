import Foundation
import StoreKit
import Security

enum TrialMarker {
    static func start(_ date: Date) -> Date {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.hgsldswk.invoices.trial-start", kSecAttrAccount as String: "paid-era"]
        var item: CFTypeRef?
        let read = query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, b in b }
        if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess, let bytes = item as? Data, let string = String(data: bytes, encoding: .utf8), let timestamp = Double(string) { return min(date, Date(timeIntervalSince1970: timestamp)) }
        var insert = query; insert[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
        return date
    }
}
@MainActor final class PurchaseStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var busy = false
    @Published var error: String?
    var onEntitlement: ((Bool, Date?) -> Void)?
    private var updates: Task<Void, Never>?
    var proID: String { Bundle.main.object(forInfoDictionaryKey: "InvoicesProProductID") as? String ?? "com.hgsldswk.invoices.pro" }
    var trialID: String { Bundle.main.object(forInfoDictionaryKey: "InvoicesTrialProductID") as? String ?? "com.hgsldswk.invoices.trial" }
    func start() async {
        guard !Launch.isFree else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, case .verified(let transaction) = result else { continue }
                await self.refresh(); await transaction.finish()
            }
        }
        do { products = try await Product.products(for: [proID,trialID]) } catch { self.error = L.t("The App Store is unavailable. Your invoices are still available.") }
        await refresh()
    }
    func refresh() async {
        var pro = false, trial: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == proID { pro = true }
            if t.productID == trialID { trial = min(trial ?? t.originalPurchaseDate, t.originalPurchaseDate) }
        }
        onEntitlement?(pro, trial)
    }
    func purchase(_ product: Product) async {
        guard !Launch.isFree, !busy else { return }
        busy = true; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { error = L.t("The purchase could not be verified."); return }
                await refresh(); await transaction.finish()
            case .pending: error = L.t("Purchase pending approval.")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { self.error = L.t("Purchase failed. Please try again.") }
    }
    func restore() async {
        guard !Launch.isFree else { return }
        busy = true; defer { busy = false }
        do { try await AppStore.sync(); await refresh() } catch { self.error = L.t("Restore failed. Please try again.") }
    }
    deinit { updates?.cancel() }
}
