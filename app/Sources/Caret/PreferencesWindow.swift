import AppKit
import SwiftUI

/// Fenêtre de réglages.
///
/// Caret est une app d'arrière-plan sans Dock : ouvrir une fenêtre demande de
/// l'activer explicitement, sinon elle apparaît derrière tout le reste. On
/// repasse en arrière-plan à la fermeture pour ne pas rester dans le
/// sélecteur d'applications.
@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages de Caret"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct PreferencesView: View {
    @State private var prefs = Preferences.shared
    @State private var lexiconText: String = ""

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
        .onAppear { lexiconText = prefs.lexicon.joined(separator: "\n") }
    }
}
