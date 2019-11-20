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

enum QoS: UInt8, MQTTCodable {
    case qos0
    case qos1
    case qos2
}

struct ControlOptions: OptionSet, MQTTCodable {
    let rawValue: UInt8
    
    // Control Packet type
//    publish =     0x30
//    puback =      0x40
//    pubrec =      0x50
//    pubrel =      0x60
//    pubcomp =     0x70
//    unsubscribe = 0xa0
//    unsuback =    0xb0
    static let connect      = ControlOptions(rawValue: 1 << 4)
    static let connack      = ControlOptions(rawValue: 2 << 4)
    static let subscribe    = ControlOptions(rawValue: 8 << 4)
    static let suback       = ControlOptions(rawValue: 9 << 4)
    static let pingreq      = ControlOptions(rawValue: 12 << 4)
    static let pingresp     = ControlOptions(rawValue: 13 << 4)
    static let disconnect   = ControlOptions(rawValue: 14 << 4)
    
    // Flags specific to each Control Packet type
    static let reserved0    = ControlOptions(rawValue: 0)
    static let reserved1    = ControlOptions(rawValue: 1 << 1)
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
        var bytes: [UInt8] = try MQTTEncoder.encode(fixedHeader)
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
        self.fixedHeader = FixedHeader(controlOptions: [.connect, .reserved0], remainingLength: remainingLength)
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
    case success                = 0x00
    case unspecifiedError       = 0x80
    case malformedPacket        = 0x81
    case protocolError          = 0x82
    case implementationError    = 0x83
    case unsupportedVersion     = 0x84
    case invalidClientId        = 0x85
    case invalidCredentials     = 0x86
    case unauthorized           = 0x87
    case unavailable            = 0x88
    case busy                   = 0x89
    case banned                 = 0x8A
    case badAuthMethod          = 0x8C
    case willTopicInvalid       = 0x90
    case packetTooLarge         = 0x95
    case quotaExceeded          = 0x97
    case willPayloadInvalid     = 0x99
    case retainNotSupported     = 0x9A
    case willQoSNotSupported    = 0x9B
    case useAnotherServer       = 0x9C
    case serverMoved            = 0x9D
    case rateLimitExceeded      = 0x9F
}

struct ConnackPacket: DecodablePacket {
    
    let fixedHeader: FixedHeader
    
    // Variable Header
    let flags: ConnackFlags             // 3.2.2.1 Connect Acknowledge Flags
    let reasonCode: ConnackReason       // 3.2.2.2 Connect Reason Code
    
    // Payload
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

// MARK: 3.8 SUBSCRIBE - Subscribe request

struct SubscriptionOptions: OptionSet, MQTTEncodable {     // 3.8.3.1 Subscription Options
    let rawValue: UInt8

    static let qos0                         = SubscriptionOptions(rawValue: QoS.qos0.rawValue)
    static let qos1                         = SubscriptionOptions(rawValue: QoS.qos1.rawValue)
    static let qos2                         = SubscriptionOptions(rawValue: QoS.qos2.rawValue)
    
    static let noLocal                      = SubscriptionOptions(rawValue: 1 << 2)
    
    static let retainAsPublished            = SubscriptionOptions(rawValue: 1 << 3)
    
    static let retainSendOnSubscribe        = SubscriptionOptions(rawValue: 0 << 4)
    static let retainSendIfNewSubscription  = SubscriptionOptions(rawValue: 1 << 4)
    static let retainDoNotSend              = SubscriptionOptions(rawValue: 2 << 4)
}

struct SubscribePacket: EncodablePacket {
    
    let fixedHeader: FixedHeader

    // Variable Header
    let packetId: UInt16
    let propertyLength: UIntVar = 0

    // Payload
    let topicFilter: String
    let options: SubscriptionOptions

    public init(topicFilter: String, packetId: UInt16, options: SubscriptionOptions = [.qos0, .retainSendOnSubscribe]) throws {
        let variableHeaderLength: UInt = 2 + 1 + 0 + 0 + 0 // 2 byte packetIdentifier + property length value + subscriptionID byte + subscription ID byte count + user property byte count
        let payloadlength = topicFilter.byteCount + 1 // byte count of the topic + byte count of the options for that topic
        let remainingLength = try UIntVar(payloadlength + variableHeaderLength)

        self.fixedHeader = FixedHeader(controlOptions: [.subscribe, .reserved1], remainingLength: remainingLength)
        self.packetId = packetId
        self.topicFilter = topicFilter
        self.options = options
    }
}

// MARK: 3.9 SUBACK – Subscribe acknowledgement

enum SubscriptionError: UInt8, MQTTDecodable, Error {
    case unspecifiedError               = 0x80
    case implementaionSpecificError     = 0x83
    case notAuthorized                  = 0x87
    case topicFilterInvalid             = 0x8F
    case packetIdInUse                  = 0x91
    case quotaExceeded                  = 0x97
    case sharedSubscriptionsUnsupported = 0x9E
    case subscriptionIdsUnsupported     = 0xA1
    case wildcardsUnsupported           = 0xA2
}
    
struct SubackPacket: DecodablePacket {
    
    enum Error: Swift.Error {
        case notImplemented
    }
    
    let fixedHeader: FixedHeader
    
    let packetId: UInt16                // 3.9.2 SUBACK Variable Header
    let propertyLength: UIntVar         // 3.9.2.1.1 Property Length
    
    let qos: QoS?
    let error: SubscriptionError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        let propertyLength = try container.decode(UIntVar.self)
        if 0 < Int(propertyLength) {
            throw Error.notImplemented
        }
        self.propertyLength = propertyLength
        if let qos = try? container.decode(QoS.self) {
            self.qos = qos
            self.error = nil
        } else {
            self.qos = nil
            self.error = try container.decode(SubscriptionError.self)
        }
    }
}

// MARK: 3.12 PINGREQ – PING request

struct PingReqPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.pingreq, .reserved0], remainingLength: 0)
}

// MARK: 3.14 DISCONNECT – Disconnect notification

struct DisconnectPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.disconnect, .reserved0], remainingLength: 0)
}
