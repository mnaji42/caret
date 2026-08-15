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
        window.setContentSize(NSSize(width: 540, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
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
        case general, transcription, collection, history

        var label: String {
            switch self {
            case .general: "Général"
            case .transcription: "Transcription"
            case .collection: "Collecte"
            case .history: "Historique"
            }
        }

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .transcription: "waveform"
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
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                let active = item == tab
                Label(item.label, systemImage: item.symbol)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Style.accent : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? Style.accent.opacity(0.18) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { tab = item }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

// MARK: - Général

private struct GeneralTab: View {
    @State private var prefs = Preferences.shared
    @State private var soundsEnabled = Feedback.soundsEnabled
    @State private var noteFile: URL? = Preferences.shared.noteFile

    var body: some View {
        Card(title: "Déclencheur") {
            FeatureSwitch(title: "Dicter avec la touche Option seule",
                          isOn: $prefs.triggerEnabled)
            Row(label: "Côté") {
                PillPicker(options: [(ModifierKeyMonitor.Side.right, "Droite"),
                                     (ModifierKeyMonitor.Side.left, "Gauche")],
                           selection: $prefs.triggerSide,
                           disabled: !prefs.triggerEnabled)
            }
            Note("Option reste utilisable normalement : le déclenchement n'a "
                 + "lieu que si aucune autre touche n'est pressée entre-temps.")

            Divider().opacity(0.25)
            Row(label: "Raccourci clavier") {
                ShortcutRecorder(shortcut: $prefs.dictateShortcut) { _ in }
                    .frame(width: 150, height: 26)
            }
            Note("Cliquez puis tapez la combinaison voulue. Elle fonctionne "
                 + "même sans l'autorisation d'Accessibilité, contrairement à la "
                 + "touche Option seule. macOS refuse les raccourcis sans "
                 + "Contrôle ni Commande.")
        }

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
        .onAppear { noteFile = prefs.noteFile }
    }
}

// MARK: - Transcription

private struct TranscriptionTab: View {
    @State private var prefs = Preferences.shared
    @State private var localReady = false
    @State private var localName = "—"
    @State private var lexiconText = ""

    var body: some View {
        Card(title: "Langue") {
            PillPicker(options: Preferences.languages.map { ($0.0, $0.1) },
                       selection: $prefs.language)
            Note("Vaut pour tous les moteurs. Un seul choix à la fois : les "
                 + "modèles imposent une langue par passage, et « automatique » "
                 + "se trompe précisément sur les phrases qui en mêlent deux.")
        }

        Card(title: "Moteur") {
            ChoiceRow(title: EngineChoice.apple.label,
                      subtitle: EngineChoice.apple.explanation,
                      selected: prefs.engine == .apple,
                      hasDetail: false,
                      action: { prefs.engine = .apple }) { EmptyView() }

            ChoiceRow(title: EngineChoice.crisperWhisper.label,
                      subtitle: EngineChoice.crisperWhisper.explanation,
                      selected: prefs.engine == .crisperWhisper,
                      action: { prefs.engine = .crisperWhisper }) {
                Row(label: "Mode par défaut") {
                    PillPicker(options: [(TranscriptionMode.intended, "Texte nettoyé"),
                                         (TranscriptionMode.verbatim, "Mot à mot")],
                               selection: $prefs.defaultMode)
                }
                Row(label: "Service") {
                    Text(localReady ? localName : "hors ligne")
                        .font(.system(size: 12))
                        .foregroundStyle(localReady ? Color.secondary : Color.red)
                }
                if !localReady {
                    Note("Le modèle n'est pas installé, ou le service met "
                         + "quelques secondes à charger. Lancez `scripts/setup.sh` "
                         + "une fois : Sofler démarre et arrête ensuite le "
                         + "service tout seul.", warning: true)
                }

                Divider().opacity(0.25)
                Text("Vocabulaire technique")
                    .font(.system(size: 12, weight: .medium))
                OptionCheck(title: "Utiliser la liste intégrée",
                            isOn: $prefs.useDefaultLexicon)
                if !prefs.useDefaultLexicon {
                    TextEditor(text: $lexiconText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.2)))
                        .onChange(of: lexiconText) { _, new in
                            prefs.lexicon = new.split(separator: "\n")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    Note("Un terme par ligne. Gardez la liste courte : plus elle "
                         + "est longue, plus le modèle risque d'y piocher un mot "
                         + "sur un passage où vous n'avez rien dit.")
                }
            }

            Note("Le mode et le vocabulaire n'apparaissent que sous "
                 + "CrisperWhisper parce qu'ils n'existent que là : le moteur de "
                 + "macOS n'a qu'un rendu, et mesuré sur de vrais "
                 + "enregistrements, lui fournir un vocabulaire ne change pas "
                 + "sa sortie d'un caractère.")
        }
        .task {
            lexiconText = prefs.lexicon.joined(separator: "\n")
            let engine = SocketSpeechEngine()
            localReady = await engine.isReady()
            if localReady { localName = await engine.displayName }
        }
    }
}

// MARK: - Collecte

private struct CollectionTab: View {
    @State private var prefs = Preferences.shared
    @State private var stats = Corpus.Statistics()

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
                ForEach(EngineChoice.allCases, id: \.self) { choice in
                    OptionCheck(title: choice.label, isOn: Binding(
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
