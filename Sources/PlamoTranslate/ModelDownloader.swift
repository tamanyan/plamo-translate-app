import Foundation
import CryptoKit

/// Sequential URLSession callbacks stream directly to disk; memory use is independent of model size.
final class ModelDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let entry: ModelEntry
    private let directory: URL
    private let progress: @Sendable (Int64) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var handle: FileHandle?
    private var offset: Int64 = 0
    private var received: Int64 = 0
    private var responseError: Error?
    private var lastUpdate = Date.distantPast
    private let lock = NSLock()
    private var cancelled = false
    private let configuration: URLSessionConfiguration

    init(entry: ModelEntry, directory: URL, configuration: URLSessionConfiguration = .ephemeral,
         progress: @escaping @Sendable (Int64) -> Void) {
        self.entry = entry; self.directory = directory; self.progress = progress; self.configuration = configuration
    }
    func run() async throws -> URL {
        try Task.checkCancellation()
        let partial = directory.appendingPathComponent(entry.partialName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
        handle = try FileHandle(forUpdating: partial)
        defer { try? handle?.close(); handle = nil }
        offset = Int64(try handle!.seekToEnd())
        if offset > entry.bytes { try handle!.truncate(atOffset: 0); try handle!.seek(toOffset: 0); offset = 0 }
        received = offset
        if offset != entry.bytes {
            _ = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    self.continuation = continuation
                    var request = URLRequest(url: entry.url)
                    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                    if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
                    configuration.timeoutIntervalForRequest = 60
                    configuration.timeoutIntervalForResource = 86400
                    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                    let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                    lock.lock(); session = newSession; let isCancelled = cancelled; lock.unlock()
                    let task = newSession.dataTask(with: request)
                    task.resume()
                    if isCancelled { newSession.invalidateAndCancel() }
                }
            } onCancel: {
                self.lock.lock(); self.cancelled = true; let active = self.session; self.lock.unlock()
                active?.invalidateAndCancel()
            }
        } else { try handle?.close(); handle = nil }
        try Task.checkCancellation()
        let expected = entry
        // Hash in bounded chunks off the main actor, including any resumed prefix.
        let hashTask = Task.detached(priority: .utility) {
            try Self.sha256(of: partial)
        }
        let actual = try await withTaskCancellationHandler {
            try await hashTask.value
        } onCancel: { hashTask.cancel() }
        try Task.checkCancellation()
        guard actual == expected.sha256 else {
            try? FileManager.default.removeItem(at: partial)
            throw AppFailure.message("SHA-256が一致しません。再ダウンロードしてください。 / SHA-256 mismatch. Download again.")
        }
        let final = directory.appendingPathComponent(entry.fileName)
        if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
        try FileManager.default.moveItem(at: partial, to: final)
        return final
    }
    static func sha256(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func validRange(_ value: String?, offset: Int64, total: Int64) -> Bool {
        guard let value else { return false }
        let pieces = value.split(separator: " ")
        guard pieces.count == 2, pieces[0] == "bytes" else { return false }
        let rangeAndTotal = pieces[1].split(separator: "/")
        guard rangeAndTotal.count == 2, Int64(rangeAndTotal[1]) == total else { return false }
        let bounds = rangeAndTotal[0].split(separator: "-")
        return bounds.count == 2 && Int64(bounds[0]) == offset && Int64(bounds[1]) == total - 1
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        do {
            if http.statusCode == 200 {
                try handle?.truncate(atOffset: 0); try handle?.seek(toOffset: 0); received = 0
            } else if http.statusCode != 206 || !Self.validRange(http.value(forHTTPHeaderField: "Content-Range"), offset: offset, total: entry.bytes) {
                throw AppFailure.message("ダウンロード応答が不正です（HTTP \(http.statusCode)）。 / Invalid download response.")
            }
            progress(received)
            completionHandler(.allow)
        } catch { responseError = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard received + Int64(data.count) <= entry.bytes else { throw AppFailure.message("モデルのサイズが一致しません。 / Model size mismatch.") }
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            if Date().timeIntervalSince(lastUpdate) > 0.1 { progress(received); lastUpdate = Date() }
        } catch { responseError = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.synchronize(); try? handle?.close(); handle = nil
        session.finishTasksAndInvalidate()
        if let error = responseError ?? error { continuation?.resume(throwing: error) }
        else if received != entry.bytes { continuation?.resume(throwing: AppFailure.message("ダウンロードが中断されました。再開できます。 / Download interrupted. You can resume it.")) }
        else { progress(received); continuation?.resume(returning: directory.appendingPathComponent(entry.partialName)) }
        continuation = nil
        lock.lock(); self.session = nil; lock.unlock()
    }
}
