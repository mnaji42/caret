import AppKit

/// Caret vit dans la barre de menus, sans fenêtre ni icône au Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyMonitor!
    private var controller: DictationController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = SocketSpeechEngine()
        controller = DictationController(engine: engine)
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)

        hotkey = HotkeyMonitor { [weak self] in self?.controller.toggle() }
        let shortcut = HotkeyMonitor.Shortcut.dictate
        if !hotkey.register(shortcut) {
            NSLog("caret: impossible d'enregistrer \(shortcut.label) — raccourci déjà pris ?")
        }

        Task { await refreshMenu() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
    }

    // MARK: - Barre de menus

    private func render(_ state: DictationController.State) {
        guard let button = statusItem.button else { return }

        let (symbol, description): (String, String) = switch state {
        case .idle:       ("mic", "Caret — prêt")
        case .recording:  ("mic.fill", "Caret — enregistrement")
        case .processing: ("waveform", "Caret — transcription")
        case .failed:     ("exclamationmark.triangle", "Caret — erreur")
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description

        if case .failed(let message) = state {
            button.toolTip = message
            NSLog("caret: %@", message)
        }
        Task { await refreshMenu() }
    }

    private func refreshMenu() async {
        let engineName = await SocketSpeechEngine().displayName
        let menu = NSMenu()

        let status: String = switch controller.state {
        case .idle: "Prêt"
        case .recording: "Enregistrement…"
        case .processing: "Transcription…"
        case .failed(let message): message
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let dictate = NSMenuItem(title: "Dicter  \(HotkeyMonitor.Shortcut.dictate.label)",
                                 action: #selector(triggerDictation), keyEquivalent: "")
        dictate.target = self
        menu.addItem(dictate)
        menu.addItem(.separator())

        for mode in TranscriptionMode.allCases {
            let title = mode == .intended ? "Texte nettoyé" : "Mot à mot"
            let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = controller.mode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: engineName, action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quitter Caret", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func triggerDictation() {
        controller.toggle()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = TranscriptionMode(rawValue: raw) else { return }
        controller.mode = mode
        Task { await refreshMenu() }
    }
}

/// Point d'entrée explicite plutôt que du code top-level : `main.swift`
/// s'exécute hors du main actor, ce qui interdit d'y instancier le delegate.
@main
@MainActor
struct CaretApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory : pas d'icône au Dock, pas de fenêtre — l'app ne vit que
        // dans la barre de menus et ne vole jamais le focus, ce qui est
        // indispensable puisque le texte doit atterrir dans l'application que
        // l'utilisateur a devant lui.
        app.setActivationPolicy(.accessory)
        // Le delegate est retenu par l'app pour toute la durée du process.
        withExtendedLifetime(delegate) { app.run() }
    }
}
