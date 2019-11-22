import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(UIntVarTests.allTests),
        testCase(PacketTests.allTests),
        testCase(TransportTests.allTests),
    ]
}
#endif
