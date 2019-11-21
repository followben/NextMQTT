//
//  PacketTests.swift
//  SimpleMQTTTests
//
//  Created by Ben Stovold on 4/11/19.
//

import XCTest

@testable import SimpleMQTT

class FixedHeaderTests: XCTestCase {

    func testFixedHeaderEncode() {
        let header = FixedHeader(controlOptions: [.disconnect, .reserved0], remainingLength: 0)
        let expected: [UInt8] = [224, 0]
        let actual = try! MQTTEncoder.encode(header)
        XCTAssertEqual(expected, actual)
    }
    
    func testFixedHeaderDecode() {
        let bytes: [UInt8] = [32, 6]
        let fixedHeader = try! MQTTDecoder.decode(FixedHeader.self, data: bytes)
        XCTAssert(fixedHeader.controlOptions.contains(.connack))
        XCTAssertEqual(fixedHeader.remainingLength, 6)
    }
    
}

class ConnectPacketTests: XCTestCase {

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
    
}

class ConnackPacketTests: XCTestCase {

    func testConnackPacketDecode() {
        let bytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0, 10]
        let connack = try! MQTTDecoder.decode(ConnackPacket.self, data: bytes)
        XCTAssert(connack.fixedHeader.controlOptions.contains(.connack))
        XCTAssertEqual(Int(connack.fixedHeader.remainingLength), 6)
        XCTAssertFalse(connack.flags.contains(.sessionPresent))
        XCTAssertEqual(connack.reasonCode, .success)
        XCTAssertEqual(connack.topicAliasMaximum, 10)
    }

    func testBadConnackPacket() {
        var error: Error?
        let bytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0]
        XCTAssertThrowsError(try MQTTDecoder.decode(ConnackPacket.self, data: bytes)) { error = $0 }
        guard case .prematureEndOfData = (error as! MQTTDecoder.Error) else {
            return XCTAssert(false, "Expected .prematureEndOfData but got \(String(describing: error))")
        }
    }
    
}

class PingReqPacketTests: XCTestCase {

    func testPingReqPacketEncode() {
        let packet = PingReqPacket()
        let expected: [UInt8] = [192, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
}

class DisconnectPacketTests: XCTestCase {

    func testDisconnectPacketEncode() {
        let packet = DisconnectPacket()
        let expected: [UInt8] = [224, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
}


class SubscribePacketTests: XCTestCase {
    
    func testSubscribePacketEncode() {
        let packet = try! SubscribePacket(topicFilter: "a/b", packetId: 10)
        let expected: [UInt8] = [130, 9, 0, 10, 0, 0, 3, 97, 47, 98, 0]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
    func testSubscribePacketWithOptionsEncode() {
        let packet = try! SubscribePacket(topicFilter: "a/b/c/d", packetId: 65535, options: [.qos2])
        let expected: [UInt8] = [130, 13, 255, 255, 0, 0, 7, 97, 47, 98, 47, 99, 47, 100, 2]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
}

class SubackPacketTests: XCTestCase {
    
    func testSubackPacketDecode() {
        let bytes: [UInt8] = [144, 4, 0, 10, 0, 2]
        let suback = try! MQTTDecoder.decode(SubackPacket.self, data: bytes)
        XCTAssert(suback.fixedHeader.controlOptions.contains(.suback))
        XCTAssertEqual(Int(suback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(suback.qos, .qos2)
    }
    
    func testSubackPacketErrorDecode() {
        let bytes: [UInt8] = [144, 4, 255, 255, 0, 143]
        let suback = try! MQTTDecoder.decode(SubackPacket.self, data: bytes)
        XCTAssert(suback.fixedHeader.controlOptions.contains(.suback))
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
}

class UnsubscribePacketTests: XCTestCase {
    
    func testUnsubscribePacketEncode() {
        let packet = try! UnsubscribePacket(topicFilter: "a/c", packetId: 12)
        let expected: [UInt8] = [162, 8, 0, 12, 0, 0, 3, 97, 47, 99]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
}

class UnsubackPacketTests: XCTestCase {

    func testUnsubackPacketDecode() {
        let bytes: [UInt8] = [176, 4, 0, 12, 0, 0]
        let unsuback = try! MQTTDecoder.decode(UnsubackPacket.self, data: bytes)
        XCTAssert(unsuback.fixedHeader.controlOptions.contains(.unsuback))
        XCTAssertEqual(Int(unsuback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(unsuback.packetId, 12)
    }

    func testUnsubackPacketErrorDecode() {
        let bytes: [UInt8] = [176, 4, 0, 13, 0, 17]
        let unsuback = try! MQTTDecoder.decode(UnsubackPacket.self, data: bytes)
        XCTAssertEqual(unsuback.packetId, 13)
        XCTAssertEqual(unsuback.error, .noSubscriptionExisted)
    }

}

class PublishPacketTests: XCTestCase {
    
    struct TestPayload: Encodable {
        let a = "a"
        let b = "b"
    }

    func testPublishPacketEncode() {
        let payload = TestPayload()
        let message = try! JSONEncoder().encode(payload)
        let connect = try! PublishPacket(topicName: "a/c", message: message)
        let remainingLength = UInt8(8 + message.count)
        let expected: [UInt8] = [48, remainingLength, 0, 3, 97, 47, 99, 0, 5, 0] + [UInt8](message)
        let actual = try! MQTTEncoder.encode(connect)
        XCTAssertEqual(expected, actual)
    }
    
    func testPublishPacketDecode() {
        let fixedHeader: [UInt8] = [48, 16]
        let topic: [UInt8] = [0, 5, 47, 112, 111, 110, 103] // "/pong" as mqtt string
        let propertyLength: [UInt8] = [0]
        let message: [UInt8] = [84, 114, 121, 32, 84, 104, 105, 115] // "Try This" as utf8
        let bytes: [UInt8] = fixedHeader + topic + propertyLength + message
        let publish = try! MQTTDecoder.decode(PublishPacket.self, data: bytes)
        XCTAssertEqual(publish.fixedHeader.controlOptions, [.publish])
        XCTAssertEqual(publish.fixedHeader.remainingLength, 16)
        XCTAssertEqual(publish.topicName, "/pong")
        XCTAssertEqual(publish.propertyLength, 0)
        XCTAssertEqual(publish.message, "Try This".data(using: .utf8))
    }
}

