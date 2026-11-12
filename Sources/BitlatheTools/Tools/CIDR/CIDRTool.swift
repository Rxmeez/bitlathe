import Foundation
import BitlatheCore

public struct CIDRTool: DevTool {
    public static let id = "cidr.calc"
    public static let name = "CIDR / Subnet Calculator"
    public static let summary = "Network, broadcast, host range, mask and address class for IPv4 and IPv6 blocks"
    public static let category = ToolCategory.inspect
    public static let symbol = "point.3.connected.trianglepath.dotted"
    public static let keywords = ["cidr", "subnet", "ip", "ipv4", "ipv6", "netmask", "network", "broadcast", "hosts", "prefix"]
    public static let samples = [ToolSample("IPv4", "192.168.1.130/26"), ToolSample("IPv6", "2001:db8:abcd::/48"), ToolSample("Mask", "10.0.0.0 255.255.240.0"), ToolSample("Contains?", "10.1.2.3 in 10.0.0.0/8")]
    public struct Options: ToolOptions { public init() {} }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text.trimmed()
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if let r = text.range(of: " in ") {
            let ip = String(text[..<r.lowerBound]).trimmed()
            let block = String(text[r.upperBound...]).trimmed()
            if ip.contains(":") {
                let (a, _) = try Self.parseIPv6(ip)
                let (net, prefix) = try Self.parseIPv6(block)
                let inside = Self.v6Network(a, prefix) == Self.v6Network(net, prefix)
                return ToolOutput(text: inside ? "yes" : "no", metadata: [MetaRow("Result", inside ? "\(ip) is inside \(block)" : "\(ip) is outside \(block)", style: inside ? .success : .danger)])
            }
            let a = try Self.parseIPv4(ip)
            let (net, prefix) = try Self.parseIPv4Block(block)
            let mask = Self.mask(prefix)
            let inside = a & mask == net & mask
            return ToolOutput(text: inside ? "yes" : "no", metadata: [MetaRow("Result", inside ? "\(ip) is inside \(block)" : "\(ip) is outside \(block)", style: inside ? .success : .danger)])
        }
        if text.contains(":") { return try Self.ipv6(text) }
        return try Self.ipv4(text)
    }

    // MARK: IPv4

    static func parseIPv4(_ s: String) throws -> UInt32 {
        let parts = s.trimmed().split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw ToolError("\"\(s)\" is not an IPv4 address") }
        var v: UInt32 = 0
        for p in parts {
            guard let n = UInt32(p), n <= 255 else { throw ToolError("Octet \"\(p)\" is out of range 0–255") }
            v = (v << 8) | n
        }
        return v
    }

    static func parseIPv4Block(_ s: String) throws -> (UInt32, Int) {
        let t = s.trimmed()
        if let slash = t.firstIndex(of: "/") {
            let ip = try parseIPv4(String(t[..<slash]))
            let rest = String(t[t.index(after: slash)...])
            if rest.contains(".") { return (ip, maskToPrefix(try parseIPv4(rest))) }
            guard let prefix = Int(rest), prefix >= 0, prefix <= 32 else { throw ToolError("Prefix must be 0–32") }
            return (ip, prefix)
        }
        let parts = t.split(separator: " ")
        if parts.count == 2 { return (try parseIPv4(String(parts[0])), maskToPrefix(try parseIPv4(String(parts[1])))) }
        return (try parseIPv4(t), 32)
    }

    static func maskToPrefix(_ mask: UInt32) -> Int { mask.nonzeroBitCount }
    static func mask(_ prefix: Int) -> UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }
    static func format(_ v: UInt32) -> String { "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)" }

    static func ipv4(_ text: String) throws -> ToolOutput {
        let (ip, prefix) = try parseIPv4Block(text)
        let m = mask(prefix)
        let net = ip & m
        let bcast = net | ~m
        let total = UInt64(1) << UInt64(32 - prefix)
        let usable: UInt64 = prefix >= 31 ? total : total - 2
        let firstHost = prefix >= 31 ? net : net + 1
        let lastHost = prefix >= 31 ? bcast : bcast - 1
        let cls: String = ip >> 31 == 0 ? "A" : (ip >> 30 == 0b10 ? "B" : (ip >> 29 == 0b110 ? "C" : (ip >> 28 == 0b1110 ? "D (multicast)" : "E (reserved)")))
        var special: [String] = []
        let ranges: [(String, Int, String)] = [("10.0.0.0", 8, "Private (RFC 1918)"), ("172.16.0.0", 12, "Private (RFC 1918)"), ("192.168.0.0", 16, "Private (RFC 1918)"), ("127.0.0.0", 8, "Loopback"),
                                               ("169.254.0.0", 16, "Link-local"), ("100.64.0.0", 10, "Carrier-grade NAT"), ("0.0.0.0", 8, "This network"), ("224.0.0.0", 4, "Multicast"), ("240.0.0.0", 4, "Reserved"),
                                               ("192.0.2.0", 24, "Documentation (TEST-NET-1)"), ("198.51.100.0", 24, "Documentation (TEST-NET-2)"), ("203.0.113.0", 24, "Documentation (TEST-NET-3)"), ("255.255.255.255", 32, "Broadcast")]
        for (base, p, name) in ranges {
            if let b = try? parseIPv4(base), ip & mask(p) == b { special.append(name) }
        }
        let rows = [
            MetaRow("Address", format(ip), style: .mono), MetaRow("CIDR", "\(format(net))/\(prefix)", style: .mono), MetaRow("Netmask", format(m), style: .mono), MetaRow("Wildcard", format(~m), style: .mono),
            MetaRow("Network", format(net), style: .mono), MetaRow("Broadcast", prefix >= 31 ? "— (point-to-point)" : format(bcast), style: .mono),
            MetaRow("Host range", "\(format(firstHost)) – \(format(lastHost))", style: .mono), MetaRow("Total addresses", total.formatted()), MetaRow("Usable hosts", usable.formatted()),
            MetaRow("Class", cls), MetaRow("Type", special.isEmpty ? "Public" : special.joined(separator: ", "), style: special.isEmpty ? .plain : .warning),
            MetaRow("Binary", String(ip, radix: 2).leftPad(32).chunked(8).joined(separator: "."), style: .mono), MetaRow("Hex", String(format: "0x%08X", ip), style: .mono), MetaRow("Integer", String(ip), style: .mono),
            MetaRow("Reverse DNS", format(ip).split(separator: ".").reversed().joined(separator: ".") + ".in-addr.arpa", style: .mono),
        ]
        let facets = [OutputFacet("Network", text: "\(format(net))/\(prefix)"), OutputFacet("Netmask", text: format(m)), OutputFacet("Host range", text: "\(format(firstHost))-\(format(lastHost))")]
        return ToolOutput(text: "\(format(net))/\(prefix)", facets: facets, metadata: rows)
    }

    // MARK: IPv6

    static func parseIPv6(_ s: String) throws -> ([UInt16], Int) {
        var t = s.trimmed()
        var prefix = 128
        if let slash = t.firstIndex(of: "/") {
            guard let p = Int(t[t.index(after: slash)...]), p >= 0, p <= 128 else { throw ToolError("Prefix must be 0–128") }
            prefix = p
            t = String(t[..<slash])
        }
        if t.hasPrefix("["), t.hasSuffix("]") { t = String(t.dropFirst().dropLast()) }
        if let pct = t.firstIndex(of: "%") { t = String(t[..<pct]) }
        let halves = t.components(separatedBy: "::")
        guard halves.count <= 2 else { throw ToolError("Only one :: is allowed") }
        func groups(_ part: String) throws -> [UInt16] {
            if part.isEmpty { return [] }
            var out: [UInt16] = []
            for g in part.split(separator: ":", omittingEmptySubsequences: false) {
                if g.contains(".") {   // embedded IPv4
                    let v4 = try parseIPv4(String(g))
                    out.append(UInt16(v4 >> 16)); out.append(UInt16(v4 & 0xFFFF))
                } else {
                    guard g.count <= 4, let v = UInt16(g, radix: 16) else { throw ToolError("Invalid group \"\(g)\"") }
                    out.append(v)
                }
            }
            return out
        }
        let head = try groups(halves[0])
        let tail = halves.count == 2 ? try groups(halves[1]) : []
        guard head.count + tail.count <= 8, halves.count == 2 || head.count == 8 else { throw ToolError("IPv6 address must have 8 groups (or use ::)") }
        let addr = head + [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
        return (addr, prefix)
    }

    static func v6Network(_ a: [UInt16], _ prefix: Int) -> [UInt16] {
        (0..<8).map { i in
            let bits = max(0, min(16, prefix - i * 16))
            return bits == 0 ? 0 : a[i] & (UInt16.max << UInt16(16 - bits))
        }
    }

    static func v6Compressed(_ a: [UInt16]) -> String {
        var bestStart = -1, bestLen = 0, curStart = -1, curLen = 0
        for (i, g) in a.enumerated() {
            if g == 0 { if curStart < 0 { curStart = i; curLen = 1 } else { curLen += 1 } }
            else { if curLen > bestLen { bestStart = curStart; bestLen = curLen }; curStart = -1; curLen = 0 }
        }
        if curLen > bestLen { bestStart = curStart; bestLen = curLen }
        let hex = a.map { String($0, radix: 16) }
        if bestLen >= 2 {
            let head = hex[..<bestStart].joined(separator: ":")
            let tail = hex[(bestStart + bestLen)...].joined(separator: ":")
            return head + "::" + tail
        }
        return hex.joined(separator: ":")
    }

    static func v6Full(_ a: [UInt16]) -> String { a.map { String(format: "%04x", $0) }.joined(separator: ":") }

    static func ipv6(_ text: String) throws -> ToolOutput {
        let (addr, prefix) = try parseIPv6(text)
        let net = v6Network(addr, prefix)
        let last = (0..<8).map { i -> UInt16 in
            let bits = max(0, min(16, prefix - i * 16))
            return net[i] | (bits == 16 ? 0 : UInt16.max >> UInt16(bits))
        }
        var type = "Global unicast"
        if addr == [0, 0, 0, 0, 0, 0, 0, 1] { type = "Loopback (::1)" }
        else if addr.allSatisfy({ $0 == 0 }) { type = "Unspecified (::)" }
        else if addr[0] & 0xFE00 == 0xFC00 { type = "Unique local (fc00::/7)" }
        else if addr[0] & 0xFFC0 == 0xFE80 { type = "Link-local (fe80::/10)" }
        else if addr[0] == 0x2001, addr[1] == 0x0DB8 { type = "Documentation (2001:db8::/32)" }
        else if addr[0] & 0xFF00 == 0xFF00 { type = "Multicast (ff00::/8)" }
        else if addr[0..<5].allSatisfy({ $0 == 0 }), addr[5] == 0xFFFF { type = "IPv4-mapped (::ffff:a.b.c.d)" }
        else if addr[0] == 0x2002 { type = "6to4" }
        else if addr[0] == 0x2001, addr[1] == 0 { type = "Teredo" }
        let hostBits = 128 - prefix
        let count = hostBits >= 64 ? "2^\(hostBits)" : (UInt64(1) << UInt64(hostBits)).formatted()
        let nibbles = addr.flatMap { g in (0..<4).map { String((g >> UInt16(12 - 4 * $0)) & 0xF, radix: 16) } }
        let rows = [
            MetaRow("Address", v6Compressed(addr), style: .mono), MetaRow("Expanded", v6Full(addr), style: .mono), MetaRow("CIDR", "\(v6Compressed(net))/\(prefix)", style: .mono),
            MetaRow("Network", v6Full(net), style: .mono), MetaRow("Last address", v6Full(last), style: .mono), MetaRow("Addresses", count), MetaRow("Type", type),
            MetaRow("Reverse DNS", nibbles.reversed().joined(separator: ".") + ".ip6.arpa", style: .mono),
            MetaRow("Interface ID", prefix <= 64 ? v6Full(Array(addr[4...])).replacingOccurrences(of: "^0000:0000:0000:0000$", with: "—", options: .regularExpression) : "—", style: .mono),
        ]
        return ToolOutput(text: "\(v6Compressed(net))/\(prefix)", facets: [OutputFacet("Expanded", text: v6Full(addr)), OutputFacet("Compressed", text: v6Compressed(addr))], metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        if s.range(of: "^(\\d{1,3}\\.){3}\\d{1,3}/\\d{1,2}$", options: .regularExpression) != nil { return DetectionScore(0.95, "IPv4 CIDR block") }
        if s.range(of: "^(\\d{1,3}\\.){3}\\d{1,3}$", options: .regularExpression) != nil, (try? parseIPv4(s)) != nil { return DetectionScore(0.6, "IPv4 address") }
        if s.range(of: "^[0-9a-fA-F:]+(/\\d{1,3})?$", options: .regularExpression) != nil, s.contains("::") || s.filter({ $0 == ":" }).count == 7 { return DetectionScore(0.8, "IPv6 address") }
        return nil
    }
}

extension String {
    func leftPad(_ n: Int, with c: Character = "0") -> String { count >= n ? self : String(repeating: c, count: n - count) + self }
    func chunked(_ size: Int) -> [String] {
        var out: [String] = []
        var i = startIndex
        while i < endIndex {
            let e = index(i, offsetBy: size, limitedBy: endIndex) ?? endIndex
            out.append(String(self[i..<e]))
            i = e
        }
        return out
    }
}
