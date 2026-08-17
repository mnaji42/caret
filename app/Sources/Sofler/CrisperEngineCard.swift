import SwiftUI

/// CrisperWhisper : son rendu, son modèle, son service.
///
/// Rassemble ce qui n'existe que sous ce moteur — le mode nettoyé/verbatim et
/// le cycle de vie du modèle — pour que rien n'en soit visible quand c'est
/// macOS qui écrit. Ces réglages étaient présentés en cartes séparées, ce qui
/// faisait lire quatre décisions indépendantes là où il n'y en a qu'une, et
/// laissait le choix du modèle en évidence même sur une machine qui n'avait
/// jamais rien téléchargé.
///
/// La mécanique d'installation elle-même (machine d'état `uv`, poids Hugging
/// Face, socket Unix, licence) reste dans `CrisperWhisperSetup` : elle est
/// éprouvée, et ce composant-ci ne fait que la présenter au bon endroit.
struct CrisperEngineCard: View, ValidatingComponent {
    /// Imbriqué sous une ligne de choix.
    var isSubCard = false
    /// Pendant l'accueil, on ne propose pas de désinstaller ce qu'on vient
    /// d'installer.
    var isOnboarding = false

    @State private var prefs = Preferences.shared

    // MARK: - Validité

    /// Des poids sur le disque ne transcrivent rien tant que le service n'est
    /// pas debout : la validité demande les deux.
    static func validate() -> ComponentValidationError? {
        EngineSafetyManager.shared.isReady(.crisperWhisper,
                                           for: Preferences.shared.primaryLanguage)
            ? nil : .crisperEngineNotReady
    }

    /// Le modèle qui servirait si l'on dictait maintenant.
    ///
    /// Plusieurs peuvent coexister sur le disque : c'est celui que le
    /// descripteur désigne qui compte, pas le premier trouvé.
    private var installedModel: CrisperWhisperModel? {
        let active = EngineInstall.selectedModel
        return active.isDownloaded ? active : CrisperWhisperModel.downloaded.first
    }

    var body: some View {
        if isSubCard {
            VStack(alignment: .leading, spacing: 12) { content }
        } else {
            Card(title: title) { content }
        }
    }

    /// Le nom porte celui du modèle dès qu'il y en a un : c'est l'information
    /// qu'on cherche une fois installé — « lequel tourne en ce moment ».
    private var title: String {
        guard let installed = installedModel else {
            return EngineChoice.crisperWhisper.label
        }
        return "\(EngineChoice.crisperWhisper.label) · \(installed.label)"
    }

    @ViewBuilder
    private var content: some View {
        Subsection("Rendu")
        Row(label: "Mode par défaut") {
            PillPicker(options: [(TranscriptionMode.intended, "Texte nettoyé"),
                                 (TranscriptionMode.verbatim, "Mot à mot")],
                       selection: $prefs.defaultMode)
        }
        Note("« Nettoyé » retire les hésitations et les répétitions ; « mot à "
             + "mot » garde tout, y compris les « euh ». Le choix se change "
             + "aussi en cours de dictée, depuis la barre flottante — essayez "
             + "les deux sur la même phrase.")

        // Repliée dès qu'un modèle est là : la liste des quatre modèles, la
        // licence et le bloc de retrait répondent à une question qu'on ne se
        // pose plus une fois installé, en occupant la moitié de la fenêtre.
        CrisperWhisperSetup(
            presentation: installedModel == nil || isOnboarding ? .full : .compact,
            isActiveEngine: prefs.finalEngine == .crisperWhisper)

        if !isSubCard {
            Note("Le mode n'apparaît que sous CrisperWhisper parce qu'il "
                 + "n'existe que là : le moteur de macOS n'a qu'un rendu. "
                 + "Votre vocabulaire, lui, a son propre onglet — il ne dépend "
                 + "d'aucun moteur.")
        }
    }
}

#Preview("CrisperWhisper") {
    ScrollView {
        CrisperEngineCard()
            .padding(Style.windowPadding)
    }
    .frame(width: Style.windowWidth, height: Style.windowHeight)
    .background(Color(hex: 0x141821))
}
