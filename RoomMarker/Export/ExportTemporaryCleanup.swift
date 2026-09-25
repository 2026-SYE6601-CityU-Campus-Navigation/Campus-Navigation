import Foundation

enum ExportTemporaryLocations {
    static let root = FileManager.default.temporaryDirectory
        .appending(path: "RoomMarkerExports", directoryHint: .isDirectory)
    static let staging = root.appending(path: "staging", directoryHint: .isDirectory)
    static let archives = root.appending(path: "archives", directoryHint: .isDirectory)
}

struct ExportTemporaryCleaner {
    private let fileManager: FileManager
    private let ownedRoot: URL

    init(
        ownedRoot: URL = ExportTemporaryLocations.root,
        fileManager: FileManager = .default
    ) {
        self.ownedRoot = ownedRoot.standardizedFileURL
        self.fileManager = fileManager
    }

    func removeStaleOwnedExports(excluding protectedURLs: Set<URL> = []) throws {
        guard fileManager.fileExists(atPath: ownedRoot.path) else { return }
        let protected = Set(protectedURLs.map { $0.standardizedFileURL.path })
        let children = try fileManager.contentsOfDirectory(
            at: ownedRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children where !protected.contains(child.standardizedFileURL.path) {
            try fileManager.removeItem(at: child)
        }
    }
}
