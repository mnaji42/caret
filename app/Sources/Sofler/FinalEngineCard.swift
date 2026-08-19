import SwiftUI
import SoflerCore

/// Le choix qui compte : qui écrit le texte définitif.
///
/// Deux lignes, macOS et CrisperWhisper, chacune hébergeant son propre panneau
/// de configuration. La version de macOS et le modèle Whisper ne sont pas des
/// choix de même rang — ce sont des détails internes à chaque famille — d'où
/// leur place **à l'intérieur** de la ligne qui les concerne, et non à côté.
///
/// ## Le commit transactionnel
///
/// Cliquer sur une ligne ne l'enregistre pas. C'était le cas, et ça cassait la
/// dictée en silence : cocher « CrisperWhisper » avant la fin du téléchargement
/// écrivait le choix dans les préférences, le contrôleur appelait un service
/// absent, et l'échec ne nommait pas sa cause.
///
/// Le clic ne fait donc que déplacer un **brouillon** (`draft`). L'écriture
/// dans `Preferences` n'a lieu que lorsque le moteur choisi est réellement
/// capable d'écrire — modèle installé, service debout. Tant que ce n'est pas le
/// cas, la dictée continue avec le moteur précédent, et le panneau ouvert
/// montre ce qu'il reste à faire.
struct FinalEngineCard: View, ValidatingComponent {
    /// Affiche le badge « conseillé pour vous », calculé à l'écran 2.
    var showsRecommendation = false
    var isOnboarding = false

    @State private var prefs = Preferences.shared
    @State private var safety = EngineSafetyManager.shared
    /// Ce que l'utilisateur vient de désigner, prêt ou non.
    @State private var draft: Preferences.FinalEngineChoice?
    @State private var commitTick = 0

    // MARK: - Validité

    /// Le brouillon n'entre pas en compte : c'est le moteur **enregistré** qui
    /// dictera si l'on ferme la fenêtre maintenant, et c'est donc lui qui
    /// décide si l'étape est franchissable.
    static func validate() -> ComponentValidationError? {
        switch Preferences.shared.finalEngine {
        case .apple: AppleEngineCard.validate()
        case .crisperWhisper: CrisperEngineCard.validate()
        }
    }

    /// Ce qui est affiché comme sélectionné : le brouillon s'il y en a un.
    private var shown: Preferences.FinalEngineChoice {
        draft ?? prefs.finalEngine
    }

    var body: some View {
        // Pas d'enveloppe : les deux cartes de choix **sont** le contenu de
        // l'écran, et les emboîter dans une troisième carte ajouterait un cadre
        // autour de deux cadres.
        VStack(alignment: .leading, spacing: 10) {
            choiceRow(.apple)
            choiceRow(.crisperWhisper)

            if safety.isFallingBack {
                Note("**\(prefs.engine.fullLabel) n'est pas disponible pour "
                     + "l'instant.** Sofler dicte avec "
                     + "\(safety.effectiveEngine.fullLabel) en attendant, et "
                     + "reviendra tout seul à votre choix dès qu'il sera "
                     + "opérationnel — votre réglage n'a pas été modifié.",
                     warning: true)
            }

            Note("Rien de tout ça n'est définitif : le moteur se change à tout "
                 + "moment, ici ou depuis les Réglages, et Sofler arrête le "
                 + "service dès que vous repassez à macOS.")
        }
        // Le brouillon devient le réglage dès que son moteur sait écrire. Vérifié
        // à chaque changement d'état plutôt qu'au clic : un téléchargement qui
        // se termine trente secondes plus tard doit commiter tout seul.
        .onChange(of: shown) { _, _ in commitIfReady() }
        .onChange(of: safety.isFallingBack) { _, _ in commitIfReady() }
        .task(id: shown) { commitIfReady() }
        // Et tant que le brouillon attend, on redemande.
        //
        // Les trois déclencheurs ci-dessus ne se produisent qu'au clic. Or ce
        // qu'on attend — un service qui finit de charger 3 Go — n'émet aucune
        // notification : ni fichier observé, ni objet observable. Le brouillon
        // ne s'enregistrait donc jamais tout seul. Conséquence visible : après
        // avoir démarré CrisperWhisper, changer d'onglet et revenir affichait
        // « macOS (Natif) » sélectionné, parce que la vue recréée repart du
        // réglage — resté sur macOS — et non du brouillon, perdu avec elle.
        .task(id: awaitingCommit ? commitTick : -1) {
            guard awaitingCommit else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            commitIfReady()
            commitTick &+= 1
        }
    }

    /// Un choix attend d'être enregistré, faute d'un moteur encore prêt.
    private var awaitingCommit: Bool {
        guard let draft else { return false }
        return draft != prefs.finalEngine
    }

    private func commitIfReady() {
        guard let draft, draft != prefs.finalEngine else { return }
        let target: EngineChoice = draft == .crisperWhisper
            ? .crisperWhisper : prefs.finalAppleTechnology
        if safety.commit(target, for: prefs.primaryLanguage) {
            self.draft = nil
        }
    }

    // MARK: - Les deux lignes

    @ViewBuilder
    private func choiceRow(_ choice: Preferences.FinalEngineChoice) -> some View {
        let selected = shown == choice
        let pending = draft == choice && prefs.finalEngine != choice

        ChoiceCard(title: title(for: choice),
                   subtitle: subtitle(for: choice),
                   selected: selected,
                   recommended: showsRecommendation && isRecommended(choice),
                   action: { draft = choice }) {
            if pending {
                Note("Ce choix sera enregistré dès que le moteur sera prêt. "
                     + "En attendant, Sofler dicte toujours avec "
                     + "\(prefs.engine.fullLabel).")
            }
            switch choice {
            case .apple:
                AppleEngineCard(isSubCard: true, target: .final)
            case .crisperWhisper:
                CrisperEngineCard(isSubCard: true, isOnboarding: isOnboarding)
            }
        }
    }

    /// Le titre et la description sont ceux du prototype.
    ///
    /// Ils nomment ce que **change** le choix plutôt que la technologie, et le
    /// badge « ★ Conseillé pour vous » est porté par la carte au lieu d'être
    /// collé au titre : il se lit alors comme une annotation, pas comme une
    /// partie du nom du moteur.
    private func title(for choice: Preferences.FinalEngineChoice) -> String {
        switch choice {
        case .apple: "macOS (Natif)"
        case .crisperWhisper: "CrisperWhisper 2.0 (IA Multilingue & Code)"
        }
    }

    private func subtitle(for choice: Preferences.FinalEngineChoice) -> String {
        switch choice {
        case .apple:
            "Fourni par macOS : aucune licence, aucun compte, rien à installer, "
                + "et rien ne réside en mémoire entre deux dictées. **0 Mo de "
                + "RAM résidente**."
        case .crisperWhisper:
            "Deuxième passe intelligente par IA locale : comprend le "
                + "**Franglais sans changer de langue**, respecte le "
                + "**vocabulaire technique et le code** (`useEffect`, "
                + "variables) et nettoie les hésitations (*euh*)."
        }
    }

    private func isRecommended(_ choice: Preferences.FinalEngineChoice) -> Bool {
        switch prefs.recommendation.choice {
        case .appleNative: choice == .apple
        case .crisperWhisper: choice == .crisperWhisper
        }
    }
}

#Preview("Moteur final") {
    ScrollView {
        FinalEngineCard(showsRecommendation: true)
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
