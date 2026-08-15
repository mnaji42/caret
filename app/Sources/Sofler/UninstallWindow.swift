import AppKit
import SwiftUI

/// La fenêtre de désinstallation.
///
/// Une fenêtre à elle, ni les réglages ni l'accueil : on n'entre pas ici par
/// hasard, et on ne doit pas tomber dessus en cherchant autre chose.
@MainActor
final class UninstallWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: UninstallView(onCancel: { [weak self] in self?.close() }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Désinstaller Sofler"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(NSSize(width: 560, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        // Cf. Onboarding.swift : sans ça la fenêtre s'efface dès que Sofler
        // n'est plus l'application active.
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

// MARK: - Vue

private struct UninstallView: View {
    let onCancel: () -> Void

    @State private var selected: Set<Uninstall.Item> = Set(
        Uninstall.Item.allCases.filter(\.checkedByDefault))
    @State private var report: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(report == nil ? "Désinstaller Sofler" : "Sofler est désinstallé")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 28)
                .padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report { summary(report) } else { chooser }
                }
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

    // MARK: Choix

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("L'application part dans tous les cas. Choisissez ce qui "
                 + "s'en va avec elle.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            Card(title: "à retirer aussi") {
                ForEach(Uninstall.Item.allCases) { item in
                    let present = Uninstall.isPresent(item)
                    VStack(alignment: .leading, spacing: 3) {
                        OptionCheck(title: item.label, isOn: Binding(
                            get: { selected.contains(item) },
                            set: { on in
                                if on { selected.insert(item) } else { selected.remove(item) }
                            }))
                        .disabled(!present)

                        HStack(spacing: 6) {
                            Text(Uninstall.detail(for: item))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(present ? Color.secondary : Color.secondary.opacity(0.5))
                        }
                        .padding(.leading, 20)

                        Note(item.explanation, warning: item.irreversible && selected.contains(item))
                            .padding(.leading, 20)
                    }
                    .opacity(present ? 1 : 0.45)

                    if item != Uninstall.Item.allCases.last {
                        Divider().opacity(0.25)
                    }
                }
            }

            if selected.contains(.corpus), Corpus.shared.statistics().count > 0 {
                Card(title: "attention") {
                    Note("Vous avez coché **\(Corpus.shared.statistics().count) "
                         + "dictées archivées**. Elles vont à la corbeille, "
                         + "donc elles sont récupérables tant que vous ne "
                         + "l'avez pas vidée — mais rien ne permettrait de les "
                         + "reconstituer ensuite.", warning: true)
                }
            }

            Card(title: "ce qui n'est jamais touché") {
                Note("**Votre fichier de notes.** S'il en existe un, c'est "
                     + "votre document : Sofler y écrivait, il ne lui "
                     + "appartient pas.")
                Note("**Tout part à la corbeille**, jamais en suppression "
                     + "définitive. Vous gardez la main jusqu'à ce que vous la "
                     + "vidiez.")
            }
        }
    }

    // MARK: Compte rendu

    private func summary(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "ce qui a été fait") {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("✗") ? Style.collecting : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !selected.contains(.corpus), Corpus.shared.statistics().count > 0 {
                Card(title: "ce qui reste") {
                    Note("Vos dictées archivées sont toujours là, dans "
                         + "`~/Library/Application Support/Sofler`. "
                         + "Réinstaller Sofler les retrouvera.")
                }
            }

            Note("Merci de l'avoir essayé.")
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            if report == nil {
                Button("Annuler", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Désinstaller") { report = Uninstall.perform(selected) }
                    .buttonStyle(.borderedProminent)
                    .tint(Style.collecting)
            } else {
                Button("Quitter Sofler") { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(Style.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}
