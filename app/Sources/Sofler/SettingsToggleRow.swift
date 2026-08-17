import SwiftUI

/// La bascule d'une fonctionnalité entière : titre, explication, interrupteur.
///
/// Le composant universel de toutes les bascules de Sofler — aperçu en direct,
/// sons, historique, collecte, démarrage, mises à jour automatiques. Il existe
/// parce que ces réglages étaient écrits à la main à chaque endroit, avec des
/// tailles de police et des espacements qui avaient dérivé : le même
/// interrupteur paraissait plus important dans un onglet que dans un autre,
/// sans que rien ne le justifie.
///
/// ## Interrupteur, et pas case à cocher
///
/// La distinction n'est pas décorative, et `FeatureSwitch` la portait déjà :
/// une case à cocher se lit « ce détail est retenu », un interrupteur « cette
/// fonctionnalité est en marche ». Les confondre fait activer une collecte de
/// données en croyant cocher une préférence. Les sous-options gardent donc
/// `OptionCheck`.
struct SettingsToggleRow: View {
    let title: String
    /// La conséquence du réglage, en une phrase. Sous le titre, en petit.
    var description: String?
    /// Ce qu'il faut savoir en plus — vie privée, coût en mémoire, piège
    /// connu. Sous l'interrupteur, sur toute la largeur.
    var note: String?
    /// Rendu en ambre : sert aux notes qui avertissent, pas à celles qui
    /// expliquent.
    var noteIsWarning = false
    @Binding var isOn: Bool
    var disabled = false
    /// Enveloppé dans une `Card`, ou posé nu dans une carte existante.
    var isCard = true

    var body: some View {
        if isCard {
            Card(title: title) { content }
        } else {
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                // Dans une carte, le titre est déjà l'en-tête : le répéter
                // ici ferait lire deux fois la même chose à dix pixels
                // d'écart. Hors carte, c'est lui qui nomme le réglage.
                if !isCard {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                if let description {
                    Text(.init(description))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .toggleStyle(SoflerSwitch())
                .labelsHidden()
                .disabled(disabled)
                .opacity(disabled ? 0.45 : 1)
        }
        // Le titre part quand même à VoiceOver quand la carte le porte :
        // l'interrupteur seul s'annoncerait « activé », sans dire de quoi.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)

        if let note {
            Note(note, warning: noteIsWarning)
        }
    }
}

#Preview("Bascules") {
    @Previewable @State var live = true
    @Previewable @State var sons = false
    @Previewable @State var verrou = true

    return VStack(alignment: .leading, spacing: 16) {
        SettingsToggleRow(
            title: "Afficher l'aperçu du texte en direct",
            description: "Montre sous la barre ce que macOS entend pendant que vous parlez.",
            note: "Indicatif : le moteur d'aperçu n'a pas votre vocabulaire "
                + "technique, donc le texte inséré peut différer.",
            isOn: $live)

        SettingsToggleRow(title: "Sons de début et de fin",
                          description: "Deux clics discrets, au démarrage et à l'arrêt.",
                          isOn: $sons, isCard: false)

        SettingsToggleRow(title: "Archiver mes dictées",
                          description: "Collecte locale, pour comparer les moteurs.",
                          note: "Réglage verrouillé pendant une dictée en cours.",
                          noteIsWarning: true,
                          isOn: $verrou, disabled: true)
    }
    .padding(Style.windowPadding)
    .frame(width: Style.windowWidth)
    .background(Color(hex: 0x141821))
}
