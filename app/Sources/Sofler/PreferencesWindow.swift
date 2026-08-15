import AppKit
import SwiftUI

/// Fenêtre de réglages.
///
/// Sofler est une app d'arrière-plan sans Dock : ouvrir une fenêtre demande de
/// l'activer explicitement, sinon elle apparaît derrière tout le reste. On
/// repasse en arrière-plan à la fermeture pour ne pas rester dans le
/// sélecteur d'applications.
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

        let hosting = NSHostingController(
            rootView: PreferencesView(history: history))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages de Sofler"
        window.styleMask = [.titled, .closable]
        // La taille vient de la vue : les onglets la fixent eux-mêmes.
        window.setContentSize(NSSize(width: 520, height: 600))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Tous les réglages au même endroit.
///
/// Le menu de la barre reste volontairement court — il sert aux gestes du
/// quotidien, pas à la configuration. Un réglage qui n'existe que dans un menu
/// déroulant est introuvable dès qu'on ne se souvient plus de son nom.
/// Tous les réglages, en onglets.
///
/// Le menu de la barre reste volontairement court — il sert aux gestes du
/// quotidien. Ici on regroupe par question posée : *avec quoi je transcris*,
/// *comment je déclenche*, *ce que je garde*. Une seule liste déroulante de
/// quinze réglages obligeait à tout parcourir pour en trouver un.
private struct PreferencesView: View {
    let history: TranscriptionHistory

    var body: some View {
        TabView {
            EngineTab().tabItem { Label("Moteur", systemImage: "waveform") }
            DictationTab().tabItem { Label("Dictée", systemImage: "mic") }
            CollectionTab().tabItem { Label("Collecte", systemImage: "tray.full") }
            HistoryTab(history: history)
                .tabItem { Label("Historique", systemImage: "clock") }
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - Moteur

private struct EngineTab: View {
    @State private var prefs = Preferences.shared
    @State private var localReady = false
    @State private var localName = "—"

    var body: some View {
        Form {
            Section("Moteur de transcription") {
                Picker("Écrire avec", selection: $prefs.engine) {
                    ForEach(EngineChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(prefs.engine.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if prefs.engine == .crisperWhisper {
                    LabeledContent("Service") {
                        Text(localReady ? localName : "hors ligne")
                            .foregroundStyle(localReady ? Color.primary : Color.red)
                    }
                    if !localReady {
                        Text("Le modèle n'est pas installé ou le service ne "
                             + "tourne pas. Lancez `scripts/setup.sh` une fois ; "
                             + "Sofler démarre et arrête ensuite le service tout seul.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Vocabulaire technique") {
                if !prefs.engine.honoursLexicon {
                    Text("Le moteur de macOS ne tient pas compte d'un "
                         + "vocabulaire : mesuré sur de vrais enregistrements, "
                         + "lui fournir la liste ne change pas sa sortie. Ces "
                         + "réglages ne s'appliquent qu'à CrisperWhisper.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LexiconEditor(prefs: $prefs)
            }
        }
        .formStyle(.grouped)
        .task {
            let engine = SocketSpeechEngine()
            localReady = await engine.isReady()
            localName = await engine.displayName
        }
    }
}

private struct LexiconEditor: View {
    @Binding var prefs: Preferences
    @State private var text = ""

    var body: some View {
        Toggle("Utiliser la liste intégrée", isOn: $prefs.useDefaultLexicon)
        if !prefs.useDefaultLexicon {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: text) { _, new in
                    prefs.lexicon = new.split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            Text("Un terme par ligne. Gardez la liste courte : plus elle est "
                 + "longue, plus le modèle risque d'y piocher un mot sur un "
                 + "passage où vous n'avez rien dit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dictée

private struct DictationTab: View {
    @State private var prefs = Preferences.shared
    @State private var soundsEnabled = Feedback.soundsEnabled
    @State private var noteFile: URL? = Preferences.shared.noteFile

    var body: some View {
        Form {
            Section("Déclencheur") {
                Toggle("Dicter avec la touche Option seule", isOn: $prefs.triggerEnabled)
                Picker("Côté", selection: $prefs.triggerSide) {
                    Text("Option droite").tag(ModifierKeyMonitor.Side.right)
                    Text("Option gauche").tag(ModifierKeyMonitor.Side.left)
                }
                .disabled(!prefs.triggerEnabled)
                Text("Option reste utilisable normalement : le déclenchement "
                     + "n'a lieu que si aucune autre touche n'est pressée "
                     + "entre-temps. \(HotkeyMonitor.Shortcut.dictate.label) "
                     + "fonctionne toujours, et ne demande pas l'Accessibilité.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Mode par défaut", selection: $prefs.defaultMode) {
                    Text("Texte nettoyé").tag(TranscriptionMode.intended)
                    Text("Mot à mot").tag(TranscriptionMode.verbatim)
                }
                .disabled(!prefs.engine.hasModes)
                Picker("Langue", selection: $prefs.language) {
                    ForEach(Preferences.languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                if !prefs.engine.hasModes {
                    Text("Le moteur de macOS n'a qu'un rendu : le choix du mode "
                         + "ne s'applique qu'à CrisperWhisper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notes") {
                LabeledContent("Fichier") {
                    Text(noteFile?.lastPathComponent ?? "aucun")
                        .foregroundStyle(noteFile == nil ? .secondary : .primary)
                }
                HStack {
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
                Text("Le bouton « Notes » de la barre écrit dans ce fichier, et "
                     + "il reste mémorisé quand vous revenez au curseur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Retour") {
                Toggle("Aperçu en direct dans la barre", isOn: $prefs.livePreviewEnabled)
                Toggle("Sons de début et de fin", isOn: $soundsEnabled)
                    .onChange(of: soundsEnabled) { _, new in Feedback.soundsEnabled = new }
            }
        }
        .formStyle(.grouped)
        .onAppear { noteFile = prefs.noteFile }
    }
}

// MARK: - Collecte

private struct CollectionTab: View {
    @State private var prefs = Preferences.shared
    @State private var stats = Corpus.Statistics()

    var body: some View {
        Form {
            Section("Collecte") {
                Toggle("Archiver les dictées pour comparer les moteurs",
                       isOn: $prefs.corpusEnabled)
                Toggle("Conserver aussi l'audio", isOn: $prefs.corpusKeepsAudio)
                    .disabled(!prefs.corpusEnabled)
                Text("L'audio coûte environ 2 Mo la minute, contre quelques "
                     + "kilo-octets de texte — d'où la case séparée. Sans lui, "
                     + "impossible de rejouer une dictée pour arbitrer un "
                     + "désaccord entre moteurs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcrire aussi avec") {
                ForEach(EngineChoice.allCases, id: \.self) { choice in
                    Toggle(choice.label, isOn: Binding(
                        get: { prefs.corpusEngines.contains(choice) },
                        set: { on in
                            if on { prefs.corpusEngines.insert(choice) }
                            else { prefs.corpusEngines.remove(choice) }
                        }))
                    .disabled(!prefs.corpusEnabled || choice == prefs.engine)
                }
                Text("En plus du moteur qui écrit, et **après** insertion : "
                     + "la latence de dictée n'est jamais échangée contre de "
                     + "la collecte. Un moteur non coché n'est jamais chargé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if prefs.needsLocalEngine {
                    Label("Le service CrisperWhisper tourne — environ 3 Go en mémoire.",
                          systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Corpus") {
                LabeledContent("État") { Text(stats.summary) }
                HStack {
                    Button("Afficher dans le Finder") { Corpus.shared.reveal() }
                    Button("Tout effacer") {
                        Corpus.shared.clear()
                        stats = Corpus.shared.statistics()
                    }
                    .disabled(stats.count == 0)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { stats = Corpus.shared.statistics() }
    }
}

// MARK: - Historique

private struct HistoryTab: View {
    let history: TranscriptionHistory
    @State private var entries: [TranscriptionHistory.Entry] = []
    @State private var justCopied: UUID?

    var body: some View {
        Form {
            Section("Transcriptions récentes") {
                Toggle("Conserver l'historique", isOn: Binding(
                    get: { history.isEnabled },
                    set: { history.isEnabled = $0; entries = history.entries }))

                if entries.isEmpty {
                    Text(history.isEnabled ? "Aucune pour l'instant"
                                           : "Historique désactivé")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            // Tronqué à une ligne : la fenêtre doit rester
                            // lisible d'un coup d'œil, pas devenir une liste
                            // qu'on fait défiler.
                            Text(entry.preview)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(entry.text)
                            Spacer()
                            Text(entry.relativeAge)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                                justCopied = entry.id
                            } label: {
                                Image(systemName: justCopied == entry.id
                                      ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copier le texte entier")
                        }
                    }
                    Button("Effacer l'historique") {
                        history.clear()
                        entries = []
                    }
                }
                Text("Le texte complet est copié, pas la version tronquée. "
                     + "L'historique reste aussi dans le menu de la barre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { entries = history.entries }
    }
}
