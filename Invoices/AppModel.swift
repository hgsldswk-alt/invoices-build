import Foundation
import SwiftData
import SwiftUI
import WidgetKit

@MainActor final class AppModel: ObservableObject {
    let container: ModelContainer
    let context: ModelContext
    let ephemeral: Bool
    let preferences: UserDefaults
    let scheduler: ReminderScheduler
    let purchases = PurchaseStore()
    @Published var documents: [Document] = []
    @Published var clients: [Client] = []
    @Published var items: [Item] = []
    @Published var business: Business
    @Published var selected: Document?
    @Published var section = "invoices"
    @Published var revision = 0
    @Published var entitlement = Entitlement()
    @Published var error: String?
    @Published var cloudStatus = ""
    @Published var now = Date()
    @Published var toast: String?
    @Published var milestone: String?
    @Published var showMilestone = false
    @Published var showInvite = false
    @Published var showPaywall = false
    @Published var pendingReminder: UUID?
    @Published var shouldReview = false
    var undoAction: (() -> Void)?
    private var toastTask: Task<Void, Never>?
    var hasPro: Bool { entitlement.hasPro(at: now) }
    var liveDocuments: [Document] { documents.filter { $0.deletedAt == nil } }
    var receivableDocuments: [Document] {
        let invoices = liveDocuments.filter { $0.kind == "invoice" }
        let ids = Set(invoices.map(\.id))
        return invoices.filter { d in d.depositParentID.map { !ids.contains($0) } ?? true }
    }
    var cloudEnabled: Bool { preferences.bool(forKey: "cloudEnabled") }
    var faceLock: Bool { preferences.bool(forKey: "faceLock") }
    private struct Startup {
        let inMemory: Bool
        let preferences: UserDefaults
        let entitlement: Entitlement
        let cloudID: String?
        let needsTrialMarker: Bool

        init(inMemory: Bool) {
            self.inMemory = inMemory
            preferences = inMemory ? UserDefaults(suiteName: "invoices.ephemeral.\(UUID())")! : .standard
            if inMemory { preferences.set(false, forKey: "cloudEnabled") }
            entitlement = preferences.data(forKey: "entitlement").flatMap { try? JSONDecoder().decode(Entitlement.self, from: $0) } ?? Entitlement()
            if !inMemory && preferences.bool(forKey: "cloudEnabled") && entitlement.canUseICloud {
                cloudID = Bundle.main.object(forInfoDictionaryKey: "InvoicesCloudContainer") as? String ?? "iCloud.com.hgsldswk.invoices"
            } else {
                cloudID = nil
            }
            needsTrialMarker = !inMemory && !Launch.isFree && entitlement.proStartedAt == nil
        }
    }

    private struct OpenedStorage: Sendable {
        let container: ModelContainer
        let status: String
        let trialStart: Date?
    }

    static func load(scheduler: ReminderScheduler) async throws -> AppModel {
        let startup = Startup(inMemory: Launch.ephemeral)
        let storage = try await Task.detached(priority: .userInitiated) { [inMemory = startup.inMemory, cloudID = startup.cloudID, needsTrialMarker = startup.needsTrialMarker] in
            try AppModel.openStorage(inMemory: inMemory, cloudID: cloudID, needsTrialMarker: needsTrialMarker)
        }.value
        return try AppModel(startup: startup, storage: storage, scheduler: scheduler)
    }

    convenience init(inMemory: Bool) throws {
        let startup = Startup(inMemory: inMemory)
        let storage = try Self.openStorage(inMemory: inMemory, cloudID: startup.cloudID, needsTrialMarker: startup.needsTrialMarker)
        try self.init(startup: startup, storage: storage, scheduler: ReminderScheduler())
    }

    private nonisolated static func openStorage(inMemory: Bool, cloudID: String?, needsTrialMarker: Bool) throws -> OpenedStorage {
        let schema = Schema([Business.self,Client.self,Item.self,Document.self,LineItem.self,Payment.self,Attachment.self])
        let container: ModelContainer
        let status: String
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Invoices", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloudID.map { .private($0) } ?? .none)])
            status = cloudID == nil ? L.t("Stored on this device") : L.t("iCloud enabled · Changes sync when connected.")
        } catch where cloudID != nil {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Invoices", schema: schema, cloudKitDatabase: .none)])
            status = L.t("iCloud unavailable · Using local storage.")
        }
        return OpenedStorage(container: container, status: status, trialStart: needsTrialMarker ? TrialMarker.start(Date()) : nil)
    }

    private init(startup: Startup, storage: OpenedStorage, scheduler: ReminderScheduler) throws {
        ephemeral = startup.inMemory
        preferences = startup.preferences
        container = storage.container
        self.scheduler = scheduler
        cloudStatus = storage.status
        context = ModelContext(container); context.autosaveEnabled = true
        let existing = try context.fetch(FetchDescriptor<Business>())
        if let first = existing.first { business = first } else { let b = Business(); context.insert(b); business = b }
        entitlement = startup.entitlement
        if !Launch.isFree && entitlement.proStartedAt == nil { entitlement.proStartedAt = storage.trialStart ?? Date() }
        if ProcessInfo.processInfo.arguments.contains("-expired") { entitlement.proStartedAt = Date().addingTimeInterval(-40 * 86400); entitlement.trialClaimedAt = nil; entitlement.purchasedPro = false }
        try reload()
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") }) && documents.isEmpty { Demo.seed(self); try reload() }
        now = Date()
        for d in documents where d.deletedAt.map({ now.timeIntervalSince($0) >= 30 * 86400 }) == true { context.delete(d) }
        try context.save(); try reload()
        if documents.isEmpty { selected = newDocument() }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-estimates") { section = "estimates" }; if args.contains("-clients") { section = "clients" }
        if args.contains("-more") || args.contains("-reports") { section = "more" }
        if args.contains("-editor") || args.contains("-preview") { selected = documents.first { $0.number == "INV-0042" } }
        showPaywall = !Launch.isFree && args.contains("-paywall")
        showMilestone = args.contains("-share-milestone"); showInvite = args.contains("-invite")
        if args.contains("-paid-toast"), let d = documents.first(where: { $0.number == "INV-0042" }) { markPaid(d) }
        scheduler.onOpen = { [weak self] id, kind in self?.openNotification(id, kind: kind) }
        if let pending = scheduler.pendingOpen { openNotification(pending.0, kind: pending.1); scheduler.pendingOpen = nil }
        purchases.onEntitlement = { [weak self] pro, trial in
            guard let self else { return }; self.entitlement.purchasedPro = pro
            if let trial { self.entitlement.trialClaimedAt = min(self.entitlement.trialClaimedAt ?? trial, trial) }
            self.persistEntitlement(); self.updateSnapshot()
        }
        persistEntitlement(); updateSnapshot()
    }
    func reload() throws {
        documents = try context.fetch(FetchDescriptor<Document>(sortBy: [SortDescriptor(\Document.createdAt, order: .reverse)]))
        clients = try context.fetch(FetchDescriptor<Client>(sortBy: [SortDescriptor(\Client.lastUsed, order: .reverse)]))
        items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.lastUsed, order: .reverse)]))
        revision += 1
    }
    func save(requestNotifications: Bool = false) {
        do { try context.save(); try reload(); error = nil; now = Date(); updateSnapshot(); reschedule(request: requestNotifications) }
        catch { self.error = L.t("Could not save. Keep the app open and export a backup.") }
    }
    func persistEntitlement() { if let bytes = try? JSONEncoder().encode(entitlement) { preferences.set(bytes, forKey: "entitlement") } }
    @discardableResult func newDocument(kind: String = "invoice") -> Document {
        let s = business.settings
        let (number, next) = Numbering.next(prefix: kind == "invoice" ? s.invoicePrefix : s.estimatePrefix, start: kind == "invoice" ? s.nextInvoiceNumber : s.nextEstimateNumber, existing: Set(documents.map(\.number)))
        let d = Document(kind: kind, number: number); context.insert(d)
        if kind == "invoice" { business.settings.nextInvoiceNumber = next } else { business.settings.nextEstimateNumber = next }
        d.title = kind == "invoice" ? s.invoiceTitle : s.estimateWord; d.currencyCode = s.currencyCode; d.terms = s.defaultTerms
        d.dueDate = Calendar.current.date(byAdding: .day, value: d.terms, to: Date())
        d.tax1 = s.defaultTax1; d.tax2 = s.defaultTax2; d.pricesIncludeTax = s.pricesIncludeTax; d.notes = s.defaultNotes; d.termsText = s.defaultTermsText
        d.lines = []; d.payments = []; d.attachments = []
        save(); return d
    }
    func pick(_ c: Client, for d: Document) {
        d.client = c; d.clientName = c.name; d.clientEmail = c.email; d.clientPhone = c.phone; d.clientAddress = c.address; c.lastUsed = Date()
        if let currency = c.currencyCode { d.currencyCode = currency }
        if let terms = c.defaultTerms { d.terms = terms; d.dueDate = Calendar.current.date(byAdding: .day, value: terms, to: d.issueDate) }
        if let tax = c.defaultTax { d.tax1 = tax }
        save()
    }
    func ensureClient(_ d: Document) {
        guard d.client == nil, !d.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let c = clients.first(where: { $0.name.caseInsensitiveCompare(d.clientName) == .orderedSame }) { d.client = c; return }
        let c = Client(name: d.clientName); c.email = d.clientEmail; c.phone = d.clientPhone; c.address = d.clientAddress
        context.insert(c); d.client = c
    }
    func editClientName(_ name: String, for d: Document) {
        if d.client != nil && d.clientName != name {
            d.client = nil; d.clientEmail = ""; d.clientPhone = ""; d.clientAddress = ""
        }
        d.clientName = name
    }
    func appendLine(_ d: Document, item: Item? = nil) -> LineItem {
        let line = LineItem(name: item?.name ?? "", price: item?.unitPrice ?? 0)
        line.order = d.orderedLines.count; line.unit = item?.unit ?? "ea"; line.details = item?.details ?? ""; line.taxable = item?.taxable ?? true
        context.insert(line); var all = d.lines ?? []; all.append(line); d.lines = all; item?.lastUsed = Date(); save(); return line
    }
    @discardableResult func duplicate(_ source: Document, asInvoice: Bool = false, revision: Bool = false) -> Document {
        let copy = newDocument(kind: asInvoice ? "invoice" : source.kind), number = copy.number
        var record = DocumentRecord(source)
        record.id = copy.id; record.number = revision ? Numbering.revision(source.number, existing: Set(documents.map(\.number))) : number
        record.kind = asInvoice ? "invoice" : source.kind; record.title = asInvoice ? business.settings.invoiceTitle : source.title
        record.status = "draft"; record.issueDate = Date(); record.dueDate = Calendar.current.date(byAdding: .day, value: source.terms, to: Date())
        record.createdAt = Date(); record.updatedAt = Date(); record.sentAt = nil; record.deletedAt = nil; record.payments = []
        record.clientSignature = nil; record.signedAt = nil; record.recurrence = "none"; record.recurrenceNext = nil; record.depositParentID = nil; record.linkedDocumentID = nil
        record.lines = record.lines.map { var l = $0; l.id = UUID(); return l }
        record.attachments = record.attachments.map { var a = $0; a.id = UUID(); return a }
        record.apply(to: copy, context: context, clients: clients); save(); return copy
    }
    func convert(_ source: Document) {
        if let linked = source.linkedDocumentID, let existing = documents.first(where: { $0.id == linked }) { selected = existing; return }
        let invoice = duplicate(source, asInvoice: true)
        source.status = "converted"; source.linkedDocumentID = invoice.id; invoice.linkedDocumentID = source.id; selected = invoice; save()
    }
    func depositInvoice(from source: Document, percent: Decimal? = nil, amount: Decimal? = nil) -> Document {
        let requested = Money.round(amount ?? source.totals.total * max(0, min(100, percent ?? 50)) / 100, currency: source.currencyCode)
        let d = newDocument(); d.client = source.client; d.clientName = source.clientName; d.clientEmail = source.clientEmail; d.clientAddress = source.clientAddress; d.currencyCode = source.currencyCode
        d.tax1Rate = 0; d.tax2Rate = 0; d.depositParentID = source.id; source.depositRequested = requested
        let line = appendLine(d); line.name = "Deposit for " + source.number; line.unitPrice = max(0, min(source.totals.balance, requested)); line.taxable = false
        save(); return d
    }
    func syncDepositPayments() {
        let sources = documents.filter { $0.depositParentID != nil && $0.deletedAt == nil }
        for parent in documents {
            let deposits = sources.filter { $0.depositParentID == parent.id }
            let sourceIDs = Set(deposits.flatMap { ($0.payments ?? []).map(\.id) })
            for payment in parent.payments ?? [] where payment.sourcePaymentID != nil && !sourceIDs.contains(payment.sourcePaymentID!) { context.delete(payment) }
            var list = (parent.payments ?? []).filter { $0.sourcePaymentID == nil || sourceIDs.contains($0.sourcePaymentID!) }
            for deposit in deposits {
                for payment in deposit.payments ?? [] {
                    let mirror = list.first(where: { $0.sourcePaymentID == payment.id }) ?? Payment()
                    if mirror.modelContext == nil { context.insert(mirror); list.append(mirror) }
                    mirror.sourcePaymentID = payment.id; mirror.date = payment.date; mirror.amount = payment.amount; mirror.method = payment.method; mirror.note = "Deposit received · " + deposit.number
                }
            }
            parent.payments = list
        }
    }
    func addPayment(_ d: Document, amount: Decimal, method: String, date: Date = Date(), note: String = "") {
        guard amount > 0 else { return }
        let p = Payment(amount: Money.round(amount, currency: d.currencyCode), method: method); p.date = date; p.note = note
        context.insert(p); var all = d.payments ?? []; all.append(p); d.payments = all
        business.settings.lastPaymentMethod = method; syncDepositPayments(); save(); progress()
    }
    func markPaid(_ d: Document) {
        let amount = d.totals.balance; guard amount > 0 else { return }
        let previousIDs = Set((d.payments ?? []).map(\.id))
        addPayment(d, amount: amount, method: business.settings.lastPaymentMethod)
        notify(L.f("Paid %@", Money.format(amount, currency: d.currencyCode))) { [weak self, weak d] in
            guard let self, let d else { return }
            for p in d.payments ?? [] where !previousIDs.contains(p.id) { self.context.delete(p) }
            d.payments = (d.payments ?? []).filter { previousIDs.contains($0.id) }; self.syncDepositPayments(); self.save()
        }
    }
    func sent(_ d: Document) {
        let old = d.status, oldDate = d.sentAt
        d.status = "sent"; d.sentAt = Date(); save(); progress()
        notify(L.t("Sent")) { [weak self, weak d] in guard let self, let d else { return }; d.status = old; d.sentAt = oldDate; self.save() }
    }
    func notify(_ value: String, undo: (() -> Void)? = nil) {
        toastTask?.cancel(); toast = value; undoAction = undo
        toastTask = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); guard !Task.isCancelled else { return }; toast = nil; undoAction = nil; milestone = nil }
    }
    func undoToast() { undoAction?(); undoAction = nil; toast = nil; milestone = nil; toastTask?.cancel() }
    func progress() {
        let paid = liveDocuments.filter { $0.kind == "invoice" && $0.computedStatus() == "paid" }.count
        if ReviewGate.shouldRequest(paidCount: paid, alreadyRequested: preferences.bool(forKey: "reviewRequested")) { shouldReview = true; preferences.set(true, forKey: "reviewRequested") }
        var receipts: [String: Decimal] = [:]
        for d in liveDocuments where d.kind == "invoice" { receipts[d.currencyCode, default: 0] += d.sortedPayments.filter { $0.sourcePaymentID == nil }.reduce(0) { $0 + $1.amount } }
        var seen = Set(preferences.stringArray(forKey: "milestones") ?? [])
        if let reached = Milestone.reached(sentCount: liveDocuments.filter { $0.kind == "invoice" && $0.sentAt != nil }.count, receivedByCurrency: receipts, seen: seen) { milestone = reached; seen.insert(reached); preferences.set(Array(seen), forKey: "milestones") }
    }
    func delete(_ d: Document) { d.deletedAt = Date(); syncDepositPayments(); save() }
    func openNotification(_ id: UUID, kind: String) {
        guard let d = liveDocuments.first(where: { $0.id == id }) else { return }
        if kind == "recurring", let next = d.recurrenceNext, Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: Date()) {
            let draft = duplicate(d); d.recurrenceNext = ReminderPlan.next(next, period: d.recurrence); selected = draft; save()
        } else if kind == "reminder" { selected = d; pendingReminder = d.id }
        else { selected = d }
    }
    func reschedule(request: Bool = false) {
        guard !ephemeral else { return }
        let values = liveDocuments.filter { $0.kind == "invoice" }.map { d in
            ReminderCandidate(id: d.id, number: d.number, client: d.clientName, due: d.dueDate, unpaid: d.status != "draft" && d.totals.balance > 0, recurring: d.recurrence == "none" ? nil : d.recurrenceNext)
        }
        Task { await scheduler.schedule(values, enabled: business.settings.remindersOn && entitlement.canUseReminders, request: request, ephemeral: ephemeral); objectWillChange.send() }
    }
    func updateSnapshot() {
        guard !ephemeral else { return }
        let invoices = receivableDocuments.filter { $0.totals.balance > 0 }
        var balances: [String: Decimal] = [:]
        for d in invoices { balances[d.currencyCode, default: 0] += d.totals.balance }
        var snapshot = WidgetSnapshot(); snapshot.entitlement = entitlement
        snapshot.balances = balances.keys.sorted().map { WidgetBalance(currency: $0, amount: Money.format(balances[$0, default: 0], currency: $0)) }
        snapshot.overdue = invoices.filter { $0.computedStatus() == "overdue" }.count
        snapshot.invoices = invoices.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.prefix(3).map { WidgetInvoice(id: $0.id, name: $0.clientName, number: $0.number, amount: Money.format($0.totals.balance, currency: $0.currencyCode)) }
        if let url = WidgetSnapshot.url, let bytes = try? JSONEncoder().encode(snapshot) { try? bytes.write(to: url, options: .atomic); WidgetCenter.shared.reloadAllTimelines() }
    }
    var backup: BackupData { BackupData(business: BusinessRecord(business), clients: clients.map(ClientRecord.init), items: items.map(ItemRecord.init), documents: documents.map(DocumentRecord.init)) }
    func restore(_ data: BackupData, replace: Bool) throws {
        selected = nil
        try Backup.restore(data, context: context, replace: replace)
        try reload()
        syncDepositPayments(); save()
    }
    func require(_ allowed: Bool, perform: () -> Void) { if allowed { perform() } else { showPaywall = true } }
}
