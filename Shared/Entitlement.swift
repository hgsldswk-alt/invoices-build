import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false
    var trialStart: Date { trialClaimedAt ?? proStartedAt ?? firstOpen }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86400) }
    func isPremium(at now: Date) -> Bool { purchasedPro || (now >= trialStart.addingTimeInterval(-600) && now < trialEnd) }
    func hasPro(at now: Date = Date(), isFree: Bool = Launch.isFree) -> Bool { isFree || isPremium(at: now) }
    func remainingDays(at now: Date) -> Int { max(0, min(30, Int(ceil(trialEnd.timeIntervalSince(now) / 86400)))) }
    func canUseTemplate(_ template: String, at now: Date = Date()) -> Bool { template == "Classic" || hasPro(at: now) }
    var canUsePayQR: Bool { hasPro() }
    var canAttachPhotos: Bool { hasPro() }
    var canClientSign: Bool { hasPro() }
    var canUseReminders: Bool { hasPro() }
    var canUseRecurring: Bool { hasPro() }
    var canSeeReports: Bool { hasPro() }
    var canUseStatement: Bool { hasPro() }
    var canUseICloud: Bool { hasPro() }
    var canUseFaceID: Bool { hasPro() }
    var canImportCSV: Bool { hasPro() }
    var canHideMadeWith: Bool { hasPro() }
    var canUseWidget: Bool { hasPro() }
    var canReadData: Bool { true }
    var canCreateDocument: Bool { true }
    var canEditDocument: Bool { true }
    var canSendDocument: Bool { true }
    var canExportData: Bool { true }
}
