import Foundation

struct ReminderCandidate: Equatable {
    var id: UUID
    var number: String
    var client: String
    var due: Date?
    var unpaid: Bool
    var recurring: Date?
}
struct PlannedReminder: Equatable {
    var identifier: String
    var documentID: UUID
    var date: Date
    var kind: String
    var title: String
}
enum ReminderPlan {
    static func make(_ documents: [ReminderCandidate], now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for d in documents {
            if d.unpaid, let due = d.due {
                for offset in [0,3,7] {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: due), let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), date > now else { continue }
                    result.append(PlannedReminder(identifier: "invoice-\(d.id)-\(offset)", documentID: d.id, date: date, kind: "reminder", title: d.number + " · " + d.client))
                }
            }
            if let next = d.recurring {
                let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next
                let date = max(now.addingTimeInterval(5), nine)
                result.append(PlannedReminder(identifier: "recurring-\(d.id)", documentID: d.id, date: date, kind: "recurring", title: d.client))
            }
        }
        return Array(result.sorted { $0.date == $1.date ? $0.identifier < $1.identifier : $0.date < $1.date }.prefix(64))
    }
    static func next(_ date: Date, period: String, calendar: Calendar = .current) -> Date? {
        switch period {
        case "weekly": return calendar.date(byAdding: .day, value: 7, to: date)
        case "monthly": return calendar.date(byAdding: .month, value: 1, to: date)
        case "quarterly": return calendar.date(byAdding: .month, value: 3, to: date)
        default: return nil
        }
    }
}
