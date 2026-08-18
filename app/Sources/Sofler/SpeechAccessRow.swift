import SwiftUI

/// L'autorisation de reconnaissance vocale d'Apple, demandée là où elle sert.
///
/// ## Pourquoi elle ne vit pas avec les deux autres
///
/// Le micro et l'accessibilité sont inconditionnels : sans eux, Sofler ne peut
/// ni entendre ni écrire, quel que soit le moteur. Ils appartiennent donc au
/// déclencheur (`TriggerCard`).
///
/// Celle-ci non. Elle ne concerne que `SFSpeechRecognizer`, c'est-à-dire la
/// version **Dictée** du moteur de macOS. Quelqu'un qui dicte avec
/// CrisperWhisper, ou avec Apple Intelligence, n'en a aucun usage — et la lui
/// réclamer serait exactement ce qu'on reproche aux applications qui demandent
/// plus de droits qu'elles n'en emploient.
///
/// Elle apparaît donc **à côté du moteur qui la consomme**, et seulement quand
/// ce moteur est réellement en jeu. `PermissionsMonitor.requiresSpeech` en juge
/// sur trois usages possibles : la Dictée écrit, elle tourne pour la collecte,
/// ou c'est elle qui assure l'aperçu en direct.
struct SpeechAccessRow: View {
    /// Explique à quoi sert le droit. Vrai à l'accueil ; faux dans les
    /// Réglages, où l'on vient réparer, pas lire un exposé.
    var explains = false

    @State private var monitor = PermissionsMonitor.shared

    var body: some View {
        Group {
            if monitor.speechGranted {
                GrantedLine("Reconnaissance Vocale Apple accordée")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .strokeBorder(Style.textTertiary, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconnaissance Vocale Apple (Requis)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Exigée par macOS pour permettre à Apple "
                                 + "Dictée de traiter le signal vocal.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Style.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("Accorder") {
                            Task {
                                _ = await LegacySpeechEngine.requestAuthorisation()
                                monitor.refresh()
                            }
                        }
                        .buttonStyle(SoflerPrimaryButtonStyle())
                    }

                    if explains {
                        Note("Le moteur de la **Dictée** de macOS passe par ce "
                             + "droit — macOS le compte séparément du micro. "
                             + "**Rien ne part chez Apple** : Sofler force la "
                             + "reconnaissance hors ligne et refuse de "
                             + "transcrire si la machine ne sait pas le faire.")
                    }

                }
            }
        }
        .onAppear { monitor.observe() }
        .onDisappear { monitor.release() }
    }
}

#Preview("Reconnaissance vocale") {
    VStack(alignment: .leading, spacing: 16) {
        Card {
            SpeechAccessRow(explains: true)
        }
    }
    .padding(Style.windowPadding)
    .frame(width: Style.windowWidth)
    .background(Color(hex: 0x141821))
}
