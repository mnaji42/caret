import Foundation
import Speech

/// Les moteurs que Sofler sait utiliser.
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
enum EngineChoice: String, CaseIterable, Sendable, Codable {
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
    var label: String {
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
    var versionLabel: String? {
        switch self {
        case .apple: "Apple Intelligence"
        case .appleLegacy: "Dictée"
        case .crisperWhisper: nil
        }
    }

    /// Famille et version d'un coup — « macOS · Dictée », « CrisperWhisper ».
    var fullLabel: String {
        guard let versionLabel else { return label }
        return "\(label) · \(versionLabel)"
    }

    /// Les moteurs fournis par le système, dans l'ordre de finesse attendue.
    static var systemEngines: [EngineChoice] { [.apple, .appleLegacy] }

    /// Ce moteur vient-il de macOS ?
    ///
    /// Les règles qui distinguent les familles se posent **ainsi**, jamais en
    /// nommant CrisperWhisper : un quatrième moteur ajouté demain hériterait
    /// silencieusement des règles écrites pour le troisième.
    var isSystem: Bool { Self.systemEngines.contains(self) }

    /// Ce moteur distingue-t-il texte nettoyé et mot à mot ?
    var hasModes: Bool { self == .crisperWhisper }

    /// Ce moteur est-il utilisable ici, **maintenant** ?
    ///
    /// Mesuré, jamais déduit d'un numéro de version. Une machine virtuelle en
    /// macOS 26 dicte parfaitement avec `SFSpeechRecognizer` et n'a aucun
    /// modèle pour `SpeechTranscriber` : conclure de « macOS 26 » que le
    /// second fonctionne serait faux, et l'a été.
    func isAvailable(for language: String) -> Bool {
        switch self {
        case .apple:
            if #available(macOS 26.0, *) { return SpeechTranscriber.isAvailable }
            return false
        case .appleLegacy:
            return LegacySpeechEngine.isAvailable(for: language)
        case .crisperWhisper:
            return EngineService.isInstalled || EngineService.modelIsDownloaded
        }
    }

    /// Les versions de macOS que cette machine sait faire tourner, ici et
    /// maintenant, dans cette langue.
    ///
    /// C'est la liste qui décide s'il y a un sélecteur à afficher : deux
    /// entrées, un sélecteur ; une seule, la version passe dans le titre et
    /// rien ne suggère un choix impossible ; aucune, la ligne reste mais
    /// n'est plus sélectionnable.
    static func availableSystemEngines(for language: String) -> [EngineChoice] {
        systemEngines.filter { $0.isAvailable(for: language) }
    }

    /// La version de macOS à retenir quand on choisit « macOS ».
    ///
    /// Celle déjà réglée si elle fonctionne — changer de langue ou rouvrir les
    /// réglages ne doit pas déplacer un choix explicite — sinon la plus fine
    /// disponible. `nil` quand aucune ne marche ici.
    static func systemEngine(preferring current: EngineChoice,
                             for language: String) -> EngineChoice? {
        if current.isSystem, current.isAvailable(for: language) { return current }
        return availableSystemEngines(for: language).first
    }

    /// Ce moteur accepte-t-il un lexique qui change quelque chose ?
    ///
    /// Faux pour Apple, et c'est mesuré : `contextualStrings` existe dans son
    /// API mais ne modifie pas la sortie sur nos enregistrements.
    var honoursLexicon: Bool { self == .crisperWhisper }

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
    var explanation: String {
        switch self {
        case .apple, .appleLegacy:
            "Fourni par macOS : aucune licence, aucun compte, rien à installer, "
                + "et rien ne réside en mémoire entre deux dictées. **Tout reste "
                + "sur votre Mac** — Sofler force la reconnaissance hors ligne, "
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
    var versionExplanation: String? {
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
