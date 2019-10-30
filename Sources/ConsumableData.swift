//
//  ConsumableData.swift
//  SimpleMQTT
//
//  Created by Benjamin Stovold on 23/10/19.
//

import Foundation

struct ConsumableData {
    let data:Data
    var index = 0
    var atEnd:Bool {
        return index >= data.count
    }

    init(_ data:Data) {
        self.data = data
    }

    mutating func read() -> UInt8? {
        guard !atEnd else { return nil }
        let byte = data[index]
        index += 1
        return byte
    }

    mutating func read(_ count:Int) -> [UInt8]? {
        guard index + count <= data.count else { return nil }
        let subdata = data.subdata(in: index..<index + count)
        index += count
        return [UInt8](subdata)
    }

    mutating func upTo(_ marker:UInt8) -> [UInt8]? {
        guard let end = (index..<data.count).firstIndex( where: { data[$0] == marker } ) else {  return nil }
        
        let upTo = read(end - index)
        self.skip() // consume the marker
        return upTo
    }

    mutating func skip(_ count:Int = 1) {
        index += count
    }

    mutating func skipThrough(_ marker:UInt8) {
        if let end = (index..<data.count).firstIndex( where: { data[$0] == marker } ) {
            index = end + 1
        } else {
            index = data.count
        }
    }
}
