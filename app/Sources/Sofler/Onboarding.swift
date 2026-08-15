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
    case presentation, permissions, tryIt

    var title: String {
        switch self {
        case .presentation: "Bienvenue dans Sofler"
        case .permissions: "Deux autorisations"
        case .tryIt: "Choisissez, puis essayez"
        }
    }
}

/// Vrai si le moteur intégré — celui de macOS — est utilisable ici.
///
/// C'est la seule condition qui rend Sofler utilisable sans rien installer.
/// En dessous, l'application se lance quand même (cf. LSMinimumSystemVersion
/// dans install.sh) précisément pour pouvoir l'expliquer.
private var systemEngineAvailable: Bool {
    if #available(macOS 26.0, *) { true } else { false }
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
    @State private var prefs = Preferences.shared
    /// Ce que la dictée d'essai vient écrire. Le champ n'est pas rempli par le
    /// code : le texte y arrive par le même chemin que dans n'importe quelle
    /// autre application, ce qui est précisément ce qu'on cherche à prouver.
    @State private var trial = ""
    /// Coché d'avance, appliqué à la fin. Voir la carte « retrouver Sofler ».
    @State private var launchAtLogin = true

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
        case .permissions: permissionsStep
        case .tryIt: tryStep
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
                StatusRow(ok: systemEngineAvailable, label: systemVersionLabel,
                          detail: systemEngineAvailable
                            ? "le moteur intégré est disponible"
                            : "le moteur intégré demande macOS 26",
                          warningOnly: true)
                if !systemEngineAvailable {
                    Note("Sur votre version, le moteur inclus n'existe pas. "
                         + "Vous pouvez mettre à jour macOS, ou passer par "
                         + "CrisperWhisper à l'écran suivant — il fonctionne "
                         + "dès macOS 14.", warning: true)
                    Button("Ouvrir la mise à jour de logiciels") {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!)
                    }
                }
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

    // MARK: 3 — Moteur, puis essai

    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deux moteurs. La question tient en une phrase : dictez-vous "
                 + "des mots que le français courant ne contient pas ?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(EngineChoice.allCases, id: \.self) { choice in
                EngineOption(
                    choice: choice,
                    selected: prefs.engine == choice,
                    enabled: choice == .crisperWhisper || systemEngineAvailable,
                    select: { prefs.engine = choice })
            }

            if prefs.engine == .crisperWhisper {
                crisperWhisperTerms
            }

            Card(title: "essayez maintenant") {
                Note("Cliquez dans le cadre, tapez "
                     + "**\(prefs.triggerSide.label)**, dites une phrase, puis "
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

            Card(title: "retrouver Sofler") {
                Note("Il vit dans la barre de menus, en haut à droite : un "
                     + "caret entouré d'ondes pendant qu'il écoute.")
                Note("Maintenez **⌥** une seconde pour ouvrir les réglages. "
                     + "Au clavier, sans la touche Option : "
                     + "**\(prefs.dictateShortcut.label)**.")

                Divider().opacity(0.25)

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
        }
    }

    private var crisperWhisperTerms: some View {
        Card(title: "avant d'installer CrisperWhisper") {
            Note("**Rien n'est téléchargé automatiquement.** Le modèle n'est "
                 + "pas dans l'application, et Sofler n'ira pas le chercher "
                 + "sans vous.")
            Note("**Licence non commerciale.** Les poids sont distribués par "
                 + "Nyra Health sous une licence de recherche non "
                 + "commerciale — sous une lecture stricte, dicter un "
                 + "courriel professionnel peut déjà en relever. Le code de "
                 + "Sofler, lui, est libre.")
            Button("Lire la licence") {
                NSWorkspace.shared.open(URL(string:
                    "https://huggingface.co/nyralabs/CrisperWhisper2.0_turbo/blob/main/LICENSE.md")!)
            }
            Divider().opacity(0.25)
            Note("**L'installation passe par le Terminal** et n'est pas "
                 + "incluse dans l'application téléchargée : il faut récupérer "
                 + "le dépôt et lancer un script. Mac Apple Silicon requis.",
                 warning: true)
            Button("Ouvrir les instructions") {
                NSWorkspace.shared.open(URL(string:
                    "https://github.com/mnaji42/sofler#build-from-source")!)
            }
        }
    }

    // MARK: Pied

    /// Bloqué tant que le micro et l'accessibilité manquent — mais seulement
    /// sur l'écran qui les présente. Bloquer ailleurs punirait sans expliquer.
    private var canContinue: Bool {
        step != .permissions || monitor.allGranted
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

            Button(step == .tryIt ? "Terminer" : "Continuer") {
                if step == .tryIt {
                    LoginItem.set(launchAtLogin)
                    prefs.onboarded = true
                    onFinish()
                } else {
                    step = Step(rawValue: step.rawValue + 1) ?? .tryIt
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

/// Un moteur présenté comme un choix, avec ce qu'il coûte.
///
/// `EngineChoice.explanation` porte le texte : le dupliquer ici condamnerait
/// les réglages et l'accueil à finir par se contredire.
private struct EngineOption: View {
    let choice: EngineChoice
    let selected: Bool
    let enabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Style.accent : Color.secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.label).font(.system(size: 13, weight: .medium))
                    Text(choice.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !enabled {
                        Text("Indisponible sur \(systemVersionLabel).")
                            .font(.system(size: 11))
                            .foregroundStyle(Style.collecting)
                    }
                }
                Spacer()
            }
            .padding(Style.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                    .fill(Style.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                            .strokeBorder(selected ? Style.accent.opacity(0.6) : Style.cardStroke,
                                          lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
