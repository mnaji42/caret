import Foundation

/// Moteur joignable via socket Unix — l'implémentation d'aujourd'hui.
///
/// Le service Python garde le modèle chaud ; on ne paie ici que le transport
/// et l'inférence. Quand un backend Core ML natif existera, il remplacera
/// cette classe sans que le reste de l'application bouge.
actor SocketSpeechEngine: SpeechEngine {
    private let socketPath: String
    private var cachedName: String?

    init(socketPath: String = SocketSpeechEngine.defaultSocketPath) {
        self.socketPath = socketPath
    }

    static var defaultSocketPath: String {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/sofler/engine.sock")
            .path
    }

    var identity: EngineIdentity {
        get async {
            let model = try? await send(header: ["op": "ping"])["model"] as? String
            return EngineIdentity(engine: "crisperwhisper", model: model ?? nil)
        }
    }

    var displayName: String {
        get async {
            if let cachedName { return cachedName }
            guard let info = try? await send(header: ["op": "ping"]),
                  let model = info["model"] as? String else {
                return "Moteur hors ligne"
            }
            let device = info["device"] as? String ?? "?"
            let short = model.split(separator: "/").last.map(String.init) ?? model
            let name = "\(short) · \(device)"
            cachedName = name
            return name
        }
    }

    func isReady() async -> Bool {
        guard let info = try? await send(header: ["op": "ping"]) else { return false }
        return info["ready"] as? Bool ?? false
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        var header: [String: Any] = [
            "op": "transcribe",
            "mode": request.mode.rawValue,
            "language": request.language,
        ]
        if let lexicon = request.lexicon {
            header["lexicon"] = lexicon
            header["hotwords"] = lexicon
        }

        let reply = try await send(header: header,
                                   payload: Self.pcm16(from: request.samples))

        if let error = reply["error"] as? String {
            throw SpeechEngineError.engineError(error)
        }

        let timings = reply["timings"] as? [String: Any] ?? [:]
        func ms(_ key: String) -> Double { (timings[key] as? NSNumber)?.doubleValue ?? 0 }

        return TranscriptionResult(
            text: reply["text"] as? String ?? "",
            mode: TranscriptionMode(rawValue: reply["mode"] as? String ?? "") ?? request.mode,
            windowSeconds: (reply["window_s"] as? NSNumber)?.doubleValue ?? 0,
            truncated: reply["truncated"] as? Bool ?? false,
            latency: .init(melMs: ms("mel_ms"), encoderMs: ms("encoder_ms"),
                           decoderMs: ms("decoder_ms"), wallMs: ms("wall_ms"))
        )
    }

    // MARK: - Transport

    /// Trame : [4 octets longueur JSON big-endian][JSON][charge utile].
    private func send(header: [String: Any], payload: Data = Data()) async throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw SpeechEngineError.transportFailure("socket() a échoué")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw SpeechEngineError.transportFailure("chemin de socket trop long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            // Le message disait de lancer une commande dans le dépôt du
            // projet. C'est inutilisable pour qui a installé depuis le .dmg —
            // il n'a pas de dépôt — et trompeur quand les poids sont là mais
            // pas le service, ce qui est l'état laissé par une désinstallation
            // où l'on a coché « service moteur » en gardant le modèle.
            throw SpeechEngineError.unavailable(EngineService.unreachableAdvice)
        }

        var outHeader = header
        outHeader["payload_bytes"] = payload.count
        let json = try JSONSerialization.data(withJSONObject: outHeader)

        var frame = Data()
        withUnsafeBytes(of: UInt32(json.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(json)
        frame.append(payload)
        try Self.writeAll(fd: fd, data: frame)

        let lengthBytes = try Self.readExactly(fd: fd, count: 4)
        let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let replyJSON = try Self.readExactly(fd: fd, count: Int(length))

        guard let object = try JSONSerialization.jsonObject(with: replyJSON) as? [String: Any] else {
            throw SpeechEngineError.transportFailure("réponse illisible")
        }
        // Le service annonce toujours payload_bytes ; on draine s'il y a lieu.
        if let extra = object["payload_bytes"] as? Int, extra > 0 {
            _ = try? Self.readExactly(fd: fd, count: extra)
        }
        return object
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 {
                    throw SpeechEngineError.transportFailure("écriture interrompue")
                }
                offset += written
            }
        }
    }

    private static func readExactly(fd: Int32, count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let got = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress!.advanced(by: offset), count - offset)
            }
            if got <= 0 {
                throw SpeechEngineError.transportFailure("lecture interrompue")
            }
            offset += got
        }
        return Data(buffer)
    }

    private static func pcm16(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            withUnsafeBytes(of: Int16(clamped * 32767).littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        return data
    }
}
