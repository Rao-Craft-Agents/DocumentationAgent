//  WHAT: A JSON value written the same way every time: objects keep the order they are built in, numbers are
//        integers, strings are escaped as `JSON.stringify` escapes them. What the site's data files are made of.
//  PIN:  THE SAME TREE WRITES THE SAME BYTES. `JSONSerialization` orders a dictionary's keys as it pleases and writes
//        numbers its own way; a rerun of the site on an unchanged project must change no file, so every object here
//        is a list of pairs in an order the writer chose, and a map is sorted before it becomes one.

import Foundation

indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    static func == (a: JSONValue, b: JSONValue) -> Bool { a.text == b.text }

    static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
    static func ints(_ values: [Int]) -> JSONValue { .array(values.map(JSONValue.int)) }
    static func optional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    static func optional(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }

    /// An object from a map, its keys sorted.
    static func sorted(_ map: [String: JSONValue]) -> JSONValue { .object(map.keys.sorted().map { ($0, map[$0]!) }) }

    /// The value as compact JSON.
    var text: String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(256)
        write(into: &bytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    func write(into out: inout [UInt8]) {
        switch self {
        case .null: out.append(contentsOf: [110, 117, 108, 108])
        case .bool(let value): out.append(contentsOf: value ? Array("true".utf8) : Array("false".utf8))
        case .int(let value): out.append(contentsOf: Array(String(value).utf8))
        case .string(let value): Self.write(value, into: &out)
        case .array(let values):
            out.append(91)
            for (i, value) in values.enumerated() {
                if i > 0 { out.append(44) }
                value.write(into: &out)
            }
            out.append(93)
        case .object(let pairs):
            out.append(123)
            for (i, pair) in pairs.enumerated() {
                if i > 0 { out.append(44) }
                Self.write(pair.0, into: &out)
                out.append(58)
                pair.1.write(into: &out)
            }
            out.append(125)
        }
    }

    private static let hex: [UInt8] = Array("0123456789abcdef".utf8)

    static func write(_ string: String, into out: inout [UInt8]) {
        out.append(34)
        for byte in string.utf8 {
            switch byte {
            case 34: out.append(contentsOf: [92, 34])
            case 92: out.append(contentsOf: [92, 92])
            case 10: out.append(contentsOf: [92, 110])
            case 13: out.append(contentsOf: [92, 114])
            case 9: out.append(contentsOf: [92, 116])
            case 8: out.append(contentsOf: [92, 98])
            case 12: out.append(contentsOf: [92, 102])
            case 0..<32: out.append(contentsOf: [92, 117, 48, 48, hex[Int(byte >> 4)], hex[Int(byte & 15)]])
            default: out.append(byte)
            }
        }
        out.append(34)
    }
}
