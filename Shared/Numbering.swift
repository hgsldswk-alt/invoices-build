import Foundation

enum Numbering {
    static func number(prefix: String, next: Int) -> String { prefix + String(format: "%04d", max(1, next)) }
    static func next(prefix: String, start: Int, existing: Set<String>) -> (String, Int) {
        var n = max(1, start)
        while existing.contains(number(prefix: prefix, next: n)) { n += 1 }
        return (number(prefix: prefix, next: n), n + 1)
    }
    static func isDuplicate(_ number: String, id: UUID, documents: [(UUID, String)]) -> Bool {
        documents.contains { $0.0 != id && $0.1.caseInsensitiveCompare(number.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }
    static func revision(_ number: String, existing: Set<String>) -> String {
        var n = 1
        while existing.contains(number + "-R\(n)") { n += 1 }
        return number + "-R\(n)"
    }
}
