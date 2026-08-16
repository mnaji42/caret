import AppKit
import SwiftUI

/// L'accueil du premier lancement.
///
/// Sofler ne peut pas se contenter d'apparaître dans la barre de menus. Il lui
/// faut le micro et l'accessibilité, et son moteur intégré exige macOS 26 —
/// des conditions qu'une app sans fenêtre n'a aucun moyen d'expliquer une fois
/// lancée et invisible. Sans accueil, le premier lancement se solde par une
/// icône muette et une dictée qui ne fait rien.
///
/// Trois écrans, pas six. La version précédente en comptait six, dont quatre
/// ne portaient qu'un titre et deux phrases : dans un accueil, une page vide
/// n'est pas de la clarté, c'est un clic de plus avant d'essayer.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    /// N'ouvre que si l'accueil n'a jamais été mené à terme.
    func showIfNeeded() {
        guard !Preferences.shared.onboarded else { return }
        show()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: OnboardingView(onFinish: { [weak self] in self?.close() }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Bienvenue dans Sofler"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // Même verre que la barre et les réglages : trois surfaces, un seul
        // dialecte visuel.
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(NSSize(width: 580, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        // Sans ça, la fenêtre disparaît de l'écran dès que Sofler cesse d'être
        // l'application active — c'est-à-dire à l'instant précis où l'accueil
        // envoie quelqu'un accorder une autorisation dans les Réglages
        // Système. Il revient, et l'accueil s'est évaporé : il croit avoir
        // fait fuir l'application, alors qu'elle tourne toujours.
        window.hidesOnDeactivate = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Étapes

private enum Step: Int, CaseIterable {
    case presentation, permissions, tryIt, finish

    var title: String {
        switch self {
        case .presentation: "Bienvenue dans Sofler"
        case .permissions: "Deux autorisations"
        case .tryIt: "Comment Sofler écrit"
        // Séparée de la précédente depuis que celle-ci est exactement l'onglet
        // Transcription des Réglages : y laisser le démarrage automatique
        // aurait mélangé un réglage général à une page qui n'en contient
        // aucun, et empêché de partager la vue.
        case .finish: "Retrouver Sofler"
        }
    }
}

private var systemVersionLabel: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "macOS \(v.majorVersion).\(v.minorVersion)"
}

// MARK: - Fenêtre

private struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: Step = .presentation
    @State private var monitor = PermissionsMonitor.shared
    @State private var assets = SpeechAssets.shared
    @State private var prefs = Preferences.shared
    /// Ce que la dictée d'essai vient écrire. Le champ n'est pas rempli par le
    /// code : le texte y arrive par le même chemin que dans n'importe quelle
    /// autre application, ce qui est précisément ce qu'on cherche à prouver.
    @State private var trial = ""
    /// Coché d'avance, appliqué à la fin. Voir la carte « retrouver Sofler ».
    @State private var launchAtLogin = true

    /// Le déclencheur réellement actif — un seul l'est à la fois. Annoncer les
    /// deux laisserait croire qu'ils fonctionnent tous les deux.
    private var triggerLabel: String {
        prefs.triggerKind == .option
            ? prefs.triggerSide.label
            : prefs.dictateShortcut.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(step.title)
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 28)
                .padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassBackground().ignoresSafeArea())
        .task { startAssetCheck() }
    }

    /// Lancé à l'ouverture de la fenêtre, pas à l'arrivée sur la page : le
    /// téléchargement se fait pendant qu'on lit la présentation et qu'on
    /// accorde les autorisations, au lieu d'ajouter son attente à la leur.
    private func startAssetCheck() {
        Task { await assets.ensure(language: prefs.language) }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .presentation: presentationStep
        case .permissions: permissionsStep
        case .tryIt: tryStep
        case .finish: finishStep
        }
    }

    // MARK: 1 — Présentation

    private var presentationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vous appuyez sur une touche, vous parlez, vous appuyez à "
                 + "nouveau. Le texte s'écrit.")
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

            // Les deux destinations sur le même plan. Le mode notes est ce qui
            // sépare Sofler d'une dictée ordinaire : ne le mentionner qu'en
            // passant reviendrait à cacher la moitié de l'application.
            Card(title: "deux façons de s'en servir") {
                Text("**Au curseur.** Le texte atterrit là où votre curseur "
                     + "clignote déjà — éditeur, navigateur, messagerie — sans "
                     + "changer de fenêtre.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.25)

                Text("**Dans un fichier de notes.** Vous désignez un fichier, "
                     + "et tout ce que vous dictez s'y ajoute, où que soit le "
                     + "curseur. C'est ce qui permet de réfléchir à voix "
                     + "haute : vous parlez pendant que vous travaillez, les "
                     + "idées s'empilent dans le fichier, et vous les relisez "
                     + "après.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Note("La destination se change d'un clic sur la barre, même en "
                 + "plein milieu d'une phrase : elle n'est lue qu'au moment où "
                 + "vous arrêtez de parler.")

            Card(title: "rien ne sort de votre Mac") {
                Note("Votre voix est transcrite sur place, par votre machine. "
                     + "Sofler n'a pas de compte, pas de serveur, et n'envoie "
                     + "nulle part ce que vous dictez. Il n'y a aucun réglage "
                     + "pour l'y autoriser — la fonction n'existe pas.")
            }
        }
    }

    // MARK: 2 — Autorisations

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // La version de macOS ne bloque pas : elle ne se corrige pas dans
            // l'instant, et griser « Continuer » dessus enfermerait quelqu'un
            // dans un écran dont il ne peut plus sortir.
            Card(title: "votre Mac") {
                StatusRow(ok: EngineChoice.systemEngineAvailable, label: systemVersionLabel,
                          detail: EngineChoice.systemEngineAvailable
                            ? "le moteur intégré est disponible"
                            : "le moteur intégré demande macOS 26",
                          warningOnly: true)
                if !EngineChoice.systemEngineAvailable {
                    Note("Sur votre version, le moteur inclus n'existe pas. "
                         + "Vous pouvez mettre à jour macOS, ou passer par "
                         + "CrisperWhisper à l'écran suivant — il fonctionne "
                         + "dès macOS 14.", warning: true)
                    Button("Ouvrir la mise à jour de logiciels") {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!)
                    }
                }
                if EngineChoice.systemEngineAvailable { speechModel }
            }

            Card(title: "ce que Sofler doit pouvoir faire") {
                PermissionsChecklist(explains: true)
            }

            if !monitor.allGranted {
                Note("« Continuer » s'activera dès que les deux seront "
                     + "accordées.")
            }
        }
    }

    /// Le modèle de reconnaissance de macOS, vérifié et récupéré ici.
    ///
    /// Ici et pas à la première dictée : quelqu'un qui vient d'appuyer sur une
    /// touche pour voir si ça marche ne doit pas attendre un téléchargement.
    /// Et sans choix à faire — ce modèle sert à l'aperçu en direct quel que
    /// soit le moteur retenu, donc il est un prérequis, pas une option.
    @ViewBuilder
    private var speechModel: some View {
        switch assets.state {
        case .unknown, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Vérification du modèle de reconnaissance…")
                    .font(.system(size: 12))
            }

        case .installing(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text(fraction > 0
                     ? "Téléchargement du modèle de reconnaissance — "
                       + "\(Int(fraction * 100)) %"
                     : "Téléchargement du modèle de reconnaissance…")
                    .font(.system(size: 12))
                ProgressView(value: max(fraction, 0.02))
                    .progressViewStyle(.linear)
                    .tint(Style.accent)
                Text("macOS le fournit mais ne l'embarque pas : sur une "
                     + "installation neuve il faut aller le chercher, une "
                     + "seule fois.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .ready:
            StatusRow(ok: true, label: "Modèle de reconnaissance",
                      detail: "prêt")

        case .unsupported(let why):
            Note(why, warning: true)

        case .failed(let message):
            Note("Le modèle de reconnaissance de macOS n'a pas pu être "
                 + "téléchargé : \(message) Vous pouvez continuer — "
                 + "CrisperWhisper s'installe à l'écran suivant et ne dépend "
                 + "pas de celui-ci.", warning: true)
            Button("Réessayer") {
                Task { await assets.retry(language: prefs.language) }
            }
        }
    }

    // MARK: 3 — Moteur, puis essai

    /// Exactement l'onglet Transcription des Réglages, plus le champ d'essai.
    ///
    /// C'était une deuxième implémentation des mêmes questions, et elle avait
    /// perdu en route le mode mot à mot, le vocabulaire et la langue. Un
    /// accueil qui ne montre pas une fonctionnalité est un accueil après
    /// lequel on ne la découvre jamais.
    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deux moteurs, et une seule question : les mots de votre "
                 + "métier, les noms propres, les mots anglais — voulez-vous "
                 + "qu'ils s'écrivent tels que vous les dites ?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            TranscriptionSettings(
                systemEngineAvailable: EngineChoice.systemEngineAvailable)

            Card(title: "essayez maintenant") {
                Note("Cliquez dans le cadre, tapez "
                     + "**\(triggerLabel)**, dites une phrase, puis "
                     + "tapez à nouveau. Le texte s'écrira ici — exactement "
                     + "comme il le fera dans vos applications.")
                TextEditor(text: $trial)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 90)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Style.cardStroke, lineWidth: 1)))
                if !trial.isEmpty {
                    Note("C'est bien votre voix qui a écrit ça. Vous pouvez "
                         + "effacer et recommencer autant que vous voulez.")
                }
            }
        }
    }

    // MARK: 4 — Réglages généraux

    /// Ce qui ne relève d'aucun moteur : où trouver l'application, et
    /// faut-il la lancer toute seule.
    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "retrouver Sofler") {
                Note("Il vit dans la barre de menus, en haut à droite : un "
                     + "caret entouré d'ondes pendant qu'il écoute.")
                Note(prefs.triggerKind == .option
                     ? "Maintenez **⌥** une seconde pour ouvrir les réglages."
                     : "Les réglages s'ouvrent depuis ce menu.")
            }

            Card(title: "ouverture de session") {
                // Proposé et coché, pas imposé en silence. Appliqué au clic
                // sur « Terminer » : cocher une case n'est pas encore une
                // décision, finir l'accueil en est une.
                FeatureSwitch(title: "Lancer Sofler à l'ouverture de session",
                              isOn: $launchAtLogin)
                Note("Sans ça, la touche Option ne fera rien après chaque "
                     + "redémarrage, jusqu'à ce que vous pensiez à rouvrir "
                     + "l'application — et rien ne dira que c'est la raison. "
                     + "Se change à tout moment dans les réglages.")
            }

            Card(title: "revenir sur tout ça") {
                Note("Rien de ce que vous venez de choisir n'est définitif. "
                     + "Le moteur, le modèle, la langue et le mode se "
                     + "changent depuis **Réglages › Transcription**, qui est "
                     + "la même page que celle que vous venez de voir. "
                     + "CrisperWhisper et ses modèles se téléchargent ou se "
                     + "retirent quand vous voulez, et **Désinstaller "
                     + "Sofler…** dans le menu retire tout, en vous laissant "
                     + "cocher ce qui part.")
            }
        }
    }

    // MARK: Pied

    /// Bloqué tant que le micro et l'accessibilité manquent — mais seulement
    /// sur l'écran qui les présente. Bloquer ailleurs punirait sans expliquer.
    /// Attendre la fin du téléchargement, pas son succès.
    ///
    /// Laisser passer pendant qu'il descend mènerait à la page d'essai avec un
    /// moteur qui n'écrit rien — précisément la confusion qu'on cherche à
    /// supprimer. Mais bloquer sur un échec enfermerait quelqu'un dans un
    /// écran dont rien ne le sort : un réseau coupé n'est pas une raison de
    /// perdre l'accueil, et CrisperWhisper reste installable à l'écran suivant.
    private var canContinue: Bool {
        guard step == .permissions else { return true }
        return monitor.allGranted && (assets.isSettled || !EngineChoice.systemEngineAvailable)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .presentation {
                Button("Retour") {
                    step = Step(rawValue: step.rawValue - 1) ?? .presentation
                }
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == step ? Style.accent : Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer()

            Button(step == .finish ? "Terminer" : "Continuer") {
                if step == .finish {
                    LoginItem.set(launchAtLogin)
                    prefs.onboarded = true
                    onFinish()
                } else {
                    step = Step(rawValue: step.rawValue + 1) ?? .finish
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Style.accent)
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}

// MARK: - Pièces
