import UIKit
import CoreText
import CoreImage
import PDFKit

enum PDFRenderer {
    enum Draw {
        case text(String, CGRect, UIFont, UIColor, NSTextAlignment)
        case fill(CGRect, UIColor)
        case line(CGPoint, CGPoint, UIColor)
        case image(Data, CGRect)
        case link(URL, CGRect)
    }
    final class Layout {
        var pages: [[Draw]] = [[]]
        var y: CGFloat = 40
        let size: CGSize
        let accent: UIColor
        let words: PDFWords
        var template: String
        var useSerif = false
        let fontSize: CGFloat
        var width: CGFloat { size.width - 80 }
        var bottom: CGFloat { size.height - 65 }
        init(size: CGSize, accent: UIColor, words: PDFWords, template: String) {
            self.size = size; self.accent = accent; self.words = words; self.template = template; fontSize = template == "Compact" ? 9 : 10
        }
        func add(_ op: Draw) { pages[pages.count - 1].append(op) }
        func page() { pages.append([]); y = 40 }
        func ensure(_ height: CGFloat) { if y + height > bottom { page() } }
        func text(_ value: String, x: CGFloat = 40, y: CGFloat? = nil, width: CGFloat? = nil, size: CGFloat? = nil, bold: Bool = false, color: UIColor = .black, align: NSTextAlignment = .left, serif: Bool = false) {
            let font = serif || useSerif ? UIFont(name: bold ? "Georgia-Bold" : "Georgia", size: size ?? fontSize) ?? .systemFont(ofSize: size ?? fontSize) : .systemFont(ofSize: size ?? fontSize, weight: bold ? .semibold : .regular)
            add(.text(value, CGRect(x: x, y: y ?? self.y, width: width ?? self.width, height: (size ?? fontSize) * 1.5), font, color, align))
        }
        func wrappedLines(_ value: String, width: CGFloat, size: CGFloat? = nil) -> [String] {
            let string = value as NSString
            guard string.length > 0 else { return [] }
            let font = useSerif ? UIFont(name: "Georgia", size: size ?? fontSize) ?? .systemFont(ofSize: size ?? fontSize) : UIFont.systemFont(ofSize: size ?? fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: value, attributes: attrs) as CFAttributedString)
            var offset = 0, lines: [String] = []
            while offset < string.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(width)))
                lines.append(string.substring(with: NSRange(location: offset, length: min(count, string.length - offset))).trimmingCharacters(in: .newlines))
                offset += count
            }
            return lines
        }
        func flow(_ value: String, size: CGFloat? = nil, color: UIColor = .darkGray) {
            let step = (size ?? fontSize) * 1.6
            for line in wrappedLines(value, width: width, size: size) { ensure(step); text(line, size: size, color: color); y += step }
        }
        func rule() { add(.line(CGPoint(x: 40, y: y), CGPoint(x: size.width - 40, y: y), .lightGray)); y += 10 }
        func tableHeader() {
            ensure(30)
            let colored = ["Modern","Bold","Contractor"].contains(template)
            if colored { add(.fill(CGRect(x: 40, y: y, width: width, height: 24), accent)) }
            let c: UIColor = colored ? .white : .black
            text(words.t("Description"), x: 46, y: y + 5, width: width * 0.52, bold: true, color: c)
            text(words.t("Qty"), x: 40 + width * 0.53, y: y + 5, width: width * 0.11, color: c, align: .right)
            text(words.t("Rate"), x: 40 + width * 0.65, y: y + 5, width: width * 0.15, color: c, align: .right)
            text(words.t("Amount"), x: 40 + width * 0.81, y: y + 5, width: width * 0.18 - 6, color: c, align: .right)
            y += 30
        }
        func total(_ label: String, _ amount: String, bold: Bool = false) {
            ensure(23); text(label, x: 40 + width * 0.44, width: width * 0.33, bold: bold)
            text(amount, x: 40 + width * 0.78, width: width * 0.22, bold: bold, color: bold ? accent : .black, align: .right); y += 22
        }
    }
    static func color(_ hex: String) -> UIColor {
        let v = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x1f5b4a
        return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    static func qr(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage"); filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let result = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(result, from: result.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    static func filename(_ d: DocumentRecord, receipt: Bool = false) -> String {
        let value = (receipt ? "Receipt" : d.title) + " " + d.number + " - " + d.clientName
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let clean = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(180)) + ".pdf"
    }
    static func render(document d: DocumentRecord, business b: BusinessRecord, entitlement: Entitlement, receipt: Bool = false) -> Data {
        let s = b.settings, words = PDFWords(language: b.settings.pdfLanguage)
        let template = entitlement.canUseTemplate(s.template) ? s.template : "Classic"
        let size = s.paperSize == "a4" ? CGSize(width: 595, height: 842) : CGSize(width: 612, height: 792)
        let accent: UIColor = template == "Minimal" ? .black : color(s.accentColorHex)
        let p = Layout(size: size, accent: accent, words: words, template: template)
        p.useSerif = s.font == "Serif"
        let t = d.totals
        func amount(_ n: Decimal) -> String { Money.format(n, currency: d.currency, locale: words.locale) }
        if template == "Bold" { p.add(.fill(CGRect(x: 0, y: 0, width: size.width, height: 12), accent)) }
        if let logo = b.logo { p.add(.image(logo, CGRect(x: 40, y: 40, width: 42, height: 42))) }
        let bx: CGFloat = b.logo == nil ? 40 : 92
        p.text(b.name, x: bx, width: size.width * 0.5 - bx, size: 13, bold: true)
        p.text(words.t(receipt ? "Receipt" : d.title).uppercased(), x: size.width * 0.50, width: size.width * 0.5 - 40, size: 24, color: accent, align: .right, serif: template == "Classic")
        p.y += 30
        p.text(d.number, x: size.width * 0.60, width: size.width * 0.4 - 40, align: .right)
        let businessInfo = [b.address,b.email,b.phone,b.website,b.taxID.isEmpty ? "" : b.taxIDLabel + ": " + b.taxID].filter { !$0.isEmpty }.joined(separator: "\n")
        for line in p.wrappedLines(businessInfo, width: size.width * 0.50 - 40) { p.text(line, width: size.width * 0.5 - 40, size: 9); p.y += 14 }
        p.y = max(p.y + 22, 130)
        p.text(words.t("Bill to"), color: .gray); p.y += 18
        p.flow([d.clientName,d.clientAddress,d.clientEmail].filter { !$0.isEmpty }.joined(separator: "\n"))
        p.y += 12
        p.flow(words.t("Issued") + ": " + words.date(d.issueDate) + (d.dueDate.map { "    " + words.t("Due") + ": " + words.date($0) } ?? ""), size: 9)
        p.y += 18; p.tableHeader()
        for (index, line) in d.lines.enumerated() {
            let label = line.name + (line.details.isEmpty ? "" : "\n" + line.details)
            var desc = p.wrappedLines(label, width: p.width * 0.51 - 12)
            if desc.isEmpty { desc = [""] }
            for (j, text) in desc.enumerated() {
                if p.y + 17 > p.bottom { p.page(); p.tableHeader() }
                p.text(text, x: 46, width: p.width * 0.51 - 12)
                if j == 0 {
                    p.text("\(line.quantity) " + line.unit, x: 40 + p.width * 0.52, width: p.width * 0.12, align: .right)
                    p.text(amount(line.price), x: 40 + p.width * 0.65, width: p.width * 0.15, align: .right)
                    p.text(amount(t.lineAmounts[index]), x: 40 + p.width * 0.81, width: p.width * 0.18 - 6, align: .right)
                }
                p.y += 17
            }
            p.y += 5; p.rule()
        }
        p.y += 12
        p.total(words.t("Subtotal"), amount(t.subtotal))
        if t.discount > 0 { p.total(words.t("Discount"), "−" + amount(t.discount)) }
        if t.tax1 > 0 { p.total(d.tax1.name + " \(d.tax1.rate)%", amount(t.tax1)) }
        if t.tax2 > 0 { p.total(d.tax2.name + " \(d.tax2.rate)%", amount(t.tax2)) }
        if t.shipping > 0 { p.total(words.t("Shipping"), amount(t.shipping)) }
        p.total(words.t("Total"), amount(t.total), bold: true)
        for payment in d.payments { p.total(words.t(payment.sourcePaymentID != nil || payment.note.hasPrefix("Deposit") ? "Deposit received" : "Payment received"), "−" + amount(payment.amount)) }
        p.total(words.t("Balance due"), amount(t.balance), bold: true)
        p.y += 12
        if !s.payInstructions.isEmpty { p.flow(s.payInstructions); p.y += 10 }
        if d.showPayLinks {
            let links = Array(s.payLinks.filter { $0.validURL != nil }.prefix(3))
            for link in links {
                guard let url = link.validURL else { continue }
                for text in p.wrappedLines(link.title + ": " + link.url, width: p.width) {
                    p.ensure(18); p.text(text, color: accent)
                    p.add(.link(url, CGRect(x: 40, y: p.y, width: p.width, height: 18))); p.y += 18
                }
            }
            if entitlement.canUsePayQR, let link = links.first, let image = qr(link.url)?.pngData() { p.ensure(85); p.add(.image(image, CGRect(x: 40, y: p.y, width: 76, height: 76))); p.y += 85 }
        }
        if !d.notes.isEmpty { p.flow(words.t("Notes"), color: accent); p.flow(d.notes); p.y += 10 }
        if !d.termsText.isEmpty { p.flow(words.t("Terms"), color: accent); p.flow(d.termsText); p.y += 10 }
        for payment in receipt ? d.payments : [] { p.flow(words.date(payment.date) + " · " + payment.method + " · " + amount(payment.amount) + " " + payment.note) }
        if d.showOwnSignature, let signature = b.signature { p.ensure(78); p.add(.image(signature, CGRect(x: size.width - 200, y: p.y, width: 160, height: 50))); p.y += 55; p.text(words.t("Authorized signature"), x: size.width - 200, width: 160, size: 8); p.y += 20 }
        if let signature = d.clientSignature {
            p.ensure(88); p.add(.image(signature, CGRect(x: 40, y: p.y, width: 160, height: 50))); p.y += 55
            p.flow(words.t("Client signature") + (d.signedAt.map { " · " + words.date($0) } ?? ""), size: 8)
        }
        if template == "Contractor" {
            let photos = d.attachments.prefix(3)
            if !photos.isEmpty { p.ensure(90); for (i, a) in photos.enumerated() { if let data = a.data { p.add(.image(data, CGRect(x: 40 + CGFloat(i) * 110, y: p.y, width: 100, height: 75))) } }; p.y += 90 }
        }
        if !d.attachments.isEmpty {
            for (i, photo) in d.attachments.enumerated() {
                if i % 2 == 0 { p.page(); p.text(words.t("Photos") + " · " + d.number, size: 15, bold: true); p.y += 30 }
                let h = (size.height - 170) / 2
                p.ensure(h)
                if let data = photo.data { p.add(.image(data, CGRect(x: 40, y: p.y, width: p.width, height: h - 45))) }
                p.y += h - 40
                p.flow(photo.caption, size: 9)
                p.y += 12
            }
        }
        return draw(p, paid: d.kind == "invoice" && t.paid > 0 && t.balance <= 0, madeWith: s.showMadeWith || !entitlement.canHideMadeWith)
    }
    static func statement(client: ClientRecord, documents: [DocumentRecord], business: BusinessRecord) -> Data {
        let s = business.settings, words = PDFWords(language: business.settings.pdfLanguage)
        let size = s.paperSize == "a4" ? CGSize(width: 595, height: 842) : CGSize(width: 612, height: 792)
        let p = Layout(size: size, accent: color(s.accentColorHex), words: words, template: "Classic")
        p.flow(words.t("Statement"), size: 24); p.y += 10; p.flow(business.name); p.flow(client.name); p.flow(client.address); p.y += 20
        let liveIDs = Set(documents.filter { $0.deletedAt == nil }.map(\.id))
        let unpaid = documents.filter { d in d.deletedAt == nil && d.kind == "invoice" && d.clientID == client.id && d.totals.balance > 0 && (d.depositParentID.map { !liveIDs.contains($0) } ?? true) }
        for currency in Set(unpaid.map(\.currency)).sorted() {
            p.flow(currency, size: 14, color: p.accent)
            for d in unpaid.filter({ $0.currency == currency }) { p.ensure(25); p.text(d.number + " · " + words.date(d.issueDate)); p.text(Money.format(d.totals.balance, currency: currency, locale: words.locale), align: .right); p.y += 25 }
            p.total(words.t("Balance due"), Money.format(unpaid.filter { $0.currency == currency }.reduce(0) { $0 + $1.totals.balance }, currency: currency, locale: words.locale), bold: true); p.y += 15
        }
        return draw(p, paid: false, madeWith: s.showMadeWith)
    }
    static func draw(_ p: Layout, paid: Bool, madeWith: Bool) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: p.size))
        return renderer.pdfData { context in
            for (index, page) in p.pages.enumerated() {
                context.beginPage()
                UIColor.white.setFill(); context.cgContext.fill(CGRect(origin: .zero, size: p.size))
                for op in page {
                    switch op {
                    case let .text(value, rect, font, color, align):
                        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byTruncatingTail
                        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
                    case let .fill(rect, color): color.setFill(); context.cgContext.fill(rect)
                    case let .line(a,b,color): color.setStroke(); context.cgContext.setLineWidth(0.5); context.cgContext.move(to: a); context.cgContext.addLine(to: b); context.cgContext.strokePath()
                    case let .image(data, rect):
                        if let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 {
                            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                            image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                        }
                    case let .link(url, rect): context.setURL(url, for: rect)
                    }
                }
                if paid && index == 0 {
                    let cg = context.cgContext; cg.saveGState(); cg.translateBy(x: p.size.width - 100, y: 113); cg.rotate(by: -0.13)
                    p.accent.setStroke(); cg.setLineWidth(1.5); cg.stroke(CGRect(x: -44, y: -18, width: 88, height: 34))
                    (p.words.t("PAID") as NSString).draw(in: CGRect(x: -37, y: -14, width: 80, height: 28), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: p.accent]); cg.restoreGState()
                }
                let page = String(format: p.words.t("Page %d of %d"), index + 1, p.pages.count)
                (page as NSString).draw(at: CGPoint(x: 40, y: p.size.height - 30), withAttributes: [.font: UIFont.systemFont(ofSize: 7), .foregroundColor: UIColor.gray])
                if madeWith {
                    let value = "Made with Invoices & Estimates Offline" as NSString
                    let rect = CGRect(x: p.size.width - 225, y: p.size.height - 30, width: 185, height: 12)
                    value.draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: 6.5), .foregroundColor: UIColor.gray])
                    if let url = AppLinks.store { context.setURL(url, for: rect) }
                }
            }
        }
    }
}
