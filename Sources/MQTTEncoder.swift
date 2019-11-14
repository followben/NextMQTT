//
//  MQTTEncoder.swift
//  SimpleMQTT iOS
//
//  Created by Ben Stovold on 4/11/19.
//

import Foundation

protocol MQTTEncodable: Encodable {
    func mqttEncode(to encoder: MQTTEncoder) throws
}

extension MQTTEncodable {
    func mqttEncode(to encoder: MQTTEncoder) throws {
        try self.encode(to: encoder)
    }
}

class MQTTEncoder {
    var data: [UInt8] = []
    
    public init() {}
}

extension MQTTEncoder {
    static func encode(_ value: MQTTEncodable) throws -> [UInt8] {
        let encoder = MQTTEncoder()
        try value.mqttEncode(to: encoder)
        return encoder.data
    }
}

extension MQTTEncoder {
    enum Error: Swift.Error {
        /// Attempted to encode a type which is `Encodable`, but not `MQTTEncodable`.
        /// (`MQTTEncodable` is required because `MQTTEncoder` doesn't support full keyed
        /// coding functionality.)
        case typeNotConformingToMQTTEncodable(Encodable.Type)
        
        /// Attempted to encode a type which is not `Encodable`.
        case typeNotConformingToEncodable(Any.Type)
    }
}

/// Default Encoding for various Types.
extension MQTTEncoder {
    func encode(_ value: Bool) {
        encode(value ? 1 as UInt8 : 0 as UInt8)
    }
    
    func encode(_ value: UInt8) {
        appendBytes(of: value)
    }
    
    func encode(_ value: Float) {
        appendBytes(of: CFConvertFloatHostToSwapped(value))
    }
    
    func encode(_ value: Double) {
        appendBytes(of: CFConvertDoubleHostToSwapped(value))
    }
    
    func encode(_ encodable: Encodable) throws {
        switch encodable {
        case let v as Int:
            try encode(Int64(v))
        case let v as UInt:
            try encode(UInt64(v))
            
        case let v as Float:
            encode(v)
        case let v as Double:
            encode(v)
            
        case let v as Bool:
            encode(v)
            
        case let encodable as MQTTEncodable:
            try encodable.mqttEncode(to: self)
            
        default:
            throw Error.typeNotConformingToMQTTEncodable(type(of: encodable))
        }
    }
    
    /// Append the raw bytes of the parameter to the encoder's data. No byte-swapping
    /// or other encoding is done.
    func appendBytes<T>(of: T) {
        var target = of
        withUnsafeBytes(of: &target) {
            data.append(contentsOf: $0)
        }
    }
}

extension MQTTEncoder: Encoder {
    var codingPath: [CodingKey] { return [] }
    
    var userInfo: [CodingUserInfoKey : Any] { return [:] }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return UnkeyedContanier(encoder: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return UnkeyedContanier(encoder: self)
    }
    
    private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        var encoder: MQTTEncoder
        
        var codingPath: [CodingKey] { return [] }
        
        func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            try encoder.encode(value)
        }
        
        func encodeNil(forKey key: Key) throws {}
        
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return encoder.container(keyedBy: keyType)
        }
        
        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            return encoder.unkeyedContainer()
        }
        
        func superEncoder() -> Encoder {
            return encoder
        }
        
        func superEncoder(forKey key: Key) -> Encoder {
            return encoder
        }
    }
    
    private struct UnkeyedContanier: UnkeyedEncodingContainer, SingleValueEncodingContainer {
        var encoder: MQTTEncoder
        
        var codingPath: [CodingKey] { return [] }
        
        var count: Int { return 0 }

        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            return encoder.container(keyedBy: keyType)
        }
        
        func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            return self
        }
        
        func superEncoder() -> Encoder {
            return encoder
        }
        
        func encodeNil() throws {}
        
        func encode<T>(_ value: T) throws where T : Encodable {
            try encoder.encode(value)
        }
    }
}
