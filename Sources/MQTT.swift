//
//  MQTT.swift
//  SimpleMQTT
//
//  Created by Ben Stovold on 23/10/19.
//

import Foundation

public final class MQTT {
    
    // MARK: - Public Properties
    
    public enum OptionsKey {
        case pingInterval, secureConnection, clientId, bufferSize, readQos
    }

    // MARK: - Internal Properties
    
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

    private enum ReadState {
        case idle
        case readingFixedHeader
        case readingRemainingLength
        case readingVariableHeader
        case readingPayload
    }
    
    private var readState: ReadState = .idle

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
    private var readQos: DispatchQoS {
        options[.readQos] as? DispatchQoS ?? DispatchQoS.background
    }
    
    private var onConnAck: (() -> Void)?
    
    private var _transport: Transport?
    private var transport: Transport {
        if let transport = _transport { return transport }
        let transport = Transport(hostName: host, port: port, useTLS: secureConnection, queue: DispatchQueue.main)
        transport.delegate = self
        _transport = transport
        return transport
    }
    
    private var messageId: UInt16 = 0
    
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
        onConnAck = { [weak self] in
            self?.connectionState = .connected
            self?.keepAlive()
            completion?(true)
        }
        messageId = 0
        transport.start()c
    }
    
    public func disconnect() {
        sendDisconnect()
    }
    
//    public func subscribe(to topic: String) { }
//
//    public func unsubscribe(from topic: String) { }
//
//    public func publish(to topic: String, message: Data?) { }
    
    // MARK: - Private Methods
    
    private func keepAlive() {
        let deadline = DispatchTime.now() + .seconds(Int(pingInterval / 2))
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard self?.connectionState == .connected else { return }
            
            self?.sendPing()
            self?.keepAlive()
        }
    }
    
    private func reconnect() {
        assert(connectionState == .dropped || connectionState == .reconnecting)
        if connectionState == .dropped {
            connectionState = .reconnecting
            onConnAck = { [weak self] in
                self?.connectionState = .connected
                self?.keepAlive()
            }
        }
        let deadline = DispatchTime.now() + .seconds(5)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            if self?.connectionState == .dropped || self?.connectionState == .reconnecting {
                print("Reconnect Timed Out. Trying again...")
                self?.reconnect()
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
    
    private func sendDisconnect() {
        connectionState = .disconnecting
        transport.send(packet: DisconnectPacket())
        transport.stop()
        connectionState = .disconnected
    }
    
    private func nextMessageId() -> UInt16 {
        messageId = messageId &+ 1
        return messageId
    }
    
    private func resetTransport() {
        _transport = nil
    }
}

extension MQTT: TransportDelegate {
    func didStart(transport: Transport) {
        sendConnect()
    }

    func didReceive(packet: MQTTPacket, transport: Transport) {
        if packet.fixedHeader.controlOptions == .connack, let onConnAck = onConnAck {
            onConnAck()
            self.onConnAck = nil
        } else if packet.fixedHeader.controlOptions == .pingresp {
            print("Ping acknowledged")
        }
    }

    func didStop(transport: Transport, error: Transport.Error?) {
        if error == nil {
            connectionState = .dropped
            resetTransport()
            reconnect()
        }
    }
}
