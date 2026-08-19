import AppKit
import SwiftUI

/// Le lexique : les mots que le moteur doit écrire tels qu'on les dit.
///
/// ## Ce que ça fait sous le capot
///
/// Les termes partent dans le prompt initial de CrisperWhisper, encadrés par
/// `<htx> … <ehtx>`, ce qui force le décodeur vers leur orthographe exacte.
/// Le moteur de macOS, lui, les ignore : son API accepte bien des chaînes de
/// contexte, mais elles ne changent pas sa sortie — c'est mesuré, et c'est
/// pourquoi la carte le dit au lieu de laisser croire à un réglage universel.
///
/// ## Pourquoi la liste doit rester courte
///
/// C'est contre-intuitif et c'est mesuré : à 36 termes, le modèle perd des
/// virgules — « Dans Next.js j'ai envie » au lieu de « Dans Next.js, j'ai
/// envie ». Un prompt plus long dilue le contexte audio. Il faut donc retirer
/// un terme pour en ajouter un, pas empiler — d'où l'avertissement au-delà de
/// vingt-cinq.
struct VocabularySettings: View {
    @State private var prefs = Preferences.shared
    @State private var entry = ""

    /// Le seuil au-delà duquel la liste commence à nuire.
    private static let crowded = 25

    var body: some View {
        explanation
        editor
        Note("💡 **Conseil :** Privilégiez les mots rares, les noms de projets "
             + "ou les termes bilingues que la dictée a tendance à écorcher.")
    }

    // MARK: - Ce que c'est

    private var explanation: some View {
        // Le prototype titre cette carte « Vocabulaire & Mots Métier ». Il le
        // peut : sa galerie de composants affiche `VocabularyView` seul. Dans
        // l'onglet, l'en-tête de page dit déjà « Lexique & Mots Métier » juste
        // au-dessus — le titre y répétait donc le titre. C'est la page qui
        // nomme, le composant qui explique.
        Card {
            Text("Guidez l'IA locale avec vos noms propres, acronymes ou "
                 + "jargon technique.")
                .font(.system(size: 11.5))
                .foregroundStyle(Style.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Note("Ces termes sont injectés comme repères dans l'IA "
                 + "**CrisperWhisper** pour garantir une orthographe exacte "
                 + "(ex : `Next.js`, `API REST`, `Stripe`, `URSSAF`).")
        }
    }

    // MARK: - La liste

    private var editor: some View {
        AccentCard {
            inputRow
            Text(.init("Appuyez sur **Entrée** ou **,** pour ajouter. Accepte "
                       + "les espaces, tirets et majuscules."))
                .font(.system(size: 10.5))
                .foregroundStyle(Style.textTertiary)

            Divider().opacity(0.25)

            if prefs.lexicon.isEmpty { empty } else { tags }

            Divider().opacity(0.25)
            footer
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Tapez un mot ou collez une liste (séparée par des "
                      + "virgules)...", text: $entry)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
                // Entrée valide. La virgule est traitée à l'ajout plutôt qu'à
                // la frappe : l'intercepter empêcherait de coller une liste
                // entière d'un coup, qui est justement le cas rapide.
                .onSubmit { add(entry) }

            Button("+ Ajouter") { add(entry) }
                .buttonStyle(CasprPrimaryButtonStyle())
                .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("Aucun terme personnalisé. Caspr transcrit en français "
                 + "courant sans conditionnement.")
                .font(.system(size: 12))
                .foregroundStyle(Style.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("+ Insérer des exemples (Développement Web)") {
                add(Preferences.starterLexicon.joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Style.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var tags: some View {
        ScrollView {
            FlowLayout(spacing: 6) {
                ForEach(prefs.lexicon, id: \.self) { term in
                    tag(term)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 160)
    }

    /// Un terme, rectangulaire et non en pilule.
    ///
    /// La pilule est réservée aux choix — pastilles de mode, langues actives.
    /// Un mot du lexique n'est pas un choix parmi d'autres : c'est une entrée
    /// dans une liste, et le rectangle le dit.
    private func tag(_ term: String) -> some View {
        HStack(spacing: 6) {
            Text(term)
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
            RemoveCross(label: "Supprimer \(term)") { remove(term) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Style.accent.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Style.accent.opacity(0.25), lineWidth: 1)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(prefs.lexicon.count > 1
                 ? "\(prefs.lexicon.count) termes enregistrés"
                 : "\(prefs.lexicon.count) terme enregistré")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCrowded ? Style.warning : Style.textSecondary)

            if isCrowded {
                Text("⚠️ Liste longue (gardez 5 à 25 termes pour une précision "
                     + "optimale)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Style.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !prefs.lexicon.isEmpty {
                DangerLink("Tout effacer") { prefs.lexicon = [] }
            }
        }
    }

    private var isCrowded: Bool { prefs.lexicon.count > Self.crowded }

    // MARK: - Saisie

    /// Ajoute un ou plusieurs termes.
    ///
    /// Découpe sur les virgules et les retours à la ligne : coller une liste
    /// entière est le geste rapide, et l'obliger à passer terme par terme
    /// serait punir le cas courant pour simplifier le code.
    private func add(_ raw: String) {
        let terms = raw
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return }

        var updated = prefs.lexicon
        for term in terms {
            // Dédoublonnage insensible à la casse : `React` et `react` sont le
            // même mot pour le décodeur, et deux entrées allongeraient le
            // prompt sans rien apporter.
            guard !updated.contains(where: {
                $0.compare(term, options: .caseInsensitive) == .orderedSame
            }) else { continue }
            updated.append(term)
        }
        prefs.lexicon = updated
        entry = ""
    }

    private func remove(_ term: String) {
        prefs.lexicon.removeAll { $0 == term }
    }
}

/// La croix de retrait d'un tag, qui rougit au survol.
struct RemoveCross: View {
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering ? Style.danger : Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

#Preview("Lexique") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            VocabularySettings()
        }
        .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
