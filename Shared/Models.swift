import Foundation
import SwiftData

struct PayLink: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var url = ""
    var validURL: URL? {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host != nil else { return nil }
        return parsed
    }
}
struct BusinessSettings: Codable, Equatable {
    var currencyCode = "USD"
    var paperSize = "letter"
    var defaultTerms = 0
    var defaultNotes = ""
    var defaultTermsText = ""
    var defaultTax1 = Tax(name: "Sales Tax")
    var defaultTax2 = Tax(name: "Tax 2")
    var pricesIncludeTax = false
    var estimateWord = "Estimate"
    var invoiceTitle = "Invoice"
    var invoicePrefix = "INV-"
    var nextInvoiceNumber = 1
    var estimatePrefix = "EST-"
    var nextEstimateNumber = 1
    var payInstructions = ""
    var payLinks: [PayLink] = []
    var template = "Modern"
    var accentColorHex = "1F5B4A"
    var font = "System"
    var showMadeWith = true
    var remindersOn = true
    var pdfLanguage = "en"
    var sendMethod = "email"
    var lastPaymentMethod = "cash"
}
@Model final class Business {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var website: String = ""
    var taxIDLabel: String = "EIN"
    var taxID: String = ""
    @Attribute(.externalStorage) var logo: Data?
    @Attribute(.externalStorage) var signature: Data?
    var settingsData: Data = Data()
    var settings: BusinessSettings {
        get { (try? JSONDecoder().decode(BusinessSettings.self, from: settingsData)) ?? BusinessSettings() }
        set { settingsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    init(region: RegionDefaults = .current) {
        var s = BusinessSettings()
        s.currencyCode = region.currency; s.paperSize = region.paper; s.defaultTax1 = region.tax
        s.estimateWord = region.estimateWord; s.invoiceTitle = region.invoiceTitle
        settingsData = (try? JSONEncoder().encode(s)) ?? Data()
        taxIDLabel = region.taxIDLabel
    }
}
@Model final class Client {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
    var currencyCode: String?
    var defaultTerms: Int?
    var tax1Data: Data?
    var lastUsed: Date = Date()
    @Relationship(inverse: \Document.client) var documents: [Document]?
    var defaultTax: Tax? {
        get { tax1Data.flatMap { try? JSONDecoder().decode(Tax.self, from: $0) } }
        set { tax1Data = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
    init(name: String = "") { self.name = name }
}
@Model final class Item {
    var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    var unitPrice: Decimal = 0
    var unit: String = "ea"
    var taxable: Bool = true
    var lastUsed: Date = Date()
    init(name: String = "", price: Decimal = 0, unit: String = "ea") { self.name = name; unitPrice = price; self.unit = unit }
}
@Model final class Document {
    var id: UUID = UUID()
    var kind: String = "invoice"
    var number: String = ""
    var title: String = "Invoice"
    var issueDate: Date = Date()
    var dueDate: Date?
    var terms: Int = 0
    var status: String = "draft"
    var clientName: String = ""
    var clientEmail: String = ""
    var clientPhone: String = ""
    var clientAddress: String = ""
    var client: Client?
    var currencyCode: String = "USD"
    @Relationship(deleteRule: .cascade, inverse: \LineItem.document) var lines: [LineItem]?
    var discountKind: String = "percent"
    var discountValue: Decimal = 0
    var shipping: Decimal = 0
    var tax1Name: String = "Tax"
    var tax1Rate: Decimal = 0
    var tax2Name: String = "Tax 2"
    var tax2Rate: Decimal = 0
    var tax2Compound: Bool = false
    var pricesIncludeTax: Bool = false
    var depositRequested: Decimal?
    @Relationship(deleteRule: .cascade, inverse: \Payment.document) var payments: [Payment]?
    var notes: String = ""
    var termsText: String = ""
    @Attribute(.externalStorage) var clientSignature: Data?
    var signedAt: Date?
    var showOwnSignature: Bool = true
    var showPayLinks: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \Attachment.document) var attachments: [Attachment]?
    var linkedDocumentID: UUID?
    var depositParentID: UUID?
    var recurrence: String = "none"
    var recurrenceNext: Date?
    var sentAt: Date?
    var deletedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    init(kind: String = "invoice", number: String = "") { self.kind = kind; self.number = number }
    var orderedLines: [LineItem] { (lines ?? []).sorted { $0.order < $1.order } }
    var sortedPayments: [Payment] { (payments ?? []).sorted { $0.date < $1.date } }
    var tax1: Tax { get { Tax(name: tax1Name, rate: tax1Rate) } set { tax1Name = newValue.name; tax1Rate = newValue.rate } }
    var tax2: Tax { get { Tax(name: tax2Name, rate: tax2Rate, compound: tax2Compound) } set { tax2Name = newValue.name; tax2Rate = newValue.rate; tax2Compound = newValue.compound } }
    var moneyInput: MoneyInput {
        MoneyInput(currency: currencyCode, lines: orderedLines.map(\.moneyLine), discount: Discount(kind: discountKind, value: discountValue), tax1: tax1, tax2: tax2, includesTax: pricesIncludeTax, shipping: shipping, payments: sortedPayments.map(\.amount))
    }
    var totals: MoneyResult { Money.calculate(moneyInput) }
    func computedStatus(at now: Date = Date()) -> String { Money.status(stored: status, kind: kind, balance: totals.balance, payments: sortedPayments.map(\.amount), due: dueDate, now: now) }
}
@Model final class LineItem {
    var id: UUID = UUID()
    var order: Int = 0
    var name: String = ""
    var details: String = ""
    var quantity: Decimal = 1
    var unit: String = "ea"
    var unitPrice: Decimal = 0
    var discountKind: String = "percent"
    var discountValue: Decimal = 0
    var taxable: Bool = true
    var document: Document?
    init(name: String = "", price: Decimal = 0, quantity: Decimal = 1) { self.name = name; unitPrice = price; self.quantity = quantity }
    var moneyLine: MoneyLine { MoneyLine(quantity: quantity, unitPrice: unitPrice, discount: Discount(kind: discountKind, value: discountValue), taxable: taxable) }
}
@Model final class Payment {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Decimal = 0
    var method: String = "cash"
    var note: String = ""
    var sourcePaymentID: UUID?
    var document: Document?
    init(amount: Decimal = 0, method: String = "cash") { self.amount = amount; self.method = method }
    static let methods = ["cash", "check", "card", "bankTransfer", "paypal", "venmo", "zelle", "other"]
}
@Model final class Attachment {
    var id: UUID = UUID()
    var caption: String = ""
    var order: Int = 0
    @Attribute(.externalStorage) var data: Data?
    var document: Document?
    init(data: Data? = nil) { self.data = data }
}
