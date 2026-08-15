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

    /// Ce moteur distingue-t-il texte nettoyé et mot à mot ?
    var hasModes: Bool { self == .crisperWhisper }

    /// Ce moteur accepte-t-il un lexique qui change quelque chose ?
    ///
    /// Faux pour Apple, et c'est mesuré : `contextualStrings` existe dans son
    /// API mais ne modifie pas la sortie sur nos enregistrements.
    var honoursLexicon: Bool { self == .crisperWhisper }

    var explanation: String {
        switch self {
        case .apple:
            "Inclus dans macOS, rien à télécharger. Transcrit pendant que "
                + "vous parlez, donc sans attente. Ne connaît pas votre "
                + "vocabulaire technique : il écrira « use effect »."
        case .crisperWhisper:
            "Écrit `useEffect` correctement et distingue texte nettoyé et "
                + "mot à mot. Demande un modèle de 1,6 Go, environ 3 Go en "
                + "mémoire, et des poids sous licence non commerciale."
        }
    }
}
