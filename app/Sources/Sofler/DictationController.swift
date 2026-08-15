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

    /// Mode, langue et lexique sont **lus** dans les préférences, jamais
    /// recopiés.
    ///
    /// Ils l'ont été, et c'était un bug : le contrôleur gardait des copies
    /// rafraîchies à la fermeture de la fenêtre de réglages. Choisir l'anglais
    /// puis dicter sans fermer la fenêtre transcrivait de l'anglais avec le
    /// modèle français — panne parfaitement muette, puisque le moteur rend
    /// simplement un texte vide ou absurde. Toute copie d'un réglage est une
    /// occasion de divergence ; il n'y en a plus.
    var mode: TranscriptionMode {
        get { Preferences.shared.defaultMode }
        set { Preferences.shared.defaultMode = newValue }
    }

    /// `nil` laisse le moteur appliquer son lexique développeur par défaut.
    var lexicon: [String]? { Preferences.shared.effectiveLexicon }

    var language: String { Preferences.shared.language }

    /// Destination du texte : curseur actif, ou fichier de notes.
    ///
    /// Elle n'est lue qu'à la livraison (cf. `deliver`), jamais au démarrage :
    /// basculer en pleine phrase redirige donc la dictée en cours, dans les
    /// deux sens. C'est le comportement attendu — on se rend compte en parlant
    /// que ça ne doit pas aller là.
    var target: DictationTarget = .caret

    /// Fichier des notes, mémorisé même quand on écrit au curseur.
    var noteFile: URL? { Preferences.shared.noteFile }

    /// Le service local. Toujours construit, jamais contacté tant qu'il n'est
    /// pas choisi — c'est `EngineService` qui décide s'il tourne.
    private let localEngine: any SpeechEngine
    /// Le moteur système, absent avant macOS 26.
    private let systemEngine: (any SpeechEngine)?
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

    let history = TranscriptionHistory()

    /// Audio d'une dictée dont la transcription a échoué. Conservé en mémoire
    /// vive uniquement, jamais écrit sur disque, et libéré dès qu'une
    /// insertion réussit ou que l'utilisateur y renonce.
    private var pendingAudio: [Float]?

    /// Moteur qui écrit réellement, selon le réglage — avec repli sur celui
    /// qui existe si l'autre est indisponible.
    private var writer: any SpeechEngine {
        engine(for: Preferences.shared.engine) ?? localEngine
    }

    private func engine(for choice: EngineChoice) -> (any SpeechEngine)? {
        switch choice {
        case .apple: systemEngine
        case .crisperWhisper: localEngine
        }
    }

    init(engine: any SpeechEngine) {
        self.localEngine = engine
        if #available(macOS 26.0, *) {
            self.systemEngine = AppleSpeechEngine()
        } else {
            self.systemEngine = nil
        }
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
        // La langue se change bien plus souvent que le mode — on s'en rend
        // compte en basculant d'une phrase française à une phrase anglaise —
        // d'où sa présence dans la barre. Comme le reste, elle est lue à la
        // livraison : basculer en pleine dictée vaut pour la dictée en cours.
        overlay.onSelectLanguage = { [weak self] code in
            guard let self else { return }
            Preferences.shared.language = code
            refreshOverlay()
            onStateChange?(state)
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
            modesAvailable: Preferences.shared.engine.hasModes,
            language: Preferences.shared.language,
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
            Log.info("enregistrement démarré")
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
        Log.info("fin d'enregistrement : \(String(format: "%.1f", seconds)) s capturées, moteur \(Preferences.shared.engine.rawValue)")

        // Un appui-relâché trop bref ne contient rien d'exploitable ; inutile
        // de réveiller le moteur. Un vrai VAD reste à faire (cf. README).
        guard samples.count > Int(AudioRecorder.targetSampleRate * 0.3) else {
            Log.info("trop court, ignoré")
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
            let result = try await writer.transcribe(
                TranscriptionRequest(samples: samples, mode: used,
                                     language: language, lexicon: lexicon))

            let text = result.text
            overlay.hide()
            guard !text.isEmpty else {
                // Cas silencieux à l'usage : rien n'est inséré, rien n'entre
                // dans l'historique, et sans trace on ne peut pas distinguer
                // « le moteur n'a rien entendu » d'une panne.
                Log.error("le moteur a rendu un texte vide "
                          + "(\(Preferences.shared.engine.rawValue), "
                          + "\(Int(result.latency.wallMs)) ms)")
                pendingAudio = nil
                state = .idle
                return
            }
            try await deliver(text)
            history.add(text, mode: used)
            pendingAudio = nil
            Log.info("transcrit en \(Int(result.latency.wallMs)) ms, \(text.count) caractères")
            state = .idle
            // Après l'insertion, jamais avant : la collecte ne doit rien
            // coûter au temps que l'utilisateur attend.
            collect(samples: samples, primary: result, mode: used)
        } catch {
            overlay.hide()
            pendingAudio = samples
            let minutes = Double(samples.count) / AudioRecorder.targetSampleRate / 60
            Log.error("échec de transcription : \(error.localizedDescription) — \(String(format: "%.1f", minutes)) min conservées")
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

    /// Archive la dictée, puis la complète avec les autres moteurs demandés.
    ///
    /// Le texte du moteur système est gratuit quand l'aperçu tournait : il a
    /// été produit pendant que l'utilisateur parlait. Tout le reste demande
    /// une passe supplémentaire, lancée **après** insertion.
    private func collect(samples: [Float], primary: TranscriptionResult,
                         mode used: TranscriptionMode) {
        let prefs = Preferences.shared
        guard prefs.corpusEnabled else { return }

        let id = Corpus.makeIdentifier()
        let choice = prefs.engine
        var entry = CorpusEntry(
            id: id,
            date: Date(),
            durationSeconds: Double(samples.count) / AudioRecorder.targetSampleRate,
            language: language,
            destination: target.isLocked ? "notes" : "curseur",
            lexicon: choice.honoursLexicon ? lexicon : nil,
            transcriptions: [])

        if prefs.corpusKeepsAudio {
            entry.audioFile = Corpus.shared.writeAudio(samples, id: id)
        }

        // Figé ici, et pas à l'archivage : l'archivage a lieu plusieurs
        // centaines de millisecondes plus tard, et si l'utilisateur réenchaîne
        // une dictée d'ici là, `applePreviewText` a déjà été réinitialisé puis
        // rempli par la nouvelle. Constaté dans le corpus — une entrée portait
        // comme texte Apple le début de la dictée suivante. À ce point-ci la
        // reconnaissance système est finalisée depuis longtemps : elle l'était
        // avant même que la transcription ne rende la main.
        let preview = applePreviewText
        let pending = prefs.enginesToCollect().subtracting([choice])
        secondPassTask = Task { [weak self] in
            await self?.completeAndArchive(entry, samples: samples,
                                           primary: primary, insertedMode: used,
                                           writer: choice, pending: pending,
                                           preview: preview)
        }
    }

    /// Complète l'archive avec ce qui manque, puis écrit la ligne.
    ///
    /// Chaque moteur supplémentaire occupe la machine : ces passes sont donc
    /// lancées après insertion, et abandonnées dès qu'une nouvelle dictée
    /// démarre. Ce qui n'a pas été produit est **consigné** dans `skipped` —
    /// une transcription manquante ne doit jamais être confondue avec un
    /// moteur qu'on n'avait pas coché.
    private func completeAndArchive(_ entry: CorpusEntry, samples: [Float],
                                    primary: TranscriptionResult,
                                    insertedMode: TranscriptionMode,
                                    writer choice: EngineChoice,
                                    pending: Set<EngineChoice>,
                                    preview: String) async {
        var entry = entry
        let identity = await (engine(for: choice)?.identity
                              ?? EngineIdentity(engine: choice.rawValue, model: nil))

        entry.transcriptions.append(CorpusTranscription(
            engine: identity.engine, model: identity.model,
            mode: choice.hasModes ? insertedMode.rawValue : nil,
            text: primary.text, latencyMs: primary.latency.wallMs, inserted: true))

        // Le second mode du moteur qui vient d'écrire, quand il en a deux.
        var remaining: [(EngineChoice, TranscriptionMode?)] = []
        if choice.hasModes {
            let other: TranscriptionMode = insertedMode == .intended ? .verbatim : .intended
            remaining.append((choice, other))
        }
        for engine in pending.sorted(by: { $0.rawValue < $1.rawValue }) {
            remaining.append((engine, engine.hasModes ? .intended : nil))
        }

        // L'aperçu a déjà transcrit avec le moteur système : on ne le refait
        // pas tourner pour rien.
        if !preview.isEmpty,
           let index = remaining.firstIndex(where: { $0.0 == .apple }) {
            entry.transcriptions.append(CorpusTranscription(
                engine: "apple", model: nil, mode: nil,
                text: preview, latencyMs: nil, inserted: false))
            remaining.remove(at: index)
        }

        for (choice, mode) in remaining {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, state == .idle else {
                entry.skipped.append("\(choice.rawValue): dictée enchaînée")
                continue
            }
            guard let engine = engine(for: choice) else {
                entry.skipped.append("\(choice.rawValue): indisponible")
                continue
            }
            do {
                let result = try await engine.transcribe(TranscriptionRequest(
                    samples: samples, mode: mode ?? .intended,
                    language: entry.language,
                    lexicon: choice.honoursLexicon ? entry.lexicon : nil))
                let identity = await engine.identity
                entry.transcriptions.append(CorpusTranscription(
                    engine: identity.engine, model: identity.model,
                    mode: mode?.rawValue, text: result.text,
                    latencyMs: result.latency.wallMs, inserted: false))
            } catch {
                NSLog("sofler: corpus — %@ a échoué : %@", choice.rawValue,
                      error.localizedDescription)
                entry.skipped.append("\(choice.rawValue): \(error.localizedDescription)")
            }
        }

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
