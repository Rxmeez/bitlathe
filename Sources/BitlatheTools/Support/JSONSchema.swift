import Foundation
import BitlatheCore

/// JSON Schema validator covering the keywords people actually use (draft-07 through 2020-12 core vocabulary).
public enum JSONSchemaValidator {
    public struct Issue: Sendable, Equatable {
        public var path: String
        public var message: String
    }

    public static func validate(_ instance: JSONValue, against schema: JSONValue) -> [Issue] {
        var issues: [Issue] = []
        validate(instance, schema, path: "$", root: schema, issues: &issues, depth: 0)
        return issues
    }

    private static func validate(_ v: JSONValue, _ schema: JSONValue, path: String, root: JSONValue, issues: inout [Issue], depth: Int) {
        guard depth < 64 else { return }
        if case .bool(let b) = schema {
            if !b { issues.append(Issue(path: path, message: "Schema forbids any value here")) }
            return
        }
        guard case .object = schema else { return }

        if let ref = schema["$ref"]?.stringValue {
            if let target = resolve(ref, root: root) {
                validate(v, target, path: path, root: root, issues: &issues, depth: depth + 1)
            } else {
                issues.append(Issue(path: path, message: "Unresolvable $ref \(ref)"))
            }
        }

        // type
        if let t = schema["type"] {
            let types: [String] = t.stringValue.map { [$0] } ?? (t.arrayValue?.compactMap(\.stringValue) ?? [])
            if !types.isEmpty, !types.contains(where: { matchesType(v, $0) }) {
                issues.append(Issue(path: path, message: "Expected \(types.joined(separator: " or ")), got \(v.typeName)"))
            }
        }
        if let e = schema["enum"]?.arrayValue, !e.contains(v) {
            issues.append(Issue(path: path, message: "Value is not one of the allowed values: \(e.map { JSONSerializer.string($0, options: .minified) }.joined(separator: ", "))"))
        }
        if let c = schema["const"], c != v {
            issues.append(Issue(path: path, message: "Value must equal \(JSONSerializer.string(c, options: .minified))"))
        }

        // numbers
        if let n = v.doubleValue {
            if let m = schema["minimum"]?.doubleValue, n < m { issues.append(Issue(path: path, message: "\(fmt(n)) is less than minimum \(fmt(m))")) }
            if let m = schema["maximum"]?.doubleValue, n > m { issues.append(Issue(path: path, message: "\(fmt(n)) is greater than maximum \(fmt(m))")) }
            if let m = schema["exclusiveMinimum"]?.doubleValue, n <= m { issues.append(Issue(path: path, message: "\(fmt(n)) must be greater than \(fmt(m))")) }
            if let m = schema["exclusiveMaximum"]?.doubleValue, n >= m { issues.append(Issue(path: path, message: "\(fmt(n)) must be less than \(fmt(m))")) }
            if let m = schema["multipleOf"]?.doubleValue, m > 0 {
                let q = n / m
                if abs(q - q.rounded()) > 1e-9 { issues.append(Issue(path: path, message: "\(fmt(n)) is not a multiple of \(fmt(m))")) }
            }
        }

        // strings
        if let s = v.stringValue {
            if let m = schema["minLength"]?.intValue, s.count < m { issues.append(Issue(path: path, message: "String is shorter than \(m) characters")) }
            if let m = schema["maxLength"]?.intValue, s.count > m { issues.append(Issue(path: path, message: "String is longer than \(m) characters")) }
            if let p = schema["pattern"]?.stringValue, s.range(of: p, options: .regularExpression) == nil {
                issues.append(Issue(path: path, message: "String does not match pattern \(p)"))
            }
            if let f = schema["format"]?.stringValue, let msg = checkFormat(s, f) { issues.append(Issue(path: path, message: msg)) }
        }

        // arrays
        if let a = v.arrayValue {
            if let m = schema["minItems"]?.intValue, a.count < m { issues.append(Issue(path: path, message: "Array has fewer than \(m) items")) }
            if let m = schema["maxItems"]?.intValue, a.count > m { issues.append(Issue(path: path, message: "Array has more than \(m) items")) }
            if schema["uniqueItems"]?.boolValue == true {
                for i in a.indices where a[..<i].contains(a[i]) {
                    issues.append(Issue(path: "\(path)[\(i)]", message: "Duplicate item in array that requires unique items"))
                    break
                }
            }
            let prefix = schema["prefixItems"]?.arrayValue ?? (schema["items"]?.arrayValue ?? [])
            for (i, item) in a.enumerated() {
                if i < prefix.count {
                    validate(item, prefix[i], path: "\(path)[\(i)]", root: root, issues: &issues, depth: depth + 1)
                } else if let items = schema["items"], items.arrayValue == nil {
                    validate(item, items, path: "\(path)[\(i)]", root: root, issues: &issues, depth: depth + 1)
                } else if let add = schema["additionalItems"], !prefix.isEmpty {
                    validate(item, add, path: "\(path)[\(i)]", root: root, issues: &issues, depth: depth + 1)
                }
            }
            if let contains = schema["contains"] {
                var scratch: [Issue] = []
                let any = a.contains { item in
                    scratch.removeAll()
                    validate(item, contains, path: path, root: root, issues: &scratch, depth: depth + 1)
                    return scratch.isEmpty
                }
                if !any { issues.append(Issue(path: path, message: "Array does not contain a required item")) }
            }
        }

        // objects
        if let o = v.objectValue {
            let keys = o.map(\.key)
            if let req = schema["required"]?.arrayValue?.compactMap(\.stringValue) {
                for r in req where !keys.contains(r) { issues.append(Issue(path: path, message: "Missing required property \"\(r)\"")) }
            }
            if let m = schema["minProperties"]?.intValue, o.count < m { issues.append(Issue(path: path, message: "Object has fewer than \(m) properties")) }
            if let m = schema["maxProperties"]?.intValue, o.count > m { issues.append(Issue(path: path, message: "Object has more than \(m) properties")) }
            let props = schema["properties"]?.objectValue ?? []
            let patternProps = schema["patternProperties"]?.objectValue ?? []
            for (k, val) in o {
                var matched = false
                if let p = props.first(where: { $0.key == k }) {
                    matched = true
                    validate(val, p.value, path: childPath(path, k), root: root, issues: &issues, depth: depth + 1)
                }
                for pp in patternProps where k.range(of: pp.key, options: .regularExpression) != nil {
                    matched = true
                    validate(val, pp.value, path: childPath(path, k), root: root, issues: &issues, depth: depth + 1)
                }
                if !matched, let add = schema["additionalProperties"] {
                    if case .bool(false) = add { issues.append(Issue(path: childPath(path, k), message: "Unexpected property \"\(k)\"")) }
                    else { validate(val, add, path: childPath(path, k), root: root, issues: &issues, depth: depth + 1) }
                }
            }
            if let names = schema["propertyNames"] {
                for k in keys { validate(.string(k), names, path: childPath(path, k), root: root, issues: &issues, depth: depth + 1) }
            }
            if let deps = schema["dependentRequired"]?.objectValue ?? schema["dependencies"]?.objectValue {
                for (k, needed) in deps where keys.contains(k) {
                    for n in needed.arrayValue?.compactMap(\.stringValue) ?? [] where !keys.contains(n) {
                        issues.append(Issue(path: path, message: "Property \"\(k)\" requires \"\(n)\""))
                    }
                }
            }
        }

        // combinators
        if let all = schema["allOf"]?.arrayValue {
            for s in all { validate(v, s, path: path, root: root, issues: &issues, depth: depth + 1) }
        }
        if let any = schema["anyOf"]?.arrayValue {
            var ok = false
            for s in any {
                var scratch: [Issue] = []
                validate(v, s, path: path, root: root, issues: &scratch, depth: depth + 1)
                if scratch.isEmpty { ok = true; break }
            }
            if !ok { issues.append(Issue(path: path, message: "Value does not match any of the anyOf schemas")) }
        }
        if let one = schema["oneOf"]?.arrayValue {
            var matches = 0
            for s in one {
                var scratch: [Issue] = []
                validate(v, s, path: path, root: root, issues: &scratch, depth: depth + 1)
                if scratch.isEmpty { matches += 1 }
            }
            if matches != 1 { issues.append(Issue(path: path, message: "Value matches \(matches) of the oneOf schemas; exactly one required")) }
        }
        if let not = schema["not"] {
            var scratch: [Issue] = []
            validate(v, not, path: path, root: root, issues: &scratch, depth: depth + 1)
            if scratch.isEmpty { issues.append(Issue(path: path, message: "Value must not match the \"not\" schema")) }
        }
        if let ifS = schema["if"] {
            var scratch: [Issue] = []
            validate(v, ifS, path: path, root: root, issues: &scratch, depth: depth + 1)
            if scratch.isEmpty, let then = schema["then"] { validate(v, then, path: path, root: root, issues: &issues, depth: depth + 1) }
            if !scratch.isEmpty, let els = schema["else"] { validate(v, els, path: path, root: root, issues: &issues, depth: depth + 1) }
        }
    }

    private static func childPath(_ p: String, _ k: String) -> String {
        k.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil ? "\(p).\(k)" : "\(p)['\(k)']"
    }

    private static func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

    private static func matchesType(_ v: JSONValue, _ t: String) -> Bool {
        switch t {
        case "null": v.isNull
        case "boolean": v.boolValue != nil
        case "object": v.objectValue != nil
        case "array": v.arrayValue != nil
        case "string": v.stringValue != nil
        case "number": v.doubleValue != nil
        case "integer": v.doubleValue.map { $0 == $0.rounded() } ?? false
        default: true
        }
    }

    private static func resolve(_ ref: String, root: JSONValue) -> JSONValue? {
        guard ref.hasPrefix("#") else { return nil }
        let pointer = ref.dropFirst()
        if pointer.isEmpty { return root }
        var current = root
        for part in pointer.split(separator: "/").dropFirst(0) where !part.isEmpty {
            let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            if let next = current[key] { current = next }
            else if let i = Int(key), let next = current[i] { current = next }
            else { return nil }
        }
        return current
    }

    private static func checkFormat(_ s: String, _ f: String) -> String? {
        let ok: Bool
        switch f {
        case "email": ok = s.matches(#"^[^@\s]+@[^@\s]+\.[^@\s]+$"#)
        case "uri", "url": ok = URL(string: s)?.scheme != nil
        case "uuid": ok = UUID(uuidString: s) != nil
        case "date": ok = s.matches(#"^\d{4}-\d{2}-\d{2}$"#)
        case "date-time": ok = ISO8601DateFormatter().date(from: s) != nil || s.matches(#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#)
        case "time": ok = s.matches(#"^\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?$"#)
        case "ipv4": ok = s.matches(#"^(\d{1,3}\.){3}\d{1,3}$"#) && s.split(separator: ".").allSatisfy { (Int($0) ?? 999) <= 255 }
        case "ipv6": ok = s.contains(":") && s.matches(#"^[0-9a-fA-F:.]+$"#)
        case "hostname": ok = s.matches(#"^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"#)
        case "regex": ok = (try? NSRegularExpression(pattern: s)) != nil
        default: ok = true
        }
        return ok ? nil : "String is not a valid \(f)"
    }
}
