import AppKit
import AVFoundation
import Carbon.HIToolbox

/// Enchaînement raccourci → capture → transcription → insertion.
///
/// Un seul cycle à la fois : réappuyer pendant le traitement est ignoré
/// plutôt que mis en file, sinon deux transcriptions se disputeraient le
/// curseur.
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    var onStateChange: ((State) -> Void)?

    /// Mode par défaut : `intended`. Les nombres tranchent — verbatim rend
    /// « deux cents » là où intended rend « 200 », et personne ne veut
    /// « erreur cinq cents » dans un rapport de bug.
    var mode: TranscriptionMode = .intended

    /// `nil` laisse le moteur appliquer son lexique développeur par défaut.
    var lexicon: [String]?

    var language: String = "fr"

    /// Destination du texte : curseur actif, ou fichier de notes.
    ///
    /// Elle n'est lue qu'à la livraison (cf. `deliver`), jamais au démarrage :
    /// basculer en pleine phrase redirige donc la dictée en cours, dans les
    /// deux sens. C'est le comportement attendu — on se rend compte en parlant
    /// que ça ne doit pas aller là.
    var target: DictationTarget = .caret

    /// Fichier des notes, mémorisé même quand on écrit au curseur.
    var noteFile: URL? { Preferences.shared.noteFile }

    private let engine: any SpeechEngine
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = RecordingOverlay()
    private var escapeMonitor: HotkeyMonitor?

    /// Aperçu en direct, quand le système sait le faire et que l'utilisateur
    /// le veut. `nil` le reste du temps.
    private var preview: (any SpeechPreviewing)?

    /// Dernier texte rendu par le moteur de macOS pour la dictée en cours.
    private var applePreviewText = ""

    /// Seconde passe du moteur pour la collecte. Annulable : elle ne doit
    /// jamais retarder une nouvelle dictée.
    private var secondPassTask: Task<Void, Never>?

    /// Dernière identité connue du moteur, pour ne pas la redemander à chaque
    /// dictée — elle ne change qu'au redémarrage du service.
    private var lastIdentity: EngineIdentity?

    let history = TranscriptionHistory()

    /// Audio d'une dictée dont la transcription a échoué. Conservé en mémoire
    /// vive uniquement, jamais écrit sur disque, et libéré dès qu'une
    /// insertion réussit ou que l'utilisateur y renonce.
    private var pendingAudio: [Float]?

    init(engine: any SpeechEngine) {
        self.engine = engine
        overlay.levelProvider = { [weak self] in self?.recorder.level ?? 0 }
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.onSelectMode = { [weak self] mode in
            guard let self else { return }
            self.mode = mode
            refreshOverlay()
            onStateChange?(state)
        }
        overlay.onSelectTarget = { [weak self] wantsNotes in
            guard let self else { return }
            setNotesTarget(wantsNotes)
            refreshOverlay()
            onStateChange?(state)
        }
        // La collecte se coupe depuis la barre, pas seulement depuis le menu :
        // c'est en dictant qu'on se rend compte qu'on ne veut pas archiver
        // ce qu'on est en train de dire.
        overlay.onToggleCorpus = { [weak self] in
            guard let self else { return }
            Preferences.shared.corpusEnabled.toggle()
            refreshOverlay()
            onStateChange?(state)
        }
        overlay.onTogglePreview = { [weak self] in
            guard let self else { return }
            Preferences.shared.livePreviewEnabled.toggle()
            refreshOverlay()
            guard state == .recording else { return }
            // En pleine dictée, l'aperçu ne rattrape pas ce qui a déjà été
            // dit : il reprend à partir d'ici. Ça ne change rien au texte
            // transcrit, qui vient d'un tout autre chemin.
            if Preferences.shared.livePreviewEnabled { startPreview() } else { stopPreview() }
        }
    }

    /// État courant de la barre.
    private var overlayStatus: RecordingOverlay.Status {
        RecordingOverlay.Status(
            mode: mode,
            target: target,
            noteName: noteFile?.lastPathComponent,
            // Sans fichier mémorisé, basculer sur les notes suppose un
            // sélecteur — impossible pendant qu'on parle.
            canPickNote: state != .recording,
            previewEnabled: Preferences.shared.livePreviewEnabled,
            corpusEnabled: Preferences.shared.corpusEnabled,
            corpusKeepsAudio: Preferences.shared.corpusKeepsAudio)
    }

    private func refreshOverlay() {
        overlay.update(overlayStatus)
    }

    /// Appelé par le raccourci global : démarre ou termine la dictée.
    func toggle() {
        switch state {
        case .idle, .failed:
            Task { await startRecording() }
        case .recording:
            Task { await finishRecording() }
        case .processing:
            break  // cycle en cours, on ignore
        }
    }

    func cancel() {
        guard state == .recording else { return }
        recorder.cancel()
        stopPreview()
        releaseEscape()
        overlay.hide()
        Feedback.cancelled()
        state = .idle
    }

    // MARK: - Étapes

    private func startRecording() async {
        switch AudioRecorder.microphoneAccess {
        case .granted:
            break
        case .undetermined:
            // L'app vit en arrière-plan : sans activation, le dialogue système
            // s'ouvre derrière les autres fenêtres et passe inaperçu.
            NSApp.activate(ignoringOtherApps: true)
            guard await AudioRecorder.requestPermission() else {
                state = .failed("Accès au micro refusé.")
                return
            }
        case .denied:
            state = .failed("Micro refusé — ouvrir Réglages › Micro depuis le menu de Sofler.")
            Permissions.openMicrophoneSettings()
            return
        }

        guard injector.hasPermission else {
            injector.requestPermission()
            state = .failed("Accessibilité requise — voir le menu de Sofler.")
            return
        }
        do {
            try recorder.start()
            captureEscape()
            // Une collecte encore en cours cède la place : le moteur ne traite
            // qu'une requête à la fois, et la dictée qui commence est
            // prioritaire sur l'archivage de la précédente.
            secondPassTask?.cancel()
            applePreviewText = ""
            // Avant d'afficher la barre : elle grise le bouton Notes tant
            // qu'un sélecteur serait impossible, et lit l'état pour le savoir.
            state = .recording
            overlay.showRecording(overlayStatus)
            startPreview()
            Feedback.recordingStarted()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let samples = recorder.stop()
        stopPreview()
        releaseEscape()
        Feedback.recordingStopped()
        overlay.showProcessing()

        let seconds = Double(samples.count) / AudioRecorder.targetSampleRate
        NSLog("sofler: fin d'enregistrement, %.1fs capturées", seconds)

        // Un appui-relâché trop bref ne contient rien d'exploitable ; inutile
        // de réveiller le moteur. Un vrai VAD reste à faire (cf. README).
        guard samples.count > Int(AudioRecorder.targetSampleRate * 0.3) else {
            NSLog("sofler: trop court, ignoré")
            overlay.hide()
            state = .idle
            return
        }

        await transcribeAndInject(samples)
    }

    /// Transcrit puis insère, en gardant l'audio tant que ce n'est pas réussi.
    ///
    /// Une dictée peut durer dix minutes. Perdre cet audio parce que le moteur
    /// était arrêté ou a échoué obligerait à tout redire — c'est le pire échec
    /// possible pour cette application. L'audio n'est donc libéré qu'après une
    /// insertion réussie, et `retryLast()` permet de relancer sans reparler.
    private func transcribeAndInject(_ samples: [Float]) async {
        state = .processing
        let used = mode
        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(samples: samples, mode: used,
                                     language: language, lexicon: lexicon))

            let text = result.text
            overlay.hide()
            guard !text.isEmpty else {
                pendingAudio = nil
                state = .idle
                return
            }
            try await deliver(text)
            history.add(text, mode: used)
            pendingAudio = nil
            NSLog("sofler: %.0f ms, fenêtre %.0fs — %@",
                  result.latency.wallMs, result.windowSeconds, text)
            state = .idle
            // Après l'insertion, jamais avant : la collecte ne doit rien
            // coûter au temps que l'utilisateur attend.
            collect(samples: samples, primary: result, mode: used)
        } catch {
            overlay.hide()
            pendingAudio = samples
            let minutes = Double(samples.count) / AudioRecorder.targetSampleRate / 60
            NSLog("sofler: échec, %.1f min d'audio conservées pour réessai", minutes)
            state = .failed("\(error.localizedDescription) — audio conservé, « Réessayer » dans le menu.")
        }
    }

    /// Achemine le texte vers la destination courante.
    ///
    /// Sur cible verrouillée, l'insertion au curseur est délibérément évitée :
    /// l'intérêt du verrou est justement de pouvoir continuer à travailler
    /// ailleurs sans que la dictée vienne s'écrire dans le code en cours.
    private func deliver(_ text: String) async throws {
        switch target {
        case .caret:
            try await injector.inject(text)
        case .file(let url):
            try TargetWriter.append(text, to: url)
            NSLog("sofler: ajouté à %@", url.lastPathComponent)
        }
    }

    /// Insère un texte déjà transcrit — réinsertion depuis l'historique.
    func insert(_ text: String) async {
        do {
            try await deliver(text)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Bascule entre curseur et notes, sans jamais rien redétecter.
    ///
    /// Le fichier de notes est mémorisé indépendamment de la destination
    /// courante : revenir au curseur ne l'oublie pas, et y retourner ne coûte
    /// qu'un clic. La version précédente relançait la détection à chaque
    /// bascule, donc pouvait ouvrir un sélecteur au milieu d'une phrase — un
    /// panneau modal qui active Sofler, déplace le curseur et avale les
    /// frappes, c'est-à-dire tout ce que la barre flottante évite par
    /// ailleurs.
    func setNotesTarget(_ wantsNotes: Bool) {
        guard wantsNotes else {
            target = .caret
            return
        }
        if let file = noteFile {
            target = .file(file)
            return
        }
        guard state != .recording else {
            NSLog("sofler: aucun fichier de notes mémorisé — en choisir un depuis le menu")
            return
        }
        chooseNoteFile()
    }

    /// Choisit le fichier des notes, et écrit dedans à partir de maintenant.
    ///
    /// On tente d'abord le document ouvert devant : dans ce cas il suffit de
    /// poser le curseur dans le fichier voulu, sans passer par un sélecteur.
    @discardableResult
    func chooseNoteFile() -> URL? {
        var chosen = TargetWriter.frontmostDocument()
        if chosen == nil {
            // Détection impossible : plutôt qu'un sélecteur surgissant sans
            // raison apparente, on dit pourquoi avant de le proposer.
            NSLog("sofler: fichier non identifié — sélecteur")
            chosen = TargetWriter.chooseFile()
        }
        guard let chosen else { return nil }
        Preferences.shared.noteFile = chosen
        target = .file(chosen)
        NSLog("sofler: notes dans %@", chosen.path)
        return chosen
    }

    /// Revient au curseur. Le fichier de notes reste mémorisé.
    func unlockTarget() {
        target = .caret
    }

    // MARK: - Collecte

    /// Archive la dictée, puis la complète avec le mode non utilisé.
    ///
    /// Le texte d'Apple ne coûte rien : il a été produit pendant que
    /// l'utilisateur parlait, et il était jusqu'ici jeté. Seul le second mode
    /// de CrisperWhisper demande une passe supplémentaire.
    private func collect(samples: [Float], primary: TranscriptionResult,
                         mode used: TranscriptionMode) {
        guard Preferences.shared.corpusEnabled else { return }

        let id = Corpus.makeIdentifier()
        let engine = self.engine
        var entry = CorpusEntry(
            id: id,
            date: Date(),
            durationSeconds: Double(samples.count) / AudioRecorder.targetSampleRate,
            language: language,
            modeUsed: used.rawValue,
            destination: target.isLocked ? "notes" : "curseur",
            lexicon: lexicon)
        entry.engineUsed = lastIdentity?.engine ?? "crisperwhisper"
        entry.modelUsed = lastIdentity?.model
        record(primary.text, latency: primary.latency.wallMs, mode: used, in: &entry)

        if Preferences.shared.corpusKeepsAudio {
            entry.audioFile = Corpus.shared.writeAudio(samples, id: id)
        }

        let other: TranscriptionMode = used == .intended ? .verbatim : .intended
        secondPassTask = Task { [weak self] in
            await self?.completeAndArchive(entry, samples: samples, mode: other)
        }
    }

    private func record(_ text: String, latency: Double,
                        mode: TranscriptionMode, in entry: inout CorpusEntry) {
        switch mode {
        case .intended:
            entry.textIntended = text
            entry.latencyIntendedMs = latency
        case .verbatim:
            entry.textVerbatim = text
            entry.latencyVerbatimMs = latency
        }
    }

    /// Transcrit le mode restant, puis écrit la ligne.
    ///
    /// Le moteur ne traite qu'une requête à la fois : cette passe doit donc
    /// pouvoir renoncer. D'où le délai de grâce avant de l'engager — si
    /// l'utilisateur réappuie aussitôt, on abandonne sans avoir occupé le
    /// moteur, et la ligne est écrite quand même, marquée comme incomplète.
    /// Une donnée manquante et signalée vaut mieux qu'une dictée qui attend.
    private func completeAndArchive(_ entry: CorpusEntry, samples: [Float],
                                    mode other: TranscriptionMode) async {
        var entry = entry
        // L'identité se demande au moteur, donc hors du chemin de la dictée.
        let identity = await engine.identity
        entry.engineUsed = identity.engine
        entry.modelUsed = identity.model
        lastIdentity = identity

        try? await Task.sleep(for: .milliseconds(400))

        if Task.isCancelled || state != .idle {
            entry.secondPassSkipped = true
        } else {
            do {
                let result = try await engine.transcribe(
                    TranscriptionRequest(samples: samples, mode: other,
                                         language: entry.language,
                                         lexicon: entry.lexicon))
                record(result.text, latency: result.latency.wallMs,
                       mode: other, in: &entry)
            } catch {
                NSLog("sofler: corpus — seconde passe échouée : %@",
                      error.localizedDescription)
                entry.secondPassSkipped = true
            }
        }

        // Relu ici et pas à la création : le moteur de macOS finalise son
        // texte juste après l'arrêt du micro, donc quelques centaines de
        // millisecondes après que l'insertion a eu lieu.
        if !applePreviewText.isEmpty { entry.textApple = applePreviewText }
        Corpus.shared.append(entry)
    }

    // MARK: - Aperçu en direct

    /// Branche l'aperçu sur le flux micro, si le système et l'utilisateur le
    /// permettent.
    ///
    /// Rien de ceci ne touche à la transcription : l'aperçu lit les mêmes
    /// tampons, en parallèle, et son texte est jeté à la fin. Un échec de
    /// l'aperçu n'a donc aucun effet sur la dictée.
    private func startPreview() {
        guard Preferences.shared.livePreviewEnabled, preview == nil else { return }
        guard let preview = SpeechPreview.make(
            onText: { [weak self] text in
                // Retenu pour la collecte : c'est la transcription du moteur
                // de macOS sur exactement le même audio.
                self?.applePreviewText = text
                self?.overlay.setPreviewText(text)
            },
            onFailure: { [weak self] reason in self?.overlay.setPreviewNotice(reason) })
        else {
            overlay.setPreviewNotice("aperçu : nécessite macOS 26")
            return
        }
        self.preview = preview
        recorder.onBuffer = { [weak preview] buffer in preview?.append(buffer) }
        // Détaché : le premier lancement peut télécharger le modèle système,
        // et la dictée ne doit pas attendre.
        Task { await preview.start(language: language) }
    }

    private func stopPreview() {
        recorder.onBuffer = nil
        preview?.stop()
        preview = nil
    }

    /// Relance la transcription de l'audio conservé après un échec.
    func retryLast() {
        guard let pendingAudio, state != .processing else { return }
        Task { await transcribeAndInject(pendingAudio) }
    }

    /// Libère l'audio conservé. Appelé quand l'utilisateur renonce.
    func discardPending() {
        pendingAudio = nil
        state = .idle
    }

    var hasPendingAudio: Bool { pendingAudio != nil }

    var pendingDuration: TimeInterval {
        Double(pendingAudio?.count ?? 0) / AudioRecorder.targetSampleRate
    }

    // MARK: - Échap pendant l'enregistrement

    /// Échap n'est capté que le temps de l'enregistrement : le monopoliser en
    /// permanence casserait son usage normal dans toutes les autres apps.
    private func captureEscape() {
        let monitor = HotkeyMonitor { [weak self] in self?.cancel() }
        _ = monitor.register(.cancel)
        escapeMonitor = monitor
    }

    private func releaseEscape() {
        escapeMonitor?.unregister()
        escapeMonitor = nil
    }
}
