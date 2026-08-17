import AppKit
import SwiftUI

/// Fenêtre de réglages.
///
/// Sofler est une app d'arrière-plan sans Dock : ouvrir une fenêtre demande de
/// l'activer explicitement, sinon elle apparaît derrière tout le reste.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    /// L'historique appartient au contrôleur de dictée : on le passe plutôt
    /// que d'en faire un singleton de plus, pour qu'il n'existe qu'un seul
    /// propriétaire de ces données.
    func show(history: TranscriptionHistory) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView(history: history))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages de Sofler"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // Le fond est peint par la vue, avec le même verre que la barre : sans
        // ça, macOS glisse son gris système derrière et les deux surfaces de
        // l'application ne se ressemblent plus.
        window.backgroundColor = .clear
        window.isOpaque = false
        // La même géométrie que l'accueil, au point près : les cartes de
        // configuration sont littéralement les mêmes vues aux deux endroits.
        window.applySoflerGeometry()
        window.isReleasedWhenClosed = false
        // Les réglages contiennent eux aussi des boutons qui ouvrent les
        // Réglages Système. Sans ça, ils s'effacent au moment d'y aller, et on
        // revient devant rien. Cf. Onboarding.swift, même cause.
        window.hidesOnDeactivate = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Fenêtre

private struct PreferencesView: View {
    let history: TranscriptionHistory
    @State private var tab: Tab = .general

    /// Trois questions, dans l'ordre où on se les pose : *comment je
    /// déclenche et où ça va*, *avec quoi ça transcrit*, *ce que je garde*.
    ///
    /// La version précédente séparait « Moteur » et « Dictée », ce qui
    /// obligeait à choisir la langue sur une page et le moteur sur une autre
    /// alors que l'une ne sert qu'à l'autre.
    enum Tab: String, CaseIterable {
        case general, transcription, vocabulary, collection, history

        var label: String {
            switch self {
            case .general: "Général"
            case .transcription: "Transcription"
            case .vocabulary: "Vocabulaire"
            case .collection: "Collecte"
            case .history: "Historique"
            }
        }

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .transcription: "waveform"
            case .vocabulary: "text.book.closed"
            case .collection: "tray.full"
            case .history: "clock"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .general: GeneralTab()
                    case .transcription: TranscriptionTab()
                    case .vocabulary: VocabularySettings()
                    case .collection: CollectionTab()
                    case .history: HistoryTab(history: history)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(GlassBackground().ignoresSafeArea())
        .tint(Style.accent)
    }

    /// Les onglets reprennent la forme des pastilles de la barre plutôt que le
    /// `TabView` système, dont la barre d'outils grise casse la continuité.
    private var tabBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { item in
                    let active = item == tab
                    Label(item.label, systemImage: item.symbol)
                        .font(.system(size: 12, weight: active ? .semibold : .medium))
                        .foregroundStyle(active
                            ? Color(nsColor: NSColor.systemTeal
                                .blended(withFraction: 0.25, of: .white) ?? .systemTeal)
                            : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(active ? Style.accent.opacity(0.20) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { tab = item }
                }
            }
            .padding(4)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06),
                                                    lineWidth: 1)))
            Spacer()
        }
        .padding(.bottom, 14)
    }
}

// MARK: - Général

private struct GeneralTab: View {
    @State private var prefs = Preferences.shared
    @State private var soundsEnabled = Feedback.soundsEnabled
    @State private var noteFile: URL? = Preferences.shared.noteFile

    var body: some View {
        // La même vue que l'accueil, sans la zone d'essai : on ne découvre pas
        // la dictée depuis les Réglages. Les deux écrans posaient la même
        // question avec deux implémentations, et elles avaient déjà divergé.
        TriggerCard(showTrialSandbox: false)

        Card(title: "Où va le texte") {
            Note("Par défaut au curseur de l'application active. Le bouton "
                 + "« Notes » de la barre écrit dans ce fichier à la place, et "
                 + "il reste mémorisé quand vous revenez au curseur — y "
                 + "retourner ne coûte qu'un clic, même en pleine dictée.")
            Row(label: "Fichier de notes") {
                Text(noteFile?.lastPathComponent ?? "aucun")
                    .font(.system(size: 12))
                    .foregroundStyle(noteFile == nil ? .tertiary : .secondary)
            }
            ButtonRow {
                Button(noteFile == nil ? "Choisir…" : "Changer…") {
                    if let chosen = TargetWriter.chooseFile() {
                        prefs.noteFile = chosen
                        noteFile = chosen
                    }
                }
                if let url = noteFile {
                    Button("Afficher") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Oublier") { prefs.noteFile = nil; noteFile = nil }
                }
            }
        }

        Card(title: "Retours pendant la dictée") {
            FeatureSwitch(title: "Aperçu en direct dans la barre",
                          isOn: $prefs.livePreviewEnabled)
            Note("Affiche sous la barre ce que le moteur de macOS entend "
                 + "pendant que vous parlez. Indicatif : il n'a pas votre "
                 + "vocabulaire technique, donc le texte inséré peut différer.")
            FeatureSwitch(title: "Sons de début et de fin", isOn: $soundsEnabled)
                .onChange(of: soundsEnabled) { _, new in Feedback.soundsEnabled = new }
        }

        MicrophoneModeCard()

        LoginItemCard()

        // Le micro et l'accessibilité sont désormais portés par `TriggerCard`,
        // plus haut dans cette même page : les répéter ici ferait lire deux
        // fois le même état, et douter duquel des deux dit vrai.
        //
        // Reste la reconnaissance vocale, qui ne relève pas du déclencheur mais
        // du moteur — et seulement quand ce moteur est réellement en jeu.
        if PermissionsMonitor.shared.requiresSpeech {
            Card(title: "Moteur de la Dictée") {
                SpeechAccessRow()
                Note("Ce droit n'est demandé que parce que la **Dictée** de "
                     + "macOS est en service ici — pour écrire, pour l'aperçu "
                     + "en direct, ou pour la collecte.")
            }
        }

        VersionCard()
            .onAppear { noteFile = prefs.noteFile }
    }
}

/// Mode micro de macOS.
///
/// Il n'apparaissait que sur la barre d'enregistrement, ce qui donnait
/// l'impression d'un réglage de Sofler rangé au mauvais endroit. En réalité
/// **aucune application ne peut le changer** : c'est un réglage système,
/// commun à toutes les apps. Le dire ici évite de le chercher.
private struct MicrophoneModeCard: View {
    @State private var mode = AudioRecorder.microphoneModeLabel

    var body: some View {
        Card(title: "Micro") {
            Row(label: "Mode") {
                Text(mode).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Note("**L'isolement de la voix** retire le bruit autour de vous et "
                 + "améliore nettement la transcription en environnement "
                 + "bruyant.")
            Note("macOS ne laisse aucune application imposer ce mode : il vaut "
                 + "pour toutes à la fois, et c'est vous qui le choisissez.")
            // Pas de bouton ici, et c'est mesuré : `showSystemUserInterface`
            // n'ouvre rien tant qu'aucune capture n'est en cours. macOS ne
            // propose ce choix que pendant qu'une application utilise le
            // micro. Le bouton existait, ne faisait rien depuis les réglages,
            // et laissait croire à une panne.
            Note("Le choix ne s'offre que **pendant** qu'une application "
                 + "utilise le micro. Depuis la barre de Sofler, en pleine "
                 + "dictée, un clic sur le mode l'ouvre ; sinon, il est dans "
                 + "le Centre de contrôle, sous « Micro ».")
        }
        // Il change depuis le Centre de contrôle, sans nous prévenir.
        .onAppear { mode = AudioRecorder.microphoneModeLabel }
    }
}

/// Démarrage à l'ouverture de session.
///
/// L'état est relu à chaque affichage plutôt que mémorisé : ce réglage existe
/// aussi dans Réglages Système › Général › Ouverture, et l'utilisateur peut
/// l'y couper sans nous prévenir. Un interrupteur qui afficherait l'inverse de
/// la réalité serait pire que pas d'interrupteur du tout.
private struct LoginItemCard: View {
    @State private var enabled = LoginItem.isEnabled
    @State private var refused = false

    var body: some View {
        Card(title: "Démarrage") {
            FeatureSwitch(title: "Lancer Sofler à l'ouverture de session",
                          isOn: $enabled)
                .onChange(of: enabled) { _, wanted in
                    let actual = LoginItem.set(wanted)
                    refused = actual != wanted
                    // Recaler l'interrupteur sur ce que le système a vraiment
                    // fait, pas sur ce qu'on lui a demandé.
                    if actual != enabled { enabled = actual }
                }

            if refused, LoginItem.requiresApproval {
                Note("macOS a gardé le refus enregistré dans Réglages Système "
                     + "› Général › Ouverture : c'est là qu'il faut "
                     + "réautoriser Sofler.", warning: true)
                Button("Ouvrir Réglages Système › Ouverture") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            } else {
                Note("Sofler vit dans la barre de menus : s'il ne tourne pas, "
                     + "la touche de dictée ne fait rien, et rien n'indique "
                     + "que c'est la raison.")
            }
        }
        .onAppear { enabled = LoginItem.isEnabled }
    }
}

/// Version installée, et mise à jour.
///
/// Rien n'indique par ailleurs la version qu'on utilise : c'est le premier
/// renseignement que demande quiconque reçoit un rapport de bug.
private struct VersionCard: View {
    @State private var prefs = Preferences.shared
    @State private var checker = UpdateChecker.shared
    @State private var installer = UpdateInstaller.shared

    var body: some View {
        Card(title: "Version") {
            HStack(spacing: 8) {
                Text(UpdateChecker.buildLabel)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if checker.checking { ProgressView().controlSize(.small) }
            }

            if !UpdateChecker.isReleaseBuild {
                Note("Compilé depuis les sources : `\(UpdateChecker.gitDescribe)`. "
                     + "Les vérifications automatiques sont suspendues sur un "
                     + "build de développement, qui est presque toujours en "
                     + "avance sur la dernière release.")
            }

            if let update = checker.newer {
                Note("**La version \(update.version) est disponible.**")
                UpdateAction(update: update, installer: installer)
            }

            FeatureSwitch(title: "Vérifier automatiquement, une fois par jour",
                          isOn: $prefs.checksForUpdates)
            Note("Désactivé par défaut : tant que vous ne l'activez pas, "
                 + "Sofler ne contacte rien ni personne. Une fois activé, il "
                 + "demande à GitHub le numéro de la dernière version publiée "
                 + "— une adresse IP et rien d'autre, jamais ce que vous avez "
                 + "dicté. C'est la seule requête réseau que l'application "
                 + "sache faire.")

            HStack(spacing: 8) {
                Button("Vérifier maintenant") {
                    Task { await checker.check() }
                }
                .disabled(checker.checking)

                if let error = checker.lastError {
                    Text(error).font(.system(size: 11))
                        .foregroundStyle(Style.collecting)
                } else if checker.newer == nil, !checker.checking,
                          let date = checker.lastCheckedAt {
                    Text("À jour — vérifié \(date.formatted(.relative(presentation: .named))).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Le bouton « Mettre à jour », et ce qu'il devient pendant qu'il travaille.
///
/// Un seul bouton, qui va jusqu'au bout : télécharger, vérifier, remplacer,
/// relancer. La page GitHub reste offerte à côté, mais elle n'est plus le
/// chemin — c'est là qu'on va pour *lire* ce qui change, pas pour installer.
///
/// Chaque étape est nommée pendant qu'elle dure. Une barre de progression
/// muette, sur une opération qui remplace l'application qu'on est en train
/// d'utiliser, invite surtout à cliquer ailleurs pour voir.
private struct UpdateAction: View {
    let update: UpdateChecker.Release
    @Bindable var installer: UpdateInstaller

    var body: some View {
        switch installer.phase {
        case .idle:
            ready

        case .downloading(let fraction):
            step("Téléchargement… \(Int(fraction * 100)) %") {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Style.accent)
            }

        case .verifying:
            step("Vérification de la signature…")

        case .installing:
            step("Installation…")

        case .relaunching:
            step("Mise à jour posée. Sofler redémarre…")

        case .failed(let message):
            Note(message, warning: true)
            ButtonRow {
                Button("Réessayer") { installer.reset() }
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
        }
    }

    @ViewBuilder
    private var ready: some View {
        // L'obstacle est consulté avant d'offrir le bouton, jamais après le
        // clic : un dossier non inscriptible ou une copie signée ad hoc ne
        // s'arrangeront pas d'un second essai.
        if let obstacle = UpdateInstaller.obstacle {
            ButtonRow {
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
            Note(obstacle, warning: true)
        } else if update.asset == nil {
            ButtonRow {
                Button("Ouvrir la page de téléchargement") {
                    NSWorkspace.shared.open(update.page)
                }
            }
            Note("Cette release n'attache pas d'image disque : l'installation "
                 + "depuis l'application n'est pas possible pour celle-ci.",
                 warning: true)
        } else {
            HStack(spacing: 8) {
                Button("Mettre à jour") {
                    Task { await installer.install(update) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Style.accent)
                .controlSize(.small)

                Button("Voir ce qui change") {
                    NSWorkspace.shared.open(update.page)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Note("Tout se passe ici : le téléchargement, la vérification que "
                 + "la nouvelle version porte bien la même signature que "
                 + "celle-ci, le remplacement et le redémarrage. Vos réglages, "
                 + "votre corpus, le modèle et les autorisations restent en "
                 + "place — seule l'application est remplacée, en entier, sans "
                 + "rien laisser de l'ancienne.")
        }
    }

    /// Une étape en cours : ce qu'elle fait, dit en toutes lettres.
    @ViewBuilder
    private func step<Extra: View>(
        _ label: String, @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label).font(.system(size: 12))
            }
            extra()
        }
    }
}

// MARK: - Transcription

/// L'onglet Transcription n'est plus qu'un appel : tout son contenu est
/// partagé avec l'accueil. Cf. TranscriptionSettings.
private struct TranscriptionTab: View {
    var body: some View {
        TranscriptionSettings()
    }
}

// MARK: - Collecte

private struct CollectionTab: View {
    @State private var prefs = Preferences.shared
    @State private var stats = Corpus.Statistics()

    /// Le nom du moteur, et son état quand il ne peut rien produire ici.
    private func label(for choice: EngineChoice) -> String {
        choice.isAvailable(for: prefs.language)
            ? choice.fullLabel
            : "\(choice.fullLabel) — indisponible ici"
    }

    var body: some View {
        Card(title: "Collecte") {
            FeatureSwitch(title: "Archiver mes dictées", isOn: $prefs.corpusEnabled)
            Note("À chaque dictée, Sofler garde le texte produit par chaque "
                 + "moteur à partir du **même** audio. Ça sert à une seule "
                 + "chose : vous permettre de comparer les moteurs sur votre "
                 + "voix, votre vocabulaire et votre micro, au lieu de vous fier "
                 + "à des mesures faites sur celle de quelqu'un d'autre.\n\n"
                 + "**Tout reste sur votre Mac.** Rien n'est envoyé nulle part, "
                 + "ni à l'auteur de l'application ni à personne — il n'existe "
                 + "aucun serveur pour le recevoir. Vous pouvez ouvrir le "
                 + "dossier, le lire, et l'effacer quand vous voulez.")
        }

        if prefs.corpusEnabled {
            Card(title: "Ce qui est gardé") {
                OptionCheck(title: "Conserver aussi l'audio",
                            isOn: $prefs.corpusKeepsAudio)
                Note("Environ 2 Mo la minute, contre quelques kilo-octets de "
                     + "texte. Sans lui, impossible de réécouter une dictée pour "
                     + "arbitrer un désaccord entre deux moteurs.")

                Divider().opacity(0.25)
                Text("Transcrire aussi avec")
                    .font(.system(size: 12, weight: .medium))
                // `fullLabel`, pas `label` : celui-ci nomme la famille, donc
                // les deux versions de macOS afficheraient ici deux cases
                // rigoureusement identiques. C'est le seul écran où l'on
                // désigne un moteur précis plutôt qu'un fournisseur — on
                // coche « macOS · Dictée » pour comparer les deux versions
                // entre elles.
                ForEach(EngineChoice.allCases, id: \.self) { choice in
                    OptionCheck(title: label(for: choice), isOn: Binding(
                        get: { prefs.corpusEngines.contains(choice) },
                        set: { on in
                            if on { prefs.corpusEngines.insert(choice) }
                            else { prefs.corpusEngines.remove(choice) }
                        }))
                    .disabled(choice == prefs.engine)
                }
                Note("En plus du moteur qui écrit, et **après** insertion : la "
                     + "latence de dictée n'est jamais échangée contre de la "
                     + "collecte. Un moteur non coché n'est jamais chargé.")
                // Listé et non masqué : savoir qu'une version n'existe pas sur
                // cette machine est une information, une ligne absente n'en est
                // pas une. La case reste cochable — elle vaudra le jour où le
                // moteur sera là, et d'ici là rien ne tourne.
                if EngineChoice.allCases.contains(where: {
                    !$0.isAvailable(for: prefs.language)
                }) {
                    Note("Les moteurs marqués indisponibles ne sont pas "
                         + "exécutés et n'apparaissent pas dans le corpus : "
                         + "cochés d'avance, ils reprendront le jour où cette "
                         + "machine saura les faire tourner.")
                }
                if prefs.needsLocalEngine {
                    Label("Le service CrisperWhisper tourne — environ 3 Go en mémoire.",
                          systemImage: "memorychip")
                        .font(.system(size: 11))
                        .foregroundStyle(Style.collecting)
                }
            }

            Card(title: "Corpus") {
                Row(label: "État") {
                    Text(stats.summary).font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                // `stats` partait d'une structure vide que rien ne remplissait
                // : l'onglet annonçait « Corpus vide » quel qu'en soit le
                // contenu — le pire mensonge possible sur un écran dont le
                // seul rôle est de dire ce qui est gardé.
                .onAppear { stats = Corpus.shared.statistics() }
                ButtonRow {
                    Button("Afficher dans le Finder") { Corpus.shared.reveal() }
                    Button("Tout effacer") {
                        Corpus.shared.clear()
                        stats = Corpus.shared.statistics()
                    }
                    .disabled(stats.count == 0)
                }
            }
        }
    }
}

// MARK: - Historique

private struct HistoryTab: View {
    let history: TranscriptionHistory
    @State private var entries: [TranscriptionHistory.Entry] = []
    @State private var justCopied: UUID?

    var body: some View {
        Card(title: "Transcriptions récentes") {
            FeatureSwitch(title: "Conserver l'historique", isOn: Binding(
                get: { history.isEnabled },
                set: { history.isEnabled = $0; entries = history.entries }))

            if !history.isEnabled {
                Note("Rien n'est écrit. Les transcriptions passées ne sont pas "
                     + "conservées, même localement.")
            } else if entries.isEmpty {
                Note("Aucune pour l'instant")
            } else {
                ForEach(entries) { entry in
                    Divider().opacity(0.25)
                    HStack(spacing: 10) {
                        // Tronqué à une ligne : la fenêtre doit rester lisible
                        // d'un coup d'œil, pas devenir une liste qu'on fait
                        // défiler.
                        Text(entry.preview)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(entry.text)
                        Spacer(minLength: 8)
                        Text(entry.relativeAge)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            justCopied = entry.id
                        } label: {
                            Image(systemName: justCopied == entry.id
                                  ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(justCopied == entry.id
                                                 ? Style.accent : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Copier le texte entier")
                    }
                }
                Divider().opacity(0.25)
                ButtonRow {
                    Button("Effacer l'historique") {
                        history.clear()
                        entries = []
                    }
                }
            }
            Note("Le texte complet est copié, pas la version tronquée. "
                 + "L'historique reste aussi dans le menu de la barre.")
        }
        .onAppear { entries = history.entries }
    }
}
