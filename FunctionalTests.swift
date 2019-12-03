import XCTest
@testable import NextMQTT

// MARK: - MQTT tests

final class MQTTTests: XCTestCase {
    
    var yin: MQTT!
    var yang: MQTT!
    
    override func setUp() {
        super.setUp()
        
        yin = MQTT(host: "127.0.0.1", port: 1883)
        yang = MQTT(host: "127.0.0.1", port: 1883)
    }

    func testMostOnceSubscribe() {
        let subscribed = expectation(description: "subscribed")
        let erred = expectation(description: "error")
        erred.isInverted = true
        yin.connect { result in
            if case .failure = result {
                erred.fulfill()
                return
            }
            self.yin.subscribe(to: "/ping", options: [.qos(.mostOnce)]) { result in
                defer { self.yin.disconnect() }
                switch result {
                case .success:
                    subscribed.fulfill()
                case .failure:
                    erred.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 0.5)
    }
    
    func testLeastOncePublishSubscribe() {
        let msg = "hello"
        let topic = "/ping"
        let subscribed = expectation(description: "subscribed")
        let publishedSent = expectation(description: "publish sent")
        let publishReceived = expectation(description: "publish received")
        let erred = expectation(description: "error")
        erred.isInverted = true
        yin.onMessage = { t, m in
            defer { self.yin.disconnect() }
            guard t == topic, let received = m, msg == String(decoding: received, as: UTF8.self) else { return }
            publishReceived.fulfill()
        }
        yin.connect { result in
            if case .failure = result { return erred.fulfill() }
            self.yin.subscribe(to: topic, options: [.qos(.leastOnce)]) { result in
                switch result {
                case .success:
                    subscribed.fulfill()
                case .failure:
                    erred.fulfill()
                }
            }
        }
        yang.connect { result in
            if case .failure = result { return erred.fulfill() }
            self.yang.publish(to: topic, qos: .leastOnce, message: msg.data(using: .utf8)) { result in
                defer { self.yang.disconnect() }
                switch result {
                case .success:
                    publishedSent.fulfill()
                case .failure:
                    erred.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 0.5)
    }
    
    func testExactlyOncePublishSubscribe() {
        let topic = "/ping"
        let subscribed = expectation(description: "subscribed")
        let publishedSent = expectation(description: "publish sent")
        let publishReceived = expectation(description: "publish received")
        publishReceived.assertForOverFulfill = true
        let erred = expectation(description: "error")
        erred.isInverted = true
        yin.onMessage = { t, m in
            defer { self.yin.disconnect() }
            guard t == topic, m == nil else { return }
            publishReceived.fulfill()
        }
        yin.connect { result in
            if case .failure = result { return erred.fulfill() }
            self.yin.subscribe(to: topic, options: [.qos(.exactlyOnce)]) { result in
                switch result {
                case .success:
                    subscribed.fulfill()
                case .failure:
                    erred.fulfill()
                }
            }
        }
        yang.connect { result in
            if case .failure = result { return erred.fulfill() }
            self.yang.publish(to: topic, qos: .exactlyOnce, message: nil) { result in
                defer { self.yang.disconnect() }
                switch result {
                case .success:
                    publishedSent.fulfill()
                case .failure:
                    erred.fulfill()
                }
            }
        }
        waitForExpectations(timeout: 0.5)
    }
}

