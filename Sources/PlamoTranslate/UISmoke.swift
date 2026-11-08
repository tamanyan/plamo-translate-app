import SwiftUI

/// Deterministic snapshots of real native windows. Uses a temporary store, never user history.
@MainActor
enum UISmoke {
    static func run(state: AppState, window: NSWindow) async {
        guard let index = CommandLine.arguments.firstIndex(of: "--ui-smoke-test"), CommandLine.arguments.count > index + 1 else { exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            state.preferences.autoTranslate = false
            NSApp.activate(ignoringOtherApps: true)
            state.preferences.closeBehavior = .background
            window.performClose(nil)
            guard !window.isVisible else { throw AppFailure.message("Background close did not hide the window") }
            state.preferences.appearance = .light
            let record = TranslationRecord(source: "ことばは、人と人をつなぐ。\n新しいアイデアを、世界へ届けよう。", translation: "Words connect people.\nShare your new ideas with the world.", sourceLanguage: "ja", targetLanguage: "en", engine: .plamo, favorite: true)
            state.records = [record]
            state.restore(record)
            window.setContentSize(NSSize(width: 1180, height: 740))
            window.makeKeyAndOrderFront(nil)
            try await settle()
            try capture(window, to: directory.appendingPathComponent("translation-ja.png"))
            state.preferences.language = .en
            state.preferences.appearance = .dark
            try await settle()
            try capture(window, to: directory.appendingPathComponent("translation-en-dark.png"))
            state.preferences.language = .ja
            state.preferences.appearance = .light
            for tab in 0...2 {
                let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
                panel.contentView = NSHostingView(rootView: SettingsView(state: state, models: state.models, initialTab: tab))
                panel.center(); panel.makeKeyAndOrderFront(nil)
                try await settle()
                try capture(panel, to: directory.appendingPathComponent("settings-\(tab).png"))
                panel.orderOut(nil)
            }
            print("UI snapshots: \(directory.path)")
            NSApp.terminate(nil)
        } catch { fputs("UI smoke failed: \(error)\n", stderr); exit(1) }
    }
    private static func settle() async throws { try await Task.sleep(for: .milliseconds(700)) }
    private static func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw AppFailure.message("No content view") }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw AppFailure.message("Cannot create bitmap") }
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { throw AppFailure.message("Cannot encode PNG") }
        try data.write(to: url)
    }
}

extension AppState {
    static func forLaunch() -> AppState {
        if CommandLine.arguments.contains("--ui-smoke-test") {
            return AppState(store: LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("PlamoUISmoke-" + UUID().uuidString)))
        }
        return AppState()
    }
}
