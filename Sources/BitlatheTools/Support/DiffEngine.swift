import Foundation
import BitlatheCore

/// Myers diff over arbitrary equatable tokens plus helpers for lines, words and characters.
public enum DiffEngine {
    public enum Op: Sendable, Equatable { case equal, insert, delete }
    public struct Edit<T: Sendable & Equatable>: Sendable, Equatable {
        public var op: Op
        public var token: T
        public var oldIndex: Int?
        public var newIndex: Int?
    }

    public static func diff<T: Equatable & Sendable & Hashable>(_ a: [T], _ b: [T]) -> [Edit<T>] {
        // Trim common prefix/suffix for speed.
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        var edits: [Edit<T>] = []
        for i in 0..<start { edits.append(Edit(op: .equal, token: a[i], oldIndex: i, newIndex: i)) }
        let midA = Array(a[start..<endA]), midB = Array(b[start..<endB])
        if !midA.isEmpty || !midB.isEmpty {
            if midA.count * midB.count > 4_000_000 {
                // Too big for O(ND) in reasonable memory; fall back to a simple LCS-free diff.
                for (i, t) in midA.enumerated() { edits.append(Edit(op: .delete, token: t, oldIndex: start + i, newIndex: nil)) }
                for (i, t) in midB.enumerated() { edits.append(Edit(op: .insert, token: t, oldIndex: nil, newIndex: start + i)) }
            } else {
                edits += myers(midA, midB, offsetA: start, offsetB: start)
            }
        }
        for i in endA..<a.count { edits.append(Edit(op: .equal, token: a[i], oldIndex: i, newIndex: i - endA + endB)) }
        return edits
    }

    private static func myers<T: Equatable & Sendable>(_ a: [T], _ b: [T], offsetA: Int, offsetB: Int) -> [Edit<T>] {
        let n = a.count, m = b.count
        let max = n + m
        var v = [Int](repeating: 0, count: 2 * max + 2)
        var trace: [[Int]] = []
        var found = false
        outer: for d in 0...max {
            trace.append(v)
            var k = -d
            while k <= d {
                let idx = k + max
                var x: Int
                if k == -d || (k != d && v[idx - 1] < v[idx + 1]) { x = v[idx + 1] } else { x = v[idx - 1] + 1 }
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[idx] = x
                if x >= n, y >= m { found = true; break outer }
                k += 2
            }
        }
        _ = found
        // Backtrack
        var edits: [Edit<T>] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let idx = k + max
            let prevK: Int
            if k == -d || (k != d && v[idx - 1] < v[idx + 1]) { prevK = k + 1 } else { prevK = k - 1 }
            let prevX = v[prevK + max]
            let prevY = prevX - prevK
            while x > prevX, y > prevY {
                x -= 1; y -= 1
                edits.append(Edit(op: .equal, token: a[x], oldIndex: offsetA + x, newIndex: offsetB + y))
            }
            if d > 0 {
                if x == prevX { y -= 1; edits.append(Edit(op: .insert, token: b[y], oldIndex: nil, newIndex: offsetB + y)) }
                else { x -= 1; edits.append(Edit(op: .delete, token: a[x], oldIndex: offsetA + x, newIndex: nil)) }
            }
        }
        return edits.reversed()
    }

    // MARK: Tokenisers

    public static func lines(_ s: String) -> [String] {
        var out = s.components(separatedBy: "\n")
        if out.last == "" && s.hasSuffix("\n") { out.removeLast() }
        return out.map { $0.removingSuffix("\r") }
    }

    public static func words(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentIsWord: Bool?
        for c in s {
            let isWord = c.isLetter || c.isNumber || c == "_"
            if c.isWhitespace || c.isNewline {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(String(c))
                currentIsWord = nil
                continue
            }
            if let w = currentIsWord, w != isWord, !current.isEmpty { out.append(current); current = "" }
            current.append(c)
            currentIsWord = isWord
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    public static func characters(_ s: String) -> [String] { s.map { String($0) } }

    /// Unified diff text.
    public static func unified(_ a: String, _ b: String, nameA: String = "a", nameB: String = "b", context: Int = 3, ignoreWhitespace: Bool = false, ignoreCase: Bool = false) -> String {
        func norm(_ l: String) -> String {
            var s = l
            if ignoreWhitespace { s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed() }
            if ignoreCase { s = s.lowercased() }
            return s
        }
        let la = lines(a), lb = lines(b)
        let edits = diff(la.map(norm), lb.map(norm))
        var out = "--- \(nameA)\n+++ \(nameB)\n"
        // Group into hunks
        var i = 0
        var hunks: [[Int]] = []
        var current: [Int] = []
        var lastChange = -context - 1
        for (idx, e) in edits.enumerated() {
            if e.op != .equal {
                if idx - lastChange > 2 * context, !current.isEmpty { hunks.append(current); current = [] }
                if current.isEmpty { current = Array(max(0, idx - context)..<idx) }
                current.append(idx)
                lastChange = idx
            } else if !current.isEmpty, idx - lastChange <= context {
                current.append(idx)
            }
            i = idx
        }
        _ = i
        if !current.isEmpty { hunks.append(current) }
        if hunks.isEmpty { return "" }
        for h in hunks {
            let range = h.first!...h.last!   // swiftlint:disable:this force_unwrapping
            let slice = edits[range]
            let oldStart = (slice.first { $0.oldIndex != nil }?.oldIndex ?? 0) + 1
            let newStart = (slice.first { $0.newIndex != nil }?.newIndex ?? 0) + 1
            let oldCount = slice.filter { $0.op != .insert }.count
            let newCount = slice.filter { $0.op != .delete }.count
            out += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
            for e in slice {
                let text = e.op == .insert ? lb[e.newIndex!] : la[e.oldIndex!]   // swiftlint:disable:this force_unwrapping
                out += (e.op == .equal ? " " : (e.op == .insert ? "+" : "-")) + text + "\n"
            }
        }
        return out
    }

    // MARK: JSON structural diff

    public struct JSONChange: Sendable, Equatable {
        public enum Kind: String, Sendable { case added, removed, changed, typeChanged, moved }
        public var path: String
        public var kind: Kind
        public var before: String?
        public var after: String?
    }

    public static func jsonDiff(_ a: JSONValue, _ b: JSONValue, path: String = "$", ignoreOrder: Bool = false) -> [JSONChange] {
        var out: [JSONChange] = []
        switch (a, b) {
        case (.object(let oa), .object(let ob)):
            for (k, va) in oa {
                let p = "\(path).\(k)"
                if let vb = ob.first(where: { $0.key == k })?.value { out += jsonDiff(va, vb, path: p, ignoreOrder: ignoreOrder) }
                else { out.append(JSONChange(path: p, kind: .removed, before: JSONSerializer.string(va, options: .minified), after: nil)) }
            }
            for (k, vb) in ob where !oa.contains(where: { $0.key == k }) {
                out.append(JSONChange(path: "\(path).\(k)", kind: .added, before: nil, after: JSONSerializer.string(vb, options: .minified)))
            }
            if !ignoreOrder, oa.map(\.key).filter({ k in ob.contains { $0.key == k } }) != ob.map(\.key).filter({ k in oa.contains { $0.key == k } }) {
                out.append(JSONChange(path: path, kind: .moved, before: "keys reordered", after: nil))
            }
        case (.array(let aa), .array(let ab)):
            if ignoreOrder {
                var remaining = ab
                for (i, va) in aa.enumerated() {
                    if let idx = remaining.firstIndex(of: va) { remaining.remove(at: idx) }
                    else { out.append(JSONChange(path: "\(path)[\(i)]", kind: .removed, before: JSONSerializer.string(va, options: .minified), after: nil)) }
                }
                for vb in remaining { out.append(JSONChange(path: "\(path)[]", kind: .added, before: nil, after: JSONSerializer.string(vb, options: .minified))) }
            } else {
                let edits = diff(aa.map { JSONSerializer.string($0, options: .minified) }, ab.map { JSONSerializer.string($0, options: .minified) })
                var pendingDeletes: [(Int, JSONValue)] = []
                for e in edits {
                    switch e.op {
                    case .equal: pendingDeletes.removeAll()
                    case .delete: pendingDeletes.append((e.oldIndex!, aa[e.oldIndex!]))   // swiftlint:disable:this force_unwrapping
                    case .insert:
                        let vb = ab[e.newIndex!]   // swiftlint:disable:this force_unwrapping
                        if let (oi, va) = pendingDeletes.first, case .object = va, case .object = vb {
                            pendingDeletes.removeFirst()
                            out += jsonDiff(va, vb, path: "\(path)[\(oi)]", ignoreOrder: ignoreOrder)
                        } else {
                            out.append(JSONChange(path: "\(path)[\(e.newIndex!)]", kind: .added, before: nil, after: JSONSerializer.string(vb, options: .minified)))   // swiftlint:disable:this force_unwrapping
                        }
                    }
                }
                // flush
                let flushed = edits.filter { $0.op == .delete }.map { $0.oldIndex! }   // swiftlint:disable:this force_unwrapping
                for d in pendingDeletes where flushed.contains(d.0) { out.append(JSONChange(path: "\(path)[\(d.0)]", kind: .removed, before: JSONSerializer.string(d.1, options: .minified), after: nil)) }
            }
        default:
            if a != b {
                let kind: JSONChange.Kind = a.typeName != b.typeName && !(a.typeName == "integer" && b.typeName == "number") && !(a.typeName == "number" && b.typeName == "integer") ? .typeChanged : .changed
                out.append(JSONChange(path: path, kind: kind, before: JSONSerializer.string(a, options: .minified), after: JSONSerializer.string(b, options: .minified)))
            }
        }
        return out
    }
}
