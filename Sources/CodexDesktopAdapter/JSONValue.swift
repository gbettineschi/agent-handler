// Adapted from Agent HUD Open, Apache-2.0. See THIRD_PARTY_NOTICES.md.
import Foundation

/// A Sendable JSON value that preserves integer precision.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), integer(Int64), number(Double), bool(Bool), null, omitted
    /// A subtree deliberately excluded by the Desktop question projection, unlike truncated required text.
    case discarded

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Int64.self) { self = .integer(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .integer(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null, .omitted, .discarded: try value.encodeNil()
        }
    }

    /// Reads JSON text directly into values, many times faster than through `Decodable`, which tries each type in turn
    /// and throws on each miss. It gives what `JSONDecoder` gives: a number written whole, or with a fraction of zeros
    /// or an exponent, is an integer when it fits Int64, and a repeated key keeps its first value. Text it does not
    /// take, such as one with a byte order mark, a trailing comma or bytes that are not UTF-8, goes to `JSONDecoder`.
    public static func parse(_ data: Data) throws -> Self {
        let parsed: Self? = data.withUnsafeBytes { buffer in
            var parser = JSONParser(bytes: buffer.bindMemory(to: UInt8.self))
            guard let value = try? parser.value(depth: 0) else { return nil }
            parser.skipSpace()
            return parser.index == parser.bytes.count ? value : nil
        }
        return try parsed ?? JSONDecoder().decode(Self.self, from: data)
    }

    /// Reads JSON text as `parse` does, leaving out every string value longer than `limit` bytes as written: it reads as
    /// `null`, and its bytes are passed over without being copied or checked. A reader of a state that carries
    /// screenshots and page dumps beside the few fields it wants reads the fields at the cost of finding where each
    /// long string ends. Keys are read whole, and text the parser does not take throws rather than going to
    /// `JSONDecoder`, which could only read it whole.
    public static func parse(_ data: Data, leavingOutStringsOver limit: Int) throws -> Self {
        try data.withUnsafeBytes { buffer in
            var parser = JSONParser(bytes: buffer.bindMemory(to: UInt8.self), stringLimit: limit)
            let value = try parser.value(depth: 0)
            parser.skipSpace()
            guard parser.index == parser.bytes.count else { throw JSONParser.Malformed() }
            return value
        }
    }

    /// Decode a bounded native frame while dropping only fields already excluded by DesktopProjection.
    /// The node allowance bounds retained values; skipped JSON is validated without building its tree.
    static func parseDesktopFrame(_ data: Data) throws -> Self {
        guard data.count <= 128 * 1024 * 1024 else { throw JSONParser.Malformed() }
        return try data.withUnsafeBytes { buffer in
            var parser = JSONParser(bytes: buffer.bindMemory(to: UInt8.self), stringLimit: 16_384)
            let value = try parser.value(depth: 0, context: .frame)
            parser.skipSpace()
            guard parser.index == parser.bytes.count else { throw JSONParser.Malformed() }
            return value
        }
    }

    public static func from<T: Encodable>(_ value: T) throws -> Self {
        try parse(RecordCoding.encoder().encode(value))
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: RecordCoding.encoder().encode(self))
    }
}

/// JSON's grammar over UTF-8 bytes, into `JSONValue`s.
private struct JSONParser {
    /// Text the parser does not take, which `JSONDecoder` then reads or rejects itself.
    struct Malformed: Error {}

    let bytes: UnsafeBufferPointer<UInt8>
    /// A string value longer than this many bytes as written is passed over and read as null; nil reads every string.
    var stringLimit: Int?
    var index = 0
    var remainingNodes = 200_000
    // Duplicate-key validation in discarded objects needs keys, but never their values.
    // Bound that temporary storage across the active recursion stack as well.
    var remainingScratch = 1024 * 1024

    mutating func skipSpace() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 { index += 1 }
    }

    mutating func value(depth: Int, context: DesktopProjection.Context = .raw) throws -> JSONValue {
        remainingNodes -= 1
        skipSpace()
        guard remainingNodes >= 0, index < bytes.count, depth < 128 else { throw Malformed() }
        if context == .discarded {
            try skipValue(depth: depth)
            return .discarded
        }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            index += 1
            var object: [String: JSONValue] = [:]
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw Malformed() }
                guard let end = closingQuote(), end - index <= 16_384 else { throw Malformed() }
                let key = try string()
                guard object[key] == nil else { throw Malformed() }
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw Malformed() }
                index += 1
                let member = try value(depth: depth + 1, context: context.member(key))
                if object.index(forKey: key) == nil { object[key] = member }
                skipSpace()
                guard index < bytes.count else { throw Malformed() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                guard bytes[index] == UInt8(ascii: "}") else { throw Malformed() }
                index += 1
                return .object(object)
            }
        case UInt8(ascii: "["):
            index += 1
            var array: [JSONValue] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(array) }
            while true {
                array.append(try value(depth: depth + 1, context: context.element))
                skipSpace()
                guard index < bytes.count else { throw Malformed() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                guard bytes[index] == UInt8(ascii: "]") else { throw Malformed() }
                index += 1
                return .array(array)
            }
        case UInt8(ascii: "\""):
            if let stringLimit, let close = closingQuote(), close - index - 1 > stringLimit {
                index = close + 1
                return .omitted
            }
            return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return try number()
        }
    }

    /// Consume irrelevant JSON without spending retained-node capacity or allocating value containers.
    /// Duplicate keys, key lengths, nesting and finite numbers remain checked. Strings
    /// retain the existing oversized-string omission policy; other syntax is validated.
    mutating func skipValue(depth: Int) throws {
        skipSpace()
        guard depth < 128, index < bytes.count else { throw Malformed() }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            index += 1
            var keys: Set<String> = []
            var scratch = 0
            defer { remainingScratch += scratch }
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\""),
                      let end = closingQuote(), end - index <= 16_384 else { throw Malformed() }
                let key = try string(), cost = key.utf8.count + 64
                guard cost <= remainingScratch, keys.insert(key).inserted else { throw Malformed() }
                remainingScratch -= cost; scratch += cost
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw Malformed() }
                index += 1
                try skipValue(depth: depth + 1)
                skipSpace()
                guard index < bytes.count else { throw Malformed() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                guard bytes[index] == UInt8(ascii: "}") else { throw Malformed() }
                index += 1; return
            }
        case UInt8(ascii: "["):
            index += 1
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return }
            while true {
                try skipValue(depth: depth + 1)
                skipSpace()
                guard index < bytes.count else { throw Malformed() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                guard bytes[index] == UInt8(ascii: "]") else { throw Malformed() }
                index += 1; return
            }
        case UInt8(ascii: "\""):
            if let stringLimit, let close = closingQuote(), close - index - 1 > stringLimit { index = close + 1 }
            else { _ = try string() }
        case UInt8(ascii: "t"): try literal("true")
        case UInt8(ascii: "f"): try literal("false")
        case UInt8(ascii: "n"): try literal("null")
        default: _ = try number()
        }
    }

    mutating func literal(_ word: StaticString) throws {
        let count = word.utf8CodeUnitCount
        guard bytes.count - index >= count, memcmp(bytes.baseAddress! + index, word.utf8Start, count) == 0 else { throw Malformed() }
        index += count
    }

    /// Where the string starting at the opening quote closes, found by the quotes alone: one after an odd run of
    /// backslashes is part of the text.
    func closingQuote() -> Int? {
        guard let base = bytes.baseAddress else { return nil }
        var from = index + 1
        while from < bytes.count, let found = memchr(base + from, 0x22, bytes.count - from) {
            let quote = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            var slashes = 0
            while quote - slashes > index + 1, bytes[quote - slashes - 1] == UInt8(ascii: "\\") { slashes += 1 }
            if slashes % 2 == 0 { return quote }
            from = quote + 1
        }
        return nil
    }

    /// The string starting at the opening quote.
    mutating func string() throws -> String {
        index += 1
        let start = index
        var ascii = true
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                let raw = UnsafeBufferPointer(rebasing: bytes[start..<index])
                let text = String(decoding: raw, as: UTF8.self)
                // Text that is not UTF-8 is not repaired here.
                guard ascii || text.utf8.elementsEqual(raw) else { throw Malformed() }
                index += 1
                return text
            }
            if byte == UInt8(ascii: "\\") { break }
            guard byte >= 0x20 else { throw Malformed() }
            if byte >= 0x80 { ascii = false }
            index += 1
        }
        // Escaped: rebuilt byte by byte from where the plain run stopped.
        var utf8 = Array(bytes[start..<index])
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                let text = String(decoding: utf8, as: UTF8.self)
                guard text.utf8.elementsEqual(utf8) else { throw Malformed() }
                return text
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { throw Malformed() }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): utf8.append(escape)
                case UInt8(ascii: "b"): utf8.append(0x08)
                case UInt8(ascii: "f"): utf8.append(0x0C)
                case UInt8(ascii: "n"): utf8.append(0x0A)
                case UInt8(ascii: "r"): utf8.append(0x0D)
                case UInt8(ascii: "t"): utf8.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex()
                    if (0xD800..<0xDC00).contains(scalar) {
                        guard bytes.count - index >= 6, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else { throw Malformed() }
                        index += 2
                        let low = try hex()
                        guard (0xDC00..<0xE000).contains(low) else { throw Malformed() }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    } else if (0xDC00..<0xE000).contains(scalar) { throw Malformed() }
                    guard let unicode = Unicode.Scalar(scalar) else { throw Malformed() }
                    utf8.append(contentsOf: unicode.utf8)
                default: throw Malformed()
                }
            default:
                guard byte >= 0x20 else { throw Malformed() }
                utf8.append(byte)
            }
        }
        throw Malformed()
    }

    mutating func hex() throws -> UInt32 {
        guard bytes.count - index >= 4 else { throw Malformed() }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw Malformed()
            }
            value = value << 4 | UInt32(digit)
        }
        return value
    }

    /// JSON's number grammar. A whole number within Int64 is an integer however it is written, as `JSONDecoder` reads
    /// it; any other is a Double.
    mutating func number() throws -> JSONValue {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else { throw Malformed() }
        if bytes[index] == UInt8(ascii: "0") { index += 1 } else { while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 } }
        let integerEnd = index
        var zeroFraction = true, exponent = false
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            let digits = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                if bytes[index] != UInt8(ascii: "0") { zeroFraction = false }
                index += 1
            }
            guard index > digits else { throw Malformed() }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            exponent = true
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            let digits = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
            guard index > digits else { throw Malformed() }
        }
        // Written whole, or with a fraction of zeros: an integer when its digits fit, exactly as written.
        if !exponent, zeroFraction,
           let integer = Int64(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<integerEnd]), as: UTF8.self)) {
            return .integer(integer)
        }
        guard let double = Double(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)),
              double.isFinite else { throw Malformed() }
        if exponent, let integer = Int64(exactly: double) { return .integer(integer) }
        return .number(double)
    }
}

public extension JSONValue {
    subscript(_ key: String) -> JSONValue { objectValue?[key] ?? .null }
    var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
}
