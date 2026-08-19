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
    private let onboarding = OnboardingWindowController()
    private let uninstaller = UninstallWindowController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        LanguageSwitchCoordinator.shared.probeSelectedLanguages()
        let engine = SocketSpeechEngine()
        controller = DictationController(engine: engine)
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)

        // L'accueil ne connaît pas la fenêtre des Réglages, et n'a aucune
        // raison de la connaître : son bouton « Personnaliser… » passe par ici.
        onboarding.openSettings = { [weak self] in
            guard let self else { return }
            preferences.show(history: controller.history)
        }

        let prefs = Preferences.shared
        // Un modèle de 3 Go ne reste pas chargé « au cas où » : le service
        // local ne tourne que s'il écrit ou s'il est coché dans une collecte
        // active. Réconcilié au lancement, puis à chaque changement.
        EngineService.reconcile(needed: prefs.needsLocalEngine)

        // Déclencheur principal : Option pressée seule.
        modifierKey = ModifierKeyMonitor(
            side: prefs.triggerSide,
            onTrigger: { [weak self] in self?.controller.toggle() },
            onHold: { [weak self] in self?.openSettingsFromHold() })
        if prefs.triggerKind == .option, !modifierKey.start() {
            NSLog("sofler: tap clavier indisponible — accessibilité accordée ?")
        }

        // L'autre déclencheur possible, exclusif du précédent. Il passe par
        // Carbon, qui n'exige aucune autorisation, là où le tap réclame
        // l'accessibilité — c'est la porte de sortie quand Option est déjà
        // prise, ou quand on refuse ce droit.
        //
        // Sous « touche Option » il n'est même pas enregistré : le laisser
        // actif ferait fonctionner un déclencheur que l'utilisateur a écarté.
        hotkey = HotkeyMonitor { [weak self] in self?.controller.toggle() }
        let shortcut = prefs.dictateShortcut
        if prefs.triggerKind == .shortcut, !hotkey.register(shortcut) {
            NSLog("sofler: impossible d'enregistrer \(shortcut.label) — raccourci déjà pris ?")
        }

        // Ouvrir le menu au clavier : sans ça, retrouver une transcription
        // suppose de viser une icône de barre de menus à la souris.
        historyHotkey = HotkeyMonitor { [weak self] in self?.openMenu() }
        _ = historyHotkey.register(.history)

        // Le système désactive un tap dont le processus a trop tardé ; sans ce
        // réarmement la dictée cesserait de répondre sans prévenir. Le même
        // appel crée le tap s'il n'a pas pu l'être au lancement, faute
        // d'accessibilité — c'est le filet de sécurité, à dix secondes près.
        reArmTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard Preferences.shared.triggerKind == .option else { return }
                self?.modifierKey.reArmIfNeeded()
            }
        }

        // Et voici le chemin rapide : pendant l'accueil, quelqu'un vient
        // d'accorder l'accessibilité et va essayer la touche Option dans la
        // seconde. Attendre le prochain tour de l'horloge lui ferait conclure
        // que ça ne marche pas.
        NotificationCenter.default.addObserver(
            forName: .soflerAccessibilityGranted, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard Preferences.shared.triggerKind == .option else { return }
                self?.modifierKey.reArmIfNeeded()
            }
        }

        // Le tap clavier ne se reconfigure pas tout seul : on le reconstruit
        // dès que le réglage change, pas à la fermeture d'une fenêtre.
        NotificationCenter.default.addObserver(
            forName: .soflerTriggerChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        }

        Task {
            // Au premier lancement, l'accueil prend la main sur le micro : il
            // l'explique avant de le demander. Les deux en même temps feraient
            // surgir le dialogue système derrière la fenêtre d'accueil, et
            // macOS ne le présente qu'une fois — le manquer vaut refus.
            if Preferences.shared.onboarded {
                await requestMicrophoneIfNeeded()
            } else {
                onboarding.show()
            }
            await refreshMenu()
        }

        // Avant tout le reste de l'asynchrone : si l'application tourne depuis
        // l'image disque, rien de ce qui suit ne tiendra.
        warnIfNotInstalled()

        // Hors du chemin critique : ça ne conditionne rien de ce lancement-ci,
        // seulement le confort des suivants.
        Task.detached { await MainActor.run { Quarantine.clearFromOwnBundle() } }

        // Après le reste : rien ici ne conditionne l'usage de l'application,
        // et le résultat n'arrive qu'une fois le réseau revenu.
        Task {
            await UpdateChecker.shared.checkIfDue()
            if UpdateChecker.shared.newer != nil { await refreshMenu() }
        }
    }

    /// Sofler tourne depuis l'image disque : on ne l'explique pas, on le règle.
    ///
    /// La disposition d'un .dmg est un piège que macOS n'a jamais corrigé. On
    /// glisse l'application dans Applications, et elle reste affichée juste à
    /// côté dans la fenêtre de l'image — donc c'est *elle* qu'on double-clique,
    /// parce qu'elle est là. Rien ne distingue les deux icônes.
    ///
    /// La copie ainsi lancée est en lecture seule, et tout ce qui suit s'en
    /// trouve empoisonné sans jamais se nommer : autorisations attachées à un
    /// chemin temporaire, quarantaine impossible à retirer, mise à jour
    /// intégrée refusée, désinstallation sans rien à retirer. Quatre pannes
    /// diagnostiquées séparément avant qu'on remonte à ce double-clic.
    ///
    /// D'où un dialogue qui *agit* au lieu d'instruire : ouvrir la copie déjà
    /// installée, ou installer et ouvrir s'il n'y en a pas. Un clic, et le
    /// problème n'a plus lieu d'être expliqué.
    private func warnIfNotInstalled() {
        guard Uninstall.runsFromReadOnlyVolume else { return }
        let destination = URL(fileURLWithPath: "/Applications/Sofler.app")
        let installed = FileManager.default.fileExists(atPath: destination.path)

        let alert = NSAlert()
        alert.alertStyle = .warning
        // « Pas installé » portait un jugement là où il n'y a qu'un fait, et
        // un fait discutable : l'application est bien là, elle est simplement
        // sur un support qui va disparaître. On nomme donc l'endroit, pas un
        // état — et on dit ce que cet endroit empêche, pour que le choix se
        // fasse en connaissance de cause plutôt que sur une injonction.
        alert.messageText = installed
            ? "Ce n'est pas la copie installée"
            : "Sofler tourne depuis l'image disque"
        alert.informativeText = installed
            ? """
              Sofler est bien dans Applications, mais c'est la copie restée \
              dans l'image disque qui vient de s'ouvrir — les deux icônes se \
              ressemblent, et celle de l'image est la plus proche.

              Celle-ci est en lecture seule : les autorisations que vous lui \
              accorderez seront perdues, et les mises à jour ne s'y \
              installeront pas. Ouvrez plutôt celle d'Applications.
              """
            : """
              Cette copie vit sur l'image disque montée : elle disparaîtra \
              quand vous éjecterez l'image, et macOS l'exécute en lecture \
              seule.

              Deux conséquences concrètes. Les autorisations micro et \
              accessibilité s'attachent à ce chemin temporaire, donc elles \
              seront à ré-accorder. Et les mises à jour ne peuvent pas \
              s'installer sur un volume qu'on ne peut pas écrire.

              Applications est l'endroit habituel parce qu'il est permanent \
              et inscriptible — mais n'importe quel dossier de votre disque \
              ferait l'affaire, et ce message ne reviendrait pas. Sofler peut \
              s'y copier, éjecter l'image et s'y rouvrir tout seul.
              """
        alert.addButton(withTitle: installed
                        ? "Ouvrir la copie installée"
                        : "Installer dans Applications")
        alert.addButton(withTitle: "Continuer quand même")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if installed {
            relaunch(from: destination, ejecting: sourceVolume)
        } else {
            install(to: destination)
        }
    }

    /// Recopie l'application dans Applications, puis s'y rouvre.
    private func install(to destination: URL) {
        let fm = FileManager.default
        do {
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: Bundle.main.bundleURL, to: destination)
            // Recopiée depuis une image téléchargée, elle hérite de la
            // quarantaine. La retirer ici évite que la copie fraîchement
            // installée redemande l'autorisation à chaque ouverture.
            let strip = Process()
            strip.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            strip.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try? strip.run()
            strip.waitUntilExit()
            // L'image disque part avec : c'est elle qui laissait une fenêtre
            // ouverte sur une icône devenue inutile, et c'est cette icône qui
            // se fait double-cliquer au tour suivant.
            relaunch(from: destination, ejecting: sourceVolume)
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "L'installation n'a pas pu se faire"
            // L'image ne contient plus de raccourci vers Applications : le
            // repli passe donc par la barre latérale du Finder, seul endroit
            // où la cible reste visible.
            failure.informativeText = "\(error.localizedDescription)\n\nGlissez "
                + "Sofler sur « Applications » dans la barre latérale du "
                + "Finder, éjectez l'image, puis ouvrez-le depuis Applications."
            failure.runModal()
        }
    }

    /// Le volume d'où l'on s'exécute, s'il est amovible.
    ///
    /// `nil` sur le disque de démarrage : on n'éjecte pas le Mac.
    private var sourceVolume: URL? {
        let values = try? Uninstall.appBundle.resourceValues(
            forKeys: [.volumeURLKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey])
        guard let volume = values?.volume, volume.path != "/" else { return nil }
        return (values?.volumeIsReadOnly ?? false) ? volume : nil
    }

    /// Ouvre la copie installée, éjecte l'image, et se retire.
    ///
    /// L'ordre est imposé par la situation : on ne peut pas éjecter un volume
    /// depuis un processus qui s'y exécute. Un veilleur détaché attend donc
    /// notre disparition, démonte l'image, puis ouvre la bonne copie. Adopté
    /// par launchd, il survit à notre sortie.
    ///
    /// Éjecter compte autant que réinstaller : c'est la fenêtre restée ouverte
    /// sur l'icône de l'image qui provoque le double-clic au mauvais endroit,
    /// et la refermer supprime la question au lieu d'y répondre.
    private func relaunch(from bundle: URL, ejecting volume: URL?) {
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = [
            "-c",
            """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
            /bin/sleep 0.4
            if [ -n "$3" ]; then
                /usr/bin/hdiutil detach "$3" -quiet 2>/dev/null \
                    || /usr/bin/hdiutil detach "$3" -force -quiet 2>/dev/null
            fi
            /usr/bin/open "$2"
            """,
            "sofler-install",
            String(ProcessInfo.processInfo.processIdentifier),
            bundle.path,
            volume?.path ?? "",
        ]
        watcher.standardOutput = FileHandle.nullDevice
        watcher.standardError = FileHandle.nullDevice
        try? watcher.run()
        NSApp.terminate(nil)
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

        let (image, description): (NSImage?, String) = switch state {
        case .idle:
            controller.target.isLocked
                ? (MenuBarIcon.image(listening: false, locked: true),
                   "Sofler — écrit dans \(controller.target.displayName)")
                : (MenuBarIcon.image(listening: false), "Sofler — prêt")
        case .recording:
            (MenuBarIcon.image(listening: true), "Sofler — enregistrement")
        case .processing:
            (MenuBarIcon.image(listening: true, dimmed: true), "Sofler — transcription")
        // Le seul état qui garde un symbole système. Le triangle d'alerte se
        // lit sans rien avoir appris, là où un caret en détresse ne voudrait
        // rien dire — et l'erreur est le moment où l'on a le moins envie de
        // déchiffrer une icône.
        case .failed:
            (NSImage(systemSymbolName: "exclamationmark.triangle",
                     accessibilityDescription: nil), "Sofler — erreur")
        }

        image?.isTemplate = true
        image?.accessibilityDescription = description
        button.image = image
        button.toolTip = description

        if case .failed(let message) = state {
            button.toolTip = message
            NSLog("sofler: %@", message)
        }
        Task { await refreshMenu() }
    }

    private func refreshMenu() async {
        let menu = NSMenu()

        // Configuration inachevée : le menu se réduit à ce qui a du sens.
        //
        // Il s'ouvre quand même, et c'est le point important. Les documents
        // demandaient d'intercepter aussi ce clic pour rouvrir l'accueil —
        // ce serait retirer le seul chemin vers « Quitter », et enfermer
        // quelqu'un qui refuse l'accessibilité en connaissance de cause dans
        // une fenêtre qui revient à chaque tentative de fermer l'application.
        if SetupRecoveryGuard.shouldIntercept {
            let header = NSMenuItem(title: "Sofler — configuration à terminer",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            let resume = NSMenuItem(title: "Terminer la configuration…",
                                    action: #selector(openOnboarding),
                                    keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)

            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quitter Sofler",
                                    action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: "q"))
            statusItem.menu = menu
            return
        }

        let status: String = switch controller.state {
        case .idle: "Prêt"
        case .recording: "Enregistrement…"
        case .processing: "Transcription…"
        case .failed(let message): message
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")

        // En haut, avant tout le reste. L'icône de la barre ne porte pas de
        // pastille : un point permanent pour un évènement non urgent finit par
        // se faire ignorer, puis détester. Le menu s'ouvre de toute façon
        // souvent — c'est par lui qu'on atteint l'historique et les réglages.
        if let update = UpdateChecker.shared.newer {
            let item = NSMenuItem(title: "↑  Installer la version \(update.version)",
                                  action: #selector(openUpdate), keyEquivalent: "")
            item.target = self
            item.toolTip = "Vous utilisez la \(UpdateChecker.currentVersion). "
                + "Ouvre les Réglages, où un bouton fait tout le reste."
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // N'annoncer que le déclencheur réellement actif : afficher les deux
        // laisserait croire qu'ils marchent tous les deux.
        let prefs = Preferences.shared
        let trigger = prefs.triggerKind == .option
            ? prefs.triggerSide.label
            : prefs.dictateShortcut.label
        let dictate = NSMenuItem(
            title: "Dicter  \(trigger)",
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

        // La destination, en lecture seule.
        //
        // Le *choix* du fichier a quitté ce menu pour `DestinationCard`, dans
        // l'onglet Général : un menu de barre qu'on doit parcourir pour
        // retrouver un sélecteur de fichier a cessé d'être un menu.
        //
        // Mais l'**indication** reste, et c'est délibéré — les documents
        // demandaient de retirer la section entière. Verrouillé sur un
        // fichier, le texte n'apparaît plus là où on regarde, et hors dictée
        // rien d'autre ne le signale. C'est le seul filet contre une demi-heure
        // de dictée écrite dans un fichier qu'on avait oublié.
        if let url = controller.target.fileURL {
            let locked = NSMenuItem(title: "▸ Écrit dans \(url.lastPathComponent)",
                                    action: #selector(revealTarget), keyEquivalent: "")
            locked.target = self
            locked.toolTip = "\(url.path)\n\nSe change dans Réglages › Général."
            menu.addItem(locked)
            menu.addItem(.separator())
        }

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

        // L'accueil contient la seule explication de ce que fait
        // l'accessibilité et de ce qu'implique la licence du modèle. Ne
        // l'afficher qu'une fois reviendrait à cacher ces deux réponses à
        // quiconque n'a pas tout lu le premier jour.
        let welcome = NSMenuItem(title: "Revoir l'accueil…", action: #selector(openOnboarding),
                                 keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)

        // Sous les réglages, au-dessus de « Quitter » : là où on cherche une
        // sortie. Une application qui réclame le micro, l'accessibilité et le
        // démarrage automatique doit savoir partir, et le dire.
        let uninstall = NSMenuItem(title: "Désinstaller Sofler…",
                                   action: #selector(openUninstaller), keyEquivalent: "")
        uninstall.target = self
        menu.addItem(uninstall)

        menu.addItem(NSMenuItem(title: "Quitter Sofler", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func triggerDictation() {
        // La dictée ne peut rien produire tant que le socle minimal n'est pas
        // posé : plutôt qu'un échec de plus, on rouvre l'écran qui l'explique,
        // là où la personne s'était arrêtée.
        guard !SetupRecoveryGuard.intercept(.dictation, reopening: onboarding) else {
            return
        }
        controller.toggle()
    }

    /// Mène au bouton, pas au navigateur.
    ///
    /// L'installation vit dans les Réglages plutôt que dans ce menu : elle
    /// dure une minute, elle a des étapes, elle peut échouer pour une raison
    /// qui demande une phrase entière. Un élément de menu ne sait rien montrer
    /// de tout ça, et la barre se referme au premier clic.
    @objc private func openUpdate() {
        openPreferences()
    }

    @objc private func openOnboarding() {
        onboarding.show()
    }

    @objc private func openUninstaller() {
        uninstaller.show()
    }

    /// Déroule le menu de la barre de menus par programme.
    private func openMenu() {
        Task {
            await refreshMenu()
            statusItem.button?.performClick(nil)
        }
    }

    /// Option maintenue : on ouvre les réglages, et on renonce à la dictée en
    /// cours s'il y en avait une.
    ///
    /// L'audio est jeté, rien n'est transcrit ni inséré : quelqu'un qui tient
    /// la touche deux secondes ne demande pas qu'on écrive ce qu'il vient de
    /// dire, il demande les réglages.
    private func openSettingsFromHold() {
        controller.cancel()
        Log.info("Option maintenue — ouverture des réglages")
        openPreferences()
    }

    @objc private func openPreferences() {
        guard !SetupRecoveryGuard.intercept(.settings, reopening: onboarding) else {
            return
        }
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
        modifierKey = ModifierKeyMonitor(
            side: prefs.triggerSide,
            onTrigger: { [weak self] in self?.controller.toggle() },
            onHold: { [weak self] in self?.openSettingsFromHold() })
        if prefs.triggerKind == .option { modifierKey.start() }

        // Le raccourci Carbon est enregistré auprès du système : en changer
        // suppose de rendre l'ancien avant de prendre le nouveau.
        hotkey.unregister()
        if prefs.triggerKind == .shortcut, !hotkey.register(prefs.dictateShortcut) {
            Log.error("raccourci \(prefs.dictateShortcut.label) refusé — déjà pris ?")
        }
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
        app.mainMenu = editingMenu()
        // Le delegate est retenu par l'app pour toute la durée du process.
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Le menu principal, réduit aux commandes d'édition.
    ///
    /// ## Pourquoi une application sans menu en a quand même besoin
    ///
    /// Sofler est en `.accessory` : pas de Dock, pas de barre de menus visible.
    /// J'en avais conclu qu'elle n'avait pas besoin de `mainMenu`. C'est faux, et
    /// ça se voyait : **⌘A, ⌘C, ⌘V et ⌘Z ne faisaient rien** dans le moindre
    /// champ de texte de l'application — la zone d'essai de l'accueil, la
    /// recherche de langues, la saisie du lexique.
    ///
    /// macOS ne câble pas ces raccourcis dans les vues : il les route par le
    /// menu principal, en envoyant le sélecteur au premier répondant. Sans
    /// menu, il n'y a aucun chemin, et les touches tombent dans le vide sans
    /// que rien ne le signale.
    ///
    /// Le menu reste invisible — une app accessoire n'affiche pas sa barre —
    /// mais les raccourcis retrouvent leur route. Réduit à l'édition : ni
    /// « Fichier », ni « Fenêtre », ni « Aide », qui n'auraient rien à porter.
    private static func editingMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Édition")

        // `nil` comme cible : le sélecteur descend la chaîne des répondants
        // jusqu'au champ qui a le focus, ce qui est exactement le comportement
        // attendu et ce que fait le menu Édition de n'importe quelle app.
        func add(_ title: String, _ selector: Selector, _ key: String,
                 modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }

        add("Annuler", Selector(("undo:")), "z")
        add("Rétablir", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("Couper", #selector(NSText.cut(_:)), "x")
        add("Copier", #selector(NSText.copy(_:)), "c")
        add("Coller", #selector(NSText.paste(_:)), "v")
        add("Tout sélectionner", #selector(NSText.selectAll(_:)), "a")

        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
