import Foundation
import BitlatheCore

public struct HTMLEntitiesTool: DevTool {
    public static let id = "html.entities"
    public static let name = "HTML Entities"
    public static let summary = "Encode text as HTML entities (named, decimal or hex) and decode entities back"
    public static let category = ToolCategory.encode
    public static let symbol = "ampersand"
    public static let keywords = ["html", "entity", "entities", "escape", "unescape", "&amp;", "&lt;", "encode", "decode"]
    public static let samples = [ToolSample("Encode", "<a href=\"x\">Tom & Jerry's café</a> © 2026"), ToolSample("Decode", "&lt;p&gt;Caf&eacute; &amp; cr&#232;me &#x2014; &copy;&lt;/p&gt;", options: ["mode": .string("decode")])]
    public static let optionFields: [OptionField] = [
        .encodeDecode,
        .segmented("style", "Style", [.init("named", "Named"), .init("decimal", "&#NNN;"), .init("hex", "&#xHH;")], default: "named", visibleWhen: ("mode", ["encode"])),
        .segmented("scope", "Encode", [.init("special", "Special only"), .init("nonascii", "Special + non-ASCII"), .init("all", "Everything")], default: "nonascii", visibleWhen: ("mode", ["encode"])),
    ]
    public struct Options: ToolOptions {
        public var mode = "encode"
        public var style = "named"
        public var scope = "nonascii"
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.isEmpty else { throw ToolError.emptyInput }
        if options.mode == "encode" {
            var out = ""
            var count = 0
            for u in text.unicodeScalars {
                let special = ["&", "<", ">", "\"", "'"].contains(String(u))
                let shouldEncode = options.scope == "all" || special || (options.scope == "nonascii" && u.value > 0x7E)
                if !shouldEncode { out.unicodeScalars.append(u); continue }
                count += 1
                if options.style == "named", let name = HTMLEntityTable.nameFor[u.value] { out += "&\(name);" }
                else if options.style == "hex" { out += String(format: "&#x%X;", u.value) }
                else if options.style == "named", special { out += "&#\(u.value);" }
                else { out += "&#\(u.value);" }
            }
            return ToolOutput(text: out, metadata: [MetaRow("Entities", "\(count)")])
        }
        let (decoded, count) = HTMLEntityTable.decode(text)
        return ToolOutput(text: decoded, metadata: [MetaRow("Entities decoded", "\(count)")])
    }

    public static func detect(_ s: String) -> DetectionScore? {
        let n = s.matches(of: /&(#\d+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]{1,31});/).count
        return n >= 2 ? DetectionScore(min(0.5 + Double(n) * 0.08, 0.85), "HTML entities", options: ["mode": .string("decode")]) : nil
    }
}

public enum HTMLEntityTable {
    public static let entities: [String: UInt32] = {
        var m: [String: UInt32] = [
            "quot": 34, "amp": 38, "apos": 39, "lt": 60, "gt": 62, "nbsp": 160, "iexcl": 161, "cent": 162, "pound": 163, "curren": 164, "yen": 165, "brvbar": 166, "sect": 167,
            "uml": 168, "copy": 169, "ordf": 170, "laquo": 171, "not": 172, "shy": 173, "reg": 174, "macr": 175, "deg": 176, "plusmn": 177, "sup2": 178, "sup3": 179, "acute": 180,
            "micro": 181, "para": 182, "middot": 183, "cedil": 184, "sup1": 185, "ordm": 186, "raquo": 187, "frac14": 188, "frac12": 189, "frac34": 190, "iquest": 191,
            "Agrave": 192, "Aacute": 193, "Acirc": 194, "Atilde": 195, "Auml": 196, "Aring": 197, "AElig": 198, "Ccedil": 199, "Egrave": 200, "Eacute": 201, "Ecirc": 202,
            "Euml": 203, "Igrave": 204, "Iacute": 205, "Icirc": 206, "Iuml": 207, "ETH": 208, "Ntilde": 209, "Ograve": 210, "Oacute": 211, "Ocirc": 212, "Otilde": 213, "Ouml": 214,
            "times": 215, "Oslash": 216, "Ugrave": 217, "Uacute": 218, "Ucirc": 219, "Uuml": 220, "Yacute": 221, "THORN": 222, "szlig": 223, "agrave": 224, "aacute": 225,
            "acirc": 226, "atilde": 227, "auml": 228, "aring": 229, "aelig": 230, "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234, "euml": 235, "igrave": 236,
            "iacute": 237, "icirc": 238, "iuml": 239, "eth": 240, "ntilde": 241, "ograve": 242, "oacute": 243, "ocirc": 244, "otilde": 245, "ouml": 246, "divide": 247,
            "oslash": 248, "ugrave": 249, "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "thorn": 254, "yuml": 255, "OElig": 338, "oelig": 339, "Scaron": 352,
            "scaron": 353, "Yuml": 376, "fnof": 402, "circ": 710, "tilde": 732, "Alpha": 913, "Beta": 914, "Gamma": 915, "Delta": 916, "Epsilon": 917, "Zeta": 918, "Eta": 919,
            "Theta": 920, "Iota": 921, "Kappa": 922, "Lambda": 923, "Mu": 924, "Nu": 925, "Xi": 926, "Omicron": 927, "Pi": 928, "Rho": 929, "Sigma": 931, "Tau": 932, "Upsilon": 933,
            "Phi": 934, "Chi": 935, "Psi": 936, "Omega": 937, "alpha": 945, "beta": 946, "gamma": 947, "delta": 948, "epsilon": 949, "zeta": 950, "eta": 951, "theta": 952,
            "iota": 953, "kappa": 954, "lambda": 955, "mu": 956, "nu": 957, "xi": 958, "omicron": 959, "pi": 960, "rho": 961, "sigmaf": 962, "sigma": 963, "tau": 964,
            "upsilon": 965, "phi": 966, "chi": 967, "psi": 968, "omega": 969, "thetasym": 977, "upsih": 978, "piv": 982, "ensp": 8194, "emsp": 8195, "thinsp": 8201,
            "zwnj": 8204, "zwj": 8205, "lrm": 8206, "rlm": 8207, "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218, "ldquo": 8220, "rdquo": 8221,
            "bdquo": 8222, "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230, "permil": 8240, "prime": 8242, "Prime": 8243, "lsaquo": 8249, "rsaquo": 8250,
            "oline": 8254, "frasl": 8260, "euro": 8364, "image": 8465, "weierp": 8472, "real": 8476, "trade": 8482, "alefsym": 8501, "larr": 8592, "uarr": 8593, "rarr": 8594,
            "darr": 8595, "harr": 8596, "crarr": 8629, "lArr": 8656, "uArr": 8657, "rArr": 8658, "dArr": 8659, "hArr": 8660, "forall": 8704, "part": 8706, "exist": 8707,
            "empty": 8709, "nabla": 8711, "isin": 8712, "notin": 8713, "ni": 8715, "prod": 8719, "sum": 8721, "minus": 8722, "lowast": 8727, "radic": 8730, "prop": 8733,
            "infin": 8734, "ang": 8736, "and": 8743, "or": 8744, "cap": 8745, "cup": 8746, "int": 8747, "there4": 8756, "sim": 8764, "cong": 8773, "asymp": 8776, "ne": 8800,
            "equiv": 8801, "le": 8804, "ge": 8805, "sub": 8834, "sup": 8835, "nsub": 8836, "sube": 8838, "supe": 8839, "oplus": 8853, "otimes": 8855, "perp": 8869, "sdot": 8901,
            "lceil": 8968, "rceil": 8969, "lfloor": 8970, "rfloor": 8971, "lang": 9001, "rang": 9002, "loz": 9674, "spades": 9824, "clubs": 9827, "hearts": 9829, "diams": 9830,
            "check": 10003, "cross": 10007, "star": 9734, "starf": 9733, "phone": 9742, "female": 9792, "male": 9794, "hyphen": 8208, "dash": 8208, "nbsp;": 160,
            "Tab": 9, "NewLine": 10, "excl": 33, "num": 35, "dollar": 36, "percnt": 37, "lpar": 40, "rpar": 41, "ast": 42, "plus": 43, "comma": 44, "period": 46, "sol": 47,
            "colon": 58, "semi": 59, "equals": 61, "quest": 63, "commat": 64, "lsqb": 91, "bsol": 92, "rsqb": 93, "Hat": 94, "lowbar": 95, "grave": 96, "lcub": 123, "verbar": 124,
            "rcub": 125, "half": 189, "laquo;": 171, "lsquor": 8218, "rsquor": 8217, "ldquor": 8222, "rdquor": 8221, "horbar": 8213, "Vert": 8214, "nldr": 8229, "mldr": 8230,
            "caret": 8257, "hybull": 8259, "bprime": 8245, "tprime": 8244, "qprime": 8279, "frac13": 8531, "frac23": 8532, "frac15": 8533, "frac18": 8539, "frac38": 8540,
            "frac58": 8541, "frac78": 8542, "larrb": 8676, "rarrb": 8677, "LeftArrow": 8592, "RightArrow": 8594, "UpArrow": 8593, "DownArrow": 8595, "boxh": 9472, "boxv": 9474,
            "block": 9608, "blk14": 9617, "blk12": 9618, "blk34": 9619, "squ": 9633, "square": 9633, "squf": 9642, "rect": 9645, "cir": 9675, "xcirc": 9711, "bigcirc": 9711,
            "sharp": 9839, "flat": 9837, "natural": 9838, "sung": 9834, "spadesuit": 9824, "heartsuit": 9829, "diamondsuit": 9830, "clubsuit": 9827, "checkmark": 10003,
            "maltese": 10016, "sext": 10038, "VerticalSeparator": 10072, "lbbrk": 10098, "rbbrk": 10099, "lobrk": 10214, "robrk": 10215, "langle": 10216, "rangle": 10217,
            "ohm": 937, "mho": 8487, "angst": 197, "numero": 8470, "copysr": 8471, "incare": 8453, "ell": 8467, "planck": 8463, "hbar": 8463, "Copf": 8450, "naturals": 8469, "rationals": 8474, "reals": 8477, "integers": 8484,
        ]
        m["nbsp;"] = nil
        m["laquo;"] = nil
        return m
    }()

    public static let nameFor: [UInt32: String] = {
        var m: [UInt32: String] = [:]
        for (k, v) in entities where m[v] == nil || k.count < m[v]!.count { m[v] = k }   // swiftlint:disable:this force_unwrapping
        m[39] = "#39"
        m[160] = "nbsp"
        m[8212] = "mdash"
        m[8211] = "ndash"
        m[8230] = "hellip"
        m[8217] = "rsquo"
        m[8221] = "rdquo"
        m[8222] = "bdquo"
        m[8218] = "sbquo"
        m[8208] = "hyphen"
        m[9633] = "square"
        return m
    }()

    public static func decode(_ s: String) -> (String, Int) {
        guard s.contains("&") else { return (s, 0) }
        var out = ""
        var count = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let semi = s[i...].prefix(40).firstIndex(of: ";") {
                let body = s[s.index(after: i)..<semi]
                var scalar: UInt32?
                if body.hasPrefix("#x") || body.hasPrefix("#X") { scalar = UInt32(body.dropFirst(2), radix: 16) }
                else if body.hasPrefix("#") { scalar = UInt32(body.dropFirst()) }
                else { scalar = entities[String(body)] }
                if let v = scalar, let u = UnicodeScalar(v) {
                    out.unicodeScalars.append(u)
                    count += 1
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return (out, count)
    }
}
