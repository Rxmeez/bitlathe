import Foundation
import zlib
import Compression
import BitlatheCore

enum Compressor {
    enum Algorithm: String, CaseIterable {
        case gzip, deflate, zlib, brotli, lzfse, lz4, lzma

        var title: String {
            switch self {
            case .gzip: "Gzip"
            case .deflate: "Deflate (raw)"
            case .zlib: "Zlib"
            case .brotli: "Brotli"
            case .lzfse: "LZFSE"
            case .lz4: "LZ4"
            case .lzma: "LZMA"
            }
        }
    }

    static func sniff(_ data: Data) -> Algorithm? {
        guard data.count >= 2 else { return nil }
        let b = [UInt8](data.prefix(6))
        if b[0] == 0x1F, b[1] == 0x8B { return .gzip }
        if b[0] == 0x78, [0x01, 0x5E, 0x9C, 0xDA, 0x20, 0x7D, 0xBB, 0xF9].contains(b[1]) { return .zlib }
        if b[0] == 0xFD, data.count >= 6, b[1] == 0x37, b[2] == 0x7A, b[3] == 0x58, b[4] == 0x5A { return .lzma }
        if b[0] == 0x62, b[1] == 0x76, b[2] == 0x78 { return .lzfse }  // "bvx"
        if b[0] == 0x04, b[1] == 0x22, b[2] == 0x4D, b[3] == 0x18 { return .lz4 }
        return nil
    }

    static func compress(_ data: Data, algorithm: Algorithm, level: Int = 6) throws -> Data {
        switch algorithm {
        case .gzip: return try zlibCompress(data, windowBits: 15 + 16, level: level)
        case .deflate: return try zlibCompress(data, windowBits: -15, level: level)
        case .zlib: return try zlibCompress(data, windowBits: 15, level: level)
        case .brotli: return try apple(data, encode: true, COMPRESSION_BROTLI)
        case .lzfse: return try apple(data, encode: true, COMPRESSION_LZFSE)
        case .lz4: return try apple(data, encode: true, COMPRESSION_LZ4)
        case .lzma: return try apple(data, encode: true, COMPRESSION_LZMA)
        }
    }

    static func decompress(_ data: Data, algorithm: Algorithm) throws -> Data {
        switch algorithm {
        case .gzip: return try zlibDecompress(data, windowBits: 15 + 16)
        case .deflate: return try zlibDecompress(data, windowBits: -15)
        case .zlib: return try zlibDecompress(data, windowBits: 15)
        case .brotli: return try apple(data, encode: false, COMPRESSION_BROTLI)
        case .lzfse: return try apple(data, encode: false, COMPRESSION_LZFSE)
        case .lz4: return try apple(data, encode: false, COMPRESSION_LZ4)
        case .lzma: return try apple(data, encode: false, COMPRESSION_LZMA)
        }
    }

    private static func zlibCompress(_ input: Data, windowBits: Int32, level: Int) throws -> Data {
        var stream = z_stream()
        var status = deflateInit2_(&stream, Int32(max(0, min(9, level))), Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ToolError("zlib init failed (\(status))") }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, UInt(input.count))) + 64)
        let outCount = output.count
        var inputCopy = input
        let produced: Int = try inputCopy.withUnsafeMutableBytes { inPtr -> Int in
            try output.withUnsafeMutableBytes { outPtr -> Int in
                stream.next_in = inPtr.bindMemory(to: Bytef.self).baseAddress
                stream.avail_in = uInt(input.count)
                stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outCount)
                status = deflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END else { throw ToolError("Compression failed (\(status))") }
                return outCount - Int(stream.avail_out)
            }
        }
        output.count = produced
        return output
    }

    private static func zlibDecompress(_ input: Data, windowBits: Int32) throws -> Data {
        guard !input.isEmpty else { throw ToolError.emptyInput }
        var stream = z_stream()
        var status = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ToolError("zlib init failed (\(status))") }
        defer { inflateEnd(&stream) }
        var output = Data()
        var inputCopy = input
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        try inputCopy.withUnsafeMutableBytes { inPtr in
            stream.next_in = inPtr.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(input.count)
            repeat {
                try buffer.withUnsafeMutableBufferPointer { buf in
                    stream.next_out = buf.baseAddress
                    stream.avail_out = uInt(chunk)
                    status = inflate(&stream, Z_NO_FLUSH)
                    switch status {
                    case Z_OK, Z_STREAM_END, Z_BUF_ERROR: break
                    case Z_DATA_ERROR: throw ToolError("Data is not valid \(windowBits < 0 ? "deflate" : (windowBits > 15 ? "gzip" : "zlib"))", hint: stream.msg.map { String(cString: $0) })
                    case Z_NEED_DICT: throw ToolError("Stream needs a preset dictionary")
                    default: throw ToolError("Decompression failed (\(status))")
                    }
                    output.append(buf.baseAddress!, count: chunk - Int(stream.avail_out))   // swiftlint:disable:this force_unwrapping
                }
                if output.count > 512 * 1024 * 1024 { throw ToolError("Decompressed data exceeds 512 MB") }
            } while status != Z_STREAM_END && stream.avail_in > 0 || (status == Z_OK && stream.avail_out == 0)
        }
        return output
    }

    private static func apple(_ input: Data, encode: Bool, _ algo: compression_algorithm) throws -> Data {
        guard !input.isEmpty else { throw ToolError.emptyInput }
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0, src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)   // swiftlint:disable:this force_unwrapping
        guard compression_stream_init(&stream, encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE, algo) == COMPRESSION_STATUS_OK else {
            throw ToolError("Could not initialise \(encode ? "compressor" : "decompressor")")
        }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        try input.withUnsafeBytes { inPtr in
            stream.src_ptr = inPtr.bindMemory(to: UInt8.self).baseAddress!   // swiftlint:disable:this force_unwrapping
            stream.src_size = input.count
            var status: compression_status
            repeat {
                status = try buffer.withUnsafeMutableBufferPointer { buf -> compression_status in
                    stream.dst_ptr = buf.baseAddress!   // swiftlint:disable:this force_unwrapping
                    stream.dst_size = chunk
                    let st = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    if st == COMPRESSION_STATUS_ERROR { throw ToolError("Data is not valid \(algo == COMPRESSION_BROTLI ? "Brotli" : (algo == COMPRESSION_LZFSE ? "LZFSE" : (algo == COMPRESSION_LZ4 ? "LZ4" : "LZMA")))") }
                    output.append(buf.baseAddress!, count: chunk - stream.dst_size)   // swiftlint:disable:this force_unwrapping
                    return st
                }
                if output.count > 512 * 1024 * 1024 { throw ToolError("Decompressed data exceeds 512 MB") }
            } while status == COMPRESSION_STATUS_OK
        }
        return output
    }

    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { ptr in
            UInt32(zlib.crc32(0, ptr.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
        }
    }

    static func adler32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { ptr in
            UInt32(zlib.adler32(1, ptr.bindMemory(to: Bytef.self).baseAddress, uInt(data.count)))
        }
    }
}
