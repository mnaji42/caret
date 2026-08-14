import AppKit

/// Les dernières transcriptions, pour les réinsérer sans reparler.
///
/// Volontairement court : au-delà de quelques entrées, retrouver la bonne dans
/// une liste coûte plus de temps que de redicter la phrase.
///
/// Seul le **texte** est conservé, jamais l'audio. Le stockage passe par les
/// préférences de l'app : effacer une entrée la supprime réellement, sans
/// fichier résiduel ni passage par la corbeille.
@MainActor
final class TranscriptionHistory {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let text: String
        let date: Date
        let mode: String
        init(text: String, mode: TranscriptionMode) {
            self.id = UUID()
            self.text = text
            self.date = Date()
            self.mode = mode.rawValue
        }

        /// « à l'instant », « il y a 3 min » — repère plus utile qu'une heure
        /// absolue pour retrouver ce qu'on vient de dicter.
        var relativeAge: String {
            let seconds = Int(Date().timeIntervalSince(date))
            switch seconds {
            case ..<10: return "à l'instant"
            case ..<60: return "il y a \(seconds) s"
            case ..<3600: return "il y a \(seconds / 60) min"
            default: return "il y a \(seconds / 3600) h"
            }
        }

        var preview: String {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            return flat.count <= 60 ? flat : String(flat.prefix(58)) + "…"
        }
    }

    static let limit = 5

    private let storageKey = "caret.history"
    private let enabledKey = "caret.history.enabled"

    private(set) var entries: [Entry] = []

    /// Historique désactivable : certains ne veulent aucune trace écrite de ce
    /// qu'ils dictent, même locale.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if !isEnabled { clear() }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        if isEnabled, let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = stored
        }
    }

    func add(_ text: String, mode: TranscriptionMode) {
        guard isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries.insert(Entry(text: trimmed, mode: mode), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        // Force l'écriture immédiate : sans ça l'effacement demandé par
        // l'utilisateur resterait en attente en mémoire.
        UserDefaults.standard.synchronize()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
