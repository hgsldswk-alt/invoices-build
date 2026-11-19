import Foundation

enum Launch {
    static let freePeriod = false
    static func isFree(arguments: [String], freePeriod: Bool = Launch.freePeriod) -> Bool {
        freePeriod && !arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) })
    }
    static var isFree: Bool { isFree(arguments: ProcessInfo.processInfo.arguments) }
    static var ephemeral: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-demo") || ["-uitest-fresh", "-paywall", "-expired", "-paid-mode"].contains($0) }
    }
}
