import SwiftUI

/// Le champ où l'on essaie la dictée pour la première fois.
///
/// ## Il ne simule rien, et c'est tout le sujet
///
/// Le prototype React propose un bouton `[ 🎙️ Simuler Touche Option ]` qui
/// écrit une phrase toute faite, lettre à lettre. C'est une maquette, et à ce
/// titre c'est légitime — il n'y a pas de micro derrière une page web.
///
/// En natif, ce bouton serait un mensonge, et un mensonge coûteux. Ce qu'on
/// cherche à prouver ici, c'est précisément que **le vrai déclencheur, le vrai
/// micro et le vrai moteur écrivent dans un vrai champ de saisie** — par
/// exactement le même chemin que dans n'importe quelle autre application.
/// Une animation qui imite le résultat ne prouve rien, et si la dictée est
/// cassée elle le cache.
///
/// Le champ ci-dessous n'est donc jamais rempli par le code. Le texte y arrive
/// par `TextInjector`, comme partout ailleurs. S'il n'arrive pas, c'est
/// l'information la plus utile que l'accueil puisse donner.
struct TrialSandbox: View {
    /// Grisé tant que le micro ou l'accessibilité manque : sans eux, appuyer
    /// sur la touche ne produirait rien, et l'essai raté se lirait comme
    /// « Sofler ne marche pas » au lieu de « il manque un droit ».
    var isLocked: Bool
    /// Le déclencheur à annoncer — « ⌥ droite », « ⌃⌥⌘D ».
    var triggerLabel: String

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ZONE D'ESSAI")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.9)
                    .foregroundStyle(.tertiary)
                Spacer()
                if isLocked {
                    Label("Accordez les accès ci-dessus", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Style.warning)
                } else {
                    Label("Prêt pour l'essai", systemImage: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Style.accent)
                }
            }

            Text(.init("Cliquez dans le cadre, tapez **\(triggerLabel)**, dites "
                       + "une phrase, puis tapez à nouveau."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 84)
                .background(
                    RoundedRectangle(cornerRadius: Style.fieldRadius, style: .continuous)
                        .fill(Style.innerBoxFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Style.fieldRadius,
                                             style: .continuous)
                                .strokeBorder(Style.cardStroke, lineWidth: 1)))

            if !text.isEmpty {
                Label("C'est bien votre voix qui a écrit ça — par le même "
                      + "chemin que dans vos applications.",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Style.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(isLocked ? 0.38 : 1)
        .disabled(isLocked)
        .animation(.easeOut(duration: 0.25), value: isLocked)
    }
}

#Preview("Essai — déverrouillé") {
    TrialSandbox(isLocked: false, triggerLabel: "⌥ droite")
        .padding(Style.windowPadding)
        .frame(width: Style.windowWidth)
        .background(Color(hex: 0x141821))
}

#Preview("Essai — verrouillé") {
    TrialSandbox(isLocked: true, triggerLabel: "⌥ droite")
        .padding(Style.windowPadding)
        .frame(width: Style.windowWidth)
        .background(Color(hex: 0x141821))
}
