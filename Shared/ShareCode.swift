import Foundation

struct StyleCode: Codable, Equatable {
    var v = 1
    var template = "Classic"
    var accent = "1F5B4A"
    var font: String? = "System"
    var notes = ""
    var terms = ""
    var estimateWord = "Estimate"
}
enum ShareCode {
    static let prefix = "Invoices style:"
    static let templates = ["Classic","Modern","Minimal","Bold","Compact","Contractor"]
    static func encode(_ style: StyleCode) throws -> String {
        guard let bytes = Zlib.pack(try JSONEncoder().encode(style)) else { throw DataError.tooLarge }
        return prefix + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ text: String) throws -> StyleCode {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.count < 100000 else { throw DataError.corrupt }
        var body = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let compressed = Data(base64Encoded: body), let json = Zlib.unpack(compressed) else { throw DataError.corrupt }
        let result = try JSONDecoder().decode(StyleCode.self, from: json)
        guard result.v == 1, templates.contains(result.template), result.accent.count == 6,
              result.accent.allSatisfy(\.isHexDigit), result.notes.count <= 10000, result.terms.count <= 10000,
              ["Estimate","Quote"].contains(result.estimateWord) else { throw DataError.corrupt }
        return result
    }
}
