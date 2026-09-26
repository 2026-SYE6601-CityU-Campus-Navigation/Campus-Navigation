import Foundation

enum CanonicalPathContainment {
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    static func resolve(
        relativePath: String,
        under root: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard isSafeRelativePath(relativePath) else { return nil }
        let child = root.appendingPathComponent(relativePath)
        guard isStrictDescendant(child, of: root, fileManager: fileManager) else {
            return nil
        }
        return child
    }

    static func isStrictDescendant(
        _ child: URL,
        of root: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard child.isFileURL, root.isFileURL else { return false }
        let rootComponents = canonicalURL(root, fileManager: fileManager).pathComponents
        let childComponents = canonicalURL(child, fileManager: fileManager).pathComponents
        return childComponents.count > rootComponents.count
            && Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }

    static func relativePath(
        of child: URL,
        under root: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard isStrictDescendant(child, of: root, fileManager: fileManager) else {
            return nil
        }
        let rootComponents = canonicalURL(root, fileManager: fileManager).pathComponents
        let childComponents = canonicalURL(child, fileManager: fileManager).pathComponents
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func canonicalURL(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> URL {
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []

        while !fileManager.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missingComponents.insert(ancestor.lastPathComponent, at: 0)
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { break }
            ancestor = parent
        }

        var canonical = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents {
            canonical.appendPathComponent(component)
        }
        return canonical
    }
}

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
        let protected = Set(protectedURLs.map {
            CanonicalPathContainment.canonicalURL($0, fileManager: fileManager).path
        })
        let children = try fileManager.contentsOfDirectory(
            at: ownedRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children {
            guard CanonicalPathContainment.isStrictDescendant(
                child,
                of: ownedRoot,
                fileManager: fileManager
            ) else {
                continue
            }
            let canonicalChild = CanonicalPathContainment.canonicalURL(
                child,
                fileManager: fileManager
            ).path
            guard !protected.contains(canonicalChild) else { continue }
            try fileManager.removeItem(at: child)
        }
    }
}
