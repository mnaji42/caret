// Dessine l'icône de Sofler et écrit un .iconset prêt pour iconutil.
//
// L'icône est du code plutôt qu'un fichier binaire déposé dans le dépôt : un
// .icns ne se relit pas, ne se diffe pas, et se perd le jour où on veut
// déplacer un trait de trois pixels. Ici chaque taille est redessinée à ses
// propres dimensions au lieu d'être réduite depuis 1024 — un trait de 2 px à
// 16 px reste net, là où une réduction le laisse gris et flou.
//
//     swift scripts/make-icon.swift <dossier.iconset>

import AppKit
import Foundation

// --- Le dessin ---------------------------------------------------------------
//
// Un caret — la barre d'insertion du texte — traversé d'ondes sonores. Pas un
// microphone : c'est le symbole de la dictée d'Apple, et une app qui demande
// l'accès au micro et à l'accessibilité a tout intérêt à ne pas être prise
// pour un composant du système. Le caret dit ce que fait Sofler et que ne
// fait pas la dictée d'Apple : le texte atterrit là où le curseur se trouve
// déjà, dans l'application qu'on a devant soi.

/// Le caret seul, en unités normalisées, centré sur (0,5 ; 0,5).
///
/// Rendu par trois rectangles arrondis qui se recouvrent plutôt que par un
/// tracé unique : les jonctions sont invisibles puisque tout est de la même
/// couleur opaque, et les proportions se règlent indépendamment.
func caretPath(_ s: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let cx = s / 2, cy = s / 2
    let height = 0.300 * s      // hauteur totale du I
    let stem = 0.055 * s        // épaisseur du fût
    let serif = 0.150 * s       // largeur des empattements
    let serifH = 0.050 * s      // épaisseur des empattements
    let r = stem / 2.4          // les angles restent doux sans être des pilules

    path.append(NSBezierPath(
        roundedRect: NSRect(x: cx - stem / 2, y: cy - height / 2,
                            width: stem, height: height),
        xRadius: r, yRadius: r))
    for y in [cy - height / 2, cy + height / 2 - serifH] {
        path.append(NSBezierPath(
            roundedRect: NSRect(x: cx - serif / 2, y: y,
                                width: serif, height: serifH),
            xRadius: r, yRadius: r))
    }
    return path
}

/// Les ondes : deux arcs de chaque côté, centrés sur le caret.
///
/// Symétriques et non dirigés vers le caret. Un seul côté raconterait « la
/// voix entre », mais déséquilibre la composition et, à 16 px, ressemble à
/// une icône de réseau. Symétriques, les arcs se lisent comme de l'activité
/// autour du texte.
func wavePaths(_ s: CGFloat) -> [(NSBezierPath, CGFloat)] {
    let c = NSPoint(x: s / 2, y: s / 2)
    var out: [(NSBezierPath, CGFloat)] = []
    // Rayon, opacité. L'arc extérieur est plus pâle : la même densité sur les
    // deux donnerait une cible concentrique, pas une propagation.
    for (radius, alpha) in [(0.175 * s, CGFloat(0.95)), (0.250 * s, CGFloat(0.55))] {
        for (start, end) in [(-42.0, 42.0), (138.0, 222.0)] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: radius,
                          startAngle: CGFloat(start), endAngle: CGFloat(end))
            arc.lineWidth = 0.045 * s
            arc.lineCapStyle = .round
            out.append((arc, alpha))
        }
    }
    return out
}

/// L'icône complète, à la taille demandée.
func drawIcon(size s: CGFloat, into context: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // --- le carré arrondi ---------------------------------------------------
    // Proportions de la grille macOS depuis Big Sur : l'art occupe 824 pt d'un
    // canevas de 1024, rayon 185,4. Une icône qui remplit tout le canevas
    // paraît plus grosse que ses voisines dans le Dock et le Finder.
    let inset = 100.0 / 1024.0 * s
    let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = 185.4 / 1024.0 * s
    let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

    context.saveGState()
    squircle.addClip()
    // Le teal de Style.accent, en dégradé : la teinte de l'app, reconnaissable
    // avant même qu'on distingue la forme.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.35, green: 0.82, blue: 0.91, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.40, blue: 0.52, alpha: 1),
    ])!
    gradient.draw(in: box, angle: -90)
    context.restoreGState()

    // --- ondes puis caret ---------------------------------------------------
    for (arc, alpha) in wavePaths(s) {
        NSColor(white: 1, alpha: alpha).setStroke()
        arc.stroke()
    }
    NSColor.white.setFill()
    caretPath(s).fill()
}

// --- Sortie ------------------------------------------------------------------

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    drawIcon(size: CGFloat(size), into: context.cgContext)
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage : swift make-icon.swift <dossier.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Les noms que iconutil exige. Chaque paire taille/échelle est redessinée, pas
// interpolée depuis la précédente.
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try render(size: points * scale).write(to: out.appendingPathComponent(name))
}
print("▸ \(out.lastPathComponent) — 10 rendus")
