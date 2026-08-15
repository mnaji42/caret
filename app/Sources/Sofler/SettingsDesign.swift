import AppKit
import SwiftUI

/// Le vocabulaire visuel commun à la barre flottante et aux réglages.
///
/// Il existe parce que les deux surfaces se ressemblaient de loin sans jamais
/// se répondre : la barre avait son verre, sa teinte et ses pastilles, les
/// réglages affichaient des `Form` système gris. Deux dialectes pour une même
/// application. Les valeurs ci-dessous sont celles de `RecordingOverlay`, une
/// seule fois, pour qu'elles ne divergent pas.
enum Style {
    static let accent = Color(nsColor: .systemTeal)
    static let collecting = Color(nsColor: .systemOrange)

    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let cardFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.08)
}

/// Le verre du fond, identique à celui de la barre.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Un bloc de réglages : titre en capitales espacées, contenu sur une carte.
///
/// Remplace `Section` dans un `Form` groupé, dont le rendu système jure avec le
/// reste de l'application.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(0.9)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Style.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                        .fill(Style.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Style.cardRadius,
                                             style: .continuous)
                                .strokeBorder(Style.cardStroke, lineWidth: 1))
                )
        }
    }
}

/// Note explicative sous un réglage. Le projet en met beaucoup, parce qu'un
/// réglage dont on ignore la conséquence ne sera jamais touché.
struct Note: View {
    let text: String
    var warning = false

    init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    var body: some View {
        Text(.init(text))
            .font(.system(size: 11))
            .foregroundStyle(warning ? Style.collecting : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sélecteur en pastilles, la version SwiftUI de celui de la barre.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var disabled = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Text(option.label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Style.accent : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? Style.accent.opacity(0.20) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { if !disabled { selection = option.value } }
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Ligne « libellé à gauche, contrôle à droite ».
struct Row<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 16)
            trailing
        }
    }
}


/// Ligne sélectionnable, pour un choix qui mérite une explication.
///
/// Un `PillPicker` suffit quand les options tiennent en un mot. Choisir un
/// moteur de transcription n'est pas de cet ordre : il faut voir, au moment de
/// choisir, ce que l'option coûte et ce qu'elle empêche. D'où une ligne haute
/// qui porte son texte, plutôt qu'une pastille et une note en dessous qui ne
/// parle que de l'option déjà retenue.
struct ChoiceRow<Detail: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    /// Ce moteur a-t-il des options propres ? Explicite plutôt que déduit du
    /// contenu : tester `detail is EmptyView` marche mal dans un ViewBuilder.
    var hasDetail = true
    let action: () -> Void
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Style.accent : Color.secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)

            // Les options du moteur retenu sont attachées sous lui, pas
            // ailleurs : elles n'existent que parce qu'il a été choisi.
            // Affichées même quand le moteur n'est pas retenu : on peut
            // écrire avec macOS tout en collectant avec CrisperWhisper, et il
            // faut alors pouvoir régler ce dernier.
            if hasDetail {
                Divider().opacity(0.25).padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 12) { detail }
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Style.accent.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? Style.accent.opacity(0.35)
                                               : Color.white.opacity(0.07),
                                      lineWidth: 1)))
    }
}

/// Boutons secondaires alignés, taille et style uniformes.
struct ButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}


/// Interrupteur d'une fonctionnalité entière, par opposition à une case qui
/// coche une option.
///
/// La distinction n'est pas décorative : une case à cocher se lit comme « ce
/// détail est retenu », un interrupteur comme « cette fonctionnalité est en
/// marche ». Confondre les deux fait qu'on active une collecte de données en
/// croyant cocher une préférence.
struct FeatureSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// Case à cocher pour une option à l'intérieur d'une fonctionnalité.
struct OptionCheck: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 13))
    }
}
