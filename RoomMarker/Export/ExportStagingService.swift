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
    var auxiliaryURLs: [URL] = []
}

struct ExportStagingService {
    var streamingBaseDirectory: URL? { fileSystem is LocalExportStagingFileSystem ? baseDirectory : nil }
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
        let tracks = try snapshot.tracks.map { track in
            let dto = mapper.track(from: track, areaName: snapshot.area.name)
            try ExportContractValidator.validate(track: dto, trackID: track.id)
            return (track.fileName, try jsonEncoder.encode(dto))
        }
        return try stageFiles(manifest: jsonEncoder.encode(mapper.manifest(from: snapshot)), tracks: tracks,
                              photos: snapshot.tracks.flatMap { $0.photos.map { ($0.relativePath, $0.jpegData) } }, sessionID: sessionID)
    }

    func stage(_ snapshot: ExportV3Snapshot, sessionID: UUID = UUID()) throws -> ExportStagingResult {
        try ExportV3Validator.validate(snapshot)
        return try stageFiles(manifest: jsonEncoder.encode(snapshot.manifest),
                              tracks: snapshot.tracks.map { ($0.file, try jsonEncoder.encode($0)) },
                              photos: snapshot.photos.map { ($0.path, $0.data) }, sessionID: sessionID)
    }

    private func stageFiles(
        manifest: Data, tracks: [(String, Data)], photos: [(String, Data)], sessionID: UUID
    ) throws -> ExportStagingResult {
        let paths = ["manifest.json"] + tracks.map(\.0) + photos.map(\.0)
        guard paths.allSatisfy(ArchivePathValidator.isSafe), Set(paths).count == paths.count else {
            throw ExportValidationError.unsafeStagingPath("duplicate or invalid entry")
        }
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
            try fileSystem.write(manifest, to: manifestURL)

            var trackURLs: [URL] = []
            var photoURLs: [URL] = []
            for (path, data) in tracks {
                let trackURL = try resolved(relativePath: path, in: sessionDirectory)
                try fileSystem.createDirectory(at: trackURL.deletingLastPathComponent())
                try fileSystem.write(data, to: trackURL)
                trackURLs.append(trackURL)
            }
            for (path, data) in photos {
                let photoURL = try resolved(relativePath: path, in: sessionDirectory)
                try fileSystem.createDirectory(at: photoURL.deletingLastPathComponent())
                try fileSystem.write(data, to: photoURL)
                photoURLs.append(photoURL)
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
        guard let url = CanonicalPathContainment.resolve(
            relativePath: relativePath,
            under: root
        ) else {
            throw ExportValidationError.unsafeStagingPath(relativePath)
        }
        return url
    }

    private func validateChild(_ child: URL, of root: URL) throws {
        guard CanonicalPathContainment.isStrictDescendant(child, of: root) else {
            throw ExportValidationError.unsafeStagingPath(child.path)
        }
    }
}
