import Foundation
import Testing
@testable import CasprCore

/// La rétrocompatibilité du corpus, vérifiée à chaque build.
///
/// ## Pourquoi ces tests existent
///
/// Le corpus est la seule donnée du projet qu'aucune réinstallation ne
/// reconstitue : des heures de parole réelle, avec l'accent, le micro et le
/// vocabulaire de son auteur. Il est écrit en ajout seul et jamais relu par
/// l'application — donc **rien, à l'exécution, ne signale qu'il est devenu
/// illisible**. La relecture avale ses erreurs avec un `try?` : une ligne qui
/// ne décode plus disparaît silencieusement des statistiques, et le corpus
/// paraît simplement s'être vidé.
///
/// Le piège est connu et documenté dans `CorpusEntry` : le `Codable` synthétisé
/// **ne se rabat pas** sur la valeur par défaut d'une propriété quand la clé
/// manque, il lève `keyNotFound`. Ajouter un champ non optionnel au schéma rend
/// donc illisible *tout l'historique* d'un coup.
///
/// Les fixtures ci-dessous reproduisent les **formes exactes** relevées dans un
/// corpus réel de 94 dictées — jeux de clés et types identiques — avec des
/// textes de remplacement : ce sont les structures qui sont testées, pas les
/// phrases de quelqu'un.
@Suite("Schéma du corpus")
struct CorpusEntryTests {

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// La forme majoritaire : 64 des 94 lignes réelles. Ni `outcome`, ni
    /// `lexicon`, ni `locale`, ni `appVersion`, ni `failure`.
    private static let sansLexique = """
    {"audioFile":"2026-01-04T09-12-33.wav","date":"2026-01-04T09:12:33Z",\
    "destination":"curseur","durationSeconds":7.5,"id":"2026-01-04T09-12-33",\
    "language":"fr","skipped":[],"transcriptions":[\
    {"engine":"crisperwhisper","inserted":true,"latencyMs":212.0,\
    "mode":"intended","model":"nyralabs/CrisperWhisper2.0_turbo","text":"phrase un"},\
    {"engine":"apple","inserted":false,"text":"phrase un"}]}
    """

    /// L'autre forme : 30 lignes réelles, avec le lexique envoyé au moteur.
    private static let avecLexique = """
    {"audioFile":"2026-01-05T11-40-02.wav","date":"2026-01-05T11:40:02Z",\
    "destination":"notes","durationSeconds":21.25,"id":"2026-01-05T11-40-02",\
    "language":"en","lexicon":["useEffect","Next.js"],"skipped":["apple: indisponible"],\
    "transcriptions":[{"engine":"crisperwhisper","inserted":true,"latencyMs":388.0,\
    "mode":"verbatim","model":"nyralabs/CrisperWhisper2.0_turbo","text":"phrase deux"},\
    {"engine":"apple","inserted":false,"latencyMs":95.0,"model":"en_US","text":"phrase deux"}]}
    """

    @Test("Une ligne d'avant le multi-langues se relit encore")
    func ancienneLigneSeRelit() throws {
        let entry = try Self.decoder().decode(
            CorpusEntry.self, from: Data(Self.sansLexique.utf8))

        #expect(entry.id == "2026-01-04T09-12-33")
        #expect(entry.language == "fr")
        #expect(entry.durationSeconds == 7.5)
        #expect(entry.transcriptions.count == 2)
        #expect(entry.audioFile == "2026-01-04T09-12-33.wav")
    }

    @Test("La forme avec lexique se relit aussi")
    func ligneAvecLexiqueSeRelit() throws {
        let entry = try Self.decoder().decode(
            CorpusEntry.self, from: Data(Self.avecLexique.utf8))

        #expect(entry.lexicon == ["useEffect", "Next.js"])
        #expect(entry.skipped == ["apple: indisponible"])
        #expect(entry.destination == "notes")
    }

    /// Les champs ajoutés après coup doivent être **absents sans faire échouer
    /// la lecture**. C'est toute la règle, et c'est elle qu'on casse par
    /// inadvertance en déclarant un champ non optionnel.
    @Test("Les champs ajoutés après coup sont absents, pas fautifs")
    func champsRecentsAbsents() throws {
        let entry = try Self.decoder().decode(
            CorpusEntry.self, from: Data(Self.sansLexique.utf8))

        #expect(entry.locale == nil)
        #expect(entry.appVersion == nil)
        #expect(entry.storedOutcome == nil)
        #expect(entry.failure == nil)
    }

    /// Une ligne d'avant l'archivage des échecs ne pouvait décrire qu'une
    /// insertion réussie : c'était la seule issue archivée à l'époque.
    @Test("Sans outcome, la dictée est une insertion réussie")
    func outcomeParDefaut() throws {
        let entry = try Self.decoder().decode(
            CorpusEntry.self, from: Data(Self.sansLexique.utf8))

        #expect(entry.outcome == .inserted)
        #expect(entry.insertedTranscription?.engine == "crisperwhisper")
    }

    /// Sans `locale`, la locale à demander aux moteurs est le code court —
    /// tout ce dont on disposait alors. Une seconde passe relancée sur une
    /// vieille ligne doit donc rester possible.
    @Test("Sans locale, on retombe sur le code court")
    func localeParDefaut() throws {
        let ancienne = try Self.decoder().decode(
            CorpusEntry.self, from: Data(Self.sansLexique.utf8))
        #expect(ancienne.requestLocale == "fr")

        var moderne = ancienne
        moderne.locale = "fr-CA"
        #expect(moderne.requestLocale == "fr-CA")
    }

    /// La langue reste en code court dans les entrées neuves : c'est ce qui
    /// garde comparables les dictées d'avant et d'après le multi-langues, et
    /// c'est aussi ce qu'attend le décodeur de CrisperWhisper (`<|fr|>`).
    @Test("Une entrée neuve garde le code court et range la région à part")
    func entreeNeuveSeparelangueEtRegion() throws {
        let entry = CorpusEntry(
            id: "2026-08-18T14-00-00", date: Date(timeIntervalSince1970: 1_786_000_000),
            durationSeconds: 4, language: "fr", locale: "fr-FR",
            appVersion: "0.9.0", destination: "curseur",
            transcriptions: [CorpusTranscription(engine: "apple", text: "phrase",
                                                 inserted: true)],
            storedOutcome: .inserted)

        let line = String(decoding: try Self.encoder().encode(entry), as: UTF8.self)
        #expect(line.contains("\"language\":\"fr\""))
        #expect(line.contains("\"locale\":\"fr-FR\""))
        #expect(!line.contains("\"language\":\"fr-FR\""))
    }

    /// Un aller-retour complet ne doit rien perdre : le corpus n'est jamais
    /// réécrit, mais une ligne relue puis réencodée sert aux outils d'analyse.
    @Test("Un aller-retour ne perd aucun champ")
    func allerRetourComplet() throws {
        let original = CorpusEntry(
            id: "2026-08-18T15-30-00", date: Date(timeIntervalSince1970: 1_786_003_600),
            durationSeconds: 12.5, language: "en", locale: "en-GB",
            appVersion: "0.9.0", destination: "notes",
            lexicon: ["Kubernetes"],
            transcriptions: [
                CorpusTranscription(engine: "crisperwhisper",
                                    model: "nyralabs/CrisperWhisper2.0_turbo",
                                    mode: "intended", text: "phrase",
                                    latencyMs: 240, inserted: false),
            ],
            storedOutcome: .failed, failure: "socket injoignable",
            skipped: ["apple: dictée enchaînée"], audioFile: "2026-08-18T15-30-00.wav")

        let data = try Self.encoder().encode(original)
        let round = try Self.decoder().decode(CorpusEntry.self, from: data)

        #expect(round.locale == "en-GB")
        #expect(round.appVersion == "0.9.0")
        #expect(round.outcome == .failed)
        #expect(round.failure == "socket injoignable")
        #expect(round.skipped == ["apple: dictée enchaînée"])
        #expect(round.audioFile == "2026-08-18T15-30-00.wav")
        #expect(round.lexicon == ["Kubernetes"])
        #expect(round.transcriptions.first?.latencyMs == 240)
    }

    /// Les trois formes de transcription relevées dans le corpus réel. La
    /// dernière — sans `model`, `mode` ni `latencyMs` — est le texte de
    /// l'aperçu en direct, capté en flux pendant qu'on parlait.
    @Test("Les trois formes de transcription se relisent")
    func formesDeTranscription() throws {
        let lines = [
            #"{"engine":"crisperwhisper","inserted":true,"latencyMs":212.0,"mode":"intended","model":"turbo","text":"a"}"#,
            #"{"engine":"apple","inserted":false,"latencyMs":95.0,"model":"fr_FR","text":"b"}"#,
            #"{"engine":"apple","inserted":false,"text":"c"}"#,
        ]
        let decoded = try lines.map {
            try Self.decoder().decode(CorpusTranscription.self, from: Data($0.utf8))
        }

        #expect(decoded[0].mode == "intended")
        #expect(decoded[1].mode == nil)
        #expect(decoded[1].latencyMs == 95)
        // Sans latence : produit en flux pendant la dictée, où la notion de
        // temps mur n'a pas de sens.
        #expect(decoded[2].latencyMs == nil)
        #expect(decoded[2].model == nil)
    }
}
