import Foundation

struct ZIPSourceEntry: Equatable, Sendable {
    let archivePath: String
    let sourceURL: URL
}

struct ZIPArchiveResult: Equatable, Sendable {
    let archiveURL: URL
    let entryPaths: [String]
}

enum ZIPArchiveError: LocalizedError, Equatable, Sendable {
    case noEntries
    case unsafeEntryPath(String)
    case sourceOutsideStaging(URL)
    case sourceMissing(String)
    case sourceTooLarge(String)
    case tooManyEntries
    case outputFailure(String)

    var errorDescription: String? {
        switch self {
        case .noEntries:
            "归档没有可写入的文件。"
        case let .unsafeEntryPath(path):
            "归档路径不安全：\(path)"
        case .sourceOutsideStaging:
            "归档源文件不属于当前导出会话。"
        case let .sourceMissing(path):
            "归档源文件缺失：\(path)"
        case let .sourceTooLarge(path):
            "文件超出当前 ZIP32 导出的大小限制：\(path)"
        case .tooManyEntries:
            "导出文件数量超出当前 ZIP32 限制。"
        case let .outputFailure(reason):
            "创建 ZIP 失败：\(reason)"
        }
    }
}

protocol ZIPArchiveCreating {
    func createArchive(
        from staging: ExportStagingResult,
        areaName: String,
        exportedAt: Int64,
        archiveID: UUID
    ) throws -> ZIPArchiveResult

    func removeArchive(at url: URL) throws
}

struct StoredZIPArchiveService: ZIPArchiveCreating {
    private let archiveDirectory: URL
    private let fileManager: FileManager
    private let writer: StoredZIPWriter

    init(
        archiveDirectory: URL = ExportTemporaryLocations.archives,
        fileManager: FileManager = .default,
        writer: StoredZIPWriter = StoredZIPWriter()
    ) {
        self.archiveDirectory = archiveDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.writer = writer
    }

    func createArchive(
        from staging: ExportStagingResult,
        areaName: String,
        exportedAt: Int64,
        archiveID: UUID = UUID()
    ) throws -> ZIPArchiveResult {
        let entries = try orderedEntries(from: staging)
        guard !entries.isEmpty else { throw ZIPArchiveError.noEntries }

        do {
            try fileManager.createDirectory(
                at: archiveDirectory,
                withIntermediateDirectories: true
            )
            let baseName = ExportArchiveFilename.make(
                areaName: areaName,
                exportedAt: exportedAt,
                archiveID: archiveID
            )
            let destination = collisionSafeURL(for: baseName)
            try writer.write(entries: entries, to: destination)
            return ZIPArchiveResult(
                archiveURL: destination,
                entryPaths: entries.map(\.archivePath)
            )
        } catch let error as ZIPArchiveError {
            throw error
        } catch {
            throw ZIPArchiveError.outputFailure(error.localizedDescription)
        }
    }

    func removeArchive(at url: URL) throws {
        let candidate = url.standardizedFileURL
        try validateChild(candidate, of: archiveDirectory)
        if fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func orderedEntries(from staging: ExportStagingResult) throws -> [ZIPSourceEntry] {
        let sourceURLs = [staging.manifestURL] + staging.trackURLs + staging.photoURLs
        return try sourceURLs.map { sourceURL in
            let path = try relativePath(of: sourceURL, under: staging.sessionDirectory)
            guard ArchivePathValidator.isSafe(path) else {
                throw ZIPArchiveError.unsafeEntryPath(path)
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ZIPArchiveError.sourceMissing(path)
            }
            return ZIPSourceEntry(archivePath: path, sourceURL: sourceURL)
        }
    }

    private func relativePath(of source: URL, under root: URL) throws -> String {
        let safeRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let safeSource = source.resolvingSymlinksInPath().standardizedFileURL
        let prefix = safeRoot.path + "/"
        guard safeSource.path.hasPrefix(prefix) else {
            throw ZIPArchiveError.sourceOutsideStaging(source)
        }
        return String(safeSource.path.dropFirst(prefix.count))
    }

    private func collisionSafeURL(for filename: String) -> URL {
        let initial = archiveDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let stem = initial.deletingPathExtension().lastPathComponent
        for suffix in 2...10_000 {
            let candidate = archiveDirectory.appendingPathComponent("\(stem)-\(suffix).zip")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return archiveDirectory.appendingPathComponent("\(stem)-\(UUID().uuidString.lowercased()).zip")
    }

    private func validateChild(_ child: URL, of root: URL) throws {
        guard child.path.hasPrefix(root.path + "/") else {
            throw ZIPArchiveError.unsafeEntryPath(child.path)
        }
    }
}

enum ArchivePathValidator {
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\") else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

enum ExportArchiveFilename {
    static func make(areaName: String, exportedAt: Int64, archiveID: UUID) -> String {
        let safeArea = sanitize(areaName)
        let timestamp = timestampString(milliseconds: exportedAt)
        let uniqueness = archiveID.uuidString.lowercased().prefix(8)
        return "RoomMarker-\(safeArea)-\(timestamp)-\(uniqueness).zip"
    }

    static func sanitize(_ value: String) -> String {
        let disallowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_").union(.letters))
            .inverted
        let components = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: disallowed)
            .filter { !$0.isEmpty }
        let candidate = components.joined(separator: "-")
        return String((candidate.isEmpty ? "未分区" : candidate).prefix(48))
    }

    private static func timestampString(milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

struct StoredZIPWriter {
    private let fileManager: FileManager
    private let chunkSize: Int

    init(fileManager: FileManager = .default, chunkSize: Int = 64 * 1_024) {
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    func write(entries: [ZIPSourceEntry], to destination: URL) throws {
        guard entries.count <= Int(UInt16.max) else { throw ZIPArchiveError.tooManyEntries }
        let partial = destination.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partial)
        try? fileManager.removeItem(at: destination)

        do {
            fileManager.createFile(atPath: partial.path, contents: nil)
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }

            var centralRecords: [CentralRecord] = []
            for entry in entries {
                guard ArchivePathValidator.isSafe(entry.archivePath) else {
                    throw ZIPArchiveError.unsafeEntryPath(entry.archivePath)
                }
                let nameData = Data(entry.archivePath.utf8)
                guard nameData.count <= Int(UInt16.max) else {
                    throw ZIPArchiveError.unsafeEntryPath(entry.archivePath)
                }
                let metadata = try scan(entry)
                let offset = try currentOffset(output)
                guard offset <= UInt64(UInt32.max) else {
                    throw ZIPArchiveError.sourceTooLarge(entry.archivePath)
                }
                try output.write(contentsOf: localHeader(
                    name: nameData,
                    crc32: metadata.crc32,
                    size: metadata.size
                ))
                try stream(entry.sourceURL, to: output)
                centralRecords.append(CentralRecord(
                    name: nameData,
                    crc32: metadata.crc32,
                    size: metadata.size,
                    localOffset: UInt32(offset)
                ))
            }

            let centralOffset = try currentOffset(output)
            guard centralOffset <= UInt64(UInt32.max) else {
                throw ZIPArchiveError.outputFailure("ZIP32 中央目录偏移超限")
            }
            for record in centralRecords {
                try output.write(contentsOf: centralHeader(record))
            }
            let endOffset = try currentOffset(output)
            let centralSize = endOffset - centralOffset
            guard centralSize <= UInt64(UInt32.max) else {
                throw ZIPArchiveError.outputFailure("ZIP32 中央目录大小超限")
            }
            try output.write(contentsOf: endRecord(
                count: UInt16(centralRecords.count),
                centralSize: UInt32(centralSize),
                centralOffset: UInt32(centralOffset)
            ))
            try output.synchronize()
            try output.close()
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            try? fileManager.removeItem(at: destination)
            if let archiveError = error as? ZIPArchiveError { throw archiveError }
            throw ZIPArchiveError.outputFailure(error.localizedDescription)
        }
    }

    private func scan(_ entry: ZIPSourceEntry) throws -> (crc32: UInt32, size: UInt32) {
        guard fileManager.fileExists(atPath: entry.sourceURL.path) else {
            throw ZIPArchiveError.sourceMissing(entry.archivePath)
        }
        let input = try FileHandle(forReadingFrom: entry.sourceURL)
        defer { try? input.close() }
        var crc = CRC32()
        var total: UInt64 = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            total += UInt64(chunk.count)
            guard total <= UInt64(UInt32.max) else {
                throw ZIPArchiveError.sourceTooLarge(entry.archivePath)
            }
            crc.update(chunk)
        }
        return (crc.finalized, UInt32(total))
    }

    private func stream(_ source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private func currentOffset(_ handle: FileHandle) throws -> UInt64 {
        try handle.offset()
    }

    private func localHeader(name: Data, crc32: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x0403_4B50))
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(0x0800))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0x0021))
        data.appendLE(crc32)
        data.appendLE(size)
        data.appendLE(size)
        data.appendLE(UInt16(name.count))
        data.appendLE(UInt16(0))
        data.append(name)
        return data
    }

    private func centralHeader(_ record: CentralRecord) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x0201_4B50))
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(20))
        data.appendLE(UInt16(0x0800))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0x0021))
        data.appendLE(record.crc32)
        data.appendLE(record.size)
        data.appendLE(record.size)
        data.appendLE(UInt16(record.name.count))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(0))
        data.appendLE(record.localOffset)
        data.append(record.name)
        return data
    }

    private func endRecord(count: UInt16, centralSize: UInt32, centralOffset: UInt32) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x0605_4B50))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(count)
        data.appendLE(count)
        data.appendLE(centralSize)
        data.appendLE(centralOffset)
        data.appendLE(UInt16(0))
        return data
    }
}

private struct CentralRecord {
    let name: Data
    let crc32: UInt32
    let size: UInt32
    let localOffset: UInt32
}

private struct CRC32 {
    private var value: UInt32 = 0xFFFF_FFFF

    mutating func update(_ data: Data) {
        for byte in data {
            var current = (value ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                current = (current & 1) == 1
                    ? 0xEDB8_8320 ^ (current >> 1)
                    : current >> 1
            }
            value = (value >> 8) ^ current
        }
    }

    var finalized: UInt32 { value ^ 0xFFFF_FFFF }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
