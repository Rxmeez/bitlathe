import XCTest
import BitlatheCore
@testable import BitlatheTools

/// CIDR, chmod and .env inspectors.
final class NetworkAndSystemInspectTests: XCTestCase {
    // MARK: CIDR IPv4

    func testIPv4Slash26() async throws {
        let out = try await TT.run("cidr.calc", "192.168.1.130/26")
        XCTAssertEqual(TT.meta(out, "Network"), "192.168.1.128")
        XCTAssertEqual(TT.meta(out, "Broadcast"), "192.168.1.191")
        XCTAssertEqual(TT.meta(out, "Netmask"), "255.255.255.192")
        XCTAssertEqual(TT.meta(out, "Wildcard"), "0.0.0.63")
        XCTAssertEqual(TT.meta(out, "Total addresses"), "64")
        XCTAssertEqual(TT.meta(out, "Usable hosts"), "62")
        XCTAssertTrue(TT.meta(out, "Host range")?.contains("192.168.1.129") == true && TT.meta(out, "Host range")?.contains("192.168.1.190") == true)
        XCTAssertEqual(TT.meta(out, "CIDR"), "192.168.1.128/26")
        XCTAssertEqual(TT.meta(out, "Class"), "C")
        XCTAssertTrue(TT.meta(out, "Type")?.contains("Private") == true)
    }

    func testIPv4EdgePrefixes() async throws {
        let s24 = try await TT.run("cidr.calc", "10.0.0.0/24")
        XCTAssertEqual(TT.meta(s24, "Usable hosts"), "254"); XCTAssertEqual(TT.meta(s24, "Broadcast"), "10.0.0.255")
        let s8 = try await TT.run("cidr.calc", "10.1.2.3/8")
        XCTAssertEqual(TT.meta(s8, "Network"), "10.0.0.0"); XCTAssertEqual(TT.meta(s8, "Broadcast"), "10.255.255.255"); XCTAssertEqual(TT.meta(s8, "Total addresses"), (1 << 24).formatted())
        let s30 = try await TT.run("cidr.calc", "172.16.5.9/30")
        XCTAssertEqual(TT.meta(s30, "Network"), "172.16.5.8"); XCTAssertEqual(TT.meta(s30, "Broadcast"), "172.16.5.11"); XCTAssertEqual(TT.meta(s30, "Usable hosts"), "2")
        let s31 = try await TT.run("cidr.calc", "10.0.0.4/31")
        XCTAssertEqual(TT.meta(s31, "Usable hosts"), "2", "RFC 3021 point-to-point")
        let s32 = try await TT.run("cidr.calc", "8.8.8.8/32")
        XCTAssertEqual(TT.meta(s32, "Usable hosts"), "1"); XCTAssertEqual(TT.meta(s32, "Total addresses"), "1")
        let s0 = try await TT.run("cidr.calc", "0.0.0.0/0")
        XCTAssertEqual(TT.meta(s0, "Total addresses"), (UInt64(1) << 32).formatted()); XCTAssertEqual(TT.meta(s0, "Netmask"), "0.0.0.0")
        let s20 = try await TT.run("cidr.calc", "10.0.0.0 255.255.240.0")
        XCTAssertEqual(TT.meta(s20, "CIDR"), "10.0.0.0/20"); XCTAssertEqual(TT.meta(s20, "Total addresses"), "4,096")
        XCTAssertEqual(TT.meta(s20, "Broadcast"), "10.0.15.255")
    }

    func testIPv4Classes() async throws {
        for (ip, cls) in [("10.1.1.1", "A"), ("150.1.1.1", "B"), ("200.1.1.1", "C"), ("230.1.1.1", "D (multicast)"), ("250.1.1.1", "E (reserved)")] {
            let out = try await TT.run("cidr.calc", ip)
            XCTAssertEqual(TT.meta(out, "Class"), cls, ip)
        }
    }

    func testContainment() async throws {
        let yes = try await TT.run("cidr.calc", "10.1.2.3 in 10.0.0.0/8")
        XCTAssertEqual(yes.text, "yes")
        let no = try await TT.run("cidr.calc", "11.1.2.3 in 10.0.0.0/8")
        XCTAssertEqual(no.text, "no")
        let v6 = try await TT.run("cidr.calc", "2001:db8::1 in 2001:db8::/32")
        XCTAssertEqual(v6.text, "yes")
        let v6no = try await TT.run("cidr.calc", "2001:db9::1 in 2001:db8::/32")
        XCTAssertEqual(v6no.text, "no")
    }

    func testIPv4Errors() async {
        for bad in ["256.1.1.1", "1.2.3", "10.0.0.0/33", "a.b.c.d"] {
            do { _ = try await TT.run("cidr.calc", bad); XCTFail("expected error for \(bad)") } catch { XCTAssertTrue(error is ToolError, bad) }
        }
    }

    // MARK: CIDR IPv6

    func testIPv6Slash48() async throws {
        let out = try await TT.run("cidr.calc", "2001:db8:abcd::/48")
        XCTAssertEqual(TT.meta(out, "Network"), "2001:0db8:abcd:0000:0000:0000:0000:0000")
        XCTAssertEqual(TT.meta(out, "Last address"), "2001:0db8:abcd:ffff:ffff:ffff:ffff:ffff")
        XCTAssertEqual(TT.meta(out, "Addresses"), "2^80")
        XCTAssertEqual(out.text, "2001:db8:abcd::/48")
        XCTAssertTrue(TT.meta(out, "Type")?.contains("Documentation") == true)
    }

    func testIPv6SmallBlocksAndCompression() async throws {
        let s120 = try await TT.run("cidr.calc", "2001:db8::1234/120")
        XCTAssertEqual(TT.meta(s120, "Addresses"), "256")
        XCTAssertEqual(TT.meta(s120, "Network"), "2001:0db8:0000:0000:0000:0000:0000:1200")
        XCTAssertEqual(TT.meta(s120, "Last address"), "2001:0db8:0000:0000:0000:0000:0000:12ff")
        let one = try await TT.run("cidr.calc", "::1")
        XCTAssertEqual(TT.meta(one, "Expanded"), "0000:0000:0000:0000:0000:0000:0000:0001")
        XCTAssertEqual(TT.meta(one, "Addresses"), "1")
        XCTAssertTrue(TT.meta(one, "Type")?.contains("Loopback") == true)
        let full = try await TT.run("cidr.calc", "fe80:0:0:0:1:2:3:4/10")
        XCTAssertTrue(TT.meta(full, "Type")?.contains("Link-local") == true)
        XCTAssertEqual(TT.meta(full, "Network"), "fe80:0000:0000:0000:0000:0000:0000:0000")
        let all = try await TT.run("cidr.calc", "::/0")
        XCTAssertEqual(TT.meta(all, "Addresses"), "2^128")
        let mapped = try await TT.run("cidr.calc", "::ffff:192.0.2.1")
        XCTAssertEqual(TT.meta(mapped, "Expanded"), "0000:0000:0000:0000:0000:ffff:c000:0201")
        let s64 = try await TT.run("cidr.calc", "2001:db8::/64")
        XCTAssertEqual(TT.meta(s64, "Addresses"), "2^64")
    }

    func testIPv6Errors() async {
        for bad in ["2001:db8::1::2", "2001:db8::/129", "12345::1", "1:2:3:4:5:6:7"] {
            do { _ = try await TT.run("cidr.calc", bad); XCTFail("expected error for \(bad)") } catch { XCTAssertTrue(error is ToolError, bad) }
        }
    }

    // MARK: chmod

    func testOctalSymbolicConversions() throws {
        let table: [(String, Int, String)] = [
            ("755", 0o755, "rwxr-xr-x"), ("644", 0o644, "rw-r--r--"), ("600", 0o600, "rw-------"), ("777", 0o777, "rwxrwxrwx"),
            ("000", 0, "---------"), ("4755", 0o4755, "rwsr-xr-x"), ("2755", 0o2755, "rwxr-sr-x"), ("1777", 0o1777, "rwxrwxrwt"),
            ("4644", 0o4644, "rwSr--r--"), ("1754", 0o1754, "rwxr-xr-T"), ("7777", 0o7777, "rwsrwsrwt"),
        ]
        for (octal, bits, sym) in table {
            let fromOctal = try ChmodTool.parse(octal)
            XCTAssertEqual(fromOctal.bits, bits, octal)
            XCTAssertEqual(fromOctal.symbolic, sym, octal)
            XCTAssertEqual(try ChmodTool.parse(sym).bits, bits, sym)
            XCTAssertEqual(try ChmodTool.parse("-" + sym).bits, bits, "ls -l style -\(sym)")
        }
        XCTAssertEqual(try ChmodTool.parse("0644").octal, "644")
        XCTAssertEqual(try ChmodTool.parse("drwxr-xr-x").bits, 0o755)
    }

    func testChmodClausesAndTool() async throws {
        XCTAssertEqual(try ChmodTool.parse("u=rwx,g=rx,o=").bits, 0o750)
        XCTAssertEqual(try ChmodTool.parse("u=rwx,go=rx").bits, 0o755)
        XCTAssertEqual(try ChmodTool.parse("a+x").bits, 0o111)
        XCTAssertEqual(try ChmodTool.parse("u=rw,g=r,o=r").bits, 0o644)
        XCTAssertEqual(try ChmodTool.parse("u+s").bits, 0o4000)
        XCTAssertEqual(try ChmodTool.parse("+t").bits, 0o1000)
        XCTAssertEqual(try ChmodTool.parse("a=rwx,o-w").bits, 0o775)
        let out = try await TT.run("chmod.calc", "4755")
        XCTAssertEqual(TT.meta(out, "Octal"), "4755"); XCTAssertEqual(TT.meta(out, "Symbolic"), "rwsr-xr-x")
        XCTAssertEqual(TT.meta(out, "umask equivalent"), "022")
        XCTAssertNotNil(TT.meta(out, "setuid"))
        let w = try await TT.run("chmod.calc", "666")
        XCTAssertEqual(TT.meta(w, "Warning"), "World-writable")
        XCTAssertEqual(TT.meta(w, "Owner"), "read, write"); XCTAssertEqual(TT.meta(w, "umask equivalent"), "111")
        for bad in ["888", "rwxrwx", "hello", "9"] { XCTAssertThrowsError(try ChmodTool.parse(bad), bad) }
    }

    func testChmodCommandWithFilename() async throws {
        // detect() claims `chmod …` text, so the tool must accept a full command line.
        XCTAssertNotNil(ChmodTool.detect("chmod 755 script.sh"))
        let out = try await TT.run("chmod.calc", "chmod 755 script.sh")
        XCTAssertEqual(TT.meta(out, "Octal"), "755")
        let r = try await TT.run("chmod.calc", "chmod -R 644 dir/")
        XCTAssertEqual(TT.meta(r, "Octal"), "644")
    }

    // MARK: .env

    func testEnvParsingBasics() {
        let text = """
        # comment
        A=1
        export B="two words" # trailing
        C='single $A'
        D=
        E=plain # note
        F="line1\\nline2"
        """
        let (entries, warnings) = EnvInspectTool.parse(text)
        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
        XCTAssertEqual(map["A"], "1")
        XCTAssertEqual(map["B"], "two words")
        XCTAssertEqual(map["C"], "single $A")
        XCTAssertEqual(map["D"], "")
        XCTAssertEqual(map["E"], "plain")
        XCTAssertEqual(map["F"], "line1\nline2")
        XCTAssertEqual(entries.first { $0.key == "B" }?.comment, "trailing")
        XCTAssertEqual(entries.first { $0.key == "E" }?.comment, "note")
        XCTAssertEqual(entries.first { $0.key == "B" }?.line, 3)
        XCTAssertTrue(warnings.contains { $0.message.contains("D is empty") })
    }

    func testEnvWarnings() {
        let (entries, warnings) = EnvInspectTool.parse("PORT=3000\nPORT=3001\nbad key=1\nnoequals\nlower=1\nQUOTE=\"oops\nX=unquoted value here")
        XCTAssertEqual(entries.first { $0.key == "PORT" }?.value, "3001", "last duplicate wins")
        let msgs = warnings.map(\.message).joined(separator: "\n")
        XCTAssertTrue(msgs.contains("Duplicate key PORT"), msgs)
        XCTAssertTrue(msgs.contains("Invalid key"), msgs)
        XCTAssertTrue(msgs.contains("No '='"), msgs)
        XCTAssertTrue(msgs.contains("not UPPER_CASE"), msgs)
    }

    func testEnvMultilineQuotedValue() {
        let (entries, warnings) = EnvInspectTool.parse("KEY=\"-----BEGIN\nabc\n-----END\"\nNEXT=1")
        XCTAssertEqual(entries.first { $0.key == "KEY" }?.value, "-----BEGIN\nabc\n-----END")
        XCTAssertEqual(entries.first { $0.key == "NEXT" }?.value, "1")
        XCTAssertTrue(warnings.isEmpty, "\(warnings)")
    }

    func testEnvExpansion() {
        let (raw, _) = EnvInspectTool.parse("USER=ada\nGREETING=\"Hello ${USER}\"\nPATH2=$USER/bin\nDEF=${MISSING:-fallback}\nLIT='$USER'\nNONE=${NOPE}")
        let map = Dictionary(uniqueKeysWithValues: EnvInspectTool.expand(raw).map { ($0.key, $0.value) })
        XCTAssertEqual(map["GREETING"], "Hello ada")
        XCTAssertEqual(map["PATH2"], "ada/bin")
        XCTAssertEqual(map["DEF"], "fallback")
        XCTAssertEqual(map["NONE"], "")
        XCTAssertEqual(map["LIT"], "$USER", "single-quoted values are literal and must not be expanded")
    }

    func testEnvSecretsMaskingAndOutputs() async throws {
        let text = "DATABASE_URL=postgres://user:hunter2@localhost:5432/app\nAPI_KEY=sk_live_51Habcdefghijklmnop\nDEBUG=true\nPORT=3000"
        let json = try await TT.run("env.inspect", text)
        XCTAssertEqual(TT.meta(json, "Variables"), "4")
        XCTAssertEqual(TT.meta(json, "Secrets detected"), "2")
        XCTAssertFalse(json.text.contains("hunter2"), "secrets are masked by default")
        XCTAssertFalse(json.text.contains("sk_live_51Habcdefghijklmnop"))
        XCTAssertTrue(json.text.contains("\"PORT\""))
        let plain = try await TT.run("env.inspect", text, ["mask": .bool(false)])
        XCTAssertTrue(plain.text.contains("hunter2"))
        let shell = try await TT.run("env.inspect", "A=1\nB=two words", ["output": .string("shell"), "mask": .bool(false)])
        XCTAssertTrue(shell.text.contains("export A=1") && shell.text.contains("export B='two words'"), shell.text)
        let k8s = try await TT.run("env.inspect", "A=hello", ["output": .string("k8s"), "mask": .bool(false), "secretName": .string("my-secret")])
        XCTAssertTrue(k8s.text.contains("name: my-secret"))
        XCTAssertTrue(k8s.text.contains("A: " + Data("hello".utf8).base64EncodedString()))
        XCTAssertEqual(json.isValid, true)
        let bad = try await TT.run("env.inspect", "A=1\nA=2")
        XCTAssertEqual(bad.isValid, false)
    }

    func testEnvDetect() {
        XCTAssertNotNil(EnvInspectTool.detect("A=1\nB=2\nC=3"))
        XCTAssertNil(EnvInspectTool.detect("A=1"))
        XCTAssertNil(EnvInspectTool.detect("hello\nworld"))
    }
}
