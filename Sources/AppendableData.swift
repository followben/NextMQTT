//
//  AppendableData.swift
//  SimpleMQTT
//
//  Created by Benjamin Stovold on 23/10/19.
//

import Foundation

struct AppendableData {
    var data = Data()
    
    static func += (block: inout AppendableData, byte: UInt8) {
        block.data.append(byte)
    }
    
    static func += (block: inout AppendableData, short: UInt16) {
        block += UInt8(short >> 8)
        block += UInt8(short & 0xFF)
    }
    
    static func += (block: inout AppendableData, data: Data) {
        block.data += data
    }
    
    static func += (block: inout AppendableData, string: String) {
        block += UInt16(string.utf8.count)
        block += string.data(using: .utf8)!
    }
}
