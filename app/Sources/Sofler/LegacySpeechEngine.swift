import AVFoundation
import Foundation
import Speech

/// Le moteur de la dictée de macOS, celui qui existe depuis toujours.
///
/// C'est l'autre reconnaissance vocale d'Apple : `SFSpeechRecognizer`,
/// disponible depuis macOS 10.15, celle qui fait fonctionner la Dictée du
/// système. `SpeechTranscriber` — l'API de macOS 26 qu'utilise
/// `AppleSpeechEngine` — est plus récente et taillée pour la transcription
/// longue, mais elle exige macOS 26, une puce Apple Silicon, et des modèles
/// livrés avec Apple Intelligence.
///
/// Cette contrainte laissait des Mac entiers sans aucun moteur : un Mac Intel
/// sous macOS 26 n'a ni Apple Intelligence ni CrisperWhisper, alors que la
/// Dictée d'Apple y fonctionne parfaitement. Le constat est venu d'une machine
/// virtuelle où la Dictée dictait très bien pendant que Sofler annonçait
/// qu'aucune langue n'était disponible — deux familles d'actifs distinctes,
/// `UAF_Siri_UnderstandingASRHammer` d'un côté,
/// `UAF_Speech_AutomaticSpeechRecognition` de l'autre.
///
/// Mesuré sur cette machine, ce moteur couvre **63 langues** contre 30.
///
/// ## Tout reste sur la machine, ou rien ne se fait
///
/// `SFSpeechRecognizer` envoie l'audio aux serveurs d'Apple **par défaut**.
/// Sofler promet exactement l'inverse, et cette promesse ne se négocie pas :
/// `requiresOnDeviceRecognition` est donc forcé, et si la machine ne sait pas
/// reconnaître hors ligne, ce moteur se déclare indisponible au lieu de
/// transmettre quoi que ce soit. Un repli qui trahirait la promesse serait
/// pire que l'absence de repli.
final class LegacySpeechEngine: SpeechEngine, @unchecked Sendable {
    enum EngineError: LocalizedError {
        case unavailable
        case notAuthorised
        case offlineUnsupported(String)
        case noResult

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "La dictée de macOS n'est pas disponible pour cette langue."
            case .notAuthorised:
                "macOS n'a pas autorisé Sofler à utiliser la reconnaissance "
                    + "vocale. Réglages Système › Confidentialité et sécurité › "
                    + "Reconnaissance vocale."
            case .offlineUnsupported(let code):
                "macOS ne sait pas reconnaître « \(code) » hors ligne sur cette "
                    + "machine. Sofler n'enverra pas votre voix à un serveur : "
                    + "utilisez CrisperWhisper, ou une autre langue."
            case .noResult:
                "La dictée de macOS n'a rien produit."
            }
        }
    }

    private var resolvedLocale: String?

    // MARK: - Disponibilité

    /// Ce moteur peut-il travailler pour cette langue, **sans réseau** ?
    ///
    /// Les deux conditions comptent autant l'une que l'autre : un
    /// `SFSpeechRecognizer` disponible mais incapable de travailler hors ligne
    /// ne nous sert à rien, puisqu'on ne l'utilisera jamais dans ce mode.
    static func isAvailable(for language: String) -> Bool {
        guard let recognizer = recognizer(for: language) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    /// Les langues que ce moteur sait traiter hors ligne, en codes courts.
    ///
    /// Regroupées par langue et non par région : l'application propose « fr »,
    /// pas « fr-BE » — et `fr-CA` prouve que le français est couvert.
    static var offlineLanguages: Set<String> {
        var found: Set<String> = []
        for locale in SFSpeechRecognizer.supportedLocales() {
            guard let code = locale.language.languageCode?.identifier else { continue }
            if found.contains(code) { continue }
            if isAvailable(for: locale.identifier) { found.insert(code) }
        }
        return found
    }

    /// Le reconnaisseur d'une langue, résolu par la liste du système.
    ///
    /// La version précédente concaténait « -FR » quand le code court ne
    /// suffisait pas — ce qui donnait « en-FR » pour l'anglais, un identifiant
    /// qui n'existe pas. D'où un moteur nul et un « transcription impossible »
    /// en anglais pendant que le français marchait : la faute n'était pas dans
    /// l'accent, elle était dans cette ligne.
    ///
    /// La région de la machine passe en premier — un francophone au Canada
    /// veut `fr-CA` — puis n'importe quelle région de la même langue.
    private static func recognizer(for language: String) -> SFSpeechRecognizer? {
        if let exact = SFSpeechRecognizer(locale: Locale(identifier: language)),
           exact.isAvailable { return exact }

        let code = Locale(identifier: language).language.languageCode?.identifier
            ?? language
        let here = Locale.current.region?.identifier
        let candidates = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == code }
            .sorted { a, _ in a.region?.identifier == here }
        for locale in candidates {
            if let found = SFSpeechRecognizer(locale: locale), found.isAvailable {
                return found
            }
        }
        return nil
    }

    /// Demande l'autorisation, une fois.
    ///
    /// Distincte du micro : macOS considère la reconnaissance vocale comme un
    /// droit séparé, et l'accorder ne dit rien de l'autre. Demandée au moment
    /// où ce moteur est retenu, pas au lancement — inutile d'inquiéter
    /// quelqu'un qui ne s'en servira jamais.
    static func requestAuthorisation() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var isAuthorised: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - SpeechEngine

    var identity: EngineIdentity {
        get async { EngineIdentity(engine: "apple-legacy", model: resolvedLocale) }
    }

    var displayName: String {
        get async { "macOS Dictée · \(resolvedLocale ?? "—")" }
    }

    func isReady() async -> Bool {
        // La langue est lue sur le fil principal, où vivent les préférences.
        let language = await MainActor.run { Preferences.shared.language }
        return Self.isAuthorised && Self.isAvailable(for: language)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let recognizer = Self.recognizer(for: request.language) else {
            throw EngineError.unavailable
        }
        guard recognizer.isAvailable else { throw EngineError.unavailable }
        guard recognizer.supportsOnDeviceRecognition else {
            throw EngineError.offlineUnsupported(request.language)
        }
        guard await Self.requestAuthorisation() else { throw EngineError.notAuthorised }
        resolvedLocale = recognizer.locale.identifier

        let started = Date()
        let audio = SFSpeechAudioBufferRecognitionRequest()
        // La ligne qui tient la promesse. Sans elle, l'audio partirait chez
        // Apple — ce que Sofler garantit ne jamais faire.
        audio.requiresOnDeviceRecognition = true
        audio.shouldReportPartialResults = false
        // Le lexique, quand il y en a un. Contrairement au moteur de macOS 26,
        // celui-ci accepte `contextualStrings` — reste à mesurer si ça change
        // quelque chose sur de vraies dictées, ce que le corpus dira.
        if let lexicon = request.lexicon, !lexicon.isEmpty {
            audio.contextualStrings = lexicon
        }

        for buffer in Self.buffers(from: request.samples) {
            audio.append(buffer)
        }
        audio.endAudio()

        let text: String = try await withCheckedThrowingContinuation { continuation in
            // `resume` ne doit partir qu'une fois : le rappel est appelé à
            // chaque résultat, et une erreur peut suivre un résultat final.
            let done = Guard()
            recognizer.recognitionTask(with: audio) { result, error in
                if let error {
                    if done.claim() { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                if done.claim() {
                    continuation.resume(
                        returning: result.bestTranscription.formattedString)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(started) * 1000
        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            // Comme le moteur de macOS 26 : un seul rendu, on renvoie le mode
            // demandé plutôt que d'inventer une distinction qui n'existe pas.
            mode: request.mode,
            windowSeconds: Double(request.samples.count) / AudioRecorder.targetSampleRate,
            truncated: false,
            latency: TranscriptionResult.Latency(melMs: 0, encoderMs: 0,
                                                 decoderMs: 0, wallMs: elapsed))
    }

    // MARK: - Outils

    /// Découpe les échantillons en tampons, au format que le moteur attend.
    ///
    /// `SFSpeechAudioBufferRecognitionRequest` accepte du PCM flottant à la
    /// fréquence d'origine : pas de conversion nécessaire, contrairement à
    /// l'analyseur de macOS 26 qui impose la sienne.
    private static func buffers(from samples: [Float]) -> [AVAudioPCMBuffer] {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: AudioRecorder.targetSampleRate,
                                         channels: 1, interleaved: false)
        else { return [] }

        let chunk = 16_000                     // une seconde
        var out: [AVAudioPCMBuffer] = []
        var offset = 0
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            samples[offset..<(offset + count)].withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: count)
            }
            out.append(buffer)
            offset += count
        }
        return out
    }

    /// Un verrou minuscule : le premier qui réclame gagne.
    private final class Guard: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if taken { return false }
            taken = true
            return true
        }
    }
}
