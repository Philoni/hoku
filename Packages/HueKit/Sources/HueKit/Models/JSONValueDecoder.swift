import Foundation

// Decodes typed models straight from a `JSONValue` tree. The store decodes a model
// for every event-stream update; going through `JSONEncoder` → `Data` → `JSONDecoder`
// for each of them cost most of the time spent on events. Semantics match
// `JSONDecoder` with default strategies (verified by `JSONValueDecoderTests`).

extension JSONValue {
    /// Decodes a typed model from this value.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try unbox(as: type, codingPath: [])
    }

    fileprivate func unbox<T: Decodable>(as type: T.Type, codingPath: [any CodingKey]) throws -> T {
        // Fast paths for leaves, which make up most of a resource.
        switch type {
        case is JSONValue.Type:
            return self as! T
        case is String.Type:
            guard case let .string(string) = self else { throw mismatch(type, codingPath) }
            return string as! T
        case is Double.Type:
            guard case let .number(number) = self else { throw mismatch(type, codingPath) }
            return number as! T
        case is Bool.Type:
            guard case let .bool(bool) = self else { throw mismatch(type, codingPath) }
            return bool as! T
        case is Int.Type:
            return try integer(Int.self, codingPath) as! T
        default:
            return try T(from: JSONValueDecoder(value: self, codingPath: codingPath))
        }
    }

    fileprivate func integer<I: BinaryInteger>(_ type: I.Type, _ codingPath: [any CodingKey]) throws -> I {
        guard case let .number(number) = self, number.rounded() == number, let value = I(exactly: number) else {
            throw mismatch(type, codingPath)
        }
        return value
    }

    fileprivate func float(_ codingPath: [any CodingKey]) throws -> Float {
        guard case let .number(number) = self else { throw mismatch(Float.self, codingPath) }
        return Float(number)
    }

    fileprivate func mismatch(_ type: Any.Type, _ codingPath: [any CodingKey]) -> DecodingError {
        if case .null = self {
            return .valueNotFound(type, .init(codingPath: codingPath, debugDescription: "Expected \(type) but found null."))
        }
        return .typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected \(type), found \(self)."))
    }
}

private struct JSONValueDecoder: Decoder {
    let value: JSONValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case let .object(object) = value else { throw value.mismatch([String: JSONValue].self, codingPath) }
        return KeyedDecodingContainer(KeyedContainer<Key>(object: object, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(array) = value else { throw value.mismatch([JSONValue].self, codingPath) }
        return UnkeyedContainer(array: array, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueContainer(value: value, codingPath: codingPath)
    }
}

private struct IndexKey: CodingKey {
    let intValue: Int?
    var stringValue: String { "Index \(intValue ?? 0)" }
    init(_ index: Int) { intValue = index }
    init?(stringValue _: String) { nil }
    init?(intValue: Int) { self.intValue = intValue }
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: [String: JSONValue]
    let codingPath: [any CodingKey]

    var allKeys: [Key] { object.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    private func value(_ key: Key) throws -> JSONValue {
        guard let value = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value for key \(key.stringValue)."))
        }
        return value
    }

    private func path(_ key: Key) -> [any CodingKey] { codingPath + [key] }

    func decodeNil(forKey key: Key) throws -> Bool {
        if case .null = try value(key) { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try value(key).unbox(as: type, codingPath: path(key))
    }

    func decode(_: Bool.Type, forKey key: Key) throws -> Bool { try value(key).unbox(as: Bool.self, codingPath: path(key)) }
    func decode(_: String.Type, forKey key: Key) throws -> String { try value(key).unbox(as: String.self, codingPath: path(key)) }
    func decode(_: Double.Type, forKey key: Key) throws -> Double { try value(key).unbox(as: Double.self, codingPath: path(key)) }
    func decode(_: Float.Type, forKey key: Key) throws -> Float { try value(key).float(path(key)) }
    func decode(_: Int.Type, forKey key: Key) throws -> Int { try value(key).integer(Int.self, path(key)) }
    func decode(_: Int8.Type, forKey key: Key) throws -> Int8 { try value(key).integer(Int8.self, path(key)) }
    func decode(_: Int16.Type, forKey key: Key) throws -> Int16 { try value(key).integer(Int16.self, path(key)) }
    func decode(_: Int32.Type, forKey key: Key) throws -> Int32 { try value(key).integer(Int32.self, path(key)) }
    func decode(_: Int64.Type, forKey key: Key) throws -> Int64 { try value(key).integer(Int64.self, path(key)) }
    func decode(_: UInt.Type, forKey key: Key) throws -> UInt { try value(key).integer(UInt.self, path(key)) }
    func decode(_: UInt8.Type, forKey key: Key) throws -> UInt8 { try value(key).integer(UInt8.self, path(key)) }
    func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 { try value(key).integer(UInt16.self, path(key)) }
    func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 { try value(key).integer(UInt32.self, path(key)) }
    func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 { try value(key).integer(UInt64.self, path(key)) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try JSONValueDecoder(value: value(key), codingPath: path(key)).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try JSONValueDecoder(value: value(key), codingPath: path(key)).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        JSONValueDecoder(value: .object(object), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        JSONValueDecoder(value: object[key.stringValue] ?? .null, codingPath: path(key))
    }
}

private struct UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [JSONValue]
    let codingPath: [any CodingKey]
    private(set) var currentIndex = 0

    init(array: [JSONValue], codingPath: [any CodingKey]) {
        self.array = array
        self.codingPath = codingPath
    }

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    private mutating func next<T>(_ type: T.Type) throws -> (JSONValue, [any CodingKey]) {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [IndexKey(currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        defer { currentIndex += 1 }
        return (array[currentIndex], codingPath + [IndexKey(currentIndex)])
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd, case .null = array[currentIndex] else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let (value, path) = try next(type)
        return try value.unbox(as: type, codingPath: path)
    }

    mutating func decode(_: Bool.Type) throws -> Bool { try decode(Bool.self as Bool.Type, generic: ()) }
    mutating func decode(_: String.Type) throws -> String { try decode(String.self as String.Type, generic: ()) }
    mutating func decode(_: Double.Type) throws -> Double { try decode(Double.self as Double.Type, generic: ()) }
    mutating func decode(_: Float.Type) throws -> Float { let (value, path) = try next(Float.self); return try value.float(path) }
    mutating func decode(_: Int.Type) throws -> Int { try integer(Int.self) }
    mutating func decode(_: Int8.Type) throws -> Int8 { try integer(Int8.self) }
    mutating func decode(_: Int16.Type) throws -> Int16 { try integer(Int16.self) }
    mutating func decode(_: Int32.Type) throws -> Int32 { try integer(Int32.self) }
    mutating func decode(_: Int64.Type) throws -> Int64 { try integer(Int64.self) }
    mutating func decode(_: UInt.Type) throws -> UInt { try integer(UInt.self) }
    mutating func decode(_: UInt8.Type) throws -> UInt8 { try integer(UInt8.self) }
    mutating func decode(_: UInt16.Type) throws -> UInt16 { try integer(UInt16.self) }
    mutating func decode(_: UInt32.Type) throws -> UInt32 { try integer(UInt32.self) }
    mutating func decode(_: UInt64.Type) throws -> UInt64 { try integer(UInt64.self) }

    private mutating func decode<T: Decodable>(_ type: T.Type, generic _: Void) throws -> T {
        let (value, path) = try next(type)
        return try value.unbox(as: type, codingPath: path)
    }

    private mutating func integer<I: BinaryInteger>(_ type: I.Type) throws -> I {
        let (value, path) = try next(type)
        return try value.integer(type, path)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let (value, path) = try next([String: JSONValue].self)
        return try JSONValueDecoder(value: value, codingPath: path).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let (value, path) = try next([JSONValue].self)
        return try JSONValueDecoder(value: value, codingPath: path).unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder {
        let (value, path) = try next(JSONValue.self)
        return JSONValueDecoder(value: value, codingPath: path)
    }
}

private struct SingleValueContainer: SingleValueDecodingContainer {
    let value: JSONValue
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T { try value.unbox(as: type, codingPath: codingPath) }
    func decode(_: Bool.Type) throws -> Bool { try value.unbox(as: Bool.self, codingPath: codingPath) }
    func decode(_: String.Type) throws -> String { try value.unbox(as: String.self, codingPath: codingPath) }
    func decode(_: Double.Type) throws -> Double { try value.unbox(as: Double.self, codingPath: codingPath) }
    func decode(_: Float.Type) throws -> Float { try value.float(codingPath) }
    func decode(_: Int.Type) throws -> Int { try value.integer(Int.self, codingPath) }
    func decode(_: Int8.Type) throws -> Int8 { try value.integer(Int8.self, codingPath) }
    func decode(_: Int16.Type) throws -> Int16 { try value.integer(Int16.self, codingPath) }
    func decode(_: Int32.Type) throws -> Int32 { try value.integer(Int32.self, codingPath) }
    func decode(_: Int64.Type) throws -> Int64 { try value.integer(Int64.self, codingPath) }
    func decode(_: UInt.Type) throws -> UInt { try value.integer(UInt.self, codingPath) }
    func decode(_: UInt8.Type) throws -> UInt8 { try value.integer(UInt8.self, codingPath) }
    func decode(_: UInt16.Type) throws -> UInt16 { try value.integer(UInt16.self, codingPath) }
    func decode(_: UInt32.Type) throws -> UInt32 { try value.integer(UInt32.self, codingPath) }
    func decode(_: UInt64.Type) throws -> UInt64 { try value.integer(UInt64.self, codingPath) }
}
