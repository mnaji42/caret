import SwiftUI
import CasprCore

/// Trois questions sur l'usage, et le moteur qu'elles conseillent.
///
/// ## Ce que fait cette carte, et ce qu'elle ne fait pas
///
/// Elle **conseille**. Elle ne configure rien : le moteur se choisit à l'écran
/// suivant, et la recommandation y est rappelée sans jamais y être appliquée
/// d'office. La distinction compte — décider à la place de quelqu'un le
/// téléchargement de 1,6 Go sur la foi de trois cases cochées serait exactement
/// ce que ce projet reproche aux applications qui installent d'abord et
/// expliquent ensuite.
///
/// Aucune des trois cases n'est obligatoire : ne rien cocher est une réponse,
/// et elle mène au conseil par défaut. La carte est donc toujours valide.
///
/// Les règles de décision vivent dans `EngineRecommendation`, côté `CasprCore`,
/// et sont testées : quatre règles conditionnelles qui décident d'un
/// téléchargement de 1,6 Go méritent mieux qu'une relecture.
struct UsageHabitsCard: View, ValidatingComponent {
    @State private var prefs = Preferences.shared

    /// Toujours valide : ce questionnaire est facultatif, et le griser
    /// « Continuer » dessus punirait quelqu'un qui n'a rien à déclarer.
    static func validate() -> ComponentValidationError? { nil }

    private static let questions: [(UsageHabits.Habit, String)] = [
        (.mixesLanguages,
         "Je mélange souvent les langues (Franglais, expressions bilingues au "
            + "quotidien)."),
        (.usesJargon,
         "J'utilise du vocabulaire technique, du code (`useEffect`, variables) "
            + "ou du jargon métier."),
        (.wantsLightweight,
         "Je cherche la simplicité et la légèreté (dictée rapide, 0 Mo de RAM, "
            + "pas d'IA lourde)."),
    ]

    var body: some View {
        Card {
            ForEach(Self.questions, id: \.0) { habit, question in
                choice(habit, question)
            }
            recommendation
        }
    }

    private func choice(_ habit: UsageHabits.Habit, _ question: String) -> some View {
        let checked = prefs.habits.has(habit)

        return HStack(alignment: .top, spacing: 10) {
            CheckBox(checked: checked)
            Text(.init(question))
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(checked ? Style.textPrimary : Style.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(checked ? Color.white.opacity(0.04) : Color.clear))
        .contentShape(Rectangle())
        // La règle d'exclusion vit dans le modèle, pas ici : « légèreté » et
        // les deux autres s'annulent, et une vue qui l'appliquerait de son côté
        // serait une seconde version de la règle.
        .onTapGesture { prefs.habits.toggle(habit) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? [.isSelected, .isButton] : .isButton)
    }

    private var recommendation: some View {
        let advice = prefs.recommendation
        let engine = advice.choice == .crisperWhisper
            ? "CrisperWhisper Turbo" : "macOS Natif (0 Mo)"

        return HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(Style.accent)
                .frame(width: 3)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(.init("💡 **Recommandation personnalisée :** \(engine) — "
                           + "\(advice.reason)."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Style.accent)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Style.accent.opacity(0.07)))
        // Le conseil se recalcule à chaque case cochée et à chaque changement
        // de langue : l'animer évite qu'il paraisse sauter d'une valeur à
        // l'autre sans lien avec le geste qu'on vient de faire.
        .animation(.easeOut(duration: 0.18), value: advice)
    }
}

#Preview("Habitudes") {
    ScrollView {
        UsageHabitsCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: 400)
    .background(Color(hex: 0x141821))
}
