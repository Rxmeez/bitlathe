import XCTest
import BitlatheCore
@testable import BitlatheTools

final class JWTTests: XCTestCase {
    private var tokens: [String: String] = [:]

    override func setUp() {
        let data = Data(TT.fixture("jwt/tokens.json").utf8)
        tokens = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func verify(_ alg: String, keyFile: String) async throws -> ToolOutput {
        try await TT.run("jwt.debug", tokens[alg]!, ["key": .string(TT.fixture(keyFile))])
    }

    func testRFC7515HS256Example() async throws {
        // RFC 7515 appendix A.1.
        let token = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let k = "AyM1SysPpbyDfgZld3umj1qzKObwVMkoqQ-EstJQLr_T-1qS0gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr1Z9CAow"
        let ok = try await TT.run("jwt.debug", token, ["secret": .string(k), "secretBase64": .bool(true)])
        XCTAssertEqual(ok.isValid, true)
        XCTAssertEqual(TT.facet(ok, "Header")?.contains("HS256"), true)
        XCTAssertTrue(TT.facet(ok, "Payload")?.contains("joe") == true)
        // exp (2011) is long past: that is a warning, not an invalid signature.
        XCTAssertTrue(ok.warnings.contains { $0.contains("expired") })
        XCTAssertFalse(ok.warnings.contains { $0.contains("verification failed") })

        let bad = try await TT.run("jwt.debug", token, ["secret": .string("AAAA"), "secretBase64": .bool(true)])
        XCTAssertEqual(bad.isValid, false)
        XCTAssertTrue(bad.warnings.contains { $0.contains("verification failed") })
    }

    func testDecodeWithoutKeyLeavesValidityUnknown() async throws {
        let out = try await TT.run("jwt.debug", tokens["HS256"]!)
        XCTAssertNil(out.isValid)
        XCTAssertTrue(TT.facet(out, "Payload")?.contains("Ada") == true)
        XCTAssertNotNil(TT.meta(out, "Signature check"))
    }

    func testHS256SecretVerification() async throws {
        let good = try await TT.run("jwt.debug", tokens["HS256"]!, ["secret": .string("secret-key-for-tests")])
        XCTAssertEqual(good.isValid, true)
        let bad = try await TT.run("jwt.debug", tokens["HS256"]!, ["secret": .string("wrong")])
        XCTAssertEqual(bad.isValid, false)
    }

    func testRS256PS256ES256EdDSAVerifyWithOpenSSLKeys() async throws {
        for (alg, pub, priv) in [("RS256", "keys/rsa2048.pub.pem", "keys/rsa2048.pem"),
                                 ("PS256", "keys/rsa2048.pub.pem", "keys/rsa2048.pem"),
                                 ("ES256", "keys/p256.pub.pem", "keys/p256.pem"),
                                 ("EdDSA", "keys/ed25519.pub.pem", "keys/ed25519.pem")] {
            let out = try await verify(alg, keyFile: pub)
            XCTAssertEqual(out.isValid, true, "\(alg) public key")
            let withPrivate = try await verify(alg, keyFile: priv)
            XCTAssertEqual(withPrivate.isValid, true, "\(alg) private key")
        }
    }

    func testWrongKeyFailsVerification() async throws {
        // An RS256 token checked against a different RSA key must be flagged invalid.
        let other = try CryptoKeys.generateRSA(bits: 2048)
        let pem = CryptoKeys.pem(CryptoKeys.publicKey(of: other))
        let out = try await TT.run("jwt.debug", tokens["RS256"]!, ["key": .string(pem)])
        XCTAssertEqual(out.isValid, false)
    }

    func testTamperedPayloadFails() async throws {
        var parts = tokens["ES256"]!.split(separator: ".").map(String.init)
        parts[1] = Data(#"{"sub":"evil","exp":4102444800}"#.utf8).base64URL
        let out = try await TT.run("jwt.debug", parts.joined(separator: "."), ["key": .string(TT.fixture("keys/p256.pub.pem"))])
        XCTAssertEqual(out.isValid, false)
    }

    func testSignThenVerifyRoundTrip() async throws {
        let claims = #"{"sub":"42","name":"Ada"}"#
        for (alg, priv, pub) in [("RS256", "keys/rsa2048.pem", "keys/rsa2048.pub.pem"),
                                 ("PS256", "keys/rsa2048.pem", "keys/rsa2048.pub.pem"),
                                 ("ES256", "keys/p256.pem", "keys/p256.pub.pem"),
                                 ("EdDSA", "keys/ed25519.pem", "keys/ed25519.pub.pem")] {
            let signed = try await TT.run("jwt.debug", claims, ["mode": .string("sign"), "algorithm": .string(alg), "key": .string(TT.fixture(priv))])
            let decoded = try await TT.run("jwt.debug", signed.text, ["key": .string(TT.fixture(pub))])
            XCTAssertEqual(decoded.isValid, true, alg)
            XCTAssertTrue(TT.facet(decoded, "Payload")?.contains("Ada") == true)
        }
        let hs = try await TT.run("jwt.debug", claims, ["mode": .string("sign"), "algorithm": .string("HS384"), "secret": .string("s3cret")])
        let back = try await TT.run("jwt.debug", hs.text, ["secret": .string("s3cret")])
        XCTAssertEqual(back.isValid, true)
        XCTAssertEqual(TT.meta(back, "Algorithm")?.hasPrefix("HS384"), true)
        // Default expiry (1h) and iat are added by the signer.
        XCTAssertTrue(TT.facet(back, "Payload")?.contains("exp") == true)
        XCTAssertTrue(TT.facet(back, "Payload")?.contains("iat") == true)
    }

    func testSigningWithPublicKeyIsRejected() async {
        do {
            _ = try await TT.run("jwt.debug", "{}", ["mode": .string("sign"), "algorithm": .string("RS256"), "key": .string(TT.fixture("keys/rsa2048.pub.pem"))])
            XCTFail("expected error")
        } catch { XCTAssertTrue(error is ToolError) }
    }

    func testAlgNoneWarns() async throws {
        let h = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URL
        let p = Data(#"{"sub":"1","exp":4102444800}"#.utf8).base64URL
        let out = try await TT.run("jwt.debug", "\(h).\(p).")
        XCTAssertTrue(out.warnings.contains { $0.contains("alg=none") })
        XCTAssertNil(out.isValid)
    }

    func testExpiredIsWarningNotInvalid() async throws {
        let signed = try await TT.run("jwt.debug", #"{"sub":"1","exp":1000000000}"#,
                                      ["mode": .string("sign"), "algorithm": .string("HS256"), "secret": .string("k")])
        let out = try await TT.run("jwt.debug", signed.text, ["secret": .string("k")])
        XCTAssertEqual(out.isValid, true)
        XCTAssertTrue(out.warnings.contains { $0.lowercased().contains("expired") })
    }

    func testBearerPrefixAndErrors() async throws {
        let out = try await TT.run("jwt.debug", "Bearer " + tokens["HS256"]!)
        XCTAssertTrue(TT.facet(out, "Payload")?.contains("1234") == true)
        do { _ = try await TT.run("jwt.debug", "abc.def"); XCTFail("expected error") } catch { XCTAssertTrue(error is ToolError) }
        do { _ = try await TT.run("jwt.debug", "a.b.c.d.e"); XCTFail("expected JWE error") } catch let e as ToolError { XCTAssertTrue(e.message.contains("JWE")) }
    }

    func testDetect() {
        XCTAssertGreaterThan(JWTTool.detect(tokens["HS256"]!)?.confidence ?? 0, 0.9)
        XCTAssertNil(JWTTool.detect("hello.world.foo"))
    }
}
