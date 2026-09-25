import Foundation

protocol ExportStagingFileSystem {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    func removeItem(at url: URL) throws
}

struct LocalExportStagingFileSystem: ExportStagingFileSystem {
    private let fileManager = FileManager.default

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

struct ExportStagingResult: Equatable, Sendable {
    let sessionDirectory: URL
    let manifestURL: URL
    let trackURLs: [URL]
    let photoURLs: [URL]
}

struct ExportStagingService {
    private let baseDirectory: URL
    private let fileSystem: any ExportStagingFileSystem
    private let mapper: ExportDTOMapper
    private let jsonEncoder: ExportJSONEncoder

    init(
        baseDirectory: URL = ExportTemporaryLocations.staging,
        fileSystem: any ExportStagingFileSystem = LocalExportStagingFileSystem(),
        mapper: ExportDTOMapper = ExportDTOMapper(),
        jsonEncoder: ExportJSONEncoder = ExportJSONEncoder()
    ) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.fileSystem = fileSystem
        self.mapper = mapper
        self.jsonEncoder = jsonEncoder
    }

    func stage(
        _ snapshot: AreaExportSnapshot,
        sessionID: UUID = UUID()
    ) throws -> ExportStagingResult {
        let sessionDirectory = baseDirectory
            .appending(path: sessionID.uuidString.lowercased(), directoryHint: .isDirectory)
            .standardizedFileURL
        try validateChild(sessionDirectory, of: baseDirectory)
        guard !fileSystem.fileExists(at: sessionDirectory) else {
            throw ExportValidationError.stagingSessionAlreadyExists
        }

        do {
            try fileSystem.createDirectory(at: sessionDirectory)
            let manifestURL = try resolved(relativePath: "manifest.json", in: sessionDirectory)
            let manifest = mapper.manifest(from: snapshot)
            try fileSystem.write(jsonEncoder.encode(manifest), to: manifestURL)

            var trackURLs: [URL] = []
            var photoURLs: [URL] = []
            for track in snapshot.tracks {
                let trackDTO = mapper.track(from: track, areaName: snapshot.area.name)
                try ExportContractValidator.validate(track: trackDTO, trackID: track.id)
                let trackURL = try resolved(relativePath: track.fileName, in: sessionDirectory)
                try fileSystem.createDirectory(at: trackURL.deletingLastPathComponent())
                try fileSystem.write(jsonEncoder.encode(trackDTO), to: trackURL)
                trackURLs.append(trackURL)

                for photo in track.photos {
                    let photoURL = try resolved(relativePath: photo.relativePath, in: sessionDirectory)
                    try fileSystem.createDirectory(at: photoURL.deletingLastPathComponent())
                    try fileSystem.write(photo.jpegData, to: photoURL)
                    photoURLs.append(photoURL)
                }
            }

            return ExportStagingResult(
                sessionDirectory: sessionDirectory,
                manifestURL: manifestURL,
                trackURLs: trackURLs,
                photoURLs: photoURLs
            )
        } catch {
            if fileSystem.fileExists(at: sessionDirectory) {
                try? fileSystem.removeItem(at: sessionDirectory)
            }
            if let validationError = error as? ExportValidationError {
                throw validationError
            }
            throw ExportValidationError.stagingFailure(error.localizedDescription)
        }
    }

    func cleanUp(_ result: ExportStagingResult) throws {
        try validateChild(result.sessionDirectory, of: baseDirectory)
        if fileSystem.fileExists(at: result.sessionDirectory) {
            try fileSystem.removeItem(at: result.sessionDirectory)
        }
    }

    private func resolved(relativePath: String, in root: URL) throws -> URL {
        guard isSafeRelativePath(relativePath) else {
            throw ExportValidationError.unsafeStagingPath(relativePath)
        }
        let url = root.appending(path: relativePath).standardizedFileURL
        try validateChild(url, of: root)
        return url
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private func validateChild(_ child: URL, of root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else {
            throw ExportValidationError.unsafeStagingPath(childPath)
        }
    }
}
