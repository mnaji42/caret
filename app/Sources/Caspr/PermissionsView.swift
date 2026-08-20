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
/// une est affichée : Caspr tourne en permanence, un timer à 1 Hz qui ne
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

    /// L'interrupteur de la Dictée de macOS, relu au même rythme que les
    /// autorisations.
    ///
    /// Ce n'en est pas une — cf. `SystemDictation` — mais il se corrige au même
    /// endroit et de la même façon : on part dans les Réglages Système, on
    /// bascule quelque chose, et rien ne revient nous le dire. C'est exactement
    /// le trou que ce moniteur existe pour boucher.
    private(set) var dictationDisabled = SystemDictation.isDisabled

    /// Le droit de reconnaissance vocale n'entre dans le compte que s'il sert :
    /// l'exiger sur une machine qui dictera avec CrisperWhisper bloquerait
    /// l'accueil sur une autorisation inutile.
    /// Combien d'autorisations cette machine réclame réellement.
    var neededCount: Int { requiresSpeech ? 3 : 2 }

    /// Le droit de reconnaissance vocale est-il en jeu ici ?
    ///
    /// Trois façons de faire tourner la Dictée, et il suffit d'une : elle
    /// écrit, la collecte l'exécute après insertion, ou c'est elle qui assure
    /// l'aperçu en direct. La version précédente ne voyait que la première et
    /// une approximation de la troisième — quelqu'un qui écrivait avec
    /// CrisperWhisper tout en archivant avec la Dictée n'avait jamais
    /// l'occasion d'accorder le droit dont sa collecte dépendait.
    var requiresSpeech: Bool {
        let prefs = Preferences.shared
        // Contient toujours le moteur d'écriture, plus ceux de la collecte.
        if prefs.enginesToCollect().contains(.appleLegacy) { return true }
        // La permission de reconnaissance vocale suit **le moteur de l'aperçu**,
        // qui est celui qui l'utilise. La déduire du moteur d'écriture la
        // demandait au mauvais moment : réglé sur Dictée pour l'aperçu et sur
        // Apple Intelligence pour la transcription, on ne la réclamait jamais.
        return prefs.livePreviewEnabled
            && SpeechPreview.engine(using: prefs.liveEngineTechnology,
                                    for: prefs.language) == .appleLegacy
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
        micAccess = AudioRecorder.microphoneAccess
        speechGranted = LegacySpeechEngine.isAuthorised

        let granted = AXIsProcessTrusted()
        let wasGranted = accessibilityGranted
        accessibilityGranted = granted

        let wasDictationDisabled = dictationDisabled
        dictationDisabled = SystemDictation.isDisabled

        // ## Pourquoi seulement ces deux-là
        //
        // Se remettre devant ne vaut que pour ce qui s'obtient **ailleurs** :
        // l'accessibilité et l'interrupteur de la Dictée s'accordent dans les
        // Réglages Système, et macOS y laisse le focus une fois le geste fait.
        //
        // Le micro et la reconnaissance vocale, non : leur dialogue est
        // présenté par notre propre processus, et macOS nous rend la main tout
        // seul en le refermant. On s'activait quand même — et sur un Mac où les
        // Réglages Système étaient restés ouverts derrière (ce qui est le cas
        // juste après avoir accordé l'accessibilité), cet appel tombait pendant
        // que le dialogue se refermait et le focus atterrissait sur eux plutôt
        // que sur Caspr. On accordait le micro et on se retrouvait dans les
        // Réglages, sans rien avoir demandé.
        if (granted && !wasGranted) || (wasDictationDisabled && !dictationDisabled) {
            returnToForeground()
        }
        // C'est ici qu'on apprend le plus tôt que le droit vient d'arriver —
        // pendant que l'accueil est ouvert et que l'utilisateur regarde. Le
        // déclencheur clavier en dépend et ne se répare pas seul.
        if granted, !wasGranted {
            NotificationCenter.default.post(name: .casprAccessibilityGranted,
                                            object: nil)
        }
    }

    /// Ramène Caspr devant, au moment où l'on sait que le geste vient d'être
    /// fait dans les Réglages Système.
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
