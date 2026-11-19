import Foundation

@MainActor enum Demo {
    static func seed(_ m: AppModel) {
        let uk = ProcessInfo.processInfo.arguments.contains("-demo-uk")
        let b = m.business
        b.name = "Harbor Tile Co."; b.email = "hello@harbortile.co"; b.phone = "512 555 0142"; b.address = "214 Bay St, Austin TX 78701"
        b.settings.currencyCode = uk ? "GBP" : "USD"; b.settings.paperSize = uk ? "a4" : "letter"
        b.settings.defaultTax1 = Tax(name: uk ? "VAT" : "Sales tax", rate: uk ? 20 : Decimal(string: "8.25")!)
        b.settings.estimateWord = uk ? "Quote" : "Estimate"; b.settings.defaultTerms = 14
        b.settings.payInstructions = "Or bank transfer · Acct 0123 4567 · Routing 111000025"
        var link = PayLink(); link.title = "Pay online"; link.url = "https:" + "//paypal.me/harbortile"; b.settings.payLinks = [link]
        let names = ["Harper Renovations","Maya Whitfield","Oak & Copper Café","Daniel Lee","Greenline Storage"]
        var clients: [Client] = []
        for (i,name) in names.enumerated() {
            let c = Client(name: name); c.email = "client\(i + 1)@example.com"; c.address = i == 0 ? "88 Cedar Ln, Austin TX" : "Austin TX"
            m.context.insert(c); clients.append(c)
        }
        let prices = ["60","24","64","45","120","75"]
        let itemNames = ["Kitchen tiling — labour","Porcelain tile 60×60","Grout & adhesive","Surface preparation","Tile removal","Site visit"]
        for i in 0..<6 { let item = Item(name: itemNames[i], price: Decimal(string: prices[i])!, unit: i == 0 ? "hr" : i == 1 ? "sq ft" : "ea"); m.context.insert(item) }
        let today = Calendar.current.startOfDay(for: Date())
        func days(_ count: Int) -> Date { Calendar.current.date(byAdding: .day, value: count, to: today)! }
        func document(_ n: String, client: Int, age: Int, status: String, price: Decimal, kind: String = "invoice") -> Document {
            let d = Document(kind: kind, number: n); m.context.insert(d)
            d.title = kind == "estimate" ? b.settings.estimateWord : "Invoice"; d.client = clients[client]; d.clientName = clients[client].name; d.clientEmail = clients[client].email; d.clientAddress = clients[client].address
            d.issueDate = days(-age); d.createdAt = days(-age); d.updatedAt = d.createdAt; d.dueDate = days(14-age); d.terms = 14; d.currencyCode = b.settings.currencyCode; d.status = status
            d.sentAt = status == "draft" ? nil : d.issueDate; d.lines = []; d.payments = []; d.attachments = []
            if price > 0 { let l = LineItem(name: "Tile installation", price: price); m.context.insert(l); d.lines = [l] }
            return d
        }
        let main = document("INV-0042", client: 0, age: 1, status: "sent", price: 0)
        let l1 = LineItem(name: itemNames[0], price: 60, quantity: 24); l1.unit = "hr"
        let l2 = LineItem(name: itemNames[1], price: 24, quantity: 34); l2.unit = "sq ft"; l2.order = 1
        let l3 = LineItem(name: itemNames[2], price: 64); l3.order = 2
        for l in [l1,l2,l3] { m.context.insert(l) }; main.lines = [l1,l2,l3]
        main.tax1 = b.settings.defaultTax1; main.discountValue = 5
        let deposit = Payment(amount: 500, method: "bankTransfer"); deposit.note = "Deposit received"; deposit.date = days(-1); m.context.insert(deposit); main.payments = [deposit]
        let partial = document("INV-0041", client: 1, age: 2, status: "sent", price: 1280)
        let p = Payment(amount: 640); p.date = days(-1); m.context.insert(p); partial.payments = [p]
        _ = document("INV-0040", client: 2, age: 4, status: "draft", price: Decimal(string: "873.67")!)
        let overdue = document("INV-0037", client: 3, age: 23, status: "sent", price: 860); overdue.dueDate = days(-9)
        let paid = document("INV-0036", client: 4, age: 27, status: "sent", price: 1925)
        let paidPayment = Payment(amount: 1925); paidPayment.date = days(-3); m.context.insert(paidPayment); paid.payments = [paidPayment]
        _ = document("EST-0012", client: 0, age: 2, status: "sent", price: 2400, kind: "estimate")
        _ = document("EST-0011", client: 2, age: 9, status: "accepted", price: 780, kind: "estimate")
        b.settings.nextInvoiceNumber = 43; b.settings.nextEstimateNumber = 13
        try? m.context.save()
    }
}
