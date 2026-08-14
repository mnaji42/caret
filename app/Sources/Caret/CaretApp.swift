import AppKit

/// Caret vit dans la barre de menus, sans fenêtre ni icône au Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyMonitor!
    private var historyHotkey: HotkeyMonitor!
    private var modifierKey: ModifierKeyMonitor!
    private var reArmTimer: Timer?
    private var controller: DictationController!
    private let preferences = PreferencesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = SocketSpeechEngine()
        controller = DictationController(engine: engine)
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)

        let prefs = Preferences.shared
        controller.mode = prefs.defaultMode
        controller.language = prefs.language
        controller.lexicon = prefs.effectiveLexicon

        // Déclencheur principal : Option pressée seule.
        modifierKey = ModifierKeyMonitor(side: prefs.triggerSide) { [weak self] in
            self?.controller.toggle()
        }
        if prefs.triggerEnabled, !modifierKey.start() {
            NSLog("caret: tap clavier indisponible — accessibilité accordée ?")
        }

        // Repli clavier, utile si l'accessibilité n'est pas encore accordée
        // (le tap l'exige, pas Carbon) ou si Option droite sert à autre chose.
        hotkey = HotkeyMonitor { [weak self] in self?.controller.toggle() }
        let shortcut = HotkeyMonitor.Shortcut.dictate
        if !hotkey.register(shortcut) {
            NSLog("caret: impossible d'enregistrer \(shortcut.label) — raccourci déjà pris ?")
        }

        // Ouvrir le menu au clavier : sans ça, retrouver une transcription
        // suppose de viser une icône de barre de menus à la souris.
        historyHotkey = HotkeyMonitor { [weak self] in self?.openMenu() }
        _ = historyHotkey.register(.history)

        // Le système désactive un tap dont le processus a trop tardé ; sans ce
        // réarmement la dictée cesserait de répondre sans prévenir.
        reArmTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.modifierKey.reArmIfNeeded() }
        }

        Task {
            await requestMicrophoneIfNeeded()
            await refreshMenu()
        }
    }

    /// Demande le micro au lancement plutôt qu'à la première dictée.
    ///
    /// Au lancement l'utilisateur vient d'agir et regarde son écran ; à la
    /// première dictée il est dans une autre app, et un dialogue surgissant
    /// derrière sa fenêtre passe inaperçu. macOS n'affiche ce dialogue qu'une
    /// fois : le manquer enregistre un refus définitif, et l'app n'apparaît
    /// même pas dans la liste des Réglages tant qu'elle n'a rien demandé.
    private func requestMicrophoneIfNeeded() async {
        guard AudioRecorder.microphoneAccess == .undetermined else { return }
        NSApp.activate(ignoringOtherApps: true)
        _ = await AudioRecorder.requestPermission()
        await refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        reArmTimer?.invalidate()
        modifierKey?.stop()
        hotkey?.unregister()
        historyHotkey?.unregister()
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

        let dictate = NSMenuItem(
            title: "Dicter  ⌥ droite  ·  \(HotkeyMonitor.Shortcut.dictate.label)",
            action: #selector(triggerDictation), keyEquivalent: "")
        dictate.target = self
        menu.addItem(dictate)

        // Une dictée ratée après plusieurs minutes de parole doit pouvoir être
        // relancée sans tout redire : l'audio est encore là.
        if controller.hasPendingAudio {
            let minutes = controller.pendingDuration / 60
            let label = minutes >= 1
                ? String(format: "Réessayer (%.1f min conservées)", minutes)
                : String(format: "Réessayer (%.0f s conservées)", controller.pendingDuration)
            let retry = NSMenuItem(title: label, action: #selector(retry), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)

            let discard = NSMenuItem(title: "Abandonner cet enregistrement",
                                     action: #selector(discard), keyEquivalent: "")
            discard.target = self
            menu.addItem(discard)
        }
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

        // Section toujours présente, même vide : masquée, elle est
        // indécouvrable — on ne cherche pas une fonction dont rien n'indique
        // l'existence.
        let entries = controller.history.entries
        let header = NSMenuItem(
            title: "Transcriptions récentes  \(HotkeyMonitor.Shortcut.history.label)",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if entries.isEmpty {
            let empty = NSMenuItem(
                title: controller.history.isEnabled
                    ? "  aucune pour l'instant"
                    : "  historique désactivé",
                action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in entries {
                let item = NSMenuItem(title: "  \(entry.preview)",
                                      action: #selector(reinsert(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.text
                item.toolTip = "\(entry.relativeAge)\n\n\(entry.text)"
                menu.addItem(item)
            }

            let clear = NSMenuItem(title: "  Effacer l'historique",
                                   action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
        menu.addItem(.separator())

        let sounds = NSMenuItem(title: "Retour sonore", action: #selector(toggleSounds),
                                keyEquivalent: "")
        sounds.target = self
        sounds.state = Feedback.soundsEnabled ? .on : .off
        menu.addItem(sounds)

        let diag = NSMenuItem(title: controller.captureNextForDiagnostics
                                ? "Diagnostic : prochaine dictée sera enregistrée"
                                : "Enregistrer la prochaine dictée (diagnostic)…",
                              action: #selector(toggleDiagnostics), keyEquivalent: "")
        diag.target = self
        diag.state = controller.captureNextForDiagnostics ? .on : .off
        menu.addItem(diag)

        let keepHistory = NSMenuItem(title: "Conserver l'historique",
                                     action: #selector(toggleHistory), keyEquivalent: "")
        keepHistory.target = self
        keepHistory.state = controller.history.isEnabled ? .on : .off
        menu.addItem(keepHistory)
        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: engineName, action: nil, keyEquivalent: "")
        engineItem.isEnabled = false
        menu.addItem(engineItem)

        // Les autorisations restent visibles en permanence : elles sont la
        // première cause de « ça ne marche pas », et l'utilisateur ne peut pas
        // deviner laquelle manque.
        let permsItem = NSMenuItem(
            title: Permissions.summary(accessibilityGranted: AXIsProcessTrusted()),
            action: nil, keyEquivalent: "")
        permsItem.isEnabled = false
        menu.addItem(permsItem)

        if !Permissions.allGranted {
            let mic = NSMenuItem(title: "Ouvrir les réglages Micro…",
                                 action: #selector(openMicSettings), keyEquivalent: "")
            mic.target = self
            menu.addItem(mic)

            let ax = NSMenuItem(title: "Ouvrir les réglages Accessibilité…",
                                action: #selector(openAXSettings), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Réglages…", action: #selector(openPreferences),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: "Quitter Caret", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func triggerDictation() {
        controller.toggle()
    }

    /// Déroule le menu de la barre de menus par programme.
    private func openMenu() {
        Task {
            await refreshMenu()
            statusItem.button?.performClick(nil)
        }
    }

    @objc private func openPreferences() {
        preferences.show()
        // Les réglages s'appliquent à la volée : rien à redémarrer.
        Task {
            for await _ in NotificationCenter.default.notifications(
                named: NSWindow.willCloseNotification) {
                applyPreferences()
                break
            }
        }
    }

    /// Reporte les réglages sur les composants déjà en place.
    private func applyPreferences() {
        let prefs = Preferences.shared
        controller.mode = prefs.defaultMode
        controller.language = prefs.language
        controller.lexicon = prefs.effectiveLexicon

        // Le côté du déclencheur est fixé à la création du tap : il faut le
        // reconstruire pour en changer.
        modifierKey.stop()
        modifierKey = ModifierKeyMonitor(side: prefs.triggerSide) { [weak self] in
            self?.controller.toggle()
        }
        if prefs.triggerEnabled { modifierKey.start() }
        Task { await refreshMenu() }
    }

    @objc private func retry() {
        controller.retryLast()
    }

    @objc private func discard() {
        controller.discardPending()
        Task { await refreshMenu() }
    }

    @objc private func reinsert(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        Task { await controller.insert(text) }
    }

    @objc private func clearHistory() {
        controller.history.clear()
        Task { await refreshMenu() }
    }

    @objc private func toggleDiagnostics() {
        controller.captureNextForDiagnostics.toggle()
        Task { await refreshMenu() }
    }

    @objc private func toggleSounds() {
        Feedback.soundsEnabled.toggle()
        Task { await refreshMenu() }
    }

    @objc private func toggleHistory() {
        controller.history.isEnabled.toggle()
        Task { await refreshMenu() }
    }

    @objc private func openMicSettings() {
        Permissions.openMicrophoneSettings()
    }

    @objc private func openAXSettings() {
        // Ouvre le dialogue système si l'app n'a jamais été inscrite, ce qui
        // la fait apparaître dans la liste ; sinon le volet seul suffit.
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        Permissions.openAccessibilitySettings()
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
