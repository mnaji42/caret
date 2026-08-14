import Foundation

/// Journal des relectures, pour juger le mode relu sur pièces.
///
/// Le mode est expérimental et son intérêt ne se décide pas en une fois :
/// il faut voir, sur des semaines d'usage réel, s'il répare plus qu'il
/// n'abîme. Chaque modification est donc consignée en clair, avec les deux
/// versions.
///
/// Écrit dans les journaux de l'application, jamais transmis nulle part, et
/// supprimable d'un `rm`.
enum ReviewLog {
    static var url: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Caret")
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        return directory.appendingPathComponent("relectures.md")
    }

    static func record(before: String, after: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = """

        ## \(stamp)

        - avant : \(before)
        - après : \(after)

        """
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? ("# Relectures du mode expérimental\n" + entry)
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
