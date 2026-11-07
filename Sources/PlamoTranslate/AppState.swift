import AppKit
import AVFoundation
import SwiftUI
import Translation

@MainActor
final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { persistPreferences() } }
    @Published var records: [TranslationRecord]
    @Published var sourceText = ""
    @Published var output = ""
    @Published var sourceLanguage = "auto"
    @Published var targetLanguage = "en"
    @Published var context = ""
    @Published var glossary = ""
    @Published var isRunning = false
    @Published var error: String?
    @Published var notice: String?
    @Published var showSettings = false
    @Published var showOptions = false
    @Published var showSidebar = true
    @Published var selectedRecord: UUID?
    @Published var appleConfiguration: TranslationSession.Configuration?
    @Published var pendingRequest: TranslationRequest?
    @Published var completedEngine: Engine?
    @Published var elapsed: TimeInterval = 0
    let models: ModelManager
    private var debounce: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var startedAt = Date()
    private let store: LocalStore
    private let speaker = AVSpeechSynthesizer()

    init(store: LocalStore = LocalStore()) {
        self.store = store
        models = ModelManager(store: store)
        preferences = store.load("preferences.json", fallback: Preferences())
        records = store.load("history.json", fallback: [TranslationRecord]())
    }
    var ui: DisplayLanguage { preferences.language }
    func t(_ ja: String, _ en: String) -> String { ui == .ja ? ja : en }
    var colorScheme: ColorScheme? {
        switch preferences.appearance { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var canTranslate: Bool { !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceText.count <= 30000 }

    func sourceChanged() {
        invalidate()
        output = ""
        completedEngine = nil
        selectedRecord = nil
        if sourceText.count > 30000 {
            error = t("一度に翻訳できるのは30,000文字までです。", "Translate up to 30,000 characters at a time.")
            return
        }
        schedule()
    }
    func optionsChanged() {
        invalidate()
        output = ""
        completedEngine = nil
        schedule()
    }
    func schedule() {
        guard preferences.autoTranslate, canTranslate else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            self?.translate()
        }
    }
    func invalidate() {
        debounce?.cancel()
        translationTask?.cancel()
        appleConfiguration = nil
        pendingRequest = nil
        isRunning = false
        error = nil
        notice = nil
    }
    func stop() {
        invalidate()
        notice = t("翻訳を停止しました", "Translation stopped")
    }
    func translate() {
        invalidate()
        guard canTranslate else { return }
        let detected = sourceLanguage == "auto" ? Language.detect(sourceText) : sourceLanguage
        guard detected != targetLanguage else {
            error = t("原文と翻訳先が同じ言語です。翻訳先を変更してください。", "Source and target languages are the same. Choose another target.")
            return
        }
        let request = TranslationRequest(id: UUID(), text: sourceText, source: sourceLanguage, target: targetLanguage,
            engine: preferences.engine, endpoint: preferences.endpoint, context: context, glossary: glossary, polite: preferences.polite)
        pendingRequest = request
        output = ""
        completedEngine = nil
        isRunning = true
        startedAt = Date()
        if request.engine == .apple {
            appleConfiguration = .init(source: detected.map { Locale.Language(identifier: $0) }, target: .init(identifier: request.target))
            appleConfiguration?.invalidate()
        } else {
            translationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await models.startEngine()
                    try Task.checkCancellation()
                    guard pendingRequest?.id == request.id else { return }
                    var connected = request
                    connected = TranslationRequest(id: request.id, text: request.text, source: request.source,
                        target: request.target, engine: request.engine, endpoint: models.endpoint,
                        context: request.context, glossary: request.glossary, polite: request.polite, apiToken: models.token)
                    try await PlamoClient().translate(connected) { [weak self] chunk in
                        guard self?.pendingRequest?.id == request.id else { return }
                        self?.output += chunk
                    }
                    self.finish(request)
                } catch is CancellationError { } catch {
                    guard !Task.isCancelled else { return }
                    self.fail(error, request: request)
                }
            }
        }
    }
    func translateWithApple(_ session: TranslationSession, requestID: UUID?) async {
        guard let request = pendingRequest, request.id == requestID, request.engine == .apple else { return }
        do {
            let result = try await session.translate(request.text)
            try Task.checkCancellation()
            guard pendingRequest?.id == request.id else { return }
            output = result.targetText
            finish(request)
        } catch is CancellationError { } catch {
            guard !Task.isCancelled else { return }
            fail(error, request: request)
        }
    }
    func finish(_ request: TranslationRequest) {
        guard pendingRequest?.id == request.id else { return }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(AppFailure.message(t("翻訳結果が空でした。もう一度お試しください。", "The translation was empty. Try again.")), request: request)
            return
        }
        isRunning = false
        elapsed = Date().timeIntervalSince(startedAt)
        completedEngine = request.engine
        pendingRequest = nil
        if preferences.saveHistory {
            if let existing = records.first(where: { $0.source == request.text && $0.translation == output && $0.targetLanguage == request.target }) {
                selectedRecord = existing.id
            } else {
                let record = TranslationRecord(source: request.text, translation: output, sourceLanguage: request.source,
                    targetLanguage: request.target, engine: request.engine)
                records.insert(record, at: 0)
                // Favorites survive normal history pruning.
                let recent = Set(records.filter { !$0.favorite }.prefix(100).map(\.id))
                records.removeAll { !$0.favorite && !recent.contains($0.id) }
                selectedRecord = record.id
                persistHistory()
            }
        }
    }
    func fail(_ failure: Error, request: TranslationRequest) {
        guard pendingRequest?.id == request.id else { return }
        isRunning = false
        pendingRequest = nil
        let detail = (failure as? URLError) != nil && request.engine == .plamo
            ? t("PLaMoに接続できません。設定の「モデル」でモデルをメモリから解放し、再試行してください。", "Cannot connect to PLaMo. Unload the model in Settings → Models and retry.")
            : failure.localizedDescription
        error = detail
    }
    func newTranslation() {
        invalidate()
        sourceText = ""
        output = ""
        completedEngine = nil
        selectedRecord = nil
    }
    func restore(_ record: TranslationRecord) {
        invalidate()
        sourceText = record.source
        output = record.translation
        sourceLanguage = record.sourceLanguage
        targetLanguage = record.targetLanguage
        completedEngine = record.engine
        selectedRecord = record.id
    }
    func swap() {
        let source = sourceLanguage == "auto" ? (Language.detect(sourceText) ?? "ja") : sourceLanguage
        guard source != targetLanguage, Language.all.contains(where: { $0.id == source }) else { return }
        let original = sourceText
        let translated = output
        invalidate()
        sourceLanguage = targetLanguage
        targetLanguage = source
        sourceText = translated.isEmpty ? original : translated
        output = translated.isEmpty ? "" : original
        completedEngine = nil
        selectedRecord = nil
    }
    func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            notice = t("クリップボードにテキストがありません", "No text on the clipboard")
            return
        }
        sourceText = text
        sourceChanged()
    }
    func copy() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        notice = t("翻訳をコピーしました", "Translation copied")
    }
    func speak() {
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate); return }
        let utterance = AVSpeechUtterance(string: output)
        utterance.voice = AVSpeechSynthesisVoice(language: targetLanguage)
        speaker.speak(utterance)
    }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Translation.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try output.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
    func toggleFavorite(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].favorite.toggle()
        persistHistory()
    }
    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        if selectedRecord == id { selectedRecord = nil }
        persistHistory()
    }
    func clearHistory() {
        records = []
        selectedRecord = nil
        persistHistory()
    }
    private func persistPreferences() {
        do { try store.save(preferences, as: "preferences.json") }
        catch { self.error = t("設定を保存できませんでした: ", "Could not save settings: ") + error.localizedDescription }
    }
    private func persistHistory() {
        do { try store.save(records, as: "history.json") }
        catch { self.error = t("履歴を保存できませんでした: ", "Could not save history: ") + error.localizedDescription }
    }
}
