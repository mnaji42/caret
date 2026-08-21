//  Les moteurs, et ce qu'ils savent faire.
//
//  Ce fichier est dans CasprCore, pas dans l'application, et c'est la raison
//  d'être de l'étape : les capacités d'un moteur sont des **règles pures**, du
//  même genre que la comparaison de versions ou le découpage d'un titre de
//  fenêtre. Elles n'interrogent ni le micro, ni launchd, ni le disque — elles
//  se déduisent du cas, et rien d'autre.
//
//  Elles n'étaient donc couvertes par aucun test, alors que ce sont exactement
//  celles qui se cassent sans bruit : une capacité fausse ne plante pas, elle
//  fait dicter avec le mauvais moteur. Ce qui interroge la machine — « ce
//  moteur est-il utilisable ici, maintenant ? » — reste dans l'application,
//  dans `EngineChoice+Availability.swift`.

import Foundation

/// Les moteurs que Caspr sait utiliser.
///
/// Volontairement une énumération fermée plutôt qu'une liste dynamique : les
/// moteurs ne s'ajoutent pas à l'exécution, ils demandent chacun une
/// implémentation. Ce qui varie à l'exécution, c'est leur *disponibilité* —
/// modèle téléchargé ou non, version de macOS.
///
/// ## Deux familles, trois moteurs
///
/// macOS en fournit deux, et ils ne s'opposent pas : c'est le même fournisseur,
/// la même promesse et le même réglage, à une génération près. Les présenter
/// comme trois choix de même rang faisait lire trois décisions là où il n'y en
/// a qu'une — « macOS ou CrisperWhisper » — suivie d'un détail interne, au même
/// titre que le modèle sous CrisperWhisper. D'où `label`, qui nomme la famille,
/// et `versionLabel`, qui nomme la version à l'intérieur.
public enum EngineChoice: String, CaseIterable, Sendable, Codable {
    /// Le moteur de macOS 26 : `SpeechTranscriber`, taillé pour la
    /// transcription longue. Exige Apple Intelligence.
    case apple
    /// L'autre moteur de macOS : `SFSpeechRecognizer`, celui de la Dictée du
    /// système, disponible depuis macOS 10.15 et sur toute machine dont la
    /// dictée fonctionne — Mac Intel compris.
    case appleLegacy = "apple-legacy"
    /// CrisperWhisper via le service local. Lexique et deux modes, mais
    /// ~3 Go en mémoire et des poids sous licence non commerciale.
    case crisperWhisper = "crisperwhisper"

    /// Le fournisseur, tel qu'on le choisit.
    public var label: String {
        switch self {
        case .apple, .appleLegacy: "macOS"
        case .crisperWhisper: "CrisperWhisper"
        }
    }

    /// La version, à l'intérieur de la famille. `nil` quand il n'y en a qu'une.
    ///
    /// Les deux noms sont ceux des Réglages Système, et c'est délibéré : quand
    /// une version manque, c'est là qu'il faut aller. « Apple Intelligence »
    /// est exactement ce qui conditionne les modèles de `SpeechTranscriber` ;
    /// « Dictée » est le panneau qui installe ceux de `SFSpeechRecognizer`.
    /// Un nom qui dit « récent » ou « classique » aurait laissé chercher.
    public var versionLabel: String? {
        switch self {
        case .apple: "Apple Intelligence"
        case .appleLegacy: "Dictée"
        case .crisperWhisper: nil
        }
    }

    /// Famille et version d'un coup — « macOS · Dictée », « CrisperWhisper ».
    public var fullLabel: String {
        guard let versionLabel else { return label }
        return "\(label) · \(versionLabel)"
    }

    /// Les moteurs fournis par le système, dans l'ordre de finesse attendue.
    public static var systemEngines: [EngineChoice] { [.apple, .appleLegacy] }

    /// Ce moteur vient-il de macOS ?
    ///
    /// Les règles qui distinguent les familles se posent **ainsi**, jamais en
    /// nommant CrisperWhisper : un quatrième moteur ajouté demain hériterait
    /// silencieusement des règles écrites pour le troisième.
    ///
    /// ## Pourquoi un `switch` là où une appartenance suffisait
    ///
    /// `systemEngines.contains(self)` répond juste, et répondra encore juste
    /// pour un moteur ajouté demain — *faux*, ce qui se trouve être la bonne
    /// réponse. C'est précisément le problème : elle est bonne par accident.
    /// Un `switch` sans `default` oblige le compilateur à poser la question au
    /// moment où le cas apparaît, plutôt qu'à la laisser se répondre toute
    /// seule. Toutes les capacités ci-dessous suivent cette règle, et c'est
    /// leur seule raison d'être écrites ainsi.
    public var isSystem: Bool {
        switch self {
        case .apple, .appleLegacy: true
        case .crisperWhisper: false
        }
    }

    /// Ce moteur tourne-t-il derrière le service local ?
    ///
    /// Le miroir de `isSystem`, et il manquait. Dix-neuf endroits demandaient
    /// `== .crisperWhisper` pour poser *cette* question — faut-il démarrer un
    /// démon, attendre que le socket réponde, proposer un téléchargement — et
    /// non « est-ce CrisperWhisper ». La nuance est sans effet tant qu'il n'y
    /// a qu'un moteur local ; au deuxième elle devient un défaut muet, puisque
    /// le compilateur n'a rien à redire à une égalité qui reste vraie.
    ///
    /// Concrètement, trois pannes que cette propriété existe pour empêcher :
    /// un moteur déclaré prêt sans que son démon soit debout, un moteur qui
    /// arrête son propre service parce que `needsLocalEngine` l'ignore, et un
    /// choix d'utilisateur silencieusement lu comme « macOS ».
    public var isLocalService: Bool {
        switch self {
        case .crisperWhisper: true
        case .apple, .appleLegacy: false
        }
    }

    /// Ce moteur distingue-t-il texte nettoyé et mot à mot ?
    public var hasModes: Bool {
        switch self {
        case .crisperWhisper: true
        case .apple, .appleLegacy: false
        }
    }

    /// Ce moteur accepte-t-il un lexique qui change quelque chose ?
    ///
    /// Faux pour Apple, et c'est mesuré : `contextualStrings` existe dans son
    /// API mais ne modifie pas la sortie sur nos enregistrements.
    public var honoursLexicon: Bool {
        switch self {
        case .crisperWhisper: true
        case .apple, .appleLegacy: false
        }
    }

    /// Ce que change le choix **de famille**, dit sans jargon.
    ///
    /// Ce texte porte la ligne qu'on sélectionne : il doit valoir pour les deux
    /// versions de macOS, puisqu'on choisit la famille avant la version. Ce qui
    /// les sépare est dans `versionExplanation`, sous le sélecteur.
    ///
    /// La formulation précédente opposait « use effect » à `useEffect`, ce qui
    /// ne parle qu'aux gens qui écrivent du React. La différence mesurée est
    /// pourtant générale : un moteur sans conditionnement remplace les mots
    /// qu'il ne connaît pas par ceux qui leur ressemblent, et ça vaut pour les
    /// noms propres et les mots étrangers autant que pour le code.
    public var explanation: String {
        switch self {
        case .apple, .appleLegacy:
            "Fourni par macOS : aucune licence, aucun compte, rien à installer, "
                + "et rien ne réside en mémoire entre deux dictées. **Tout reste "
                + "sur votre Mac** — Caspr force la reconnaissance hors ligne, "
                + "et refuse de travailler si la machine ne sait pas le faire. "
                + "Il transcrit en langue courante et n'a qu'un seul rendu : les "
                + "mots qu'il ne connaît pas — noms propres, mots anglais, "
                + "vocabulaire de votre métier — sont remplacés par ceux qui "
                + "leur ressemblent."
        case .crisperWhisper:
            "Vous lui donnez la liste des mots que vous employez, et il les "
                + "écrit tels quels. Il sait aussi séparer le texte nettoyé du "
                + "mot à mot, qui garde vos hésitations. En échange : 1,6 Go à "
                + "télécharger, environ 3 Go en mémoire, et des poids sous "
                + "licence non commerciale."
        }
    }

    /// Ce que change le choix **de version**, sous le sélecteur.
    ///
    /// Court exprès : il n'apparaît que quand il y a réellement deux versions à
    /// départager, et il ne répète pas ce que la ligne dit déjà de la famille.
    public var versionExplanation: String? {
        switch self {
        case .apple:
            "Le moteur apparu avec macOS 26. Plus fin sur les passages longs, "
                + "et son modèle se télécharge par langue — il demande Apple "
                + "Intelligence."
        case .appleLegacy:
            "Le moteur de la Dictée de macOS, présent sur toute machine où la "
                + "dictée du système fonctionne, Mac Intel compris. Rien à "
                + "télécharger : il se sert des modèles que la Dictée a déjà "
                + "installés, et il couvre plus de langues que l'autre."
        case .crisperWhisper:
            nil
        }
    }
}
