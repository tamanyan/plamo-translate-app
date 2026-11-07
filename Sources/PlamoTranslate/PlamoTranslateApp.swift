import SwiftUI

@main
struct PlamoTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.forLaunch()

    var body: some Scene {
        Window("PLaMo Translate", id: "main") {
            TranslationView(state: state)
                .preferredColorScheme(state.colorScheme)
                .background(WindowConnector(state: state, delegate: delegate))
                .sheet(isPresented: $state.showSettings) { SettingsView(state: state, models: state.models) }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(state.t("新しい翻訳", "New Translation")) { delegate.showMain(); state.newTranslation() }
                    .keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button(state.t("設定…", "Settings…")) { delegate.showMain(); state.showSettings = true }
                    .keyboardShortcut(",")
            }
            CommandMenu(state.t("翻訳", "Translation")) {
                Button(state.t("翻訳する", "Translate")) { state.translate() }
                    .keyboardShortcut(.return, modifiers: .command).disabled(!state.canTranslate)
                Button(state.t("停止", "Stop")) { state.stop() }.keyboardShortcut(".").disabled(!state.isRunning)
                Button(state.t("言語を入れ替え", "Swap Languages")) { state.swap() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button(state.t("翻訳をコピー", "Copy Translation")) { state.copy() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button(state.t("翻訳を書き出す…", "Export Translation…")) { state.export() }.disabled(state.output.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button(state.t("履歴の表示切り替え", "Toggle History")) { state.showSidebar.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .control])
            }
        }
    }
}

private struct WindowConnector: NSViewRepresentable {
    let state: AppState
    let delegate: AppDelegate
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                switch state.preferences.appearance {
                case .system: window.appearance = nil
                case .light: window.appearance = NSAppearance(named: .aqua)
                case .dark: window.appearance = NSAppearance(named: .darkAqua)
                }
                delegate.connect(state, window: window)
            }
        }
    }
}
