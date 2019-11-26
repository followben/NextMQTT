# NextMQTT

![](https://github.com/followben/NextMQTT/workflows/Swift/badge.svg)

NextMQTT is a modern MQTT 5.0 client for iOS and watchOS.

It currently includes basic functionality including subscribe/ unsubscribe and publish/ receive with "at most once" ([QoS 0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html#_Toc3901235)) delivery.

Although the project is [actively maintained](#Roadmap), it is not yet production-ready and [contributions](#Contribute) are welcome.

## Use

Closures may be called on a background thread. Always dispatch to main before updating UI from a NextMQTTT closure.

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
mqtt.connect { result in
    switch result {
    case .success():
        print("connected")
    case .failure(let error):
        print(error.description)
    }
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
mqtt.onConnectionState = { state in
    print("new connection state is \(state)")
}
```
## Install

In your Xcode project, select File > Swift Packages > Add Package Dependency... and add `https://github.com/followben/NextMQTT`. For the latest stable changes, select the `master` branch.

NextMQTT has been tested on watchOS 6 and iOS 13. In theory NextMQTT will also work on macOS 12 and tvOS but this hasn't been verified.

## Contribute
PRs are welcome. For major changes, open an issue first to discuss what you would like to change.

Please ensure tests pass and are up-to-date.

## Roadmap
Planned features include:
* Session state & expiry
* Support for QoS 1 and 2
* Will Messages
* Properties, incl. User Properties
* Extended authentication flows

There is no plan to support MQTT 3.1, Websockets or Shared Subscriptions.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
