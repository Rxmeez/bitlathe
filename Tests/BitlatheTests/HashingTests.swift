import XCTest
import BitlatheCore
@testable import BitlatheTools

final class HashingTests: XCTestCase {
    private func h(_ algo: String, _ s: String, key: String? = nil) -> String {
        TT.hex(HashGeneratorTool.digest(algo, Data(s.utf8), key: key.map { Data($0.utf8) })!)
    }

    func testEmptyAndAbcVectors() {
        let vectors: [(String, String, String)] = [
            ("md5", "", "d41d8cd98f00b204e9800998ecf8427e"),
            ("md5", "abc", "900150983cd24fb0d6963f7d28e17f72"),
            ("sha1", "", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            ("sha1", "abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            ("sha256", "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("sha256", "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("sha384", "abc", "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"),
            ("sha512", "abc", "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"),
            ("sha512_256", "abc", "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23"),
            ("sha512_256", "", "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a"),
            ("sha3_224", "abc", "e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf"),
            ("sha3_256", "", "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"),
            ("sha3_256", "abc", "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"),
            ("sha3_384", "abc", "ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25"),
            ("sha3_512", "abc", "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0"),
            ("keccak256", "", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
            ("keccak256", "abc", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
            ("shake128", "", "7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26"),
            ("shake256", "", "46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be"),
            // RFC 7693 appendix A / B
            ("blake2b", "abc", "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"),
            ("blake2b", "", "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"),
            ("blake2s", "abc", "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982"),
            ("blake2s", "", "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9"),
            ("blake2b256", "abc", "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"),
            ("blake3", "", "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
            ("blake3", "abc", "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"),
            ("crc32", "123456789", "cbf43926"),
            ("adler32", "Wikipedia", "11e60398"),
        ]
        for (algo, input, expected) in vectors {
            XCTAssertEqual(h(algo, input), expected, "\(algo)(\"\(input)\")")
        }
    }

    func testBlake3OfficialVectorOneByte() {
        // BLAKE3 test_vectors.json, input_len = 1 (bytes follow i % 251).
        XCTAssertEqual(TT.hex(Blake3.hash(Data([0]))), "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213")
    }

    func testSHA3HundredThousandA() {
        let d = Data(repeating: UInt8(ascii: "a"), count: 100_000)
        XCTAssertEqual(TT.hex(Keccak.sha3(d, bits: 256)), "7c772c3f1ef6bb4320c0bf1597c3ddbdc4862bfd2ea2d9664208fd3ee17342c2")
    }

    func testHMAC() {
        let msg = "The quick brown fox jumps over the lazy dog"
        XCTAssertEqual(h("md5", msg, key: "key"), "80070713463e7749b90c2dc24911e275")
        XCTAssertEqual(h("sha1", msg, key: "key"), "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9")
        XCTAssertEqual(h("sha256", msg, key: "key"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        XCTAssertEqual(h("sha3_256", msg, key: "key"), "8c6e0683409427f8931711b10ca92a506eb1fafa48fadd66d76126f47ac2c333")
        XCTAssertEqual(h("blake2b", "abc", key: "key"), "5c6a9a4ae911c02fb7e71a991eb9aea371ae993d4842d206e6020d46f5e41358c6d5c277c110ef86c959ed63e6ecaaaceaaff38019a43264ae06acf73b9550b1")
        XCTAssertEqual(h("blake2s", "abc", key: "key"), "3f9723437b033bf0c1f4df43cafd0776068cb0a95912de13f3b2952a3aba764d")
    }

    func testToolAllAlgorithmsAndEncodings() async throws {
        let all = try await TT.run("hash.generate", "abc")
        XCTAssertEqual(TT.facet(all, "SHA-256"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(TT.facet(all, "MD5"), "900150983cd24fb0d6963f7d28e17f72")
        let b64 = try await TT.run("hash.generate", "abc", ["algorithm": .string("sha256"), "encoding": .string("base64")])
        XCTAssertEqual(b64.text, "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
        let upper = try await TT.run("hash.generate", "abc", ["algorithm": .string("md5"), "uppercase": .bool(true)])
        XCTAssertEqual(upper.text, "900150983CD24FB0D6963F7D28E17F72")
        let hm = try await TT.run("hash.generate", "The quick brown fox jumps over the lazy dog",
                                  ["algorithm": .string("sha256"), "hmac": .bool(true), "key": .string("key")])
        XCTAssertEqual(hm.text, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    }

    func testEmptySampleAndPerLine() async throws {
        let e = try await TT.run("hash.generate", " ", ["algorithm": .string("sha256")])
        XCTAssertEqual(e.text, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let l = try await TT.run("hash.generate", "abc\nabc", ["algorithm": .string("md5"), "perLine": .bool(true)])
        XCTAssertEqual(l.text, "900150983cd24fb0d6963f7d28e17f72\n900150983cd24fb0d6963f7d28e17f72")
    }

    func testHMACRequiresKey() async {
        do { _ = try await TT.run("hash.generate", "x", ["hmac": .bool(true)]); XCTFail("expected error") }
        catch { XCTAssertTrue(error is ToolError) }
    }
}
