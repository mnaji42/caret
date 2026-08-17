import AppKit
import SwiftUI

/// Comment on lance une dictée, et les deux droits que ça demande.
///
/// La même vue dans l'accueil et dans les Réglages — c'est tout l'intérêt du
/// composant. Elle n'a qu'un paramètre, `showTrialSandbox`, parce que la zone
/// d'essai n'a de sens qu'une fois : à l'accueil, quand on n'a encore jamais vu
/// Sofler écrire.
///
/// ## Ce qui se replie, et ce qui ne doit jamais se replier
///
/// Le prototype réduit chaque autorisation accordée à une ligne `✓`, et c'est
/// juste : une fois le droit obtenu, l'encart explicatif n'est plus qu'un pavé
/// qui pousse le reste vers le bas.
///
/// Mais il replie **tous** les cas de la même façon, et deux d'entre eux ne
/// sont pas des « pas encore accordé » :
///
/// - **Micro refusé.** macOS ne représente plus jamais son dialogue une fois le
///   refus enregistré. Un bouton « Accorder » qui n'ouvre rien laisse cliquer
///   dans le vide ; il faut envoyer aux Réglages Système.
/// - **Accessibilité accordée à une autre signature.** Sofler apparaît coché
///   dans les Réglages Système et l'application ne le voit pas — parce que
///   macOS attache le droit à une signature, pas à un chemin. Décocher puis
///   recocher n'y change rien. C'est une heure perdue par qui ne le sait pas,
///   et ça se produit à **chaque mise à jour** d'une application signée ad hoc.
///
/// Ces deux cas gardent donc leur explication complète et leur échappatoire.
/// Le repli en `✓` vaut pour ce qui est acquis, pas pour ce qui est coincé.
struct TriggerCard: View, ValidatingComponent {
    /// Affiche la zone d'essai. Vrai dans l'accueil, faux dans les Réglages.
    var showTrialSandbox = true

    @State private var prefs = Preferences.shared
    @State private var monitor = PermissionsMonitor.shared

    // MARK: - Validité

    /// Micro **et** accessibilité : sans les deux, la dictée ne peut ni
    /// entendre ni écrire.
    ///
    /// La reconnaissance vocale n'en fait pas partie — elle dépend du moteur
    /// retenu et appartient à `AppleEngineCard`. L'exiger ici bloquerait
    /// quelqu'un qui dictera avec CrisperWhisper sur un droit dont il n'a pas
    /// l'usage.
    static func validate() -> ComponentValidationError? {
        let monitor = PermissionsMonitor.shared
        if monitor.micAccess != .granted { return .microphonePermissionRequired }
        if !monitor.accessibilityGranted { return .accessibilityPermissionRequired }
        return nil
    }

    private var permissionsComplete: Bool { Self.isValid }

    var body: some View {
        Card(title: "Déclencheur") {
            Row(label: "Dicter avec") {
                PillPicker(options: [(Preferences.TriggerKind.option, "Touche Option"),
                                     (Preferences.TriggerKind.shortcut, "Raccourci clavier")],
                           selection: $prefs.triggerKind)
            }

            if prefs.triggerKind == .option {
                optionMode
            } else {
                shortcutMode
            }

            permissions

            if showTrialSandbox {
                Divider().opacity(0.25)
                TrialSandbox(isLocked: !permissionsComplete,
                             triggerLabel: triggerLabel)
            }
        }
        // L'horloge des autorisations ne tourne que pendant qu'une vue la
        // regarde : Sofler vit en permanence en arrière-plan, et un timer à
        // 1 Hz qui ne s'arrête jamais est une dépense sans contrepartie.
        .onAppear { monitor.observe() }
        .onDisappear { monitor.release() }
    }

    /// Le déclencheur réellement actif — un seul l'est à la fois.
    private var triggerLabel: String {
        prefs.triggerKind == .option
            ? prefs.triggerSide.label
            : prefs.dictateShortcut.label
    }

    // MARK: - Les deux modes

    @ViewBuilder
    private var optionMode: some View {
        Row(label: "Laquelle") {
            PillPicker(options: ModifierKeyMonitor.Side.allCases.map { ($0, $0.label) },
                       selection: $prefs.triggerSide)
        }
        VStack(alignment: .leading, spacing: 4) {
            gesture("1er appui", "ouvre la barre flottante et commence à écouter")
            gesture("2e appui", "termine l'écoute et insère le texte")
            gesture("Échap ⎋", "annule la dictée sans rien écrire")
        }
        Note("La touche reste utilisable normalement : rien ne se déclenche si "
             + "une autre touche est pressée entre-temps.\n\n"
             + "**Maintenir Option une seconde** ouvre les Réglages.")
    }

    private func gesture(_ key: String, _ effect: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.tertiary)
            Text(.init("**\(key)** : \(effect)"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var shortcutMode: some View {
        Row(label: "Raccourci") {
            ShortcutRecorder(shortcut: $prefs.dictateShortcut) { _ in }
                .frame(width: 150, height: 26)
        }
        Note("Cliquez puis tapez la combinaison voulue. macOS refuse les "
             + "raccourcis sans Contrôle ni Commande.")
        Note("La touche Option ne déclenche plus rien, et ne maintient plus "
             + "l'ouverture des Réglages — ils restent accessibles depuis le "
             + "menu. En contrepartie, un raccourci fonctionne **sans "
             + "l'autorisation d'Accessibilité** pour être capté ; elle reste "
             + "nécessaire pour écrire le texte à votre curseur.")
    }

    // MARK: - Autorisations

    /// L'encart d'action pour ce qui manque, les lignes `✓` pour ce qui est
    /// acquis. Rien du tout quand les deux sont accordés et qu'il n'y a donc
    /// plus de décision à prendre.
    @ViewBuilder
    private var permissions: some View {
        if !permissionsComplete {
            VStack(alignment: .leading, spacing: 10) {
                if monitor.micAccess != .granted { microphone }
                if monitor.micAccess != .granted, !monitor.accessibilityGranted {
                    Divider().opacity(0.25)
                }
                if !monitor.accessibilityGranted { accessibility }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .fill(Style.innerBoxFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Style.innerRadius,
                                         style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)))
        }

        VStack(alignment: .leading, spacing: 3) {
            if monitor.micAccess == .granted {
                GrantedLine("Accès Microphone accordé")
            }
            if monitor.accessibilityGranted {
                GrantedLine("Accès Accessibilité accordé")
            }
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 8) {
            PermissionNeed(
                title: "Accès Microphone",
                detail: "Requis pour écouter votre voix pendant la dictée. "
                    + "Sofler n'ouvre le micro qu'entre les deux appuis.",
                // Refusé : le bouton d'action serait un bouton qui ne fait
                // rien, puisque macOS ne représente plus le dialogue.
                action: monitor.micAccess == .undetermined ? "Accorder" : nil) {
                Task { await monitor.requestMicrophone() }
            }

            if monitor.micAccess == .denied {
                Note("macOS ne représente plus son dialogue une fois le refus "
                     + "enregistré : il faut réactiver Sofler à la main.",
                     warning: true)
                ButtonRow {
                    Button("Ouvrir Réglages Système › Micro") {
                        Permissions.openMicrophoneSettings()
                    }
                }
            }
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 8) {
            PermissionNeed(
                title: "Accès Accessibilité",
                detail: "Requis pour écrire le texte dans l'application que "
                    + "vous avez devant vous, et pour voir la touche Option "
                    + "pressée seule.",
                action: "Accorder") {
                NSApp.activate(ignoringOtherApps: true)
                Permissions.requestAccessibility()
            }
            Note("macOS ne laisse aucune application s'accorder ce droit "
                 + "elle-même. Sofler reste ouvert pendant ce temps et se met "
                 + "à jour tout seul dès que c'est fait.")
            StuckAccessibilityNote()
        }
    }
}

// MARK: - Pièces

/// Une autorisation manquante : ce que c'est, à quoi elle sert, et le bouton.
private struct PermissionNeed: View {
    let title: String
    let detail: String
    /// `nil` retire le bouton : il y a des impasses où il n'ouvrirait rien, et
    /// un bouton qui ne fait rien est pire que pas de bouton.
    let action: String?
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .strokeBorder(Style.warning, lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action, action: perform)
                    .buttonStyle(.borderedProminent)
                    .tint(Style.accent)
                    .controlSize(.small)
            }
        }
    }
}

/// Une autorisation acquise, en une ligne qui ne prend plus de place.
struct GrantedLine: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Style.accent).frame(width: 15, height: 15)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Style.onAccent)
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Style.accent)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), accordé")
    }
}

/// Le piège de l'autorisation attachée à une signature.
///
/// Sofler apparaît coché dans les Réglages Système, et `AXIsProcessTrusted()`
/// répond faux. Ce n'est ni un bug ni un oubli : macOS indexe le droit
/// d'accessibilité sur la **signature** du binaire. Une application signée ad
/// hoc change de signature à chaque compilation, donc **à chaque mise à jour**
/// — et l'entrée cochée pilote un enregistrement périmé que décocher/recocher
/// ne répare pas.
///
/// Cette vue est séparée parce que le cas se produit aussi hors de l'accueil,
/// et qu'elle a coûté assez de temps pour mériter d'être nommée à l'écran
/// plutôt que redécouverte.
struct StuckAccessibilityNote: View {
    /// Une réinitialisation par ouverture de fenêtre : recliquer sans être
    /// passé par les Réglages Système effacerait ce qu'on vient d'accorder.
    @State private var justReset = false

    var body: some View {
        Divider().opacity(0.25)
        Note("**Sofler apparaît déjà coché dans les Réglages Système ?** "
             + "L'autorisation a été accordée à une version signée autrement, "
             + "et macOS ne la reconnaît plus. Décocher puis recocher n'y fera "
             + "rien : la case pilote une entrée périmée.")
        ButtonRow {
            Button(justReset ? "Autorisation effacée — recochez la case"
                             : "Réinitialiser l'autorisation") {
                Permissions.resetAccessibility()
                PermissionsMonitor.shared.refresh()
                justReset = true
            }
            .disabled(justReset)
            Button("Ouvrir les Réglages Système") {
                Permissions.openAccessibilitySettings()
            }
        }
    }
}

#Preview("Déclencheur") {
    ScrollView {
        TriggerCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
