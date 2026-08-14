import AppKit
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

    private let engine: any SpeechEngine
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = RecordingOverlay()
    private var escapeMonitor: HotkeyMonitor?

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
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let samples = recorder.stop()
        releaseEscape()
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

        state = .processing
        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(samples: samples, mode: mode, lexicon: lexicon))

            overlay.hide()
            guard !result.text.isEmpty else {
                state = .idle
                return
            }
            try await injector.inject(result.text)
            NSLog("caret: %.0f ms, fenêtre %.0fs — %@",
                  result.latency.wallMs, result.windowSeconds, result.text)
            state = .idle
        } catch {
            overlay.hide()
            state = .failed(error.localizedDescription)
        }
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
