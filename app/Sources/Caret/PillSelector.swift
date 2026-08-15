import AppKit

/// Sélecteur à deux ou trois valeurs, dessiné à la main.
///
/// `NSSegmentedControl` a été essayé d'abord, et écarté pour une raison
/// mesurée : en style `.capsule`, `selectedSegmentBezelColor` est ignoré — le
/// segment actif reste du gris système. Sans teinte, l'état actif se distingue
/// à peine de l'inactif, ce qui vide de son sens l'idée même de montrer l'état
/// plutôt que l'action.
///
/// Le contrôle vit dans un panneau qui ne devient **jamais** fenêtre clé, pour
/// que le curseur de l'utilisateur ne bouge pas. Tout clic y est donc un
/// « premier clic », que `NSControl` ignore par défaut : d'où
/// `acceptsFirstMouse` sur chaque segment, sans quoi il faudrait cliquer deux
/// fois.
@MainActor
final class PillSelector: NSView {
    var onSelect: ((Int) -> Void)?

    private let accent: NSColor
    private var buttons: [SegmentButton] = []
    private(set) var selectedIndex = 0

    private static let height: CGFloat = 32
    private static let inset: CGFloat = 4

    init(labels: [String], accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Le groupe flotte au-dessus du panneau principal, donc au-dessus de
        // n'importe quelle fenêtre : il lui faut son propre verre, sans quoi
        // un simple fond translucide serait illisible sur du texte clair.
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Self.height / 2
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, label) in labels.enumerated() {
            let button = SegmentButton(title: label)
            button.target = self
            button.action = #selector(tapped(_:))
            button.tag = index
            buttons.append(button)
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
        ])
        select(0)
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    func setLabel(_ text: String, at index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons[index].title = text
        buttons[index].restyle(selected: index == selectedIndex, accent: accent)
        invalidateIntrinsicContentSize()
    }

    func setEnabled(_ enabled: Bool, at index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons[index].isEnabled = enabled
        buttons[index].alphaValue = enabled ? 1 : 0.35
    }

    func select(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (position, button) in buttons.enumerated() {
            button.restyle(selected: position == index, accent: accent)
        }
    }

    @objc private func tapped(_ sender: NSButton) {
        // On ne repeint pas ici : c'est le contrôleur qui décide si le
        // changement est accepté, et il rappelle `select` en retour. Une
        // bascule refusée — les notes sans fichier mémorisé, par exemple — ne
        // doit pas s'afficher comme si elle avait eu lieu.
        onSelect?(sender.tag)
    }
}

/// Un segment. Bouton sans bordure dont le fond porte l'état.
private final class SegmentButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 12
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Actif = fond teinté et texte à la teinte, plutôt qu'un aplat saturé
    /// sous du blanc.
    ///
    /// L'aplat plein se voyait de loin, mais il criait : sur une barre qu'on
    /// garde sous les yeux pendant qu'on travaille, c'est fatigant. Un fond à
    /// faible opacité suffit à désigner l'état, et le texte à la teinte le
    /// confirme sans forcer le contraste.
    func restyle(selected: Bool, accent: NSColor) {
        layer?.backgroundColor = selected
            ? accent.withAlphaComponent(0.20).cgColor
            : NSColor.clear.cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .medium),
            .foregroundColor: selected
                ? accent.blended(withFraction: 0.25, of: .white) ?? accent
                : NSColor.secondaryLabelColor,
        ])
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height = 24
        return size
    }
}
