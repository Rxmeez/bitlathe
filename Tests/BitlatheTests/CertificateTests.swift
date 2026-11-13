import XCTest
import BitlatheCore
@testable import BitlatheTools

final class CertificateTests: XCTestCase {
    private func norm(_ s: String?) -> String { (s ?? "").replacingOccurrences(of: ":", with: "").lowercased() }

    func testRSASelfSignedCertificate() async throws {
        let out = try await TT.run("cert.x509", TT.fixture("cert/rsa-selfsigned.pem"))
        // Reference values from `openssl x509 -fingerprint -sha256 -serial -subject`.
        XCTAssertEqual(norm(TT.meta(out, "Fingerprint SHA-256")), "80a777a8528fbd5998c31b2bc38cd77d296c36d5993927ce08a50759f1652cfd")
        XCTAssertEqual(norm(TT.meta(out, "Fingerprint SHA-1")), "06e0e0224c631a9ea3aac334afb3de3b8ffd5ed4")
        XCTAssertEqual(norm(TT.meta(out, "Serial")), "17858f437029e6d453b86adbd747841458cdf346")
        XCTAssertEqual(TT.meta(out, "SPKI SHA-256 (HPKP pin)"), "XFROflc3WhzXIfcjIIv2H4Sl5JbWKYxWR6riPIq0z1c=")
        let subject = TT.meta(out, "Subject") ?? ""
        XCTAssertTrue(subject.contains("rsa.example.test") && subject.contains("Bitlathe Test"), subject)
        let sans = TT.meta(out, "Subject Alt Names") ?? ""
        XCTAssertTrue(sans.contains("rsa.example.test") && sans.contains("www.example.test") && sans.contains("10.0.0.1"), sans)
        XCTAssertTrue(TT.meta(out, "Public key")?.contains("RSA") == true)
        XCTAssertTrue(TT.meta(out, "Public key")?.contains("2048") == true)
        XCTAssertEqual(TT.meta(out, "Version"), "v3")
        XCTAssertFalse((TT.meta(out, "Valid until") ?? "").contains("EXPIRED"))
    }

    func testECSelfSignedCertificate() async throws {
        let out = try await TT.run("cert.x509", TT.fixture("cert/ec-selfsigned.pem"))
        XCTAssertEqual(norm(TT.meta(out, "Fingerprint SHA-256")), "6c635e475190e238b6837edfbc38ef6b0d37803d19878d1e1a9d74b11a2507e6")
        XCTAssertEqual(norm(TT.meta(out, "Fingerprint SHA-1")), "e511017860aa80e205b287032864db9af9d88b52")
        XCTAssertEqual(TT.meta(out, "SPKI SHA-256 (HPKP pin)"), "BWB9zktQITGyb4m53bls3IkgJttsaCWOJLpRLB1geLQ=")
        XCTAssertTrue(TT.meta(out, "Signature algorithm")?.lowercased().contains("ecdsa") == true)
    }

    func testCSR() async throws {
        let out = try await TT.run("cert.x509", TT.fixture("cert/request.csr"))
        XCTAssertTrue(TT.meta(out, "Type")?.contains("Certificate Signing Request") == true)
        XCTAssertTrue(TT.meta(out, "Subject")?.contains("csr.example.test") == true)
        let sans = TT.meta(out, "Requested SANs") ?? ""
        XCTAssertTrue(sans.contains("csr.example.test") && sans.contains("alt.example.test"), sans)
        XCTAssertEqual(norm(TT.meta(out, "SHA-256")), "d7ed553036d38df049620da5ba0ffef8c6d88555d5ed0d42402f857868af5248")
    }

    func testChainOfTwo() async throws {
        let pem = TT.fixture("cert/rsa-selfsigned.pem") + "\n" + TT.fixture("cert/ec-selfsigned.pem")
        let out = try await TT.run("cert.x509", pem)
        XCTAssertNotNil(out.metadata.first { $0.label.contains("Block 2") })
    }

    func testGarbageReportsErrorRow() async throws {
        let out = try await TT.run("cert.x509", "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----")
        XCTAssertNotNil(TT.meta(out, "Error"))
        XCTAssertNil(TT.meta(out, "Subject"))
    }
}
