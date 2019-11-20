//
//  MQTT.swift
//  SimpleMQTT
//
//  Created by Ben Stovold on 23/10/19.
//

import Foundation

public final class MQTT {
    
    public enum OptionsKey {
        case pingInterval, secureConnection, clientId, bufferSize
    }
    
    private enum ConnectionState {
        case notConnected
        case connecting
        case connected
        case disconnecting
        case reconnecting
        case dropped
        case disconnected
    }
    
    private var connectionState: ConnectionState = .notConnected {
        didSet {
            print("Connection state changed: \(connectionState)")
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
    private var bufferSize: Int {
        options[.bufferSize] as? Int ?? 4096
    }
    private var secureConnection: Bool {
        options[.secureConnection] as? Bool ?? false
    }
    
    private let transportQueue = DispatchQueue(label: "com.simplemqtt.transport")
    
    private var _transport: Transport?
    private var transport: Transport {
        if let transport = _transport { return transport }
        let transport = Transport(hostName: host, port: port, useTLS: secureConnection, queue: transportQueue)
        transport.delegate = self
        _transport = transport
        return transport
    }
    
    private var packetId: UInt16 = 0
    
    enum CompletionHandler {
        case noResultHandler(() -> Void)
        case emptyResultHandler((Result<Void, Error>) -> Void)
        case subscriptionResultHandler(((Result<QoS, SubscriptionError>) -> Void))
    }
    
    private var connAckHandler: (() -> Void)?
    private var completionHandlers: [UInt16: CompletionHandler] = [:]
    
    // MARK: - Lifecycle
    
    deinit {
        disconnect()
    }
    
    public convenience init(host: String, port: Int, options: [OptionsKey: Any]? = nil) {
        self.init(host: host, port: port, username: nil, password: nil, optionsDict: options)
    }
    
    public convenience init(host: String, port: Int, username: String, password: String, options: [OptionsKey: Any]? = nil) {
        self.init(host: host, port: port, username: username, password: password, optionsDict: options)
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
    
    // MARK: - Public Methods
    
    public func connect(completion: ((_ success: Bool) -> Void)? = nil) {
        connectionState = .connecting
        connAckHandler = { [weak self] in
            guard let self = self else { return }
            self.connectionState = .connected
            self.keepAlive()
            completion?(true)
        }
        packetId = 0
        transportQueue.async {
            self.transport.start()
        }
    }
    
    public func disconnect() {
        transportQueue.async {
            self.sendDisconnect()
        }
    }
    
    public func subscribe(to topic: String) {
        transportQueue.async {
            self.sendSubscribe(topic)
        }
    }
    
//    public func unsubscribe(from topic: String) { }
//
//    public func publish(to topic: String, message: Data?) { }
    
    // MARK: - Private Methods
    
    private func keepAlive() {
        let deadline = DispatchTime.now() + .seconds(Int(pingInterval / 2))
        transportQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            self.sendPing()
            self.keepAlive()
        }
    }
    
    private func reconnect() {
        assert(connectionState == .dropped || connectionState == .reconnecting)
        if connectionState == .dropped {
            connectionState = .reconnecting
            connAckHandler = { [weak self] in
                guard let self = self else { return }
                self.connectionState = .connected
                self.keepAlive()
            }
        }
        let deadline = DispatchTime.now() + .seconds(5)
        transportQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let self = self else { return }
            if self.connectionState == .dropped || self.connectionState == .reconnecting {
                print("Reconnect Timed Out. Trying again...")
                self.reconnect()
            }
        }
        resetTransport()
        transport.start()
    }
    
    private func sendConnect() {
        let conn = try! ConnectPacket(clientId: clientId, username: username, password: password, keepAlive: pingInterval)
        transport.send(packet: conn)
    }

    private func sendPing() {
        print("Pinging...")
        transport.send(packet: PingReqPacket())
    }
    
    private func sendSubscribe(_ topicFilter: String, completion: ((Result<QoS, SubscriptionError>) -> Void)? = nil) {
        let sub = try! SubscribePacket(topicFilter: topicFilter, packetId: nextPacketId())
        if let handler = completion {
            completionHandlers[sub.packetId] = CompletionHandler.subscriptionResultHandler(handler)
        }
        print("Sending \(sub)")
        transport.send(packet: sub)
    }
    
    private func sendDisconnect() {
        connectionState = .disconnecting
        transport.send(packet: DisconnectPacket())
        transport.stop()
        connectionState = .disconnected
    }
    
    private func nextPacketId() -> UInt16 {
        packetId = packetId &+ 1
        return packetId
    }
    
    private func resetTransport() {
        _transport = nil
    }
}

// MARK: - TransportDelegate methods

extension MQTT: TransportDelegate {
    func didStart(transport: Transport) {
        sendConnect()
    }

    func didReceive(packet: MQTTPacket, transport: Transport) {
        switch packet.fixedHeader.controlOptions {
        case .connack:
            if let connackClosure = connAckHandler {
                connackClosure()
                connAckHandler = nil
            }
        case .suback:
            let result = Result { try MQTTDecoder.decode(SubackPacket.self, data: packet.bytes) }
            guard case .success(let suback) = result else {
                let error = result.mapError { $0 }
                print("Error decoding suback: \(error)")
                return
            }
            
            var handler: ((Result<QoS, SubscriptionError>) -> Void)?
            
            if case .subscriptionResultHandler(let localHandler) = completionHandlers.removeValue(forKey: suback.packetId) {
                handler = localHandler
            }
            if let qos = suback.qos {
                print("Subscription successful: \(qos)")
                handler?(.success(qos))
            } else if let error = suback.error {
                print("Subscription error: \(error)")
                handler?(.failure(error))
            }
            
        default:
            print("Received \(packet.fixedHeader.controlOptions)")
        }
    }

    func didStop(transport: Transport, error: Transport.Error?) {
        if error == nil {
            connectionState = .dropped
            resetTransport()
            reconnect()
        } else {
            print("TODO: handle transport error")
        }
    }
}
