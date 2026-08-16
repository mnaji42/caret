import AppKit
import SwiftUI

/// L'état des autorisations, relu périodiquement.
///
/// Elles s'accordent dans une *autre* application — le dialogue système pour
/// le micro, les Réglages Système pour l'accessibilité — et rien n'en revient :
/// aucune notification, aucun rappel. Sans relecture, l'interface resterait au
/// rouge alors que l'utilisateur vient d'accorder le droit sous nos yeux, et
/// il conclurait que ça n'a pas marché.
///
/// Une seule horloge pour toutes les vues, et seulement pendant qu'au moins
/// une est affichée : Sofler tourne en permanence, un timer à 1 Hz qui ne
/// s'arrête jamais est une dépense sans contrepartie le reste du temps.
@MainActor
@Observable
final class PermissionsMonitor {
    static let shared = PermissionsMonitor()

    private(set) var micAccess = AudioRecorder.microphoneAccess
    private(set) var accessibilityGranted = AXIsProcessTrusted()

    /// Les deux autorisations sans lesquelles la dictée ne peut rien faire.
    /// La version de macOS n'en fait pas partie : elle ne se corrige pas dans
    /// l'instant, et bloquer dessus enfermerait l'utilisateur.
    private(set) var speechGranted = LegacySpeechEngine.isAuthorised

    /// Le droit de reconnaissance vocale n'entre dans le compte que s'il sert :
    /// l'exiger sur une machine qui dictera avec CrisperWhisper bloquerait
    /// l'accueil sur une autorisation inutile.
    /// Combien d'autorisations cette machine réclame réellement.
    var neededCount: Int { requiresSpeech ? 3 : 2 }

    /// Le droit de reconnaissance vocale est-il en jeu ici ?
    var requiresSpeech: Bool {
        if Preferences.shared.engine == .appleLegacy { return true }
        let language = Preferences.shared.language
        return EngineChoice.appleLegacy.isAvailable(for: language)
            && !EngineChoice.apple.isAvailable(for: language)
    }

    var allGranted: Bool {
        guard micAccess == .granted, accessibilityGranted else { return false }
        return requiresSpeech ? speechGranted : true
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers = 0

    func observe() {
        observers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func release() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let wasMic = micAccess
        micAccess = AudioRecorder.microphoneAccess

        let granted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = granted
        let wasSpeech = speechGranted
        speechGranted = LegacySpeechEngine.isAuthorised

        // Accorder une autorisation fait passer les Réglages Système devant,
        // et l'accueil disparaît derrière — on se retrouve à le chercher dans
        // Mission Control alors qu'on venait de faire exactement ce qu'il
        // demandait. macOS ne le remonte pas tout seul.
        if (granted && !wasGranted) || (micAccess == .granted && wasMic != .granted)
            || (speechGranted && !wasSpeech) {
            returnToForeground()
        }
        // C'est ici qu'on apprend le plus tôt que le droit vient d'arriver —
        // pendant que l'accueil est ouvert et que l'utilisateur regarde. Le
        // déclencheur clavier en dépend et ne se répare pas seul.
        if granted, !wasGranted {
            NotificationCenter.default.post(name: .soflerAccessibilityGranted,
                                            object: nil)
        }
    }

    /// Ramène Sofler devant, au moment où l'on sait que le droit vient
    /// d'arriver.
    ///
    /// Seulement si une de ses fenêtres est visible : accorder l'accessibilité
    /// six mois plus tard, depuis les Réglages Système, ne doit pas faire
    /// surgir une application d'arrière-plan par-dessus le travail en cours.
    private func returnToForeground() {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeKey
        }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Déclenche le dialogue système du micro, si macOS accepte encore de
    /// l'afficher.
    func requestMicrophone() async {
        // Le dialogue s'ouvre derrière les autres fenêtres tant que l'app est
        // en arrière-plan — l'état permanent d'une app de barre de menus.
        NSApp.activate(ignoringOtherApps: true)
        _ = await AudioRecorder.requestPermission()
        refresh()
    }
}

// MARK: - Pièces d'interface

/// Une ligne « pastille + libellé + état », pour ce que l'application subit au
/// lieu de le décider : version du système, autorisations.
struct StatusRow: View {
    let ok: Bool
    let label: String
    let detail: String
    /// Un manque qui n'empêche pas d'avancer se signale en orange, pas en
    /// rouge : c'est un avertissement, pas une panne.
    var warningOnly = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Style.accent : Style.collecting)
                .font(.system(size: 15))
            Text(label).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// Micro et accessibilité : leur état, et de quoi le corriger.
///
/// La même vue dans l'accueil et dans les Réglages. Deux copies finiraient par
/// se contredire, et surtout : quelqu'un qui a cliqué « Continuer » trop vite
/// le premier jour doit pouvoir retrouver ces boutons plus tard, sans deviner
/// qu'ils n'existent que dans un écran d'accueil qu'il a fermé.
struct PermissionsChecklist: View {
    /// L'accueil explique à quoi servent ces droits ; les Réglages, non. On y
    /// vient pour réparer quelque chose, pas pour lire un exposé.
    var explains = false

    @State private var monitor = PermissionsMonitor.shared
    /// Une réinitialisation par ouverture de fenêtre : recliquer sans être
    /// passé par les Réglages Système ne ferait qu'effacer ce qu'on vient
    /// d'accorder.
    @State private var justReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micSection
            Divider().opacity(0.25)
            accessibilitySection
            // Ce droit n'existe que pour le moteur de la Dictée : le réclamer
            // à quelqu'un qui dictera avec CrisperWhisper serait une
            // autorisation demandée pour rien, et c'est exactement ce qu'on
            // reproche aux applications qui en demandent trop.
            if monitor.requiresSpeech {
                Divider().opacity(0.25)
                speechSection
            }
        }
        .onAppear { monitor.observe() }
        .onDisappear { monitor.release() }
    }

    // MARK: Reconnaissance vocale

    private var speechSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(ok: monitor.speechGranted, label: "Reconnaissance vocale",
                      detail: monitor.speechGranted ? "accordée" : "pas encore accordée")

            if explains {
                Note("Le moteur de la Dictée de macOS passe par ce droit — "
                     + "macOS le compte séparément du micro. **Rien ne part "
                     + "chez Apple** : Sofler force la reconnaissance hors "
                     + "ligne, et refuse de transcrire si la machine ne sait "
                     + "pas le faire.")
            }

            if !monitor.speechGranted {
                Button("Autoriser la reconnaissance vocale") {
                    Task {
                        _ = await LegacySpeechEngine.requestAuthorisation()
                        monitor.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
            }
        }
    }

    // MARK: Micro

    private var micSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(ok: monitor.micAccess == .granted, label: "Micro",
                      detail: micDetail)

            if explains {
                Note("Sofler n'ouvre le micro que pendant que vous dictez, "
                     + "entre les deux appuis sur la touche. Le reste du "
                     + "temps il est fermé.")
            }

            switch monitor.micAccess {
            case .granted:
                EmptyView()
            case .undetermined:
                Button("Autoriser le micro") {
                    Task { await monitor.requestMicrophone() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
            case .denied:
                Note("macOS ne représente plus le dialogue une fois le refus "
                     + "enregistré : il faut réactiver Sofler à la main.",
                     warning: true)
                Button("Ouvrir Réglages Système › Micro") {
                    Permissions.openMicrophoneSettings()
                }
            }
        }
    }

    private var micDetail: String {
        switch monitor.micAccess {
        case .granted: "accordé"
        case .undetermined: "pas encore demandé"
        case .denied: "refusé"
        }
    }

    // MARK: Accessibilité

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(ok: monitor.accessibilityGranted, label: "Accessibilité",
                      detail: monitor.accessibilityGranted ? "accordée" : "pas encore accordée")

            if explains {
                Note("C'est l'autorisation la plus intrusive que macOS sache "
                     + "accorder, et elle mérite d'être justifiée plutôt que "
                     + "réclamée. Elle sert à **écrire le texte** dans "
                     + "l'application que vous avez devant vous — macOS "
                     + "n'offre aucune autre voie — et à **voir la touche "
                     + "Option** pressée seule, qui déclenche la dictée.")
                Note("Sofler ne lit pas ce que vous tapez : le tap clavier ne "
                     + "s'intéresse qu'aux modificateurs et laisse passer les "
                     + "événements intacts. Le code est ouvert, cette "
                     + "affirmation est vérifiable.")
            }

            if !monitor.accessibilityGranted {
                HStack(spacing: 8) {
                    // D'abord le dialogue de macOS : c'est une demande, pas
                    // une éjection vers une autre application.
                    Button("Autoriser l'accessibilité") {
                        NSApp.activate(ignoringOtherApps: true)
                        Permissions.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Style.accent)

                    // Le dialogue n'apparaît qu'une fois par application :
                    // au-delà, ce lien est le seul chemin restant.
                    Button("Ouvrir les Réglages Système") {
                        Permissions.openAccessibilitySettings()
                    }
                }
                Note("macOS ne laisse aucune application s'accorder ce droit "
                     + "elle-même : la case se coche dans les Réglages "
                     + "Système. Sofler reste ouvert pendant ce temps, et "
                     + "l'état ci-dessus se met à jour tout seul dès que "
                     + "c'est fait.")

                Divider().opacity(0.25)

                // La panne qui fait perdre une heure : la case est cochée, et
                // l'application ne la voit pas. On la nomme, parce que
                // personne ne devine tout seul que macOS attache
                // l'autorisation à une signature et non à une application.
                Note("**Sofler apparaît déjà coché dans les Réglages Système ?** "
                     + "Alors l'autorisation a été accordée à une version "
                     + "signée autrement, et macOS ne la reconnaît plus. "
                     + "Décocher puis recocher n'y fera rien : la case pilote "
                     + "une entrée périmée.")
                Button(justReset ? "Autorisation effacée — recochez la case"
                                 : "Réinitialiser l'autorisation") {
                    Permissions.resetAccessibility()
                    monitor.refresh()
                    justReset = true
                }
                .disabled(justReset)
                Note("Efface l'entrée et repart de zéro. Il faudra ensuite "
                     + "recocher Sofler dans les Réglages Système.")
            }
        }
    }
}
