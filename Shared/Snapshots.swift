import Foundation
import SwiftData

struct BusinessRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var email: String
    var phone: String
    var address: String
    var website: String
    var taxIDLabel: String
    var taxID: String
    var logo: Data?
    var signature: Data?
    var settings: BusinessSettings
    init(_ b: Business) {
        id = b.id; name = b.name; email = b.email; phone = b.phone; address = b.address; website = b.website
        taxIDLabel = b.taxIDLabel; taxID = b.taxID; logo = b.logo; signature = b.signature; settings = b.settings
    }
    func apply(to b: Business) {
        b.id = id; b.name = name; b.email = email; b.phone = phone; b.address = address; b.website = website
        b.taxIDLabel = taxIDLabel; b.taxID = taxID; b.logo = logo; b.signature = signature; b.settings = settings
    }
}
struct ClientRecord: Codable, Equatable {
    var id: UUID; var name: String; var email: String; var phone: String; var address: String; var notes: String
    var currencyCode: String?; var defaultTerms: Int?; var tax: Tax?; var lastUsed: Date
    init(_ c: Client) {
        id = c.id; name = c.name; email = c.email; phone = c.phone; address = c.address; notes = c.notes
        currencyCode = c.currencyCode; defaultTerms = c.defaultTerms; tax = c.defaultTax; lastUsed = c.lastUsed
    }
    func make() -> Client {
        let c = Client(name: name); c.id = id; c.email = email; c.phone = phone; c.address = address; c.notes = notes
        c.currencyCode = currencyCode; c.defaultTerms = defaultTerms; c.defaultTax = tax; c.lastUsed = lastUsed; return c
    }
}
struct ItemRecord: Codable, Equatable {
    var id: UUID; var name: String; var details: String; var price: Decimal; var unit: String; var taxable: Bool; var lastUsed: Date
    init(_ item: Item) { id = item.id; name = item.name; details = item.details; price = item.unitPrice; unit = item.unit; taxable = item.taxable; lastUsed = item.lastUsed }
    func make() -> Item { let i = Item(name: name, price: price, unit: unit); i.id = id; i.details = details; i.taxable = taxable; i.lastUsed = lastUsed; return i }
}
struct LineRecord: Codable, Equatable, Identifiable {
    var id = UUID(); var order = 0; var name = ""; var details = ""; var quantity: Decimal = 1; var unit = "ea"; var price: Decimal = 0
    var discount = Discount(); var taxable = true
    init() {}
    init(_ l: LineItem) { id = l.id; order = l.order; name = l.name; details = l.details; quantity = l.quantity; unit = l.unit; price = l.unitPrice; discount = Discount(kind: l.discountKind, value: l.discountValue); taxable = l.taxable }
    func apply(to l: LineItem) { l.id = id; l.name = name; l.unitPrice = price; l.quantity = quantity; l.order = order; l.details = details; l.unit = unit; l.discountKind = discount.kind; l.discountValue = discount.value; l.taxable = taxable }
    func make() -> LineItem { let l = LineItem(); apply(to: l); return l }
    var moneyLine: MoneyLine { MoneyLine(quantity: quantity, unitPrice: price, discount: discount, taxable: taxable) }
}
struct PaymentRecord: Codable, Equatable, Identifiable {
    var id: UUID; var date: Date; var amount: Decimal; var method: String; var note: String; var sourcePaymentID: UUID?
    init(_ p: Payment) { id = p.id; date = p.date; amount = p.amount; method = p.method; note = p.note; sourcePaymentID = p.sourcePaymentID }
    func apply(to p: Payment) { p.id = id; p.amount = amount; p.method = method; p.date = date; p.note = note; p.sourcePaymentID = sourcePaymentID }
    func make() -> Payment { let p = Payment(); apply(to: p); return p }
}
struct AttachmentRecord: Codable, Equatable, Identifiable {
    var id: UUID; var caption: String; var order: Int; var data: Data?
    init(_ a: Attachment) { id = a.id; caption = a.caption; order = a.order; data = a.data }
    func apply(to a: Attachment) { a.id = id; a.data = data; a.caption = caption; a.order = order }
    func make() -> Attachment { let a = Attachment(); apply(to: a); return a }
}
struct DocumentRecord: Codable, Equatable, Identifiable {
    var id: UUID; var kind: String; var number: String; var title: String; var issueDate: Date; var dueDate: Date?; var terms: Int; var status: String
    var clientID: UUID?; var clientName: String; var clientEmail: String; var clientPhone: String; var clientAddress: String; var currency: String
    var lines: [LineRecord]; var discount: Discount; var shipping: Decimal; var tax1: Tax; var tax2: Tax; var includesTax: Bool
    var depositRequested: Decimal?; var payments: [PaymentRecord]; var notes: String; var termsText: String
    var clientSignature: Data?; var signedAt: Date?; var showOwnSignature: Bool; var showPayLinks: Bool; var attachments: [AttachmentRecord]
    var linkedDocumentID: UUID?; var depositParentID: UUID?; var recurrence: String; var recurrenceNext: Date?
    var sentAt: Date?; var deletedAt: Date?; var createdAt: Date; var updatedAt: Date
    init(_ d: Document) {
        id = d.id; kind = d.kind; number = d.number; title = d.title; issueDate = d.issueDate; dueDate = d.dueDate; terms = d.terms; status = d.status
        clientID = d.client?.id; clientName = d.clientName; clientEmail = d.clientEmail; clientPhone = d.clientPhone; clientAddress = d.clientAddress; currency = d.currencyCode
        lines = d.orderedLines.map(LineRecord.init); discount = Discount(kind: d.discountKind, value: d.discountValue); shipping = d.shipping; tax1 = d.tax1; tax2 = d.tax2; includesTax = d.pricesIncludeTax
        depositRequested = d.depositRequested; payments = d.sortedPayments.map(PaymentRecord.init); notes = d.notes; termsText = d.termsText
        clientSignature = d.clientSignature; signedAt = d.signedAt; showOwnSignature = d.showOwnSignature; showPayLinks = d.showPayLinks
        attachments = (d.attachments ?? []).sorted { $0.order < $1.order }.map(AttachmentRecord.init)
        linkedDocumentID = d.linkedDocumentID; depositParentID = d.depositParentID; recurrence = d.recurrence; recurrenceNext = d.recurrenceNext
        sentAt = d.sentAt; deletedAt = d.deletedAt; createdAt = d.createdAt; updatedAt = d.updatedAt
    }
    var moneyInput: MoneyInput { MoneyInput(currency: currency, lines: lines.map(\.moneyLine), discount: discount, tax1: tax1, tax2: tax2, includesTax: includesTax, shipping: shipping, payments: payments.map(\.amount)) }
    var totals: MoneyResult { Money.calculate(moneyInput) }
    func apply(to d: Document, context: ModelContext, clients: [Client]) {
        d.id = id; d.kind = kind; d.number = number; d.title = title; d.issueDate = issueDate; d.dueDate = dueDate; d.terms = terms; d.status = status
        d.client = clients.first { $0.id == clientID }; d.clientName = clientName; d.clientEmail = clientEmail; d.clientPhone = clientPhone; d.clientAddress = clientAddress; d.currencyCode = currency
        let oldLines = d.lines ?? []
        let lineIDs = Set(lines.map(\.id))
        for line in oldLines where !lineIDs.contains(line.id) { context.delete(line) }
        d.lines = lines.map { record in
            if let l = oldLines.first(where: { $0.id == record.id }) { record.apply(to: l); return l }
            let l = record.make(); context.insert(l); return l
        }
        d.discountKind = discount.kind; d.discountValue = discount.value; d.shipping = shipping; d.tax1 = tax1; d.tax2 = tax2; d.pricesIncludeTax = includesTax
        d.depositRequested = depositRequested
        let oldPayments = d.payments ?? []
        let paymentIDs = Set(payments.map(\.id))
        for p in oldPayments where !paymentIDs.contains(p.id) { context.delete(p) }
        d.payments = payments.map { record in
            if let p = oldPayments.first(where: { $0.id == record.id }) { record.apply(to: p); return p }
            let p = record.make(); context.insert(p); return p
        }
        d.notes = notes; d.termsText = termsText; d.clientSignature = clientSignature; d.signedAt = signedAt; d.showOwnSignature = showOwnSignature; d.showPayLinks = showPayLinks
        let oldAttachments = d.attachments ?? []
        let attachmentIDs = Set(attachments.map(\.id))
        for a in oldAttachments where !attachmentIDs.contains(a.id) { context.delete(a) }
        d.attachments = attachments.map { record in
            if let a = oldAttachments.first(where: { $0.id == record.id }) { record.apply(to: a); return a }
            let a = record.make(); context.insert(a); return a
        }
        d.linkedDocumentID = linkedDocumentID; d.depositParentID = depositParentID; d.recurrence = recurrence; d.recurrenceNext = recurrenceNext
        d.sentAt = sentAt; d.deletedAt = deletedAt; d.createdAt = createdAt; d.updatedAt = updatedAt
    }
}
