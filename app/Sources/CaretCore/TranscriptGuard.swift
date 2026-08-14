import Foundation

/// Garde-fou sur une transcription réécrite par un modèle de langue.
///
/// Le mode « relu » repasse le texte dans un LLM local pour réparer les mots
/// manifestement inventés. Mesuré, ce modèle dérape de trois façons :
///
/// * il **répond** à la phrase au lieu de la corriger — « dis-moi ce qu'il
///   reste dans le Tarot de map » a produit une liste à puces de ce que
///   contient une feuille de route ;
/// * il corrige avec aplomb et à tort — « chun-teint » devenu « changer »
///   alors que le mot était « chunk » ;
/// * il ajoute du formatage qu'on ne lui a pas demandé.
///
/// On ne peut pas cibler les passages douteux : mesuré aussi, les mots à
/// faible confiance du transcripteur sont des mots **corrects** — l'hésitation
/// porte sur la ponctuation. Le modèle est aussi sûr de ses inventions que du
/// reste.
///
/// D'où ce filtre : une réécriture n'est acceptée que si elle **ressemble**
/// assez à l'original. Une correction de quelques mots passe ; une réponse
/// hors sujet ou une reformulation est rejetée et l'original conservé.
public enum TranscriptGuard {

    /// Écart maximal toléré, en proportion de la longueur.
    ///
    /// Réparer du charabia touche quelques mots. Au-delà, ce n'est plus une
    /// correction — c'est un autre texte, et mieux vaut un mot bizarre visible
    /// qu'un paragraphe réécrit sans qu'on le sache.
    public static let maximumDrift = 0.35

    /// Nombre de mots toujours autorisés, quelle que soit la longueur.
    ///
    /// Sur une phrase courte, une correction légitime pèse lourd en
    /// proportion : « le Tarot de map » réparé en « la roadmap » touche quatre
    /// mots sur huit, soit la moitié du texte. Sans ce plancher, le filtre
    /// rejetterait précisément les corrections qu'on attend de lui.
    public static let alwaysAllowedWords = 4

    public enum Verdict: Equatable {
        case accepted(String)
        case rejected(reason: String)
    }

    public static func review(original: String, rewritten: String) -> Verdict {
        let clean = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else {
            return .rejected(reason: "réponse vide")
        }
        // Un texte qui gonfle ou fond a été reformulé, pas réparé.
        let ratio = Double(clean.count) / Double(max(source.count, 1))
        guard ratio > 0.6, ratio < 1.4 else {
            return .rejected(reason: "longueur trop différente")
        }
        // Le formatage est un signe que le modèle a « rédigé » une réponse.
        if clean.contains("**") || clean.contains("\n*") || clean.contains("\n-") {
            return .rejected(reason: "formatage ajouté")
        }
        let (changed, total) = wordChanges(source, clean)
        let allowed = max(alwaysAllowedWords,
                          Int(Double(total) * maximumDrift))
        guard changed <= allowed else {
            return .rejected(reason: "\(changed) mots changés sur \(total)")
        }
        return .accepted(clean)
    }

    /// Nombre de mots qui diffèrent, et taille du plus long des deux textes.
    ///
    /// Comparaison ensembliste plutôt qu'alignement : on cherche l'ampleur du
    /// changement, pas sa nature, et ça reste juste quand l'ordre bouge un peu.
    static func wordChanges(_ a: String, _ b: String) -> (changed: Int, total: Int) {
        let left = tokens(a)
        let right = tokens(b)
        let total = max(left.count, right.count)
        guard total > 0 else { return (0, 0) }

        var remaining = right
        var shared = 0
        for word in left where remaining.firstIndex(of: word) != nil {
            remaining.remove(at: remaining.firstIndex(of: word)!)
            shared += 1
        }
        return (total - shared, total)
    }

    /// Proportion de mots modifiés, entre 0 et 1.
    static func wordDrift(_ a: String, _ b: String) -> Double {
        let (changed, total) = wordChanges(a, b)
        return total == 0 ? 0 : Double(changed) / Double(total)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
