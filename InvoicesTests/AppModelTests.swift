import XCTest
@testable import Invoices

@MainActor final class AppModelTests: XCTestCase {
    func testDepositAndConversion() throws {
        let m = try AppModel(inMemory: true), original = m.newDocument()
        original.clientName = "Client"; let line = m.appendLine(original); line.name = "Work"; line.unitPrice = 1000; original.tax1Rate = 0
        m.save(); let deposit = m.depositInvoice(from:original,percent:50)
        XCTAssertEqual(deposit.totals.total,500); XCTAssertEqual(deposit.orderedLines.first?.name,"Deposit for " + original.number)
        XCTAssertEqual(m.receivableDocuments.reduce(Decimal(0)) { $0 + $1.totals.balance },1000)
        m.addPayment(deposit,amount:500,method:"cash"); XCTAssertEqual(original.totals.balance,500)
        m.markPaid(original); XCTAssertEqual(original.computedStatus(),"paid"); m.undoToast(); XCTAssertEqual(original.totals.balance,500)
        let estimate = m.newDocument(kind:"estimate"); let quoteLine = m.appendLine(estimate); quoteLine.name = "Quote work"; quoteLine.unitPrice = 50
        m.convert(estimate); let invoice = try XCTUnwrap(m.selected)
        XCTAssertEqual(estimate.status,"converted"); XCTAssertEqual(invoice.linkedDocumentID,estimate.id); XCTAssertEqual(invoice.orderedLines.first?.name,"Quote work")
        let client = Client(name:"Previous client"); client.email = "previous@example.com"; m.context.insert(client); m.pick(client,for:original)
        let copy = m.duplicate(original)
        m.editClientName("New client",for:copy); XCTAssertNil(copy.client); XCTAssertEqual(copy.clientEmail,"")
        m.ensureClient(copy); XCTAssertEqual(copy.client?.name,"New client"); XCTAssertEqual(original.clientEmail,"previous@example.com")
    }
    func testUndoSnapshotKeepsExistingLineIdentity() throws {
        let model = try AppModel(inMemory: true), document = model.newDocument()
        let line = model.appendLine(document); line.name = "Original"
        let saved = DocumentRecord(document)
        line.name = "Changed"; saved.apply(to: document, context: model.context, clients: model.clients)
        XCTAssertTrue(document.orderedLines.first === line)
        XCTAssertEqual(line.name,"Original")
    }
}
