//
//  TransportTests.swift
//  NextMQTTTests
//
//  Created by Ben Stovold on 10/11/19.
//

import XCTest

@testable import NextMQTT

class TestServer : NSObject, NetServiceDelegate {
    
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


class TransportTests: XCTestCase, TransportDelegate {

    var testServer: TestServer!
    
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
}
