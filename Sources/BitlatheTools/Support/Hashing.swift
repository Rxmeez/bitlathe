import Foundation
import CryptoKit
import BitlatheCore

/// Hash functions beyond CryptoKit: SHA-3 / Keccak, BLAKE2b/2s, BLAKE3, CRC32, plus thin wrappers.
public enum Hashing {
    public static func sha256d(_ d: Data) -> Data { Data(SHA256.hash(data: Data(SHA256.hash(data: d)))) }
    public static func md5(_ d: Data) -> Data { Data(Insecure.MD5.hash(data: d)) }
    public static func sha1(_ d: Data) -> Data { Data(Insecure.SHA1.hash(data: d)) }
    public static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
    public static func sha384(_ d: Data) -> Data { Data(SHA384.hash(data: d)) }
    public static func sha512(_ d: Data) -> Data { Data(SHA512.hash(data: d)) }
}

// MARK: - Keccak / SHA-3

public struct Keccak {
    static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000, 0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A, 0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A, 0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    static let rotations: [Int] = [0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14]
    static let piLanes: [Int] = [0, 10, 20, 5, 15, 16, 1, 11, 21, 6, 7, 17, 2, 12, 22, 23, 8, 18, 3, 13, 14, 24, 9, 19, 4]

    static func keccakF(_ s: inout [UInt64]) {
        for rc in roundConstants {
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { c[x] = s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20] }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ (c[(x + 1) % 5] << 1 | c[(x + 1) % 5] >> 63)
                for y in stride(from: 0, to: 25, by: 5) { s[y + x] ^= d }
            }
            var b = [UInt64](repeating: 0, count: 25)
            for i in 0..<25 {
                let r = rotations[i]
                b[piLanes[i]] = r == 0 ? s[i] : (s[i] << UInt64(r) | s[i] >> UInt64(64 - r))
            }
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 { s[y + x] = b[y + x] ^ (~b[y + (x + 1) % 5] & b[y + (x + 2) % 5]) }
            }
            s[0] ^= rc
        }
    }

    /// rate in bytes; suffix 0x06 for SHA-3, 0x01 for Keccak, 0x1F for SHAKE.
    public static func hash(_ data: Data, rate: Int, outputLength: Int, suffix: UInt8) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        var block = [UInt8](repeating: 0, count: rate)
        var blockLen = 0
        func absorbBlock() {
            for i in 0..<(rate / 8) {
                var lane: UInt64 = 0
                for j in 0..<8 { lane |= UInt64(block[i * 8 + j]) << UInt64(8 * j) }
                state[i] ^= lane
            }
            keccakF(&state)
        }
        for byte in data {
            block[blockLen] = byte
            blockLen += 1
            if blockLen == rate { absorbBlock(); blockLen = 0; block = [UInt8](repeating: 0, count: rate) }
        }
        block[blockLen] ^= suffix
        block[rate - 1] ^= 0x80
        absorbBlock()
        var out = Data()
        while out.count < outputLength {
            for i in 0..<(rate / 8) where out.count < outputLength {
                for j in 0..<8 where out.count < outputLength { out.append(UInt8((state[i] >> UInt64(8 * j)) & 0xFF)) }
            }
            if out.count < outputLength { keccakF(&state) }
        }
        return out
    }

    public static func sha3(_ data: Data, bits: Int) -> Data { hash(data, rate: 200 - bits / 4, outputLength: bits / 8, suffix: 0x06) }
    public static func keccak(_ data: Data, bits: Int) -> Data { hash(data, rate: 200 - bits / 4, outputLength: bits / 8, suffix: 0x01) }
    public static func shake128(_ data: Data, outputBytes: Int) -> Data { hash(data, rate: 168, outputLength: outputBytes, suffix: 0x1F) }
    public static func shake256(_ data: Data, outputBytes: Int) -> Data { hash(data, rate: 136, outputLength: outputBytes, suffix: 0x1F) }
}

// MARK: - BLAKE2b

public struct Blake2b {
    static let iv: [UInt64] = [0x6A09E667F3BCC908, 0xBB67AE8584CAA73B, 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1, 0x510E527FADE682D1, 0x9B05688C2B3E6C1F, 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179]
    static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3], [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8], [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13], [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11], [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10], [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    ]

    public static func hash(_ data: Data, outputLength: Int = 64, key: Data = Data()) -> Data {
        var h = iv
        h[0] ^= 0x01010000 ^ (UInt64(key.count) << 8) ^ UInt64(outputLength)
        var input = [UInt8](data)
        if !key.isEmpty { input = [UInt8](key) + [UInt8](repeating: 0, count: 128 - key.count) + input }
        var t: UInt64 = 0
        var offset = 0
        func compress(_ block: [UInt8], last: Bool) {
            var m = [UInt64](repeating: 0, count: 16)
            for i in 0..<16 { for j in 0..<8 { m[i] |= UInt64(block[i * 8 + j]) << UInt64(8 * j) } }
            var v = h + iv
            v[12] ^= t
            if last { v[14] = ~v[14] }
            func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
                v[a] = v[a] &+ v[b] &+ x; v[d] = (v[d] ^ v[a]) >> 32 | (v[d] ^ v[a]) << 32
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]) >> 24 | (v[b] ^ v[c]) << 40
                v[a] = v[a] &+ v[b] &+ y; v[d] = (v[d] ^ v[a]) >> 16 | (v[d] ^ v[a]) << 48
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]) >> 63 | (v[b] ^ v[c]) << 1
            }
            for r in 0..<12 {
                let s = sigma[r]
                g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]]); g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]])
                g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]]); g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
        }
        while input.count - offset > 128 {
            t += 128
            compress(Array(input[offset..<offset + 128]), last: false)
            offset += 128
        }
        let rest = Array(input[offset...])
        t += UInt64(rest.count)
        compress(rest + [UInt8](repeating: 0, count: 128 - rest.count), last: true)
        var out = Data()
        for i in 0..<8 { for j in 0..<8 where out.count < outputLength { out.append(UInt8((h[i] >> UInt64(8 * j)) & 0xFF)) } }
        return out
    }
}

// MARK: - BLAKE2s

public struct Blake2s {
    static let iv: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]

    public static func hash(_ data: Data, outputLength: Int = 32, key: Data = Data()) -> Data {
        var h = iv
        h[0] ^= 0x01010000 ^ (UInt32(key.count) << 8) ^ UInt32(outputLength)
        var input = [UInt8](data)
        if !key.isEmpty { input = [UInt8](key) + [UInt8](repeating: 0, count: 64 - key.count) + input }
        var t: UInt64 = 0
        var offset = 0
        func compress(_ block: [UInt8], last: Bool) {
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 { for j in 0..<4 { m[i] |= UInt32(block[i * 4 + j]) << UInt32(8 * j) } }
            var v = h + iv
            v[12] ^= UInt32(t & 0xFFFF_FFFF)
            v[13] ^= UInt32(t >> 32)
            if last { v[14] = ~v[14] }
            func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
                v[a] = v[a] &+ v[b] &+ x; v[d] = (v[d] ^ v[a]) >> 16 | (v[d] ^ v[a]) << 16
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]) >> 12 | (v[b] ^ v[c]) << 20
                v[a] = v[a] &+ v[b] &+ y; v[d] = (v[d] ^ v[a]) >> 8 | (v[d] ^ v[a]) << 24
                v[c] = v[c] &+ v[d]; v[b] = (v[b] ^ v[c]) >> 7 | (v[b] ^ v[c]) << 25
            }
            for r in 0..<10 {
                let s = Blake2b.sigma[r]
                g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]]); g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]])
                g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]]); g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
        }
        while input.count - offset > 64 {
            t += 64
            compress(Array(input[offset..<offset + 64]), last: false)
            offset += 64
        }
        let rest = Array(input[offset...])
        t += UInt64(rest.count)
        compress(rest + [UInt8](repeating: 0, count: 64 - rest.count), last: true)
        var out = Data()
        for i in 0..<8 { for j in 0..<4 where out.count < outputLength { out.append(UInt8((h[i] >> UInt32(8 * j)) & 0xFF)) } }
        return out
    }
}

// MARK: - BLAKE3

public struct Blake3 {
    static let iv: [UInt32] = Blake2s.iv
    static let msgPermutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
    static let chunkStart: UInt32 = 1, chunkEnd: UInt32 = 2, parent: UInt32 = 4, root: UInt32 = 8, keyedHash: UInt32 = 16

    static func g(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ mx: UInt32, _ my: UInt32) {
        s[a] = s[a] &+ s[b] &+ mx; s[d] = (s[d] ^ s[a]).rotated(16)
        s[c] = s[c] &+ s[d]; s[b] = (s[b] ^ s[c]).rotated(12)
        s[a] = s[a] &+ s[b] &+ my; s[d] = (s[d] ^ s[a]).rotated(8)
        s[c] = s[c] &+ s[d]; s[b] = (s[b] ^ s[c]).rotated(7)
    }

    static func compress(_ cv: [UInt32], _ block: [UInt32], _ counter: UInt64, _ blockLen: UInt32, _ flags: UInt32) -> [UInt32] {
        var s = cv + [iv[0], iv[1], iv[2], iv[3], UInt32(counter & 0xFFFF_FFFF), UInt32(counter >> 32), blockLen, flags]
        var m = block
        for i in 0..<7 {
            g(&s, 0, 4, 8, 12, m[0], m[1]); g(&s, 1, 5, 9, 13, m[2], m[3]); g(&s, 2, 6, 10, 14, m[4], m[5]); g(&s, 3, 7, 11, 15, m[6], m[7])
            g(&s, 0, 5, 10, 15, m[8], m[9]); g(&s, 1, 6, 11, 12, m[10], m[11]); g(&s, 2, 7, 8, 13, m[12], m[13]); g(&s, 3, 4, 9, 14, m[14], m[15])
            if i < 6 { m = msgPermutation.map { m[$0] } }
        }
        for i in 0..<8 { s[i] ^= s[i + 8]; s[i + 8] ^= cv[i] }
        return s
    }

    static func words(_ bytes: ArraySlice<UInt8>) -> [UInt32] {
        var w = [UInt32](repeating: 0, count: 16)
        var padded = Array(bytes)
        padded += [UInt8](repeating: 0, count: 64 - padded.count)
        for i in 0..<16 { for j in 0..<4 { w[i] |= UInt32(padded[i * 4 + j]) << UInt32(8 * j) } }
        return w
    }

    struct Output {
        var cv: [UInt32]; var block: [UInt32]; var counter: UInt64; var blockLen: UInt32; var flags: UInt32
        func chainingValue() -> [UInt32] { Array(compress(cv, block, counter, blockLen, flags).prefix(8)) }
        func rootBytes(_ n: Int) -> Data {
            var out = Data()
            var c: UInt64 = 0
            while out.count < n {
                let w = compress(cv, block, c, blockLen, flags | root)
                for word in w { for j in 0..<4 where out.count < n { out.append(UInt8((word >> UInt32(8 * j)) & 0xFF)) } }
                c += 1
            }
            return out
        }
    }

    static func chunkOutput(_ chunk: ArraySlice<UInt8>, key: [UInt32], counter: UInt64, flags: UInt32) -> Output {
        var cv = key
        let blocks = stride(from: chunk.startIndex, to: max(chunk.endIndex, chunk.startIndex + 1), by: 64).map { chunk[$0..<min($0 + 64, chunk.endIndex)] }
        for (i, b) in blocks.enumerated() {
            var f = flags
            if i == 0 { f |= chunkStart }
            if i == blocks.count - 1 { return Output(cv: cv, block: words(b), counter: counter, blockLen: UInt32(b.count), flags: f | chunkEnd) }
            cv = Array(compress(cv, words(b), counter, UInt32(b.count), f).prefix(8))
        }
        return Output(cv: cv, block: words([]), counter: counter, blockLen: 0, flags: flags | chunkStart | chunkEnd)
    }

    static func parentOutput(_ l: [UInt32], _ r: [UInt32], key: [UInt32], flags: UInt32) -> Output {
        Output(cv: key, block: l + r, counter: 0, blockLen: 64, flags: flags | parent)
    }

    public static func hash(_ data: Data, outputLength: Int = 32, key: Data? = nil) -> Data {
        var k = iv
        var flags: UInt32 = 0
        if let key, key.count == 32 {
            let kb = [UInt8](key)
            var kw = [UInt32](repeating: 0, count: 8)
            for i in 0..<8 {
                for j in 0..<4 {
                    let shift = UInt32(8 * j)
                    kw[i] |= UInt32(kb[i * 4 + j]) << shift
                }
            }
            k = kw
            flags = keyedHash
        }
        let bytes = [UInt8](data)
        if bytes.isEmpty { return chunkOutput(bytes[...], key: k, counter: 0, flags: flags).rootBytes(outputLength) }
        var cvStack: [[UInt32]] = []
        var chunkCounter: UInt64 = 0
        var offset = 0
        var lastOutput: Output?
        while offset < bytes.count {
            let end = min(offset + 1024, bytes.count)
            let out = chunkOutput(bytes[offset..<end], key: k, counter: chunkCounter, flags: flags)
            if end == bytes.count { lastOutput = out; break }
            var cv = out.chainingValue()
            chunkCounter += 1
            var total = chunkCounter
            while total & 1 == 0 {
                cv = parentOutput(cvStack.removeLast(), cv, key: k, flags: flags).chainingValue()
                total >>= 1
            }
            cvStack.append(cv)
            offset = end
        }
        var output = lastOutput!   // swiftlint:disable:this force_unwrapping
        while let left = cvStack.popLast() {
            output = parentOutput(left, output.chainingValue(), key: k, flags: flags)
        }
        return output.rootBytes(outputLength)
    }
}

extension UInt32 {
    func rotated(_ n: UInt32) -> UInt32 { (self >> n) | (self << (32 - n)) }
}
