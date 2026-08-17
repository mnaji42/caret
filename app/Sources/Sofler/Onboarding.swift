import AppKit
import SwiftUI

/// L'accueil du premier lancement.
///
/// Sofler ne peut pas se contenter d'apparaître dans la barre de menus. Il lui
/// faut le micro et l'accessibilité, et son moteur intégré exige des modèles
/// qui se téléchargent — des conditions qu'une app sans fenêtre n'a aucun moyen
/// d'expliquer une fois lancée et invisible. Sans accueil, le premier lancement
/// se solde par une icône muette et une dictée qui ne fait rien.
///
/// ## Cinq étapes, et aucune n'est une page vide
///
/// Une version précédente en comptait six, dont quatre ne portaient qu'un titre
/// et deux phrases ; celle d'après en comptait cinq mais réimplémentait les
/// questions que les Réglages posaient déjà, si bien que les deux avaient
/// divergé. Celle-ci n'écrit **aucun** réglage de son côté : chaque étape
/// instancie les mêmes vues que les Réglages, et sa seule responsabilité est
/// l'ordre dans lequel on les rencontre.
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
            rootView: OnboardingView(onFinish: { [weak self] in self?.close() },
                                     onOpenSettings: { [weak self] in
                                         self?.close()
                                         self?.openSettings?()
                                     }))
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

    /// Ouvre les Réglages, posé par le delegate : l'accueil ne connaît pas la
    /// fenêtre des Réglages et n'a aucune raison de la connaître.
    var openSettings: (() -> Void)?

    private func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Les étapes

private enum Step: Int, CaseIterable {
    case welcome, languages, trigger, engine, finish

    var title: String {
        switch self {
        case .welcome: "Bienvenue dans Sofler"
        // La langue avant tout le reste : c'est elle qui décide du modèle à
        // récupérer, et ce téléchargement doit être fini avant le premier essai.
        case .languages: "Vos langues"
        case .trigger: "Comment déclencher la dictée"
        case .engine: "Qui écrit le texte"
        case .finish: "Tout est prêt"
        }
    }

    var subtitle: String? {
        switch self {
        case .welcome:
            "La dictée locale, pensée pour vos mots, votre métier et vos "
                + "langues mêlées."
        case .languages:
            "Sofler récupérera les modèles correspondants pendant que vous "
                + "configurez le reste."
        case .trigger:
            "Deux autorisations, puis un premier essai."
        case .engine:
            "Ce choix se change à tout moment, et n'engage à rien."
        case .finish:
            nil
        }
    }
}

// MARK: - Fenêtre

private struct OnboardingView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    @State private var prefs = Preferences.shared
    @State private var step: Step
    @State private var launchAtLogin = LoginItem.isEnabled

    init(onFinish: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
        // Reprend là où on s'était arrêté. Rouvrir sur la page de bienvenue
        // quelqu'un qui était à l'étape des autorisations lui ferait relire ce
        // qu'il vient de lire, et douter d'avoir progressé.
        _step = State(initialValue:
            Step(rawValue: Preferences.shared.onboardingStep) ?? .welcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, Style.windowPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassBackground().ignoresSafeArea())
        // Enregistrée en continu : quitter l'application au milieu d'une étape
        // ne doit pas coûter les précédentes.
        .onChange(of: step) { _, now in prefs.onboardingStep = now.rawValue }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.title)
                .font(.system(size: 24, weight: .bold))
                .kerning(-0.4)
            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, Style.windowPadding)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .languages: languagesStep
        case .trigger: triggerStep
        case .engine: engineStep
        case .finish: finishStep
        }
    }

    // MARK: 1 — Bienvenue

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "le principe en trois points") {
                principle(1, "Écrivez au son de votre voix",
                          "Vous appuyez sur une touche, vous parlez, vous "
                          + "appuyez à nouveau. Le texte s'insère à votre "
                          + "curseur, dans l'application que vous avez devant "
                          + "vous.")
                Divider().opacity(0.25)
                principle(2, "Rien ne sort de votre Mac",
                          "Aucun compte, aucun serveur, aucune connexion "
                          + "requise. **Il n'existe aucun réglage pour "
                          + "autoriser l'envoi de ce que vous dictez — la "
                          + "fonction n'existe pas.**")
                Divider().opacity(0.25)
                principle(3, "Vous choisissez le moteur",
                          "Celui de macOS ne pèse rien et n'a rien à "
                          + "télécharger. CrisperWhisper écrit les mots de "
                          + "votre métier tels que vous les dites, en échange "
                          + "de 1,6 Go et d'environ 3 Go en mémoire.")
            }

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
                     + "idées s'empilent, et vous les relisez après.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Note("Trois écrans suffisent à pouvoir dicter. Les deux suivants "
                 + "affinent, et se refont plus tard depuis les Réglages.")
        }
    }

    private func principle(_ number: Int, _ title: String,
                           _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Style.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Style.accentDim))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(.init(detail))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 2 — Langues et usage

    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "langues de dictée") {
                LanguagePicker()
                Note("La première de la liste est celle avec laquelle Sofler "
                     + "dicte. Vous en changerez d'un clic depuis les Réglages "
                     + "ou la barre flottante.")
            }
            UsageHabitsCard()
        }
    }

    // MARK: 3 — Déclencheur, autorisations, essai

    /// L'étape charnière : c'est elle qui rend Sofler utilisable, et c'est la
    /// dernière que la garde d'accès exige.
    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TriggerCard(showTrialSandbox: true)
            AppleEngineCard()
            Note("Ce moteur assure l'aperçu en direct sous la barre pendant "
                 + "que vous parlez, et écrit le texte final tant que vous "
                 + "n'avez pas choisi autre chose à l'écran suivant.")
        }
    }

    // MARK: 4 — Moteur final

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            FinalEngineCard(showsRecommendation: true, isOnboarding: true)
        }
    }

    // MARK: 5 — Récapitulatif

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "votre configuration") {
                summary("Langue", prefs.primary.badge)
                summary("Déclencheur", prefs.triggerKind == .option
                        ? "Touche \(prefs.triggerSide.label)"
                        : prefs.dictateShortcut.label)
                summary("Moteur", prefs.engine.fullLabel)
                summary("Destination", prefs.destination == .notes
                        ? (prefs.noteFile?.lastPathComponent ?? "fichier de notes")
                        : "au curseur")
            }

            Card(title: "bon à savoir") {
                tip("menubar.rectangle", "Sofler vit dans la barre de menus",
                    prefs.triggerKind == .option
                        ? "Un caret entouré d'ondes pendant qu'il écoute. "
                          + "**Maintenir ⌥ une seconde** ouvre les Réglages."
                        : "Un caret entouré d'ondes pendant qu'il écoute. Les "
                          + "Réglages s'ouvrent depuis ce menu.")
                Divider().opacity(0.25)
                tip("clock.arrow.circlepath", "Vous ne perdez jamais une dictée",
                    "Même sans curseur actif, le texte part dans l'historique "
                    + "local du menu, où il reste copiable. Et si un moteur "
                    + "échoue, l'audio est conservé : « Réessayer » relance "
                    + "sans vous faire tout redire.")
                Divider().opacity(0.25)
                tip("folder", "La destination se change en pleine phrase",
                    "Un clic sur la barre flottante bascule entre le curseur "
                    + "et votre fichier de notes — la destination n'est lue "
                    + "qu'au moment où vous arrêtez de parler.")
            }

            SettingsToggleRow(
                title: "Lancer Sofler à l'ouverture de session",
                description: "Disponible dans la barre de menus dès le "
                    + "démarrage de votre Mac.",
                note: "Sans ça, la touche de dictée ne fera rien après chaque "
                    + "redémarrage, jusqu'à ce que vous pensiez à rouvrir "
                    + "l'application — et rien ne dira que c'est la raison.",
                isOn: $launchAtLogin)

            ButtonRow {
                Button("Personnaliser dans les Réglages…") {
                    apply()
                    onOpenSettings()
                }
            }
            Note("Tout ce que vous venez de choisir se retrouve dans les "
                 + "Réglages, dans les mêmes cartes que celles que vous venez "
                 + "de voir. **Désinstaller Sofler…** y retire tout, en vous "
                 + "laissant cocher ce qui part.")
        }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func tip(_ symbol: String, _ title: String,
                     _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Style.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(.init(detail))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pied

    /// Ce qui manque pour passer à l'étape suivante, ou `nil`.
    ///
    /// Chaque étape délègue à ses propres composants : ce sont eux qui savent
    /// ce qui leur manque, et ils le savent d'une seule façon, partagée avec
    /// les Réglages.
    private var blocker: ComponentValidationError? {
        switch step {
        case .welcome: nil
        case .languages: LanguagePicker.validate()
        // Le moteur macOS ne bloque pas : sur une machine sans aucun moteur
        // système, CrisperWhisper s'installe à l'écran suivant et n'a besoin de
        // rien de tout ça. Bloquer ici enfermerait dans une page dont rien ne
        // sort.
        case .trigger: TriggerCard.validate()
        case .engine: FinalEngineCard.validate()
        case .finish: nil
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let blocker, step != .welcome {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    // Dit ce qui manque, au lieu de griser sans expliquer. Un
                    // bouton inactif muet est la façon la plus sûre de faire
                    // abandonner quelqu'un à l'étape des autorisations.
                    Text(blocker.errorDescription ?? "")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundStyle(Style.warning)
                .padding(.horizontal, Style.windowPadding)
                .padding(.bottom, 6)
            }

            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Retour") {
                        step = Step(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(Step.allCases, id: \.self) { each in
                        Circle()
                            .fill(each == step ? Style.accent
                                               : Color.secondary.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                Button(step == .finish ? "Terminer" : "Continuer") {
                    if step == .finish {
                        apply()
                        onFinish()
                    } else {
                        step = Step(rawValue: step.rawValue + 1) ?? .finish
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .disabled(blocker != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Style.windowPadding)
            .padding(.vertical, 18)
        }
    }

    /// Applique ce que l'accueil a différé, et clôt la configuration.
    ///
    /// Le démarrage automatique est le seul réglage que l'accueil n'écrit pas
    /// en direct : cocher une case n'est pas encore une décision, finir
    /// l'accueil en est une. Tout le reste a été enregistré par les composants
    /// au fil de l'eau.
    private func apply() {
        LoginItem.set(launchAtLogin)
        prefs.onboarded = true
    }
}

// MARK: - Pièces

/// Une langue, l'état de son modèle, et de quoi le récupérer.
///
/// Conservée pour les Réglages Système et les diagnostics : `AppleEngineCard`
/// porte désormais le cas courant, mais cette ligne reste la façon la plus
/// compacte de montrer l'état d'**une** langue précise.
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
                    .foregroundStyle(Style.warning)
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
