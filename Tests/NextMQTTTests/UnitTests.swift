import XCTest
@testable import NextMQTT

// MARK: - UIntVar tests

final class UIntVarTests: XCTestCase {
    static var allTests = [
        // UIntVar
        ("testUIntVarDescription", testUIntVarDescription),
        ("testUIntVarValueTooLarge", testUIntVarValueTooLarge),
        ("testUIntVarMQTTEncode", testUIntVarMQTTEncode),
        ("testUIntVarZeroByteMQTTEncode", testUIntVarZeroByteMQTTEncode),
        ("testUIntVarMQTTDecodeFixedBytes", testUIntVarMQTTDecodeFixedBytes),
        ("testUIntVarMQTTDecodeByteStream", testUIntVarMQTTDecodeByteStream),
        ("testUIntVarMQTTDecodeInvalidBytes", testUIntVarMQTTDecodeInvalidBytes),
    ]
    
    func testUIntVarDescription() {
         XCTAssertEqual("0", UIntVar.min.description)
         XCTAssertEqual("268435455", UIntVar.max.description)
         XCTAssertEqual("12345678", try UIntVar(12345678 as UInt).description)
         XCTAssertEqual("1", UIntVar(1).description)
         XCTAssertEqual("8388608", try UIntVar(1 << 23).description)
         XCTAssertEqual("66", UIntVar(66).description)
     }
     
     func testUIntVarValueTooLarge() {
         var error: Error?
         XCTAssertThrowsError(try UIntVar(268435456 as UInt)) { error = $0 }
         XCTAssertTrue(error is UIntVar.Error)
         XCTAssertEqual(error as? UIntVar.Error, .valueTooLarge)
     }
     
     func testUIntVarMQTTEncode() {
         let aVarUInt: UIntVar = 123458909
         let expected: [UInt8] = [221, 170, 239, 58]
         let actual: [UInt8] = try! MQTTEncoder.encode(aVarUInt)
         XCTAssertEqual(expected, actual)
     }
     
     func testUIntVarZeroByteMQTTEncode() {
         let aVarUInt: UIntVar = 0
         let expected: [UInt8] = [0]
         let actual: [UInt8] = try! MQTTEncoder.encode(aVarUInt)
         XCTAssertEqual(expected, actual)
     }
     
     func testUIntVarMQTTDecodeFixedBytes() {
         let bytes: [UInt8] = [221, 170, 239, 58]
         let expected: UIntVar = 123458909
         let actual: UIntVar = try! MQTTDecoder.decode(UIntVar.self, data: bytes)
         XCTAssertEqual(expected, actual)
     }
     
     func testUIntVarMQTTDecodeByteStream() {
         let bytes: [UInt8] = [255, 255, 255, 127, 128]
         let expected: UIntVar = 268435455
         let actual: UIntVar = try! MQTTDecoder.decode(UIntVar.self, data: bytes)
         XCTAssertEqual(expected, actual)
     }
     
     func testUIntVarMQTTDecodeInvalidBytes() {
         var error: Error?
         let bytes: [UInt8] = [255, 255, 255, 128]
         XCTAssertThrowsError(try MQTTDecoder.decode(UIntVar.self, data: bytes)) { error = $0 }
         guard case .invalidUIntVar = (error as! MQTTDecoder.Error) else {
             return XCTAssert(false, "Expected .invalidUIntVar but got \(String(describing: error))")
         }
     }
}

// MARK: - Packet tests

final class PacketTests: XCTestCase {
    
    static var allTests = [
        ("testFixedHeaderEncode", testFixedHeaderEncode),
        ("testFixedHeaderDecode", testFixedHeaderDecode),
        ("testConnectPacketEncode", testConnectPacketEncode),
        ("testConnectPacketEncodeWithUserPasswordPing", testConnectPacketEncodeWithUserPasswordPing),
        ("testConnackPacketDecode", testConnackPacketDecode),
        ("testBadConnackPacket", testBadConnackPacket),
        ("testPingReqPacketEncode", testPingReqPacketEncode),
        ("testDisconnectPacketEncode", testDisconnectPacketEncode),
        ("testSubscribePacketEncode", testSubscribePacketEncode),
        ("testSubscribePacketWithOptionsEncode", testSubscribePacketWithOptionsEncode),
        ("testSubackPacketDecode", testSubackPacketDecode),
        ("testSubackPacketErrorDecode", testSubackPacketErrorDecode),
        ("testUnsupportedSubackPacket", testUnsupportedSubackPacket),
        ("testBadSubackPacket", testBadSubackPacket),
        ("testUnsubscribePacketEncode", testUnsubscribePacketEncode),
        ("testUnsubackPacketDecode", testUnsubackPacketDecode),
        ("testUnsubackPacketErrorDecode", testUnsubackPacketErrorDecode),
        ("testPublishPacketEncode", testPublishPacketEncode),
        ("testPublishPacketDecode", testPublishPacketDecode)
    ]

    private struct TestPayload: Encodable {
        let a = "a"
        let b = "b"
    }
    
    func testFixedHeaderEncode() {
        let header = FixedHeader(controlOptions: [.packetType(.disconnect), .reserved0], remainingLength: 0)
        let expected: [UInt8] = [224, 0]
        let actual = try! MQTTEncoder.encode(header)
        XCTAssertEqual(expected, actual)
    }
    
    func testFixedHeaderDecode() {
        let bytes: [UInt8] = [32, 6]
        let fixedHeader = try! MQTTDecoder.decode(FixedHeader.self, data: bytes)
        XCTAssertEqual(fixedHeader.controlOptions.packetType, .connack)
        XCTAssertEqual(fixedHeader.remainingLength, 6)
    }
    
    func testConnectPacketEncode() {
        let connect = try! ConnectPacket(clientId: "123")
        let expected: [UInt8] = [16, 16, 0, 4, 77, 81, 84, 84, 5, 0, 0, 10, 0, 0, 3, 49, 50, 51]
        let actual = try! MQTTEncoder.encode(connect)
        XCTAssertEqual(expected, actual)
    }
    
    func testConnectPacketEncodeWithUserPasswordPing() {
        let connect = try! ConnectPacket(clientId: "123", username: "A", password: "B", keepAlive: 22)
        let expected: [UInt8] = [16, 22, 0, 4, 77, 81, 84, 84, 5, 192, 0, 22, 0, 0, 3, 49, 50, 51, 0, 1, 65, 0, 1, 66]
        let actual = try! MQTTEncoder.encode(connect)
        XCTAssertEqual(expected, actual)
    }
    
    func testConnectPacketEncodeWithCleanStart() {
        let connect = try! ConnectPacket(clientId: "123", cleanStart: true)
        let expected: [UInt8] = [16, 16, 0, 4, 77, 81, 84, 84, 5, 2, 0, 10, 0, 0, 3, 49, 50, 51]
        let actual = try! MQTTEncoder.encode(connect)
        XCTAssertEqual(expected, actual)
    }
    
    func testConnectPacketEncodeWithSessionExpiry() {
        let connect = try! ConnectPacket(clientId: "123", sessionExpiry: 120)
        let expected: [UInt8] = [16, 21, 0, 4, 77, 81, 84, 84, 5, 0, 0, 10, 5, 17, 0, 0, 0, 120, 0, 3, 49, 50, 51]
        let actual = try! MQTTEncoder.encode(connect)
        XCTAssertEqual(expected, actual)
    }
    
    func testConnackPacketDecode() {
        let bytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0, 10]
        let connack = try! MQTTDecoder.decode(ConnackPacket.self, data: bytes)
        XCTAssertEqual(connack.fixedHeader.controlOptions.packetType, .connack)
        XCTAssertEqual(Int(connack.fixedHeader.remainingLength), 6)
        XCTAssertFalse(connack.flags.contains(.sessionPresent))
        XCTAssertNil(connack.error)
        XCTAssertEqual(connack.topicAliasMaximum, 10)
    }
    
    func testConnackPacketErrorDecode() {
        let bytes: [UInt8] = [32, 3, 0, 151, 3]
        let connack = try! MQTTDecoder.decode(ConnackPacket.self, data: bytes)
        XCTAssertEqual(connack.fixedHeader.controlOptions.packetType, .connack)
        XCTAssertEqual(connack.error, .quotaExceeded)
    }

    func testBadConnackPacket() {
        var error: Error?
        let bytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0]
        XCTAssertThrowsError(try MQTTDecoder.decode(ConnackPacket.self, data: bytes)) { error = $0 }
        guard case .prematureEndOfData = (error as! MQTTDecoder.Error) else {
            return XCTAssert(false, "Expected .prematureEndOfData but got \(String(describing: error))")
        }
    }
    
    func testPingReqPacketEncode() {
        let packet = PingReqPacket()
        let expected: [UInt8] = [192, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testDisconnectPacketEncode() {
        let packet = DisconnectPacket()
        let expected: [UInt8] = [224, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testSubscribePacketEncode() {
        let packet = try! SubscribePacket(topicFilter: "a/b", packetId: 10, options: [.qos(.mostOnce)])
        let expected: [UInt8] = [130, 9, 0, 10, 0, 0, 3, 97, 47, 98, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testSubscribePacketWithOptionsEncode() {
        let packet = try! SubscribePacket(topicFilter: "a/b/c/d", packetId: 65535, options: [.qos(.exactlyOnce)])
        let expected: [UInt8] = [130, 13, 255, 255, 0, 0, 7, 97, 47, 98, 47, 99, 47, 100, 2]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testSubackPacketDecode() {
        let bytes: [UInt8] = [144, 4, 0, 10, 0, 2]
        let suback = try! MQTTDecoder.decode(SubackPacket.self, data: bytes)
        XCTAssertEqual(suback.fixedHeader.controlOptions.packetType, .suback)
        XCTAssertEqual(Int(suback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(suback.qos, .exactlyOnce)
    }
    
    func testSubackPacketErrorDecode() {
        let bytes: [UInt8] = [144, 4, 255, 255, 0, 143]
        let suback = try! MQTTDecoder.decode(SubackPacket.self, data: bytes)
        XCTAssertEqual(suback.fixedHeader.controlOptions.packetType, .suback)
        XCTAssertEqual(Int(suback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(suback.error, .topicFilterInvalid)
    }

    // this test will need to go when user properties and/ or reason string support is addded
    func testUnsupportedSubackPacket() {
        var error: Error?
        let bytes: [UInt8] = [144, 8, 0, 1, 4, 31, 0, 1, 97, 0]   // 4 is property length, 31 is Reason String Id; [0, 1, 97] is "a"
        XCTAssertThrowsError(try MQTTDecoder.decode(SubackPacket.self, data: bytes)) { error = $0 }
        guard case .notImplemented = (error as! SubackPacket.Error) else {
            return XCTAssert(false, "Expected .notImplemented but got \(String(describing: error))")
        }
    }
    
    func testBadSubackPacket() {
        var error: Error?
        let bytes: [UInt8] = [144, 4, 0]
        XCTAssertThrowsError(try MQTTDecoder.decode(SubackPacket.self, data: bytes)) { error = $0 }
        guard case .prematureEndOfData = (error as! MQTTDecoder.Error) else {
            return XCTAssert(false, "Expected .prematureEndOfData but got \(String(describing: error))")
        }
    }
    
    func testUnsubscribePacketEncode() {
        let packet = try! UnsubscribePacket(topicFilter: "a/c", packetId: 12)
        let expected: [UInt8] = [162, 8, 0, 12, 0, 0, 3, 97, 47, 99]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testUnsubackPacketDecode() {
        let bytes: [UInt8] = [176, 4, 0, 12, 0, 0]
        let unsuback = try! MQTTDecoder.decode(UnsubackPacket.self, data: bytes)
        XCTAssertEqual(unsuback.fixedHeader.controlOptions.packetType, .unsuback)
        XCTAssertEqual(Int(unsuback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(unsuback.packetId, 12)
    }

    func testUnsubackPacketErrorDecode() {
        let bytes: [UInt8] = [176, 4, 0, 13, 0, 17]
        let unsuback = try! MQTTDecoder.decode(UnsubackPacket.self, data: bytes)
        XCTAssertEqual(unsuback.packetId, 13)
        XCTAssertEqual(unsuback.error, .noSubscriptionExisted)
    }

    func testPublishPacketEncode() {
        let payload = TestPayload()
        let message = try! JSONEncoder().encode(payload)
        let publish = try! PublishPacket(topicName: "a/c", qos: .mostOnce, message: message)
        let remainingLength = UInt8(6 + message.count)
        let expected: [UInt8] = [48, remainingLength, 0, 3, 97, 47, 99, 0] + [UInt8](message)
        let actual = try! MQTTEncoder.encode(publish)
        XCTAssertEqual(expected, actual)
    }
    
    func testPublishPacketQoS2NoMessageEncode() {
        let publish = try! PublishPacket(topicName: "a/c", qos: .exactlyOnce, packetId: 5, message: nil)
        let expected: [UInt8] = [52, 8, 0, 3, 97, 47, 99, 0, 5, 0]
        let actual = try! MQTTEncoder.encode(publish)
        XCTAssertEqual(expected, actual)
    }
    
    func testPublishPacketDecode() {
        let fixedHeader: [UInt8] = [48, 16]
        let topic: [UInt8] = [0, 5, 47, 112, 111, 110, 103] // "/pong" as mqtt string
        let propertyLength: [UInt8] = [0]
        let message: [UInt8] = [84, 114, 121, 32, 84, 104, 105, 115] // "Try This" as utf8
        let bytes: [UInt8] = fixedHeader + topic + propertyLength + message
        let publish = try! MQTTDecoder.decode(PublishPacket.self, data: bytes)
        XCTAssertEqual(publish.fixedHeader.controlOptions.packetType, .publish)
        XCTAssertEqual(publish.fixedHeader.remainingLength, 16)
        XCTAssertEqual(publish.topicName, "/pong")
        XCTAssertEqual(publish.propertyLength, 0)
        XCTAssertEqual(publish.message, "Try This".data(using: .utf8))
    }
    
    func testPublishPacketQoS1Decode() {
        let fixedHeader: [UInt8] = [50, 16]
        let topic: [UInt8] = [0, 5, 47, 112, 111, 110, 103] // "/pong" as mqtt string
        let packetId: [UInt8] = [0, 12]
        let propertyLength: [UInt8] = [0]
        let message: [UInt8] = [84, 114, 121, 32, 84, 104, 105, 115] // "Try This" as utf8
        let bytes: [UInt8] = fixedHeader + topic + packetId + propertyLength + message
        let publish = try! MQTTDecoder.decode(PublishPacket.self, data: bytes)
        XCTAssert(publish.fixedHeader.controlOptions.contains(.qos(.leastOnce)))
        XCTAssertEqual(publish.fixedHeader.remainingLength, 16)
        XCTAssertEqual(publish.topicName, "/pong")
        XCTAssertEqual(publish.propertyLength, 0)
        XCTAssertEqual(publish.message, "Try This".data(using: .utf8))
    }
    
    func testPublishPacketQoS2Decode() {
        let fixedHeader: [UInt8] = [52, 10]
        let topic: [UInt8] = [0, 5, 47, 112, 111, 110, 103] // "/pong" as mqtt string
        let packetId: [UInt8] = [0, 11]
        let propertyLength: [UInt8] = [0]
        let bytes: [UInt8] = fixedHeader + topic + packetId + propertyLength
        let publish = try! MQTTDecoder.decode(PublishPacket.self, data: bytes)
        XCTAssert(publish.fixedHeader.controlOptions.contains(.qos(.exactlyOnce)))
        XCTAssertEqual(publish.fixedHeader.remainingLength, 10)
        XCTAssertEqual(publish.topicName, "/pong")
        XCTAssertEqual(publish.propertyLength, 0)
    }
    
    func testPubackDecode() {
        let bytes: [UInt8] = [64, 2, 0, 15]
        let puback = try! MQTTDecoder.decode(PubackPacket.self, data: bytes)
        XCTAssertEqual(puback.fixedHeader.controlOptions.packetType, .puback)
        XCTAssertEqual(puback.fixedHeader.remainingLength, 2)
        XCTAssertEqual(puback.packetId, 15)
    }
    
    func testPubackWithReasonCodeDecode() {
        let bytes: [UInt8] = [64, 3, 0, 1, 16]
        let puback = try! MQTTDecoder.decode(PubackPacket.self, data: bytes)
        XCTAssertEqual(puback.fixedHeader.controlOptions.packetType, .puback)
        XCTAssertEqual(puback.fixedHeader.remainingLength, 3)
        XCTAssertEqual(puback.packetId, 1)
        XCTAssertEqual(puback.error, .noMatchingSubscribers)
    }
    
    func testPubackEncode() {
        let puback = PubackPacket(packetId: 1)
        let expected: [UInt8] = [64, 2, 0, 1]
        let actual = try! MQTTEncoder.encode(puback)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubackWithReasonCodeEncode() {
        let puback = PubackPacket(packetId: 12, error: .unspecifiedError)
        let expected: [UInt8] = [64, 3, 0, 12, 128]
        let actual = try! MQTTEncoder.encode(puback)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubrecDecode() {
        let bytes: [UInt8] = [80, 2, 0, 15]
        let decoder = MQTTDecoder(data: bytes)
        let pubrec = try! decoder.decode(PubrecPacket.self)
        XCTAssertEqual(pubrec.fixedHeader.controlOptions.packetType, .pubrec)
        XCTAssertEqual(pubrec.fixedHeader.remainingLength, 2)
        XCTAssertEqual(pubrec.packetId, 15)
    }
    
    func testPubrecWithReasonCodeDecode() {
        let bytes: [UInt8] = [80, 3, 0, 1, 16]
        let pubrec = try! MQTTDecoder.decode(PubrecPacket.self, data: bytes)
        XCTAssertEqual(pubrec.fixedHeader.controlOptions.packetType, .pubrec)
        XCTAssertEqual(pubrec.fixedHeader.remainingLength, 3)
        XCTAssertEqual(pubrec.packetId, 1)
        XCTAssertEqual(pubrec.error, .noMatchingSubscribers)
    }
    
    func testPubrecEncode() {
        let pubrec = PubrecPacket(packetId: 1)
        let expected: [UInt8] = [80, 2, 0, 1]
        let actual = try! MQTTEncoder.encode(pubrec)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubrecWithReasonCodeEncode() {
        let pubrec = PubrecPacket(packetId: 12, error: .unspecifiedError)
        let expected: [UInt8] = [80, 3, 0, 12, 128]
        let actual = try! MQTTEncoder.encode(pubrec)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubrelDecode() {
        let bytes: [UInt8] = [98, 2, 0, 15]
        let pubrel = try! MQTTDecoder.decode(PubrelPacket.self, data: bytes)
        XCTAssertEqual(pubrel.fixedHeader.controlOptions.packetType, .pubrel)
        XCTAssertEqual(pubrel.fixedHeader.remainingLength, 2)
        XCTAssertEqual(pubrel.packetId, 15)
    }
    
    func testPubrelWithReasonCodeDecode() {
        let bytes: [UInt8] = [98, 3, 0, 1, 146]
        let pubrel = try! MQTTDecoder.decode(PubrelPacket.self, data: bytes)
        XCTAssertEqual(pubrel.fixedHeader.controlOptions.packetType, .pubrel)
        XCTAssertEqual(pubrel.fixedHeader.remainingLength, 3)
        XCTAssertEqual(pubrel.packetId, 1)
        XCTAssertEqual(pubrel.error, .packetIdNotFound)
    }
    
    func testPubrelEncode() {
        let pubrel = PubrelPacket(packetId: 1)
        let expected: [UInt8] = [98, 2, 0, 1]
        let actual = try! MQTTEncoder.encode(pubrel)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubrelWithReasonCodeEncode() {
        let pubrel = PubrelPacket(packetId: 12, error: .packetIdNotFound)
        let expected: [UInt8] = [98, 3, 0, 12, 146]
        let actual = try! MQTTEncoder.encode(pubrel)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubcompDecode() {
        let bytes: [UInt8] = [112, 2, 0, 15]
        let pubcomp = try! MQTTDecoder.decode(PubrelPacket.self, data: bytes)
        XCTAssertEqual(pubcomp.fixedHeader.controlOptions.packetType, .pubcomp)
        XCTAssertEqual(pubcomp.fixedHeader.remainingLength, 2)
        XCTAssertEqual(pubcomp.packetId, 15)
    }
    
    func testPubcomWithReasonCodeDecode() {
        let bytes: [UInt8] = [112, 3, 0, 1, 146]
        let pubcomp = try! MQTTDecoder.decode(PubcompPacket.self, data: bytes)
        XCTAssertEqual(pubcomp.fixedHeader.controlOptions.packetType, .pubcomp)
        XCTAssertEqual(pubcomp.fixedHeader.remainingLength, 3)
        XCTAssertEqual(pubcomp.packetId, 1)
        XCTAssertEqual(pubcomp.error, .packetIdNotFound)
    }
    
    func testPubcompEncode() {
        let pubcomp = PubcompPacket(packetId: 1)
        let expected: [UInt8] = [112, 2, 0, 1]
        let actual = try! MQTTEncoder.encode(pubcomp)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubcompWithReasonCodeEncode() {
        let pubcomp = PubcompPacket(packetId: 12, error: .packetIdNotFound)
        let expected: [UInt8] = [112, 3, 0, 12, 146]
        let actual = try! MQTTEncoder.encode(pubcomp)
        XCTAssertEqual(expected, actual)
    }
}
