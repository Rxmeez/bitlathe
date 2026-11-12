import Foundation
import BitlatheCore

public struct StringInspectorTool: DevTool {
    public static let id = "string.inspect"
    public static let name = "String Inspector"
    public static let summary = "Length, bytes, words, lines and per-character code points — flags invisible characters, homoglyphs and mixed line endings"
    public static let category = ToolCategory.inspect
    public static let symbol = "textformat.abc.dottedunderline"
    public static let keywords = ["string", "unicode", "code point", "length", "bytes", "characters", "invisible", "zero width", "homoglyph", "emoji", "normalize", "grapheme"]
    public static let samples = [ToolSample("Tricky text", "Héllo wörld 👋🏽 — paypaI.com\u{200B} test\u{FEFF}\r\nsecond line\nthird 🇬🇧 Ａ"), ToolSample("Emoji", "👨‍👩‍👧‍👦 🏳️‍🌈 é vs é")]
    public static let optionFields: [OptionField] = [
        .segmented("view", "View", [.init("summary", "Summary"), .init("chars", "Characters"), .init("issues", "Issues")], default: "summary"),
        .picker("normalize", "Normalise", [.init("none", "Keep"), .init("nfc", "NFC"), .init("nfd", "NFD"), .init("nfkc", "NFKC"), .init("nfkd", "NFKD")], default: "none", help: "Output the text in a Unicode normalisation form"),
        .toggle("stripInvisible", "Strip invisible characters"),
    ]
    public struct Options: ToolOptions {
        public var view = "summary"
        public var normalize = "none"
        public var stripInvisible = false
        public init() {}
    }
    public init() {}

    static let invisibles: [UInt32: String] = [
        0x200B: "ZERO WIDTH SPACE", 0x200C: "ZERO WIDTH NON-JOINER", 0x200D: "ZERO WIDTH JOINER", 0x2060: "WORD JOINER", 0xFEFF: "BYTE ORDER MARK / ZWNBSP", 0x00AD: "SOFT HYPHEN",
        0x200E: "LEFT-TO-RIGHT MARK", 0x200F: "RIGHT-TO-LEFT MARK", 0x202A: "LTR EMBEDDING", 0x202B: "RTL EMBEDDING", 0x202C: "POP DIRECTIONAL FORMATTING", 0x202D: "LTR OVERRIDE", 0x202E: "RTL OVERRIDE",
        0x2066: "LTR ISOLATE", 0x2067: "RTL ISOLATE", 0x2068: "FIRST STRONG ISOLATE", 0x2069: "POP DIRECTIONAL ISOLATE", 0x00A0: "NO-BREAK SPACE", 0x2007: "FIGURE SPACE", 0x202F: "NARROW NO-BREAK SPACE",
        0x3000: "IDEOGRAPHIC SPACE", 0x180E: "MONGOLIAN VOWEL SEPARATOR", 0x034F: "COMBINING GRAPHEME JOINER", 0x061C: "ARABIC LETTER MARK", 0x115F: "HANGUL CHOSEONG FILLER", 0x1160: "HANGUL JUNGSEONG FILLER", 0x3164: "HANGUL FILLER", 0xFFA0: "HALFWIDTH HANGUL FILLER",
        0x2028: "LINE SEPARATOR", 0x2029: "PARAGRAPH SEPARATOR", 0x0009: "TAB", 0x000B: "VERTICAL TAB", 0x000C: "FORM FEED", 0x0085: "NEXT LINE",
    ]
    static let confusables: [Character: String] = [
        "а": "Cyrillic a (looks like Latin a)", "е": "Cyrillic e", "о": "Cyrillic o", "р": "Cyrillic r (looks like p)", "с": "Cyrillic s (looks like c)", "у": "Cyrillic u (looks like y)", "х": "Cyrillic h (looks like x)",
        "і": "Cyrillic i", "ј": "Cyrillic je (looks like j)", "ѕ": "Cyrillic dze (looks like s)", "А": "Cyrillic A", "В": "Cyrillic V (looks like B)", "Е": "Cyrillic E", "К": "Cyrillic K", "М": "Cyrillic M", "Н": "Cyrillic N (looks like H)",
        "О": "Cyrillic O", "Р": "Cyrillic R (looks like P)", "С": "Cyrillic S (looks like C)", "Т": "Cyrillic T", "Х": "Cyrillic H (looks like X)", "ο": "Greek omicron (looks like o)", "ν": "Greek nu (looks like v)", "α": "Greek alpha",
        "Ι": "Greek capital iota (looks like I)", "Ο": "Greek capital omicron", "Ρ": "Greek capital rho (looks like P)", "Τ": "Greek capital tau", "Ζ": "Greek capital zeta", "Β": "Greek capital beta", "Η": "Greek capital eta",
        "ℓ": "script small l", "I": "", "l": "", "ı": "dotless i", "ɡ": "script g", "ꓲ": "Lisu letter (looks like I)",
    ]

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        var text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        var outputText = text
        if options.stripInvisible { outputText = String(outputText.unicodeScalars.filter { !Self.invisibles.keys.contains($0.value) || $0 == "\t" }) }
        switch options.normalize {
        case "nfc": outputText = outputText.precomposedStringWithCanonicalMapping
        case "nfd": outputText = outputText.decomposedStringWithCanonicalMapping
        case "nfkc": outputText = outputText.precomposedStringWithCompatibilityMapping
        case "nfkd": outputText = outputText.decomposedStringWithCompatibilityMapping
        default: break
        }
        let scalars = Array(text.unicodeScalars)
        let graphemes = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lineEndings = text.lineEndingKinds
        let lines = text.lineCount
        var issues: [(Range<Int>, String)] = []
        var utf16Offset = 0
        var nonASCII = 0
        var emojiCount = 0
        var combining = 0
        var scripts: Set<String> = []
        for u in scalars {
            let len = u.utf16.count
            if let name = Self.invisibles[u.value], u != "\t" { issues.append((utf16Offset..<(utf16Offset + len), "U+\(String(format: "%04X", u.value)) \(name)")) }
            if u.properties.generalCategory == .control, u != "\n", u != "\r", u != "\t" { issues.append((utf16Offset..<(utf16Offset + len), "Control character U+\(String(format: "%04X", u.value))")) }
            if u.value == 0xFFFD { issues.append((utf16Offset..<(utf16Offset + len), "Replacement character (broken encoding)")) }
            if u.value > 0x7F { nonASCII += 1 }
            if u.properties.isEmojiPresentation || (u.properties.isEmoji && u.value > 0x2000) { emojiCount += 1 }
            if u.properties.generalCategory == .nonspacingMark || u.properties.generalCategory == .enclosingMark { combining += 1 }
            if u.properties.isAlphabetic { scripts.insert(Self.script(u)) }
            if let c = Self.confusables[Character(u)], !c.isEmpty { issues.append((utf16Offset..<(utf16Offset + len), "Homoglyph: \(c)")) }
            if (0xFF01...0xFF5E).contains(u.value) { issues.append((utf16Offset..<(utf16Offset + len), "Fullwidth form of '\(UnicodeScalar(u.value - 0xFEE0).map { String($0) } ?? "")'")) }
            utf16Offset += len
        }
        if lineEndings.count > 1 { issues.append((0..<0, "Mixed line endings: \(lineEndings.sorted().joined(separator: " + "))")) }
        if text.hasPrefix("\u{FEFF}") { issues.append((0..<1, "Starts with a byte order mark")) }
        if scripts.count > 1, scripts.contains("Latin"), scripts.contains("Cyrillic") || scripts.contains("Greek") { issues.append((0..<0, "Mixed scripts: \(scripts.sorted().joined(separator: ", ")) — possible spoofing")) }
        if text.hasSuffix(" ") || text.contains(" \n") { issues.append((0..<0, "Trailing whitespace present")) }
        let nfc = text.precomposedStringWithCanonicalMapping
        if nfc != text { issues.append((0..<0, "Text is not NFC-normalised (\(text.unicodeScalars.count - nfc.unicodeScalars.count) decomposed sequences)")) }
        text = ""

        let rows: [MetaRow] = [
            MetaRow("Characters (graphemes)", "\(graphemes)"), MetaRow("Code points", "\(scalars.count)"), MetaRow("UTF-8 bytes", "\(outputText.utf8.count)"), MetaRow("UTF-16 units", "\(outputText.utf16.count)"),
            MetaRow("Words", "\(words)"), MetaRow("Lines", "\(lines)"), MetaRow("Line endings", lineEndings.isEmpty ? "none" : lineEndings.sorted().joined(separator: " + "), style: lineEndings.count > 1 ? .warning : .plain),
            MetaRow("Non-ASCII", "\(nonASCII)"), MetaRow("Emoji", "\(emojiCount)"), MetaRow("Combining marks", "\(combining)"), MetaRow("Scripts", scripts.isEmpty ? "—" : scripts.sorted().joined(separator: ", ")),
            MetaRow("Issues", issues.isEmpty ? "None" : "\(issues.count)", style: issues.isEmpty ? .success : .warning),
            MetaRow("ASCII only", nonASCII == 0 ? "Yes" : "No"), MetaRow("Palindrome", Self.isPalindrome(outputText) ? "Yes" : "No"),
        ]
        var annotations = issues.filter { !$0.0.isEmpty }.map { Annotation(.input, range: $0.0, style: .warning, tooltip: $0.1) }
        if annotations.count > 500 { annotations = Array(annotations.prefix(500)) }
        var body: String
        switch options.view {
        case "chars":
            var lines: [String] = ["Char  Code point  UTF-8        Name / Category"]
            var count = 0
            for g in outputText {
                for u in g.unicodeScalars {
                    let visible = u.properties.generalCategory == .control || Self.invisibles[u.value] != nil ? "·" : String(u)
                    let name = u.properties.name ?? Self.invisibles[u.value] ?? "?"
                    lines.append("\(visible.padding(toLength: 5, withPad: " ", startingAt: 0)) U+\(String(format: "%04X", u.value).padding(toLength: 9, withPad: " ", startingAt: 0)) \(String(u).utf8.map { String(format: "%02X", $0) }.joined(separator: " ").padding(toLength: 12, withPad: " ", startingAt: 0)) \(name)  [\(Self.category(u.properties.generalCategory))]")
                    count += 1
                    if count > 5000 { lines.append("… truncated at 5000 code points"); break }
                }
                if count > 5000 { break }
            }
            body = lines.joined(separator: "\n")
        case "issues":
            body = issues.isEmpty ? "No issues found." : issues.map { r, m in
                if r.isEmpty { return "• \(m)" }
                let (l, c) = outputText.lineAndColumn(utf16Offset: r.lowerBound)
                return "• Ln \(l), Col \(c): \(m)"
            }.joined(separator: "\n")
        default:
            body = outputText
        }
        return ToolOutput(text: body, metadata: rows, annotations: annotations, warnings: options.view == "summary" ? issues.prefix(8).map(\.1) : [], isValid: issues.isEmpty ? true : nil)
    }

    static func isPalindrome(_ s: String) -> Bool {
        let clean = s.lowercased().filter { $0.isLetter || $0.isNumber }
        return clean.count > 1 && clean == String(clean.reversed())
    }

    static func script(_ u: UnicodeScalar) -> String {
        switch u.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: "Latin"
        case 0x370...0x3FF, 0x1F00...0x1FFF: "Greek"
        case 0x400...0x4FF, 0x500...0x52F: "Cyrillic"
        case 0x590...0x5FF: "Hebrew"
        case 0x600...0x6FF, 0x750...0x77F: "Arabic"
        case 0x900...0x97F: "Devanagari"
        case 0xE00...0xE7F: "Thai"
        case 0x1100...0x11FF, 0xAC00...0xD7AF, 0x3130...0x318F: "Hangul"
        case 0x3040...0x309F: "Hiragana"
        case 0x30A0...0x30FF: "Katakana"
        case 0x4E00...0x9FFF, 0x3400...0x4DBF: "Han"
        case 0xFF00...0xFFEF: "Fullwidth"
        default: "Other"
        }
    }

    static func category(_ c: Unicode.GeneralCategory) -> String {
        switch c {
        case .uppercaseLetter: "Lu"
        case .lowercaseLetter: "Ll"
        case .titlecaseLetter: "Lt"
        case .modifierLetter: "Lm"
        case .otherLetter: "Lo"
        case .nonspacingMark: "Mn"
        case .spacingMark: "Mc"
        case .enclosingMark: "Me"
        case .decimalNumber: "Nd"
        case .letterNumber: "Nl"
        case .otherNumber: "No"
        case .connectorPunctuation: "Pc"
        case .dashPunctuation: "Pd"
        case .openPunctuation: "Ps"
        case .closePunctuation: "Pe"
        case .initialPunctuation: "Pi"
        case .finalPunctuation: "Pf"
        case .otherPunctuation: "Po"
        case .mathSymbol: "Sm"
        case .currencySymbol: "Sc"
        case .modifierSymbol: "Sk"
        case .otherSymbol: "So"
        case .spaceSeparator: "Zs"
        case .lineSeparator: "Zl"
        case .paragraphSeparator: "Zp"
        case .control: "Cc"
        case .format: "Cf"
        case .surrogate: "Cs"
        case .privateUse: "Co"
        case .unassigned: "Cn"
        @unknown default: "?"
        }
    }
}
