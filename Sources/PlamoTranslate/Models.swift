import Foundation
import NaturalLanguage

enum DisplayLanguage: String, Codable, CaseIterable { case ja, en }
enum Appearance: String, Codable, CaseIterable { case system, light, dark }
enum CloseBehavior: String, Codable, CaseIterable { case background, quit, ask }
enum Engine: String, Codable, CaseIterable { case apple, plamo }

struct Language: Identifiable, Hashable, Codable {
    let id: String
    let ja: String
    let en: String
    func name(_ ui: DisplayLanguage) -> String { ui == .ja ? ja : en }
    static let automatic = Language(id: "auto", ja: "言語を検出", en: "Detect language")
    static let all: [Language] = [
        .init(id: "ja", ja: "日本語", en: "Japanese"),
        .init(id: "en", ja: "英語", en: "English"),
        .init(id: "ko", ja: "韓国語", en: "Korean"),
        .init(id: "zh-Hans", ja: "中国語（簡体字）", en: "Chinese (Simplified)"),
        .init(id: "zh-Hant", ja: "中国語（繁体字）", en: "Chinese (Traditional)"),
        .init(id: "fr", ja: "フランス語", en: "French"),
        .init(id: "de", ja: "ドイツ語", en: "German"),
        .init(id: "es", ja: "スペイン語", en: "Spanish"),
        .init(id: "it", ja: "イタリア語", en: "Italian"),
        .init(id: "pt", ja: "ポルトガル語", en: "Portuguese"),
        .init(id: "ru", ja: "ロシア語", en: "Russian"),
        .init(id: "ar", ja: "アラビア語", en: "Arabic"),
        .init(id: "hi", ja: "ヒンディー語", en: "Hindi"),
        .init(id: "vi", ja: "ベトナム語", en: "Vietnamese"),
        .init(id: "th", ja: "タイ語", en: "Thai"),
        .init(id: "id", ja: "インドネシア語", en: "Indonesian"),
        .init(id: "uk", ja: "ウクライナ語", en: "Ukrainian"),
        .init(id: "tr", ja: "トルコ語", en: "Turkish"),
        .init(id: "pl", ja: "ポーランド語", en: "Polish"),
        .init(id: "nl", ja: "オランダ語", en: "Dutch")
    ]
    static func find(_ id: String) -> Language { all.first { $0.id == id } ?? automatic }
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
    var plamoCode: String {
        switch id { case "zh-Hans": return "zh-CN"; case "zh-Hant": return "zh-TW"; default: return id }
    }
}

struct Preferences: Codable, Equatable {
    var language: DisplayLanguage = .ja
    var appearance: Appearance = .system
    var closeBehavior: CloseBehavior = .ask
    var autoTranslate = true
    var saveHistory = true
    var shortcutEnabled = false
    var engine: Engine = .plamo
    var endpoint = "http://127.0.0.1:8080"
    var polite = true
}

struct TranslationRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var source: String
    var translation: String
    var sourceLanguage: String
    var targetLanguage: String
    var engine: Engine
    var favorite = false
}

struct TranslationRequest: Equatable {
    let id: UUID
    let text: String
    let source: String
    let target: String
    let engine: Engine
    let endpoint: String
    let context: String
    let glossary: String
    let polite: Bool
    var apiToken: String = ""
}

enum AppFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Atomic, local-only persistence. A corrupt file is preserved for recovery.
struct LocalStore {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlamoTranslate", isDirectory: true)
    }
    func load<T: Decodable>(_ name: String, fallback: T) -> T {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return fallback }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            try? FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name + ".corrupt-" + UUID().uuidString))
            return fallback
        }
    }
    func save<T: Encodable>(_ value: T, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(value)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
