import XCTest
@testable import BitlatheCore
@testable import BitlatheTools

final class VisualizerTests: XCTestCase {

    func graph(_ out: ToolOutput) throws -> Diagram {
        try XCTUnwrap(Diagram.decode(try XCTUnwrap(out.facets.first { $0.title == Diagram.facetTitle }?.payload.text)))
    }

    func gha(_ yaml: String) async throws -> ToolOutput {
        try await GitHubActionsTool().run(ToolInput(text: yaml), options: .init())
    }

    func k8s(_ yaml: String, config: Bool = true) async throws -> ToolOutput {
        var o = KubernetesTool.Options()
        o.config = config
        return try await KubernetesTool().run(ToolInput(text: yaml), options: o)
    }

    // MARK: GitHub Actions

    func testWorkflowStagesFollowNeeds() async throws {
        let out = try await gha(GitHubActionsTool.sampleWorkflow)
        let d = try graph(out)
        XCTAssertEqual(d.columns(), [["on"], ["job:lint"], ["job:test", "job:build"], ["job:deploy"]])
        XCTAssertTrue(d.edges.contains(Diagram.Edge("on", "job:lint")))
        XCTAssertTrue(d.edges.contains { $0.from == "job:build" && $0.to == "job:deploy" && $0.dashed }, "deploy has an `if:`, so its arrows are dashed")
        XCTAssertFalse(d.edges.contains { $0.from == "on" && $0.to == "job:deploy" }, "only jobs with no needs hang off the triggers")
        XCTAssertEqual(out.metadata.first { $0.label == "Stages" }?.value, "3")
        XCTAssertTrue(out.text.contains("deploy  ← test, build"), out.text)
        XCTAssertTrue(out.text.contains("schedule (At 03:00"), "cron schedules are explained: " + out.text)
        XCTAssertTrue(out.warnings.isEmpty, out.warnings.joined())
        // `runs-on: ${{ matrix.os }}` shows the runners it stands for; the triggers card says which branches.
        XCTAssertEqual(d.nodes.first { $0.id == "job:test" }?.subtitle, "ubuntu-latest, macos-latest")
        XCTAssertEqual(d.nodes.first?.lines.first, "push: branches: main")
    }

    func testMatrixCountsFollowGitHubRules() {
        func count(_ yaml: String) throws -> Int? {
            try Workflow.matrix(YAMLBridge.parseOne(yaml))?.count
        }
        XCTAssertEqual(try count("os: [a, b]\nnode: [18, 20, 22]"), 6)
        XCTAssertEqual(try count("os: [a, b]\nnode: [18, 20, 22]\nexclude:\n  - os: b\n    node: 18"), 5)
        // An exclude naming one axis removes every combination with that value.
        XCTAssertEqual(try count("os: [a, b]\nnode: [18, 20]\nexclude:\n  - os: b"), 2)
        // An include that adds a key to existing combinations adds no job; one that contradicts all of them adds one.
        XCTAssertEqual(try count("os: [a, b]\ninclude:\n  - os: a\n    experimental: true"), 2)
        XCTAssertEqual(try count("os: [a, b]\ninclude:\n  - os: c"), 3)
        XCTAssertEqual(try count("include:\n  - os: a\n  - os: b"), 2, "an include-only matrix is one job per entry")
        XCTAssertNil(try count("os: ${{ fromJSON(needs.setup.outputs.os) }}"), "computed at run time")
    }

    func testWorkflowProblemsAreWarningsNotFailures() async throws {
        let yaml = """
            on: push
            jobs:
              a:
                needs: b
                runs-on: ubuntu-latest
                steps: [{run: echo a}]
              b:
                needs: a
                runs-on: ubuntu-latest
                steps: [{run: echo b}]
              c:
                needs: missing
                steps: [{run: echo c}]
            """
        let out = try await gha(yaml)
        XCTAssertTrue(out.warnings.contains { $0.contains("cycle") }, out.warnings.joined(separator: "\n"))
        XCTAssertTrue(out.warnings.contains { $0.contains("\"missing\"") })
        XCTAssertTrue(out.warnings.contains { $0.contains("Job c has neither") })
        XCTAssertEqual(try graph(out).nodes.count, 4)
    }

    func testTriggerFormsAndReusableWorkflows() async throws {
        let yaml = """
            on: [push, pull_request]
            jobs:
              call:
                uses: org/repo/.github/workflows/build.yml@main
            """
        let out = try await gha(yaml)
        let d = try graph(out)
        XCTAssertEqual(d.nodes.first?.title, "2 triggers")
        XCTAssertEqual(d.nodes.last?.subtitle, "calls build.yml@main")
        do { _ = try await gha("name: nothing here"); XCTFail("a file without jobs is not a workflow") } catch {}
    }

    func testWorkflowDetection() {
        XCTAssertEqual(GitHubActionsTool.detect(GitHubActionsTool.sampleWorkflow)?.confidence ?? 0, 0.93, accuracy: 0.001)
        XCTAssertNil(GitHubActionsTool.detect("name: x\nsteps:\n  - a"))
        XCTAssertNil(GitHubActionsTool.detect(KubernetesTool.sampleManifests))
    }

    // MARK: Kubernetes

    func testManifestsAreLinkedTheWayTheClusterWould() async throws {
        let out = try await k8s(KubernetesTool.sampleManifests)
        let d = try graph(out)
        func has(_ from: String, _ to: String, _ label: String? = nil) -> Bool {
            d.edges.contains { $0.from == from && $0.to == to && (label == nil || $0.label == label) }
        }
        // One host (shown on the Ingress card), so the arrows carry just the path.
        XCTAssertTrue(has("Ingress/default/shop", "Service/default/web", "/"))
        XCTAssertTrue(has("Ingress/default/shop", "Service/default/api", "/api"))
        XCTAssertTrue(has("Service/default/web", "Deployment/default/web", "selects"))
        XCTAssertFalse(has("Service/default/web", "Deployment/default/api"), "selectors match labels, not names")
        XCTAssertTrue(has("Deployment/default/web", "ConfigMap/default/web-config", "env"))
        XCTAssertTrue(has("Deployment/default/api", "PersistentVolumeClaim/default/uploads", "mounts"))
        XCTAssertTrue(has("Deployment/default/api", "ServiceAccount/default/api", "runs as"))
        XCTAssertTrue(has("HorizontalPodAutoscaler/default/api", "Deployment/default/api", "scales 3–10"))
        // The Secret is referred to but not in the manifests: a dashed stand-in, and named in the facts.
        let secret = try XCTUnwrap(d.nodes.first { $0.id == "Secret/default/db-credentials" })
        XCTAssertTrue(secret.external)
        XCTAssertEqual(out.metadata.first { $0.label == "Not defined here" }?.value, "Secret db-credentials")
        XCTAssertTrue(out.metadata.first { $0.label == "Images" }?.value.contains("shop-api:2.1.3") == true)
        // Traffic reads left to right.
        let cols = d.columns()
        func col(_ id: String) -> Int? { cols.firstIndex { $0.contains(id) } }
        XCTAssertLessThan(try XCTUnwrap(col("Ingress/default/shop")), try XCTUnwrap(col("Service/default/web")))
        XCTAssertLessThan(try XCTUnwrap(col("Service/default/web")), try XCTUnwrap(col("Deployment/default/web")))
        XCTAssertLessThan(try XCTUnwrap(col("Deployment/default/web")), try XCTUnwrap(col("ConfigMap/default/web-config")))
        XCTAssertTrue(out.warnings.isEmpty, out.warnings.joined())
    }

    func testSelectorsRespectNamespacesAndReportMisses() async throws {
        let yaml = """
            apiVersion: v1
            kind: Service
            metadata: {name: web, namespace: prod}
            spec: {selector: {app: web}}
            ---
            apiVersion: apps/v1
            kind: Deployment
            metadata: {name: web, namespace: staging}
            spec:
              template:
                metadata: {labels: {app: web}}
                spec: {containers: [{name: web, image: nginx}]}
            """
        let out = try await k8s(yaml)
        XCTAssertTrue(try graph(out).edges.isEmpty, "a Service only selects pods in its own namespace")
        XCTAssertTrue(out.warnings.contains { $0.contains("Service web selects app=web") }, out.warnings.joined())
        XCTAssertEqual(out.metadata.first { $0.label == "Namespaces" }?.value, "prod, staging")
    }

    func testSecretValuesAreNeverShown() async throws {
        let yaml = """
            apiVersion: v1
            kind: Secret
            metadata: {name: db}
            type: Opaque
            stringData:
              password: hunter2-very-secret
            """
        let out = try await k8s(yaml)
        let everything = out.text + (out.facets.compactMap(\.payload.text).joined()) + out.metadata.map(\.value).joined()
        XCTAssertFalse(everything.contains("hunter2"), "only key names are listed")
        XCTAssertTrue(try graph(out).nodes[0].details.contains { $0.value.hasPrefix("password") })
    }

    func testListsRBACAndHidingConfig() async throws {
        let yaml = """
            apiVersion: v1
            kind: List
            items:
              - apiVersion: rbac.authorization.k8s.io/v1
                kind: RoleBinding
                metadata: {name: read, namespace: ops}
                roleRef: {kind: ClusterRole, name: view, apiGroup: rbac.authorization.k8s.io}
                subjects: [{kind: ServiceAccount, name: bot, namespace: ops}]
              - apiVersion: v1
                kind: ConfigMap
                metadata: {name: settings, namespace: ops}
                data: {a: "1"}
            """
        let full = try await k8s(yaml)
        let d = try graph(full)
        XCTAssertTrue(d.edges.contains { $0.from == "RoleBinding/ops/read" && $0.to == "ClusterRole//view" && $0.label == "grants" })
        XCTAssertTrue(d.edges.contains { $0.from == "ServiceAccount/ops/bot" && $0.to == "RoleBinding/ops/read" })
        XCTAssertTrue(d.nodes.contains { $0.id == "ConfigMap/ops/settings" })
        let hidden = try await k8s(yaml, config: false)
        XCTAssertFalse(try graph(hidden).nodes.contains { $0.id == "ConfigMap/ops/settings" })
    }

    func testManifestDetection() {
        XCTAssertEqual(KubernetesTool.detect(KubernetesTool.sampleManifests)?.reason, "Kubernetes manifests (9)")
        XCTAssertNil(KubernetesTool.detect("apiVersion: 2\nname: x"))
        XCTAssertNil(KubernetesTool.detect(GitHubActionsTool.sampleWorkflow))
    }

    func testTheSmartBoxPicksTheVisualisers() throws {
        let tools = ToolCatalog.all
        XCTAssertEqual(SmartBox.analyse(GitHubActionsTool.sampleWorkflow, tools: tools)?.actions.first?.tool.id, "gha.visualize")
        XCTAssertEqual(SmartBox.analyse(KubernetesTool.sampleManifests, tools: tools)?.actions.first?.tool.id, "k8s.visualize")
        XCTAssertTrue(SmartBox.analyse(KubernetesTool.sampleManifests, tools: tools)?.actions.contains { $0.tool.id == "yaml.format" } == true,
                      "the YAML formatter stays one key away")
    }

    // MARK: Diagram

    func testLayoutToleratesCyclesAndOrdersToCutCrossings() {
        let n = { (id: String) in Diagram.Node(id: id, title: id, symbol: "circle", tone: .other) }
        let cyclic = Diagram(title: "", nodes: ["a", "b", "c"].map(n), edges: [.init("a", "b"), .init("b", "c"), .init("c", "a")])
        XCTAssertEqual(cyclic.columns().flatMap { $0 }.sorted(), ["a", "b", "c"])
        // x → q and y → p: q goes level with x and p with y, so the arrows do not cross.
        let crossing = Diagram(title: "", nodes: ["x", "y", "p", "q"].map(n), edges: [.init("x", "q"), .init("y", "p")])
        XCTAssertEqual(crossing.columns(), [["x", "y"], ["q", "p"]])
        // Edges to nodes that do not exist, self-loops and duplicates are dropped.
        let messy = Diagram(title: "", nodes: ["a"].map(n), edges: [.init("a", "zz"), .init("a", "a"), .init("a", "a")])
        XCTAssertTrue(messy.edges.isEmpty)
    }

    func testMermaidExport() {
        let d = Diagram(title: "t", nodes: [
            Diagram.Node(id: "on", title: "push", badge: "on", symbol: "bolt", tone: .trigger),
            Diagram.Node(id: "job:a \"x\"", title: "Build \"it\"", symbol: "gear", tone: .job, external: true),
        ], edges: [.init("on", "job:a \"x\"", label: "starts", dashed: true)])
        let m = d.mermaid()
        XCTAssertTrue(m.hasPrefix("flowchart LR"))
        XCTAssertTrue(m.contains("n0_on([\""), "triggers are rounded")
        XCTAssertTrue(m.contains("Build #quot;it#quot;"), "quotes are escaped")
        XCTAssertTrue(m.contains("-.->|starts|"))
        XCTAssertTrue(m.contains("classDef external"))
    }
}
