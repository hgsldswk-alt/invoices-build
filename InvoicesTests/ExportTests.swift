import XCTest
@testable import Invoices

@MainActor final class ExportTests: XCTestCase {
    func testCSVExportsAllFiveTables() throws {
        let c = Client(name:"Client"), i = Item(name:"Work",price:60), d = Document(number:"INV-1")
        d.client = c; d.clientName = c.name; d.lines = [LineItem(name:"Work",price:60)]; d.payments = [Payment(amount:30)]
        let exports = CSV.exports(documents:[DocumentRecord(d)],clients:[ClientRecord(c)],items:[ItemRecord(i)])
        XCTAssertEqual(Set(exports.map(\.0)),["documents.csv","lines.csv","payments.csv","clients.csv","items.csv"])
        for (_,bytes) in exports { XCTAssertEqual(Array(bytes.prefix(3)),[0xef,0xbb,0xbf]); XCTAssertGreaterThan(try CSV.parse(String(data:bytes,encoding:.utf8)!).count,1) }
    }
}
