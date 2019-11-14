//
//  MQTTDecoder.swift
//  SimpleMQTT iOS
//
//  Created by Ben Stovold on 4/11/19.
//

import Foundation

protocol MQTTDecodable: Decodable {
    init(fromMQTTDecoder decoder: MQTTDecoder) throws
}

extension MQTTDecodable {
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        try self.init(from: decoder)
    }
}

class MQTTDecoder {
    fileprivate var data: [UInt8]
    fileprivate var cursor = 0
    
    init(data: [UInt8]) {
        self.data = data
    }
    
    init() {
        self.data = []
    }
    
    func append(_ newData: [UInt8]) {
        newData.forEach { data.append($0) }
    }
}

extension MQTTDecoder {
    static func decode<T: MQTTDecodable>(_ type: T.Type, data: [UInt8]) throws -> T {
        return try MQTTDecoder(data: data).decode(T.self)
    }
}

extension MQTTDecoder {
    
    enum Error: Swift.Error {
        /// The decoder hit the end of the data while the values it was decoding expected
        /// more.
        case prematureEndOfData
        
        /// Attempted to decode a type which is `Decodable`, but not `MQTTDecodable`.
        /// (`MQTTDecodable` is required because `MQTTDecoder` doesn't support keyed coding.)
        case typeNotConformingToMQTTDecodable(Decodable.Type)
        
        /// Attempted to decode a type which is not `Decodable`.
        case typeNotConformingToDecodable(Any.Type)
        
        /// Attempted to decode an `Int` which can't be represented. This happens in 32-bit
        /// code when the stored `Int` doesn't fit into 32 bits.
        case intOutOfRange(Int64)
        
        /// Attempted to decode a `UInt` which can't be represented. This happens in 32-bit
        /// code when the stored `UInt` doesn't fit into 32 bits.
        case uintOutOfRange(UInt64)
        
        /// Attempted to decode a `Bool` where the byte representing it was not a `1` or a `0`.
        case boolOutOfRange(UInt8)
        
        /// Attempted to decode a `String` but the encoded `String` data was not valid UTF-8.
        case invalidUTF8([UInt8])
        
        /// Attempted to decode a `UIntVar` but the encoded data was not a valid UIntVar.
        case invalidUIntVar([UInt8])
    }
}

/// Default Decoding for various Types.
extension MQTTDecoder {
    func decode(_ type: Bool.Type) throws -> Bool {
        switch try decode(UInt8.self) {
        case 0: return false
        case 1: return true
        case let x: throw Error.boolOutOfRange(x)
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        var swapped = CFSwappedFloat32()
        try read(into: &swapped)
        return CFConvertFloatSwappedToHost(swapped)
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        var swapped = CFSwappedFloat64()
        try read(into: &swapped)
        return CFConvertDoubleSwappedToHost(swapped)
    }
    
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        switch type {
            
        case is Int.Type:
            let v = try decode(Int64.self)
            if let v = Int(exactly: v) {
                return v as! T
            } else {
                throw Error.intOutOfRange(v)
            }
        case is UInt.Type:
            let v = try decode(UInt64.self)
            if let v = UInt(exactly: v) {
                return v as! T
            } else {
                throw Error.uintOutOfRange(v)
            }
            
        case is Float.Type:
            return try decode(Float.self) as! T
        case is Double.Type:
            return try decode(Double.self) as! T
            
        case is Bool.Type:
            return try decode(Bool.self) as! T
            
        case let decodableT as MQTTDecodable.Type:
            return try decodableT.init(fromMQTTDecoder: self) as! T
            
        default:
            throw Error.typeNotConformingToMQTTDecodable(type)
        }
    }
    
    /// Read the appropriate number of raw bytes directly into the given value. No byte
    /// swapping or other postprocessing is done.
    func read<T>(into: inout T) throws {
        try read(MemoryLayout<T>.size, into: &into)
    }
}

/// Internal methods for decoding raw data.
extension MQTTDecoder {
    /// Read the given number of bytes into the given pointer, advancing the cursor
    /// appropriately.
    func read(_ byteCount: Int, into: UnsafeMutableRawPointer) throws {
        if cursor + byteCount > data.count {
            throw Error.prematureEndOfData
        }
        
        data.withUnsafeBytes({
            let from = $0.baseAddress! + cursor
            memcpy(into, from, byteCount)
        })
        
        cursor += byteCount
    }
}

extension MQTTDecoder: Decoder {
    var codingPath: [CodingKey] { return [] }
    
    var userInfo: [CodingUserInfoKey : Any] { return [:] }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(KeyedContainer<Key>(decoder: self))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }
    
    private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var decoder: MQTTDecoder
        
        var codingPath: [CodingKey] { return [] }
        
        var allKeys: [Key] { return [] }
        
        func contains(_ key: Key) -> Bool {
            return true
        }
        
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            return try decoder.decode(T.self)
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            return true
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            return try decoder.container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            return try decoder.unkeyedContainer()
        }
        
        func superDecoder() throws -> Decoder {
            return decoder
        }
        
        func superDecoder(forKey key: Key) throws -> Decoder {
            return decoder
        }
    }
    
    private struct UnkeyedContainer: UnkeyedDecodingContainer, SingleValueDecodingContainer {
        var decoder: MQTTDecoder
        
        var codingPath: [CodingKey] { return [] }
        
        var count: Int? { return decoder.data.count }
        
        var currentIndex: Int { return decoder.cursor }

        var isAtEnd: Bool { return decoder.cursor > (decoder.data.count - 1) }
        
        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            return try decoder.decode(type)
        }
        
        func decodeNil() -> Bool {
            return true
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            return try decoder.container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            return self
        }
        
        func superDecoder() throws -> Decoder {
            return decoder
        }
    }
}

private extension FixedWidthInteger {
    static func from(byteDecoder: MQTTDecoder) throws -> Self {
        var v = Self.init()
        try byteDecoder.read(into: &v)
        return self.init(bigEndian: v)
    }
}
