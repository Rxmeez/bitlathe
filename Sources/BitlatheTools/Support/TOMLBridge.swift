import Foundation
import TOMLKit
import BitlatheCore

enum TOMLBridge {
    static func parse(_ text: String) throws -> JSONValue {
        do {
            let table = try TOMLTable(string: text)
            return convert(table)
        } catch let e as TOMLParseError {
            return try { throw ToolError(e.debugDescription.split(separator: "\n").first.map(String.init) ?? "Invalid TOML",
                                         line: Int(e.source.begin.line), column: Int(e.source.begin.column)) }()
        } catch {
            throw ToolError("Invalid TOML: \(error.localizedDescription)")
        }
    }

    static func convert(_ table: TOMLTable) -> JSONValue {
        .object(table.keys.map { key in (key: key, value: convert(table[key])) })
    }

    static func convert(_ v: (any TOMLValueConvertible)?) -> JSONValue {
        guard let v else { return .null }
        if let t = v.table { return convert(t) }
        if let a = v.array { return .array(a.map { convert($0) }) }
        if let b = v.bool { return .bool(b) }
        if let i = v.int { return .number(String(i)) }
        if let d = v.double { return .number(d) }
        if let s = v.string { return .string(s) }
        if let d = v.date { return .string(String(format: "%04d-%02d-%02d", d.year, d.month, d.day)) }
        if let t = v.time { return .string(String(format: "%02d:%02d:%02d", t.hour, t.minute, t.second)) }
        if let dt = v.dateTime {
            var s = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", dt.date.year, dt.date.month, dt.date.day, dt.time.hour, dt.time.minute, dt.time.second)
            if let off = dt.offset { s += off.offset == 0 ? "Z" : String(format: "%@%02d:%02d", off.offset < 0 ? "-" : "+", abs(off.offset) / 60, abs(off.offset) % 60) }
            return .string(s)
        }
        return .string(v.debugDescription)
    }

    static func serialize(_ v: JSONValue) throws -> String {
        guard case .object = v else { throw ToolError("TOML documents must be an object at the top level", hint: "Wrap the value in an object") }
        let table = try toTable(v)
        return table.convert()
    }

    static func toTable(_ v: JSONValue) throws -> TOMLTable {
        let t = TOMLTable()
        guard case .object(let o) = v else { return t }
        for (k, val) in o {
            if let x = try toValue(val) { t[k] = x }
        }
        return t
    }

    static func toValue(_ v: JSONValue) throws -> (any TOMLValueConvertible)? {
        switch v {
        case .null: return nil
        case .bool(let b): return b
        case .number(let s):
            if let i = Int(s) { return i }
            if let d = Double(s) { return d }
            return s
        case .string(let s): return s
        case .array(let a):
            let arr = TOMLArray()
            for item in a { if let x = try toValue(item) { arr.append(x) } }
            return arr
        case .object: return try toTable(v)
        }
    }
}
