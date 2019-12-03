//
//  NextMQTT
//
//  Copyright (c) Ben Stovold 2019
//  MIT license, see LICENSE file for details
//

import Foundation

extension UIntVar {
    enum Error: Swift.Error {
        case valueTooLarge
    }
}

struct UIntVar: ExpressibleByIntegerLiteral {
    typealias IntegerLiteralType = UInt
    
    private static var _maxValue: UInt = 268435455
    
    fileprivate let value: UInt
    
    init(_ value: UInt) throws {
        guard value <= UIntVar._maxValue else {
            throw Error.valueTooLarge
        }
        self.value = value
    }

    init(integerLiteral value: UInt) {
        assert(value <= UIntVar._maxValue, "value \(value) too large for UIntVar")
        try! self.init(value)
    }

    static var max: UIntVar {
        return try! .init(UIntVar._maxValue)
    }

    static let min: UIntVar = 0
}

extension UInt {
    init(_ uintvar: UIntVar) {
        self = UInt(uintvar.value)
    }
}

extension Int {
    init(_ uintvar: UIntVar) {
        self = Int(uintvar.value)
    }
}

extension UIntVar: Equatable {}

extension UIntVar: Codable {}

extension UIntVar: CustomStringConvertible {
    var description: String {
        return Int(self).description
    }
}

extension UIntVar: MQTTEncodable {
    fileprivate func bytes() -> [UInt8] {
        guard value > 0 else { return [UInt8(value)] }
        
        var working = value
        var bytes = [UInt8]()

        while working > 0 {
            var byte: UInt8 = UInt8(working % 0x80)
            working = working / 0x80
            if working > 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        }
        return bytes
    }
    
    func mqttEncode(to encoder: MQTTEncoder) {
        self.bytes().forEach { encoder.appendBytes(of: $0) }
    }
}

extension UIntVar: MQTTDecodable {
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var multiplier: UInt = 1
        var working: UInt = 0x00
        var bytes: [UInt8] = []
        
        while true {
            if multiplier > 128*128*128 {
                throw MQTTDecoder.Error.invalidUIntVar(bytes)
            }
            var byte = UInt8.init()
            try decoder.read(into: &byte)
            bytes.append(byte)
            working += UInt(byte & 0x7F) * multiplier
            multiplier *= 0x80
            if byte & 0x80 == 0 {
                break
            }
        }
        
        try self.init(working)
    }
}
