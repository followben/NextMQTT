//
//  MQTT.swift
//  NextMQTT
//
//  Created by Ben Stovold on 23/10/19.
//

import os
import Foundation

extension OSLog {
    static let mqtt = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "mqtt")
}

public final class MQTT {
    
    public enum OptionsKey {
        case pingInterval, secureConnection, clientId, maxBuffer, cleanStart
    }
    
    public var onMessage: ((String, Data?) -> Void)?
    public var onConnectionState: ((ConnectionState) -> Void)?
    
    public enum QoS: UInt8 {
        case qos0
        case qos1
        case qos2
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
        options[.pingInterval] as? UInt16 ?? 10
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
    
    private let transportQueue = DispatchQueue(label: "com.simplemqtt.transport")
    
    private var _transport: Transport?
    private var transport: Transport {
        if let transport = _transport { return transport }
        let transport = Transport(hostName: host, port: port, useTLS: secureConnection, maxBuffer: maxBuffer, queue: transportQueue)
        transport.delegate = self
        _transport = transport
        return transport
    }
    
    private var packetId: UInt16 = 0
    
    private var connAckHandler: ((Result<Void, MQTT.ConnectError>) -> Void)?
    private var handlerCoordinator = CompletionHandlerCoordinator()
    
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
    
    func connect(completion: ((Result<Void, MQTT.ConnectError>) -> Void)? = nil) {
        connectionState = .connecting
        connAckHandler = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success():
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
    
    func subscribe(to topicFilter: String, completion: ((Result<QoS, SubscribeError>) -> Void)? = nil) {
        transportQueue.async {
            self.sendSubscribe(topicFilter, completion: completion)
        }
    }
    
    func unsubscribe(from topicFilter: String, completion: ((Result<Void, UnsubscribeError>) -> Void)? = nil) {
        transportQueue.async {
            self.sendUnsubscribe(topicFilter, completion: completion)
        }
    }

    func publish(to topicName: String, message: Data?) {
        transportQueue.async {
            self.sendPublish(topicName, message: message)
        }
    }
    
}

// MARK: - iVar Helpers

private extension MQTT {
    
    func nextPacketId() -> UInt16 {
        packetId = packetId &+ 1
        return packetId
    }
    
    func resetTransport() {
        _transport = nil
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
                case .success():
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
        let conn = try! ConnectPacket(clientId: clientId, username: username, password: password, keepAlive: pingInterval, cleanStart: cleanStart)
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: conn))
        transport.send(packet: conn)
    }

    func sendPing() {
        let ping = PingReqPacket()
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: ping))
        transport.send(packet: ping)
    }
    
    func sendSubscribe(_ topicFilter: String, completion: ((Result<QoS, SubscribeError>) -> Void)? = nil) {
        let sub = try! SubscribePacket(topicFilter: topicFilter, packetId: nextPacketId())
        if let handler = completion {
            handlerCoordinator.store(completionHandler: CompletionHandler.subscribeResultHandler(handler), for: sub.packetId)
        }
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: sub))
        transport.send(packet: sub)
    }
    
    func sendUnsubscribe(_ topicFilter: String, completion: ((Result<Void, UnsubscribeError>) -> Void)? = nil) {
        let unsub = try! UnsubscribePacket(topicFilter: topicFilter, packetId: nextPacketId())
        if let handler = completion {
            handlerCoordinator.store(completionHandler: CompletionHandler.unsubscribeResultHandler(handler), for: unsub.packetId)
        }
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: unsub))
        transport.send(packet: unsub)
    }
    
    func sendPublish(_ topicName: String, message: Data?) {
        let publish = try! PublishPacket(topicName: topicName, message: message)
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: publish))
        transport.send(packet: publish)
    }
    
    func sendDisconnect() {
        connectionState = .disconnecting
        let disconnect = DisconnectPacket()
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: disconnect))
        transport.send(packet: disconnect)
        transport.stop()
        connectionState = .disconnected
    }
}

// MARK: - Receiving (TransportDelegate)

extension MQTTDecoder {
    static func decode<T: MQTTDecodable>(_ packet: MQTTPacket, as type: T.Type) -> T? {
        let result = Result { try MQTTDecoder.decode(T.self, data: packet.bytes) }
        guard case .success(let packet) = result else {
            os_log("Error decoding packet: %@", log: .mqtt, type: .error, String(describing: result.mapError { $0 }))
            return nil
        }
        return packet
    }
}

extension MQTT: TransportDelegate {
    func didStart(transport: Transport) {
        sendConnect()
    }

    func didReceive(packet: MQTTPacket, transport: Transport) {
        switch packet.fixedHeader.controlOptions {
        case .connack:
            if let onConnack = connAckHandler {
                if let connack = MQTTDecoder.decode(packet, as: ConnackPacket.self) {
                    if let error = connack.error {
                        onConnack(.failure(error))
                    } else {
                        onConnack(.success(()))
                    }
                } else {
                    onConnack(.failure(.unspecifiedError))
                }
                connAckHandler = nil
            }
            
        case .suback:
            guard let suback = MQTTDecoder.decode(packet, as: SubackPacket.self) else { return }
            
            var handler: ((Result<QoS, SubscribeError>) -> Void)?
            if case .subscribeResultHandler(let resultHandler) = handlerCoordinator.retrieveCompletionHandler(for: suback.packetId) {
                handler = resultHandler
            }
            
            if let qos = suback.qos {
                os_log("Subscribe successful: %@", log: .mqtt, type: .info, String(describing: qos))
                handler?(.success(qos))
            } else if let error = suback.error {
                os_log("Subscribe error: %@", log: .mqtt, type: .error, String(describing: error))
                handler?(.failure(error))
            }
            
        case .unsuback:
            guard let unsuback = MQTTDecoder.decode(packet, as: UnsubackPacket.self) else { return }
            
            var handler: ((Result<Void, UnsubscribeError>) -> Void)?
            if case .unsubscribeResultHandler(let resultHandler) = handlerCoordinator.retrieveCompletionHandler(for: unsuback.packetId) {
                handler = resultHandler
            }
            
            if let error = unsuback.error {
                os_log("Unsubscribe error: %@", log: .mqtt, type: .error, String(describing: error))
                handler?(.failure(error))
            } else {
                os_log("Unsubscribe successful", log: .mqtt, type: .info)
                handler?(.success(()))
            }
            
        case .publish:
            guard let messageHandler = onMessage, let publish = MQTTDecoder.decode(packet, as: PublishPacket.self) else { return }
            messageHandler(publish.topicName, publish.message)
            
        default:
            os_log("Received %@", log: .mqtt, type: .debug, String(describing: packet.fixedHeader.controlOptions))
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

// MARK: - Helper classes

fileprivate extension MQTT {
    enum CompletionHandler {
        case emptyHandler(() -> Void)
        case errorHandler((Error?) -> Void)
        case subscribeResultHandler(((Result<QoS, SubscribeError>) -> Void))
        case unsubscribeResultHandler(((Result<Void, UnsubscribeError>) -> Void))
    }

    class CompletionHandlerCoordinator {
        private var completionHandlers: [UInt16: CompletionHandler] = [:]
        private let completionHandlerAccessQueue = DispatchQueue(label: "com.simplemqtt.completion", attributes: .concurrent)

        // TODO: add timeout errors for completion handler types?
        fileprivate func store(completionHandler: CompletionHandler, for packetId: UInt16) {
            completionHandlerAccessQueue.async(flags:.barrier) {
                self.completionHandlers[packetId] = completionHandler
            }
        }

        fileprivate func retrieveCompletionHandler(for packetId: UInt16) -> CompletionHandler? {
            var handler: CompletionHandler?
            completionHandlerAccessQueue.sync {
                handler = self.completionHandlers[packetId]
            }
            completionHandlerAccessQueue.async(flags:.barrier) {
                self.completionHandlers[packetId] = nil
            }
            return handler
        }
    }
}
