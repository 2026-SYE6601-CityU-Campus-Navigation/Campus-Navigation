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

    func validate(relativePath: String) throws {
        _ = try validatedURL(for: relativePath, mustExist: false)
    }

    func delete(relativePath: String) throws {
        let url = try validatedURL(for: relativePath, mustExist: false)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteTrackDirectory(trackID: UUID) throws {
        let relativePath = "photos/\(trackID.uuidString.lowercased())"
        let directory = try validatedURL(for: relativePath, mustExist: false)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
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

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let ownedRoot = photosURL.resolvingSymlinksInPath().standardizedFileURL
        let comparisonURL: URL
        if mustExist || fileManager.fileExists(atPath: candidate.path) {
            comparisonURL = candidate.resolvingSymlinksInPath().standardizedFileURL
        } else {
            let resolvedParent = candidate.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
            comparisonURL = resolvedParent.appendingPathComponent(candidate.lastPathComponent)
        }

        let ownedPrefix = ownedRoot.path.hasSuffix("/") ? ownedRoot.path : ownedRoot.path + "/"
        guard comparisonURL.path.hasPrefix(ownedPrefix) else {
            throw PhotoStorageError.unsafeRelativePath
        }
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
