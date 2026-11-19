import Foundation

enum ReviewGate {
    static func shouldRequest(paidCount: Int, alreadyRequested: Bool) -> Bool { paidCount == 3 && !alreadyRequested }
}
enum Milestone {
    static func reached(sentCount: Int, receivedByCurrency: [String: Decimal], seen: Set<String>) -> String? {
        if sentCount >= 100 && !seen.contains("invoices100") { return "invoices100" }
        for currency in receivedByCurrency.keys.sorted() {
            for threshold in [10000, 100000] {
                let key = "\(currency)-\(threshold)"
                if receivedByCurrency[currency, default: 0] >= Decimal(threshold) && !seen.contains(key) { return key }
            }
        }
        return nil
    }
}
