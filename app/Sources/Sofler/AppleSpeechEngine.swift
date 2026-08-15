import AVFoundation
import Foundation
import Speech

/// Le moteur de reconnaissance de macOS, en transcription complète.
///
/// C'est le même que celui de l'aperçu en direct, utilisé autrement : là on
/// lui donne l'enregistrement entier d'un coup et on attend son texte
/// définitif, plutôt que de suivre ses résultats volatils.
///
/// Il vient avec le système : rien à télécharger, aucune licence à accepter,
/// et il fonctionne sur toute machine en macOS 26. C'est ce qui en fait le
/// moteur par défaut. Sa limite est connue et mesurée : il n'a **pas** de
/// conditionnement par vocabulaire exploitable — `contextualStrings` existe
/// mais reste sans effet sur nos enregistrements — donc il n'écrira jamais
/// `useEffect`. Et il n'a qu'un rendu, sans distinction nettoyé/mot-à-mot.
@available(macOS 26.0, *)
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    enum EngineError: LocalizedError {
        case unavailable
        case localeUnsupported(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "La reconnaissance vocale de macOS est indisponible."
            case .localeUnsupported(let code):
                return "macOS ne reconnaît pas la langue « \(code) »."
            }
        }
    }

    /// Locale réellement retenue, renseignée après la première transcription.
    private var resolvedLocale: String?

    var identity: EngineIdentity {
        get async {
            EngineIdentity(engine: "apple", model: resolvedLocale)
        }
    }

    var displayName: String {
        get async { "macOS SpeechTranscriber · \(resolvedLocale ?? "—")" }
    }

    func isReady() async -> Bool {
        SpeechTranscriber.isAvailable
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard SpeechTranscriber.isAvailable else { throw EngineError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: request.language)) else {
            throw EngineError.localeUnsupported(request.language)
        }
        resolvedLocale = locale.identifier

        // Sans résultats volatils ni `fastResults` : ici on ne cherche pas la
        // réactivité mais le meilleur texte que ce moteur sache produire.
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        try await LivePreview.reserve(locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]) else {
            throw EngineError.unavailable
        }

        let started = Date()
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let collected = Task { () -> String in
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: stream)

        for buffer in Self.buffers(from: request.samples, to: format) {
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = (try? await collected.value) ?? ""
        let elapsed = Date().timeIntervalSince(started) * 1000

        return TranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            // Le moteur système ne distingue pas les modes : on rend celui qui
            // a été demandé plutôt que d'inventer une valeur.
            mode: request.mode,
            windowSeconds: Double(request.samples.count) / AudioRecorder.targetSampleRate,
            truncated: false,
            // Pas de découpage mel/encodeur/décodeur observable ici : seul le
            // temps mur a un sens.
            latency: TranscriptionResult.Latency(melMs: 0, encoderMs: 0,
                                                 decoderMs: 0, wallMs: elapsed))
    }

    /// Découpe les échantillons en tampons au format de l'analyseur.
    ///
    /// Par morceaux plutôt qu'en un seul bloc : le moteur travaille en flux, et
    /// un tampon de dix minutes le ferait allouer d'un coup ce qu'il aurait pu
    /// consommer au fil de l'eau.
    private static func buffers(from samples: [Float],
                                to format: AVAudioFormat) -> [AVAudioPCMBuffer] {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: AudioRecorder.targetSampleRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: format) else { return [] }

        let chunk = 16_000                     // une seconde
        var out: [AVAudioPCMBuffer] = []
        var offset = 0

        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let input = AVAudioPCMBuffer(pcmFormat: source,
                                               frameCapacity: AVAudioFrameCount(count)) else { break }
            input.frameLength = AVAudioFrameCount(count)
            samples[offset..<(offset + count)].withUnsafeBufferPointer { source in
                input.floatChannelData![0].update(from: source.baseAddress!, count: count)
            }

            let ratio = format.sampleRate / AudioRecorder.targetSampleRate
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(Double(count) * ratio) + 1) else { break }

            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return input
            }
            if error == nil, converted.frameLength > 0 { out.append(converted) }
            offset += count
        }
        return out
    }
}
