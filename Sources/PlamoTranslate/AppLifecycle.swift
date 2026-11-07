import AppKit
import ApplicationServices
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate?
    var state: AppState?
    private var statusItem: NSStatusItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastCopy = Date.distantPast
    private var copyChangeCount = 0
    private var subscription: AnyCancellable?
    private var smokeStarted = false
    weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "PLaMo Translate")
        let menu = NSMenu()
        menu.addItem(withTitle: "PLaMo Translate", action: #selector(showMain), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了 / Quit", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        item.menu = menu
        statusItem = item
    }
    func connect(_ state: AppState, window: NSWindow) {
        guard mainWindow !== window else { return }
        self.state = state; mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        subscription = state.$preferences.map(\.shortcutEnabled).removeDuplicates().sink { [weak self] enabled in
            self?.configureShortcut(enabled)
        }
        if !smokeStarted, CommandLine.arguments.contains("--ui-smoke-test") {
            smokeStarted = true
            Task { await UISmoke.run(state: state, window: window) }
        }
    }
    @objc func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state?.invalidate(); state?.models.shutdown() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow, let state else { return true }
        switch state.preferences.closeBehavior {
        case .background: sender.orderOut(nil)
        case .quit: NSApp.terminate(nil)
        case .ask:
            let alert = NSAlert()
            alert.messageText = state.t("ウィンドウを閉じた後の動作", "After closing the window")
            alert.informativeText = state.t("バックグラウンドで実行すると、選択テキストのショートカットを引き続き使えます。", "Keep running in the background to use the selected-text shortcut.")
            alert.addButton(withTitle: state.t("バックグラウンドで実行", "Keep running"))
            alert.addButton(withTitle: state.t("アプリを終了", "Quit"))
            alert.addButton(withTitle: state.t("キャンセル", "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: sender.orderOut(nil)
            case .alertSecondButtonReturn: NSApp.terminate(nil)
            default: break
            }
        }
        return false
    }
    private func configureShortcut(_ enabled: Bool) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        lastCopy = .distantPast
        guard enabled else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleKey(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleKey(event); return event }
    }
    private func handleKey(_ event: NSEvent) {
        guard event.keyCode == 8, !event.isARepeat,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad]) == .command else { return }
        let now = Date()
        if now.timeIntervalSince(lastCopy) < 0.5 {
            lastCopy = .distantPast
            let previousChangeCount = copyChangeCount
            // Let the normal Copy command finish before reading its result.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, let state, state.preferences.shortcutEnabled,
                      NSPasteboard.general.changeCount > previousChangeCount,
                      let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
                state.invalidate()
                state.sourceText = text
                state.translate()
                showMain()
            }
        } else { lastCopy = now; copyChangeCount = NSPasteboard.general.changeCount }
    }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class LoginService: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            enabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = error.localizedDescription }
    }
}
