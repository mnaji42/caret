import AppKit

/// Où atterrit le texte transcrit.
///
/// Par défaut au curseur de l'application active. Une fois verrouillé sur un
/// fichier, tout y est ajouté quoi que fasse le curseur — on continue de
/// travailler normalement et les notes s'accumulent au bon endroit.
///
/// Le verrou vise un **fichier**, pas un champ texte, et c'est délibéré.
/// Retenir un `AXUIElement` paraît plus direct mais casse vite : la référence
/// devient caduque dès que l'onglet change, que la fenêtre se ferme ou que
/// l'éditeur recycle sa vue. Et les éditeurs qui comptent ici — Cursor,
/// VS Code — sont des applications Electron dont l'arbre d'accessibilité
/// n'expose pas de champ inscriptible fiable. Écrire dans le fichier
/// fonctionne toujours, l'éditeur recharge tout seul, et ça marche même
/// fenêtre fermée.
enum DictationTarget: Equatable {
    case caret
    case file(URL)

    var isLocked: Bool {
        if case .file = self { return true }
        return false
    }

    var fileURL: URL? {
        if case .file(let url) = self { return url }
        return nil
    }

    var displayName: String {
        switch self {
        case .caret: "Curseur de l'app active"
        case .file(let url): url.lastPathComponent
        }
    }
}

/// Ajoute le texte dicté à un fichier.
@MainActor
enum TargetWriter {
    enum WriteError: LocalizedError {
        case notWritable(String)

        var errorDescription: String? {
            switch self {
            case .notWritable(let name):
                return "Écriture impossible dans \(name). Vérifier les droits du fichier."
            }
        }
    }

    /// Deux sauts de ligne entre les entrées.
    ///
    /// Un seul saut fusionne les paragraphes en Markdown, ce qui collerait les
    /// notes les unes aux autres. Deux les séparent visuellement et donnent
    /// des paragraphes distincts au rendu.
    private static let separator = "\n\n"

    static func append(_ text: String, to url: URL) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        // Ne pas ouvrir un fichier vide par des lignes blanches, et ne pas
        // doubler celles qui s'y trouvent déjà.
        var prefix = separator
        if existing.isEmpty {
            prefix = ""
        } else if existing.hasSuffix(separator) {
            prefix = ""
        } else if existing.hasSuffix("\n") {
            prefix = "\n"
        }

        let updated = existing + prefix + trimmed + "\n"
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.notWritable(url.lastPathComponent)
        }
    }

    /// Fichier ouvert dans l'application active, si elle en expose un.
    ///
    /// Beaucoup d'applications publient le chemin de leur document courant via
    /// l'accessibilité. Quand c'est le cas, verrouiller ne demande aucun
    /// sélecteur : on pose le curseur dans le fichier et on verrouille.
    static func frontmostDocument() -> URL? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXFocusedWindowAttribute as CFString, &window) == .success,
            let focused = window else { return nil }

        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused as! AXUIElement, kAXDocumentAttribute as CFString,
            &document) == .success,
            let path = document as? String, !path.isEmpty else { return nil }

        // Le chemin arrive en file:// chez la plupart, en chemin brut chez
        // d'autres.
        let url = path.hasPrefix("file://")
            ? URL(string: path)
            : URL(fileURLWithPath: path)
        guard let url else { return nil }

        // Validation stricte, sinon on écrit n'importe où. Certaines
        // applications publient un attribut vide ou tronqué : une première
        // version acceptait « / », qui existe bel et bien et passait le simple
        // test d'existence, d'où une cible verrouillée sur la racine du disque.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path,
                                             isDirectory: &isDirectory),
              !isDirectory.boolValue,
              !url.lastPathComponent.isEmpty,
              url.lastPathComponent != "/",
              FileManager.default.isWritableFile(atPath: url.path)
        else { return nil }

        return url
    }

    /// Sélecteur de fichier, pour les applications qui ne publient rien.
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choisir le fichier de destination"
        panel.message = "Les transcriptions seront ajoutées à la fin de ce fichier."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
