//
//  NextMQTT
//
//  Copyright (c) Ben Stovold 2019
//  MIT license, see LICENSE file for details
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

fileprivate enum Success: UInt8, MQTTDecodable {
    case success = 0x00
}

extension MQTT.QoS: MQTTCodable {}

enum PacketType: UInt8 {
    case connect      = 1
    case connack      = 2
    case publish      = 3
    case puback       = 4
    case pubrec       = 5
    case pubrel       = 6
    case pubcomp      = 7
    case subscribe    = 8
    case suback       = 9
    case unsubscribe  = 10
    case unsuback     = 11
    case pingreq      = 12
    case pingresp     = 13
    case disconnect   = 14
}

struct ControlOptions: OptionSet, MQTTCodable {
    let rawValue: UInt8
    
    // 2.1.2 MQTT Control Packet type
    var packetType: PacketType {
        return PacketType(rawValue: self.rawValue >> 4)!
    }
    
    static func packetType(_ packetType: PacketType) -> Self {
        ControlOptions(rawValue: packetType.rawValue << 4)
    }
    
    // 2.1.3 Flags specific to each MQTT Control Packet type
    
    // CONNECT, CONNACK, PUBACK, PUBREC, PUBCOMP, SUBACK, UNSUBACK, PINGREQ, PINGRESP, DISCONNECT, AUTH
    static let reserved0    = ControlOptions(rawValue: 0)
    
    // PUBREL, SUBSCRIBE, UNSUBSCRIBE
    static let reserved1    = ControlOptions(rawValue: 1 << 1)
    
    // PUBLISH
    static let retain       = ControlOptions(rawValue: 1 << 0)
    static func qos(_ qos: MQTT.QoS) -> Self {
        ControlOptions(rawValue: qos.rawValue << 1)
    }
    static let dup          = ControlOptions(rawValue: 1 << 2)
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
protocol CodablePacket: EncodablePacket, DecodablePacket {}

// MARK: Generic Decodable MQTT Packet

/**
 A type for decoding a generic MQTT packet.
 
 Decodes only the fixed header, marshalling _all_ bytes for the packet (including fixed and
 variable headers and any payload) into the `bytes` property.
 
 Used to decode the inbound bytestream from an MQTT server to correctly separate packets and
 determine their type (from the fixed header) for further processing.
*/
struct MQTTPacket: DecodablePacket {
    let fixedHeader: FixedHeader
    
    /// All of the contiguous bytes for the packet, incl. the fixed header.
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

struct ConnectPacket: EncodablePacket {
    
    let fixedHeader: FixedHeader

    // Variable header
    let mqttName: String = MQTT.ProtocolName          // section 3.1.2.1 Protocol Name
    let mqttVersion: UInt8 = MQTT.ProtocolVersion     // section 3.1.2.2 Protocol Version
    let connectFlags: ConnectFlags  // section 3.1.2.3 Connect Flags
    let keepAlive: UInt16           // section 3.1.2.10 Keep Alive
    let propLength: UInt8           // section 3.1.2.11 CONNECT Properties
    let sessionExpiryFlag: UInt8?
    let sessionExpiryInterval: UInt32?
    
    // Payload
    let clientId: String
    let username: String?
    let password: String?
    
    init(clientId: String, username: String? = nil, password: String? = nil, keepAlive: UInt16 = 10, cleanStart: Bool = false, sessionExpiry: UInt32 = 0) throws {
        let propLength: UInt8 = (sessionExpiry > 0) ? 5 : 0
        let variableHeaderLength = MQTT.ProtocolName.byteCount + 1 + 1 + 2 + 1 + UInt(propLength)
        let payloadlength = clientId.byteCount + (username?.byteCount ?? 0) + (password?.byteCount ?? 0)
        let remainingLength = try UIntVar(payloadlength + variableHeaderLength)
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.connect), .reserved0], remainingLength: remainingLength)
        self.clientId = clientId
        self.username = username
        self.password = password
        var connectFlags: ConnectFlags = []
        if cleanStart {
            connectFlags.insert(.cleanStart)     // section 3.1.2.4 Clean Start Flag
        }
        if username != nil {
            connectFlags.insert(.username)      // section 3.1.2.8 User Name Flag
        }
        if password != nil {
            connectFlags.insert(.password)      // section 3.1.2.9 Password Flag
        }
        self.connectFlags = connectFlags
        self.keepAlive = keepAlive
        self.propLength = propLength
        if sessionExpiry > 0 {
            self.sessionExpiryFlag = 0x11
            self.sessionExpiryInterval = 120
        } else {
            self.sessionExpiryFlag = nil
            self.sessionExpiryInterval = nil
        }
    }
}

// MARK: 3.2 CONNACK – Connect acknowledgement

struct ConnackFlags: OptionSet, MQTTDecodable {
    let rawValue: UInt8

    static let sessionPresent   = ConnackFlags(rawValue: 1 << 0)    // 3.2.2.1.1 Session Present
}

public extension MQTT {
    enum ConnectError: UInt8, Error {
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
}

extension MQTT.ConnectError: MQTTDecodable {}

struct ConnackPacket: DecodablePacket {
    
    let fixedHeader: FixedHeader
    
    let flags: ConnackFlags             // 3.2.2.1 Connect Acknowledge Flags
    let error: MQTT.ConnectError?
    
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

        if let _ = try? container.decode(Success.self) {
            self.error = nil
        } else {
            self.error = try container.decode(MQTT.ConnectError.self)
        }
        
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

// MARK: 3.3 PUBLISH – Publish message

public extension MQTT {
    enum PublishError: UInt8, Error {
        case noMatchingSubscribers          = 0x10
        case unspecifiedError               = 0x80
        case implementaionSpecificError     = 0x83
        case notAuthorized                  = 0x87
        case topicNameInvalid               = 0x90
        case packetIdInUse                  = 0x91
        case packetIdNotFound               = 0x92
        case quotaExceeded                  = 0x97
        case payloadFormatInvalid           = 0x99
    }
}

extension MQTT.PublishError: MQTTCodable {}

struct PublishPacket: CodablePacket {
    
    enum Error: Swift.Error {
        case notImplemented
    }
    
    let fixedHeader: FixedHeader
    
    let topicName: String
    let packetId: UInt16?
    let propertyLength: UInt8
    let message: Data?
    
    init(topicName: String, qos: MQTT.QoS, packetId: UInt16? = nil, message: Data?) throws {
        precondition((qos == .mostOnce && packetId == nil) || (qos != .mostOnce && packetId != nil))
        let packetIdLength: UInt = (packetId != nil) ? 2 : 0
        let variableHeaderLength = topicName.byteCount + packetIdLength + 1 // topic + packetId + propertyLength
        let payloadLength = UInt(message?.count ?? 0)
        let remainingLength = try UIntVar(variableHeaderLength + payloadLength)
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.publish), .qos(qos)], remainingLength: remainingLength)
        self.topicName = topicName
        self.packetId = packetId
        self.propertyLength = 0
        self.message = message
    }
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.topicName = try container.decode(String.self)
        let opts = self.fixedHeader.controlOptions
        if opts.contains(.qos(.leastOnce)) || opts.contains(.qos(.exactlyOnce)) {
            self.packetId = try container.decode(UInt16.self)
        } else {
            self.packetId = nil
        }
        self.propertyLength = try container.decode(UInt8.self)
        self.message = try? container.decode(Data.self)
    }
}

// MARK: 3.4 PUBACK – Publish acknowledgement

struct PubackPacket: CodablePacket {
    
    let fixedHeader: FixedHeader
    let packetId: UInt16                // 3.4.2 PUBACK Variable Header
    let error: MQTT.PublishError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        self.error = (try? container.decode(MQTT.PublishError.self)) ?? nil
    }
    
    init(packetId: UInt16, error: MQTT.PublishError? = nil) {
        let remainingLength: UIntVar = (error == nil) ? 2 : 3
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.puback), .reserved0], remainingLength: remainingLength)
        self.packetId = packetId
        self.error = error
    }
}

// MARK: 3.5 PUBREC – Publish received (QoS 2 delivery part 1)

struct PubrecPacket: CodablePacket {
    
    let fixedHeader: FixedHeader
    let packetId: UInt16                // 3.5.2 PUBREC Variable Header
    let error: MQTT.PublishError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        self.error = (try? container.decode(MQTT.PublishError.self)) ?? nil
    }
    
    init(packetId: UInt16, error: MQTT.PublishError? = nil) {
        let remainingLength: UIntVar = (error == nil) ? 2 : 3
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.pubrec), .reserved0], remainingLength: remainingLength)
        self.packetId = packetId
        self.error = error
    }
}

// MARK: 3.6 PUBREL – Publish release (QoS 2 delivery part 2)

struct PubrelPacket: CodablePacket {
    
    let fixedHeader: FixedHeader
    let packetId: UInt16                // 3.6.2 PUBREL Variable Header
    let error: MQTT.PublishError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        self.error = (try? container.decode(MQTT.PublishError.self)) ?? nil
    }
    
    init(packetId: UInt16, error: MQTT.PublishError? = nil) {
        precondition(error == nil || error == .packetIdNotFound, "Invalid PUBREL error, expected 0x92 PacketId Not Found")
        let remainingLength: UIntVar = (error == nil) ? 2 : 3
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.pubrel), .reserved1], remainingLength: remainingLength)
        self.packetId = packetId
        self.error = error
    }
}

// MARK: 3.7 PUBCOMP – Publish complete (QoS 2 delivery part 3)

struct PubcompPacket: CodablePacket {
    
    let fixedHeader: FixedHeader
    let packetId: UInt16                // 3.7.2 PUBCOMP Variable Header
    let error: MQTT.PublishError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        self.error = (try? container.decode(MQTT.PublishError.self)) ?? nil
    }
    
    init(packetId: UInt16, error: MQTT.PublishError? = nil) {
        precondition(error == nil || error == .packetIdNotFound, "Invalid PUBCOMP error, expected 0x92 PacketId Not Found")
        let remainingLength: UIntVar = (error == nil) ? 2 : 3
        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.pubcomp), .reserved0], remainingLength: remainingLength)
        self.packetId = packetId
        self.error = error
    }
}

// MARK: 3.8 SUBSCRIBE - Subscribe request

public extension MQTT {
    
    struct SubscribeOptions: OptionSet, MQTTEncodable {     // 3.8.3.1 Subscription Options
        public let rawValue: UInt8
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static func qos(_ qos: MQTT.QoS) -> Self {
            SubscribeOptions(rawValue: qos.rawValue)
        }
        
        public static let noLocal                      = SubscribeOptions(rawValue: 1 << 2)
        
        public static let retainAsPublished            = SubscribeOptions(rawValue: 1 << 3)
        
        public static let retainSendOnSubscribe        = SubscribeOptions(rawValue: 0 << 4)
        public static let retainSendIfNewSubscription  = SubscribeOptions(rawValue: 1 << 4)
        public static let retainDoNotSend              = SubscribeOptions(rawValue: 2 << 4)
    }
}

struct SubscribePacket: EncodablePacket {
    
    let fixedHeader: FixedHeader

    // Variable Header
    let packetId: UInt16
    let propertyLength: UIntVar = 0

    // Payload
    let topicFilter: String
    let options: MQTT.SubscribeOptions

    init(topicFilter: String, packetId: UInt16, options: MQTT.SubscribeOptions) throws {
        let variableHeaderLength: UInt = 2 + 1 + 0 + 0 + 0 // 2 byte packetIdentifier + property length value + subscriptionID byte + subscription ID byte count + user property byte count
        let payloadlength = topicFilter.byteCount + 1 // byte count of the topic + byte count of the options for that topic
        let remainingLength = try UIntVar(payloadlength + variableHeaderLength)

        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.subscribe), .reserved1], remainingLength: remainingLength)
        self.packetId = packetId
        self.topicFilter = topicFilter
        self.options = options
    }
}

// MARK: 3.9 SUBACK – Subscribe acknowledgement

public extension MQTT {
    enum SubscribeError: UInt8, Error {
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
}

extension MQTT.SubscribeError: MQTTDecodable {}

struct SubackPacket: DecodablePacket {
    
    enum Error: Swift.Error {
        case notImplemented
    }
    
    let fixedHeader: FixedHeader
    
    let packetId: UInt16                // 3.9.2 SUBACK Variable Header
    let propertyLength: UIntVar         // 3.9.2.1.1 Property Length
    
    let qos: MQTT.QoS?
    let error: MQTT.SubscribeError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        let propertyLength = try container.decode(UIntVar.self)
        if 0 < Int(propertyLength) {
            throw Error.notImplemented
        }
        self.propertyLength = propertyLength
        if let qos = try? container.decode(MQTT.QoS.self) {
            self.qos = qos
            self.error = nil
        } else {
            self.qos = nil
            self.error = try container.decode(MQTT.SubscribeError.self)
        }
    }
}

// MARK: 3.10 UNSUBSCRIBE – Unsubscribe request

struct UnsubscribePacket: EncodablePacket {
    
    let fixedHeader: FixedHeader

    // Variable Header
    let packetId: UInt16
    let propertyLength: UIntVar = 0

    // Payload
    let topicFilter: String

    public init(topicFilter: String, packetId: UInt16) throws {
        let variableHeaderLength: UInt = 2 + 1 + 0 + 0 // 2 byte packetIdentifier + property length value + user property byte + user property byte count
        let payloadlength = topicFilter.byteCount
        let remainingLength = try UIntVar(payloadlength + variableHeaderLength)

        self.fixedHeader = FixedHeader(controlOptions: [.packetType(.unsubscribe), .reserved1], remainingLength: remainingLength)
        self.packetId = packetId
        self.topicFilter = topicFilter
    }
}

// MARK: 3.11 UNSUBACK – Unsubscribe acknowledgement

fileprivate enum UnsubscribeSuccess: UInt8, MQTTDecodable {
    case success = 0x00
}

public enum UnsubscribeError: UInt8, MQTTDecodable, Error {
    case noSubscriptionExisted          = 0x11
    case unspecifiedError               = 0x80
    case implementaionSpecificError     = 0x83
    case notAuthorized                  = 0x87
    case topicFilterInvalid             = 0x8F
    case packetIdInUse                  = 0x91
}
    
struct UnsubackPacket: DecodablePacket {
    
    enum Error: Swift.Error {
        case notImplemented
    }
    
    let fixedHeader: FixedHeader
    
    let packetId: UInt16                // 3.11.2 UNSUBACK Variable Header
    let propertyLength: UIntVar         // 3.11.2.1.1 Property Length
    
    let error: UnsubscribeError?
    
    init(fromMQTTDecoder decoder: MQTTDecoder) throws {
        var container = try decoder.unkeyedContainer()
        self.fixedHeader = try container.decode(FixedHeader.self)
        self.packetId = try container.decode(UInt16.self)
        let propertyLength = try container.decode(UIntVar.self)
        if 0 < Int(propertyLength) {
            throw Error.notImplemented
        }
        self.propertyLength = propertyLength
        if let _ = try? container.decode(UnsubscribeSuccess.self) {
            self.error = nil
        } else {
            self.error = try container.decode(UnsubscribeError.self)
        }
    }
}

// MARK: 3.12 PINGREQ – PING request

struct PingReqPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.packetType(.pingreq), .reserved0], remainingLength: 0)
}

// MARK: 3.14 DISCONNECT – Disconnect notification

struct DisconnectPacket: EncodablePacket {
    let fixedHeader: FixedHeader = FixedHeader(controlOptions: [.packetType(.disconnect), .reserved0], remainingLength: 0)
}
