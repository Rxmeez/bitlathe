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

    /// Largest edit distance explored in a single middle-snake search before that region is reported as wholly changed.
    static let maxSearchDepth = 6_000

    public static func diff<T: Equatable & Sendable & Hashable>(_ a: [T], _ b: [T]) -> [Edit<T>] {
        // Intern tokens as dense integers so the inner loop compares Ints, not Strings.
        var ids: [T: Int] = [:]
        ids.reserveCapacity(a.count + b.count)
        func intern(_ t: T) -> Int {
            if let i = ids[t] { return i }
            let i = ids.count
            ids[t] = i
            return i
        }
        let ia = a.map(intern), ib = b.map(intern)
        var solver = MyersSolver(a: ia, b: ib)
        solver.solve(0, ia.count, 0, ib.count)
        var edits: [Edit<T>] = []
        edits.reserveCapacity(Swift.max(a.count, b.count) + 16)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, solver.deleted[i] {
                edits.append(Edit(op: .delete, token: a[i], oldIndex: i, newIndex: nil)); i += 1
            } else if j < b.count, solver.inserted[j] {
                edits.append(Edit(op: .insert, token: b[j], oldIndex: nil, newIndex: j)); j += 1
            } else {
                edits.append(Edit(op: .equal, token: a[i], oldIndex: i, newIndex: j)); i += 1; j += 1
            }
        }
        return edits
    }

    /// Linear-space Myers (1986 section 4b): find the middle snake, recurse on both halves.
    /// Memory is O(N + M); time is O(ND) with D bounded by `maxSearchDepth` per region.
    private struct MyersSolver {
        let a: [Int]
        let b: [Int]
        var deleted: [Bool]
        var inserted: [Bool]
        var vf: [Int]
        var vb: [Int]

        init(a: [Int], b: [Int]) {
            self.a = a
            self.b = b
            deleted = [Bool](repeating: false, count: a.count)
            inserted = [Bool](repeating: false, count: b.count)
            let size = 2 * Swift.min(a.count + b.count, DiffEngine.maxSearchDepth) + 4
            vf = [Int](repeating: 0, count: size)
            vb = [Int](repeating: 0, count: size)
        }

        mutating func solve(_ aLo0: Int, _ aHi0: Int, _ bLo0: Int, _ bHi0: Int) {
            var aLo = aLo0, aHi = aHi0, bLo = bLo0, bHi = bHi0
            while aLo < aHi, bLo < bHi, a[aLo] == b[bLo] { aLo += 1; bLo += 1 }
            while aLo < aHi, bLo < bHi, a[aHi - 1] == b[bHi - 1] { aHi -= 1; bHi -= 1 }
            if aLo == aHi {
                for j in bLo..<bHi { inserted[j] = true }
                return
            }
            if bLo == bHi {
                for i in aLo..<aHi { deleted[i] = true }
                return
            }
            guard let (xs, ys, xe, ye) = middleSnake(aLo, aHi, bLo, bHi) else {
                // Too different to align cheaply: report the region as replaced.
                for i in aLo..<aHi { deleted[i] = true }
                for j in bLo..<bHi { inserted[j] = true }
                return
            }
            solve(aLo, aLo + xs, bLo, bLo + ys)
            solve(aLo + xe, aHi, bLo + ye, bHi)
        }

        /// Returns the middle snake in coordinates relative to (aLo, bLo), or nil when the search budget is exhausted.
        private mutating func middleSnake(_ aLo: Int, _ aHi: Int, _ bLo: Int, _ bHi: Int) -> (Int, Int, Int, Int)? {
            let n = aHi - aLo, m = bHi - bLo
            let delta = n - m
            let odd = delta & 1 != 0
            let maxD = Swift.min((n + m + 1) / 2, DiffEngine.maxSearchDepth)
            let off = maxD + 1
            vf[off + 1] = 0
            vb[off + 1] = 0
            for d in 0...maxD {
                var k = -d
                while k <= d {
                    var x = (k == -d || (k != d && vf[off + k - 1] < vf[off + k + 1])) ? vf[off + k + 1] : vf[off + k - 1] + 1
                    var y = x - k
                    let x0 = x, y0 = y
                    while x < n, y < m, a[aLo + x] == b[bLo + y] { x += 1; y += 1 }
                    vf[off + k] = x
                    if odd {
                        let kb = delta - k
                        if kb >= -(d - 1), kb <= d - 1, x + vb[off + kb] >= n { return (x0, y0, x, y) }
                    }
                    k += 2
                }
                k = -d
                while k <= d {
                    var x = (k == -d || (k != d && vb[off + k - 1] < vb[off + k + 1])) ? vb[off + k + 1] : vb[off + k - 1] + 1
                    var y = x - k
                    let x0 = x, y0 = y
                    while x < n, y < m, a[aLo + n - 1 - x] == b[bLo + m - 1 - y] { x += 1; y += 1 }
                    vb[off + k] = x
                    if !odd {
                        let kf = delta - k
                        if kf >= -d, kf <= d, vf[off + kf] + x >= n { return (n - x, m - y, n - x0, m - y0) }
                    }
                    k += 2
                }
            }
            return nil
        }
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
                func flushDeletes() {
                    for d in pendingDeletes { out.append(JSONChange(path: "\(path)[\(d.0)]", kind: .removed, before: JSONSerializer.string(d.1, options: .minified), after: nil)) }
                    pendingDeletes.removeAll()
                }
                for e in edits {
                    switch e.op {
                    case .equal: flushDeletes()   // deletions not paired with an insert are real removals
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
                flushDeletes()
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
