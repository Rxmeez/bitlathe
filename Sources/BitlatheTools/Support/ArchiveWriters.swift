import Foundation
import BitlatheCore

/// Minimal writers for ZIP (stored), ICNS and ICO containers.
enum ArchiveWriters {
    static func zip(_ entries: [(path: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offsets: [UInt32] = []
        func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
        func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let dosTime = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        let dosDate = (((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        for (path, data) in entries {
            let name = Data(path.utf8)
            let crc = Compressor.crc32(data)
            offsets.append(UInt32(out.count))
            var local = Data()
            local += le32(0x04034b50); local += le16(20); local += le16(0x0800); local += le16(0); local += le16(dosTime); local += le16(dosDate)
            local += le32(crc); local += le32(UInt32(data.count)); local += le32(UInt32(data.count)); local += le16(name.count); local += le16(0); local += name; local += data
            out += local
            var dir = Data()
            dir += le32(0x02014b50); dir += le16(20); dir += le16(20); dir += le16(0x0800); dir += le16(0); dir += le16(dosTime); dir += le16(dosDate)
            dir += le32(crc); dir += le32(UInt32(data.count)); dir += le32(UInt32(data.count)); dir += le16(name.count); dir += le16(0); dir += le16(0); dir += le16(0); dir += le16(0); dir += le32(0)
            dir += le32(offsets.last ?? 0); dir += name
            central += dir
        }
        let centralOffset = UInt32(out.count)
        out += central
        var end = Data()
        end += le32(0x06054b50); end += le16(0); end += le16(0); end += le16(entries.count); end += le16(entries.count); end += le32(UInt32(central.count)); end += le32(centralOffset); end += le16(0)
        out += end
        return out
    }

    /// ICNS with PNG-encoded entries. sizes: pixel size → PNG data.
    static func icns(_ pngs: [Int: Data]) -> Data {
        let types: [Int: String] = [16: "icp4", 32: "icp5", 64: "icp6", 128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"]
        let retina: [Int: String] = [32: "ic11", 64: "ic12", 256: "ic13", 512: "ic14"]   // @2x variants
        var body = Data()
        func be32(_ v: UInt32) -> Data { var x = v.bigEndian; return Data(bytes: &x, count: 4) }
        for (size, type) in types.sorted(by: { $0.key < $1.key }) {
            guard let png = pngs[size] else { continue }
            body += Data(type.utf8) + be32(UInt32(png.count + 8)) + png
        }
        for (size, type) in retina.sorted(by: { $0.key < $1.key }) {
            guard let png = pngs[size] else { continue }
            body += Data(type.utf8) + be32(UInt32(png.count + 8)) + png
        }
        return Data("icns".utf8) + be32(UInt32(body.count + 8)) + body
    }

    /// ICO with PNG-encoded entries (sizes up to 256).
    static func ico(_ pngs: [(Int, Data)]) -> Data {
        var out = Data()
        func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
        func le32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
        out += le16(0) + le16(1) + le16(pngs.count)
        var offset = 6 + 16 * pngs.count
        var images = Data()
        for (size, png) in pngs {
            out += Data([UInt8(size >= 256 ? 0 : size), UInt8(size >= 256 ? 0 : size), 0, 0]) + le16(1) + le16(32) + le32(png.count) + le32(offset)
            images += png
            offset += png.count
        }
        return out + images
    }
}
