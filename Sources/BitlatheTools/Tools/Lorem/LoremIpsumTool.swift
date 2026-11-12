import Foundation
import BitlatheCore

public struct LoremIpsumTool: DevTool {
    public static let id = "lorem.ipsum"
    public static let name = "Lorem Ipsum"
    public static let summary = "Placeholder text: classic Latin, hipster, tech jargon or corporate, as words, sentences or paragraphs"
    public static let category = ToolCategory.generate
    public static let symbol = "text.quote"
    public static let keywords = ["lorem", "ipsum", "placeholder", "dummy text", "filler", "hipster", "generate"]
    public static let io = ToolIO.generator
    public static let optionFields: [OptionField] = [
        .segmented("unit", "Unit", [.init("paragraphs", "Paragraphs"), .init("sentences", "Sentences"), .init("words", "Words")], default: "paragraphs"),
        .stepper("count", "Count", min: 1, max: 500, default: 3),
        .picker("flavour", "Flavour", [.init("classic", "Classic"), .init("hipster", "Hipster"), .init("tech", "Tech"), .init("corporate", "Corporate"), .init("cupcake", "Cupcake")], default: "classic"),
        .toggle("startClassic", "Start with “Lorem ipsum…”", default: true, visibleWhen: ("flavour", ["classic"])),
        .segmented("format", "Format", [.init("plain", "Plain"), .init("html", "HTML <p>"), .init("markdown", "Markdown")], default: "plain"),
        .stepper("seed", "Seed", min: 0, max: 99999, default: 0, help: "0 = random each time", advanced: true),
    ]
    public struct Options: ToolOptions {
        public var unit = "paragraphs"
        public var count = 3
        public var flavour = "classic"
        public var startClassic = true
        public var format = "plain"
        public var seed = 0
        public init() {}
    }
    public init() {}

    static let classic = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim id est laborum curabitur pretium tincidunt lacus nulla gravida orci a odio nullam varius turpis et commodo pharetra est eros bibendum elit nec luctus magna felis sollicitudin mauris integer in mauris eu nibh euismod gravida duis ac tellus et risus vulputate vehicula donec lobortis risus a elit etiam tempor ut ullamcorper ligula eu tempor congue eros est euismod turpis id tincidunt sapien risus a quam maecenas fermentum consequat mi donec fermentum pellentesque malesuada nulla a mi duis sapien sem aliquet nec commodo eget consequat quis neque aliquam faucibus elit in dignissim semper arcu".split(separator: " ").map(String.init)
    static let hipster = "artisan kombucha selvage raw denim pour-over cold-brew fixie gentrify tote bag mustache vinyl pitchfork bespoke brunch kale chips sustainable small batch ethical locavore banjo chambray cornhole wayfarers ramps narwhal typewriter bicycle rights heirloom meggings craft beer aesthetic literally normcore succulents shoreditch tilde yr tumblr vexillologist hella squid cloud bread hammock polaroid flannel portland farm-to-table meditation celiac dreamcatcher taxidermy whatever semiotics retro authentic bushwick paleo quinoa matcha pabst pinterest letterpress lumbersexual kitsch jianbing hexagon vape mixtape umami".split(separator: " ").map(String.init)
    static let tech = "microservice kubernetes container refactor latency throughput idempotent cache invalidation sharding replica consensus rollback blue-green deploy observability tracing backpressure mutex goroutine async await monad closure middleware webhook schema migration index query planner serverless cold start edge function cdn token bucket rate limit jwt oauth sandbox entropy hash collision merkle tree gossip protocol vector clock eventual consistency saga orchestration circuit breaker sidecar service mesh ingress egress bastion terraform helm chart artifact registry semver changelog monorepo linter bundler tree-shaking hydration virtual dom reducer selector memoize debounce throttle polyfill transpile wasm gpu shader tensor embedding gradient inference quantize".split(separator: " ").map(String.init)
    static let corporate = "synergy leverage stakeholder alignment bandwidth deliverable roadmap north-star paradigm shift value-add low-hanging fruit circle back deep dive touch base move the needle best practice core competency thought leadership holistic scalable robust ecosystem growth hacking disrupt pivot omnichannel customer journey key learnings action items quick win going forward run it up the flagpole boil the ocean ping me offline drill down table stakes bleeding edge mission-critical win-win game changer onboarding empower ideate streamline optimize incentivize monetize actionable insights kpi okr q4 headcount runway burn rate".split(separator: " ").map(String.init)
    static let cupcake = "cupcake ipsum dolor sit amet candy canes marshmallow gingerbread chocolate bar jelly beans toffee brownie muffin lollipop sugar plum caramels croissant macaroon tiramisu danish pudding sweet roll dragée biscuit pastry soufflé wafer bonbon fruitcake cheesecake liquorice tart cookie donut cotton candy halvah oat cake pie topping jujubes ice cream powder gummies apple pie bear claw chupa chups sesame snaps lemon drops carrot cake jelly-o marzipan".split(separator: " ").map(String.init)

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let pool: [String] = switch options.flavour {
        case "hipster": Self.hipster
        case "tech": Self.tech
        case "corporate": Self.corporate
        case "cupcake": Self.cupcake
        default: Self.classic
        }
        var rng = SeededGenerator(seed: options.seed == 0 ? UInt64.random(in: 1...UInt64.max) : UInt64(options.seed))
        func word() -> String { pool[Int(rng.next() % UInt64(pool.count))] }
        func sentence(first: Bool = false) -> String {
            let n = 6 + Int(rng.next() % 12)
            var words = (0..<n).map { _ in word() }
            if first, options.flavour == "classic", options.startClassic { words = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit"] + words.dropFirst(8) }
            if n > 9, rng.next() % 2 == 0 { words[Int(rng.next() % UInt64(n - 4)) + 2] += "," }
            var s = words.joined(separator: " ")
            s = s.prefix(1).uppercased() + s.dropFirst()
            return s + (rng.next() % 10 == 0 ? "!" : ".")
        }
        func paragraph(first: Bool) -> String { (0..<(3 + Int(rng.next() % 5))).map { sentence(first: first && $0 == 0) }.joined(separator: " ") }
        var units: [String]
        switch options.unit {
        case "words":
            var w = (0..<options.count).map { _ in word() }
            if options.flavour == "classic", options.startClassic, options.count >= 2 { w = ["lorem", "ipsum"] + w.dropFirst(2) }
            units = [w.joined(separator: " ").capitalizedFirst()]
        case "sentences":
            units = [(0..<options.count).map { sentence(first: $0 == 0) }.joined(separator: " ")]
        default:
            units = (0..<options.count).map { paragraph(first: $0 == 0) }
        }
        let text: String
        switch options.format {
        case "html": text = units.map { "<p>\($0)</p>" }.joined(separator: "\n")
        case "markdown": text = units.joined(separator: "\n\n")
        default: text = units.joined(separator: "\n\n")
        }
        let wordCount = text.split { $0.isWhitespace }.count
        return ToolOutput(text: text, language: options.format == "html" ? .html : .plain, metadata: [MetaRow("Words", "\(wordCount)"), MetaRow("Characters", "\(text.count)")])
    }
}
