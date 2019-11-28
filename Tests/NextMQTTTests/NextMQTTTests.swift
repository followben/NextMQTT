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
    
    func testConnackPacketDecode() {
        let bytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0, 10]
        let connack = try! MQTTDecoder.decode(ConnackPacket.self, data: bytes)
        XCTAssert(connack.fixedHeader.controlOptions.contains(.connack))
        XCTAssertEqual(Int(connack.fixedHeader.remainingLength), 6)
        XCTAssertFalse(connack.flags.contains(.sessionPresent))
        XCTAssertNil(connack.error)
        XCTAssertEqual(connack.topicAliasMaximum, 10)
    }
    
    func testConnackPacketErrorDecode() {
        let bytes: [UInt8] = [32, 3, 0, 151, 3]
        let connack = try! MQTTDecoder.decode(ConnackPacket.self, data: bytes)
        XCTAssert(connack.fixedHeader.controlOptions.contains(.connack))
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
        XCTAssert(suback.fixedHeader.controlOptions.contains(.suback))
        XCTAssertEqual(Int(suback.fixedHeader.remainingLength), 4)
        XCTAssertEqual(suback.qos, .exactlyOnce)
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
    
    func testUnsubscribePacketEncode() {
        let packet = try! UnsubscribePacket(topicFilter: "a/c", packetId: 12)
        let expected: [UInt8] = [162, 8, 0, 12, 0, 0, 3, 97, 47, 99]
        let actual = try! MQTTEncoder.encode(packet)
        XCTAssertEqual(expected, actual)
    }
    
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
        XCTAssertEqual(publish.fixedHeader.controlOptions, [.publish])
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
    
    func testSimplePubackDecode() {
        let bytes: [UInt8] = [64, 2, 0, 15]
        let puback = try! MQTTDecoder.decode(PubackPacket.self, data: bytes)
        XCTAssertEqual(puback.fixedHeader.controlOptions, [.puback])
        XCTAssertEqual(puback.fixedHeader.remainingLength, 2)
        XCTAssertEqual(puback.packetId, 15)
    }
    
    func testPubackWithReasonCodeDecode() {
        let bytes: [UInt8] = [64, 4, 0, 1, 16]
        let puback = try! MQTTDecoder.decode(PubackPacket.self, data: bytes)
        XCTAssertEqual(puback.fixedHeader.controlOptions, [.puback])
        XCTAssertEqual(puback.fixedHeader.remainingLength, 4)
        XCTAssertEqual(puback.packetId, 1)
        XCTAssertEqual(puback.error, .noMatchingSubscribers)
    }
    
    func testPubackEncode() {
        let puback = try! PubackPacket(packetId: 1)
        let expected: [UInt8] = [64, 2, 0, 1]
        let actual = try! MQTTEncoder.encode(puback)
        XCTAssertEqual(expected, actual)
    }
    
    func testPubackWithReasonCodeEncode() {
        let puback = try! PubackPacket(packetId: 12, error: .unspecifiedError)
        let expected: [UInt8] = [64, 3, 0, 12, 128]
        let actual = try! MQTTEncoder.encode(puback)
        XCTAssertEqual(expected, actual)
    }
}

// MARK: - Transport tests

final class TransportTests: XCTestCase, TransportDelegate {
    
    static var allTests = [
        ("testTransport", testTransport),
    ]

    private var testServer: TestServer!
    var didStartCalled = false
    var didStopCalled = false
    var packetsReceived: [MQTTPacket] = []
    
    override func setUp() {
        super.setUp()
        didStartCalled = false
        didStopCalled = false
        packetsReceived = []
        testServer = TestServer()
        testServer.start()
    }
    
    override func tearDown() {
        testServer?.stop()
        testServer = nil
        super.tearDown()
    }
    
    func run(interval: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: interval)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    func didStart(transport: Transport) {
        didStartCalled = true
    }
    
    func didReceive(packet: MQTTPacket, transport: Transport) {
        packetsReceived.append(packet)
    }
    
    func didStop(transport: Transport, error: Transport.Error?) {
        didStopCalled = true
    }
    
    func testTransport() {
        let transport = Transport(hostName: "127.0.0.1", port: testServer.port, useTLS: false, maxBuffer: 2048, queue: DispatchQueue.main)
        
        let connectPacket = try! ConnectPacket(clientId: "A")
        let connectBytes = try! MQTTEncoder.encode(connectPacket)
        
        let connackBytes: [UInt8] = [32, 6, 0, 0, 3, 34, 0, 10]
        testServer.data = connackBytes

        transport.delegate = self
        transport.start()
        
        transport.send(packet: connectPacket)
        run(interval: 1.0)
        transport.stop()
        
        XCTAssert(didStartCalled)
        XCTAssertEqual(testServer.bytesReceived, connectBytes)
        XCTAssertEqual(packetsReceived.first?.fixedHeader.controlOptions, .connack)
        XCTAssert(!didStopCalled) // should not call didStop if stop() invoked
    }
    
    private final class TestServer : NSObject, NetServiceDelegate {
        
        var data: [UInt8] = [UInt8]()

        private let service = NetService(domain: "", type: "_x-test-data._tcp.", name: "", port: 0)
        private var connection: Connection?
        
        var port: Int {
            service.port
        }
        
        var bytesReceived: [UInt8]? {
            connection?.inputBuffer
        }
        
        func start() {
            service.delegate = self
            service.publish(options: [.listenForConnections])
            repeat {
                if service.port != -1 {
                    break
                }
                RunLoop.current.run(mode: .default, before: .distantFuture)
            } while true
        }
        
        func stop() {
            service.delegate = nil
            service.stop()
            connection?.stop()
        }
        
        // MARK: NetServiceDelegate methods
        
        func netServiceDidPublish(_ sender: NetService) {
            // do nothing
        }
        
        func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
            // If we fail to publish a service the entire test fails.
            fatalError()
        }
        
        func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
            connection = Connection(inputStream: inputStream, outputStream: outputStream, data: data)
            connection?.start(completionHandler: {
                self.connection = nil
            })
        }
    }

    private final class Connection : NSObject, StreamDelegate {
        
        let inputStream: InputStream
        let outputStream: OutputStream
        var streams: [Stream] { return [self.inputStream, self.outputStream] }
        
        var inputBuffer: [UInt8]?

        private var outputBuffer: [UInt8]
        private var hasSpaceAvailable = false
        
        private var completionHandler: (() -> Void)!
        
        required init(inputStream: InputStream, outputStream: OutputStream, data: [UInt8]) {
            self.outputBuffer = data
            self.inputStream = inputStream
            self.outputStream = outputStream
            super.init()
        }
        
        func start(completionHandler: @escaping () -> Void) {
            precondition(self.completionHandler == nil)
            self.completionHandler = completionHandler
            for stream in streams {
                stream.delegate = self
                stream.schedule(in: .current, forMode: .default)
                stream.open()
            }
        }
        
        func stop() {
            for stream in streams {
                stream.delegate = self
                stream.close()
            }
            completionHandler?()
        }

        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            switch eventCode {
            case [.openCompleted]:
                break
            case [.hasBytesAvailable]:
                serviceInput()
            case [.hasSpaceAvailable]:
                hasSpaceAvailable = true
                serviceOutput()
            case [.endEncountered]:
                stop()
            case [.errorOccurred]:
                stop()
            default:
                fatalError()
            }
        }

        private func serviceInput() {
            let max = 2048
            var inputBuffer = [UInt8](repeating: 0, count: max)
            let length = self.inputStream.read(&inputBuffer, maxLength: max)
            self.inputBuffer = [UInt8](inputBuffer.prefix(length))
        }

        private func serviceOutput() {
            let outputBufferCount = outputBuffer.count
            guard self.hasSpaceAvailable && outputBufferCount != 0 else {
                return
            }
            let bytesWritten: Int = outputBuffer.withUnsafeBytes { ptr in
                guard let bytes = ptr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return outputStream.write(bytes, maxLength: outputBufferCount)
            }
            if bytesWritten > 0 {
                outputBuffer.removeFirst(bytesWritten)
            }
        }
    }
}
