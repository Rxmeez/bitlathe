import Foundation
import BitlatheCore

/// Draws a GitHub Actions workflow: what starts it, its jobs in the order `needs:` forces, each job's runner, matrix
/// and steps. The text result is an outline (for the CLI and agents); the app draws the graph from the `Graph` facet.
public struct GitHubActionsTool: DevTool {
    public static let id = "gha.visualize"
    public static let name = "GitHub Actions Visualizer"
    public static let summary = "See a workflow as a graph: triggers, jobs in dependency order, runners, matrices and steps"
    public static let category = ToolCategory.inspect
    public static let symbol = "point.3.connected.trianglepath.dotted"
    public static let keywords = ["github", "actions", "workflow", "ci", "cd", "pipeline", "yaml", "needs", "jobs", "matrix", "graph", "visualize", "visualise", "diagram"]
    public static let samples = [ToolSample("CI and deploy", sampleWorkflow)]
    public static let optionFields: [OptionField] = [
        .toggle("steps", "Steps on cards", default: true, help: "List each job's steps on its card; they are always in the inspector"),
    ]
    public struct Options: ToolOptions {
        public var steps = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let workflow = try Workflow.parse(text)
        let diagram = workflow.diagram(stepsOnCards: options.steps)
        var rows = [MetaRow("Workflow", workflow.name ?? "(unnamed)")]
        rows.append(MetaRow("Triggers", workflow.triggers.isEmpty ? "none" : workflow.triggers.map(\.event).joined(separator: ", ")))
        rows.append(MetaRow("Jobs", "\(workflow.jobs.count)"))
        rows.append(MetaRow("Stages", "\(workflow.stageCount)"))
        let runs = workflow.jobs.map { $0.matrix?.count ?? 1 }.reduce(0, +)
        if workflow.jobs.contains(where: { $0.matrix != nil }) {
            rows.append(MetaRow("Runs", workflow.jobs.contains { $0.matrix?.count == nil && $0.matrix != nil } ? "\(runs)+ (some matrices are computed at run time)" : "\(runs) with matrices expanded"))
        }
        rows.append(MetaRow("Steps", "\(workflow.jobs.map(\.steps.count).reduce(0, +))"))
        return ToolOutput(text: workflow.outline(), language: .plain,
                          facets: [OutputFacet("Mermaid", text: diagram.mermaid()), OutputFacet(Diagram.facetTitle, text: diagram.json(), language: .json)],
                          metadata: rows, warnings: workflow.warnings)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("jobs:"), s.range(of: #"(?m)^jobs:\s*$"#, options: .regularExpression) != nil,
              s.range(of: #"(?m)^\s+(runs-on|uses|steps):"#, options: .regularExpression) != nil else { return nil }
        let hasOn = s.range(of: #"(?m)^("?on"?|true):"#, options: .regularExpression) != nil
        return DetectionScore(hasOn ? 0.93 : 0.8, "GitHub Actions workflow")
    }

    static let sampleWorkflow = """
        name: CI
        on:
          push:
            branches: [main]
          pull_request:
          schedule:
            - cron: "0 3 * * *"
          workflow_dispatch:

        jobs:
          lint:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: actions/setup-node@v4
              - run: npm ci
              - run: npm run lint

          test:
            needs: lint
            runs-on: ${{ matrix.os }}
            strategy:
              matrix:
                os: [ubuntu-latest, macos-latest]
                node: [18, 20, 22]
                exclude:
                  - os: macos-latest
                    node: 18
            steps:
              - uses: actions/checkout@v4
              - uses: actions/setup-node@v4
                with:
                  node-version: ${{ matrix.node }}
              - run: npm ci
              - run: npm test

          build:
            needs: lint
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - run: npm ci && npm run build
              - uses: actions/upload-artifact@v4
                with:
                  name: dist
                  path: dist

          deploy:
            needs: [test, build]
            if: github.ref == 'refs/heads/main'
            runs-on: ubuntu-latest
            environment: production
            steps:
              - uses: actions/download-artifact@v4
              - name: Deploy to production
                run: ./scripts/deploy.sh
        """
}

// MARK: - Model

struct Workflow {
    struct Trigger { let event: String; let detail: String? }
    struct Matrix {
        let axes: [String]
        /// Each axis's values as text, for showing `${{ matrix.os }}` as the runners it stands for.
        var values: [String: [String]] = [:]
        /// nil when the matrix is computed at run time (`${{ fromJSON(…) }}`).
        let count: Int?
    }
    struct Job {
        let id: String
        let name: String?
        let runsOn: String?
        let uses: String?
        let needs: [String]
        let condition: String?
        let environment: String?
        let matrix: Matrix?
        let steps: [String]
        let services: [String]
        let container: String?
        let timeout: String?
        let outputs: [String]
        var stage = 0
        var title: String { name ?? id }
    }

    var name: String?
    var triggers: [Trigger] = []
    var jobs: [Job] = []
    var warnings: [String] = []
    var stageCount: Int { (jobs.map(\.stage).max() ?? -1) + 1 }

    static func parse(_ text: String) throws -> Workflow {
        let docs = try YAMLBridge.parse(text)
        guard let root = docs.first(where: { $0.objectValue != nil }), root.objectValue != nil else {
            throw ToolError("Not a workflow: expected a YAML mapping with `on:` and `jobs:`")
        }
        guard let jobsValue = root["jobs"]?.objectValue, !jobsValue.isEmpty else {
            throw ToolError("No jobs found", hint: "A workflow needs a `jobs:` mapping, e.g. jobs: { build: { runs-on: ubuntu-latest, steps: [...] } }")
        }
        var wf = Workflow()
        wf.name = root["name"].flatMap(Self.scalar)
        // YAML 1.1 reads a bare `on` as true; YAMLBridge keeps it as the string "on", but accept both spellings.
        wf.triggers = Self.triggers(root["on"] ?? root["true"])
        if wf.triggers.isEmpty { wf.warnings.append("No `on:` triggers: this workflow never runs") }

        for (id, value) in jobsValue {
            let needs: [String]
            switch value["needs"] {
            case .string(let s)?: needs = [s]
            case .array(let a)?: needs = a.compactMap(Self.scalar)
            default: needs = []
            }
            let runsOn: String?
            switch value["runs-on"] {
            case .array(let a)?: runsOn = a.compactMap(Self.scalar).joined(separator: ", ")
            case .object(let o)?: runsOn = o.map { "\($0.key): \(Self.scalar($0.value) ?? "…")" }.joined(separator: ", ")
            case let v?: runsOn = Self.scalar(v)
            case nil: runsOn = nil
            }
            let steps = (value["steps"]?.arrayValue ?? []).enumerated().map { i, step -> String in
                if let name = step["name"].flatMap(Self.scalar) { return name }
                if let uses = step["uses"].flatMap(Self.scalar) { return uses }
                if let run = step["run"].flatMap(Self.scalar) {
                    let first = run.split(separator: "\n").first.map(String.init) ?? run
                    return "run: " + first + (run.contains("\n") ? " …" : "")
                }
                return "step \(i + 1)"
            }
            let matrix = Self.matrix(value["strategy"]?["matrix"])
            // `runs-on: ${{ matrix.os }}` means "each of these runners".
            var runner = runsOn
            if let r = runsOn, let m = r.wholeMatch(of: /\$\{\{\s*matrix\.([\w-]+)\s*\}\}/), let values = matrix?.values[String(m.1)], !values.isEmpty {
                runner = values.joined(separator: ", ")
            }
            let environment: String? = value["environment"].flatMap { $0["name"].flatMap(Self.scalar) ?? Self.scalar($0) }
            let services = value["services"]?.objectValue?.map { "\($0.key) (\($0.value["image"].flatMap(Self.scalar) ?? "?"))" } ?? []
            let container = value["container"].flatMap { $0["image"].flatMap(Self.scalar) ?? Self.scalar($0) }
            let job = Job(id: id, name: value["name"].flatMap(Self.scalar), runsOn: runner, uses: value["uses"].flatMap(Self.scalar),
                          needs: needs, condition: value["if"].flatMap(Self.scalar), environment: environment,
                          matrix: matrix, steps: steps, services: services, container: container,
                          timeout: value["timeout-minutes"].flatMap(Self.scalar), outputs: value["outputs"]?.objectValue?.map(\.key) ?? [])
            if job.runsOn == nil, job.uses == nil { wf.warnings.append("Job \(id) has neither `runs-on:` nor `uses:`") }
            wf.jobs.append(job)
        }

        // Stages: a job runs one stage after the last job it needs. Unknown names and cycles are reported, not fatal.
        let ids = Set(wf.jobs.map(\.id))
        for job in wf.jobs { for n in job.needs where !ids.contains(n) { wf.warnings.append("Job \(job.id) needs \"\(n)\", which is not a job in this workflow") } }
        let byID = Dictionary(uniqueKeysWithValues: wf.jobs.map { ($0.id, $0) })
        var stage: [String: Int] = [:]
        var visiting = Set<String>()
        var cycleReported = false
        func depth(_ id: String) -> Int {
            if let s = stage[id] { return s }
            if visiting.contains(id) {
                if !cycleReported { wf.warnings.append("The jobs' `needs:` form a cycle through \(id): GitHub will refuse to run this workflow"); cycleReported = true }
                return 0
            }
            visiting.insert(id)
            let s = (byID[id]?.needs.filter(ids.contains).map { depth($0) + 1 }.max()) ?? 0
            visiting.remove(id)
            stage[id] = s
            return s
        }
        for i in wf.jobs.indices { wf.jobs[i].stage = depth(wf.jobs[i].id) }
        return wf
    }

    // MARK: Pieces

    static func scalar(_ v: JSONValue) -> String? {
        switch v {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    static func triggers(_ value: JSONValue?) -> [Trigger] {
        guard let value else { return [] }
        switch value {
        case .string(let s): return [Trigger(event: s, detail: nil)]
        case .array(let a): return a.compactMap(scalar).map { Trigger(event: $0, detail: nil) }
        case .object(let o):
            return o.map { event, config in Trigger(event: event, detail: triggerDetail(event, config)) }
        default: return []
        }
    }

    static func triggerDetail(_ event: String, _ config: JSONValue) -> String? {
        if event == "schedule" {
            let crons = (config.arrayValue ?? []).compactMap { $0["cron"].flatMap(scalar) }
            return crons.map { cron in
                let words = (try? CronExpression.parse(cron, syntax: "standard"))?.description
                return words.map { "\($0) (\(cron), UTC)" } ?? cron
            }.joined(separator: "; ")
        }
        var parts: [String] = []
        for key in ["branches", "branches-ignore", "tags", "tags-ignore", "paths", "paths-ignore", "types", "workflows"] {
            let values: [String]
            switch config[key] {
            case .array(let a)?: values = a.compactMap(scalar)
            case let v?: values = scalar(v).map { [$0] } ?? []
            case nil: values = []
            }
            if !values.isEmpty { parts.append("\(key): \(values.joined(separator: ", "))") }
        }
        if let inputs = config["inputs"]?.objectValue, !inputs.isEmpty { parts.append("inputs: " + inputs.map(\.key).joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The number of jobs a matrix starts, following GitHub's rules for `include` and `exclude`.
    static func matrix(_ value: JSONValue?) -> Matrix? {
        guard let value else { return nil }
        guard let o = value.objectValue else { return Matrix(axes: [], count: nil) }   // an expression
        var axes: [(String, [JSONValue])] = []
        var shown: [String: [String]] = [:]
        var dynamic = false
        for (k, v) in o where k != "include" && k != "exclude" {
            if let a = v.arrayValue { axes.append((k, a)) } else { dynamic = true }
        }
        let names = axes.map(\.0)
        for (k, v) in axes { shown[k] = v.compactMap(scalar) }
        if dynamic { return Matrix(axes: names, values: shown, count: nil) }
        // Every combination of the axes (capped: GitHub itself stops at 256 jobs).
        var combos: [[String: JSONValue]] = axes.isEmpty ? [] : [[:]]
        for (k, values) in axes {
            combos = combos.flatMap { c in values.map { v in c.merging([k: v]) { $1 } } }
            if combos.count > 10_000 { return Matrix(axes: names, values: shown, count: nil) }
        }
        func matches(_ combo: [String: JSONValue], _ rule: [(key: String, value: JSONValue)]) -> Bool {
            rule.allSatisfy { combo[$0.key] == $0.value }
        }
        for rule in o.first(where: { $0.key == "exclude" })?.value.arrayValue ?? [] {
            guard let r = rule.objectValue else { continue }
            combos.removeAll { matches($0, r) }
        }
        var count = combos.count
        let axisNames = Set(names)
        for rule in o.first(where: { $0.key == "include" })?.value.arrayValue ?? [] {
            guard let r = rule.objectValue else { continue }
            // Added to every combination it does not contradict; a new combination when it fits none.
            let fitsOne = combos.contains { combo in r.allSatisfy { !axisNames.contains($0.key) || combo[$0.key] == $0.value } }
            if !fitsOne { count += 1 }
        }
        return Matrix(axes: names, values: shown, count: count)
    }

    // MARK: Output

    func outline() -> String {
        var lines: [String] = []
        lines.append(name ?? "Workflow")
        if !triggers.isEmpty {
            lines.append("on: " + triggers.map { t in t.detail.map { "\(t.event) (\($0))" } ?? t.event }.joined(separator: ", "))
        }
        let width = min(jobs.map(\.id.count).max() ?? 0, 28)
        for s in 0..<stageCount {
            lines.append("")
            lines.append("Stage \(s + 1)")
            for job in jobs where job.stage == s {
                var facts = [job.uses.map { "calls \($0)" } ?? job.runsOn ?? "no runner"]
                if let m = job.matrix { facts.append(m.count.map { "matrix ×\($0)" } ?? "matrix (computed)") }
                if !job.steps.isEmpty { facts.append(job.steps.count == 1 ? "1 step" : "\(job.steps.count) steps") }
                if let e = job.environment { facts.append("environment \(e)") }
                var line = "  " + job.id.padding(toLength: max(width, job.id.count), withPad: " ", startingAt: 0)
                if !job.needs.isEmpty { line += "  ← " + job.needs.joined(separator: ", ") }
                line += "   " + facts.joined(separator: " · ")
                lines.append(line)
                if let c = job.condition { lines.append("  " + String(repeating: " ", count: max(width, job.id.count)) + "   if: \(c)") }
            }
        }
        return lines.joined(separator: "\n")
    }

    func diagram(stepsOnCards: Bool) -> Diagram {
        var nodes: [Diagram.Node] = []
        var edges: [Diagram.Edge] = []
        let triggerID = "on"
        if !triggers.isEmpty {
            nodes.append(Diagram.Node(
                id: triggerID, title: triggers.count == 1 ? triggers[0].event : "\(triggers.count) triggers", badge: "on",
                symbol: "bolt.fill", tone: .trigger,
                lines: triggers.count == 1 ? (triggers[0].detail.map { [$0] } ?? []) : triggers.map { t in t.detail.map { "\(t.event): \($0)" } ?? t.event },
                details: triggers.map { Diagram.Detail($0.event, $0.detail ?? "any") }, layer: 0))
        }
        let ids = Set(jobs.map(\.id))
        for job in jobs {
            var details = [Diagram.Detail("Job id", job.id)]
            if let r = job.runsOn { details.append(.init("Runs on", r)) }
            if let u = job.uses { details.append(.init("Calls", u)) }
            if !job.needs.isEmpty { details.append(.init("Needs", job.needs.joined(separator: ", "))) }
            if let c = job.condition { details.append(.init("Runs if", c)) }
            if let m = job.matrix {
                details.append(.init("Matrix", (m.axes.isEmpty ? "" : m.axes.joined(separator: " × ") + " → ") + (m.count.map { "\($0) jobs" } ?? "computed at run time")))
            }
            if let e = job.environment { details.append(.init("Environment", e)) }
            if let c = job.container { details.append(.init("Container", c)) }
            if !job.services.isEmpty { details.append(.init("Services", job.services.joined(separator: ", "))) }
            if let t = job.timeout { details.append(.init("Timeout", "\(t) min")) }
            if !job.outputs.isEmpty { details.append(.init("Outputs", job.outputs.joined(separator: ", "))) }
            for (i, step) in job.steps.enumerated() { details.append(.init("Step \(i + 1)", step)) }
            nodes.append(Diagram.Node(
                id: "job:" + job.id, title: job.title,
                subtitle: job.uses.map { "calls " + ($0.split(separator: "/").last.map(String.init) ?? $0) } ?? job.runsOn,
                badge: job.matrix.map { m in m.count.map { "matrix ×\($0)" } ?? "matrix" } ?? (job.environment.map { "env: \($0)" }),
                symbol: job.uses != nil ? "arrow.triangle.branch" : "gearshape.2", tone: .job,
                lines: stepsOnCards ? job.steps : [], details: details, layer: job.stage + (triggers.isEmpty ? 0 : 1)))
            let real = job.needs.filter(ids.contains)
            if real.isEmpty, !triggers.isEmpty { edges.append(Diagram.Edge(triggerID, "job:" + job.id)) }
            for n in real { edges.append(Diagram.Edge("job:" + n, "job:" + job.id, label: nil, dashed: job.condition != nil)) }
        }
        return Diagram(title: name ?? "Workflow", nodes: nodes, edges: edges)
    }
}
