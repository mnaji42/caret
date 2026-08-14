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

    /// Destination du texte : curseur actif, ou fichier verrouillé.
    var target: DictationTarget = .caret

    private let engine: any SpeechEngine
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = RecordingOverlay()
    private var escapeMonitor: HotkeyMonitor?

    let history = TranscriptionHistory()

    /// Audio d'une dictée dont la transcription a échoué. Conservé en mémoire
    /// vive uniquement, jamais écrit sur disque, et libéré dès qu'une
    /// insertion réussit ou que l'utilisateur y renonce.
    private var pendingAudio: [Float]?

    init(engine: any SpeechEngine) {
        self.engine = engine
        overlay.levelProvider = { [weak self] in self?.recorder.level ?? 0 }
        overlay.onCancel = { [weak self] in self?.cancel() }
        overlay.onToggleMode = { [weak self] in
            guard let self else { return }
            mode = mode == .intended ? .verbatim : .intended
            overlay.updateMode(mode)
        }
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
            state = .failed("Micro refusé — ouvrir Réglages › Micro depuis le menu de Caret.")
            Permissions.openMicrophoneSettings()
            return
        }

        guard injector.hasPermission else {
            injector.requestPermission()
            state = .failed("Accessibilité requise — voir le menu de Caret.")
            return
        }
        do {
            try recorder.start()
            captureEscape()
            overlay.showRecording(mode: mode)
            Feedback.recordingStarted()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let samples = recorder.stop()
        releaseEscape()
        Feedback.recordingStopped()
        overlay.showProcessing()

        let seconds = Double(samples.count) / AudioRecorder.targetSampleRate
        NSLog("caret: fin d'enregistrement, %.1fs capturées", seconds)

        // Un appui-relâché trop bref ne contient rien d'exploitable ; inutile
        // de réveiller le moteur. Un vrai VAD reste à faire (cf. README).
        guard samples.count > Int(AudioRecorder.targetSampleRate * 0.3) else {
            NSLog("caret: trop court, ignoré")
            overlay.hide()
            state = .idle
            return
        }

        if captureNextForDiagnostics {
            captureNextForDiagnostics = false
            writeDiagnosticFile(samples)
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
        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(samples: samples, mode: mode,
                                     language: language, lexicon: lexicon))

            overlay.hide()
            guard !result.text.isEmpty else {
                pendingAudio = nil
                state = .idle
                return
            }
            try await deliver(result.text)
            history.add(result.text, mode: mode)
            pendingAudio = nil
            NSLog("caret: %.0f ms, fenêtre %.0fs — %@",
                  result.latency.wallMs, result.windowSeconds, result.text)
            state = .idle
        } catch {
            overlay.hide()
            pendingAudio = samples
            let minutes = Double(samples.count) / AudioRecorder.targetSampleRate / 60
            NSLog("caret: échec, %.1f min d'audio conservées pour réessai", minutes)
            state = .failed("\(error.localizedDescription) — audio conservé, « Réessayer » dans le menu.")
        }
    }

    /// Écrit la prochaine dictée sur le Bureau, en plus de la transcrire.
    ///
    /// Sans l'audio d'origine, analyser une erreur de transcription revient à
    /// spéculer : impossible de distinguer une mauvaise reconnaissance d'un
    /// artefact de découpage ou d'une hallucination du lexique. Explicite et
    /// ponctuel — l'audio n'est jamais écrit autrement.
    var captureNextForDiagnostics = false

    private func writeDiagnosticFile(_ samples: [Float]) {
        let name = "caret-diagnostic-\(Int(Date().timeIntervalSince1970)).wav"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").appendingPathComponent(name)
        guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioRecorder.targetSampleRate,
                channels: 1, interleaved: false),
              let file = try? AVAudioFile(forWriting: url,
                                          settings: format.settings,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else {
            NSLog("caret: écriture du fichier de diagnostic impossible")
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!,
                                               count: samples.count)
        }
        try? file.write(from: buffer)
        NSLog("caret: diagnostic écrit — %@", url.path)
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
            NSLog("caret: ajouté à %@", url.lastPathComponent)
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

    /// Verrouille la destination sur un fichier.
    ///
    /// On tente d'abord le document ouvert devant : dans ce cas il suffit de
    /// poser le curseur dans le fichier voulu, sans passer par un sélecteur.
    func lockTarget() {
        if let document = TargetWriter.frontmostDocument() {
            target = .file(document)
            NSLog("caret: verrouillé sur %@", document.path)
        } else if let chosen = TargetWriter.chooseFile() {
            target = .file(chosen)
        }
    }

    func unlockTarget() {
        target = .caret
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
