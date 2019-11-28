//
//  Transport.swift
//  NextMQTT
//
//  Created by Ben Stovold on 6/11/19.
//

import os
import Foundation

protocol TransportDelegate : AnyObject {

    func didStart(transport: Transport)

    func didReceive(packet: MQTTPacket, transport: Transport)

    /// Not called when connection results from `.stop()` being called
    func didStop(transport: Transport, error: Transport.Error?)
}

/// The possible connection states.
///
/// - initialised: The transport has been created by not started.
/// - starting: The transport is starting up, that is, the TCP connection is connecting.
/// - started: The transport has started up, that is, the TCP connection is in place.
/// - stopped: The transport has stopped.  If the error is nil the transport
///     stopped because either the client called `stop()` or an EOF on the TCP
///     connection. If the error is not nil, something went wrong with the TCP
///     connection.

enum TransportState {
    case initialised
    case starting
    case started
    case stopped(Error?)
}

final class Transport {
    
    private var state: State = .initialised

    let name: String
    let useTLS: Bool
    let queue: DispatchQueue
    let maxBuffer: Int
    let streamTaskMaker: () -> URLSessionStreamTask

    weak var delegate: TransportDelegate? = nil
    
    var transportState: TransportState {
        return self.state.transportState
    }
    
    deinit {
        // If this assert fires you’ve released the last reference to this
        // transport without stopping it.
        switch self.state {
        case .initialised: break
        case .started:     fatalError()
        case .stopped:     break
        }
    }

    /// Creates an object that will communicate over a stream task created by
    /// calling the stream task maker closure.
    ///
    /// The `streamTaskMaker` closure means that the client is in change of
    /// stream task creation, which is useful because it allows the client to
    /// manage the `URLSession` in which the streams are created.
    ///
    /// - Parameters:
    ///   - name: A name for the connection; not used internally, but handy while
    ///     debuging.
    ///   - use: Whether to enable TLS or not.
    ///   - queue: The queue on which to operate; delegate callbacks are called
    ///     on this queue.
    ///   - streamTaskMaker: A closure called to create the stream task for this
    ///     connection.  The resulting stream task is ‘owned‘ by this object.
    ///     You can’t go modifying it after the fact.  The stream task must not
    ///     be resumed; this object takes care of resuming it.

    required init(name: String, useTLS: Bool, maxBuffer: Int, queue: DispatchQueue, streamTaskMaker: @escaping () -> URLSessionStreamTask) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.name = name
        self.useTLS = useTLS
        self.queue = queue
        self.maxBuffer = maxBuffer
        self.streamTaskMaker = streamTaskMaker
    }
    
    /// Creates an object that will communicate with the specified host and
    /// port, optionally using TLS.
    ///
    /// - Parameters:
    ///   - hostName: The host name to connect to (can be an IP address, both IPv4 and IPv6).
    ///   - port: The port on which to connect.
    ///   - useTLS: Whether to enable TLS or not.
    ///   - queue: The queue on which to operate; delegate callbacks are called
    ///     on this queue.

    convenience init(hostName: String, port: Int, useTLS: Bool, maxBuffer: Int, queue: DispatchQueue) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.init(name: "\(hostName):\(port)", useTLS: useTLS, maxBuffer: maxBuffer, queue: queue, streamTaskMaker: { () -> URLSessionStreamTask in
            return URLSession.shared.streamTask(withHostName: hostName, port: port)
        })
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        process(event: .start)
    }
    
    func send(packet: EncodablePacket) {
        dispatchPrecondition(condition: .onQueue(queue))
        os_log("Sending: %@", log: .mqtt, type: .debug, String(describing: packet))
        process(event: .send(packet: packet))
    }
    
    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        process(event: .stop(error: nil, notify: false))
    }
    
    enum Error : Swift.Error {
        case streamTaskError(Swift.Error)
        case decodingError(MQTTDecoder.Error)
        case encodingError(MQTTEncoder.Error)
    }
    
}

extension Transport {

    /// Holds the runtime state of this object.  Each state maps to a state in
    /// `TransportState` but many states have an associated value that holds
    /// all the values valid during that states.
    ///
    /// - note: Stream task have no notion of a ‘did connect’ event, so there’s
    ///     no ‘starting’ state here.

    private enum State {
        case initialised
        case started(Started)
        case stopped(Error?)
        
        /// Returns the transport state associated with our state.
        
        var transportState: TransportState {
            switch self {
            case .initialised: return .initialised
            case .started: return .started
            case .stopped(let error): return .stopped(error)
            }
        }
    }

    /// Holds the values meaningful in the `.started` state.

    private struct Started {
        var streamTask: URLSessionStreamTask
        var decoder: MQTTDecoder
    }

    /// Events that trigger changes of state.
    ///
    /// - start: The client has called `start()`.
    /// - send: The client has called `send(message:)`.
    /// - stop: The client has called `stop()` (`notify` false) or something has
    ///     caused the stream to stop (`notify` true).  `error` will be nil if
    ///     the stop was orderly (either because the client called `stop()` or
    ///     because there was on EOF on the stream, or non-nil otherwise.
    /// - readCompleted: A read operation has completed.

    private enum Event {
        case start
        case send(packet: EncodablePacket)
        case readCompleted(data: Data, isEOF: Bool)
        case stop(error: Error?, notify: Bool)
    }

    /// Processes an event in the state machine.  All the heavy lifting here is
    /// done in state event functions, which take the state as a parameter and
    /// return a new state as the function result.

    private func process(event: Event) {
        dispatchPrecondition(condition: .onQueue(queue))

        switch (state, event) {
        case (.initialised, .start):
            state = handleStart()
        case (_, .start):
            fatalError()
        case (.started(let started), .send(let packet)):
            state = handleSend(packet: packet, started: started)
        case (_, .send):
            fatalError()
        case (.started(let started), .readCompleted(let data, let isEOF)):
            state = handleReadCompleted(data: data, isEOF: isEOF, started: started)
        case (_, .readCompleted):
            fatalError()
        case (let _state, .stop(let error, let notify)):
            state = handleStop(error: error, notify: notify, state: _state)
        }
    }

    /// Runs the supplied closure after the current state machine event has
    /// completed.  This is primarily used to post delegate events from a
    /// a state event function.
    ///
    /// - warning: It is critical that the closure check the current state
    ///     before acting.  It’s quite possible for some intervening event to
    ///     change the state to invalidate the resaon why the closure was
    ///     scheduled in the first place.
    ///
    /// This function is safe to call from any context and can, in fact, be
    /// called on a secondary thread (the thread running the `URLSession`’s
    /// delegate queue) courtesy of the stream task completion closures.
    ///
    /// - Parameter body: The closure to call.  This is passed the current state
    ///     as a parameter but, unlike a state event function, is not able to
    ///     return a new state directly (although it can call `process(event:)`
    ///     if necessary).
    
    private func deferred(_ body: @escaping (State) -> Void) {
        self.queue.async {
            dispatchPrecondition(condition: .onQueue(self.queue))
            body(self.state)
        }
    }

    /// The state event function for the `.start` event.  Transitions the object
    /// from the `.initialised` state to the `.started` state.
    ///
    /// There’s a couple of things to note here:
    ///
    /// * Stream task have no notion of a ‘did connect’ event, so we transition
    ///     straight from `.initialised` to `.started` no ‘starting’ state here.
    ///
    /// * We can’t call the delegate directly here because we _return_ the new
    ///     state, so the new state isn’t applied until we return.  If we called
    ///     the delegate directly, it would see us in the wrong state.
    ///
    ///     Instead we defer the delegate callback via a deferred closure.  That
    ///     must check the state to make sure we haven’t failed in the interim.
    ///
    /// - Returns: The new state.
    
    private func handleStart() -> State {
        dispatchPrecondition(condition: .onQueue(queue))
        let streamTask = self.streamTaskMaker()
        if useTLS {
            streamTask.startSecureConnection()
        }
        streamTask.resume()
        deferred { state in
            guard case .started = state else { return }
            self.delegate?.didStart(transport: self)
        }
        return setupRead(started: Started(
            streamTask: streamTask,
            decoder: MQTTDecoder()
        ))
    }

    /// The state event function for the `.send` event.  Called when the object
    /// is in the `.started` state and typically leaves the object in the same
    /// state (although with various associated values changed).
    ///
    /// - Parameters:
    ///   - message: The message to be sent.
    ///   - started: The value associated with the `.started` state.
    /// - Returns: The new state.

    private func handleSend(packet: EncodablePacket, started: Started) -> State {
        dispatchPrecondition(condition: .onQueue(queue))
        let started = started
        var encoded: [UInt8]
        do {
            encoded = try MQTTEncoder.encode(packet)
        } catch let error as MQTTEncoder.Error {
            return self.handleStop(error: Error.encodingError(error), notify: true, state: .started(started))
        } catch {
            fatalError()
        }
        started.streamTask.write(Data(encoded), timeout: 60.0) { (error) in
            if let error = error {
                self.deferred { _ in
                    self.process(event: .stop(error: .streamTaskError(error), notify: true))
                }
            }
        }
        return .started(started)
    }

    /// The state event function for the `.stop` event.  Can be called in any
    /// state and transitions the object to the `.stopped` state.
    ///
    /// - Parameters:
    ///   - error: If not nil, this holds the error that caused the
    ///     transition; if nil, the transition was not due to an error (it was
    ///     either triggered by the client calling `stop()` or by EOF on the
    ///     network).
    ///   - notify: If true, the client is notified of the stop via the
    ///     `didStop(transport:)` delegate callback.
    ///   - state: The current state.
    /// - Returns: The new state.

    private func handleStop(error: Error?, notify: Bool, state: State) -> State {
        dispatchPrecondition(condition: .onQueue(queue))

        // If we’re already stopped, do nothing.

        if case .stopped = state { return state }

        // Clean up based on the current state.

        switch state {
        case .initialised:
            break
        case .started(let started):
            started.streamTask.closeRead()
            started.streamTask.closeWrite()
        case .stopped:
            fatalError()
        }

        // Set up a delegate callback, if required.

        if notify {
            self.deferred { _ in
                // We don't need to check the state here because the check above
                // means that only one person can ever schedule this delegate
                // callback.  Moreover, if it was scheduled it needs to be
                // called.
                self.delegate?.didStop(transport: self, error: error)
            }
        }
        return .stopped(error)
    }

    /// The state event function for the `.readCompleted` event.  Called when
    /// the object is in the `.started` state and typically leaves the object in
    /// the same state (although with various associated values changed).
    ///
    /// This code is a little tricky because:
    ///
    /// * The decoder can error, which will stop the stream.
    ///
    /// * The decoder can generate multiple messages, which each have to
    ///   delivered to the delegate via a deferred closure.
    ///
    /// * The stream task could be at EOF, which generates a `.stop` event.
    ///   This can’t be issued directly because there could be messages in front
    ///   of it. Rather, the stop event has to be deferred until after the
    ///   message delivery is done.
    ///
    /// - Parameters:
    ///   - data: The data that was read; may be empty.
    ///   - isEOF: True if this is the last data that can be read.
    ///   - started: The value associated with the `.started` state.
    /// - Returns: The new state.

    private func handleReadCompleted(data: Data, isEOF: Bool, started: Started) -> State {
        dispatchPrecondition(condition: .onQueue(queue))
        
        // If we received data, run it through the decoder.
        var packets: [MQTTPacket]
        do {
            started.decoder.append([UInt8](data))
            packets = try started.decoder.decode([MQTTPacket].self)
            // TODO: drop?
        } catch let error as MQTTDecoder.Error {
            return self.handleStop(error: Error.decodingError(error), notify: true, state: .started(started))
        } catch {
            fatalError()
        }
        
        // Schedule the delivery of the messages to the delegate.  When each of
        // deferred closures run they have to check the state of the object to
        // ensure it hasn't stopped in the meantime.
        
        for packet in packets {
            self.deferred { state in
                guard case .started = state else { return }
                self.delegate?.didReceive(packet: packet, transport: self)
            }
        }
        
        // If we’re at EOF, schedule a `.stop` event to shut things down.   If
        // not, we set up the next read.  Both of these have to return an
        // appropriate new state.
        
        if isEOF {
            self.deferred { state in
                guard case .started = state else { return }
                self.process(event: .stop(error: nil, notify: true))
            }
            return .started(started)
        } else {
            return self.setupRead(started: started)
        }
    }

    /// Starts a read request on the stream task.  Called when the object is in
    /// the `.started` state and leaves the object in the same state.
    ///
    /// - Parameters:
    ///   - started: The value associated with the `.started` state.
    /// - Returns: The new state.

    private func setupRead(started: Started) -> State {
        dispatchPrecondition(condition: .onQueue(queue))
        started.streamTask.readData(ofMinLength: 1, maxLength: maxBuffer, timeout: 60) { (data, isEOF, error) in
            self.deferred { state in
                guard case .started = state else { return }
                if let error = error {
                    self.process(event: .stop(error: .streamTaskError(error), notify: true))
                } else {
                    self.process(event: .readCompleted(data: data ?? Data(), isEOF: isEOF))
                }
            }
        }
        return .started(started)
    }
}
