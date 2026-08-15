import AppKit
import AVFoundation

/// Accès aux volets d'autorisation des Réglages Système.
///
/// Une app ne peut pas s'accorder ces droits ni même rouvrir le dialogue une
/// fois qu'un refus a été enregistré. Le mieux qu'elle puisse faire est
/// d'amener l'utilisateur au bon endroit en un clic, plutôt que de lui
/// demander de naviguer dans les Réglages.
enum Permissions {
    private static func open(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        open("Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("Privacy_Accessibility")
    }

    /// Résumé lisible de l'état courant, affiché dans le menu.
    static func summary(accessibilityGranted: Bool) -> String {
        let mic = switch AudioRecorder.microphoneAccess {
        case .granted: "micro ✓"
        case .undetermined: "micro —"
        case .denied: "micro ✗"
        }
        return "\(mic)   accessibilité \(accessibilityGranted ? "✓" : "✗")"
    }

    static var allGranted: Bool {
        AudioRecorder.microphoneAccess == .granted && AXIsProcessTrusted()
    }
}
