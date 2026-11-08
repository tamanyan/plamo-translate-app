import Foundation
import Testing

// Small assertion functions keep callback-based URLProtocol fixtures readable.
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}
func expectTrue(_ value: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, Comment(rawValue: message), sourceLocation: sourceLocation)
}
func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}
func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
func expectThrows<T>(_ body: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try body(); Issue.record("Expected an error", sourceLocation: sourceLocation) } catch { }
}
func requireValue<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
    try #require(value, sourceLocation: sourceLocation)
}
func recordFailure(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
