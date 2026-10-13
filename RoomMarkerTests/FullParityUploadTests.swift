import Foundation
import CryptoKit
import Testing
@testable import RoomMarker

@Suite("Full parity ZIP upload")
struct FullParityUploadTests {
    @Test("Upload configuration accepts HTTP(S) without credentials and a safe field")
    func configurationAccepted() throws {
        let https = try ZIPUploadConfigurationValidator.validate(
            .init(endpoint: " https://collector.example.edu/upload?course=6601 ",
                  token: "secret", fieldName: "archive_file")
        )
        #expect(https.scheme == "https" && https.host == "collector.example.edu")
        let http = try ZIPUploadConfigurationValidator.validate(
            .init(endpoint: "http://192.168.1.10:8080/upload", token: "", fieldName: "file")
        )
        #expect(http.scheme == "http")
    }

    @Test("Unsafe upload endpoints and multipart field names are rejected", arguments: [
        ZIPUploadConfiguration(endpoint: "", token: "", fieldName: "file"),
        ZIPUploadConfiguration(endpoint: "file:///tmp/upload", token: "", fieldName: "file"),
        ZIPUploadConfiguration(endpoint: "https://user:pass@example.edu/upload", token: "", fieldName: "file"),
        ZIPUploadConfiguration(endpoint: "https://example.edu/upload#fragment", token: "", fieldName: "file"),
        ZIPUploadConfiguration(endpoint: "https://example.edu/upload", token: "", fieldName: "../file"),
        ZIPUploadConfiguration(endpoint: "https://example.edu/upload", token: "", fieldName: "a b"),
    ])
    func configurationRejected(_ configuration: ZIPUploadConfiguration) {
        #expect(throws: (any Error).self) {
            try ZIPUploadConfigurationValidator.validate(configuration)
        }
    }

    @Test("Unreadable, empty and non-ZIP input fail before any network operation")
    func archiveValidation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FullParityUploadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty.zip")
        try Data().write(to: empty)
        let notZip = root.appendingPathComponent("archive.txt")
        try Data("PK".utf8).write(to: notZip)
        let configuration = ZIPUploadConfiguration(endpoint: "https://example.edu/upload",
                                                   token: "", fieldName: "file")
        let uploader = URLSessionZIPUploader()
        await #expect(throws: ZIPUploadError.invalidArchive) {
            try await uploader.upload(archive: empty, configuration: configuration)
        }
        await #expect(throws: ZIPUploadError.invalidArchive) {
            try await uploader.upload(archive: notZip, configuration: configuration)
        }
    }

    @Test("Multipart upload is disk-streamed, bounded to owned temporary storage and preserves source bytes")
    func multipartBody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FullParityMultipartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("RoomMarker-测试.zip")
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        try bytes.write(to: archive)
        let before = SHA256.hash(data: try Data(contentsOf: archive))
        let boundary = "RoomMarker-SyntheticBoundary"
        let body = try MultipartZIPBodyBuilder.make(
            archive: archive,
            configuration: .init(endpoint: "https://example.edu/upload", token: "test-token", fieldName: "file"),
            boundary: boundary, temporaryDirectory: root
        )
        defer { try? FileManager.default.removeItem(at: body) }
        #expect(CanonicalPathContainment.isStrictDescendant(
            body, of: root.appendingPathComponent("RoomMarkerUploads", isDirectory: true)
        ))
        let payload = try Data(contentsOf: body)
        #expect(payload.range(of: bytes) != nil)
        #expect(String(decoding: payload.prefix(400), as: UTF8.self).contains("name=\"token\""))
        #expect(String(decoding: payload.prefix(800), as: UTF8.self).contains("name=\"file\""))
        #expect(payload.suffix(Data("\r\n--\(boundary)--\r\n".utf8).count) == Data("\r\n--\(boundary)--\r\n".utf8))
        #expect(SHA256.hash(data: try Data(contentsOf: archive)) == before)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}
