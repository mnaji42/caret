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
        window.setContentSize(NSSize(width: 500, height: 640))
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
private struct PreferencesView: View {
    let history: TranscriptionHistory
    @State private var prefs = Preferences.shared
    @State private var entries: [TranscriptionHistory.Entry] = []
    @State private var justCopied: UUID?
    @State private var lexiconText: String = ""
    @State private var soundsEnabled = Feedback.soundsEnabled
    @State private var corpusStats = Corpus.Statistics()
    @State private var noteFile: URL? = Preferences.shared.noteFile
    @State private var engineName = "recherche du moteur…"

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
                     + "n'a lieu que si aucune autre touche n'est pressée entre-temps. "
                     + "\(HotkeyMonitor.Shortcut.dictate.label) fonctionne toujours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transcription") {
                Picker("Mode par défaut", selection: $prefs.defaultMode) {
                    Text("Texte nettoyé").tag(TranscriptionMode.intended)
                    Text("Mot à mot").tag(TranscriptionMode.verbatim)
                }
                Picker("Langue", selection: $prefs.language) {
                    ForEach(Preferences.languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                Text("« Texte nettoyé » écrit les nombres en chiffres — « 500 » "
                     + "et non « cinq cents ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Aperçu en direct") {
                Toggle("Afficher ce qui est entendu pendant la dictée",
                       isOn: $prefs.livePreviewEnabled)
                Text("Reconnaissance en flux par le moteur de macOS, affichée "
                     + "sous la barre. Indicative : elle n'utilise pas votre "
                     + "vocabulaire technique, donc le texte inséré ne sera pas "
                     + "exactement celui affiché.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Button("Oublier") {
                            prefs.noteFile = nil
                            noteFile = nil
                        }
                    }
                }
                Text("Le bouton « Notes » de la barre écrit dans ce fichier. Il "
                     + "reste mémorisé quand vous revenez au curseur, donc y "
                     + "retourner ne coûte qu'un clic — même en pleine dictée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Collecte") {
                Toggle("Archiver les dictées pour comparer les moteurs",
                       isOn: $prefs.corpusEnabled)
                Toggle("Conserver aussi l'audio", isOn: $prefs.corpusKeepsAudio)
                    .disabled(!prefs.corpusEnabled)
                LabeledContent("État") { Text(corpusStats.summary) }
                HStack {
                    Button("Afficher dans le Finder") { Corpus.shared.reveal() }
                    Button("Tout effacer") {
                        Corpus.shared.clear()
                        corpusStats = Corpus.shared.statistics()
                    }
                    .disabled(corpusStats.count == 0)
                }
                Text("Chaque dictée devient une ligne JSON avec les trois "
                     + "transcriptions issues du même audio. L'audio coûte "
                     + "environ 2 Mo la minute, d'où la case séparée.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                                NSPasteboard.general.setString(entry.text,
                                                               forType: .string)
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

            Section("Moteur") {
                LabeledContent("Modèle") { Text(engineName) }
            }

            Section("Retour") {
                Toggle("Sons de début et de fin", isOn: $soundsEnabled)
                    .onChange(of: soundsEnabled) { _, new in
                        Feedback.soundsEnabled = new
                    }
            }

            Section("Vocabulaire technique") {
                Toggle("Utiliser la liste intégrée", isOn: $prefs.useDefaultLexicon)
                if !prefs.useDefaultLexicon {
                    TextEditor(text: $lexiconText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .border(Color.secondary.opacity(0.3))
                        .onChange(of: lexiconText) { _, new in
                            prefs.lexicon = new
                                .split(separator: "\n")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    Text("Un terme par ligne. Ces mots sont privilégiés au "
                         + "décodage : c'est ce qui fait sortir « useEffect » plutôt "
                         + "que « use effect ». Gardez la liste courte — plus elle "
                         + "est longue, plus le modèle risque d'y piocher un mot sur "
                         + "un passage où vous n'avez rien dit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            lexiconText = prefs.lexicon.joined(separator: "\n")
            corpusStats = Corpus.shared.statistics()
            noteFile = prefs.noteFile
            entries = history.entries
        }
        .task { engineName = await SocketSpeechEngine().displayName }
    }
}
