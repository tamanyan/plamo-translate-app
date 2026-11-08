import Foundation
import Testing
import CryptoKit
@testable import PlamoTranslate

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var responder: ((URLRequest, URLProtocolClient, URLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.responder?(request, client!, self) }
    override func stopLoading() { }
}

@Suite(.serialized) final class DownloadTests {
    private let payload = Data("verified model fixture".utf8)
    private var directory: URL!
    private var entry: ModelEntry!
    private var configuration: URLSessionConfiguration!
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        entry = ModelEntry(size: "fixture", quant: "test", revision: "test", bytes: Int64(payload.count), sha256: digest)
        configuration = .ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
    }
    deinit {
        FixtureProtocol.responder = nil
        try? FileManager.default.removeItem(at: directory)
    }
    private func serve(status: Int, headers: [String: String] = [:], data: Data, inspect: ((URLRequest) -> Void)? = nil) {
        FixtureProtocol.responder = { request, client, proto in
            inspect?(request)
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: data)
            client.urlProtocolDidFinishLoading(proto)
        }
    }
    private func download() async throws -> URL {
        try await ModelDownloader(entry: entry, directory: directory, configuration: configuration) { _ in }.run()
    }
    @Test func testResumeHashesPrefixAndSuffix() async throws {
        try payload.prefix(5).write(to: directory.appendingPathComponent(entry.partialName))
        serve(status: 206, headers: ["Content-Range": "bytes 5-\(payload.count - 1)/\(payload.count)"], data: payload.dropFirst(5)) { request in
            expectEqual(request.value(forHTTPHeaderField: "Range"), "bytes=5-")
        }
        let url = try await download()
        expectEqual(try Data(contentsOf: url), payload)
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.partialName).path))
    }
    @Test func testIgnoredRangeStartsOver() async throws {
        try payload.prefix(5).write(to: directory.appendingPathComponent(entry.partialName))
        serve(status: 200, data: payload)
        let url = try await download()
        expectEqual(try Data(contentsOf: url), payload)
    }
    @Test func testMalformedRangePreservesPrefixForRetry() async throws {
        try payload.prefix(5).write(to: directory.appendingPathComponent(entry.partialName))
        serve(status: 206, headers: ["Content-Range": "bytes 0-4/5"], data: payload)
        do { _ = try await download(); recordFailure("Invalid range accepted") } catch { }
        expectEqual(try Data(contentsOf: directory.appendingPathComponent(entry.partialName)), payload.prefix(5))
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path))
    }
    @Test func testWrongHashDeletesPartial() async throws {
        serve(status: 200, data: Data(repeating: 65, count: payload.count))
        do { _ = try await download(); recordFailure("Invalid hash accepted") } catch { }
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.partialName).path))
    }
    @Test func testTruncationRetainsPartial() async throws {
        serve(status: 200, data: payload.prefix(5))
        do { _ = try await download(); recordFailure("Truncated file accepted") } catch { }
        expectEqual(try Data(contentsOf: directory.appendingPathComponent(entry.partialName)), payload.prefix(5))
    }
    @Test func testCancelBeforeStartNeverPromotesModel() async throws {
        let task = Task { try await self.download() }
        task.cancel()
        do { _ = try await task.value; recordFailure("Cancelled download succeeded") } catch { }
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path))
    }
}

extension DownloadTests {
    @Test @MainActor func testCompletionStreamAndAuthentication() async throws {
        let events = "data: {\"content\":\"Hello\",\"stop\":false}\n\ndata: {\"content\":\" world\",\"stop\":false}\n\ndata: {\"stop\":true,\"stop_type\":\"eos\"}\n\n"
        serve(status: 200, data: Data(events.utf8)) { request in
            expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-secret")
            expectEqual(request.httpMethod, "POST")
        }
        let request = TranslationRequest(id: UUID(), text: "こんにちは", source: "ja", target: "en", engine: .plamo, endpoint: "http://127.0.0.1:1234", context: "", glossary: "", polite: true, apiToken: "fixture-secret")
        var text = ""
        try await PlamoClient(session: URLSession(configuration: configuration)).translate(request) { text += $0 }
        expectEqual(text, "Hello world")
    }
    @Test @MainActor func testCompletionRejectsDisconnectAndLimits() async throws {
        let request = TranslationRequest(id: UUID(), text: "こんにちは", source: "ja", target: "en", engine: .plamo, endpoint: "http://127.0.0.1:1234", context: "", glossary: "", polite: true)
        for events in ["data: {\"content\":\"partial\"}\n\n", "data: {\"stop\":true,\"stop_type\":\"limit\"}\n\n", "data: {\"stop\":true,\"truncated\":true}\n\n"] {
            serve(status: 200, data: Data(events.utf8))
            do {
                try await PlamoClient(session: URLSession(configuration: configuration)).translate(request) { _ in }
                recordFailure("Incomplete translation was accepted")
            } catch { }
        }
    }
    @Test func testActiveDownloadCancellationKeepsReceivedPrefix() async throws {
        let signal = AsyncStream<Int64>.makeStream()
        let prefix = Data(repeating: 65, count: 256 * 1024)
        serveWithoutFinishing(data: prefix)
        let entry = ModelEntry(size: "fixture", quant: "cancel", revision: "test", bytes: 1024 * 1024, sha256: "unused")
        let directory = directory!, configuration = configuration!
        let task = Task {
            defer { signal.continuation.finish() }
            return try await ModelDownloader(entry: entry, directory: directory, configuration: configuration) { count in
                if count > 0 { signal.continuation.yield(count) }
            }.run()
        }
        for await count in signal.stream {
            if count > 0 { break }
        }
        task.cancel()
        do { _ = try await task.value; recordFailure("Cancelled download succeeded") } catch { }
        signal.continuation.finish()
        expectEqual(try Data(contentsOf: directory.appendingPathComponent(entry.partialName)), prefix)
        expectFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path))
    }
    private func serveWithoutFinishing(data: Data) {
        FixtureProtocol.responder = { request, client, proto in
            client.urlProtocol(proto, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(proto, didLoad: data)
        }
    }
}
