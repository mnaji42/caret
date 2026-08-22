import SwiftUI

/// La barre de la dictée au fil.
///
/// Délibérément plus maigre que `RecordingOverlay` : celle-ci porte le mode,
/// la destination, la collecte, l'aperçu — parce que tout cela se décide
/// pendant qu'on parle et se lit à la fin. Ici il n'y a rien à décider, et le
/// texte affiché **est** le texte qui sera inséré. Reprendre les commandes de
/// l'autre barre aurait proposé des réglages sans effet sur ce chemin-là.
///
/// Un seul repère visuel les distingue au premier coup d'œil, et c'est voulu :
/// l'ambre de Voxtral, là où la barre principale est neutre. Quand deux
/// chemins coexistent, savoir lequel tourne ne doit pas demander à lire.
struct StreamingOverlayView: View {
    @Bindable var controller: StreamingDictation

    private static let amber = Color(red: 0.85, green: 0.55, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            transcript
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 620, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Self.amber.opacity(0.30), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(controller.phase == .listening ? Self.amber : .secondary)
                .frame(width: 7, height: 7)
            Text("Voxtral · au fil de la parole")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Self.amber)
            Text("⌥ gauche")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch controller.phase {
        case .connecting:
            Text("connexion…").font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .listening:
            HStack(spacing: 7) {
                if let started = controller.startedAt {
                    // Le compteur dit qu'on enregistre encore ; sans lui, une
                    // dictée silencieuse ne se distingue pas d'une barre figée.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: started, to: context.date))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(controller.text.split(separator: " ").count) mots")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        case .finishing:
            Text("finalisation…").font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .failed:
            Text("échec").font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.red)
        case .idle:
            // Le rattrapage après le dernier mot, affiché parce que c'est
            // exactement la mesure qu'on est venu chercher.
            if let tail = controller.lastTailMs {
                Text("inséré en \(String(format: "%.2f", tail / 1000)) s")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Self.amber)
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if case .failed(let message) = controller.phase {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if controller.text.isEmpty {
            Text(controller.phase == .listening ? "Parlez…" : "…")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        } else {
            // Les derniers mots, pas les premiers : ce qui vient d'être dit est
            // ce qu'on vérifie, et une barre qui grandit sans fin masquerait
            // l'écran au bout d'une minute.
            Text(Self.tail(of: controller.text, words: 34))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: controller.text)
        }
    }

    private static func tail(of text: String, words: Int) -> String {
        let all = text.split(separator: " ")
        guard all.count > words else { return text }
        return "… " + all.suffix(words).joined(separator: " ")
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
