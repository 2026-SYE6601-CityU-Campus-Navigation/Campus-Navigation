import Foundation
import UIKit

enum PhotoStorageError: LocalizedError, Equatable {
    case emptyData
    case unsafeRelativePath
    case missingFile

    var errorDescription: String? {
        switch self {
        case .emptyData:
            "照片数据为空。"
        case .unsafeRelativePath:
            "照片路径不属于 RoomMarker。"
        case .missingFile:
            "照片文件不存在。"
        }
    }
}

@MainActor
final class LocalPhotoFileStore: PhotoFileStoring {
    private let fileManager: FileManager
    private let rootURL: URL
    private let photosURL: URL

    convenience init(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(rootURL: applicationSupport.appendingPathComponent("RoomMarker", isDirectory: true))
    }

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        photosURL = self.rootURL.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
    }

    func storeJPEG(_ data: Data, trackID: UUID, timeMs: Int64) throws -> String {
        guard !data.isEmpty else { throw PhotoStorageError.emptyData }

        let trackToken = trackID.uuidString.lowercased()
        let relativeDirectory = "photos/\(trackToken)"
        let filename = "\(timeMs)-\(UUID().uuidString.lowercased()).jpg"
        let relativePath = "\(relativeDirectory)/\(filename)"
        let destination = try validatedURL(for: relativePath, mustExist: false)
        // Write an intent BEFORE creating the file. A process interruption
        // between file write and database commit is recoverable on next launch.
        try addCleanupIntent(relativePath)

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return relativePath
    }

    func read(relativePath: String) throws -> Data {
        let url = try validatedURL(for: relativePath, mustExist: true)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PhotoStorageError.missingFile
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    // Read-only capability for the background exporter; never serialized to JSON.
    func exportSource(relativePath: String) throws -> V3PhotoSource {
        .init(root: rootURL, url: try validatedURL(for: relativePath, mustExist: true))
    }

    func validate(relativePath: String) throws {
        _ = try validatedURL(for: relativePath, mustExist: false)
    }

    func delete(relativePath: String) throws {
        let url = try validatedURL(for: relativePath, mustExist: false)
        try addCleanupIntent(relativePath)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try pruneEmptyTrackDirectory(below: url)
        try confirmReferenced(relativePath: relativePath)
    }

    func deleteTrackDirectory(trackID: UUID) throws {
        let relativePath = "photos/\(trackID.uuidString.lowercased())"
        try delete(relativePath: relativePath)
    }

    func confirmReferenced(relativePath: String) throws {
        try validate(relativePath: relativePath)
        var intents = try cleanupIntents()
        intents.remove(relativePath)
        try writeCleanupIntents(intents)
    }

    func prepareDeletion(relativePath: String) throws {
        try validate(relativePath: relativePath)
        try addCleanupIntent(relativePath)
    }

    func retryPendingCleanup(protecting referencedPaths: Set<String>) throws {
        let protectedURLs = try referencedPaths.map {
            CanonicalPathContainment.canonicalURL(
                try validatedURL(for: $0, mustExist: false), fileManager: fileManager
            )
        }
        for path in try cleanupIntents() {
            let candidate = CanonicalPathContainment.canonicalURL(
                try validatedURL(for: path, mustExist: false), fileManager: fileManager
            )
            // An intent may predate a successful DB commit or describe a whole
            // Track directory. Never remove any currently referenced photo.
            if protectedURLs.contains(where: {
                $0 == candidate || CanonicalPathContainment.isStrictDescendant($0, of: candidate, fileManager: fileManager)
            }) {
                try confirmReferenced(relativePath: path)
            } else {
                try delete(relativePath: path)
            }
        }
    }

    private func journalURL() throws -> URL {
        let url = rootURL.appendingPathComponent("photo-cleanup.json")
        guard CanonicalPathContainment.isStrictDescendant(url, of: rootURL, fileManager: fileManager) else {
            throw PhotoStorageError.unsafeRelativePath
        }
        return url
    }

    private func cleanupIntents() throws -> Set<String> {
        let url = try journalURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let paths = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))
        // Reject the entire journal on corruption; never act on arbitrary paths.
        for path in paths { try validate(relativePath: path) }
        return paths
    }

    private func writeCleanupIntents(_ paths: Set<String>) throws {
        try JSONEncoder().encode(paths.sorted()).write(to: journalURL(), options: .atomic)
    }

    private func addCleanupIntent(_ path: String) throws {
        var paths = try cleanupIntents()
        paths.insert(path)
        try writeCleanupIntents(paths)
    }

    private func pruneEmptyTrackDirectory(below url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard CanonicalPathContainment.isStrictDescendant(parent, of: photosURL, fileManager: fileManager),
              parent.deletingLastPathComponent().standardizedFileURL == photosURL.standardizedFileURL,
              fileManager.fileExists(atPath: parent.path) else { return }
        if try fileManager.contentsOfDirectory(atPath: parent.path).isEmpty {
            try fileManager.removeItem(at: parent)
        }
    }

    private func validatedURL(for relativePath: String, mustExist: Bool) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\") else {
            throw PhotoStorageError.unsafeRelativePath
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.first == "photos",
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PhotoStorageError.unsafeRelativePath
        }

        let candidate = rootURL.appendingPathComponent(relativePath)
        guard CanonicalPathContainment.isStrictDescendant(
            candidate,
            of: photosURL,
            fileManager: fileManager
        ) else {
            throw PhotoStorageError.unsafeRelativePath
        }
        _ = mustExist
        return candidate
    }
}

enum PhotoContentStatus: Equatable, Sendable {
    case available
    case missing
    case corrupt
}

struct PhotoContent {
    let status: PhotoContentStatus
    let data: Data?
    let image: UIImage?
}

@MainActor
struct PhotoContentLoader {
    let storage: any PhotoFileStoring

    func load(relativePath: String) -> PhotoContent {
        do {
            let data = try storage.read(relativePath: relativePath)
            guard let image = UIImage(data: data) else {
                return PhotoContent(status: .corrupt, data: nil, image: nil)
            }
            return PhotoContent(status: .available, data: data, image: image)
        } catch {
            return PhotoContent(status: .missing, data: nil, image: nil)
        }
    }
}
