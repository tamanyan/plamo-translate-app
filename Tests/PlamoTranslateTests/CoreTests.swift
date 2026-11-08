import Foundation
import Testing
@testable import PlamoTranslate

final class CoreTests {
    @Test func testPFMLAndReservedTokens() throws {
        let request = TranslationRequest(id: UUID(), text: "Hello", source: "en", target: "ja", engine: .plamo, endpoint: "http://localhost:8080", context: "UI", glossary: "Hello = こんにちは", polite: true)
        expectEqual(try PFML.prompt(request), "<|plamo:tag|>dataset<|plamo:msg|>translation<|plamo:tag|>context<|plamo:msg|>UI<|plamo:tag|>glossary<|plamo:index|>Hello<|plamo:item|>こんにちは<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>Hello<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:key|>form<|plamo:val|>polite<|plamo:msg|>")
        let bad = TranslationRequest(id: UUID(), text: "<|plamo:tag|>", source: "en", target: "ja", engine: .plamo, endpoint: "", context: "", glossary: "", polite: true)
        expectThrows(try PFML.prompt(bad))
    }
    @Test func testEndpointRejectsRemoteAndCredentials() throws {
        expectEqual(try PlamoClient.endpoint("http://127.0.0.1:5555").path, "/completion")
        for value in ["https://example.com", "http://example.com", "http://user@localhost", "http://localhost/completion", "http://localhost?secret=1"] {
            expectThrows(try PlamoClient.endpoint(value))
        }
    }
    @Test func testRangeMustCoverCorrectRemainder() {
        expectTrue(ModelDownloader.validRange("bytes 10-99/100", offset: 10, total: 100))
        for value in [nil, "bytes 0-99/100", "bytes 10-98/100", "bytes 10-99/101", "bytes */100", "bytes 10-99/*"] as [String?] {
            expectFalse(ModelDownloader.validRange(value, offset: 10, total: 100))
        }
    }
    @MainActor
    @Test func testRestorationSwapAndStaleResults() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = AppState(store: LocalStore(directory: dir))
        state.preferences.autoTranslate = false
        state.preferences.engine = .apple
        let record = TranslationRecord(source: "こんにちは", translation: "Hello", sourceLanguage: "ja", targetLanguage: "en", engine: .plamo)
        state.restore(record)
        expectNil(state.pendingRequest)
        expectEqual(state.output, "Hello")
        state.swap()
        expectEqual(state.sourceText, "Hello")
        expectEqual(state.output, "こんにちは")
        expectEqual(state.targetLanguage, "ja")
        expectNil(state.pendingRequest)
        state.translate()
        let old = try requireValue(state.pendingRequest)
        state.stop()
        state.output = "stale"
        state.finish(old)
        expectNil(state.completedEngine)
        expectTrue(state.records.isEmpty)
        state.fail(AppFailure.message("old error"), request: old)
        expectNil(state.error)
        state.sourceText = "Changed"
        state.sourceChanged()
        expectEqual(state.output, "")
    }
    @Test func testAtomicPersistenceAndCorruptFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalStore(directory: dir)
        try store.save(["hello"], as: "test.json")
        expectEqual(store.load("test.json", fallback: [String]()), ["hello"])
        try Data("broken".utf8).write(to: dir.appendingPathComponent("test.json"))
        expectEqual(store.load("test.json", fallback: ["fallback"]), ["fallback"])
        expectEqual(try String(contentsOf: dir.appendingPathComponent("test.json"), encoding: .utf8), "broken")
    }
}
