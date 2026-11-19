import Foundation

struct Discount: Codable, Equatable {
    var kind = "percent"
    var value: Decimal = 0
    func amount(on base: Decimal) -> Decimal {
        min(max(0, base), max(0, kind == "percent" ? base * value / 100 : value))
    }
}
struct Tax: Codable, Equatable {
    var name = "Tax"
    var rate: Decimal = 0
    var compound = false
}
struct MoneyLine: Codable, Equatable {
    var quantity: Decimal = 1
    var unitPrice: Decimal = 0
    var discount = Discount()
    var taxable = true
}
struct MoneyInput: Codable, Equatable {
    var currency = "USD"
    var lines: [MoneyLine] = []
    var discount = Discount()
    var tax1 = Tax()
    var tax2 = Tax(name: "Tax 2")
    var includesTax = false
    var shipping: Decimal = 0
    var payments: [Decimal] = []
}
struct MoneyResult: Equatable {
    var lineAmounts: [Decimal] = []
    var allocatedDiscounts: [Decimal] = []
    var subtotal: Decimal = 0
    var discount: Decimal = 0
    var net: Decimal = 0
    var tax1: Decimal = 0
    var tax2: Decimal = 0
    var shipping: Decimal = 0
    var total: Decimal = 0
    var paid: Decimal = 0
    var balance: Decimal = 0
}
enum Money {
    static func digits(_ currency: String) -> Int {
        if ["BIF","CLP","DJF","GNF","ISK","JPY","KMF","KRW","PYG","RWF","UGX","UYI","VND","VUV","XAF","XOF","XPF"].contains(currency) { return 0 }
        if ["BHD","IQD","JOD","KWD","LYD","OMR","TND"].contains(currency) { return 3 }
        if ["CLF","UYW"].contains(currency) { return 4 }
        return 2
    }
    static func round(_ value: Decimal, currency: String) -> Decimal {
        var source = value, result = Decimal()
        NSDecimalRound(&result, &source, digits(currency), .plain)
        return result
    }
    static func calculate(_ input: MoneyInput) -> MoneyResult {
        let currency = input.currency
        func r(_ n: Decimal) -> Decimal { round(n, currency: currency) }
        var out = MoneyResult()
        out.lineAmounts = input.lines.map { line in
            let base = max(0, line.quantity) * max(0, line.unitPrice)
            return r(base - line.discount.amount(on: base))
        }
        out.subtotal = out.lineAmounts.reduce(0, +)
        out.discount = r(input.discount.amount(on: out.subtotal))
        var remaining = out.discount
        let lastPositive = out.lineAmounts.lastIndex(where: { $0 > 0 })
        for (index, amount) in out.lineAmounts.enumerated() {
            let share: Decimal
            if index == lastPositive { share = min(amount, remaining) }
            else if out.subtotal > 0 { share = min(remaining, min(amount, r(out.discount * amount / out.subtotal))) }
            else { share = 0 }
            out.allocatedDiscounts.append(share)
            remaining -= share
        }
        if remaining > 0 {
            for index in out.lineAmounts.indices.reversed() {
                let extra = min(remaining, out.lineAmounts[index] - out.allocatedDiscounts[index])
                out.allocatedDiscounts[index] += extra; remaining -= extra
                if remaining <= 0 { break }
            }
        }
        let r1 = max(0, input.tax1.rate) / 100
        let r2 = max(0, input.tax2.rate) / 100
        for (i, line) in input.lines.enumerated() {
            let amount = out.lineAmounts[i] - out.allocatedDiscounts[i]
            guard line.taxable else { out.net += amount; continue }
            let net: Decimal
            let t1: Decimal
            let t2: Decimal
            if input.includesTax {
                let divisor = input.tax2.compound ? (1 + r1) * (1 + r2) : 1 + r1 + r2
                let exactNet = amount / divisor
                net = r(exactNet)
                t1 = r(exactNet * r1)
                t2 = r2 > 0 ? amount - net - t1 : 0
                out.tax1 += r2 > 0 ? t1 : amount - net
            } else {
                net = amount
                t1 = r(net * r1)
                t2 = r((input.tax2.compound ? net + t1 : net) * r2)
                out.tax1 += t1
            }
            out.net += net
            out.tax2 += t2
        }
        out.shipping = r(max(0, input.shipping))
        out.total = r(out.net + out.tax1 + out.tax2 + out.shipping)
        out.paid = r(input.payments.reduce(0) { $0 + max(0, $1) })
        out.balance = r(out.total - out.paid)
        return out
    }
    static func status(stored: String, kind: String = "invoice", balance: Decimal, payments: [Decimal], due: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard kind == "invoice" else { return stored }
        let received = payments.contains(where: { $0 > 0 })
        if received && balance <= 0 { return "paid" }
        if received && balance > 0 { return "partial" }
        if stored != "draft", let due, calendar.startOfDay(for: due) < calendar.startOfDay(for: now) { return "overdue" }
        return stored
    }
    static func format(_ value: Decimal, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale; formatter.numberStyle = .currency; formatter.currencyCode = currency
        formatter.minimumFractionDigits = digits(currency); formatter.maximumFractionDigits = digits(currency)
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(currency) \(value)"
    }
}
