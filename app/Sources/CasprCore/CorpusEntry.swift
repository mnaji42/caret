import Foundation

/// Une transcription, quel que soit le moteur qui l'a produite.
///
/// Toutes les transcriptions d'une même dictée viennent du **même** audio :
/// c'est ce qui rend la comparaison honnête.
public struct CorpusTranscription: Codable, Sendable {
    /// Famille du moteur : `apple`, `crisperwhisper`, `whisper`…
    public var engine: String
    /// Modèle précis quand il y en a un ; la locale pour un moteur système.
    public var model: String?
    /// `intended`, `verbatim`, ou absent quand le moteur n'a qu'un rendu.
    public var mode: String?
    public var text: String
    /// Temps mur du moteur. Absent pour un texte capté en flux pendant la
    /// dictée, où la notion n'a pas de sens.
    public var latencyMs: Double?
    /// Vrai pour celle qui a été réellement insérée chez l'utilisateur.
    public var inserted: Bool

    public init(engine: String, model: String? = nil, mode: String? = nil,
                text: String, latencyMs: Double? = nil, inserted: Bool) {
        self.engine = engine
        self.model = model
        self.mode = mode
        self.text = text
        self.latencyMs = latencyMs
        self.inserted = inserted
    }
}

/// Une dictée, telle qu'archivée pour comparer les moteurs.
///
/// La liste est ouverte : on peut en ajouter un quatrième ou un cinquième sans
/// toucher au format. La version précédente nommait un champ par moteur
/// (`textIntended`, `textApple`), ce qui ne survivait pas au premier moteur
/// supplémentaire — les entrées d'alors ont été converties.
///
/// ## Pourquoi ce type vit dans `CasprCore`
///
/// Il décrit le format de données le plus irremplaçable du projet : des heures
/// de parole réelle qu'aucune réinstallation ne reconstituera. `CasprCore` est
/// la cible sans dépendance système, donc la seule **testable** — et une règle
/// de rétrocompatibilité qu'on ne peut pas exécuter à chaque build n'est qu'un
/// commentaire de plus. Le reste de `Corpus` (écriture du JSONL, fichiers
/// audio, statistiques) demande AppKit et AVFoundation, et reste côté
/// application.
public struct CorpusEntry: Codable, Sendable {
    /// Ce qu'il est advenu de la dictée.
    ///
    /// Le corpus n'archivait que les succès : une transcription vide ou en
    /// échec sortait avant l'archivage. C'était perdre exactement ce qu'on
    /// cherche. Une dictée où CrisperWhisper ne produit rien pendant que macOS
    /// écrit la phrase juste est l'observation la plus tranchante qui soit
    /// pour arbitrer deux moteurs — et c'est la seule qui ne laissait aucune
    /// trace, y compris quand la panne durait des semaines.
    ///
    /// Une dictée **annulée** n'en fait pas partie : appuyer sur Échap dit
    /// qu'on ne veut pas de ce qu'on vient de dire, et l'archiver contre cet
    /// avis serait une trahison. Le cas ne se pose d'ailleurs pas : `cancel()`
    /// n'atteint jamais la transcription.
    public enum Outcome: String, Codable, Sendable {
        /// Le texte a été écrit chez l'utilisateur.
        case inserted
        /// Le moteur a répondu sans erreur, et sans un mot.
        case empty
        /// Le moteur a échoué. La raison est dans `failure`.
        case failed
    }

    public var id: String
    public var date: Date
    public var durationSeconds: Double
    /// La langue, en code court — `fr`, `en`.
    ///
    /// **Reste le code court alors que les réglages sont passés aux locales
    /// complètes**, et c'est délibéré. Les 94 premières dictées de ce corpus
    /// portent `fr` ou `en` ; écrire `fr-FR` à partir d'ici produirait deux
    /// groupes pour une même langue, et tout `groupby("language")` couperait
    /// l'historique en deux — c'est-à-dire exactement ce que cette archive
    /// existe pour empêcher.
    ///
    /// C'est aussi ce qu'attend CrisperWhisper, dont le décodeur impose la
    /// langue par un jeton `<|fr|>` : `<|fr-FR|>` n'existe pas dans son
    /// vocabulaire, et le lui envoyer dégrade la transcription sans lever
    /// d'erreur. La région n'est pas perdue pour autant : elle est dans
    /// `locale`.
    public var language: String
    /// La locale complète demandée aux moteurs — `fr-FR`, `fr-CA`.
    ///
    /// **Optionnel, et il doit le rester.** Cf. `storedOutcome` : le `Codable`
    /// synthétisé lève `keyNotFound` au lieu de retomber sur une valeur par
    /// défaut, donc un champ non optionnel rendrait illisible **toute** ligne
    /// écrite avant lui — et la relecture avale ses erreurs avec un `try?`, si
    /// bien que le corpus paraîtrait simplement s'être vidé.
    ///
    /// Absent sur les dictées antérieures au multi-langues, où la région
    /// n'était pas demandée : `nil` y veut dire « la locale par défaut du
    /// système à l'époque », et non « aucune ».
    public var locale: String?
    /// La version de Caspr qui a produit cette dictée.
    ///
    /// Optionnel pour la même raison. Sert à ne pas comparer des transcriptions
    /// séparées par un changement de moteur, de lexique ou de prompt : sans ce
    /// champ, une régression de qualité introduite par une version devient
    /// indistinguable du bruit de la parole spontanée.
    public var appVersion: String?
    public var destination: String
    /// Lexique envoyé aux moteurs qui en acceptent un ; `nil` = celui du moteur.
    public var lexicon: [String]?
    public var transcriptions: [CorpusTranscription]
    /// **Optionnel, et pas une valeur par défaut.** Mesuré : `Codable`
    /// synthétisé ne se rabat pas sur la valeur par défaut d'une propriété
    /// quand la clé manque, il lève `keyNotFound`. Déclarer
    /// `var outcome: Outcome = .inserted` rendait donc illisible **toute**
    /// ligne écrite avant ce champ — et comme la relecture avale ses erreurs
    /// avec un `try?`, le corpus aurait simplement paru se vider.
    ///
    /// Lire par `outcome`, jamais par ce champ : une ligne d'avant ne pouvait
    /// décrire qu'une insertion réussie, seule issue archivée à l'époque.
    public var storedOutcome: Outcome?
    /// Le message d'échec, quand il y en a un.
    public var failure: String?
    /// Ce qui était demandé mais n'a pas été produit, et pourquoi. Sans cette
    /// trace, une transcription manquante serait indistinguable d'un moteur
    /// qu'on n'avait pas coché.
    public var skipped: [String] = []
    /// Nom du fichier dans `audio/`, si l'option est active.
    public var audioFile: String?

    public var outcome: Outcome { storedOutcome ?? .inserted }

    enum CodingKeys: String, CodingKey {
        case id, date, durationSeconds, language, locale, appVersion
        case destination, lexicon
        case transcriptions, failure, skipped, audioFile
        case storedOutcome = "outcome"
    }

    /// Ce qui a été inséré chez l'utilisateur.
    public var insertedTranscription: CorpusTranscription? {
        transcriptions.first { $0.inserted }
    }

    /// La locale à demander aux moteurs pour cette dictée.
    ///
    /// Toutes les transcriptions d'une entrée doivent porter sur **la même**
    /// locale, sinon la comparaison ne dit plus rien : `fr-CA` et `fr-FR` ne
    /// chargent pas le même modèle chez Apple, et attribuer l'écart à un moteur
    /// alors qu'il vient de la région serait la pire conclusion possible.
    ///
    /// Le repli sur `language` couvre les lignes d'avant le multi-langues, où
    /// le code court était tout ce qu'on avait.
    public var requestLocale: String { locale ?? language }

    public init(id: String, date: Date, durationSeconds: Double,
                language: String, locale: String? = nil, appVersion: String? = nil,
                destination: String, lexicon: [String]? = nil,
                transcriptions: [CorpusTranscription],
                storedOutcome: Outcome? = nil, failure: String? = nil,
                skipped: [String] = [], audioFile: String? = nil) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.language = language
        self.locale = locale
        self.appVersion = appVersion
        self.destination = destination
        self.lexicon = lexicon
        self.transcriptions = transcriptions
        self.storedOutcome = storedOutcome
        self.failure = failure
        self.skipped = skipped
        self.audioFile = audioFile
    }
}
