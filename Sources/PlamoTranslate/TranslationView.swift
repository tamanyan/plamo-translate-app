import SwiftUI
import Translation

private let accent = Color(red: 0.08, green: 0.48, blue: 0.41)

struct TranslationView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var confirmClear = false
    var body: some View {
        HStack(spacing: 0) {
            if state.showSidebar { sidebar.frame(width: 235); Divider() }
            workspace
        }
        .frame(minWidth: 880, minHeight: 580)
        .tint(accent)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { state.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(state.t("履歴の表示切り替え", "Toggle history"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { state.showSettings = true } label: { Image(systemName: "gearshape") }
                    .help(state.t("設定", "Settings"))
            }
        }
        .translationTask(state.appleConfiguration) { [requestID = state.pendingRequest?.id] session in
            await state.translateWithApple(session, requestID: requestID)
        }
        .alert(state.t("すべての履歴を削除しますか？", "Delete all history?"), isPresented: $confirmClear) {
            Button(state.t("削除", "Delete"), role: .destructive) { state.clearHistory() }
            Button(state.t("キャンセル", "Cancel"), role: .cancel) { }
        } message: { Text(state.t("お気に入りも含め、保存した翻訳を削除します。", "This also removes favorites.")) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image(systemName: "character.bubble.fill").font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLaMo").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("TRANSLATE").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
            Button { state.newTranslation() } label: {
                Label(state.t("新しい翻訳", "New translation"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
            }.buttonStyle(.bordered).controlSize(.large)
            TextField(state.t("履歴を検索", "Search history"), text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Text(state.t("翻訳履歴", "HISTORY")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "star.fill" : "star") }
                    .help(state.t("お気に入りのみ", "Favorites only"))
            }.buttonStyle(.plain)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filteredRecords) { record in
                        Button { state.restore(record) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(record.source).lineLimit(2).multilineTextAlignment(.leading)
                                    if record.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(accent) }
                                }
                                HStack {
                                    Text(Language.find(record.targetLanguage).name(state.ui))
                                    Spacer()
                                    Text(record.date, style: .date)
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(state.selectedRecord == record.id ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(state.t(record.favorite ? "お気に入りを解除" : "お気に入りに追加", record.favorite ? "Unfavorite" : "Favorite")) { state.toggleFavorite(record.id) }
                            Button(state.t("削除", "Delete"), role: .destructive) { state.delete(record.id) }
                        }
                    }
                    if filteredRecords.isEmpty {
                        Text(state.t("翻訳はこのデバイスに\n保存されます", "Translations are saved\non this device"))
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.top, 35)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Label(state.t("デバイス内で翻訳", "On-device translation"), systemImage: "lock.shield")
                Spacer()
                Button { confirmClear = true } label: { Image(systemName: "trash") }
                    .disabled(state.records.isEmpty).help(state.t("履歴をすべて削除", "Clear history"))
            }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    private var filteredRecords: [TranslationRecord] {
        state.records.filter { (!favoritesOnly || $0.favorite) && (search.isEmpty || $0.source.localizedCaseInsensitiveContains(search) || $0.translation.localizedCaseInsensitiveContains(search)) }
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.t("ことばを、もっと自由に。", "Let your words travel.")).font(.system(size: 26, weight: .semibold))
                    Text(state.t("あなたのMacで、すばやく、プライベートに翻訳。", "Fast, private translation. Right on your Mac."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(state.t("エンジン", "Engine"), selection: Binding(get: { state.preferences.engine }, set: { state.preferences.engine = $0; state.optionsChanged() })) {
                    Text("PLaMo").tag(Engine.plamo)
                    Text("Apple").tag(Engine.apple)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }.padding(.top, 12)
            HStack {
                languagePicker(source: true)
                Spacer()
                Button { state.swap() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .medium)) }
                    .buttonStyle(.plain).help(state.t("言語を入れ替え", "Swap languages"))
                Spacer()
                languagePicker(source: false)
            }.padding(.horizontal, 12)
            HStack(spacing: 0) {
                textPane(source: true)
                Divider()
                textPane(source: false)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.09)))
            HStack {
                Toggle(state.t("自動翻訳", "Auto translate"), isOn: Binding(get: { state.preferences.autoTranslate }, set: {
                    state.preferences.autoTranslate = $0
                    state.invalidate()
                    if $0 { state.schedule() }
                })).toggleStyle(.switch).controlSize(.small)
                Button { state.showOptions.toggle() } label: { Label(state.t("翻訳オプション", "Options"), systemImage: "slider.horizontal.3") }
                    .buttonStyle(.plain).padding(.leading, 12).disabled(state.preferences.engine != .plamo)
                Spacer()
                if state.isRunning {
                    ProgressView().controlSize(.small)
                    Button(state.t("停止", "Stop")) { state.stop() }.buttonStyle(.bordered)
                } else {
                    Button { state.translate() } label: {
                        Label(state.t("翻訳する", "Translate"), systemImage: "arrow.right").padding(.horizontal, 12).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).disabled(!state.canTranslate)
                }
            }.font(.callout)
            if state.showOptions && state.preferences.engine == .plamo { options }
            HStack(spacing: 7) {
                Image(systemName: state.error == nil ? "checkmark.shield" : "exclamationmark.circle")
                Text(state.error ?? state.notice ?? state.t("テキストと翻訳履歴はこのMacに保存されます。", "Text and history stay on this Mac."))
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(state.error == nil ? Color.secondary : Color.red)
        }.padding(28)
    }
    private func languagePicker(source: Bool) -> some View {
        Menu {
            if source { Button(Language.automatic.name(state.ui)) { chooseLanguage("auto", source: source) } }
            ForEach(Language.all) { language in
                Button(language.name(state.ui)) { chooseLanguage(language.id, source: source) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(Language.find(source ? state.sourceLanguage : state.targetLanguage).name(state.ui))
                Image(systemName: "chevron.down").font(.caption)
            }.font(.callout.weight(.medium)).foregroundStyle(.primary).padding(.vertical, 6)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
    private func chooseLanguage(_ id: String, source: Bool) {
        if source { state.sourceLanguage = id } else { state.targetLanguage = id }
        state.optionsChanged()
    }
    private func textPane(source: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(source ? state.t("原文", "SOURCE") : state.t("翻訳", "TRANSLATION"))
                    .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                if source {
                    Button { state.newTranslation() } label: { Image(systemName: "xmark") }
                        .disabled(state.sourceText.isEmpty).help(state.t("クリア", "Clear"))
                } else if let id = state.selectedRecord {
                    Button { state.toggleFavorite(id) } label: {
                        Image(systemName: state.records.first(where: { $0.id == id })?.favorite == true ? "star.fill" : "star")
                    }.help(state.t("お気に入り", "Favorite"))
                }
            }.buttonStyle(.plain)
            ZStack(alignment: .topLeading) {
                if (source ? state.sourceText : state.output).isEmpty {
                    Text(source ? state.t("翻訳するテキストを入力、\nまたはペーストしてください。", "Type or paste your text here.") : state.t("翻訳結果がここに表示されます。", "Your translation will appear here."))
                        .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                }
                if source {
                    TextEditor(text: Binding(get: { state.sourceText }, set: { state.sourceText = $0; state.sourceChanged() }))
                        .scrollContentBackground(.hidden).accessibilityLabel(state.t("翻訳するテキスト", "Text to translate"))
                } else {
                    ScrollView {
                        Text(state.output).frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled).padding(.top, 8).padding(.horizontal, 5)
                    }.accessibilityLabel(state.t("翻訳結果", "Translation result"))
                }
            }.font(.system(size: 17)).lineSpacing(7).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 14) {
                if source {
                    Button { state.paste() } label: { Label(state.t("ペースト", "Paste"), systemImage: "doc.on.clipboard") }
                    Spacer()
                    Text("\(state.sourceText.count.formatted()) / 30,000").foregroundStyle(.tertiary)
                } else {
                    Button { state.copy() } label: { Image(systemName: "doc.on.doc") }.help(state.t("コピー", "Copy"))
                    Button { state.speak() } label: { Image(systemName: "speaker.wave.2") }.help(state.t("読み上げ", "Read aloud"))
                    Button { state.export() } label: { Image(systemName: "square.and.arrow.up") }.help(state.t("書き出す", "Export"))
                    Spacer()
                    if let engine = state.completedEngine { Text("\(engine == .plamo ? "PLaMo" : "Apple") · \(state.elapsed, specifier: "%.1f")s").foregroundStyle(.tertiary) }
                }
            }.font(.caption).buttonStyle(.plain).disabled(!source && state.output.isEmpty)
        }.padding(20).frame(maxWidth: .infinity)
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(state.t("日本語は「です・ます」調にする", "Use polite Japanese"), isOn: Binding(get: { state.preferences.polite }, set: { state.preferences.polite = $0; state.optionsChanged() }))
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(state.t("参考コンテキスト", "Reference context")).font(.caption).foregroundStyle(.secondary)
                    TextField(state.t("例：ソフトウェアの操作説明", "e.g. Software documentation"), text: optionBinding(\.context), axis: .vertical)
                }
                VStack(alignment: .leading) {
                    Text(state.t("用語集（1行に 原語 = 訳語）", "Glossary (source = target per line)")).font(.caption).foregroundStyle(.secondary)
                    TextField("workspace = ワークスペース", text: optionBinding(\.glossary), axis: .vertical)
                }
            }.textFieldStyle(.roundedBorder)
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
    private func optionBinding(_ keyPath: ReferenceWritableKeyPath<AppState, String>) -> Binding<String> {
        Binding(get: { state[keyPath: keyPath] }, set: { state[keyPath: keyPath] = $0; state.optionsChanged() })
    }
}
