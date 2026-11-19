import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
    static func term(_ days: Int) -> String { days == 0 ? t("Due on receipt") : f("Net %d", days) }
    static func status(_ value: String) -> String {
        switch value {
        case "sent": return t("Sent")
        case "paid": return t("Paid")
        case "partial": return t("Partially paid")
        case "overdue": return t("Overdue")
        case "accepted": return t("Accepted")
        case "declined": return t("Declined")
        case "converted": return t("Converted")
        default: return t("Draft")
        }
    }
    static func method(_ value: String) -> String {
        switch value {
        case "check": return t("Check")
        case "card": return t("Card")
        case "bankTransfer": return t("Bank transfer")
        case "paypal": return "PayPal"
        case "venmo": return "Venmo"
        case "zelle": return "Zelle"
        case "other": return t("Other")
        default: return t("Cash")
        }
    }
}
enum AppLinks {
    static var store: URL? {
        let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? ""
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        var c = URLComponents(); c.scheme = "https"; c.host = "apps.apple.com"; c.path = "/app/id" + id
        return c.url
    }
    static func document(_ id: UUID) -> URL? { URL(string: "invoices:document/" + id.uuidString) }
}
struct PDFWords {
    var language: String
    func t(_ key: String) -> String {
        guard language != "en", let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
    var locale: Locale { Locale(identifier: language == "en" ? "en_US" : language == "zh-Hant" ? "zh_TW" : "zh_CN") }
    func date(_ value: Date) -> String { let f = DateFormatter(); f.locale = locale; f.dateStyle = .medium; return f.string(from: value) }
}
