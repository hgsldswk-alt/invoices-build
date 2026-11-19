import Foundation

enum ZipStore {
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ 0xffffffff
    }
    static func archive(_ files: [(String, Data)]) throws -> Data {
        guard files.count < 65535 else { throw DataError.tooLarge }
        var output = Data(), central = Data()
        func le16(_ v: UInt16) -> Data { var n = v.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        func le32(_ v: UInt32) -> Data { var n = v.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        for (name, bytes) in files {
            let filename = Data(name.utf8)
            guard bytes.count < Int(UInt32.max), output.count < Int(UInt32.max), filename.count < 65535 else { throw DataError.tooLarge }
            let offset = UInt32(output.count), size = UInt32(bytes.count), crc = crc32(bytes)
            let nameLength = UInt16(filename.count)
            for part in [le32(0x04034b50), le16(20), le16(0x0800), le16(0), le16(0), le16(0x0021),
                         le32(crc), le32(size), le32(size), le16(nameLength), le16(0), filename, bytes] {
                output.append(part)
            }
            for part in [le32(0x02014b50), le16(20), le16(20), le16(0x0800), le16(0), le16(0), le16(0x0021),
                         le32(crc), le32(size), le32(size), le16(nameLength), le16(0), le16(0), le16(0), le16(0),
                         le32(0), le32(offset), filename] {
                central.append(part)
            }
        }
        guard central.count < Int(UInt32.max), output.count < Int(UInt32.max) else { throw DataError.tooLarge }
        let start = UInt32(output.count)
        output.append(central)
        let count = UInt16(files.count)
        for part in [le32(0x06054b50), le16(0), le16(0), le16(count), le16(count), le32(UInt32(central.count)), le32(start), le16(0)] {
            output.append(part)
        }
        return output
    }
}
