# NextMQTT

NextMQTT is a modern MQTT 5.0 client for iOS and watchOS.

Currently functionality includes connect/ disconnect, subscribe/ unsubscribe, and publish/ receive, all with "at most once" ([QoS 0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901235)) delivery.

Although the project is [actively maintained](#Roadmap), it is not yet production-ready and [contributions](#Contribute) are welcome.

## Use

The api is closure-based, but closures may be called on a background thread. Always dispatch to main before updating UI from a NextMQTTT closure.

Create
```swift
mqtt = MQTT(host: "127.0.0.1", port: 1883)
// or
mqtt = MQTT(host: "my.mqttserver.com", port: 1883, username: "myuser", password: "mypassword", options: [
    .secureConnection: true,
    .pingInterval: 10,
    .clientId: "myclientid",
    .maxBuffer: 16384
])
```

Connect
```swift
mqtt.connect { error in
    guard error == nil else {
        print(error.description)
    }
    print("connected")
}
```

Subscribe
```swift
let topic = "/mytopic"
mqtt.subscribe(to: topic) { result in
    switch result {
    case .success():
        print("subscribed")
    case .failure(let error):
        print(error.description)
    }
}
```

Unsubscribe
```swift
let topic = "/mytopic"
mqtt.unSubscribe(from: topic) { result in
    switch result {
    case .success():
        print("unsubscribed")
    case .failure(let error):
        print(error.description)
    }
}
```

Publish
```swift
let jsonMessage = ["key" : "value"]
let encodedMessage = try! JSONEncoder().encode(json)
let topic = "/mytopic"
mqtt.publish(to: topic, data: encodedMessage)
```

Receive 
```swift
mqtt.onReceive = { topic, encodedMessage in
    print("received publish from \(topic)")
    if let data = encodedMessage, let message = try? JSONDecoder().decode(Message.self, from: data) {
        print(message)
    }
}
```

Monitor 
```swift
mqtt.onStatusChanged = { status in
    print("new connection status is \(status)")
}
```
## Install

Download the project and build either the iOS or watchOS target. Copy and link the resulting framework in your own Xcode project.

## Contribute
All PRs are welcome. For major changes, open an issue first to discuss what you would like to change.

Please ensure tests pass and are up-to-date.

## Roadmap
Planned features include:
* Session state & expiry
* Support for QoS 1 and 2
* Will Messages
* Properties, incl. User Properties
* Extended authentication flows

There is no plan to support MQTT 3.1 or Shared Subscriptions.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
