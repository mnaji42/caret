import OSLog

/// Journal de l'application, lisible depuis la Console et `log show`.
///
/// `NSLog` interpole en `<private>` par défaut : les messages existent mais
/// sortent caviardés, ce qui rend un diagnostic à distance impossible — on se
/// retrouve à déduire l'état de l'application depuis les journaux internes de
/// CoreAudio, ce qui a déjà coûté une fausse piste.
///
/// Ce qui passe ici est donc marqué explicitement public. Rien de sensible n'y
/// transite : des états, des durées, des noms de moteurs. **Jamais** le texte
/// dicté, qui reste entre l'utilisateur et son curseur.
enum Log {
    private static let logger = Logger(subsystem: "fr.lyriastudio.sofler",
                                       category: "dictation")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
