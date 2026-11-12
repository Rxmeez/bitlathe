import Foundation
import BitlatheCore

public struct NumberBaseTool: DevTool {
    public static let id = "number.base"
    public static let name = "Number Base Converter"
    public static let summary = "Binary, octal, decimal, hex, base 32/36 and custom bases, signed and unsigned"
    public static let category = ToolCategory.convert
    public static let symbol = "number"
    public static let keywords = ["binary", "hex", "octal", "decimal", "base", "radix", "bits", "two's complement", "convert"]
    public static let samples = [ToolSample("Decimal", "255"), ToolSample("Hex", "0xDEADBEEF"), ToolSample("Negative", "-42")]
    public static let optionFields: [OptionField] = [
        .picker("inputBase", "From", [.init("auto", "Auto (0x, 0b, 0o prefixes)"), .init("2", "Binary"), .init("8", "Octal"), .init("10", "Decimal"), .init("16", "Hex"), .init("32", "Base 32"), .init("36", "Base 36"), .init("custom", "Custom")], default: "auto"),
        .stepper("customBase", "Custom base", min: 2, max: 36, default: 7, visibleWhen: ("inputBase", ["custom"])),
        .picker("bits", "Width", [.init("auto", "Auto"), .init("8", "8-bit"), .init("16", "16-bit"), .init("32", "32-bit"), .init("64", "64-bit")], default: "auto"),
        .toggle("grouping", "Group digits", default: true),
    ]
    public struct Options: ToolOptions {
        public var inputBase = "auto"
        public var customBase = 7
        public var bits = "auto"
        public var grouping = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var text = input.text.trimmed().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")
        guard !text.isEmpty else { throw ToolError.emptyInput }
        var negative = false
        if text.hasPrefix("-") { negative = true; text.removeFirst() }
        if text.hasPrefix("+") { text.removeFirst() }
        var base: Int
        switch options.inputBase {
        case "auto":
            let l = text.lowercased()
            if l.hasPrefix("0x") { base = 16; text = String(text.dropFirst(2)) }
            else if l.hasPrefix("0b") { base = 2; text = String(text.dropFirst(2)) }
            else if l.hasPrefix("0o") { base = 8; text = String(text.dropFirst(2)) }
            else if l.hasPrefix("#"), l.count <= 9 { base = 16; text = String(text.dropFirst()) }
            else if l.range(of: "^[0-9]+$", options: .regularExpression) != nil { base = 10 }
            else if l.range(of: "^[0-9a-f]+h$", options: .regularExpression) != nil { base = 16; text.removeLast() }
            else if l.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil { base = 16 }
            else if l.range(of: "^[0-9a-z]+$", options: .regularExpression) != nil { base = 36 }
            else { throw ToolError("Not a number", hint: "Use 0x, 0b, 0o prefixes or choose the input base") }
        case "custom": base = options.customBase
        default: base = Int(options.inputBase) ?? 10
        }
        guard let magnitude = UInt64(text, radix: base) else {
            if UInt64(text.prefix(1), radix: base) == nil { throw ToolError("\"\(text.prefix(1))\" is not a valid digit in base \(base)") }
            throw ToolError("Number is too large (max 64-bit)")
        }
        let bits: Int
        switch options.bits {
        case "auto":
            let needed = negative ? (magnitude > UInt64(Int64.max) + 1 ? 128 : 64) : max(1, 64 - magnitude.leadingZeroBitCount)
            bits = needed <= 8 ? 8 : (needed <= 16 ? 16 : (needed <= 32 ? 32 : 64))
        default: bits = Int(options.bits) ?? 64
        }
        if negative, magnitude > UInt64(1) << UInt64(min(bits - 1, 63)) { throw ToolError("-\(magnitude) does not fit in \(bits) signed bits") }
        if !negative, bits < 64, magnitude >= UInt64(1) << UInt64(bits) { throw ToolError("\(magnitude) does not fit in \(bits) bits") }
        let mask: UInt64 = bits >= 64 ? .max : (UInt64(1) << UInt64(bits)) - 1
        let twos: UInt64 = negative ? (~magnitude &+ 1) & mask : magnitude
        let signedValue: Int64 = negative ? -Int64(magnitude) : (bits < 64 && magnitude >> UInt64(bits - 1) == 1 ? Int64(magnitude) - Int64(1 << UInt64(bits)) : Int64(bitPattern: magnitude))

        func fmt(_ v: UInt64, _ radix: Int, group: Int, pad: Int = 0) -> String {
            var s = String(v, radix: radix).uppercased()
            if pad > 0 { s = String(repeating: "0", count: max(0, pad - s.count)) + s }
            guard options.grouping, group > 0 else { return s }
            var out = ""
            for (i, c) in s.reversed().enumerated() {
                if i > 0, i % group == 0 { out.append(" ") }
                out.append(c)
            }
            return String(out.reversed())
        }
        let prefix = negative ? "-" : ""
        var rows = [
            MetaRow("Decimal", prefix + fmt(magnitude, 10, group: 3), style: .mono),
            MetaRow("Hex", prefix + "0x" + fmt(magnitude, 16, group: 4), style: .mono),
            MetaRow("Binary", prefix + "0b" + fmt(magnitude, 2, group: 4), style: .mono),
            MetaRow("Octal", prefix + "0o" + fmt(magnitude, 8, group: 3), style: .mono),
            MetaRow("Base 32", prefix + fmt(magnitude, 32, group: 0), style: .mono),
            MetaRow("Base 36", prefix + fmt(magnitude, 36, group: 0), style: .mono),
        ]
        if options.inputBase == "custom" { rows.append(MetaRow("Base \(base)", prefix + fmt(magnitude, base, group: 0), style: .mono)) }
        rows.append(MetaRow("Width", "\(bits)-bit"))
        rows.append(MetaRow("Signed", "\(signedValue)", style: .mono))
        rows.append(MetaRow("Unsigned", "\(twos)", style: .mono))
        rows.append(MetaRow("Two's complement hex", "0x" + fmt(twos, 16, group: 4, pad: bits / 4), style: .mono))
        rows.append(MetaRow("Two's complement binary", fmt(twos, 2, group: 4, pad: bits), style: .mono))
        rows.append(MetaRow("Bits set", "\(twos.nonzeroBitCount)"))
        if magnitude <= 0x10FFFF, let scalar = UnicodeScalar(UInt32(magnitude)), !negative {
            rows.append(MetaRow("Unicode", "U+" + String(format: "%04X", magnitude) + "  \(scalar.properties.name ?? "")" + (scalar.properties.isWhitespace ? "" : "  \(Character(scalar))")))
        }
        let facets = [OutputFacet("Hex", text: prefix + fmt(magnitude, 16, group: 0)), OutputFacet("Binary", text: prefix + fmt(magnitude, 2, group: 0)),
                      OutputFacet("Octal", text: prefix + fmt(magnitude, 8, group: 0)), OutputFacet("Decimal", text: prefix + String(magnitude))]
        return ToolOutput(text: "", facets: facets, metadata: rows)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard Detect.isSingleLine(s), s.count <= 70 else { return nil }
        let l = s.lowercased()
        if l.range(of: "^-?0x[0-9a-f_]+$", options: .regularExpression) != nil { return DetectionScore(0.8, "Hex number") }
        if l.range(of: "^-?0b[01_]+$", options: .regularExpression) != nil { return DetectionScore(0.85, "Binary number") }
        if l.range(of: "^-?0o[0-7_]+$", options: .regularExpression) != nil { return DetectionScore(0.85, "Octal number") }
        if l.range(of: "^[01]{8,64}$", options: .regularExpression) != nil { return DetectionScore(0.6, "Binary digits") }
        if l.range(of: "^-?\\d{1,9}$", options: .regularExpression) != nil { return DetectionScore(0.35, "Integer") }
        return nil
    }
}
