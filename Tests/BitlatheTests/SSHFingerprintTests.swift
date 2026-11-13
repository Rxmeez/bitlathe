import XCTest
import BitlatheCore
@testable import BitlatheTools

final class SSHFingerprintTests: XCTestCase {
    // Reference values from `ssh-keygen -lf` and `ssh-keygen -E md5 -lf` on the fixture keys.
    private let cases: [(file: String, type: String, bits: String, sha: String, md5: String)] = [
        ("ssh/id_ed25519.pub", "ED25519", "256", "SHA256:8NyQxAid4rI7Uosq0jDaI3/qhSMhYNrUe4H9nhyQWsw", "MD5:39:f7:64:08:8e:40:ab:84:a5:c5:2b:48:e8:9c:35:95"),
        ("ssh/id_ecdsa.pub", "ECDSA", "256", "SHA256:ohBAUN8UFoMcSvjvA4Y5OhNm1Qvxu3/VPtEKADimIcg", "MD5:c9:c9:59:ff:28:bc:df:76:93:87:1c:36:bd:2a:c6:ac"),
        ("ssh/id_rsa.pub", "RSA", "3072", "SHA256:vWVUgjVbvAEZtoiyGYQbth8pH62cLceo8wuHYTy6O3c", "MD5:34:c6:4f:89:ca:da:05:29:af:9f:72:a0:2e:59:60:6b"),
    ]

    func testFingerprintsMatchSSHKeygen() async throws {
        for c in cases {
            let out = try await TT.run("ssh.fingerprint", TT.fixture(c.file))
            XCTAssertEqual(TT.meta(out, "SHA-256"), c.sha, c.file)
            let md5 = TT.meta(out, "MD5") ?? ""
            XCTAssertTrue(md5 == c.md5 || "MD5:" + md5 == c.md5, "\(c.file): \(md5)")
            XCTAssertEqual(TT.meta(out, "Bits"), c.bits, c.file)
            XCTAssertTrue(TT.meta(out, "Type")?.hasPrefix(c.type) == true, c.file)
            // Randomart must be byte-identical to `ssh-keygen -lv`.
            let art = TT.fixture(c.file.replacingOccurrences(of: ".pub", with: ".art")).trimmingCharacters(in: .newlines)
            XCTAssertEqual(out.text, art, "randomart \(c.file)")
            XCTAssertTrue(TT.meta(out, "Comment")?.hasPrefix("test-") == true)
        }
    }

    func testMultipleKeysListed() async throws {
        let all = cases.map { TT.fixture($0.file) }.joined(separator: "\n")
        let out = try await TT.run("ssh.fingerprint", all)
        for c in cases { XCTAssertTrue(out.text.contains(c.sha), c.sha) }
    }

    func testDetectAndInvalid() async {
        XCTAssertNotNil(SSHFingerprintTool.detect(TT.fixture("ssh/id_ed25519.pub").trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertNil(SSHFingerprintTool.detect("just some text"))
        do { _ = try await TT.run("ssh.fingerprint", "ssh-ed25519 !!!notbase64"); XCTFail("expected error") }
        catch { XCTAssertTrue(error is ToolError) }
    }
}
