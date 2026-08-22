import Foundation

/// Client du service Voxtral, connexion maintenue le temps d'une dictée.
///
/// ## Pourquoi une classe à part plutôt qu'un ajout à `SocketSpeechEngine`
///
/// Les deux parlent le même protocole de trames, mais pas le même dialogue.
/// `SocketSpeechEngine` ouvre une connexion, envoie une requête, lit une
/// réponse, referme — un aller-retour par dictée. Ici la connexion **vit** le
/// temps de la parole : on l'ouvre au premier mot, on y verse l'audio par
/// morceaux, et le texte revient au fil. Mêler les deux dans une même classe
/// aurait obligé chacune à se protéger de l'état de l'autre.
///
/// Et surtout : ce client vise **un autre socket**. Le service Voxtral est
/// parallèle au moteur principal, avec son propre agent de lancement, parce
/// que l'application régénère celui du moteur principal quand elle réconcilie
/// son état — un moteur expérimental branché là disparaîtrait sans prévenir.
///
/// ## Ce que ça change, mesuré
///
/// Sur une dictée de 60 s : 34,1 s d'attente en envoyant le tampon complet à
/// la fin, **0,84 s** en versant l'audio au fil. Le modèle consomme l'audio à
/// 0,65× le temps réel, donc il a fini avant la dernière syllabe. L'attente
/// n'a jamais été celle du modèle, mais celle de l'architecture qui l'appelait.
final class VoxtralStreamClient: @unchecked Sendable {

    enum StreamError: LocalizedError {
        case unavailable
        case transport(String)
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Le service Voxtral ne répond pas. Lancez "
                    + "`./scripts/voxtral-stream.sh`."
            case .transport(let d): return "Communication interrompue : \(d)"
            case .engine(let d): return "Le moteur a répondu : \(d)"
            }
        }
    }

    static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/caspr/voxtral.sock").path
    }

    /// Le service tourne-t-il ? Question posée avant d'enregistrer : découvrir
    /// qu'il n'y a personne au bout après avoir parlé une minute, c'est perdre
    /// la minute.
    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultSocketPath)
    }

    private let socketPath: String
    private var fd: Int32 = -1

    init(socketPath: String = VoxtralStreamClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    deinit { if fd >= 0 { close(fd) } }

    // MARK: - Le dialogue

    func start(delayMs: Int = 480) throws {
        fd = try Self.connect(to: socketPath)
        let reply = try roundTrip(["op": "stream_start", "delay_ms": delayMs])
        if let error = reply["error"] as? String { throw StreamError.engine(error) }
    }

    /// Verse un morceau, rend le texte apparu depuis le précédent.
    @discardableResult
    func feed(_ samples: [Float]) throws -> String {
        let reply = try roundTrip(["op": "stream_chunk"], payload: Self.pcm16(samples))
        if let error = reply["error"] as? String { throw StreamError.engine(error) }
        return reply["delta"] as? String ?? ""
    }

    /// Ferme l'entrée et rend le texte complet.
    func finish() throws -> String {
        let reply = try roundTrip(["op": "stream_end"])
        if let error = reply["error"] as? String { throw StreamError.engine(error) }
        return (reply["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        if fd >= 0 { close(fd); fd = -1 }
    }

    // MARK: - Transport

    /// PCM float32 [-1, 1] vers int16 petit-boutiste, ce qu'attend le service.
    private static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            var value = Int16(clipped * 32767).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func roundTrip(_ header: [String: Any],
                           payload: Data = Data()) throws -> [String: Any] {
        guard fd >= 0 else { throw StreamError.transport("flux fermé") }
        var out = header
        out["payload_bytes"] = payload.count
        let json = try JSONSerialization.data(withJSONObject: out)

        var frame = Data()
        withUnsafeBytes(of: UInt32(json.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(json)
        frame.append(payload)
        try Self.writeAll(fd: fd, data: frame)

        let lengthBytes = try Self.readExactly(fd: fd, count: 4)
        let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let replyJSON = try Self.readExactly(fd: fd, count: Int(length))
        guard let object = try JSONSerialization.jsonObject(with: replyJSON)
                as? [String: Any] else {
            throw StreamError.transport("réponse illisible")
        }
        if let extra = object["payload_bytes"] as? Int, extra > 0 {
            _ = try? Self.readExactly(fd: fd, count: extra)
        }
        return object
    }

    private static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StreamError.transport("socket() a échoué") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); throw StreamError.transport("chemin de socket trop long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let ok = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { close(fd); throw StreamError.unavailable }
        return fd
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset),
                                    raw.count - offset)
                if written <= 0 { throw StreamError.transport("écriture interrompue") }
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
            if got <= 0 { throw StreamError.transport("lecture interrompue") }
            offset += got
        }
        return Data(buffer)
    }
}
