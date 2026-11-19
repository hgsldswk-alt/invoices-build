import Foundation

struct WidgetInvoice: Codable, Identifiable {
    var id: UUID
    var name: String
    var number: String
    var amount: String
}
struct WidgetBalance: Codable, Identifiable {
    var currency: String
    var amount: String
    var id: String { currency }
}
struct WidgetSnapshot: Codable {
    var updated = Date()
    var balances: [WidgetBalance] = []
    var overdue = 0
    var invoices: [WidgetInvoice] = []
    var entitlement = Entitlement()
    static var url: URL? {
        let group = Bundle.main.object(forInfoDictionaryKey: "InvoicesAppGroup") as? String ?? "group.com.hgsldswk.invoices"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget.json")
    }
    static func load() -> WidgetSnapshot { guard let url, let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes) else { return Self() }; return value }
}
