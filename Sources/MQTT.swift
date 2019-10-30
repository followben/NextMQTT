//
//  MQTT.swift
//  SimpleMQTT
//
//  Created by Benjamin Stovold on 23/10/19.
//

import Foundation

public final class MQTT {
    
    // MARK: - Public Properties
    
    public enum OptionsKey {
        case pingInterval, secureConnection, clientId, bufferSize, readQos
    }

    public var onMessage: ((_ topic: String, _ data: Data) -> Void)?
    public var onError: ((_ error: Error) -> Void)?
    
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
    
    private func _streamTaskInitial() -> URLSessionStreamTask {
        let session = URLSession(configuration: .default)
        let task = session.streamTask(withHostName: host, port: port)
        task.resume()
        if secureConnection {
            task.startSecureConnection()
        }
        enqueueRead()
        return task
    }
    private var _streamTask: URLSessionStreamTask?
    var streamTask: URLSessionStreamTask! {
      get {
        if _streamTask == nil { _streamTask = _streamTaskInitial() }
        return _streamTask
      }
      set {
        _streamTask = newValue
      }
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
        writeConnect()
    }
    
    public func disconnect() {
        connectionState = .disconnecting
        writeDisconnect() { [weak self] success in
            self?.streamTask.closeRead()
            self?.streamTask.closeWrite()
        }
    }
    
    public func subscribe(to topic: String) {
        sendSubscribe(to: topic)
    }
    
    public func unsubscribe(from topic: String) {
        writeUnsubscribe(from: topic)
    }
    
    public func publish(to topic: String, message: Data?) {
        writePublish(to: topic, message: message ?? Data())
    }
    
    // MARK: - Private Methods
    
    private func keepAlive() {
        let deadline = DispatchTime.now() + .seconds(Int(pingInterval / 2))
        DispatchQueue.global(qos: .default).asyncAfter(deadline: deadline) { [weak self] in
            guard self?.connectionState == .connected else { return }
            
            self?.writePing()
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
        DispatchQueue.global(qos: .default).asyncAfter(deadline: deadline) { [weak self] in
            if self?.connectionState != .connected {
                print("Reconnect Timed Out. Trying again...")
                self?.reconnect()
            }
        }
        writeConnect()
    }
    
    // MARK: Read
    
    private func enqueueRead() {
        let maxLength = bufferSize
        DispatchQueue.global(qos: readQos.qosClass).async { [weak self] in
            self?.streamTask.readData(ofMinLength: 1, maxLength: maxLength, timeout: 0, completionHandler: { data, isEOF, error in
                if let error = error {
                    self?.onError?(error)
                    return
                }
                if isEOF {
                    print("EOF")
                    self?.streamTask = nil
                    if self?.connectionState == .disconnecting {
                        self?.connectionState = .disconnected
                    } else {
                        self?.connectionState = .dropped
                        self?.reconnect()
                    }
                    return
                }
                if let data = data {
                    self?.read(data)
                }
                self?.enqueueRead()
            })
        }
    }
    
    private func read(_ data: Data) {
        var buffer = ConsumableData(data)
        var packetType: ControlPacketType = .connack
        var multiplier = 1
        var remainingLength = 0
        
        readState = .readingFixedHeader
        
        while !buffer.atEnd {
            
            while readState == .readingFixedHeader && !buffer.atEnd {
                if let header = buffer.read(), let controlType = ControlPacketType(rawValue: header) {
                    packetType = controlType
                    readState = .readingRemainingLength
                    multiplier = 1
                    remainingLength = 0
                }
            }
            
            while readState == .readingRemainingLength && !buffer.atEnd {
                if let remaining = buffer.read() {
                    remainingLength += Int(remaining & 127) * multiplier
                    if remaining & 128 == 0x00 {
                        if remainingLength > 0 {
                            readState = .readingPayload
                        } else {
                            readState = .readingFixedHeader
                        }
                    } else {
                        multiplier *= 128
                    }
                } else {
                    readState = .readingFixedHeader
                }
            }
            
            while readState == .readingPayload && !buffer.atEnd {
                switch packetType {
                case .publish:
                    let topicHeaderLength = 2
                    guard let topicLengthBuffer = buffer.read(topicHeaderLength) else {
                        readState = .readingFixedHeader
                        break
                    }
                    
                    let topicLength = Int(topicLengthBuffer[0]) * 256 + Int(topicLengthBuffer[1])
                    
                    guard remainingLength > topicLength + 2 else {
                        readState = .readingFixedHeader
                        break
                    }
                    
                    guard let topicBuffer = buffer.read(topicLength), let topic = String(bytes: topicBuffer, encoding: .utf8) else {
                        readState = .readingFixedHeader
                        break
                    }
                    
                    // TODO: Is it legal to get a topic header but no message? This assumes not.
                    guard let messageBuffer = buffer.read(remainingLength - topicLength - topicHeaderLength) else {
                        readState = .readingFixedHeader
                        break
                    }
                    
                    onMessage?(topic, Data(messageBuffer))
                    readState = .readingFixedHeader
                
                case .connack:
                    onConnAck?()
                    readState = .readingFixedHeader
                    
                default:
                    readState = .readingFixedHeader
                }
            }
        }
        
        readState = .idle
    }
    
    // MARK: Write
    
    private func writeConnect() {
        var packet = ControlPacket(type: .connect)
        packet.payload += clientId
        
        // section 3.1.2.3
        var connectFlags: UInt8 = 0b00000010        // clean session
        
        if let username = username {
            connectFlags |= 0b10000000
            packet.payload += username
        }

        if let password = password {
            connectFlags |= 0b01000000
            packet.payload += password
        }
        
        packet.variableHeader += "MQTT"             // section 3.1.2.1
        packet.variableHeader += UInt8(0b00000100)  // section 3.1.2.2
        packet.variableHeader += connectFlags
        packet.variableHeader += pingInterval       // section 3.1.2.10
        
        write(packet: packet)
    }
    
    private func writeDisconnect(completion: ((_ success: Bool) -> ())? = nil) {
        write(packet: ControlPacket(type: .disconnect)) { success in
            completion?(success)
        }
    }
    
    private func sendSubscribe(to topic: String) {
        var packet = ControlPacket(type: .subscribe, flags: .reserved)
        packet.variableHeader += nextMessageId()
        packet.payload += topic    // section 3.8.3
        packet.payload += UInt8(0) // QoS = 0
        
        write(packet: packet)
    }
    
    private func writeUnsubscribe(from topic: String) {
        var packet = ControlPacket(type: .unsubscribe, flags: .reserved)
        packet.variableHeader += nextMessageId()
        packet.payload += topic
        
        write(packet: packet)
    }
    
    private func writePublish(to topic: String, message: Data) {
        var packet = ControlPacket(type: .publish)
        packet.variableHeader += topic // section 3.3.2
        // TODO: Add 2 (for messageId) if/when QOS > 0
        packet.payload += message      // section 3.3.3
        
        write(packet: packet)
    }
    
    private func writePing() {
        write(packet: ControlPacket(type: .pingreq))
    }
    
    private func write(packet: ControlPacket, completion: ((_ success: Bool) -> ())? = nil) {
        streamTask.write(packet.data, timeout: 10, completionHandler: { error in
            completion?(error != nil)
        })
    }
    
    private func nextMessageId() -> UInt16 {
        messageId = messageId &+ 1
        return messageId
    }
}
