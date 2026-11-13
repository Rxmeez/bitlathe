import Foundation
import BitlatheCore

public struct FakeDataTool: DevTool {
    public static let id = "fake.data"
    public static let name = "Fake Data Generator"
    public static let summary = "Realistic test records — names, emails, addresses, IBANs, cards, IPs, dates — as JSON, CSV or SQL, reproducible with a seed"
    public static let category = ToolCategory.generate
    public static let symbol = "person.3.sequence"
    public static let keywords = ["fake", "mock", "test data", "faker", "seed", "names", "emails", "addresses", "iban", "credit card", "generate", "fixtures"]
    public static let io = ToolIO.generator
    public static let fieldChoices: [(String, String)] = [
        ("id", "Sequential id"), ("uuid", "UUID"), ("firstName", "First name"), ("lastName", "Last name"), ("fullName", "Full name"), ("email", "Email"), ("username", "Username"), ("password", "Password"),
        ("phone", "Phone"), ("street", "Street address"), ("city", "City"), ("postcode", "Postcode"), ("country", "Country"), ("countryCode", "Country code"), ("company", "Company"), ("jobTitle", "Job title"),
        ("iban", "IBAN (valid checksum)"), ("creditCard", "Card number (Luhn test)"), ("cardExpiry", "Card expiry"), ("ipv4", "IPv4"), ("ipv6", "IPv6"), ("macAddress", "MAC address"), ("url", "URL"), ("userAgent", "User agent"),
        ("date", "Date"), ("dateTime", "Date-time ISO"), ("timestamp", "Unix timestamp"), ("birthdate", "Birth date"), ("age", "Age"), ("boolean", "Boolean"), ("integer", "Integer"), ("decimal", "Decimal"), ("price", "Price"),
        ("currency", "Currency"), ("colorHex", "Colour hex"), ("sentence", "Sentence"), ("paragraph", "Paragraph"), ("word", "Word"), ("latitude", "Latitude"), ("longitude", "Longitude"), ("avatar", "Avatar URL"), ("slug", "Slug"), ("status", "Status enum"),
    ]
    public static let optionFields: [OptionField] = [
        .text("fields", "Fields", placeholder: "id, fullName, email, city, iban", default: "id, fullName, email, phone, city, country, iban, createdAt:dateTime", help: "Comma-separated. Use name:type to rename, e.g. created:dateTime. Types: " + fieldChoices.map(\.0).joined(separator: ", ")),
        .stepper("count", "Rows", min: 1, max: 10000, default: 10),
        .segmented("format", "Format", [.init("json", "JSON"), .init("csv", "CSV"), .init("sql", "SQL INSERT"), .init("ndjson", "NDJSON")], default: "json"),
        .stepper("seed", "Seed", min: 0, max: 999_999, default: 42, help: "Same seed → same data"),
        .text("table", "Table", placeholder: "users", default: "users", visibleWhen: ("format", ["sql"])),
        .picker("locale", "Locale", [.init("en", "English (mixed)"), .init("de", "German"), .init("fr", "French"), .init("es", "Spanish"), .init("jp", "Japanese (romanised)")], default: "en"),
    ]
    public struct Options: ToolOptions {
        public var fields = "id, fullName, email, phone, city, country, iban, createdAt:dateTime"
        public var count = 10
        public var format = "json"
        public var seed = 42
        public var table = "users"
        public var locale = "en"
        public init() {}
    }
    public init() {}

    struct Locale: @unchecked Sendable {
        var first: [String], last: [String], cities: [String], streets: [String], countries: [(String, String)], domains: [String], postcode: @Sendable (inout Gen) -> String
    }

    static let en = Locale(first: ["Ada", "Grace", "Alan", "Linus", "Margaret", "Dennis", "Barbara", "Ken", "Hedy", "Tim", "Radia", "Guido", "Katherine", "James", "Annie", "Bjarne", "Frances", "Brendan", "Joan", "Yukihiro", "Lynn", "Donald", "Mary", "Edsger", "Evelyn", "Niklaus", "Sophie", "Anders", "Priya", "Omar", "Mei", "Lucas", "Amara", "Noah", "Zara", "Ethan", "Leila", "Mateo", "Ines", "Kwame"],
                           last: ["Lovelace", "Hopper", "Turing", "Torvalds", "Hamilton", "Ritchie", "Liskov", "Thompson", "Lamarr", "Berners-Lee", "Perlman", "van Rossum", "Johnson", "Gosling", "Easley", "Stroustrup", "Allen", "Eich", "Clarke", "Matsumoto", "Conway", "Knuth", "Wilkes", "Dijkstra", "Granville", "Wirth", "Wilson", "Hejlsberg", "Patel", "Haddad", "Chen", "Silva", "Okafor", "Fischer", "Khan", "Walker", "Rossi", "Garcia", "Mensah", "Novak"],
                           cities: ["London", "Manchester", "Edinburgh", "Bristol", "New York", "San Francisco", "Austin", "Seattle", "Toronto", "Vancouver", "Sydney", "Melbourne", "Dublin", "Cambridge", "Portland", "Denver", "Chicago", "Boston", "Leeds", "Glasgow"],
                           streets: ["High Street", "Station Road", "Main Street", "Church Lane", "Park Avenue", "Victoria Road", "Mill Lane", "King Street", "Queen's Road", "Market Place", "Oak Drive", "Maple Court", "Harbour View", "Castle Hill", "Elm Grove"],
                           countries: [("United Kingdom", "GB"), ("United States", "US"), ("Canada", "CA"), ("Australia", "AU"), ("Ireland", "IE"), ("New Zealand", "NZ")],
                           domains: ["example.com", "example.org", "mail.test", "bitlathe.dev", "acme.io", "northwind.co", "globex.net"],
                           postcode: { g in String(format: "%@%d %d%@%@", g.pick(["SW", "EC", "M", "EH", "BS", "LS"]), g.int(1...20), g.int(1...9), String(UnicodeScalar(UInt8(g.int(65...90)))), String(UnicodeScalar(UInt8(g.int(65...90))))) })
    static let de = Locale(first: ["Anna", "Lukas", "Lena", "Felix", "Mia", "Jonas", "Emma", "Paul", "Sophie", "Leon", "Hannah", "Max", "Lea", "Noah", "Marie", "Finn", "Laura", "Elias", "Julia", "Ben"],
                           last: ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Schröder", "Neumann", "Braun", "Zimmermann", "Krüger", "Hartmann"],
                           cities: ["Berlin", "Hamburg", "München", "Köln", "Frankfurt", "Stuttgart", "Düsseldorf", "Leipzig", "Dresden", "Bremen", "Hannover", "Nürnberg"],
                           streets: ["Hauptstraße", "Bahnhofstraße", "Gartenstraße", "Schulstraße", "Dorfstraße", "Bergstraße", "Lindenweg", "Kirchplatz", "Am Markt", "Rosenweg"],
                           countries: [("Deutschland", "DE"), ("Österreich", "AT"), ("Schweiz", "CH")], domains: ["beispiel.de", "mail.de", "firma.at", "example.ch"],
                           postcode: { g in String(format: "%05d", g.int(10115...99998)) })
    static let fr = Locale(first: ["Camille", "Louis", "Chloé", "Hugo", "Manon", "Lucas", "Léa", "Gabriel", "Inès", "Arthur", "Jade", "Raphaël", "Zoé", "Jules", "Louise", "Adam", "Alice", "Nathan", "Eva", "Tom"],
                           last: ["Martin", "Bernard", "Thomas", "Petit", "Robert", "Richard", "Durand", "Dubois", "Moreau", "Laurent", "Simon", "Michel", "Lefebvre", "Leroy", "Roux", "David", "Bertrand", "Morel", "Fournier", "Girard"],
                           cities: ["Paris", "Lyon", "Marseille", "Toulouse", "Nice", "Nantes", "Strasbourg", "Montpellier", "Bordeaux", "Lille", "Rennes", "Grenoble"],
                           streets: ["Rue de la Paix", "Avenue Victor Hugo", "Rue de la République", "Boulevard Saint-Michel", "Rue des Lilas", "Place du Marché", "Chemin des Vignes", "Rue Pasteur", "Allée des Roses", "Quai des Belges"],
                           countries: [("France", "FR"), ("Belgique", "BE"), ("Suisse", "CH")], domains: ["exemple.fr", "courrier.fr", "societe.be", "example.ch"],
                           postcode: { g in String(format: "%05d", g.int(1000...95999)) })
    static let es = Locale(first: ["Lucía", "Hugo", "Sofía", "Martín", "Martina", "Lucas", "María", "Mateo", "Julia", "Leo", "Paula", "Daniel", "Valeria", "Alejandro", "Emma", "Pablo", "Carla", "Manuel", "Sara", "Álvaro"],
                           last: ["García", "Rodríguez", "González", "Fernández", "López", "Martínez", "Sánchez", "Pérez", "Gómez", "Martín", "Jiménez", "Ruiz", "Hernández", "Díaz", "Moreno", "Muñoz", "Álvarez", "Romero", "Alonso", "Gutiérrez"],
                           cities: ["Madrid", "Barcelona", "Valencia", "Sevilla", "Zaragoza", "Málaga", "Bilbao", "Murcia", "Palma", "Granada", "Ciudad de México", "Bogotá", "Buenos Aires", "Lima"],
                           streets: ["Calle Mayor", "Avenida de la Constitución", "Calle Real", "Paseo de la Castellana", "Plaza de España", "Calle del Sol", "Camino Viejo", "Ronda de Toledo", "Calle Luna", "Avenida del Puerto"],
                           countries: [("España", "ES"), ("México", "MX"), ("Argentina", "AR"), ("Colombia", "CO")], domains: ["ejemplo.es", "correo.es", "empresa.mx", "example.ar"],
                           postcode: { g in String(format: "%05d", g.int(1001...52999)) })
    static let jp = Locale(first: ["Haruto", "Yui", "Sota", "Aoi", "Yuto", "Hina", "Ren", "Sakura", "Riku", "Mei", "Hinata", "Akari", "Kaito", "Rin", "Yamato", "Himari", "Asahi", "Koharu", "Minato", "Tsumugi"],
                           last: ["Sato", "Suzuki", "Takahashi", "Tanaka", "Watanabe", "Ito", "Yamamoto", "Nakamura", "Kobayashi", "Kato", "Yoshida", "Yamada", "Sasaki", "Yamaguchi", "Matsumoto", "Inoue", "Kimura", "Hayashi", "Shimizu", "Saito"],
                           cities: ["Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya", "Sapporo", "Fukuoka", "Kobe", "Sendai", "Hiroshima"],
                           streets: ["1-chome Ginza", "2-chome Shibuya", "3-chome Umeda", "4-chome Namba", "5-chome Sakae", "Nakamachi 2-1", "Honmachi 3-5", "Ekimae-dori 7", "Sakuradori 12", "Minatomirai 1"],
                           countries: [("Japan", "JP")], domains: ["example.jp", "mail.co.jp", "kaisha.jp"],
                           postcode: { g in String(format: "%03d-%04d", g.int(100...999), g.int(0...9999)) })

    static let companies = ["Acme", "Globex", "Initech", "Umbrella", "Hooli", "Vandelay", "Stark", "Wayne", "Wonka", "Tyrell", "Cyberdyne", "Aperture", "Massive Dynamic", "Soylent", "Oscorp", "Pied Piper", "Dunder Mifflin", "Sterling Cooper", "Bluth", "Prestige Worldwide"]
    static let suffixes = ["Ltd", "Inc", "GmbH", "LLC", "Labs", "Studio", "Systems", "Group", "Co", "Technologies"]
    static let jobs = ["Software Engineer", "Product Designer", "Data Scientist", "DevOps Engineer", "Engineering Manager", "QA Analyst", "Technical Writer", "Site Reliability Engineer", "iOS Developer", "Security Researcher", "UX Researcher", "Solutions Architect", "Backend Developer", "Frontend Developer", "CTO"]
    static let statuses = ["active", "pending", "suspended", "archived", "trial"]
    static let currencies = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD"]
    static let words = LoremIpsumTool.classic

    struct Gen {
        var rng: SeededGenerator
        var locale: Locale
        var index = 0
        mutating func int(_ range: ClosedRange<Int>) -> Int { Int(rng.next() % UInt64(range.count)) + range.lowerBound }
        mutating func pick<T>(_ a: [T]) -> T { a[int(0...(a.count - 1))] }
        mutating func double() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 }
        mutating func digits(_ n: Int) -> String { (0..<n).map { _ in String(int(0...9)) }.joined() }
    }

    static func ibanChecksum(_ country: String, _ bban: String) -> String {
        let rearranged = bban + country + "00"
        var numeric = ""
        for c in rearranged { if let d = c.wholeNumberValue { numeric += String(d) } else if let a = c.asciiValue { numeric += String(Int(a) - 55) } }
        var remainder = 0
        for ch in numeric { remainder = (remainder * 10 + (ch.wholeNumberValue ?? 0)) % 97 }
        return String(format: "%02d", 98 - remainder)
    }

    static func luhn(_ partial: String) -> String {
        let digits = partial.compactMap(\.wholeNumberValue)
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            var v = d
            if i % 2 == 0 { v *= 2; if v > 9 { v -= 9 } }
            sum += v
        }
        return partial + String((10 - sum % 10) % 10)
    }

    static func value(_ type: String, _ g: inout Gen, row: Int, first: String, last: String) -> JSONValue {
        let l = g.locale
        switch type {
        case "id": return .number(row + 1)
        case "uuid":
            let b = (0..<16).map { _ in UInt8(g.int(0...255)) }
            var bytes = b; bytes[6] = (bytes[6] & 0x0F) | 0x40; bytes[8] = (bytes[8] & 0x3F) | 0x80
            return .string(IDGeneratorTool.format(bytes))
        case "firstName": return .string(first)
        case "lastName": return .string(last)
        case "fullName": return .string("\(first) \(last)")
        case "email":
            let f = first.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: " ", with: "")
            let la = last.lowercased().folding(options: .diacriticInsensitive, locale: nil).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
            return .string(["\(f).\(la)", "\(f)\(la)\(g.int(1...99))", "\(f.prefix(1))\(la)"][g.int(0...2)] + "@" + g.pick(l.domains))
        case "username": return .string("\(first.lowercased().folding(options: .diacriticInsensitive, locale: nil))_\(last.lowercased().folding(options: .diacriticInsensitive, locale: nil).prefix(6))\(g.int(1...999))")
        case "password": return .string(String((0..<12).map { _ in Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#$%")[g.int(0...57)] }))
        case "phone": return .string("+\(g.pick([1, 44, 49, 33, 34, 81])) \(g.digits(3)) \(g.digits(3)) \(g.digits(4))")
        case "street": return .string("\(g.int(1...240)) \(g.pick(l.streets))")
        case "city": return .string(g.pick(l.cities))
        case "postcode": return .string(l.postcode(&g))
        case "country": return .string(g.pick(l.countries).0)
        case "countryCode": return .string(g.pick(l.countries).1)
        case "company": return .string("\(g.pick(companies)) \(g.pick(suffixes))")
        case "jobTitle": return .string(g.pick(jobs))
        case "iban":
            let country = g.pick(["GB", "DE", "FR", "NL", "ES"])
            let bban: String
            switch country {
            case "DE": bban = g.digits(18)
            case "FR": bban = g.digits(10) + "0" + g.digits(10) + g.digits(2)
            case "NL": bban = "ABNA" + g.digits(10)
            case "ES": bban = g.digits(20)
            default: bban = "BUKB" + g.digits(14)
            }
            return .string(country + ibanChecksum(country, bban) + bban)
        case "creditCard":
            let prefix = g.pick(["4", "51", "4242", "5555", "3782"])   // test ranges; Luhn-valid but not real
            let length = prefix.hasPrefix("37") ? 15 : 16
            return .string(luhn(prefix + g.digits(length - prefix.count - 1)))
        case "cardExpiry": return .string(String(format: "%02d/%02d", g.int(1...12), g.int(26...31)))
        case "ipv4": return .string("\(g.int(1...223)).\(g.int(0...255)).\(g.int(0...255)).\(g.int(1...254))")
        case "ipv6": return .string("2001:db8:" + (0..<6).map { _ in String(g.int(0...65535), radix: 16) }.joined(separator: ":"))
        case "macAddress": return .string((0..<6).map { _ in String(format: "%02x", g.int(0...255)) }.joined(separator: ":"))
        case "url": return .string("https://\(g.pick(l.domains))/\(g.pick(words))/\(g.pick(words))")
        case "userAgent": return .string(g.pick(UserAgentTool.samples).input)
        case "date": return .string(Self.date(g.int(0...(365 * 5)), &g).prefix(10).description)
        case "dateTime": return .string(Self.date(g.int(0...(365 * 5)), &g))
        case "timestamp": return .number(Int(anchor.timeIntervalSince1970) - g.int(0...(86400 * 365 * 5)))
        case "birthdate": return .string(Self.date(g.int(365 * 18...365 * 80), &g).prefix(10).description)
        case "age": return .number(g.int(18...80))
        case "boolean": return .bool(g.int(0...1) == 1)
        case "integer": return .number(g.int(0...10000))
        case "decimal": return .number(Double(g.int(0...1_000_000)) / 1000)
        case "price": return .number(Double(g.int(99...99999)) / 100)
        case "currency": return .string(g.pick(currencies))
        case "colorHex": return .string(String(format: "#%06X", g.int(0...0xFFFFFF)))
        case "word": return .string(g.pick(words))
        case "sentence": return .string((0..<g.int(6...14)).map { _ in g.pick(words) }.joined(separator: " ").capitalizedFirst() + ".")
        case "paragraph": return .string((0..<4).map { _ in (0..<g.int(6...14)).map { _ in g.pick(words) }.joined(separator: " ").capitalizedFirst() + "." }.joined(separator: " "))
        case "latitude": return .number(Double(g.int(-90000...90000)) / 1000)
        case "longitude": return .number(Double(g.int(-180000...180000)) / 1000)
        case "avatar": return .string("https://i.pravatar.cc/150?u=\(first.lowercased())\(row)")
        case "slug": return .string("\(g.pick(words))-\(g.pick(words))-\(g.int(1...999))")
        case "status": return .string(g.pick(statuses))
        default: return .null
        }
    }

    /// "Now" for relative dates, truncated to the start of the UTC day so the same seed gives the same data all day.
    static var anchor: Date { Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 86_400).rounded(.down) * 86_400) }

    static func date(_ daysAgo: Int, _ g: inout Gen) -> String {
        let d = anchor.addingTimeInterval(-Double(daysAgo) * 86400 - Double(g.int(0...86399)))
        let f = ISO8601DateFormatter()
        return f.string(from: d)
    }

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let specs: [(String, String)] = options.fields.split(separator: ",").compactMap { raw in
            let s = raw.trimmed()
            guard !s.isEmpty else { return nil }
            let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
            let name = parts[0].trimmed(), type = parts.count > 1 ? parts[1].trimmed() : parts[0].trimmed()
            return (name, type)
        }
        guard !specs.isEmpty else { throw ToolError("Add at least one field") }
        let unknown = specs.map(\.1).filter { t in !Self.fieldChoices.contains { $0.0 == t } }
        guard unknown.isEmpty else { throw ToolError("Unknown field type\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", "))", hint: "Available: " + Self.fieldChoices.map(\.0).joined(separator: ", ")) }
        let locale: Locale = switch options.locale { case "de": Self.de; case "fr": Self.fr; case "es": Self.es; case "jp": Self.jp; default: Self.en }
        var g = Gen(rng: SeededGenerator(seed: UInt64(options.seed == 0 ? Int.random(in: 1...999_999) : options.seed)), locale: locale)
        var rows: [[(key: String, value: JSONValue)]] = []
        for i in 0..<options.count {
            if i % 500 == 0 { try Task.checkpoint() }
            let first = g.pick(locale.first), last = g.pick(locale.last)
            rows.append(specs.map { (key: $0.0, value: Self.value($0.1, &g, row: i, first: first, last: last)) })
        }
        let meta = [MetaRow("Rows", "\(rows.count)"), MetaRow("Fields", specs.map(\.0).joined(separator: ", ")), MetaRow("Seed", "\(options.seed)"), MetaRow("Note", "Card numbers and IBANs are checksum-valid test values, not real accounts")]
        switch options.format {
        case "csv":
            return ToolOutput(text: CSV.write(header: specs.map(\.0), rows: rows.map { $0.map { XMLJSON.scalar($0.value) } }), language: .csv, metadata: meta)
        case "sql":
            let table = options.table.isEmpty ? "users" : options.table
            let cols = specs.map { "\"\($0.0)\"" }.joined(separator: ", ")
            let values = rows.map { r in "(" + r.map { v -> String in
                switch v.value {
                case .null: "NULL"
                case .bool(let b): b ? "TRUE" : "FALSE"
                case .number(let n): n
                default: "'" + XMLJSON.scalar(v.value).replacingOccurrences(of: "'", with: "''") + "'"
                }
            }.joined(separator: ", ") + ")" }
            return ToolOutput(text: "INSERT INTO \(table) (\(cols)) VALUES\n" + values.joined(separator: ",\n") + ";", language: .sql, metadata: meta)
        case "ndjson":
            return ToolOutput(text: rows.map { JSONSerializer.string(.object($0), options: .minified) }.joined(separator: "\n"), language: .json, metadata: meta)
        default:
            return ToolOutput(text: JSONSerializer.string(.array(rows.map { .object($0) })), language: .json, metadata: meta)
        }
    }
}
