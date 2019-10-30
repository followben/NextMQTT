//
//  ControlPacket.swift
//  SimpleMQTT
//
//  Created by Benjamin Stovold on 23/10/19.
//

import Foundation

struct ControlPacketFlags: OptionSet {
    let rawValue: UInt8

    static let standard     = ControlPacketFlags(rawValue: 0)
    
    static let reserved     = ControlPacketFlags(rawValue: 1 << 1)
    
    static let qos0         = ControlPacketFlags(rawValue: 0)
    static let retain       = ControlPacketFlags(rawValue: 1 << 0)
    static let qos1         = ControlPacketFlags(rawValue: 1 << 1)
    static let qos2         = ControlPacketFlags(rawValue: 1 << 2)
    static let dup          = ControlPacketFlags(rawValue: 1 << 2)
    
    static func forPacket(_ type: ControlPacketType) -> ControlPacketFlags {
        switch type {
        case .publish:
            return .qos0
        case .pubrel, .subscribe, .unsubscribe:
            return .reserved
        default:
            return .standard
        }
    }
}
    
enum ControlPacketType: UInt8 {
    case connect =     0x10
    case connack =     0x20
    case publish =     0x30
    case puback =      0x40
    case pubrec =      0x50
    case pubrel =      0x60
    case pubcomp =     0x70
    case subscribe =   0x80
    case suback =      0x90
    case unsubscribe = 0xa0
    case unsuback =    0xb0
    case pingreq =     0xc0
    case pingresp =    0xd0
    case disconnect =  0xe0
}

struct ControlPacket {
    var type: ControlPacketType
    var flags: ControlPacketFlags
    var variableHeader = AppendableData()
    var payload = AppendableData()
    
    var remainingLength: Data {
        var workingLength = UInt(variableHeader.data.count + payload.data.count)
        var encoded = Data()
        
        while true {
            var byte = UInt8(workingLength & 0x7F)
            workingLength >>= 7
            if workingLength > 0 {
                byte |= 0x80
            }
            encoded.append(byte)
            if workingLength == 0 {
                return encoded
            }
        }
    }
    
    var data: Data {
        var bytes = Data()
        bytes.append(type.rawValue | flags.rawValue)
        bytes += remainingLength
        bytes += variableHeader.data
        bytes += payload.data
        return bytes
    }
    
    init(type: ControlPacketType, flags: ControlPacketFlags = .standard) {
        self.type = type
        self.flags = flags
    }
}
