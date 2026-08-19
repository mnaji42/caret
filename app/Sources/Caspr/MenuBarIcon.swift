import AppKit

/// Le glyphe de la barre de menus, dessiné plutôt qu'emprunté.
///
/// Il utilisait `mic`, `mic.fill` et `mic.badge.plus` — c'est-à-dire très
/// exactement les symboles de la dictée d'Apple. Deux problèmes. Dans une
/// barre de menus, l'utilisateur ne distinguait pas Caspr d'un élément du
/// système ; et une application qui réclame le micro *et* le droit de piloter
/// le clavier a tout intérêt à s'annoncer comme elle-même.
///
/// Le motif est le caret, la barre d'insertion du texte, parce que c'est ce
/// que Caspr fait de particulier : le texte atterrit là où le curseur est
/// déjà. Les ondes ne sont pas décoratives, elles portent l'état — elles
/// n'apparaissent que pendant l'écoute. Un coup d'œil suffit alors à savoir
/// si le micro tourne, ce qui est la seule question urgente que pose une app
/// de dictée.
///
/// Dessiné à l'exécution et non chargé depuis un PNG : le `drawingHandler` est
/// rappelé à chaque rendu, donc à la résolution réelle de l'écran, et les
/// variantes d'état ne coûtent pas un fichier chacune.
enum MenuBarIcon {
    /// 18 pt de haut, la hauteur utile de la barre de menus. La largeur est
    /// plus généreuse pour loger les ondes sans les coller au bord.
    private static let size = NSSize(width: 20, height: 18)

    /// - Parameters:
    ///   - listening: le micro tourne — fait apparaître les ondes.
    ///   - dimmed: transcription en cours. Atténué plutôt que remplacé par un
    ///     symbole différent : l'œil lit « la même chose, en attente » sans
    ///     avoir à réapprendre une forme.
    ///   - locked: la dictée part vers un fichier et non vers le curseur. Le
    ///     point rappelle que le texte n'ira pas là où on l'attend — la
    ///     mésaventure classique quand on a oublié le réglage.
    static func image(listening: Bool, dimmed: Bool = false,
                      locked: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let alpha: CGFloat = dimmed ? 0.45 : 1
            NSColor.black.withAlphaComponent(alpha).setFill()
            NSColor.black.withAlphaComponent(alpha).setStroke()

            caret().fill()
            if listening { for arc in waves() { arc.stroke() } }
            if locked { lockDot().fill() }
            return true
        }
        // Sans ça le glyphe reste noir sur une barre sombre, donc invisible.
        // `isTemplate` laisse macOS le teinter selon l'apparence et l'inverser
        // quand le menu est ouvert.
        image.isTemplate = true
        return image
    }

    // MARK: - Tracés

    private static func caret() -> NSBezierPath {
        let path = NSBezierPath()
        let cx = size.width / 2, cy = size.height / 2
        let height: CGFloat = 11, stem: CGFloat = 1.8
        let serif: CGFloat = 6, serifH: CGFloat = 1.8

        path.append(NSBezierPath(
            roundedRect: NSRect(x: cx - stem / 2, y: cy - height / 2,
                                width: stem, height: height),
            xRadius: 0.6, yRadius: 0.6))
        for y in [cy - height / 2, cy + height / 2 - serifH] {
            path.append(NSBezierPath(
                roundedRect: NSRect(x: cx - serif / 2, y: y,
                                    width: serif, height: serifH),
                xRadius: 0.6, yRadius: 0.6))
        }
        return path
    }

    /// Un seul arc de chaque côté, pas deux comme sur l'icône de l'app.
    ///
    /// À 18 pt, deux arcs concentriques se confondent en une tache : la barre
    /// de menus demande moins de détail que le Dock, pas la même image
    /// réduite.
    private static func waves() -> [NSBezierPath] {
        let c = NSPoint(x: size.width / 2, y: size.height / 2)
        return [(-38.0, 38.0), (142.0, 218.0)].map { start, end in
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: 6.6,
                          startAngle: CGFloat(start), endAngle: CGFloat(end))
            arc.lineWidth = 1.5
            arc.lineCapStyle = .round
            return arc
        }
    }

    /// À hauteur du milieu du caret, et non en bas à droite comme un badge
    /// d'application. Posé sous la ligne de base, le point se lisait comme une
    /// ponctuation — le glyphe entier devenait « I. » — au lieu d'un état.
    private static func lockDot() -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: size.width / 2 + 4.2,
                                    y: size.height / 2 - 1.5,
                                    width: 3, height: 3))
    }
}
