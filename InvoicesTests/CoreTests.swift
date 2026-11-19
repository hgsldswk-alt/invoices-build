import XCTest
import SwiftData
import PDFKit
@testable import Invoices

final class MoneyTests: XCTestCase {
    func dec(_ text: String) -> Decimal { Decimal(string: text)! }
    func testLineDiscountAndConventionalRounding() {
        let result = Money.calculate(MoneyInput(lines: [MoneyLine(quantity: 2, unitPrice: 15, discount: Discount(value: 10)),MoneyLine(unitPrice: dec("1.005"))]))
        XCTAssertEqual(result.lineAmounts, [27,dec("1.01")]); XCTAssertEqual(result.total, dec("28.01"))
        XCTAssertEqual(Money.round(dec("1.005"), currency: "USD"), dec("1.01"))
        XCTAssertEqual(Money.round(dec("2.5"), currency: "JPY"), 3)
    }
    func testFixedLineDiscountCannotMakeNegative() {
        let result = Money.calculate(MoneyInput(lines: [MoneyLine(quantity: 1, unitPrice: 10, discount: Discount(kind: "amount", value: 20))]))
        XCTAssertEqual(result.total, 0)
    }
    func testProportionalAllocationAndLastLineRemainder() {
        let result = Money.calculate(MoneyInput(lines: [MoneyLine(unitPrice: 1),MoneyLine(unitPrice: 1, taxable: false),MoneyLine(unitPrice: 1)], discount: Discount(kind: "amount", value: 1), tax1: Tax(rate: 10)))
        XCTAssertEqual(result.allocatedDiscounts, [dec("0.33"),dec("0.33"),dec("0.34")])
        XCTAssertEqual(result.allocatedDiscounts.reduce(0,+), 1)
        XCTAssertEqual(result.tax1, dec("0.14")); XCTAssertEqual(result.total, dec("2.14"))
    }
    func testIndependentAndCompoundTaxesAndUntaxedShipping() {
        var input = MoneyInput(lines: [MoneyLine(unitPrice: 100),MoneyLine(unitPrice: 50, taxable: false)], tax1: Tax(rate: 5), tax2: Tax(rate: 10), shipping: 10)
        let ordinary = Money.calculate(input); XCTAssertEqual(ordinary.tax1,5); XCTAssertEqual(ordinary.tax2,10); XCTAssertEqual(ordinary.total,175)
        input.tax2.compound = true
        let compound = Money.calculate(input); XCTAssertEqual(compound.tax2,dec("10.5")); XCTAssertEqual(compound.total,dec("175.5"))
    }
    func testManySmallLinesCannotReceiveNegativeNetAfterDiscount() {
        let input = MoneyInput(lines: Array(repeating: MoneyLine(unitPrice: dec("0.01")), count: 100), discount: Discount(kind:"amount",value:dec("0.49")), tax1:Tax(rate:10))
        let result = Money.calculate(input)
        XCTAssertEqual(result.allocatedDiscounts.reduce(0,+),dec("0.49"))
        XCTAssertTrue(zip(result.lineAmounts,result.allocatedDiscounts).allSatisfy { $0.0 >= $0.1 })
        XCTAssertEqual(result.net,dec("0.51"))
    }
    func testIncludedSingleAndDoubleTax() {
        var input = MoneyInput(lines: [MoneyLine(unitPrice: 120)], tax1: Tax(rate: 20), includesTax: true)
        XCTAssertEqual(Money.calculate(input).net,100); XCTAssertEqual(Money.calculate(input).tax1,20)
        input.lines = [MoneyLine(unitPrice: 115)]; input.tax1.rate = 5; input.tax2.rate = 10
        XCTAssertEqual(Money.calculate(input).net,100); XCTAssertEqual(Money.calculate(input).tax2,10)
        input.tax2.compound = true; input.lines[0].unitPrice = dec("115.5")
        let compound = Money.calculate(input); XCTAssertEqual(compound.net,100); XCTAssertEqual(compound.tax1,5); XCTAssertEqual(compound.tax2,dec("10.5")); XCTAssertEqual(compound.total,dec("115.5"))
    }
    func testTaxRoundingPerLine() {
        let result = Money.calculate(MoneyInput(lines: [MoneyLine(unitPrice: dec("0.05")),MoneyLine(unitPrice: dec("0.05"))], tax1: Tax(rate: 10)))
        XCTAssertEqual(result.tax1,dec("0.02"))
    }
    func testJPYAndPartialBalance() {
        let result = Money.calculate(MoneyInput(currency: "JPY", lines: [MoneyLine(quantity: dec("1.5"), unitPrice: 101)], payments: [50]))
        XCTAssertEqual(result.total,152); XCTAssertEqual(result.balance,102)
        XCTAssertEqual(Money.digits("KWD"),3); XCTAssertEqual(Money.digits("CLF"),4)
    }
    func testDesignExample() {
        let result = Money.calculate(MoneyInput(lines: [MoneyLine(quantity: 24, unitPrice: 60),MoneyLine(quantity: 34, unitPrice: 24),MoneyLine(unitPrice: 64)], discount: Discount(value: 5), tax1: Tax(rate: dec("8.25")), payments: [500]))
        XCTAssertEqual(result.subtotal,2320); XCTAssertEqual(result.discount,116); XCTAssertEqual(result.tax1,dec("181.83")); XCTAssertEqual(result.total,dec("2385.83")); XCTAssertEqual(result.balance,dec("1885.83"))
    }
    func testStatusUsesLocalCalendarDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: -8*3600)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 20))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 0))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: sameDay)!
        XCTAssertEqual(Money.status(stored: "sent", balance: 10, payments: [], due: sameDay, now: today, calendar: calendar),"sent")
        XCTAssertEqual(Money.status(stored: "sent", balance: 10, payments: [], due: yesterday, now: today, calendar: calendar),"overdue")
        XCTAssertEqual(Money.status(stored: "draft", balance: 10, payments: [], due: yesterday, now: today, calendar: calendar),"draft")
        XCTAssertEqual(Money.status(stored: "sent", balance: 10, payments: [5], due: yesterday),"partial")
        XCTAssertEqual(Money.status(stored: "sent", balance: 0, payments: [5], due: yesterday),"paid")
        XCTAssertEqual(Money.status(stored: "accepted", kind: "estimate", balance: 10, payments: [], due: yesterday),"accepted")
    }
}
final class PortableTests: XCTestCase {
    func testNumberingAndConflict() {
        let result = Numbering.next(prefix: "INV-", start: 1, existing: ["INV-0001","INV-0002"])
        XCTAssertEqual(result.0,"INV-0003"); XCTAssertEqual(result.1,4)
        let id = UUID()
        XCTAssertFalse(Numbering.isDuplicate("INV-0001",id: id,documents: [(id,"INV-0001")]))
        XCTAssertTrue(Numbering.isDuplicate("inv-0001",id: UUID(),documents: [(id,"INV-0001")]))
        XCTAssertEqual(Numbering.revision("INV-0042", existing: ["INV-0042-R1"]),"INV-0042-R2")
    }
    func testCSVQuotedCommaQuoteCRLFAndBOMRoundtrip() throws {
        let rows = [["Name","Email","Address"],["Acme, Inc.","a@example.com","line 1\r\nline \"2\""]]
        let data = CSV.encode(rows); XCTAssertEqual(Array(data.prefix(3)),[0xef,0xbb,0xbf])
        XCTAssertEqual(try CSV.parse(String(data: data, encoding: .utf8)!),rows)
        XCTAssertThrowsError(try CSV.parse("Name\r\n\"unclosed"))
        XCTAssertThrowsError(try CSV.parse("Name\n\"valid\"junk"))
    }
    func testCSVAliasesAndPreview() throws {
        let clients = try CSV.preview(Data("Customer Name,Email Address,Telephone,Billing Address\r\nHarper,a@b.com,123,Here\r\n".utf8))
        XCTAssertEqual(clients.count,1); XCTAssertEqual(clients.firstFive.count,1); XCTAssertEqual(clients.clients().first?.phone,"123")
        let items = try CSV.preview(Data("Description,Rate,Unit,Taxable\nPaint,12.50,hr,no\n".utf8))
        XCTAssertEqual(items.items().first?.unitPrice,Decimal(string:"12.50")); XCTAssertEqual(items.items().first?.taxable,false)
        XCTAssertThrowsError(try CSV.preview(Data("Unknown\nvalue".utf8)))
    }
    func testStyleRoundtripAndCorruptInput() throws {
        let style = StyleCode(template:"Modern",accent:"23466B",notes:"Thank you, \"friend\"\nNext line",terms:"Net 30")
        let code = try ShareCode.encode(style); XCTAssertTrue(code.hasPrefix("Invoices style:")); XCTAssertEqual(try ShareCode.decode(code),style)
        for invalid in ["", "Invoices style:!", "Other:AAAA", String(code.dropLast(4)), try ShareCode.encode(StyleCode(v:9))] { XCTAssertThrowsError(try ShareCode.decode(invalid)) }
        let json = String(data: try JSONEncoder().encode(style),encoding:.utf8)!
        XCTAssertFalse(json.contains("business")); XCTAssertFalse(json.contains("client")); XCTAssertFalse(json.contains("logo"))
    }
    func testRegionDefaults() {
        XCTAssertEqual(RegionDefaults(region:"US").paper,"letter"); XCTAssertEqual(RegionDefaults(region:"US").tax.rate,0)
        XCTAssertEqual(RegionDefaults(region:"GB").currency,"GBP"); XCTAssertEqual(RegionDefaults(region:"GB").tax.rate,20); XCTAssertEqual(RegionDefaults(region:"GB").estimateWord,"Quote")
        XCTAssertEqual(RegionDefaults(region:"AU").invoiceTitle,"Tax Invoice"); XCTAssertEqual(RegionDefaults(region:"AU").taxIDLabel,"ABN")
        XCTAssertEqual(RegionDefaults(region:"CA").currency,"CAD"); XCTAssertEqual(RegionDefaults(region:"CA").tax.rate,5)
    }
    func testFreeLaunchAndPaidTrialTolerance() {
        XCTAssertFalse(Launch.isFree(arguments: [])); XCTAssertTrue(Launch.isFree(arguments: [], freePeriod: true)); XCTAssertFalse(Launch.isFree(arguments: ["-paid-mode"], freePeriod: true)); XCTAssertFalse(Launch.isFree(arguments: ["-paywall"])); XCTAssertFalse(Launch.isFree(arguments: ["-expired"]))
        let now = Date(); var e = Entitlement(firstOpen: now.addingTimeInterval(-100*86400),proStartedAt:now)
        XCTAssertTrue(e.hasPro(at:now,isFree:false)); XCTAssertTrue(e.isPremium(at:now.addingTimeInterval(-599))); XCTAssertFalse(e.isPremium(at:now.addingTimeInterval(-601)))
        XCTAssertFalse(e.isPremium(at:now.addingTimeInterval(30*86400)))
        e.trialClaimedAt = now.addingTimeInterval(-40*86400)
        XCTAssertFalse(e.hasPro(at:now,isFree:false)); XCTAssertTrue(e.hasPro(at:now,isFree:true))
        XCTAssertTrue(e.canReadData && e.canCreateDocument && e.canEditDocument && e.canSendDocument && e.canExportData)
        e.purchasedPro = true; XCTAssertTrue(e.hasPro(at:now,isFree:false))
    }
    func testReviewAndMilestones() {
        XCTAssertFalse(ReviewGate.shouldRequest(paidCount:2,alreadyRequested:false)); XCTAssertTrue(ReviewGate.shouldRequest(paidCount:3,alreadyRequested:false)); XCTAssertFalse(ReviewGate.shouldRequest(paidCount:3,alreadyRequested:true))
        XCTAssertEqual(Milestone.reached(sentCount:100,receivedByCurrency:[:],seen:[]),"invoices100")
        XCTAssertEqual(Milestone.reached(sentCount:2,receivedByCurrency:["USD":10000],seen:[]),"USD-10000")
        XCTAssertNil(Milestone.reached(sentCount:100,receivedByCurrency:["USD":10000],seen:["invoices100","USD-10000"]))
    }
    func testReminderScheduleBoundedAndAtNine() {
        let now = Date(); let due = Calendar.current.date(byAdding:.day,value:1,to:now)!
        let candidates = (0..<100).map { _ in ReminderCandidate(id:UUID(),number:"INV-1",client:"Client",due:due,unpaid:true,recurring:nil) }
        let plan = ReminderPlan.make(candidates,now:now); XCTAssertEqual(plan.count,64)
        XCTAssertTrue(plan.allSatisfy { Calendar.current.component(.hour,from:$0.date) == 9 })
        XCTAssertTrue(ReminderPlan.make([ReminderCandidate(id:UUID(),number:"Paid",client:"",due:due,unpaid:false,recurring:nil)],now:now).isEmpty)
        XCTAssertNotNil(ReminderPlan.next(due,period:"quarterly"))
    }
    func testZipCRCAndHeaders() throws {
        XCTAssertEqual(ZipStore.crc32(Data("123456789".utf8)),0xcbf43926)
        let zip = try ZipStore.archive([("test.txt",Data("hello".utf8))])
        XCTAssertEqual(Array(zip.prefix(4)),[0x50,0x4b,0x03,0x04]); XCTAssertNotNil(zip.range(of: Data("test.txt".utf8)))
    }
}
@MainActor final class PersistenceTests: XCTestCase {
    func container() throws -> ModelContainer {
        let schema = Schema([Business.self,Client.self,Item.self,Document.self,LineItem.self,Payment.self,Attachment.self])
        return try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true,cloudKitDatabase:.none)])
    }
    func testBackupRoundtripMergeAndReplaceWithAssets() throws {
        let store = try container(), context = ModelContext(store)
        let b = Business(); b.name = "Business"; b.logo = Data([1,2,3]); context.insert(b)
        let c = Client(name:"Original client"); context.insert(c)
        let d = Document(number:"INV-1"); context.insert(d); d.client = c; d.clientName = c.name
        let l = LineItem(name:"Work",price:100); context.insert(l); d.lines = [l]
        let p = Payment(amount:25); context.insert(p); d.payments = [p]
        let photo = Attachment(data:Data([4,5])); context.insert(photo); d.attachments = [photo]; d.clientSignature = Data([6,7])
        let data = BackupData(business:BusinessRecord(b),clients:[ClientRecord(c)],items:[],documents:[DocumentRecord(d)])
        let decoded = try Backup.preview(Backup.export(data)); XCTAssertEqual(data,decoded)
        XCTAssertThrowsError(try Backup.preview(Data("bad".utf8)))
        c.name = "New client name"; XCTAssertEqual(d.clientName,"Original client")
        try Backup.restore(decoded,context:context,replace:false); XCTAssertEqual(try context.fetch(FetchDescriptor<Document>()).count,1)
        let extra = Document(number:"INV-2"); context.insert(extra); try context.save()
        try Backup.restore(decoded,context:context,replace:true)
        let restored = try context.fetch(FetchDescriptor<Document>())
        XCTAssertEqual(restored.count,1); XCTAssertEqual(restored.first?.totals.balance,75); XCTAssertEqual(restored.first?.attachments?.first?.data,Data([4,5]))
    }
    func testPDFSixtyLinesAndPaperSizes() throws {
        let b = Business(), d = Document(number:"INV-60"); d.clientName = "Client"
        d.lines = (0..<60).map { i in let l = LineItem(name:"Line \(i)",price:100); l.order = i; return l }
        for template in ShareCode.templates {
            b.settings.template = template
            let bytes = PDFRenderer.render(document:DocumentRecord(d),business:BusinessRecord(b),entitlement:Entitlement(purchasedPro:true))
            let pdf = try XCTUnwrap(PDFDocument(data:bytes)); XCTAssertGreaterThanOrEqual(pdf.pageCount,2)
            XCTAssertTrue(pdf.string?.contains("INV-60") == true)
            XCTAssertEqual(pdf.page(at:0)?.bounds(for:.mediaBox).width,612)
        }
        b.settings.paperSize = "a4"
        let pdf = PDFDocument(data:PDFRenderer.render(document:DocumentRecord(d),business:BusinessRecord(b),entitlement:Entitlement()))
        XCTAssertEqual(pdf?.page(at:0)?.bounds(for:.mediaBox).height,842)
    }
    func testCashReportsSeparateCurrenciesAndMirrorPayments() {
        let d = Document(number:"INV-1"); d.currencyCode = "USD"; d.status = "sent"; d.clientName = "Client"; d.tax1Rate = 10
        d.lines = [LineItem(name:"Work",price:100)]; d.payments = [Payment(amount:55)]
        let mirror = Payment(amount:10); mirror.sourcePaymentID = UUID(); d.payments?.append(mirror)
        let interval = DateInterval(start:Date().addingTimeInterval(-86400),duration:172800)
        let result = Reports.calculate([DocumentRecord(d)],currency:"USD",interval:interval)
        XCTAssertEqual(result.received,55); XCTAssertEqual(result.outstanding,45)
        XCTAssertEqual(Reports.calculate([DocumentRecord(d)],currency:"GBP",interval:interval).received,0)
    }
    func testCollectedTaxAcrossPeriodsDoesNotExceedInvoiceTax() {
        let d = Document(number:"INV-TAX"); d.tax1Name = "VAT"; d.tax1Rate = 10
        d.lines = [LineItem(name:"Work",price:100)]
        let start = Date(timeIntervalSince1970:1_700_000_000)
        let first = Payment(amount:55); first.date = start
        let second = Payment(amount:100); second.date = start.addingTimeInterval(100)
        d.payments = [first,second]
        let before = Reports.calculate([DocumentRecord(d)],currency:"USD",interval:DateInterval(start:start,duration:50))
        let after = Reports.calculate([DocumentRecord(d)],currency:"USD",interval:DateInterval(start:start.addingTimeInterval(50),duration:100))
        XCTAssertEqual(before.taxes["VAT"],5); XCTAssertEqual(after.taxes["VAT"],5)
    }
}
