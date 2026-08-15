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

    private static let height: CGFloat = 25
    private static let inset: CGFloat = 3

    init(labels: [String], accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        // Un fond à peine plus clair que le panneau : il faut que le groupe se
        // lise comme un ensemble sans devenir un bloc opaque de plus.
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor
        translatesAutoresizingMaskIntoConstraints = false

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
        layer?.cornerRadius = 9.5
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func restyle(selected: Bool, accent: NSColor) {
        layer?.backgroundColor = selected ? accent.cgColor : NSColor.clear.cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .medium),
            .foregroundColor: selected ? NSColor.white : NSColor.secondaryLabelColor,
        ])
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 16
        size.height = 19
        return size
    }
}
