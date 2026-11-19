import Foundation

enum CSVError: Error { case malformed, empty, missingName }
enum CSV {
    static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
    static func encode(_ rows: [[String]]) -> Data {
        Data([0xef, 0xbb, 0xbf]) + Data((rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
    static func parse(_ text: String) throws -> [[String]] {
        let chars = Array((text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text).unicodeScalars)
        var rows: [[String]] = [], row: [String] = [], value = ""
        var quoted = false, closed = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { value.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { value.unicodeScalars.append(c) }
            } else if c == "\"" {
                guard value.isEmpty && !closed else { throw CSVError.malformed }; quoted = true
            } else if c == "," {
                row.append(value); value = ""; closed = false
            } else if c == "\r" || c == "\n" {
                row.append(value); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []; value = ""; closed = false
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else {
                guard !closed else { throw CSVError.malformed }; value.unicodeScalars.append(c)
            }
            i += 1
        }
        guard !quoted else { throw CSVError.malformed }
        if !value.isEmpty || !row.isEmpty || closed { row.append(value); rows.append(row) }
        return rows
    }
    struct ImportPreview {
        var headers: [String]
        var rows: [[String]]
        var firstFive: [[String]] { Array(rows.prefix(5)) }
        var count: Int { rows.count }
        func index(_ names: [String]) -> Int? {
            headers.firstIndex { h in names.contains(h.lowercased().filter { $0.isLetter || $0.isNumber }) }
        }
        func value(_ row: [String], _ aliases: [String]) -> String {
            guard let index = index(aliases), index < row.count else { return "" }; return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func clients() -> [Client] {
            rows.compactMap { row in
                let name = value(row, ["name", "client", "clientname", "customer", "customername", "company"])
                guard !name.isEmpty else { return nil }
                let c = Client(name: name); c.email = value(row, ["email", "emailaddress"]); c.phone = value(row, ["phone", "telephone", "mobile"])
                c.address = value(row, ["address", "billingaddress"]); c.notes = value(row, ["notes", "note"]); return c
            }
        }
        func items() -> [Item] {
            rows.compactMap { row in
                let name = value(row, ["name", "item", "itemname", "product", "service", "description"])
                guard !name.isEmpty else { return nil }
                let raw = value(row, ["rate", "price", "unitprice", "amount"])
                let price = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) ?? 0
                let item = Item(name: name, price: max(0, price), unit: value(row, ["unit", "units"]))
                item.details = value(row, ["details", "description"])
                item.taxable = !["false", "no", "0", "n"].contains(value(row, ["taxable", "tax"]).lowercased())
                return item
            }
        }
    }
    static func preview(_ data: Data) throws -> ImportPreview {
        guard data.count <= 20_000_000, let string = String(data: data, encoding: .utf8) else { throw CSVError.malformed }
        let rows = try parse(string)
        guard let header = rows.first else { throw CSVError.empty }
        let result = ImportPreview(headers: header, rows: Array(rows.dropFirst()))
        guard result.index(["name", "client", "clientname", "customer", "customername", "company", "item", "itemname", "product", "service", "description"]) != nil else { throw CSVError.missingName }
        return result
    }
    static func exports(documents: [DocumentRecord], clients: [ClientRecord], items: [ItemRecord]) -> [(String, Data)] {
        let iso = ISO8601DateFormatter()
        var docs = [["ID","Kind","Number","Client","Currency","Issued","Due","Status","Subtotal","Tax 1 name","Tax 1","Tax 2 name","Tax 2","Total","Paid","Balance","Deleted"]]
        var lines = [["Document ID","Number","Order","Name","Description","Quantity","Unit","Price","Discount type","Discount","Taxable"]]
        var payments = [["ID","Document ID","Number","Currency","Date","Amount","Method","Note","Mirrored payment ID"]]
        for d in documents {
            let t = d.totals
            let state = Money.status(stored: d.status, kind: d.kind, balance: t.balance, payments: d.payments.map(\.amount), due: d.dueDate)
            docs.append([d.id.uuidString,d.kind,d.number,d.clientName,d.currency,iso.string(from: d.issueDate),d.dueDate.map(iso.string) ?? "",state,"\(t.subtotal)",d.tax1.name,"\(t.tax1)",d.tax2.name,"\(t.tax2)","\(t.total)","\(t.paid)","\(t.balance)",d.deletedAt.map(iso.string) ?? ""])
            for l in d.lines { lines.append([d.id.uuidString,d.number,"\(l.order)",l.name,l.details,"\(l.quantity)",l.unit,"\(l.price)",l.discount.kind,"\(l.discount.value)",l.taxable ? "true" : "false"]) }
            for p in d.payments { payments.append([p.id.uuidString,d.id.uuidString,d.number,d.currency,iso.string(from: p.date),"\(p.amount)",p.method,p.note,p.sourcePaymentID?.uuidString ?? ""]) }
        }
        var cs = [["ID","Name","Email","Phone","Address","Notes","Currency","Terms"]]
        for c in clients { cs.append([c.id.uuidString,c.name,c.email,c.phone,c.address,c.notes,c.currencyCode ?? "",c.defaultTerms.map(String.init) ?? ""]) }
        var its = [["ID","Name","Description","Price","Unit","Taxable"]]
        for i in items { its.append([i.id.uuidString,i.name,i.details,"\(i.price)",i.unit,i.taxable ? "true" : "false"]) }
        return [("documents.csv",encode(docs)),("lines.csv",encode(lines)),("payments.csv",encode(payments)),("clients.csv",encode(cs)),("items.csv",encode(its))]
    }
}
