import AppKit

/// Sofler vit dans la barre de menus, sans fenêtre ni icône au Dock.
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
        // Un modèle de 3 Go ne reste pas chargé « au cas où » : le service
        // local ne tourne que s'il écrit ou s'il est coché dans une collecte
        // active. Réconcilié au lancement, puis à chaque changement.
        EngineService.reconcile(needed: prefs.needsLocalEngine)

        // Déclencheur principal : Option pressée seule.
        modifierKey = ModifierKeyMonitor(side: prefs.triggerSide) { [weak self] in
            self?.controller.toggle()
        }
        if prefs.triggerEnabled, !modifierKey.start() {
            NSLog("sofler: tap clavier indisponible — accessibilité accordée ?")
        }

        // Repli clavier, utile si l'accessibilité n'est pas encore accordée
        // (le tap l'exige, pas Carbon) ou si Option droite sert à autre chose.
        hotkey = HotkeyMonitor { [weak self] in self?.controller.toggle() }
        let shortcut = prefs.dictateShortcut
        if !hotkey.register(shortcut) {
            NSLog("sofler: impossible d'enregistrer \(shortcut.label) — raccourci déjà pris ?")
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

        // Le tap clavier ne se reconfigure pas tout seul : on le reconstruit
        // dès que le réglage change, pas à la fermeture d'une fenêtre.
        NotificationCenter.default.addObserver(
            forName: .soflerTriggerChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
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
        case .idle:
            controller.target.isLocked
                ? ("mic.badge.plus", "Sofler — écrit dans \(controller.target.displayName)")
                : ("mic", "Sofler — prêt")
        case .recording:  ("mic.fill", "Sofler — enregistrement")
        case .processing: ("waveform", "Sofler — transcription")
        case .failed:     ("exclamationmark.triangle", "Sofler — erreur")
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description

        if case .failed(let message) = state {
            button.toolTip = message
            NSLog("sofler: %@", message)
        }
        Task { await refreshMenu() }
    }

    private func refreshMenu() async {
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
            title: "Dicter  ⌥ droite  ·  \(Preferences.shared.dictateShortcut.label)",
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

        // Destination : le point le plus important à rendre visible, puisque
        // verrouillé, le texte n'apparaît plus là où on regarde.
        if let url = controller.target.fileURL {
            let locked = NSMenuItem(title: "▸ Écrit dans \(url.lastPathComponent)",
                                    action: nil, keyEquivalent: "")
            locked.isEnabled = false
            locked.toolTip = url.path
            menu.addItem(locked)

            let unlock = NSMenuItem(title: "Revenir au curseur",
                                    action: #selector(unlockTarget), keyEquivalent: "")
            unlock.target = self
            unlock.toolTip = "Le fichier reste mémorisé : un clic sur « Notes » "
                + "dans la barre y revient."
            menu.addItem(unlock)

            let change = NSMenuItem(title: "Changer le fichier de notes…",
                                    action: #selector(chooseNoteFile), keyEquivalent: "")
            change.target = self
            menu.addItem(change)

            let reveal = NSMenuItem(title: "Afficher dans le Finder",
                                    action: #selector(revealTarget), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        } else if let note = controller.noteFile {
            // Le fichier survit au retour au curseur : le proposer ici évite
            // de le rechoisir, et dit lequel c'est.
            let resume = NSMenuItem(title: "Écrire dans les notes (\(note.lastPathComponent))",
                                    action: #selector(useNotes), keyEquivalent: "")
            resume.target = self
            resume.toolTip = note.path
            menu.addItem(resume)

            let change = NSMenuItem(title: "Changer le fichier de notes…",
                                    action: #selector(chooseNoteFile), keyEquivalent: "")
            change.target = self
            menu.addItem(change)
        } else {
            let lock = NSMenuItem(title: "Choisir le fichier de notes…",
                                  action: #selector(chooseNoteFile), keyEquivalent: "")
            lock.target = self
            let diag = NSMenuItem(title: "Pourquoi mon fichier n'est pas détecté ?",
                                  action: #selector(showTargetDiagnostics),
                                  keyEquivalent: "")
            diag.target = self
            defer { menu.addItem(diag) }
            lock.toolTip = "Tout ce qui est dicté sera ajouté à ce fichier, "
                + "où que soit le curseur."
            menu.addItem(lock)
        }
        menu.addItem(.separator())

        for mode in TranscriptionMode.allCases {
            let item = NSMenuItem(title: mode.label,
                                  action: #selector(selectMode(_:)), keyEquivalent: "")

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

        // Le menu s'arrête aux gestes du quotidien. Tout ce qui se règle une
        // fois puis s'oublie — aperçu, collecte, sons, historique, vocabulaire
        // — vit dans les Réglages : un menu de barre qu'on doit parcourir pour
        // retrouver une case à cocher a cessé d'être un menu.
        if !Permissions.allGranted {
            let permsItem = NSMenuItem(
                title: Permissions.summary(accessibilityGranted: AXIsProcessTrusted()),
                action: nil, keyEquivalent: "")
            permsItem.isEnabled = false
            menu.addItem(permsItem)

            let mic = NSMenuItem(title: "Ouvrir les réglages Micro…",
                                 action: #selector(openMicSettings), keyEquivalent: "")
            mic.target = self
            menu.addItem(mic)

            let ax = NSMenuItem(title: "Ouvrir les réglages Accessibilité…",
                                action: #selector(openAXSettings), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Réglages…", action: #selector(openPreferences),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: "Quitter Sofler", action: #selector(NSApplication.terminate(_:)),
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
        preferences.show(history: controller.history)
    }

    /// Reporte les réglages sur les composants déjà en place.
    private func applyPreferences() {
        let prefs = Preferences.shared
        // Un modèle de 3 Go ne reste pas chargé « au cas où » : le service
        // local ne tourne que s'il écrit ou s'il est coché dans une collecte
        // active. Réconcilié au lancement, puis à chaque changement.
        EngineService.reconcile(needed: prefs.needsLocalEngine)

        // Mode, langue et lexique ne sont plus recopiés : le contrôleur les lit
        // dans les préférences au moment de s'en servir. Reste le déclencheur,
        // dont le côté est fixé à la création du tap : il faut le reconstruire.
        modifierKey.stop()
        modifierKey = ModifierKeyMonitor(side: prefs.triggerSide) { [weak self] in
            self?.controller.toggle()
        }
        if prefs.triggerEnabled { modifierKey.start() }

        // Le raccourci Carbon est enregistré auprès du système : en changer
        // suppose de rendre l'ancien avant de prendre le nouveau.
        hotkey.unregister()
        if !hotkey.register(prefs.dictateShortcut) {
            Log.error("raccourci \(prefs.dictateShortcut.label) refusé — déjà pris ?")
        }
        Task { await refreshMenu() }
    }

    /// Montre ce que Sofler perçoit, sans passer par les journaux système.
    @objc private func showTargetDiagnostics() {
        // Capturer avant d'activer Sofler : activer changerait l'application
        // au premier plan, donc ce qu'on cherche à observer.
        let report = TargetWriter.diagnostics()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Détection du fichier"
        alert.informativeText = report
        alert.addButton(withTitle: "Copier")
        alert.addButton(withTitle: "Fermer")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    @objc private func chooseNoteFile() {
        controller.chooseNoteFile()
        Task { await refreshMenu() }
    }

    @objc private func useNotes() {
        controller.setNotesTarget(true)
        Task { await refreshMenu() }
    }

    @objc private func unlockTarget() {
        controller.unlockTarget()
        Task { await refreshMenu() }
    }

    @objc private func revealTarget() {
        guard let url = controller.target.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
struct SoflerApp {
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
