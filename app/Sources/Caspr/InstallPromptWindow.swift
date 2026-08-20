import AppKit
import SwiftUI

/// « Caspr n'est pas encore installé », au premier double-clic depuis l'image.
///
/// ## Pourquoi une fenêtre plutôt qu'une alerte
///
/// C'était un `NSAlert`. Il disait la bonne chose, mais il la disait comme le
/// système : un panneau gris devant une application qu'on découvre. Or c'est le
/// tout premier écran de Caspr, avant même l'accueil — et il pose une question
/// dont la réponse conditionne tout le reste.
///
/// ## Rien d'autre ne s'ouvre tant qu'on n'a pas répondu
///
/// L'accueil attendait derrière. Configurer des langues et des autorisations
/// depuis une copie en lecture seule n'a pourtant aucun sens : les
/// autorisations sont attachées au chemin, et ce chemin va disparaître avec
/// l'image. Tout ce travail serait à refaire, sans que rien ne le dise. Les
/// deux réponses mènent donc à l'accueil, mais **après**.
@MainActor
final class InstallPromptWindowController {
    private var window: NSWindow?

    /// Ce qu'on propose, selon qu'une copie installée existe déjà.
    struct Choice {
        let alreadyInstalled: Bool
        let onPrimary: () -> Void
        let onContinue: () -> Void
    }

    func show(_ choice: Choice) {
        guard window == nil else { return }
        let window = NSWindow.caspr(title: "") {
            InstallPromptView(choice: choice, onFinish: { [weak self] in
                self?.close()
            })
        }
        window.setContentSize(NSSize(width: 380, height: 372))
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)
        self.window = window
        window.showCentered()
    }

    private func close() {
        window?.close()
        window = nil
    }
}

private struct InstallPromptView: View {
    let choice: InstallPromptWindowController.Choice
    let onFinish: () -> Void

    @State private var working = false

    var body: some View {
        VStack(spacing: 16) {
            // L'icône de l'application, celle-là même qu'on propose de ranger
            // dans Applications. Une icône plutôt qu'un triangle
            // d'avertissement : rien n'est cassé.
            //
            // C'était un `waveform` sur un carré dégradé, dessiné ici à la
            // main — le dernier symbole générique de l'application, et sur le
            // tout premier écran qu'on voit depuis l'image disque. La fenêtre
            // montrait donc autre chose que l'icône du Finder juste derrière
            // elle, au moment précis où l'on demande de reconnaître les deux.
            if let icon = BrandIcon("caspr-app-icon", height: 68) {
                icon.shadow(color: Color(hex: 0x33E1FF).opacity(0.35),
                            radius: 14, y: 6)
            }

            VStack(spacing: 10) {
                Text(choice.alreadyInstalled
                     ? "Ce n'est pas la copie installée"
                     : "Caspr n'est pas encore installé")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    Text(choice.alreadyInstalled
                         ? "Caspr est bien dans Applications, mais c'est la "
                           + "copie restée dans l'image disque qui vient de "
                           + "s'ouvrir — les deux icônes se ressemblent."
                         : "Il est ouvert depuis l'image disque, en lecture "
                           + "seule : les autorisations accordées seraient "
                           + "perdues et les mises à jour impossibles.")
                    Text(choice.alreadyInstalled
                         ? "Ouvrez plutôt celle d'Applications : c'est elle qui "
                           + "garde vos autorisations."
                         : "Caspr peut s'installer dans **Applications** et "
                           + "s'y rouvrir tout seul.")
                }
                .font(.system(size: 12))
                .foregroundStyle(Style.textSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(primaryLabel) {
                    working = true
                    choice.onPrimary()
                }
                .buttonStyle(CasprPrimaryButtonStyle())
                .disabled(working)
                .frame(maxWidth: .infinity)

                // Le refus reste possible, et il est nommé sans reproche : on
                // peut vouloir essayer l'application avant de la ranger.
                Button("Continuer quand même") {
                    choice.onContinue()
                    onFinish()
                }
                .buttonStyle(CasprSecondaryButtonStyle())
                .disabled(working)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowBackground().ignoresSafeArea())
        .tint(Style.accent)
    }

    private var primaryLabel: String {
        if working { return "Installation en cours…" }
        return choice.alreadyInstalled ? "Ouvrir la copie installée"
                                       : "Installer et ouvrir"
    }
}
