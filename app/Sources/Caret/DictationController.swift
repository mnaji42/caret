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
    private var escapeMonitor: HotkeyMonitor?

    init(engine: any SpeechEngine) {
        self.engine = engine
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
        state = .idle
    }

    // MARK: - Étapes

    private func startRecording() async {
        guard await AudioRecorder.requestPermission() else {
            state = .failed(AudioRecorder.RecorderError.permissionDenied.localizedDescription)
            return
        }
        guard injector.hasPermission else {
            injector.requestPermission()
            state = .failed("Autoriser Caret dans Confidentialité › Accessibilité, puis relancer.")
            return
        }
        do {
            try recorder.start()
            captureEscape()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let samples = recorder.stop()
        releaseEscape()

        // Un appui-relâché trop bref ne contient rien d'exploitable ; inutile
        // de réveiller le moteur. Un vrai VAD reste à faire (cf. README).
        guard samples.count > Int(AudioRecorder.targetSampleRate * 0.3) else {
            state = .idle
            return
        }

        state = .processing
        do {
            let result = try await engine.transcribe(
                TranscriptionRequest(samples: samples, mode: mode, lexicon: lexicon))

            guard !result.text.isEmpty else {
                state = .idle
                return
            }
            try await injector.inject(result.text)
            NSLog("caret: %.0f ms, fenêtre %.0fs — %@",
                  result.latency.wallMs, result.windowSeconds, result.text)
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Échap pendant l'enregistrement

    /// Échap n'est capté que le temps de l'enregistrement : le monopoliser en
    /// permanence casserait son usage normal dans toutes les autres apps.
    private func captureEscape() {
        let monitor = HotkeyMonitor { [weak self] in self?.cancel() }
        _ = monitor.register(.init(keyCode: UInt32(kVK_Escape), modifiers: 0, label: "Échap"))
        escapeMonitor = monitor
    }

    private func releaseEscape() {
        escapeMonitor?.unregister()
        escapeMonitor = nil
    }
}
