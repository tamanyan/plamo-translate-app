import AppKit
import Combine
import Darwin

@MainActor
final class ModelManager: ObservableObject {
    struct Settings: Codable {
        var selectedID = ModelEntry.builtIn[0].id
        var acceptedLicense = false
    }
    @Published private(set) var settings: Settings
    @Published private(set) var downloaded: Set<String> = []
    @Published private(set) var partialBytes: [String: Int64] = [:]
    @Published private(set) var activeDownload: String?
    @Published private(set) var received: Int64 = 0
    @Published private(set) var verifying = false
    @Published private(set) var engineStatus = ""
    @Published private(set) var isStarting = false
    @Published private(set) var isReady = false
    @Published var error: String?
    let directory: URL
    private let store: LocalStore
    private var downloadTask: Task<Void, Never>?
    private var process: Process?
    private var logHandle: FileHandle?
    private var generation = UUID()
    private var startup: Task<Void, Error>?
    private(set) var endpoint = ""
    private(set) var token = ""

    init(store: LocalStore = LocalStore()) {
        self.store = store
        directory = store.directory.appendingPathComponent("Models", isDirectory: true)
        settings = store.load("models.json", fallback: Settings())
        refresh()
    }
    var selected: ModelEntry { ModelEntry.builtIn.first { $0.id == settings.selectedID } ?? ModelEntry.builtIn[0] }
    var modelURL: URL { directory.appendingPathComponent(selected.fileName) }
    func refresh() {
        downloaded = Set(ModelEntry.builtIn.filter { entry in
            fileSize(directory.appendingPathComponent(entry.fileName)) == entry.bytes
        }.map(\.id))
        partialBytes = Dictionary(uniqueKeysWithValues: ModelEntry.builtIn.map {
            ($0.id, fileSize(directory.appendingPathComponent($0.partialName)))
        })
    }
    private func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
    func acceptLicense() { settings.acceptedLicense = true; persist() }
    func select(_ entry: ModelEntry) {
        guard settings.selectedID != entry.id else { return }
        stopEngine()
        settings.selectedID = entry.id
        persist()
    }
    private func persist() {
        do { try store.save(settings, as: "models.json") } catch { self.error = error.localizedDescription }
    }
    func download(_ entry: ModelEntry) {
        guard settings.acceptedLicense, activeDownload == nil else { return }
        error = nil
        activeDownload = entry.id
        received = partialBytes[entry.id] ?? 0
        verifying = received == entry.bytes
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let downloader = ModelDownloader(entry: entry, directory: directory) { [weak self] count in
                    Task { @MainActor in
                        guard self?.activeDownload == entry.id else { return }
                        self?.received = count
                        self?.verifying = count == entry.bytes
                    }
                }
                _ = try await downloader.run()
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            activeDownload = nil
            verifying = false
            refresh()
        }
    }
    func pauseDownload() { downloadTask?.cancel() }
    func delete(_ entry: ModelEntry) {
        guard activeDownload != entry.id else { return }
        if selected.id == entry.id { stopEngine() }
        do {
            for name in [entry.fileName, entry.partialName] {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    static func executable() -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama/llama-server"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/engine/current/llama-server"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/engine/llama-b12110/llama-server")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    func startEngine() async throws {
        if isReady, process?.isRunning == true { return }
        if let startup {
            try await startup.value
            try Task.checkCancellation()
            return
        }
        stopEngine()
        let task = Task { try await launchEngine() }
        startup = task
        let runID = generation
        defer { if generation == runID { startup = nil } }
        try await task.value
        try Task.checkCancellation()
    }
    private func launchEngine() async throws {
        guard downloaded.contains(selected.id) else {
            throw AppFailure.message("設定の「モデル」でPLaMoをダウンロードしてください。 / Download PLaMo in Settings → Models.")
        }
        guard let executable = Self.executable() else {
            throw AppFailure.message("翻訳エンジンがありません。scripts/fetch-engine.shを実行してください。 / Translation engine missing. Run scripts/fetch-engine.sh.")
        }
        let runID = generation
        isStarting = true
        engineStatus = "Loading · " + selected.label
        defer { if generation == runID { isStarting = false } }
        let port = try Self.availablePort()
        endpoint = "http://127.0.0.1:\(port)"
        token = UUID().uuidString + UUID().uuidString
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--model", modelURL.path, "--host", "127.0.0.1", "--port", String(port),
                           "--ctx-size", "16384", "--parallel", "1", "--gpu-layers", "99",
                           "--device", "MTL0", "--verbosity", "4", "--no-webui"]
        // A minimal environment prevents inherited llama.cpp flags from changing the bind address.
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LLAMA_API_KEY": token]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        logHandle = handle
        child.standardOutput = handle; child.standardError = handle
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.generation == runID else { return }
                self.isReady = false
                self.isStarting = false
                self.engineStatus = "Stopped (\(child.terminationStatus))"
                self.error = "翻訳エンジンが終了しました。 / Translation engine stopped."
            }
        }
        process = child
        do {
            try child.run()
            for _ in 0..<600 {
                try Task.checkCancellation()
                guard generation == runID, child.isRunning else {
                    throw AppFailure.message("エンジンを起動できません。モデルとengine.logを確認してください。 / Engine failed to start. Check the model and engine.log.")
                }
                var request = URLRequest(url: URL(string: endpoint + "/health")!)
                request.timeoutInterval = 1
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                if let (_, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    try Task.checkCancellation()
                    guard generation == runID else { throw CancellationError() }
                    isReady = true; engineStatus = "Metal · " + selected.label
                    return
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw AppFailure.message("モデルの読み込みがタイムアウトしました。 / Model loading timed out.")
        } catch {
            if generation == runID { stopEngine() }
            throw error
        }
    }
    func stopEngine() {
        generation = UUID()
        startup?.cancel(); startup = nil
        if let child = process, child.isRunning {
            child.terminate()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        try? logHandle?.close(); logHandle = nil
        isReady = false; isStarting = false; engineStatus = ""
        endpoint = ""; token = ""
    }
    func shutdown() { pauseDownload(); stopEngine() }
    private static func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AppFailure.message("Cannot create loopback socket") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw AppFailure.message("Cannot bind loopback socket") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard status == 0 else { throw AppFailure.message("Cannot get loopback port") }
        return UInt16(bigEndian: address.sin_port)
    }
}
