import Foundation

/// Les moteurs que Sofler sait utiliser.
///
/// Volontairement une énumération fermée plutôt qu'une liste dynamique : les
/// moteurs ne s'ajoutent pas à l'exécution, ils demandent chacun une
/// implémentation. Ce qui varie à l'exécution, c'est leur *disponibilité* —
/// modèle téléchargé ou non, version de macOS.
enum EngineChoice: String, CaseIterable, Sendable, Codable {
    /// Le moteur de macOS. Inclus, instantané, sans lexique.
    case apple
    /// CrisperWhisper via le service local. Lexique et deux modes, mais
    /// ~3 Go en mémoire et des poids sous licence non commerciale.
    case crisperWhisper = "crisperwhisper"

    var label: String {
        switch self {
        case .apple: "macOS"
        case .crisperWhisper: "CrisperWhisper"
        }
    }

    /// Le moteur intégré est-il utilisable ici ?
    ///
    /// C'est la seule condition qui rend Sofler utilisable sans rien
    /// installer. En dessous de macOS 26 l'application se lance quand même
    /// — cf. `LSMinimumSystemVersion` dans install.sh — précisément pour
    /// pouvoir l'expliquer plutôt que de se faire refuser par le système.
    ///
    /// Vit ici et non dans une vue : l'accueil et les Réglages posent la même
    /// question, et deux copies d'une condition de disponibilité finissent
    /// toujours par répondre différemment.
    static var systemEngineAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    /// Ce moteur distingue-t-il texte nettoyé et mot à mot ?
    var hasModes: Bool { self == .crisperWhisper }

    /// Ce moteur accepte-t-il un lexique qui change quelque chose ?
    ///
    /// Faux pour Apple, et c'est mesuré : `contextualStrings` existe dans son
    /// API mais ne modifie pas la sortie sur nos enregistrements.
    var honoursLexicon: Bool { self == .crisperWhisper }

    /// Ce que change le choix, dit sans jargon.
    ///
    /// La formulation précédente opposait « use effect » à `useEffect`, ce qui
    /// ne parle qu'aux gens qui écrivent du React. La différence mesurée est
    /// pourtant générale : un moteur sans conditionnement remplace les mots
    /// qu'il ne connaît pas par ceux qui leur ressemblent, et ça vaut pour les
    /// noms propres et les mots étrangers autant que pour le code.
    var explanation: String {
        switch self {
        case .apple:
            "Fourni par macOS : aucune licence, aucun compte, et le texte "
                + "arrive dès que vous avez fini de parler. Son modèle de "
                + "reconnaissance se télécharge tout seul au premier usage "
                + "s'il n'est pas déjà sur la machine — c'est le cas d'un "
                + "macOS fraîchement installé. Il transcrit en français "
                + "courant : les mots qu'il ne connaît pas — noms propres, "
                + "mots anglais, vocabulaire de votre métier — sont remplacés "
                + "par ceux qui leur ressemblent."
        case .crisperWhisper:
            "Vous lui donnez la liste des mots que vous employez, et il les "
                + "écrit tels quels. Il sait aussi séparer le texte nettoyé du "
                + "mot à mot, qui garde vos hésitations. En échange : 1,6 Go à "
                + "télécharger, environ 3 Go en mémoire, et des poids sous "
                + "licence non commerciale."
        }
    }
}
