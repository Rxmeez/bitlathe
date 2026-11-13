import Foundation
import BitlatheCore

/// Draws Kubernetes manifests as a graph of how the resources connect: traffic from an Ingress or Gateway to a Service,
/// the workloads a Service selects, and the ConfigMaps, Secrets, volumes and service accounts those workloads use.
/// Links are worked out the way the cluster would: label selectors, `backend.service`, `envFrom`, `volumes`, `roleRef`.
/// Secret values are never read; only key names are listed.
public struct KubernetesTool: DevTool {
    public static let id = "k8s.visualize"
    public static let name = "Kubernetes Visualizer"
    public static let summary = "See manifests as a graph: Ingress → Service → workloads → ConfigMaps, Secrets, volumes and accounts"
    public static let category = ToolCategory.inspect
    public static let symbol = "helm"
    public static let keywords = ["kubernetes", "k8s", "kubectl", "manifest", "yaml", "deployment", "service", "ingress", "helm", "kustomize", "graph", "visualize", "visualise", "diagram", "configmap", "secret"]
    public static let samples = [ToolSample("Web app", sampleManifests)]
    public static let optionFields: [OptionField] = [
        .toggle("config", "ConfigMaps & Secrets", default: true, help: "Show the configuration a workload reads; hide it to see just the traffic path"),
        .toggle("rbac", "Accounts & RBAC", default: true, help: "Show service accounts, role bindings and roles"),
    ]
    public struct Options: ToolOptions {
        public var config = true
        public var rbac = true
        public init() {}
    }
    public init() {}

    public func run(_ input: ToolInput, options: Options) async throws -> ToolOutput {
        let text = input.text
        guard !text.trimmed().isEmpty else { throw ToolError.emptyInput }
        let graph = try KubeGraph.build(text)
        let diagram = graph.diagram(showConfig: options.config, showRBAC: options.rbac)
        let kinds = Dictionary(grouping: graph.resources, by: \.kind).map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var rows = [MetaRow("Resources", "\(graph.resources.count)"),
                    MetaRow("Kinds", kinds.map { "\($0.0) \($0.1)" }.joined(separator: " · "))]
        if !graph.namespaces.isEmpty { rows.append(MetaRow("Namespaces", graph.namespaces.joined(separator: ", "))) }
        rows.append(MetaRow("Links", "\(graph.links.count)"))
        let images = Array(Set(graph.resources.flatMap(\.images))).sorted()
        if !images.isEmpty { rows.append(MetaRow("Images", images.joined(separator: ", "), style: .mono)) }
        if !graph.external.isEmpty {
            rows.append(MetaRow("Not defined here", graph.external.map { "\($0.kind) \($0.name)" }.joined(separator: ", "), style: .warning))
        }
        return ToolOutput(text: graph.outline(), language: .plain,
                          facets: [OutputFacet("Mermaid", text: diagram.mermaid()), OutputFacet(Diagram.facetTitle, text: diagram.json(), language: .json)],
                          metadata: rows, warnings: graph.warnings)
    }

    public static func detect(_ s: String) -> DetectionScore? {
        guard s.contains("apiVersion:"), s.contains("kind:"),
              s.range(of: #"(?m)^\s*-?\s*apiVersion:\s*\S+"#, options: .regularExpression) != nil,
              s.range(of: #"(?m)^\s*kind:\s*[A-Z]\w+"#, options: .regularExpression) != nil else { return nil }
        let count = s.components(separatedBy: "\nkind:").count - (s.hasPrefix("kind:") ? 0 : 1)
        return DetectionScore(0.93, count > 1 ? "Kubernetes manifests (\(count))" : "Kubernetes manifest")
    }

    static let sampleManifests = """
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: shop
        spec:
          ingressClassName: nginx
          rules:
            - host: shop.example.com
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: web
                        port:
                          number: 80
                  - path: /api
                    pathType: Prefix
                    backend:
                      service:
                        name: api
                        port:
                          number: 8080
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: web
        spec:
          selector:
            app: web
          ports:
            - port: 80
              targetPort: 3000
        ---
        apiVersion: v1
        kind: Service
        metadata:
          name: api
        spec:
          selector:
            app: api
          ports:
            - port: 8080
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: web
        spec:
          replicas: 2
          selector:
            matchLabels:
              app: web
          template:
            metadata:
              labels:
                app: web
            spec:
              containers:
                - name: web
                  image: ghcr.io/example/shop-web:1.4.0
                  envFrom:
                    - configMapRef:
                        name: web-config
        ---
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: api
        spec:
          replicas: 3
          selector:
            matchLabels:
              app: api
          template:
            metadata:
              labels:
                app: api
            spec:
              serviceAccountName: api
              containers:
                - name: api
                  image: ghcr.io/example/shop-api:2.1.3
                  env:
                    - name: DATABASE_URL
                      valueFrom:
                        secretKeyRef:
                          name: db-credentials
                          key: url
                  volumeMounts:
                    - name: uploads
                      mountPath: /data
              volumes:
                - name: uploads
                  persistentVolumeClaim:
                    claimName: uploads
        ---
        apiVersion: autoscaling/v2
        kind: HorizontalPodAutoscaler
        metadata:
          name: api
        spec:
          scaleTargetRef:
            apiVersion: apps/v1
            kind: Deployment
            name: api
          minReplicas: 3
          maxReplicas: 10
        ---
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: web-config
        data:
          API_URL: http://api:8080
          FEATURE_FLAGS: checkout,wishlist
        ---
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: uploads
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 10Gi
        ---
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: api
        """
}

// MARK: - Model

struct KubeGraph {
    struct Resource {
        let kind: String
        let name: String
        /// nil for cluster-scoped kinds.
        let namespace: String?
        let labels: [String: String]
        let raw: JSONValue
        var id: String { KubeGraph.id(kind, namespace, name) }
        var podTemplate: JSONValue? { KubeGraph.podTemplate(kind: kind, raw) }
        var images: [String] {
            guard let spec = podTemplate?["spec"] else { return [] }
            return KubeGraph.containers(spec).compactMap { $0["image"]?.stringValue }
        }
    }
    struct Link: Hashable { let from: String; let to: String; let label: String }
    struct Ref: Hashable { let kind: String; let name: String; let namespace: String? }

    var resources: [Resource] = []
    var links: [Link] = []
    var external: [Ref] = []
    var warnings: [String] = []
    var namespaces: [String] = []

    static let clusterScoped: Set<String> = ["Namespace", "Node", "PersistentVolume", "StorageClass", "ClusterRole", "ClusterRoleBinding",
                                             "IngressClass", "GatewayClass", "CustomResourceDefinition", "PriorityClass",
                                             "MutatingWebhookConfiguration", "ValidatingWebhookConfiguration", "APIService", "RuntimeClass"]
    static let workloadKinds: Set<String> = ["Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "ReplicationController", "Job", "CronJob", "Pod",
                                             "Rollout", "DeploymentConfig"]
    static let routeKinds: Set<String> = ["HTTPRoute", "GRPCRoute", "TCPRoute", "TLSRoute", "UDPRoute"]

    static func id(_ kind: String, _ namespace: String?, _ name: String) -> String { "\(kind)/\(namespace ?? "")/\(name)" }

    static func build(_ text: String) throws -> KubeGraph {
        var g = KubeGraph()
        var docs = try YAMLBridge.parse(text)
        // `kubectl get -o yaml` wraps everything in a List.
        docs = docs.flatMap { d -> [JSONValue] in
            if d["kind"]?.stringValue?.hasSuffix("List") == true, let items = d["items"]?.arrayValue { return items }
            return [d]
        }
        var unnamed = 0
        for d in docs where d.objectValue != nil {
            guard let kind = d["kind"]?.stringValue else { continue }
            let meta = d["metadata"]
            guard let name = meta?["name"]?.stringValue ?? meta?["generateName"]?.stringValue else { unnamed += 1; continue }
            let ns = clusterScoped.contains(kind) ? nil : (meta?["namespace"]?.stringValue ?? "default")
            let labels = Dictionary((meta?["labels"]?.objectValue ?? []).compactMap { k, v in Workflow.scalar(v).map { (k, $0) } }) { a, _ in a }
            g.resources.append(Resource(kind: kind, name: name, namespace: ns, labels: labels, raw: d))
        }
        guard !g.resources.isEmpty else {
            throw ToolError("No Kubernetes resources found", hint: "Each document needs apiVersion, kind and metadata.name")
        }
        if unnamed > 0 { g.warnings.append(unnamed == 1 ? "1 document has no metadata.name and was skipped" : "\(unnamed) documents have no metadata.name and were skipped") }
        g.namespaces = Array(Set(g.resources.compactMap(\.namespace) + g.resources.filter { $0.kind == "Namespace" }.map(\.name))).sorted()
        g.connect()
        return g
    }

    // MARK: Links

    private func find(_ kind: String, _ name: String, _ ns: String?) -> Resource? {
        let namespace = Self.clusterScoped.contains(kind) ? nil : ns
        return resources.first { $0.kind == kind && $0.name == name && $0.namespace == namespace }
    }

    /// Links `from` to the named resource, or to a dashed stand-in when it is not in the input.
    private mutating func link(_ from: Resource, _ kind: String, _ name: String, _ label: String, namespace: String? = nil) {
        let ns = Self.clusterScoped.contains(kind) ? nil : (namespace ?? from.namespace)
        let to = Self.id(kind, ns, name)
        if find(kind, name, ns) == nil {
            let ref = Ref(kind: kind, name: name, namespace: ns)
            if !external.contains(ref) { external.append(ref) }
        }
        links.append(Link(from: from.id, to: to, label: label))
    }

    private func selected(by selector: [String: String], in ns: String?) -> [Resource] {
        guard !selector.isEmpty else { return [] }
        return resources.filter { r in
            guard Self.workloadKinds.contains(r.kind), r.namespace == ns else { return false }
            let labels = Self.podLabels(r)
            return selector.allSatisfy { labels[$0.key] == $0.value }
        }
    }

    private mutating func connect() {
        for r in resources {
            let spec = r.raw["spec"]
            switch r.kind {
            case "Service":
                let selector = Self.stringMap(spec?["selector"])
                let picked = selected(by: selector, in: r.namespace)
                for w in picked { links.append(Link(from: r.id, to: w.id, label: "selects")) }
                if !selector.isEmpty, picked.isEmpty, resources.contains(where: { Self.workloadKinds.contains($0.kind) }) {
                    warnings.append("Service \(r.name) selects \(Self.describe(selector)), but no workload here has those labels")
                }
            case "Ingress":
                for (service, label) in Self.ingressBackends(spec) { link(r, "Service", service, label) }
            case "Gateway":
                break
            case _ where Self.routeKinds.contains(r.kind):
                for parent in spec?["parentRefs"]?.arrayValue ?? [] {
                    guard let name = parent["name"]?.stringValue else { continue }
                    // Traffic flows gateway → route, so the arrow starts at the gateway.
                    let gw = Self.id(parent["kind"]?.stringValue ?? "Gateway", parent["namespace"]?.stringValue ?? r.namespace, name)
                    if find(parent["kind"]?.stringValue ?? "Gateway", name, parent["namespace"]?.stringValue ?? r.namespace) == nil {
                        let ref = Ref(kind: "Gateway", name: name, namespace: parent["namespace"]?.stringValue ?? r.namespace)
                        if !external.contains(ref) { external.append(ref) }
                    }
                    links.append(Link(from: gw, to: r.id, label: "routes"))
                }
                for rule in spec?["rules"]?.arrayValue ?? [] {
                    let path = rule["matches"]?[0]?["path"]?["value"]?.stringValue
                    for b in rule["backendRefs"]?.arrayValue ?? [] {
                        guard let name = b["name"]?.stringValue else { continue }
                        link(r, b["kind"]?.stringValue ?? "Service", name, path ?? "", namespace: b["namespace"]?.stringValue)
                    }
                }
            case "HorizontalPodAutoscaler", "VerticalPodAutoscaler":
                let target = spec?["scaleTargetRef"] ?? spec?["targetRef"]
                if let kind = target?["kind"]?.stringValue, let name = target?["name"]?.stringValue {
                    let range = [spec?["minReplicas"].flatMap(Workflow.scalar), spec?["maxReplicas"].flatMap(Workflow.scalar)].compactMap { $0 }
                    link(r, kind, name, range.count == 2 ? "scales \(range[0])–\(range[1])" : "scales")
                }
            case "PodDisruptionBudget":
                for w in selected(by: Self.stringMap(spec?["selector"]?["matchLabels"]), in: r.namespace) { links.append(Link(from: r.id, to: w.id, label: "protects")) }
            case "NetworkPolicy":
                for w in selected(by: Self.stringMap(spec?["podSelector"]?["matchLabels"]), in: r.namespace) { links.append(Link(from: r.id, to: w.id, label: "applies to")) }
            case "RoleBinding", "ClusterRoleBinding":
                if let kind = r.raw["roleRef"]?["kind"]?.stringValue, let name = r.raw["roleRef"]?["name"]?.stringValue {
                    // A RoleBinding may grant a ClusterRole, inside its own namespace.
                    link(r, kind, name, "grants")
                }
                for subject in r.raw["subjects"]?.arrayValue ?? [] where subject["kind"]?.stringValue == "ServiceAccount" {
                    guard let name = subject["name"]?.stringValue else { continue }
                    let ns = subject["namespace"]?.stringValue ?? r.namespace ?? "default"
                    let sa = Self.id("ServiceAccount", ns, name)
                    if find("ServiceAccount", name, ns) == nil {
                        let ref = Ref(kind: "ServiceAccount", name: name, namespace: ns)
                        if !external.contains(ref) { external.append(ref) }
                    }
                    links.append(Link(from: sa, to: r.id, label: "bound by"))
                }
            case "PersistentVolumeClaim":
                if let pv = spec?["volumeName"]?.stringValue { link(r, "PersistentVolume", pv, "bound to") }
                if let sc = spec?["storageClassName"]?.stringValue, find("StorageClass", sc, nil) != nil { link(r, "StorageClass", sc, "class") }
            case "CronJob", "Job":
                break
            default:
                break
            }
            if let template = r.podTemplate { podLinks(r, template) }
        }
        var seen = Set<Link>()
        links = links.filter { seen.insert($0).inserted }
    }

    /// What a workload's pods read: config, secrets, volumes, the service account and image pull secrets.
    private mutating func podLinks(_ r: Resource, _ template: JSONValue) {
        guard let spec = template["spec"] else { return }
        for c in Self.containers(spec) {
            for from in c["envFrom"]?.arrayValue ?? [] {
                if let n = from["configMapRef"]?["name"]?.stringValue { link(r, "ConfigMap", n, "env") }
                if let n = from["secretRef"]?["name"]?.stringValue { link(r, "Secret", n, "env") }
            }
            for env in c["env"]?.arrayValue ?? [] {
                if let n = env["valueFrom"]?["configMapKeyRef"]?["name"]?.stringValue { link(r, "ConfigMap", n, "env") }
                if let n = env["valueFrom"]?["secretKeyRef"]?["name"]?.stringValue { link(r, "Secret", n, "env") }
            }
        }
        for v in spec["volumes"]?.arrayValue ?? [] {
            if let n = v["configMap"]?["name"]?.stringValue { link(r, "ConfigMap", n, "volume") }
            if let n = v["secret"]?["secretName"]?.stringValue { link(r, "Secret", n, "volume") }
            if let n = v["persistentVolumeClaim"]?["claimName"]?.stringValue { link(r, "PersistentVolumeClaim", n, "mounts") }
            for s in v["projected"]?["sources"]?.arrayValue ?? [] {
                if let n = s["configMap"]?["name"]?.stringValue { link(r, "ConfigMap", n, "volume") }
                if let n = s["secret"]?["name"]?.stringValue { link(r, "Secret", n, "volume") }
            }
        }
        for s in spec["imagePullSecrets"]?.arrayValue ?? [] {
            if let n = s["name"]?.stringValue { link(r, "Secret", n, "pulls images") }
        }
        if let sa = spec["serviceAccountName"]?.stringValue ?? spec["serviceAccount"]?.stringValue, sa != "default" {
            link(r, "ServiceAccount", sa, "runs as")
        }
    }

    // MARK: Reading manifests

    static func podTemplate(kind: String, _ raw: JSONValue) -> JSONValue? {
        switch kind {
        case "Pod": return raw
        case "CronJob": return raw["spec"]?["jobTemplate"]?["spec"]?["template"]
        case _ where workloadKinds.contains(kind): return raw["spec"]?["template"]
        default: return nil
        }
    }

    static func podLabels(_ r: Resource) -> [String: String] {
        r.kind == "Pod" ? r.labels : stringMap(r.podTemplate?["metadata"]?["labels"])
    }

    static func containers(_ spec: JSONValue) -> [JSONValue] {
        (spec["initContainers"]?.arrayValue ?? []) + (spec["containers"]?.arrayValue ?? [])
    }

    static func stringMap(_ v: JSONValue?) -> [String: String] {
        Dictionary((v?.objectValue ?? []).compactMap { k, v in Workflow.scalar(v).map { (k, $0) } }) { a, _ in a }
    }

    static func describe(_ selector: [String: String]) -> String {
        selector.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// (service name, "host/path") for each backend of an Ingress, old and new field names.
    static func ingressBackends(_ spec: JSONValue?) -> [(String, String)] {
        var out: [(String, String)] = []
        func service(_ backend: JSONValue?) -> String? {
            backend?["service"]?["name"]?.stringValue ?? backend?["serviceName"]?.stringValue
        }
        if let d = service(spec?["defaultBackend"] ?? spec?["backend"]) { out.append((d, "default")) }
        let rules = spec?["rules"]?.arrayValue ?? []
        // With one host (already on the Ingress card) the path alone says which way traffic goes.
        let oneHost = Set(rules.map { $0["host"]?.stringValue ?? "*" }).count <= 1
        for rule in rules {
            let host = rule["host"]?.stringValue ?? "*"
            for p in rule["http"]?["paths"]?.arrayValue ?? [] {
                let path = p["path"]?.stringValue ?? "/"
                if let s = service(p["backend"]) { out.append((s, oneHost ? path : host + path)) }
            }
        }
        return out
    }

    // MARK: Output

    enum Column: Int { case entry = 0, route, service, workload, config, storage, binding, role, other }

    static func column(_ kind: String) -> Column {
        switch kind {
        case "Gateway": .entry
        case "Ingress": .route
        case _ where routeKinds.contains(kind): .route
        case "Service": .service
        case "HorizontalPodAutoscaler", "VerticalPodAutoscaler", "PodDisruptionBudget", "NetworkPolicy": .service
        case _ where workloadKinds.contains(kind): .workload
        case "ConfigMap", "Secret", "PersistentVolumeClaim", "ServiceAccount": .config
        case "PersistentVolume", "StorageClass": .storage
        case "RoleBinding", "ClusterRoleBinding": .binding
        case "Role", "ClusterRole": .role
        default: .other
        }
    }

    static func look(_ kind: String) -> (symbol: String, tone: Diagram.Tone) {
        switch kind {
        case "Ingress", "Gateway", "Service": ("network", .network)
        case _ where routeKinds.contains(kind): ("arrow.triangle.turn.up.right.diamond", .network)
        case "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Rollout", "DeploymentConfig", "ReplicationController": ("shippingbox", .workload)
        case "Pod": ("cube", .workload)
        case "Job": ("play.square", .workload)
        case "CronJob": ("calendar.badge.clock", .workload)
        case "ConfigMap": ("doc.text", .config)
        case "Secret": ("key.fill", .secret)
        case "PersistentVolumeClaim", "PersistentVolume", "StorageClass": ("externaldrive", .storage)
        case "ServiceAccount": ("person.crop.circle", .identity)
        case "Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding": ("person.badge.key", .identity)
        case "HorizontalPodAutoscaler", "VerticalPodAutoscaler": ("arrow.up.left.and.arrow.down.right", .policy)
        case "PodDisruptionBudget", "NetworkPolicy": ("shield.lefthalf.filled", .policy)
        default: ("square.dashed", .other)
        }
    }

    /// One line about a resource, for its card and the outline.
    func summary(_ r: Resource) -> String? {
        let spec = r.raw["spec"]
        switch r.kind {
        case "Service":
            if let ext = spec?["externalName"]?.stringValue { return "ExternalName → \(ext)" }
            let ports = (spec?["ports"]?.arrayValue ?? []).compactMap { p -> String? in
                guard let port = p["port"].flatMap(Workflow.scalar) else { return nil }
                let target = p["targetPort"].flatMap(Workflow.scalar)
                return target.map { $0 == port ? port : "\(port)→\($0)" } ?? port
            }
            return ([spec?["type"]?.stringValue ?? "ClusterIP"] + (ports.isEmpty ? [] : [ports.joined(separator: ", ")])).joined(separator: " · ")
        case "Ingress":
            let hosts = Array(Set((spec?["rules"]?.arrayValue ?? []).compactMap { $0["host"]?.stringValue })).sorted()
            let tls = spec?["tls"]?.arrayValue?.isEmpty == false
            return [hosts.joined(separator: ", "), tls ? "TLS" : nil, spec?["ingressClassName"]?.stringValue].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "Deployment", "StatefulSet", "ReplicaSet", "Rollout":
            return spec?["replicas"].flatMap(Workflow.scalar).map { $0 == "1" ? "1 replica" : "\($0) replicas" } ?? "1 replica"
        case "DaemonSet": return "one per node"
        case "CronJob":
            guard let schedule = spec?["schedule"]?.stringValue else { return nil }
            return (try? CronExpression.parse(schedule, syntax: "standard"))?.description ?? schedule
        case "ConfigMap":
            let keys = (r.raw["data"]?.objectValue ?? []).count + (r.raw["binaryData"]?.objectValue ?? []).count
            return keys == 1 ? "1 key" : "\(keys) keys"
        case "Secret":
            let keys = (r.raw["data"]?.objectValue ?? []).count + (r.raw["stringData"]?.objectValue ?? []).count
            return [r.raw["type"]?.stringValue ?? "Opaque", keys == 1 ? "1 key" : "\(keys) keys"].joined(separator: " · ")
        case "PersistentVolumeClaim":
            return [spec?["resources"]?["requests"]?["storage"].flatMap(Workflow.scalar),
                    (spec?["accessModes"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: ", ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case "Gateway":
            return spec?["gatewayClassName"]?.stringValue
        default:
            return nil
        }
    }

    func details(_ r: Resource) -> [Diagram.Detail] {
        var d = [Diagram.Detail("Kind", r.kind), Diagram.Detail("Name", r.name)]
        if let ns = r.namespace { d.append(.init("Namespace", ns)) }
        if let api = r.raw["apiVersion"]?.stringValue { d.append(.init("API version", api)) }
        if !r.labels.isEmpty { d.append(.init("Labels", Self.describe(r.labels))) }
        if let s = summary(r), !s.isEmpty { d.append(.init("Summary", s)) }
        let spec = r.raw["spec"]
        switch r.kind {
        case "Service":
            let sel = Self.stringMap(spec?["selector"])
            if !sel.isEmpty { d.append(.init("Selector", Self.describe(sel))) }
        case "Ingress":
            for (svc, route) in Self.ingressBackends(spec) { d.append(.init(route, "→ \(svc)")) }
        case "ConfigMap":
            let keys = (r.raw["data"]?.objectValue ?? []).map(\.key) + (r.raw["binaryData"]?.objectValue ?? []).map(\.key)
            if !keys.isEmpty { d.append(.init("Keys", keys.joined(separator: ", "))) }
        case "Secret":
            // Key names only: the values are the secret.
            let keys = (r.raw["data"]?.objectValue ?? []).map(\.key) + (r.raw["stringData"]?.objectValue ?? []).map(\.key)
            if !keys.isEmpty { d.append(.init("Keys", keys.joined(separator: ", ") + " (values not shown)")) }
        default: break
        }
        if let template = r.podTemplate, let ps = template["spec"] {
            for c in Self.containers(ps) {
                let name = c["name"]?.stringValue ?? "container"
                var facts = [c["image"]?.stringValue ?? "no image"]
                let ports = (c["ports"]?.arrayValue ?? []).compactMap { $0["containerPort"].flatMap(Workflow.scalar) }
                if !ports.isEmpty { facts.append("ports " + ports.joined(separator: ", ")) }
                if let res = c["resources"]?["limits"]?.objectValue, !res.isEmpty {
                    facts.append("limits " + res.map { "\($0.key) \(Workflow.scalar($0.value) ?? "?")" }.joined(separator: ", "))
                }
                d.append(.init("Container \(name)", facts.joined(separator: " · ")))
            }
        }
        return d
    }

    func outline() -> String {
        var lines: [String] = []
        let kindsCount = Set(resources.map(\.kind)).count
        let nsNote = namespaces.isEmpty ? "" : " in \(namespaces.count == 1 ? "namespace \(namespaces[0])" : "\(namespaces.count) namespaces (\(namespaces.joined(separator: ", ")))")"
        lines.append("\(resources.count) resource\(resources.count == 1 ? "" : "s") of \(kindsCount) kind\(kindsCount == 1 ? "" : "s")\(nsNote)")
        let byID = Dictionary(resources.map { ($0.id, $0) }) { a, _ in a }
        let ordered = resources.enumerated().sorted { a, b in
            let ca = Self.column(a.element.kind).rawValue, cb = Self.column(b.element.kind).rawValue
            return ca != cb ? ca < cb : a.offset < b.offset
        }.map(\.element)
        let multiNS = namespaces.count > 1
        func name(_ id: String) -> String {
            if let r = byID[id] { return "\(r.kind) \(r.name)" + (multiNS && r.namespace != nil ? " (\(r.namespace!))" : "") } // swiftlint:disable:this force_unwrapping
            let parts = id.split(separator: "/", omittingEmptySubsequences: false)
            return "\(parts.first ?? "") \(parts.last ?? "") — not in these manifests"
        }
        for r in ordered {
            lines.append("")
            lines.append(name(r.id) + (summary(r).map { $0.isEmpty ? "" : "   \($0)" } ?? ""))
            for l in links where l.from == r.id { lines.append("  → \(name(l.to))" + (l.label.isEmpty ? "" : "  (\(l.label))")) }
        }
        return lines.joined(separator: "\n")
    }

    func diagram(showConfig: Bool, showRBAC: Bool) -> Diagram {
        func shown(_ kind: String) -> Bool {
            if !showConfig, ["ConfigMap", "Secret"].contains(kind) { return false }
            if !showRBAC, ["ServiceAccount", "Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding"].contains(kind) { return false }
            return true
        }
        let multiNS = namespaces.count > 1
        var nodes: [Diagram.Node] = []
        for r in resources where shown(r.kind) && r.kind != "Namespace" {
            let look = Self.look(r.kind)
            let images = r.images
            nodes.append(Diagram.Node(
                id: r.id, title: r.name,
                subtitle: [summary(r), multiNS ? r.namespace.map { "ns \($0)" } : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                badge: r.kind, symbol: look.symbol, tone: look.tone,
                lines: images.map { $0.split(separator: "/").last.map(String.init) ?? $0 },
                details: details(r), layer: Self.column(r.kind).rawValue))
        }
        for ref in external where shown(ref.kind) {
            let look = Self.look(ref.kind)
            nodes.append(Diagram.Node(
                id: Self.id(ref.kind, ref.namespace, ref.name), title: ref.name, subtitle: "not in these manifests", badge: ref.kind,
                symbol: look.symbol, tone: look.tone,
                details: [.init("Kind", ref.kind), .init("Name", ref.name), .init("Note", "Referred to here but defined elsewhere (or missing from the cluster)")],
                external: true, layer: Self.column(ref.kind).rawValue))
        }
        let edges = links.map { Diagram.Edge($0.from, $0.to, label: $0.label.isEmpty ? nil : $0.label) }
        return Diagram(title: "Kubernetes", nodes: nodes, edges: edges)
    }
}
