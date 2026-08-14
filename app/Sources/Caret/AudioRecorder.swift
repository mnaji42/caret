import AVFoundation
import Foundation

/// Capture micro, convertie à la volée au format attendu par le moteur.
///
/// Le matériel délivre typiquement du 44,1 ou 48 kHz ; Whisper veut du 16 kHz
/// mono. On convertit pendant l'enregistrement plutôt qu'à la fin : ça étale
/// le coût sur la durée de la dictée au lieu de l'ajouter à la latence
/// perçue, qui commence au relâchement de la touche.
final class AudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Accès au micro refusé. Réglages › Confidentialité › Microphone."
            case .noInputDevice:
                return "Aucun micro disponible."
            case .converterUnavailable:
                return "Conversion audio impossible."
            }
        }
    }

    static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var isRunning = false

    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Self.targetSampleRate
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.converterUnavailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter, outputFormat: outputFormat)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Arrête la capture et rend les échantillons accumulés.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil

        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        return captured
    }

    func cancel() {
        _ = stop()
    }

    private func append(_ buffer: AVAudioPCMBuffer,
                        using converter: AVAudioConverter,
                        outputFormat: AVAudioFormat) {
        // Le ré-échantillonnage change le nombre de trames : on dimensionne la
        // sortie au ratio des fréquences, avec une trame de marge pour les
        // arrondis.
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            // Un seul buffer disponible par appel : au second passage on
            // signale la fin d'entrée, sinon le convertisseur boucle.
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, out.frameLength > 0,
              let channel = out.floatChannelData?[0] else { return }

        let converted = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))
        lock.lock()
        samples.append(contentsOf: converted)
        lock.unlock()
    }
}
