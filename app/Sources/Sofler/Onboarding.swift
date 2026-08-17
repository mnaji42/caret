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
        window.applySoflerGeometry()
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
    case presentation, language, permissions, tryIt, finish

    @MainActor
    var title: String {
        switch self {
        case .presentation: "Bienvenue dans Sofler"
        // Avant tout le reste : c'est elle qui décide du modèle à récupérer,
        // et ce téléchargement doit être fini avant le premier essai.
        case .language: "Dans quelle langue dictez-vous ?"
        // Le nombre dépend du moteur : la reconnaissance vocale ne s'ajoute
        // que pour celui de la Dictée. Un titre qui annonce « deux » devant
        // trois cases se lit comme un défaut d'attention.
        case .permissions: PermissionsMonitor.shared.neededCount == 3
            ? "Trois autorisations" : "Deux autorisations"
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
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .presentation: presentationStep
        case .language: languageStep
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
            // Ce que cette machine sait faire ne bloque pas : ça ne se corrige
            // pas dans l'instant, et griser « Continuer » dessus enfermerait
            // quelqu'un dans un écran dont il ne peut plus sortir.
            //
            // Et c'est **mesuré**. La version précédente lisait le numéro de
            // macOS : elle annonçait « le moteur intégré demande macOS 26 » et
            // proposait une mise à jour système sur des Mac où la Dictée
            // d'Apple dicte parfaitement — un avertissement inquiétant, une
            // action inutile, et rien de vrai.
            Card(title: "votre Mac") {
                StatusRow(ok: usableSystemEngine != nil, label: systemVersionLabel,
                          detail: usableSystemEngine.map {
                              "\($0.versionLabel ?? $0.label) — prêt à écrire"
                          } ?? "aucun moteur de macOS utilisable ici",
                          warningOnly: true)
                if usableSystemEngine == nil {
                    Note(LegacySpeechEngine.unavailabilityReason(for: prefs.language)
                         ?? "Aucune version du moteur de macOS n'est utilisable "
                            + "ici.", warning: true)
                    ButtonRow {
                        Button("Ouvrir Réglages › Clavier") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                    Note("CrisperWhisper s'installe à l'écran suivant et ne "
                         + "dépend d'aucun moteur de macOS.")
                }
            }

            Card(title: "ce que Sofler doit pouvoir faire") {
                PermissionsChecklist(explains: true)
            }

            if !monitor.allGranted {
                // Le compte suit la machine : la reconnaissance vocale ne
                // s'ajoute que là où la Dictée sert réellement. Le titre de la
                // page le savait déjà, cette note annonçait « les deux » devant
                // trois cases.
                Note("« Continuer » s'activera dès que \(monitor.neededCount == 3 ? "les trois" : "les deux") seront "
                     + "accordées.")
            }
        }
    }

    /// La version de macOS qui écrirait si l'on dictait maintenant.
    private var usableSystemEngine: EngineChoice? {
        EngineChoice.systemEngine(preferring: prefs.engine, for: prefs.language)
    }

    // MARK: 2 — Langue, et le modèle qui va avec

    /// La langue d'abord, parce qu'elle décide de ce qu'il faut télécharger.
    ///
    /// Elle arrivait au milieu des réglages de transcription, après les
    /// autorisations et juste avant le champ d'essai — c'est-à-dire trop tard :
    /// le modèle de reconnaissance de macOS est fourni par locale, et il faut
    /// savoir laquelle avant de pouvoir aller le chercher. Poser la question
    /// ici laisse au téléchargement le temps de se faire pendant qu'on accorde
    /// le micro et l'accessibilité, au lieu de l'ajouter à la fin.
    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "langue") {
                PillPicker(options: prefs.activeLanguages.map { ($0.code, $0.badge) },
                           selection: $prefs.primaryLanguage)
                Note("Un seul choix à la fois : les modèles imposent une langue "
                     + "par passage, et « automatique » se trompe précisément "
                     + "sur les phrases qui en mêlent deux. Vous en changerez "
                     + "quand vous voudrez — Sofler récupérera l'autre modèle à "
                     + "ce moment-là.")
            }

            // Proposer de télécharger un modèle pour un moteur que cette
            // machine ne peut pas faire tourner n'a aucun sens : le
            // téléchargement échouera, et l'échec inquiétera pour rien. La
            // carte n'apparaît que si le moteur de macOS 26 est réellement
            // disponible ici.
            if EngineChoice.apple.isAvailable(for: prefs.language) {
                Card(title: "modèle de reconnaissance") {
                    if EngineChoice.appleLegacy.isAvailable(for: prefs.language) {
                        Note("Sofler peut déjà écrire : la version **Dictée** "
                             + "est prête et n'a rien à télécharger. Ce "
                             + "modèle-ci est celui de la version **Apple "
                             + "Intelligence**, qui transcrit les passages "
                             + "longs plus finement — vous pourrez basculer de "
                             + "l'une à l'autre à l'écran suivant.")
                    }
                    ForEach(prefs.activeLanguages) { entry in
                        SpeechModelRow(language: entry.code, label: entry.displayName)
                        if entry.code != prefs.selectedLanguages.last {
                            Divider().opacity(0.2)
                        }
                    }
                    Note("macOS fournit ces modèles mais ne les embarque pas : "
                         + "sur une installation neuve il faut aller les "
                         + "chercher, une fois. Celui de votre langue se "
                         + "télécharge tout seul ; les autres attendent que "
                         + "vous en ayez besoin.")
                }
            } else if EngineChoice.appleLegacy.isAvailable(for: prefs.language) {
                Card(title: "moteur de dictée") {
                    StatusRow(ok: true, label: EngineChoice.appleLegacy.fullLabel,
                              detail: "prêt")
                    Note("Cette machine n'a pas la version **Apple "
                         + "Intelligence** du moteur de macOS, mais elle a "
                         + "celle de la **Dictée** — et elle n'a rien à "
                         + "télécharger. Sofler s'en servira.")
                }
            } else {
                Card(title: "moteur de dictée") {
                    Note(LegacySpeechEngine.unavailabilityReason(for: prefs.language)
                         ?? "Aucun moteur de macOS n'est utilisable ici.",
                         warning: true)
                    ButtonRow {
                        Button("Ouvrir Réglages › Clavier") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                    Note("CrisperWhisper s'installe deux écrans plus loin et "
                         + "ne dépend d'aucun moteur de macOS.")
                }
            }
        }
        // On regarde, on ne télécharge pas. La langue affichée est un défaut,
        // pas un choix : lancer plusieurs centaines de mégaoctets sur une
        // préférence que personne n'a encore touchée, c'est décider à la place
        // de quelqu'un qui n'a pas eu le temps de lire la question.
        .task { await assets.check(prefs.language) }
        // Là, en revanche, c'est un geste : la langue vient d'être choisie.
        .onChange(of: prefs.language) { _, chosen in
            Task { await assets.ensure(chosen) }
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

            TranscriptionSettings()

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
    /// Chaque étape garde sa propre condition.
    ///
    /// La langue bloque tant que son modèle n'est pas là : passer outre
    /// mènerait à la page d'essai avec un moteur qui n'écrit rien, ce qui est
    /// la confusion que tout ceci existe pour supprimer. Un système qui ne
    /// propose pas la langue ne bloque pas — rien ne l'y rendrait disponible,
    /// et CrisperWhisper reste installable plus loin.
    private var canContinue: Bool {
        switch step {
        case .language:
            // La version Dictée ne dépend d'aucun téléchargement : si elle est
            // là, la page est satisfaite quoi qu'il arrive au modèle de l'autre
            // version. Bloquer dessus enfermerait sur une machine qui sait
            // parfaitement dicter.
            //
            // Et la seconde condition se mesure — `SpeechTranscriber.isAvailable`
            // — au lieu de lire le numéro de macOS : une machine virtuelle en
            // macOS 26 n'a pas ce moteur, et attendre un modèle qu'elle ne
            // saura jamais installer bloquait l'accueil pour de bon.
            EngineChoice.appleLegacy.isAvailable(for: prefs.language)
                || !EngineChoice.apple.isAvailable(for: prefs.language)
                || assets.isSettled(prefs.language)
        case .permissions:
            monitor.allGranted
        default:
            true
        }
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

/// Une langue, l'état de son modèle, et de quoi le récupérer.
///
/// Calquée sur la ligne d'un modèle CrisperWhisper : même lecture, même
/// promesse. Tant qu'une pastille n'est pas verte, il manque quelque chose, et
/// le bouton dit quoi faire plutôt que de laisser deviner.
struct SpeechModelRow: View {
    let language: String
    let label: String

    @State private var assets = SpeechAssets.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch assets.state(of: language) {
            case .unknown, .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(label) — vérification…").font(.system(size: 12))
                }

            case .missing:
                StatusRow(ok: false, label: label, detail: "à télécharger",
                          warningOnly: true)
                ButtonRow {
                    Button("Télécharger \(label)") {
                        Task { await assets.install(language) }
                    }
                }

            // Indéterminé, faute de pouvoir mesurer sans casser ce qu'on
            // mesure. Cf. SpeechAssets : lire l'avancement faisait échouer le
            // téléchargement.
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(label) — téléchargement en cours…")
                        .font(.system(size: 12))
                }

            case .ready:
                StatusRow(ok: true, label: label, detail: "installé")

            case .unsupported(let why):
                StatusRow(ok: false, label: label, detail: "indisponible",
                          warningOnly: true)
                Note(why + "\n\nVous pouvez continuer.", warning: true)

            case .failed(let message):
                StatusRow(ok: false, label: label, detail: "échec",
                          warningOnly: true)
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Style.collecting)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ButtonRow {
                    Button("Réessayer") { Task { await assets.install(language) } }
                }
            }
        }
        .task { await assets.check(language) }
    }
}
