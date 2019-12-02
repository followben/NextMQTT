//
//  NextMQTT
//
//  Copyright (c) Ben Stovold 2019
//  MIT license, see LICENSE file for details
//

import os
import Foundation

internal extension OSLog {
    static let mqtt = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "mqtt")
}

public final class MQTT {
    
    public enum OptionsKey {
        case pingInterval, secureConnection, clientId, maxBuffer, cleanStart, sessionExpiry
    }
    
    public var onMessage: ((String, Data?) -> Void)?
    public var onConnectionState: ((ConnectionState) -> Void)?
    
    public enum QoS: UInt8 {
        case mostOnce
        case leastOnce
        case exactlyOnce
    }
    
    public enum ConnectionState {
        case notConnected
        case connecting
        case connected
        case disconnecting
        case reconnecting
        case dropped
        case disconnected
    }
    
    public var connectionState: ConnectionState = .notConnected {
        didSet {
            onConnectionState?(connectionState)
        }
    }

    private let host: String
    private let port: Int
    private var username: String?
    private var password: String?
    private var options: [OptionsKey: Any] = [:]
    
    private var clientId: String {
        var clientId = options[.clientId] as? String ?? "%%%%"
        while let range = clientId.range(of: "%") {
            let quadbit = String(format: "%02X", Int(arc4random() & 0xFF))
            clientId.replaceSubrange(range, with: quadbit)
        }
        return clientId
    }
    private var pingInterval: UInt16 {
        let interval = options[.pingInterval] as? Int
        return UInt16(interval ?? 20)
    }
    private var maxBuffer: Int {
        options[.maxBuffer] as? Int ?? 4096
    }
    private var secureConnection: Bool {
        options[.secureConnection] as? Bool ?? false
    }
    private var cleanStart: Bool {
        options[.cleanStart] as? Bool ?? false
    }
    private var sessionExpiry: UInt32 {
        let interval = options[.sessionExpiry] as? Int
        return UInt32(interval ?? 0)
    }
    
    private let transportQueue = DispatchQueue(label: "com.simplemqtt.transport")
    
    private var _transport: Transport?
    private var transport: Transport! {
        set {
            assert(newValue == nil)
            _transport = nil
        }
        get {
            if let transport = _transport { return transport }
            let transport = Transport(hostName: host, port: port, useTLS: secureConnection, maxBuffer: maxBuffer, queue: transportQueue)
            transport.delegate = self
            _transport = transport
            return transport
        }
    }
    
    private var packetId: UInt16 = 0
    
    private var connAckHandler: ((Result<Bool, MQTT.ConnectError>) -> Void)?
    
    private var _handlerStore: SynchronizedStore<UInt16, CompletionHandler>?
    private var handlerStore: SynchronizedStore<UInt16, CompletionHandler>! {
        set {
            assert(newValue == nil)
            _handlerStore = nil
        }
        get {
            if let store = _handlerStore { return store }
            _handlerStore = SynchronizedStore<UInt16, CompletionHandler>(withName: "completion")
            return _handlerStore
        }
    }
    
    private var _packetStore: SynchronizedStore<UInt16, UnacknowledgedPacket>?
    private var packetStore: SynchronizedStore<UInt16, UnacknowledgedPacket>! {
        set {
            assert(newValue == nil)
            _packetStore = nil
        }
        get {
            if let store = _packetStore { return store }
            _packetStore = SynchronizedStore<UInt16, UnacknowledgedPacket>(withName: "message")
            return _packetStore
        }
    }
    
    private var hasSession: Bool = false
    
    // MARK: Lifecycle
    
    deinit {
        disconnect()
    }
    
    private init(host: String, port: Int, username: String? = nil, password: String? = nil, optionsDict: [OptionsKey: Any]? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        if let options = optionsDict {
            self.options = self.options.merging(options) { $1 }
        }
    }
    
}

// MARK: - Public Methods

public extension MQTT {
    
    convenience init(host: String, port: Int, options: [OptionsKey: Any]? = nil) {
        self.init(host: host, port: port, username: nil, password: nil, optionsDict: options)
    }
    
    convenience init(host: String, port: Int, username: String, password: String, options: [OptionsKey: Any]? = nil) {
        self.init(host: host, port: port, username: username, password: password, optionsDict: options)
    }
    
    func connect(completion: ((Result<Bool, MQTT.ConnectError>) -> Void)? = nil) {
        connectionState = .connecting
        connAckHandler = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(_):
                self.connectionState = .connected
                self.keepAlive()
            case .failure(let error):
                os_log("Error on connect: %@", log: .mqtt, type: .error, String(describing: error))
                self.connectionState = .notConnected
            }
            completion?(result)
        }
        packetId = 0
        transportQueue.async {
            self.transport.start()
        }
    }
    
    func disconnect() {
        transportQueue.async {
            self.sendDisconnect()
        }
    }
    
    func subscribe(to topicFilter: String, options: SubscribeOptions = [.qos(.mostOnce), .retainSendOnSubscribe], completion: ((Result<QoS, SubscribeError>) -> Void)? = nil) {
        transportQueue.async {
            self.sendSubscribe(topicFilter, options: options, completion: completion)
        }
    }
    
    func unsubscribe(from topicFilter: String, completion: ((Result<Void, UnsubscribeError>) -> Void)? = nil) {
        transportQueue.async {
            self.sendUnsubscribe(topicFilter, completion: completion)
        }
    }

    func publish(to topicName: String, qos: QoS = .mostOnce, message: Data? = nil, completion: ((Result<Void, PublishError>) -> Void)? = nil) {
        transportQueue.async {
            self.sendPublish(topicName, qos:qos, message: message, completion: completion)
        }
    }
    
}

// MARK: - Mutators

private extension MQTT {
    
    func nextPacketId() -> UInt16 {
        packetId = packetId &+ 1
        return packetId
    }
    
    func resetTransport() {
        transport = nil
    }
    
    func resetSession() {
        if hasSession {
            os_log("Resetting session and removing stores", log: .mqtt, type: .debug)
            packetStore = nil
            handlerStore = nil
        }
        hasSession = (!cleanStart && sessionExpiry > 0)
    }

}

// MARK: - Sending

private extension MQTT {

    func keepAlive() {
        let deadline = DispatchTime.now() + .seconds(Int(pingInterval / 2))
        transportQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            self.sendPing()
            self.keepAlive()
        }
    }
    
    func reconnect() {
        assert(connectionState == .dropped || connectionState == .reconnecting)
        if connectionState == .dropped {
            connectionState = .reconnecting
            connAckHandler = { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(_):
                    self.connectionState = .connected
                    self.keepAlive()
                case .failure(let error):
                    os_log("Error on reconnect: %@", log: .mqtt, type: .error, String(describing: error))
                    self.connectionState = .dropped
                }
            }
        }
        let deadline = DispatchTime.now() + .seconds(5)
        transportQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            if self.connectionState == .dropped || self.connectionState == .reconnecting {
                os_log("Reconnect Timed Out. Trying again...", log: .mqtt, type: .info)
                self.reconnect()
            }
        }
        resetTransport()
        transport.start()
    }
    
    func sendConnect() {
        let conn = try! ConnectPacket(clientId: clientId, username: username, password: password, keepAlive: pingInterval, cleanStart: cleanStart, sessionExpiry: sessionExpiry)
        transport.send(packet: conn)
    }

    func sendPing() {
        let ping = PingReqPacket()
        transport.send(packet: ping)
    }
    
    func sendSubscribe(_ topicFilter: String, options: SubscribeOptions, completion: ((Result<QoS, SubscribeError>) -> Void)? = nil) {
        let sub = try! SubscribePacket(topicFilter: topicFilter, packetId: nextPacketId(), options: options)
        if let handler = completion {
            handlerStore.setValue(CompletionHandler.subscribeResultHandler(handler), forKey: sub.packetId)
        }
        transport.send(packet: sub)
    }
    
    func sendUnsubscribe(_ topicFilter: String, completion: ((Result<Void, UnsubscribeError>) -> Void)? = nil) {
        let unsub = try! UnsubscribePacket(topicFilter: topicFilter, packetId: nextPacketId())
        if let handler = completion {
            handlerStore.setValue(CompletionHandler.unsubscribeResultHandler(handler), forKey: unsub.packetId)
        }
        transport.send(packet: unsub)
    }
    
    func sendPublish(_ topicName: String, qos: QoS, message: Data?, completion: ((Result<Void, PublishError>) -> Void)? = nil) {
        let packetId = (qos != .mostOnce) ? nextPacketId() : nil
        let packet = try! PublishPacket(topicName: topicName, qos: qos, packetId: packetId, message: message)
        if qos != .mostOnce {
            let packetId = packet.packetId!
            packetStore.setValue(.publishSent(packet), forKey: packetId)
            if let completion = completion {
                handlerStore.setValue(.publishResultHandler(completion), forKey: packetId)
            }
        }
        transport.send(packet: packet)
        if qos == .mostOnce {
            completion?(.success(()))
        }
    }
    
    func sendPuback(packetId: UInt16) {
        let packet = PubackPacket(packetId: packetId)
        transport.send(packet: packet)
    }
    
    func sendPubrec(packetId: UInt16) {
        let packet = PubrecPacket(packetId: packetId)
        transport.send(packet: packet)
    }
    
    func sendPubrel(packetId: UInt16) {
        let packet = PubrelPacket(packetId: packetId)
        transport.send(packet: packet)
    }
    
    func sendPubcomp(packetId: UInt16) {
        let packet = PubcompPacket(packetId: packetId)
        transport.send(packet: packet)
    }
    
    func sendDisconnect() {
        connectionState = .disconnecting
        let disconnect = DisconnectPacket()
        transport.send(packet: disconnect)
        transport.stop()
        connectionState = .disconnected
    }
    
    func resendUnacknowledgedPackets() {
        os_log("Resending unacked packets", log: .mqtt, type: .info)
        for unacked in packetStore.values {
            switch unacked {
            case .publishSent(let packet):
                transport.send(packet: packet)
            case .pubRecSent(let packet):
                transport.send(packet: packet)
            default:
                break
            }
        }
    }
}

// MARK: - Receiving

private extension MQTTDecoder {
    static func decode<T: MQTTDecodable>(_ packet: MQTTPacket, as type: T.Type) -> T? {
        let result = Result { try MQTTDecoder.decode(T.self, data: packet.bytes) }
        guard case .success(let packet) = result else {
            os_log("Error decoding packet: %@", log: .mqtt, type: .error, String(describing: result.mapError { $0 }))
            return nil
        }
        return packet
    }
}

private extension MQTT {
    
    func processConnack(_ connack: ConnackPacket) {
        
        if connack.flags.contains(.sessionPresent) {
            if hasSession {
                resendUnacknowledgedPackets()
            } else {
                connAckHandler?(.failure(.protocolError)) // TODO: this should be a specific error as per [MQTT-3.2.2-4]
                transport.stop()
                connectionState = .disconnected
                resetTransport()
            }
        } else {
            resetSession()
        }
        
        if let error = connack.error {
            connAckHandler?(.failure(error))
        } else {
            connAckHandler?(.success(connack.flags.contains(.sessionPresent)))
        }
        connAckHandler = nil
    }
    
    func processSuback(_ suback: SubackPacket) {
        var handler: ((Result<QoS, SubscribeError>) -> Void)?
        if case .subscribeResultHandler(let resultHandler) = handlerStore.removeValueForKey(suback.packetId) {
            handler = resultHandler
        }
        if let qos = suback.qos {
            os_log("Subscribe successful: %@", log: .mqtt, type: .info, String(describing: qos))
            handler?(.success(qos))
        } else if let error = suback.error {
            os_log("Subscribe error: %@", log: .mqtt, type: .error, String(describing: error))
            handler?(.failure(error))
        }
    }
    
    func processUnsuback(_ unsuback: UnsubackPacket) {
        var handler: ((Result<Void, UnsubscribeError>) -> Void)?
        if case .unsubscribeResultHandler(let resultHandler) = handlerStore.removeValueForKey(unsuback.packetId) {
            handler = resultHandler
        }
        if let error = unsuback.error {
            os_log("Unsubscribe error: %@", log: .mqtt, type: .error, String(describing: error))
            handler?(.failure(error))
        } else {
            os_log("Unsubscribe successful", log: .mqtt, type: .info)
            handler?(.success(()))
        }
    }
    
    func processPublish(_ publish: PublishPacket) {
        os_log("Received publish for packetId %@", log: .mqtt, type: .debug, String(describing: publish.packetId))
        if publish.fixedHeader.controlOptions.contains(.qos(.exactlyOnce)) {
            assert(publish.packetId != nil)
            assert(publish.topicName.count > 0)
            packetStore.setValue(.publishReceived(publish), forKey: publish.packetId!)
            sendPubrec(packetId: publish.packetId!)
        } else {
            if publish.fixedHeader.controlOptions.contains(.qos(.leastOnce)), let packetId = publish.packetId {
                sendPuback(packetId: packetId)
            }
            onMessage?(publish.topicName, publish.message)
        }
    }
    
    func processPuback(_ puback: PubackPacket) {
        let publish = packetStore.removeValueForKey(puback.packetId)
        assert(publish != nil)
        var handler: ((Result<Void, PublishError>) -> Void)?
        if case .publishResultHandler(let resultHandler) = handlerStore.removeValueForKey(puback.packetId) {
            handler = resultHandler
        }
        if let error = puback.error {
            os_log("Received puback for packetId %@ with error: %@", log: .mqtt, type: .error, String(describing: puback.packetId), String(describing: error))
            handler?(.failure(error))
        } else {
            os_log("Received puback for packetId %@", log: .mqtt, type: .debug, String(describing: puback.packetId))
            handler?(.success(()))
        }
    }
    
    func processPubrec(_ pubrec: PubrecPacket) {
        let publish = packetStore.removeValueForKey(pubrec.packetId)
        assert(publish != nil)
        if let error = pubrec.error {
            var handler: ((Result<Void, PublishError>) -> Void)?
            if case .publishResultHandler(let resultHandler) = handlerStore.removeValueForKey(pubrec.packetId) {
                handler = resultHandler
            }
            os_log("Received pubrec for packetId %@ with error: %@", log: .mqtt, type: .error, String(describing: pubrec.packetId), String(describing: error))
            handler?(.failure(error))
        } else {
            os_log("Received pubrec for packetId %@", log: .mqtt, type: .debug, String(describing: pubrec.packetId))
            packetStore.setValue(.pubRecSent(pubrec), forKey: pubrec.packetId)
            sendPubrel(packetId: pubrec.packetId)
        }
    }
    
    func processPubrel(_ pubrel: PubrelPacket) {
        let packetId = pubrel.packetId
        if case .publishReceived(let publish) = packetStore.removeValueForKey(packetId) {
            os_log("Received pubrel for packetId %@", log: .mqtt, type: .debug, String(describing: packetId))
            onMessage?(publish.topicName, publish.message)
        } else {
            os_log("Received pubrel for unknown packetId %@", log: .mqtt, type: .error, String(describing: packetId))
        }
        sendPubcomp(packetId: packetId)
    }
    
    func processPubcomp(_ pubcomp: PubcompPacket) {
        let pubrec = packetStore.removeValueForKey(pubcomp.packetId)
        assert(pubrec != nil)
        var handler: ((Result<Void, PublishError>) -> Void)?
        if case .publishResultHandler(let resultHandler) = handlerStore.removeValueForKey(pubcomp.packetId) {
            handler = resultHandler
        }
        if let error = pubcomp.error {
            os_log("Received pubcomp for packetId %@ with error: %@", log: .mqtt, type: .error, String(describing: pubcomp.packetId), String(describing: error))
            handler?(.failure(error))
        } else {
            os_log("Received pubcomp for packetId %@", log: .mqtt, type: .debug, String(describing: pubcomp.packetId))
            handler?(.success(()))
        }
    }
}

// MARK: - TransportDelegate

extension MQTT: TransportDelegate {
    func didStart(transport: Transport) {
        sendConnect()
    }

    func didReceive(packet: MQTTPacket, transport: Transport) {
        switch packet.fixedHeader.controlOptions.packetType {
        case .connack:
            if let connack = MQTTDecoder.decode(packet, as: ConnackPacket.self) {
                processConnack(connack)
            } else if let onConnack = connAckHandler {
                onConnack(.failure(.unspecifiedError))
                connAckHandler = nil
            }
        case .suback:
            if let suback = MQTTDecoder.decode(packet, as: SubackPacket.self) {
                processSuback(suback)
            }
        case .unsuback:
            if let unsuback = MQTTDecoder.decode(packet, as: UnsubackPacket.self) {
                processUnsuback(unsuback)
            }
        case .publish:
            if let publish = MQTTDecoder.decode(packet, as: PublishPacket.self) {
                processPublish(publish)
            }
        case .puback:
            if let puback = MQTTDecoder.decode(packet, as: PubackPacket.self) {
                processPuback(puback)
            }
        case .pubrec:
            if let pubrec = MQTTDecoder.decode(packet, as: PubrecPacket.self) {
                processPubrec(pubrec)
            }
        case .pubrel:
            if let pubrel = MQTTDecoder.decode(packet, as: PubrelPacket.self) {
                processPubrel(pubrel)
            }
        case .pubcomp:
            if let pubcomp = MQTTDecoder.decode(packet, as: PubcompPacket.self) {
                processPubcomp(pubcomp)
            }
        default:
            os_log("Unhandled packet: %@", log: .mqtt, type: .error, String(describing: packet.fixedHeader.controlOptions))
        }
    }

    func didStop(transport: Transport, error: Transport.Error?) {
        if error == nil {
            connectionState = .dropped
            resetTransport()
            reconnect()
        } else {
            os_log("TODO: handle transport error", log: .mqtt, type: .error)
        }
    }
}

// MARK: - Storage classes

fileprivate extension MQTT {
    enum CompletionHandler {
        case subscribeResultHandler(((Result<QoS, SubscribeError>) -> Void))
        case unsubscribeResultHandler(((Result<Void, UnsubscribeError>) -> Void))
        case publishResultHandler(((Result<Void, PublishError>) -> Void))
    }
    
    enum UnacknowledgedPacket {
        case publishSent(PublishPacket)
        case pubRecSent(PubrecPacket)
        case publishReceived(PublishPacket)
    }
    
    class SynchronizedStore<Key: Hashable, Value> {
        private var store: [Key: Value] = [:]
        
        private let name: String
        private lazy var queue: DispatchQueue = {
            DispatchQueue(label: "com.simplemqtt." + name.lowercased(), attributes: .concurrent)
        }()
        
        var values: [Value] {
            return store.values.compactMap { $0 }
        }
        
        init(withName name: String) {
            self.name = name
        }
        
        func setValue(_ value: Value, forKey key: Key) {
            queue.async(flags:.barrier) {
                self.store[key] = value
                os_log("Stored with key %@: %@", log: .mqtt, type: .debug, String(describing: key), String(describing: value))
            }
        }

        @discardableResult
        func removeValueForKey(_ key: Key) -> Value? {
            var value: Value?
            queue.sync {
                value = self.store[key]
            }
            queue.async(flags: .barrier) {
                self.store[key] = nil
                
            }
            os_log("Removing from key %@: %@", log: .mqtt, type: .debug, String(describing: key), String(describing: value))
            return value
        }
    }
}
