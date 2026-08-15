import AVFoundation
import AppKit

/// Une transcription, quel que soit le moteur qui l'a produite.
///
/// Toutes les transcriptions d'une même dictée viennent du **même** audio :
/// c'est ce qui rend la comparaison honnête.
struct CorpusTranscription: Codable {
    /// Famille du moteur : `apple`, `crisperwhisper`, `whisper`…
    var engine: String
    /// Modèle précis quand il y en a un ; la locale pour un moteur système.
    var model: String?
    /// `intended`, `verbatim`, ou absent quand le moteur n'a qu'un rendu.
    var mode: String?
    var text: String
    /// Temps mur du moteur. Absent pour un texte capté en flux pendant la
    /// dictée, où la notion n'a pas de sens.
    var latencyMs: Double?
    /// Vrai pour celle qui a été réellement insérée chez l'utilisateur.
    var inserted: Bool
}

/// Une dictée, telle qu'archivée pour comparer les moteurs.
///
/// La liste est ouverte : on peut en ajouter un quatrième ou un cinquième sans
/// toucher au format. La version précédente nommait un champ par moteur
/// (`textIntended`, `textApple`), ce qui ne survivait pas au premier moteur
/// supplémentaire — les entrées d'alors ont été converties.
struct CorpusEntry: Codable {
    var id: String
    var date: Date
    var durationSeconds: Double
    var language: String
    var destination: String
    /// Lexique envoyé aux moteurs qui en acceptent un ; `nil` = celui du moteur.
    var lexicon: [String]?
    var transcriptions: [CorpusTranscription]
    /// Ce qui était demandé mais n'a pas été produit, et pourquoi. Sans cette
    /// trace, une transcription manquante serait indistinguable d'un moteur
    /// qu'on n'avait pas coché.
    var skipped: [String] = []
    /// Nom du fichier dans `audio/`, si l'option est active.
    var audioFile: String?

    /// Ce qui a été inséré chez l'utilisateur.
    var insertedTranscription: CorpusTranscription? {
        transcriptions.first { $0.inserted }
    }
}

/// Archive locale des dictées, pour mesurer les moteurs sur de la vraie voix.
///
/// Les comparaisons faites jusqu'ici — bancs du dépôt, essais sur clips —
/// portent sur des échantillons choisis, en petit nombre. Ce qui manque pour
/// trancher, c'est l'usage réel : des heures de parole spontanée, avec les
/// termes techniques, l'anglais mêlé au français et l'acoustique de la pièce.
/// D'où un format en ajout seul, qui accumule sans jamais se relire.
///
/// Tout reste sur la machine, et rien n'est écrit tant que la collecte n'est
/// pas explicitement activée.
@MainActor
final class Corpus {
    static let shared = Corpus()

    struct Statistics {
        var count = 0
        var totalSeconds: Double = 0
        var withApple = 0
        var withBothEngines = 0
        var audioFiles = 0
        var bytes: Int64 = 0

        var summary: String {
            guard count > 0 else { return "Corpus vide" }
            let minutes = Int(totalSeconds / 60)
            let duration = minutes >= 60
                ? String(format: "%d h %02d min", minutes / 60, minutes % 60)
                : "\(minutes) min"
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "Corpus : \(count) dictées · \(duration) · \(size)"
        }
    }

    let root: URL
    var sessionsFile: URL { root.appendingPathComponent("sessions.jsonl") }
    var audioDirectory: URL { root.appendingPathComponent("audio") }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // ISO 8601 : lisible à l'œil et compris sans effort par pandas.
        encoder.dateEncodingStrategy = .iso8601
        // Surtout pas de `prettyPrinted` : une ligne par dictée est ce qui
        // rend le fichier lisible en flux et réparable à la main.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        root = support.appendingPathComponent("Sofler/corpus", isDirectory: true)
    }

    /// Identifiant lisible et triable, qui sert aussi de nom de fichier audio.
    static func makeIdentifier(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Écriture

    func append(_ entry: CorpusEntry) {
        do {
            try prepare()
            var line = try encoder.encode(entry)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: sessionsFile.path) {
                let handle = try FileHandle(forWritingTo: sessionsFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: sessionsFile)
            }
            cachedStatistics = nil
            NSLog("sofler: corpus — dictée %@ archivée", entry.id)
        } catch {
            NSLog("sofler: corpus — écriture impossible : %@", String(describing: error))
        }
    }

    /// Écrit l'audio d'une dictée et rend le nom du fichier produit.
    ///
    /// Coûteux en place — de l'ordre de 2 Mo par minute en float 32 bits —
    /// d'où une option distincte de la collecte de texte.
    func writeAudio(_ samples: [Float], id: String) -> String? {
        let name = "\(id).wav"
        do {
            try prepare()
            guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: AudioRecorder.targetSampleRate,
                    channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }

            let file = try AVAudioFile(forWriting: audioDirectory.appendingPathComponent(name),
                                       settings: format.settings,
                                       commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!,
                                                   count: samples.count)
            }
            try file.write(from: buffer)
            return name
        } catch {
            NSLog("sofler: corpus — audio non conservé : %@", String(describing: error))
            return nil
        }
    }

    private func prepare() throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: audioDirectory.path) {
            try manager.createDirectory(at: audioDirectory,
                                        withIntermediateDirectories: true)
        }
        let readme = root.appendingPathComponent("README.md")
        if !manager.fileExists(atPath: readme.path) {
            try? Self.readme.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Lecture

    /// État du corpus, mis en cache.
    ///
    /// Le menu est reconstruit à chaque changement d'état, donc au démarrage
    /// de chaque dictée. Relire tout le fichier à ce moment-là, sur le main
    /// actor, ferait une saccade au pire instant — juste quand l'utilisateur
    /// commence à parler. Le cache n'a aucun risque de dériver : cette classe
    /// est le seul écrivain, et il est invalidé à chaque écriture.
    private var cachedStatistics: Statistics?

    func statistics() -> Statistics {
        if let cachedStatistics { return cachedStatistics }
        let computed = readStatistics()
        cachedStatistics = computed
        return computed
    }

    private func readStatistics() -> Statistics {
        var stats = Statistics()
        guard let content = try? String(contentsOf: sessionsFile, encoding: .utf8) else {
            return stats
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in content.split(separator: "\n") {
            guard let entry = try? decoder.decode(CorpusEntry.self,
                                                  from: Data(line.utf8)) else { continue }
            stats.count += 1
            stats.totalSeconds += entry.durationSeconds
            let moteurs = Set(entry.transcriptions.map(\.engine))
            if moteurs.contains("apple") { stats.withApple += 1 }
            if moteurs.count > 1 { stats.withBothEngines += 1 }
            if entry.audioFile != nil { stats.audioFiles += 1 }
        }
        stats.bytes = directorySize()
        return stats
    }

    private func directorySize() -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let size = try? url.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize
            total += Int64(size ?? 0)
        }
        return total
    }

    // MARK: - Entretien

    func reveal() {
        try? prepare()
        NSWorkspace.shared.activateFileViewerSelecting([sessionsFile])
    }

    /// Repart de zéro. Le dossier lui-même est conservé, pour que le Finder
    /// laissé ouvert dessus ne se retrouve pas sur un dossier fantôme.
    func clear() {
        let manager = FileManager.default
        try? manager.removeItem(at: sessionsFile)
        try? manager.removeItem(at: audioDirectory)
        try? prepare()
        cachedStatistics = nil
        NSLog("sofler: corpus vidé")
    }

    private static let readme = """
    # Corpus Sofler

    Une ligne JSON par dictée dans `sessions.jsonl`, en ajout seul. Le fichier
    n'est jamais réécrit : il peut être lu pendant que l'application tourne.

    ## Champs

    | champ | sens |
    |---|---|
    | `id` | horodatage, sert aussi de nom au fichier audio |
    | `date` | ISO 8601 |
    | `durationSeconds` | durée de parole captée |
    | `language` | langue demandée au moteur |
    | `destination` | `curseur` ou `notes` |
    | `lexicon` | termes envoyés aux moteurs, absent si celui du moteur |
    | `transcriptions[]` | une entrée par moteur et par mode |
    | `transcriptions[].engine` | `apple`, `crisperwhisper`, … |
    | `transcriptions[].model` | modèle précis, ou locale pour un moteur système |
    | `transcriptions[].mode` | `intended`, `verbatim`, absent si le moteur n'en a qu'un |
    | `transcriptions[].inserted` | celle qui a été réellement insérée |
    | `transcriptions[].latencyMs` | temps mur, absent pour un texte capté en flux |
    | `skipped[]` | moteurs demandés mais non exécutés, avec la raison |
    | `audioFile` | nom dans `audio/`, absent si l'audio n'est pas conservé |

    Les trois textes viennent du **même** audio. `textApple` est celui de
    l'aperçu en direct : il est produit en flux pendant la dictée, avec
    l'option `fastResults`, donc légèrement moins exact que ce que le même
    moteur produirait sur le fichier complet.

    ## Relire le corpus

        import pandas as pd
        df = pd.read_json("sessions.jsonl", lines=True)
        df[["textIntended", "textApple"]].head()

    ## Repartir de zéro

    Menu de Sofler › Effacer le corpus. Ou supprimer `sessions.jsonl` et
    `audio/` à la main : l'application les recrée.
    """
}
