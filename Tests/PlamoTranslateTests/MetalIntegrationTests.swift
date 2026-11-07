import Foundation
import Testing
@testable import PlamoTranslate

final class MetalIntegrationTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PLAMO_METAL_TEST"] == "1"))
    func testRealDownloadAndMetalTranslation() async throws {
        guard ProcessInfo.processInfo.environment["PLAMO_ACCEPT_MODEL_LICENSE"] == "1" else {
            recordFailure("Review the bundled PLaMo Community License before opting in"); return
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/metal-verification")
        let manager = ModelManager(store: LocalStore(directory: root))
        defer { manager.shutdown() }
        let model = ModelEntry.builtIn[0]
        if !manager.downloaded.contains(model.id) {
            _ = try await ModelDownloader(entry: model, directory: manager.directory) { count in
                if count == model.bytes { print("Model downloaded; checking SHA-256") }
            }.run()
            manager.refresh()
        }
        let first = Task { try await manager.startEngine() }
        await Task.yield()
        let second = Task { try await manager.startEngine() }
        first.cancel()
        do { try await first.value; recordFailure("Cancelled startup waiter succeeded") }
        catch is CancellationError { }
        try await second.value
        expectTrue(manager.isReady)
        let unauthenticated = URLRequest(url: try PlamoClient.endpoint(manager.endpoint))
        let (_, response) = try await URLSession.shared.data(for: unauthenticated)
        expectEqual((response as? HTTPURLResponse)?.statusCode, 401)
        let request = TranslationRequest(id: UUID(), text: "今日はとても良い天気です。", source: "ja", target: "en", engine: .plamo, endpoint: manager.endpoint, context: "", glossary: "", polite: true, apiToken: manager.token)
        var text = ""
        try await PlamoClient().translate(request) { text += $0 }
        expectFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        expectTrue(text.lowercased().contains("today") || text.lowercased().contains("weather"), "Unexpected translation: \(text)")
        print("Metal translation: \(text)")
        let log = try String(contentsOf: manager.directory.appendingPathComponent("engine.log"), encoding: .utf8)
        expectTrue(log.contains("using device MTL0"))
        expectTrue(log.contains("offloaded 17/17 layers to GPU"))
    }
}
