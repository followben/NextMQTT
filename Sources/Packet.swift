//
//  Packet.swift
//  SimpleMQTT iOS
//
//  Created by Ben Stovold on 4/11/19.
//

import Foundation

fileprivate extension MQTT {
    static let ProtocolName: String = "MQTT"
    static let ProtocolVersion: UInt8 = 5
}

fileprivate extension String {
    var byteCount: UInt {
        UInt(self.utf8.count + 2)
    }
}

struct ControlOptions: OptionSet, MQTTCodable {
    let rawValue: UInt8
    
    // Control Packet type
//    connect =     0x10
//    connack =     0x20
//    publish =     0x30
//    puback =      0x40
//    pubrec =      0x50
//    pubrel =      0x60
//    pubcomp =     0x70
//    subscribe =   0x80
//    suback =      0x90
//    unsubscribe = 0xa0
//    unsuback =    0xb0
//    pingreq =     0xc0
//    pingresp =    0xd0
//    disconnect =  0xe0
    static let connect      = ControlOptions(rawValue: 1 << 4)
    static let connack      = ControlOptions(rawValue: 2 << 4)
    static let pingreq      = ControlOptions(rawValue: 12 << 4)
    static let pingresp     = ControlOptions(rawValue: 13 << 4)
    static let disconnect   = ControlOptions(rawValue: 14 << 4)
    
    // Flags specific to each Control Packet type
    static let reserved     = ControlOptions(rawValue: 0)
}

enum PropertyIdentifier: UInt {
    case topicAliasMaximum  = 34 // Two Byte Integer
}

struct FixedHeader: MQTTCodable {
    let controlOptions: ControlOptions
    let remainingLength: UIntVar
}

protocol Packet {
    var fixedHeader: FixedHeader { get }
}

protocol EncodablePacket: Packet, MQTTEncodable {}
protocol DecodablePacket: Packet, MQTTDecodable {}

// MARK: Generic Decodable MQTT Packet

struct MQTTPacket: DecodablePacket {
    let fixedHeader: FixedHeader
    let bytes: [UInt8]
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        let fixedHeader = try container.decode(FixedHeader.self)
        let numberOfBytes = Int(fixedHeader.remainingLength)
        var bytes: [UInt8] = []
        for _ in 0..<numberOfBytes {
            let byte = try container.decode(UInt8.self)
            bytes.append(byte)
        }
        
        self.fixedHeader = fixedHeader
        self.bytes = bytes
    }
}

extension Array: MQTTDecodable where Element == MQTTPacket {
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        self.init()
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let decoded = try container.decode(MQTTPacket.self)
            self.append(decoded)
        }
    }
}

// MARK: 3.1 CONNECT – Connection Request

struct ConnectFlags: OptionSet, MQTTEncodable {
    let rawValue: UInt8

    static let cleanStart        = ConnectFlags(rawValue: 1 << 1)
    static let username          = ConnectFlags(rawValue: 1 << 7)
    static let password          = ConnectFlags(rawValue: 1 << 6)
}

public struct ConnectPacket: EncodablePacket {
    
    let fixedHeader: FixedHeader

    // Variable header
    let mqttName: String = MQTT.ProtocolName          // section 3.1.2.1 Protocol Name
    let mqttVersion: UInt8 = MQTT.ProtocolVersion     // section 3.1.2.2 Protocol Version
    let connectFlags: ConnectFlags  // TODO: section 3.1.2.3 Connect Flags
    let keepAlive: UInt16           // section 3.1.2.10 Keep Alive
    let propLength: UInt8 = 0       // TODO: section 3.1.2.11 CONNECT Properties
    
    // Payload
    let clientId: String
    let username: String?
    let password: String?
    
    public init(clientId: String, username: String? = nil, password: String? = nil, keepAlive: UInt16 = 10) throws {
        let variableHeaderLength = MQTT.ProtocolName.byteCount + 1 + 1 + 2 + 1
        let payloadlength = clientId.byteCount + (username?.byteCount ?? 0) + (password?.byteCount ?? 0)
        let remainingLength = try UIntVar(payloadlength + variableHeaderLength)
        self.fixedHeader = FixedHeader(controlOptions: [.connect, .reserved], remainingLength: remainingLength)
        self.clientId = clientId
        self.username = username
        self.password = password
        var connectFlags: ConnectFlags = []     // TODO: section 3.1.2.4 Clean Start Flag
        if username != nil {
            connectFlags.insert(.username)      // section 3.1.2.8 User Name Flag
        }
        if password != nil {
            connectFlags.insert(.password)      // section 3.1.2.9 Password Flag
        }
        self.connectFlags = connectFlags
        self.keepAlive = keepAlive

    }
}

// MARK: 3.2 CONNACK – Connect acknowledgement

struct ConnackFlags: OptionSet, MQTTDecodable {
    let rawValue: UInt8

    static let sessionPresent   = ConnackFlags(rawValue: 1 << 0)    // 3.2.2.1.1 Session Present
}

enum ConnackReason: UInt8, MQTTDecodable {
    case success                = 0x00  // Success: The Connection is accepted.
    case unspecifiedError       = 0x80  // Unspecified Error: The Server does not wish to reveal the reason for the failure, or none of the other Reason Codes apply.
    case malformedPacket        = 0x81  // Malformed Packet: Data within the CONNECT packet could not be correctly parsed.
    case protocolError          = 0x82  // Protocol Error: Data in the CONNECT packet does not conform to this specification.
    case implementationError    = 0x83  // Implementation specific error: The CONNECT is valid but is not accepted by this Server.
    case unsupportedVersion     = 0x84  // Unsupported Protocol Version: The Server does not support the version of the MQTT protocol requested by the Client.
    case invalidClientId        = 0x85  // Client Identifier not valid: The Client Identifier is a valid string but is not allowed by the Server.
    case invalidCredentials     = 0x86  // Bad User Name or Password: The Server does not accept the User Name or Password specified by the Client.
    case unauthorized           = 0x87  // Not authorized: The Client is not authorized to connect.
    case unavailable            = 0x88  // Server unavailable: The MQTT Server is not available.
    case busy                   = 0x89  // Server busy: The Server is busy. Try again later.
    case banned                 = 0x8A  // Banned: This Client has been banned by administrative action.
    case badAuthMethod          = 0x8C  // Bad authentication method: The authentication method is not supported or does not match the authentication method currently in use.
    case willTopicInvalid       = 0x90  // Topic Name invalid: The Will Topic Name is not malformed, but is not accepted by this Server.
    case packetTooLarge         = 0x95  // Packet too large: The CONNECT packet exceeded the maximum permissible size.
    case quotaExceeded          = 0x97  // Quota exceeded: An implementation or administrative imposed limit has been exceeded.
    case willPayloadInvalid     = 0x99  // Payload format invalid: The Will Payload does not match the specified Payload Format Indicator.
    case retainNotSupported     = 0x9A  // Retain not supported: The Server does not support retained messages, and Will Retain was set to 1.
    case willQoSNotSupported    = 0x9B  // QoS not supported: The Server does not support the QoS set in Will QoS.
    case useAnotherServer       = 0x9C  // Use another server: The Client should temporarily use another server.
    case serverMoved            = 0x9D  // Server moved: The Client should permanently use another server.
    case rateLimitExceeded      = 0x9F  // Connection rate exceeded: The connection rate limit has been exceeded.
}

struct ConnackPacket: DecodablePacket {
    
    let fixedHeader: FixedHeader
    
    // Variable Header
    let flags: ConnackFlags             // 3.2.2.1 Connect Acknowledge Flags
    let reasonCode: ConnackReason       // 3.2.2.2 Connect Reason Code
    
    // Properties
    var topicAliasMaximum: Int = 0
}

extension ConnackPacket: MQTTDecodable {
    
    enum Error: Swift.Error {
        case invalidPropertyIdentifier
    }
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.flags = try container.decode(ConnackFlags.self)
        self.reasonCode = try container.decode(ConnackReason.self)
        var bytesRemaining = Int(try container.decode(UIntVar.self))
        while  bytesRemaining > 0 && !container.isAtEnd {
            
            let x = container.currentIndex
            let propertyId = try container.decode(UIntVar.self)
            bytesRemaining -= container.currentIndex - x
            
            switch PropertyIdentifier(rawValue: UInt(propertyId)) {
            case .topicAliasMaximum:
                let aliasMax = try container.decode(UInt16.self)
                bytesRemaining -= MemoryLayout.size(ofValue: aliasMax)
                self.topicAliasMaximum = Int(aliasMax)
            default:
                throw Error.invalidPropertyIdentifier
            }
        }
    }
}

// MARK: 3.12 PINGREQ – PING request

struct PingReqPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.pingreq, .reserved], remainingLength: 0)
}

// MARK: 3.14 DISCONNECT – Disconnect notification

struct DisconnectPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.disconnect, .reserved], remainingLength: 0)
}
