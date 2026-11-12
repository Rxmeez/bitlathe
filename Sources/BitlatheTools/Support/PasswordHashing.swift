import Foundation
import CryptoKit
import CommonCrypto
import BitlatheCore

// MARK: - bcrypt

public enum Bcrypt {
    static let base64Alphabet = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    struct Blowfish {
        var p = BlowfishTables.pInit
        var s = BlowfishTables.sInit

        func f(_ x: UInt32) -> UInt32 {
            let a = s[0][Int(x >> 24)], b = s[1][Int((x >> 16) & 0xFF)], c = s[2][Int((x >> 8) & 0xFF)], d = s[3][Int(x & 0xFF)]
            return ((a &+ b) ^ c) &+ d
        }

        func encrypt(_ l: inout UInt32, _ r: inout UInt32) {
            var left = l, right = r
            for i in 0..<16 {
                left ^= p[i]
                right ^= f(left)
                swap(&left, &right)
            }
            swap(&left, &right)
            right ^= p[16]
            left ^= p[17]
            l = left; r = right
        }

        static func stream(_ data: [UInt8], _ pos: inout Int) -> UInt32 {
            var w: UInt32 = 0
            for _ in 0..<4 {
                w = (w << 8) | UInt32(data[pos % data.count])
                pos += 1
            }
            return w
        }

        mutating func expandKey(_ key: [UInt8], salt: [UInt8]?) {
            var pos = 0
            for i in 0..<18 { p[i] ^= Self.stream(key, &pos) }
            var l: UInt32 = 0, r: UInt32 = 0
            var spos = 0
            for i in stride(from: 0, to: 18, by: 2) {
                if let salt { l ^= Self.stream(salt, &spos); r ^= Self.stream(salt, &spos) }
                encrypt(&l, &r)
                p[i] = l; p[i + 1] = r
            }
            for box in 0..<4 {
                for i in stride(from: 0, to: 256, by: 2) {
                    if let salt { l ^= Self.stream(salt, &spos); r ^= Self.stream(salt, &spos) }
                    encrypt(&l, &r)
                    s[box][i] = l; s[box][i + 1] = r
                }
            }
        }
    }

    static func encode(_ data: [UInt8]) -> String {
        var out = ""
        var i = 0
        while i < data.count {
            let c1 = Int(data[i]); i += 1
            out.append(base64Alphabet[c1 >> 2])
            var c = (c1 & 0x03) << 4
            if i >= data.count { out.append(base64Alphabet[c]); break }
            let c2 = Int(data[i]); i += 1
            c |= c2 >> 4
            out.append(base64Alphabet[c])
            c = (c2 & 0x0F) << 2
            if i >= data.count { out.append(base64Alphabet[c]); break }
            let c3 = Int(data[i]); i += 1
            c |= c3 >> 6
            out.append(base64Alphabet[c])
            out.append(base64Alphabet[c3 & 0x3F])
        }
        return out
    }

    static func decode(_ s: String, count: Int) -> [UInt8]? {
        var map: [Character: Int] = [:]
        for (i, c) in base64Alphabet.enumerated() { map[c] = i }
        let chars = Array(s)
        var out: [UInt8] = []
        var i = 0
        while out.count < count, i + 1 < chars.count {
            guard let c1 = map[chars[i]], let c2 = map[chars[i + 1]] else { return nil }
            out.append(UInt8((c1 << 2) | (c2 >> 4)))
            if out.count >= count || i + 2 >= chars.count { break }
            guard let c3 = map[chars[i + 2]] else { return nil }
            out.append(UInt8(((c2 & 0x0F) << 4) | (c3 >> 2)))
            if out.count >= count || i + 3 >= chars.count { break }
            guard let c4 = map[chars[i + 3]] else { return nil }
            out.append(UInt8(((c3 & 0x03) << 6) | c4))
            i += 4
        }
        return out.count == count ? out : nil
    }

    static func rawHash(password: [UInt8], salt: [UInt8], cost: Int) -> [UInt8] {
        var bf = Blowfish()
        bf.expandKey(password, salt: salt)
        let rounds = 1 << cost
        for _ in 0..<rounds {
            bf.expandKey(password, salt: nil)
            bf.expandKey(salt, salt: nil)
        }
        var words: [UInt32] = []
        let magic = Array("OrpheanBeholderScryDoubt".utf8)
        for i in 0..<6 { words.append(magic[i * 4..<i * 4 + 4].reduce(0) { ($0 << 8) | UInt32($1) }) }
        for _ in 0..<64 {
            for i in stride(from: 0, to: 6, by: 2) {
                var l = words[i], r = words[i + 1]
                bf.encrypt(&l, &r)
                words[i] = l; words[i + 1] = r
            }
        }
        var out: [UInt8] = []
        for w in words { out += [UInt8(w >> 24), UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF)] }
        return Array(out.prefix(23))
    }

    public static func hash(_ password: String, cost: Int = 12, salt: [UInt8]? = nil, version: String = "2b") throws -> String {
        guard (4...31).contains(cost) else { throw ToolError("bcrypt cost must be 4–31") }
        var pw = Array(password.utf8)
        if pw.count > 72 { pw = Array(pw.prefix(72)) }
        pw.append(0)
        let s = salt ?? (0..<16).map { _ in UInt8.random(in: 0...255) }
        let h = rawHash(password: pw, salt: s, cost: cost)
        return "$\(version)$\(String(format: "%02d", cost))$" + encode(s) + encode(h)
    }

    public static func verify(_ password: String, hash: String) throws -> Bool {
        let parts = hash.split(separator: "$").map(String.init)
        guard parts.count == 3, ["2a", "2b", "2y", "2x"].contains(parts[0]), let cost = Int(parts[1]), parts[2].count == 53 else { throw ToolError("Not a bcrypt hash", hint: "Expected $2b$12$<22 char salt><31 char hash>") }
        guard let salt = decode(String(parts[2].prefix(22)), count: 16) else { throw ToolError("Invalid bcrypt salt") }
        let computed = try self.hash(password, cost: cost, salt: salt, version: parts[0])
        return Array(computed.utf8) == Array(hash.utf8)
    }
}

// MARK: - PBKDF2 / scrypt

public enum PBKDF2 {
    public static func sha256(password: Data, salt: Data, iterations: Int, length: Int) -> Data {
        var out = Data(count: length)
        let status = out.withUnsafeMutableBytes { outPtr in
            password.withUnsafeBytes { pwPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwPtr.bindMemory(to: Int8.self).baseAddress, password.count,
                                         saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         outPtr.bindMemory(to: UInt8.self).baseAddress, length)
                }
            }
        }
        precondition(status == kCCSuccess)
        return out
    }
}

public enum Scrypt {
    static func salsa20_8(_ b: inout [UInt32]) {
        var x = b
        func r(_ a: UInt32, _ n: UInt32) -> UInt32 { (a << n) | (a >> (32 - n)) }
        for _ in 0..<4 {
            x[4] ^= r(x[0] &+ x[12], 7); x[8] ^= r(x[4] &+ x[0], 9); x[12] ^= r(x[8] &+ x[4], 13); x[0] ^= r(x[12] &+ x[8], 18)
            x[9] ^= r(x[5] &+ x[1], 7); x[13] ^= r(x[9] &+ x[5], 9); x[1] ^= r(x[13] &+ x[9], 13); x[5] ^= r(x[1] &+ x[13], 18)
            x[14] ^= r(x[10] &+ x[6], 7); x[2] ^= r(x[14] &+ x[10], 9); x[6] ^= r(x[2] &+ x[14], 13); x[10] ^= r(x[6] &+ x[2], 18)
            x[3] ^= r(x[15] &+ x[11], 7); x[7] ^= r(x[3] &+ x[15], 9); x[11] ^= r(x[7] &+ x[3], 13); x[15] ^= r(x[11] &+ x[7], 18)
            x[1] ^= r(x[0] &+ x[3], 7); x[2] ^= r(x[1] &+ x[0], 9); x[3] ^= r(x[2] &+ x[1], 13); x[0] ^= r(x[3] &+ x[2], 18)
            x[6] ^= r(x[5] &+ x[4], 7); x[7] ^= r(x[6] &+ x[5], 9); x[4] ^= r(x[7] &+ x[6], 13); x[5] ^= r(x[4] &+ x[7], 18)
            x[11] ^= r(x[10] &+ x[9], 7); x[8] ^= r(x[11] &+ x[10], 9); x[9] ^= r(x[8] &+ x[11], 13); x[10] ^= r(x[9] &+ x[8], 18)
            x[12] ^= r(x[15] &+ x[14], 7); x[13] ^= r(x[12] &+ x[15], 9); x[14] ^= r(x[13] &+ x[12], 13); x[15] ^= r(x[14] &+ x[13], 18)
        }
        for i in 0..<16 { b[i] = b[i] &+ x[i] }
    }

    static func blockMix(_ b: inout [UInt32], r: Int) {
        var x = Array(b[(2 * r - 1) * 16..<2 * r * 16])
        var y = [UInt32](repeating: 0, count: b.count)
        for i in 0..<(2 * r) {
            for j in 0..<16 { x[j] ^= b[i * 16 + j] }
            salsa20_8(&x)
            let dest = (i % 2 == 0 ? i / 2 : r + i / 2) * 16
            for j in 0..<16 { y[dest + j] = x[j] }
        }
        b = y
    }

    static func roMix(_ b: inout [UInt32], n: Int, r: Int) throws {
        var v: [[UInt32]] = []
        v.reserveCapacity(n)
        var x = b
        for _ in 0..<n {
            v.append(x)
            blockMix(&x, r: r)
        }
        for i in 0..<n {
            if i % 4096 == 0 { try Task.checkpoint() }
            let j = Int(x[(2 * r - 1) * 16] & UInt32(n - 1))
            for k in 0..<x.count { x[k] ^= v[j][k] }
            blockMix(&x, r: r)
        }
        b = x
    }

    public static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) throws -> Data {
        guard n > 1, n & (n - 1) == 0 else { throw ToolError("scrypt N must be a power of two") }
        guard n * r * 128 <= 1 << 30 else { throw ToolError("scrypt parameters need more than 1 GB of memory") }
        var b = PBKDF2.sha256(password: password, salt: salt, iterations: 1, length: p * 128 * r)
        var blocks: [[UInt32]] = []
        for i in 0..<p {
            let slice = b[(i * 128 * r)..<((i + 1) * 128 * r)]
            var words = [UInt32](repeating: 0, count: 32 * r)
            for (k, byte) in slice.enumerated() { words[k / 4] |= UInt32(byte) << UInt32(8 * (k % 4)) }
            blocks.append(words)
        }
        for i in 0..<p { try roMix(&blocks[i], n: n, r: r) }
        b = Data()
        for words in blocks { for w in words { b.append(contentsOf: [UInt8(w & 0xFF), UInt8((w >> 8) & 0xFF), UInt8((w >> 16) & 0xFF), UInt8(w >> 24)]) } }
        return PBKDF2.sha256(password: password, salt: b, iterations: 1, length: length)
    }
}

// MARK: - Argon2id (RFC 9106)

public enum Argon2 {
    public enum Variant: Int { case d = 0, i = 1, id = 2 }

    static func blake2bLong(_ input: Data, length: Int) -> Data {
        var prefix = Data()
        var l = UInt32(length)
        prefix.append(contentsOf: withUnsafeBytes(of: &l) { Array($0) })
        if length <= 64 { return Blake2b.hash(prefix + input, outputLength: length) }
        var out = Data()
        var v = Blake2b.hash(prefix + input, outputLength: 64)
        out.append(v.prefix(32))
        var remaining = length - 32
        while remaining > 64 {
            v = Blake2b.hash(v, outputLength: 64)
            out.append(v.prefix(32))
            remaining -= 32
        }
        out.append(Blake2b.hash(v, outputLength: remaining))
        return out
    }

    @inline(__always) static func fBlaMka(_ x: UInt64, _ y: UInt64) -> UInt64 {
        let m = (x & 0xFFFF_FFFF) &* (y & 0xFFFF_FFFF)
        return x &+ y &+ 2 &* m
    }

    @inline(__always) static func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }

    static func g(_ v: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        v[a] = fBlaMka(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 32)
        v[c] = fBlaMka(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 24)
        v[a] = fBlaMka(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 16)
        v[c] = fBlaMka(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 63)
    }

    static func permutation(_ v: inout [UInt64]) {
        g(&v, 0, 4, 8, 12); g(&v, 1, 5, 9, 13); g(&v, 2, 6, 10, 14); g(&v, 3, 7, 11, 15)
        g(&v, 0, 5, 10, 15); g(&v, 1, 6, 11, 12); g(&v, 2, 7, 8, 13); g(&v, 3, 4, 9, 14)
    }

    /// Compression G(X, Y) → 1024-byte block as 128 UInt64 words.
    static func compress(_ x: [UInt64], _ y: [UInt64]) -> [UInt64] {
        var r = [UInt64](repeating: 0, count: 128)
        for i in 0..<128 { r[i] = x[i] ^ y[i] }
        var q = r
        // rows
        var tmp = [UInt64](repeating: 0, count: 16)
        for i in 0..<8 {
            for j in 0..<16 { tmp[j] = q[i * 16 + j] }
            permutation(&tmp)
            for j in 0..<16 { q[i * 16 + j] = tmp[j] }
        }
        // columns
        for i in 0..<8 {
            for j in 0..<8 { tmp[2 * j] = q[2 * i + 16 * j]; tmp[2 * j + 1] = q[2 * i + 1 + 16 * j] }
            permutation(&tmp)
            for j in 0..<8 { q[2 * i + 16 * j] = tmp[2 * j]; q[2 * i + 1 + 16 * j] = tmp[2 * j + 1] }
        }
        for i in 0..<128 { r[i] ^= q[i] }
        return r
    }

    public static func hash(password: Data, salt: Data, iterations t: Int, memoryKiB m: Int, parallelism p: Int, length: Int, variant: Variant = .id, version: Int = 0x13) throws -> Data {
        guard p >= 1, t >= 1, m >= 8 * p, length >= 4 else { throw ToolError("Invalid Argon2 parameters") }
        guard m <= 1 << 20 else { throw ToolError("Argon2 memory above 1 GiB is not supported here") }
        var h0 = Data()
        func le32(_ v: Int) { var x = UInt32(v); h0.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) }) }
        le32(p); le32(length); le32(m); le32(t); le32(version); le32(variant.rawValue)
        le32(password.count); h0.append(password)
        le32(salt.count); h0.append(salt)
        le32(0); le32(0)
        let H0 = Blake2b.hash(h0, outputLength: 64)
        let q = (m / (4 * p)) * 4 / p   // columns per lane (m' = 4p * floor(m/4p))
        let lanes = p
        let laneLength = (m / (4 * p)) * 4
        _ = q
        let segmentLength = laneLength / 4
        var memory = [[UInt64]](repeating: [UInt64](repeating: 0, count: 128), count: lanes * laneLength)
        func toWords(_ d: Data) -> [UInt64] {
            var w = [UInt64](repeating: 0, count: 128)
            for (i, b) in d.enumerated() { w[i / 8] |= UInt64(b) << UInt64(8 * (i % 8)) }
            return w
        }
        for lane in 0..<lanes {
            var a = H0; var la = UInt32(lane)
            var zero = UInt32(0), one = UInt32(1)
            a.append(contentsOf: withUnsafeBytes(of: &zero) { Array($0) }); a.append(contentsOf: withUnsafeBytes(of: &la) { Array($0) })
            memory[lane * laneLength] = toWords(blake2bLong(a, length: 1024))
            var b = H0
            b.append(contentsOf: withUnsafeBytes(of: &one) { Array($0) }); b.append(contentsOf: withUnsafeBytes(of: &la) { Array($0) })
            memory[lane * laneLength + 1] = toWords(blake2bLong(b, length: 1024))
        }
        let zeroBlock = [UInt64](repeating: 0, count: 128)
        for pass in 0..<t {
            for slice in 0..<4 {
                for lane in 0..<lanes {
                    try Task.checkpoint()
                    let dataIndependent = variant == .i || (variant == .id && pass == 0 && slice < 2)
                    var addressBlock = zeroBlock
                    var inputBlock = zeroBlock
                    var counter: UInt64 = 0
                    if dataIndependent {
                        inputBlock[0] = UInt64(pass); inputBlock[1] = UInt64(lane); inputBlock[2] = UInt64(slice)
                        inputBlock[3] = UInt64(lanes * laneLength); inputBlock[4] = UInt64(t); inputBlock[5] = UInt64(variant.rawValue)
                    }
                    let start = (pass == 0 && slice == 0) ? 2 : 0
                    for idx in start..<segmentLength {
                        if dataIndependent, idx == start || idx % 128 == 0 {
                            counter += 1
                            inputBlock[6] = counter
                            addressBlock = compress(zeroBlock, compress(zeroBlock, inputBlock))
                        }
                        let curIndex = lane * laneLength + slice * segmentLength + idx
                        let prevIndex = (idx == 0 && slice == 0) ? lane * laneLength + laneLength - 1 : curIndex - 1
                        let pseudoRand: UInt64 = dataIndependent ? addressBlock[idx % 128] : memory[prevIndex][0]
                        let j1 = pseudoRand & 0xFFFF_FFFF
                        let j2 = pseudoRand >> 32
                        let refLane = (pass == 0 && slice == 0) ? lane : Int(j2 % UInt64(lanes))
                        let areaSize: Int
                        if pass == 0 {
                            areaSize = refLane == lane ? slice * segmentLength + idx - 1 : slice * segmentLength + (idx == 0 ? -1 : 0)
                        } else {
                            areaSize = refLane == lane ? laneLength - segmentLength + idx - 1 : laneLength - segmentLength + (idx == 0 ? -1 : 0)
                        }
                        let x = (j1 * j1) >> 32
                        let y = (UInt64(areaSize) * x) >> 32
                        let zz = UInt64(areaSize) - 1 - y
                        let startPos = pass == 0 ? 0 : (slice == 3 ? 0 : (slice + 1) * segmentLength)
                        let refIndex = (startPos + Int(zz)) % laneLength
                        let newBlock = compress(memory[prevIndex], memory[refLane * laneLength + refIndex])
                        if pass == 0 || version == 0x10 {
                            memory[curIndex] = newBlock
                        } else {
                            for i in 0..<128 { memory[curIndex][i] ^= newBlock[i] }
                        }
                    }
                }
            }
        }
        var final = memory[laneLength - 1]
        for lane in 1..<lanes { for i in 0..<128 { final[i] ^= memory[lane * laneLength + laneLength - 1][i] } }
        var finalData = Data()
        for w in final { for s in 0..<8 { finalData.append(UInt8((w >> UInt64(8 * s)) & 0xFF)) } }
        return blake2bLong(finalData, length: length)
    }

    public static func encoded(password: Data, salt: Data, iterations: Int, memoryKiB: Int, parallelism: Int, length: Int = 32) throws -> String {
        let h = try hash(password: password, salt: salt, iterations: iterations, memoryKiB: memoryKiB, parallelism: parallelism, length: length)
        return "$argon2id$v=19$m=\(memoryKiB),t=\(iterations),p=\(parallelism)$\(salt.base64URL)$\(h.base64URL)"
    }

    public static func verify(password: Data, encoded: String) throws -> Bool {
        let parts = encoded.split(separator: "$").map(String.init)
        guard parts.count == 5, parts[0].hasPrefix("argon2") else { throw ToolError("Not an Argon2 hash", hint: "Expected $argon2id$v=19$m=…,t=…,p=…$salt$hash") }
        let variant: Variant = parts[0] == "argon2i" ? .i : (parts[0] == "argon2d" ? .d : .id)
        var m = 0, t = 0, p = 0
        for kv in parts[2].split(separator: ",") {
            let x = kv.split(separator: "=")
            guard x.count == 2, let v = Int(x[1]) else { continue }
            switch x[0] { case "m": m = v; case "t": t = v; case "p": p = v; default: break }
        }
        guard let salt = Data(base64URL: parts[3]), let expected = Data(base64URL: parts[4]) else { throw ToolError("Invalid Base64 in Argon2 hash") }
        let h = try hash(password: password, salt: salt, iterations: t, memoryKiB: m, parallelism: p, length: expected.count, variant: variant)
        return h == expected
    }
}
