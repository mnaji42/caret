import AVFoundation
import Foundation

/// Rejoue le corpus avec les moteurs de macOS, depuis l'application.
///
/// ## Pourquoi ça doit vivre ici et nulle part ailleurs
///
/// Les trois moteurs téléchargés se mesurent depuis n'importe quel script :
/// ce sont des poids qu'on charge. Les moteurs de macOS, non. Le framework
/// Speech exige l'autorisation de reconnaissance vocale, et TCC l'accorde à
/// une **identité de code** — celle de Caspr, pas celle d'un binaire d'essai.
/// Éprouvé : un outil en ligne de commande qui refait la même préparation
/// obtient `nilError`, quelle que soit la locale réservée et le format
/// converti.
///
/// D'où ce mode : l'application se prête à la mesure, avec ses propres droits.
/// C'est la seule façon de faire figurer macOS dans le même tableau que les
/// autres — sinon ses transcriptions restent celles captées au fil des
/// dictées, non comparables aux passages rejoués.
///
///     /Applications/Caspr.app/Contents/MacOS/Caspr --bench-corpus [sortie.json]
///
/// L'application ne démarre pas son interface dans ce mode : elle transcrit,
/// écrit, et rend la main.
@MainActor
enum CorpusBatch {

    static var estDemande: Bool {
        CommandLine.arguments.contains("--bench-corpus")
    }

    static func run() async -> Int32 {
        // Sans ça, `print` vers un tube reste en tampon et l'avancement
        // n'apparaît jamais — on croit le banc bloqué alors qu'il travaille.
        setvbuf(stdout, nil, _IONBF, 0)
        let args = CommandLine.arguments
        let sortie = args.firstIndex(of: "--bench-corpus").flatMap {
            $0 + 1 < args.count && !args[$0 + 1].hasPrefix("-") ? args[$0 + 1] : nil
        } ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Desktop/run-macos.json").path

        let corpus = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Caspr/corpus")
        guard let lignes = try? String(contentsOf: corpus.appending(path: "sessions.jsonl"),
                                       encoding: .utf8) else {
            FileHandle.standardError.write("corpus illisible\n".data(using: .utf8)!)
            return 1
        }

        struct Entree { let id: String; let fichier: String; let langue: String; let duree: Double }
        var dictees: [Entree] = []
        for l in lignes.split(separator: "\n") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any],
                  let id = d["id"] as? String,
                  let f = d["audioFile"] as? String,
                  FileManager.default.fileExists(atPath: corpus.appending(path: "audio/\(f)").path)
            else { continue }
            dictees.append(Entree(id: id, fichier: f,
                                  langue: d["language"] as? String ?? "fr",
                                  duree: d["durationSeconds"] as? Double ?? 0))
        }
        print("\(dictees.count) dictées à rejouer")

        // Les deux moteurs, chacun avec sa préparation. On les instancie une
        // fois : le coût d'allocation des modèles ne doit pas être compté à
        // chaque dictée, pas plus qu'il ne l'est pour les autres moteurs.
        var resultats: [[String: Any]] = []
        for (index, e) in dictees.enumerated() {
            let url = corpus.appending(path: "audio/\(e.fichier)")
            guard let samples = lire(url) else { print("   audio illisible"); continue }
            var ligne: [String: Any] = ["id": e.id, "audioFile": e.fichier,
                                        "durationSeconds": e.duree, "language": e.langue]
            for (cle, moteur) in moteurs() {
                let t = Date()
                do {
                    // Délai de garde, et il sert : `SFSpeechRecognizer` — le
                    // moteur de la Dictée — ne rend jamais la main sur un
                    // fichier long, mesuré sur 146 s. Sans lui, une seule
                    // dictée bloque tout le banc sans rien dire.
                    let r = try await avecDelai(secondes: 90) {
                        try await moteur.transcribe(TranscriptionRequest(
                            samples: samples, mode: .intended,
                            language: e.langue, lexicon: nil))
                    }
                    ligne[cle] = ["text": r.text,
                                  "latencyMs": Date().timeIntervalSince(t) * 1000]
                } catch is DelaiDepasse {
                    ligne[cle] = ["text": "", "error": "délai de 90 s dépassé"]
                } catch {
                    ligne[cle] = ["text": "", "error": "\(error)"]
                }
            }
            resultats.append(ligne)
            let apercu = ((ligne["apple"] as? [String: Any])?["text"] as? String) ?? ""
            print("[\(index + 1)/\(dictees.count)] \(String(format: "%6.1f", e.duree))s  "
                  + "\(apercu.prefix(52))")
            ecrire(resultats, vers: sortie)
        }
        print("\n\(resultats.count) dictées → \(sortie)")
        return 0
    }

    private struct DelaiDepasse: Error {}

    /// Exécute un travail, ou abandonne au bout du délai.
    ///
    /// La tâche perdante est annulée, mais un moteur système qui ne coopère pas
    /// à l'annulation continue en arrière-plan : c'est le prix à payer pour ne
    /// pas bloquer le banc, et il est acceptable ici — le process meurt à la
    /// fin de toute façon.
    private static func avecDelai<T: Sendable>(
        secondes: Double, _ travail: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { groupe in
            groupe.addTask { try await travail() }
            groupe.addTask {
                try await Task.sleep(nanoseconds: UInt64(secondes * 1_000_000_000))
                throw DelaiDepasse()
            }
            guard let premier = try await groupe.next() else { throw DelaiDepasse() }
            groupe.cancelAll()
            return premier
        }
    }

    /// Seulement le moteur de macOS 26.
    ///
    /// `SFSpeechRecognizer` — celui de la Dictée — en est absent, et pas par
    /// oubli. Lancé depuis ce mode, il fait planter le process sur une
    /// vérification TCC : « attempted to access privacy-sensitive data without
    /// a usage description », alors que `NSSpeechRecognitionUsageDescription`
    /// **est** dans l'Info.plist et que le même moteur fonctionne dans le
    /// parcours normal de l'application. La demande d'autorisation de
    /// `SFSpeechRecognizer` exige visiblement un contexte que ce mode n'offre
    /// pas, et le contourner coûterait plus que ce que la mesure rapporte —
    /// la Dictée avale de toute façon 40 % des mots, elle n'est pas un
    /// candidat sérieux.
    ///
    /// Conséquence assumée : les transcriptions de la Dictée restent celles
    /// captées au fil des dictées, marquées comme telles dans l'export.
    private static func moteurs() -> [(String, any SpeechEngine)] {
        guard #available(macOS 26.0, *) else { return [] }
        return [("apple", AppleSpeechEngine())]
    }

    /// PCM float32 mono 16 kHz, le format qu'attend `TranscriptionRequest`.
    private static func lire(_ url: URL) -> [Float]? {
        guard let f = try? AVAudioFile(forReading: url),
              let cible = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: 16_000, channels: 1,
                                        interleaved: false),
              let conv = AVAudioConverter(from: f.processingFormat, to: cible)
        else { return nil }
        var out: [Float] = []
        while true {
            guard let src = AVAudioPCMBuffer(pcmFormat: f.processingFormat,
                                             frameCapacity: 8192),
                  (try? f.read(into: src, frameCount: 8192)) != nil,
                  src.frameLength > 0 else { break }
            let ratio = cible.sampleRate / f.processingFormat.sampleRate
            let cap = AVAudioFrameCount(Double(src.frameLength) * ratio) + 1
            guard let dst = AVAudioPCMBuffer(pcmFormat: cible, frameCapacity: cap)
            else { break }
            var pris = false
            conv.convert(to: dst, error: nil) { _, st in
                if pris { st.pointee = .noDataNow; return nil }
                pris = true; st.pointee = .haveData; return src
            }
            if let ch = dst.floatChannelData?[0], dst.frameLength > 0 {
                out.append(contentsOf: UnsafeBufferPointer(start: ch,
                                                           count: Int(dst.frameLength)))
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Réécrit à chaque tour : un quart d'heure de mesure ne doit pas être
    /// perdu parce que la dernière dictée déclenche un cas non prévu.
    private static func ecrire(_ res: [[String: Any]], vers chemin: String) {
        let doc: [String: Any] = ["engine": "macos", "rejoue": true,
                                  "note": "Rejoué par Caspr.app, qui détient "
                                        + "l'autorisation de reconnaissance vocale",
                                  "results": res]
        guard let d = try? JSONSerialization.data(withJSONObject: doc,
                                                  options: [.prettyPrinted]) else { return }
        try? d.write(to: URL(fileURLWithPath: chemin))
    }
}
