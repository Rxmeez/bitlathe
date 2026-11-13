import XCTest
import BitlatheCore
@testable import BitlatheTools

final class PasswordHashingTests: XCTestCase {
    // MARK: bcrypt

    func testBcryptCryptBlowfishVectors() throws {
        // OpenBSD / crypt_blowfish test vectors (fixed salt "CCCCCCCCCCCCCCCCCCCCC.").
        XCTAssertTrue(try Bcrypt.verify("U*U", hash: "$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW"))
        XCTAssertFalse(try Bcrypt.verify("U*V", hash: "$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW"))
        XCTAssertTrue(try Bcrypt.verify("", hash: "$2a$05$CCCCCCCCCCCCCCCCCCCCC.7uG0VCzI2bS7j6ymqJi9CdcdxiRTWNy"))
    }

    func testBcryptAgainstApacheHtpasswd() throws {
        // Generated with `htpasswd -bnBC <cost> u <password>` ($2y$).
        XCTAssertTrue(try Bcrypt.verify("abc", hash: "$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm"))
        XCTAssertTrue(try Bcrypt.verify("correct horse", hash: "$2y$05$eXOR0EygXqw4b86cKEFyzuFB.P8BmqD4K8JFlvEBX/2bk9K2.pPse"))
        XCTAssertTrue(try Bcrypt.verify("pässword", hash: "$2y$04$otl6XFUqPFA29beW5CwvXOpwetZmw.0t4Pdkuf4iVPSENPSzt8Fvi"))
        XCTAssertFalse(try Bcrypt.verify("Abc", hash: "$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm"))
    }

    func testBcryptHashProducesExpectedShapeAndVerifies() throws {
        let h = try Bcrypt.hash("hunter2", cost: 4)
        XCTAssertTrue(h.hasPrefix("$2b$04$"))
        XCTAssertEqual(h.count, 60)
        XCTAssertTrue(try Bcrypt.verify("hunter2", hash: h))
        XCTAssertFalse(try Bcrypt.verify("hunter3", hash: h))
        // Fixed salt is deterministic.
        let salt = [UInt8](repeating: 7, count: 16)
        XCTAssertEqual(try Bcrypt.hash("x", cost: 4, salt: salt), try Bcrypt.hash("x", cost: 4, salt: salt))
    }

    // MARK: scrypt

    func testScryptRFC7914() throws {
        let a = try Scrypt.derive(password: Data(), salt: Data(), n: 16, r: 1, p: 1, length: 64)
        XCTAssertEqual(TT.hex(a), "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
        // RFC 7914 vector 3 parameters with p=1 (reference computed with Python hashlib.scrypt).
        let b = try Scrypt.derive(password: Data("pleaseletmein".utf8), salt: Data("SodiumChloride".utf8), n: 1024, r: 8, p: 1, length: 64)
        XCTAssertEqual(TT.hex(b), "54173687d265e43226bd914b015267e2fdd4108aa05937fb549eceb0c276a285fe59e2293f5aa3fe288f0e7e552790daa4d8d79c09294663152acb719dd225b8")
    }

    func testPBKDF2RFC6070Style() {
        // PBKDF2-HMAC-SHA256, P="password", S="salt", c=1, dkLen=32 (widely published vector).
        XCTAssertEqual(TT.hex(PBKDF2.sha256(password: Data("password".utf8), salt: Data("salt".utf8), iterations: 1, length: 32)),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(TT.hex(PBKDF2.sha256(password: Data("password".utf8), salt: Data("salt".utf8), iterations: 4096, length: 32)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    // MARK: Argon2

    func testArgon2idReferenceCLI() throws {
        // Reference values from the `argon2` command line tool (-id).
        let salt1 = Data("somesalt1234567".utf8)
        XCTAssertEqual(TT.hex(try Argon2.hash(password: Data("password".utf8), salt: salt1, iterations: 1, memoryKiB: 256, parallelism: 1, length: 32)),
                       "7f0c55172afbf363d8fde2a7013af9f28004201fbe48d07a2098bdda3c037e02")
        let salt2 = Data("saltsaltsalt1234".utf8)
        XCTAssertEqual(TT.hex(try Argon2.hash(password: Data("abc".utf8), salt: salt2, iterations: 3, memoryKiB: 64, parallelism: 4, length: 16)),
                       "6d032c45e716f82dd859201b37f058de")
        XCTAssertEqual(TT.hex(try Argon2.hash(password: Data("abc".utf8), salt: salt2, iterations: 1, memoryKiB: 256, parallelism: 1, length: 16, variant: .i)),
                       "3a8a7dbe2154b91685019c8c9bd42e29")
        XCTAssertEqual(TT.hex(try Argon2.hash(password: Data("abc".utf8), salt: salt2, iterations: 1, memoryKiB: 256, parallelism: 1, length: 16, variant: .d)),
                       "b64f71cb2a3f85b8404a646695ae24ec")
    }

    func testArgon2EncodedVerify() throws {
        let enc = "$argon2id$v=19$m=64,t=3,p=4$c2FsdHNhbHRzYWx0MTIzNA$bQMsRecW+C3YWSAbN/BY3g"   // from the argon2 CLI
        XCTAssertTrue(try Argon2.verify(password: Data("abc".utf8), encoded: enc))
        XCTAssertFalse(try Argon2.verify(password: Data("abd".utf8), encoded: enc))
        let mine = try Argon2.encoded(password: Data("pw".utf8), salt: Data(repeating: 1, count: 16), iterations: 1, memoryKiB: 64, parallelism: 1)
        XCTAssertTrue(mine.hasPrefix("$argon2id$v=19$m=64,t=1,p=1$"))
        XCTAssertTrue(try Argon2.verify(password: Data("pw".utf8), encoded: mine))
    }

    // MARK: tool

    func testToolHashThenVerifyAllAlgorithms() async throws {
        let configs: [(String, OptionValues)] = [
            ("bcrypt", ["algorithm": .string("bcrypt"), "cost": .int(4)]),
            ("scrypt", ["algorithm": .string("scrypt"), "scryptN": .string("10")]),
            ("argon2id", ["algorithm": .string("argon2id"), "memoryMiB": .int(1), "iterations": .int(1)]),
        ]
        for (name, opts) in configs {
            let hashed = try await TT.run("password.hash", "s3cret pass", opts)
            let h = hashed.text
            let ok = try await TT.run("password.hash", "s3cret pass", ["mode": .string("verify"), "hash": .string(h)])
            XCTAssertEqual(ok.isValid, true, name)
            let no = try await TT.run("password.hash", "wrong", ["mode": .string("verify"), "hash": .string(h)])
            XCTAssertEqual(no.isValid, false, name)
        }
    }

    func testToolVerifyKnownBcryptAndErrors() async throws {
        let ok = try await TT.run("password.hash", "abc\n", ["mode": .string("verify"), "hash": .string("$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm")])
        XCTAssertEqual(ok.isValid, true, "trailing newline is ignored")
        do { _ = try await TT.run("password.hash", "x", ["mode": .string("verify"), "hash": .string("nonsense")]); XCTFail() } catch { XCTAssertTrue(error is ToolError) }
        do { _ = try await TT.run("password.hash", "", [:]); XCTFail() } catch { XCTAssertTrue(error is ToolError) }
    }

    func testDetect() {
        XCTAssertNotNil(PasswordHashTool.detect("$2y$04$BbWsgGsURH8ePGFLLyQlh../rQntQoj02S.wfSvOiYYqjp2eZYSYm"))
        XCTAssertNotNil(PasswordHashTool.detect("$argon2id$v=19$m=64,t=1,p=1$c29tZQ$abc"))
        XCTAssertNil(PasswordHashTool.detect("plain text"))
    }
}
