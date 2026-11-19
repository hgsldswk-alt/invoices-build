import Foundation
import SwiftData

enum DataError: Error { case corrupt, unsupportedVersion, tooLarge }
struct BackupData: Codable, Equatable {
    var version = 1
    var business: BusinessRecord
    var clients: [ClientRecord]
    var items: [ItemRecord]
    var documents: [DocumentRecord]
}
enum Backup {
    static let maximumFileSize = 128_000_000
    static let maximumJSONSize = 96_000_000
    static func export(_ value: BackupData) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard let packed = Zlib.pack(data, limit: maximumJSONSize) else { throw DataError.tooLarge }
        return Data("INVOICES1\n".utf8) + packed
    }
    static func preview(_ data: Data) throws -> BackupData {
        let magic = Data("INVOICES1\n".utf8)
        guard data.count <= maximumFileSize, data.starts(with: magic), let json = Zlib.unpack(Data(data.dropFirst(magic.count)), limit: maximumJSONSize) else { throw DataError.corrupt }
        let decoded = try JSONDecoder().decode(BackupData.self, from: json)
        guard decoded.version == 1 else { throw DataError.unsupportedVersion }
        guard Set(decoded.documents.map(\.id)).count == decoded.documents.count,
              Set(decoded.clients.map(\.id)).count == decoded.clients.count,
              Set(decoded.items.map(\.id)).count == decoded.items.count else { throw DataError.corrupt }
        return decoded
    }
    static func readFile(_ url: URL, limit: Int = maximumFileSize) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var bytes = Data()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            guard bytes.count + chunk.count <= limit else { throw DataError.tooLarge }; bytes.append(chunk)
        }
        return bytes
    }
    @MainActor static func restore(_ value: BackupData, context: ModelContext, replace: Bool) throws {
        let existingDocuments = try context.fetch(FetchDescriptor<Document>())
        let existingClients = try context.fetch(FetchDescriptor<Client>())
        let existingItems = try context.fetch(FetchDescriptor<Item>())
        if replace {
            for d in existingDocuments { context.delete(d) }
            for c in existingClients { context.delete(c) }
            for i in existingItems { context.delete(i) }
            if let business = try context.fetch(FetchDescriptor<Business>()).first { value.business.apply(to: business) }
        }
        var clients = replace ? [] : existingClients
        let clientIDs = Set(clients.map(\.id))
        for record in value.clients where !clientIDs.contains(record.id) { let c = record.make(); context.insert(c); clients.append(c) }
        let itemIDs = Set(replace ? [] : existingItems.map(\.id))
        for record in value.items where !itemIDs.contains(record.id) { context.insert(record.make()) }
        let docIDs = Set(replace ? [] : existingDocuments.map(\.id))
        for record in value.documents where !docIDs.contains(record.id) { let d = Document(); context.insert(d); record.apply(to: d, context: context, clients: clients) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
