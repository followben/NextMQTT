//
//  MQTTCodable.swift
//  SimpleMQTT iOS
//
//  Created by Ben Stovold on 4/11/19.
//

import Foundation

typealias MQTTCodable = MQTTEncodable & MQTTDecodable

/// Consumes the remaining bytes in the decoder.
extension Data: MQTTCodable {
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        let count = decoder.count - decoder.currentIndex
        self.init()
        self.reserveCapacity(count)
        for _ in 0 ..< count {
            let decoded = try UInt8.init(from: decoder)
            self.append(decoded)
        }
    }
}

extension String: MQTTCodable {
    func mqttEncode(to encoder: MQTTEncoder) throws {
        let byteArray = Array(self.utf8)
        try encoder.encode(UInt16(byteArray.count))
        for element in byteArray {
            try element.encode(to: encoder)
        }
    }
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        let count = Int(try decoder.decode(UInt16.self))
        var utf8: [UInt8] = []
        utf8.reserveCapacity(count)
        for _ in 0 ..< count {
            let decoded = try decoder.decode(UInt8.self)
            utf8.append(decoded)
        }
        if let str = String(bytes: utf8, encoding: .utf8) {
            self = str
        } else {
            throw MQTTDecoder.Error.invalidUTF8(utf8)
        }
    }
}

extension FixedWidthInteger where Self: MQTTEncodable {
    func mqttEncode(to encoder: MQTTEncoder) {
        encoder.appendBytes(of: self.bigEndian)
    }
}

extension FixedWidthInteger where Self: MQTTDecodable {
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var v = Self.init()
        try decoder.read(into: &v)
        self.init(bigEndian: v)
    }
}

extension Int8: MQTTCodable {}
extension UInt8: MQTTCodable {}
extension Int16: MQTTCodable {}
extension UInt16: MQTTCodable {}
extension Int32: MQTTCodable {}
extension UInt32: MQTTCodable {}
extension Int64: MQTTCodable {}
extension UInt64: MQTTCodable {}
