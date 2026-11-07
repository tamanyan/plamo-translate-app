import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var models: ModelManager
    @StateObject private var login = LoginService()
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var licenseModel: ModelEntry?
    @State private var deleteModel: ModelEntry?
    @State private var showNotices = false

    init(state: AppState, models: ModelManager, initialTab: Int = 0) {
        self.state = state
        self.models = models
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.t("設定", "Settings")).font(.title2.weight(.semibold))
                Spacer()
                Button(state.t("完了", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Picker("", selection: $tab) {
                Text(state.t("一般", "General")).tag(0)
                Text(state.t("モデル", "Models")).tag(1)
                Text(state.t("このアプリについて", "About")).tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if tab == 0 { general }
                    else if tab == 1 { modelList }
                    else { about }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 690, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(state.colorScheme)
        .sheet(item: $licenseModel) { entry in
            VStack(alignment: .leading, spacing: 16) {
                Text("PLaMo Community License").font(.title2.bold())
                Text(state.t("ダウンロード前に、ライセンス全文を確認してください。", "Review the full license before downloading."))
                ScrollView {
                    Text(licenseText).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(state.t("キャンセル", "Cancel")) { licenseModel = nil }
                    Spacer()
                    Button(state.t("同意してダウンロード", "Agree and download")) {
                        models.acceptLicense(); models.download(entry); licenseModel = nil
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 620, height: 600)
        }
        .alert(state.t("モデルを削除しますか？", "Delete this model?"), isPresented: Binding(get: { deleteModel != nil }, set: { if !$0 { deleteModel = nil } })) {
            Button(state.t("削除", "Delete"), role: .destructive) { if let entry = deleteModel { state.invalidate(); models.delete(entry) }; deleteModel = nil }
            Button(state.t("キャンセル", "Cancel"), role: .cancel) { deleteModel = nil }
        }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 26) {
            settingsSection(state.t("一般設定", "General settings")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.t("表示言語", "Display language")).font(.headline)
                    Text(state.t("アプリの画面に表示する言語を選択します。", "Choose the language used in the app.")).foregroundStyle(.secondary)
                    Picker("", selection: $state.preferences.language) { Text("日本語").tag(DisplayLanguage.ja); Text("English").tag(DisplayLanguage.en) }
                        .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.t("ウィンドウを閉じた時の動作", "When closing the window")).font(.headline)
                    Picker("", selection: $state.preferences.closeBehavior) {
                        Text(state.t("バックグラウンドで実行", "Keep running in the background")).tag(CloseBehavior.background)
                        Text(state.t("アプリを終了", "Quit the app")).tag(CloseBehavior.quit)
                        Text(state.t("毎回確認する", "Ask every time")).tag(CloseBehavior.ask)
                    }.pickerStyle(.radioGroup).labelsHidden()
                    Text(state.t("バックグラウンドではショートカットを引き続き使えます。メニューバーから再表示できます。", "Shortcuts remain available in the background. Reopen from the menu bar.")).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle(state.t("ログイン時にPLaMo翻訳を起動する", "Open PLaMo Translate at login"), isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if let error = login.error { Text(error).font(.caption).foregroundStyle(.red) }
                Picker(state.t("外観", "Appearance"), selection: $state.preferences.appearance) {
                    Text(state.t("システム", "System")).tag(Appearance.system)
                    Text(state.t("ライト", "Light")).tag(Appearance.light)
                    Text(state.t("ダーク", "Dark")).tag(Appearance.dark)
                }
                Toggle(state.t("翻訳履歴を保存する", "Save translation history"), isOn: $state.preferences.saveHistory)
            }
            settingsSection(state.t("ショートカットキー設定", "Keyboard shortcut")) {
                Toggle(state.t("選択したテキストを翻訳", "Translate selected text"), isOn: Binding(get: { state.preferences.shortcutEnabled }, set: {
                    state.preferences.shortcutEnabled = $0
                    if $0 { AppDelegate.requestAccessibility() }
                }))
                HStack {
                    Text(state.t("テキストを選択して ⌘C をすばやく2回押すと、コピーした内容を翻訳します。", "Select text and press ⌘C twice quickly to translate the copied text."))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘ C  +  C").font(.system(.body, design: .monospaced)).padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                if state.preferences.shortcutEnabled && !AXIsProcessTrusted() {
                    Button(state.t("アクセシビリティの許可を設定…", "Allow Accessibility access…")) { AppDelegate.requestAccessibility() }
                    Text(state.t("システム設定で許可した後、アプリを再起動してください。コピー可能なテキストで使えます。", "Restart the app after granting access in System Settings. Works with text that can be copied.")).font(.caption).foregroundStyle(.secondary)
                }
                Button(state.t("初期設定に戻す", "Reset shortcut")) { state.preferences.shortcutEnabled = false }
            }
        }
    }
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.t("PLaMoモデル", "PLaMo models")).font(.title3.bold())
                    Text(state.t("初めての方は 0.8B · Q4_K_M がおすすめです。", "Start with 0.8B · Q4_K_M.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSWorkspace.shared.open(models.directory) } label: { Image(systemName: "folder") }.help(state.t("保存先を開く", "Open model folder"))
            }
            if !models.engineStatus.isEmpty { Label(models.engineStatus, systemImage: models.isReady ? "bolt.fill" : "hourglass").font(.caption) }
            if let error = models.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ForEach(ModelEntry.builtIn) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.label).font(.headline)
                                if models.selected.id == entry.id { Text(state.t("選択中", "Selected")).font(.caption).foregroundStyle(.tint) }
                            }
                            Text(entry.formattedSize + " · " + state.t("推奨メモリ ", "Memory ") + entry.memoryRecommendation).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if models.activeDownload == entry.id {
                            Button(state.t("停止", "Pause")) { models.pauseDownload() }
                        } else if models.downloaded.contains(entry.id) {
                            if models.selected.id != entry.id {
                                Button(state.t("使う", "Use")) { state.invalidate(); models.select(entry) }
                            }
                            Button(role: .destructive) { deleteModel = entry } label: { Image(systemName: "trash") }
                        } else {
                            Button((models.partialBytes[entry.id] ?? 0) > 0 ? state.t("再開", "Resume") : state.t("ダウンロード", "Download")) {
                                if models.settings.acceptedLicense { models.download(entry) } else { licenseModel = entry }
                            }.disabled(models.activeDownload != nil)
                            if (models.partialBytes[entry.id] ?? 0) > 0 {
                                Button(role: .destructive) { deleteModel = entry } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    if models.activeDownload == entry.id {
                        ProgressView(value: Double(models.received), total: Double(entry.bytes))
                        Text(models.verifying ? state.t("SHA-256を検証中…", "Verifying SHA-256…") : "\(ByteCountFormatter.string(fromByteCount: models.received, countStyle: .file)) / \(entry.formattedSize)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button(state.t("モデルをメモリから解放", "Unload model")) { state.invalidate(); models.stopEngine() }.disabled(!models.isReady && !models.isStarting)
                Spacer()
                Link("PLaMo Community License ↗", destination: URL(string: "https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF/blob/main/LICENSE/en")!)
            }.font(.caption)
            Text(state.t("モデルはHugging Faceから取得し、サイズとSHA-256を検証します。取得後はオフラインで利用できます。", "Models are downloaded from Hugging Face and verified by size and SHA-256. Once downloaded, they work offline.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("PLaMo Translate", systemImage: "character.bubble.fill").font(.title.bold())
            Text("Built with PLaMo.").foregroundStyle(.secondary)
            Text(state.t("SwiftUI製のmacOS向けローカル翻訳アプリです。PLaMoはllama.cppのMetalエンジンで動作します。Apple翻訳も選択できます。", "A native SwiftUI translation app for macOS. PLaMo runs locally with llama.cpp and Metal. Apple Translation is also available."))
            Link(state.t("ソースコード", "Source code"), destination: URL(string: "https://github.com/tamanyan/plamo-translate-app")!)
            Link(state.t("参考実装：tanakh/plamo-translate-desktop", "Reference: tanakh/plamo-translate-desktop"), destination: URL(string: "https://github.com/tanakh/plamo-translate-desktop")!)
            Text(state.t("モデルのカタログとPFML形式は上記MITライセンスのプロジェクトを参考にしています。", "Model catalog and PFML format adapted from the MIT-licensed project above.")).font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(state.t("ライセンスと帰属表示", "Licenses and attribution"), isExpanded: $showNotices) {
                Text(resource("ThirdPartyNotices", "md")).font(.system(size: 11)).textSelection(.enabled).padding(.top, 10)
            }
        }
    }
    private var licenseText: String { resource("ModelLicense-" + state.ui.rawValue, "txt") }
    private func resource(_ name: String, _ ext: String) -> String {
        guard let url = AppResources.bundle.url(forResource: name, withExtension: ext), let text = try? String(contentsOf: url, encoding: .utf8) else { return "Resource unavailable" }
        return text
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }
}
