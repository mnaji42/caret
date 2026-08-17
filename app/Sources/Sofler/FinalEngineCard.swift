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
        Card(title: "Moteur de transcription") {
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
    }

    private func commitIfReady() {
        guard let draft, draft != prefs.finalEngine else { return }
        let target: EngineChoice = draft == .crisperWhisper
            ? .crisperWhisper : prefs.appleTechnology
        if safety.commit(target, for: prefs.primaryLanguage) {
            self.draft = nil
        }
    }

    // MARK: - Les deux lignes

    @ViewBuilder
    private func choiceRow(_ choice: Preferences.FinalEngineChoice) -> some View {
        let selected = shown == choice
        let pending = draft == choice && prefs.finalEngine != choice

        ChoiceRow(title: title(for: choice),
                  subtitle: subtitle(for: choice),
                  selected: selected,
                  // Dévoilement progressif : les détails techniques n'ont pas à
                  // occuper la fenêtre tant qu'on n'a pas retenu le moteur.
                  hasDetail: selected,
                  action: { draft = choice }) {
            if pending {
                Note("Ce choix sera enregistré dès que le moteur sera prêt. "
                     + "En attendant, Sofler dicte toujours avec "
                     + "\(prefs.engine.fullLabel).")
            }
            switch choice {
            case .apple:
                AppleEngineCard(isSubCard: true)
            case .crisperWhisper:
                CrisperEngineCard(isSubCard: true, isOnboarding: isOnboarding)
            }
        }
    }

    private func title(for choice: Preferences.FinalEngineChoice) -> String {
        let base = switch choice {
        case .apple: EngineChoice.apple.label
        case .crisperWhisper: EngineChoice.crisperWhisper.label
        }
        guard showsRecommendation, isRecommended(choice) else { return base }
        return "\(base)  ★ conseillé pour vous"
    }

    private func subtitle(for choice: Preferences.FinalEngineChoice) -> String {
        switch choice {
        case .apple: EngineChoice.apple.explanation
        case .crisperWhisper: EngineChoice.crisperWhisper.explanation
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
