import Foundation

/// Ce que l'utilisateur dit de son usage, à l'écran 2 de l'accueil.
///
/// Trois questions, et elles ne sont pas exclusives deux à deux : on peut à la
/// fois mêler les langues et dicter du code. La simplicité, elle, s'oppose aux
/// deux autres — demander la légèreté tout en réclamant un modèle de 1,6 Go
/// n'aurait pas de sens — d'où la règle de saisie portée par `select`.
public struct UsageHabits: Equatable, Codable, Sendable {
    /// « Je mélange souvent les langues » — franglais, expressions bilingues.
    public var mixesLanguages = false
    /// « J'utilise du vocabulaire technique, du code, du jargon métier. »
    public var usesJargon = false
    /// « Je cherche la simplicité et la légèreté. »
    public var wantsLightweight = false

    public init(mixesLanguages: Bool = false, usesJargon: Bool = false,
                wantsLightweight: Bool = false) {
        self.mixesLanguages = mixesLanguages
        self.usesJargon = usesJargon
        self.wantsLightweight = wantsLightweight
    }

    public enum Habit: String, CaseIterable, Sendable {
        case mixesLanguages, usesJargon, wantsLightweight
    }

    public func has(_ habit: Habit) -> Bool {
        switch habit {
        case .mixesLanguages: mixesLanguages
        case .usesJargon: usesJargon
        case .wantsLightweight: wantsLightweight
        }
    }

    /// Bascule une habitude en maintenant la cohérence de l'ensemble.
    ///
    /// « Légèreté » et les deux autres s'excluent : cocher la première décoche
    /// les secondes, et réciproquement. Sans cette règle, on obtient un état où
    /// quelqu'un demande à la fois 0 Mo en mémoire et un modèle de 1,6 Go — et
    /// la recommandation qui en sort est arbitraire quel que soit l'ordre des
    /// règles, donc impossible à justifier à l'écran.
    public mutating func toggle(_ habit: Habit) {
        switch habit {
        case .wantsLightweight:
            let next = !wantsLightweight
            self = UsageHabits(mixesLanguages: false, usesJargon: false,
                               wantsLightweight: next)
        case .mixesLanguages:
            mixesLanguages.toggle()
            wantsLightweight = false
        case .usesJargon:
            usesJargon.toggle()
            wantsLightweight = false
        }
    }
}

/// Le moteur conseillé, et la raison qui l'accompagne.
///
/// La raison compte autant que le choix : une recommandation sans motif se lit
/// comme une préférence de l'auteur de l'application, et se suit ou s'ignore au
/// hasard. Avec son motif, elle se vérifie.
public struct EngineRecommendation: Equatable, Sendable {
    public enum Choice: String, Equatable, Sendable {
        case appleNative
        case crisperWhisper
    }

    public let choice: Choice
    public let reason: String

    /// Les langues sur lesquelles Whisper se distingue nettement des moteurs
    /// système, en ponctuation et en syntaxe.
    ///
    /// Restreint à deux, volontairement : c'est là que l'écart est assez large
    /// pour justifier 1,6 Go de téléchargement à quelqu'un qui n'a rien
    /// demandé. Élargir la liste transformerait un conseil en argumentaire.
    public static let whisperStrongBases: Set<String> = ["en", "de"]

    /// Le conseil, à partir des habitudes déclarées et de la langue principale.
    ///
    /// Les motifs sont ceux du prototype (`recommendationReason` dans
    /// `CasprContext.jsx`), mot pour mot : c'est du texte validé, pas une
    /// formulation à réinventer ici.
    ///
    /// - Parameters:
    ///   - habits: ce que l'utilisateur a coché.
    ///   - primaryBase: le code ISO-639-1 de la langue principale — `fr`, `en`.
    ///   - crisperCoversAll: CrisperWhisper couvre-t-il **toutes** les langues
    ///     retenues ? Conseiller un moteur qui n'en couvre qu'une partie ferait
    ///     basculer sur macOS dès la première bascule de langue, sans
    ///     l'annoncer.
    public static func advise(habits: UsageHabits, primaryBase: String,
                              crisperCoversAll: Bool) -> EngineRecommendation {
        // 1. La légèreté d'abord : c'est une demande explicite, et aucune
        //    qualité de transcription ne vaut qu'on passe outre.
        if habits.wantsLightweight {
            return EngineRecommendation(
                choice: .appleNative,
                reason: "Mode simplicité & légèreté (0 Mo de RAM résidente)")
        }

        // 2. Un moteur qui ne couvre pas toutes les langues retenues se
        //    disqualifie avant même qu'on regarde les habitudes : le
        //    recommander reviendrait à promettre un repli silencieux.
        guard crisperCoversAll else {
            return EngineRecommendation(
                choice: .appleNative,
                reason: "CrisperWhisper ne couvre pas toutes les langues retenues")
        }

        // 3. Les deux usages où le conditionnement du lexique change vraiment
        //    la sortie. Ils partagent leur motif : ce sont les deux faces du
        //    même problème — des mots que le moteur ne connaît pas.
        if habits.usesJargon || habits.mixesLanguages {
            return EngineRecommendation(
                choice: .crisperWhisper,
                reason: "Idéal pour le Franglais, le vocabulaire technique & le code")
        }

        // 4. L'anglais et l'allemand, où l'écart se voit sans avoir rien coché.
        if whisperStrongBases.contains(primaryBase) {
            return EngineRecommendation(
                choice: .crisperWhisper,
                reason: "Précision exceptionnelle en Anglais / Allemand via Whisper")
        }

        // 5. À défaut : ce qui ne coûte rien et n'a rien à télécharger.
        return EngineRecommendation(
            choice: .appleNative,
            reason: "Recommandé par défaut (rapide, 0 Mo de RAM)")
    }
}
