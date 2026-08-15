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
    var allGranted: Bool { micAccess == .granted && accessibilityGranted }

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
        micAccess = AudioRecorder.microphoneAccess

        let granted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = granted
        // C'est ici qu'on apprend le plus tôt que le droit vient d'arriver —
        // pendant que l'accueil est ouvert et que l'utilisateur regarde. Le
        // déclencheur clavier en dépend et ne se répare pas seul.
        if granted, !wasGranted {
            NotificationCenter.default.post(name: .soflerAccessibilityGranted,
                                            object: nil)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micSection
            Divider().opacity(0.25)
            accessibilitySection
        }
        .onAppear { monitor.observe() }
        .onDisappear { monitor.release() }
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
                Button("Ouvrir Réglages Système › Accessibilité") {
                    Permissions.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                Note("Ajoutez Sofler à la liste, puis revenez ici — l'état "
                     + "se met à jour tout seul.")
            }
        }
    }
}
