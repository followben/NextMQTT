//
//  IntegerTests.swift
//  NextMQTTTests
//
//  Created by Ben Stovold on 23/10/19.
//

import XCTest

@testable import NextMQTT

final class IntegerTests: XCTestCase {

    func testUIntVarDescription() {
        XCTAssertEqual("0", UIntVar.min.description)
        XCTAssertEqual("268435455", UIntVar.max.description)
        XCTAssertEqual("12345678", try UIntVar(12345678 as UInt).description)
        XCTAssertEqual("1", UIntVar(1).description)
        XCTAssertEqual("8388608", try UIntVar(1 << 23).description)
        XCTAssertEqual("66", UIntVar(66).description)
    }
    
    func testUIntVarValueTooLarge() {
        var error: Error?
        XCTAssertThrowsError(try UIntVar(268435456 as UInt)) { error = $0 }
        XCTAssertTrue(error is UIntVar.Error)
        XCTAssertEqual(error as? UIntVar.Error, .valueTooLarge)
    }
    
    func testUIntVarMQTTEncode() {
        let aVarUInt: UIntVar = 123458909
        let expected: [UInt8] = [221, 170, 239, 58]
        let actual: [UInt8] = try! MQTTEncoder.encode(aVarUInt)
        XCTAssertEqual(expected, actual)
    }
    
    func testUIntVarZeroByteMQTTEncode() {
        let aVarUInt: UIntVar = 0
        let expected: [UInt8] = [0]
        let actual: [UInt8] = try! MQTTEncoder.encode(aVarUInt)
        XCTAssertEqual(expected, actual)
    }
    
    func testUIntVarMQTTDecodeFixedBytes() {
        let bytes: [UInt8] = [221, 170, 239, 58]
        let expected: UIntVar = 123458909
        let actual: UIntVar = try! MQTTDecoder.decode(UIntVar.self, data: bytes)
        XCTAssertEqual(expected, actual)
    }
    
    func testUIntVarMQTTDecodeByteStream() {
        let bytes: [UInt8] = [255, 255, 255, 127, 128]
        let expected: UIntVar = 268435455
        let actual: UIntVar = try! MQTTDecoder.decode(UIntVar.self, data: bytes)
        XCTAssertEqual(expected, actual)
    }
    
    func testUIntVarMQTTDecodeInvalidBytes() {
        var error: Error?
        let bytes: [UInt8] = [255, 255, 255, 128]
        XCTAssertThrowsError(try MQTTDecoder.decode(UIntVar.self, data: bytes)) { error = $0 }
        guard case .invalidUIntVar = (error as! MQTTDecoder.Error) else {
            return XCTAssert(false, "Expected .invalidUIntVar but got \(String(describing: error))")
        }
    }
}
