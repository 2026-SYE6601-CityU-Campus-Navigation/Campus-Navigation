import Foundation
import Security

nonisolated struct ZIPUploadConfiguration: Equatable, Sendable {
    let endpoint: String
    let token: String
    let fieldName: String
}

nonisolated struct ZIPUploadResult: Equatable, Sendable {
    let statusCode: Int
    let responseBody: String
}

enum ZIPUploadError: LocalizedError, Equatable {
    case missingEndpoint
    case invalidEndpoint
    case invalidFieldName
    case invalidArchive
    case unsafeTemporaryPath
    case rejected(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEndpoint: "请先在上传设置中填写接收地址。"
        case .invalidEndpoint: "上传地址必须是 http:// 或 https://，且不能包含账号、密码或片段。"
        case .invalidFieldName: "文件字段名只能包含字母、数字、下划线或连字符。"
        case .invalidArchive: "待上传文件不是可读取的 ZIP，未发起网络请求。"
        case .unsafeTemporaryPath: "上传暂存路径不安全，操作已停止。"
        case let .rejected(code, message): "服务器拒绝上传（HTTP \(code)）\(message.isEmpty ? "" : "：\(message)")"
        case .invalidResponse: "上传完成但服务器响应无效。"
        }
    }
}

nonisolated enum ZIPUploadConfigurationValidator {
    static func validate(_ configuration: ZIPUploadConfiguration) throws -> URL {
        let raw = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw ZIPUploadError.missingEndpoint }
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else {
            throw ZIPUploadError.invalidEndpoint
        }
        let field = configuration.fieldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-") )
        guard !field.isEmpty, field.count <= 64,
              field.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ZIPUploadError.invalidFieldName
        }
        return url
    }
}

protocol ZIPUploading: Sendable {
    func upload(archive: URL, configuration: ZIPUploadConfiguration) async throws -> ZIPUploadResult
}

final class URLSessionZIPUploader: ZIPUploading, @unchecked Sendable {
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func upload(archive: URL, configuration: ZIPUploadConfiguration) async throws -> ZIPUploadResult {
        let endpoint = try ZIPUploadConfigurationValidator.validate(configuration)
        guard archive.pathExtension.lowercased() == "zip", archive.isFileURL,
              fileManager.isReadableFile(atPath: archive.path),
              (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 > 0 }) == true else {
            throw ZIPUploadError.invalidArchive
        }
        let boundary = "RoomMarker-\(UUID().uuidString)"
        let body = try MultipartZIPBodyBuilder.make(
            archive: archive, configuration: configuration, boundary: boundary,
            temporaryDirectory: fileManager.temporaryDirectory, fileManager: fileManager
        )
        defer { try? fileManager.removeItem(at: body) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = configuration.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let size = try body.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let (data, response) = try await session.upload(for: request, fromFile: body)
        guard let http = response as? HTTPURLResponse else { throw ZIPUploadError.invalidResponse }
        let responseBody = String(decoding: data.prefix(16_384), as: UTF8.self)
        guard (200..<300).contains(http.statusCode) else {
            throw ZIPUploadError.rejected(http.statusCode, responseBody)
        }
        return .init(statusCode: http.statusCode, responseBody: responseBody)
    }

}

// Builds beside the export, never in memory: the archive may contain long IMU sessions.
// Internal visibility permits deterministic byte/source-integrity tests without a network request.
nonisolated enum MultipartZIPBodyBuilder {
    static func make(archive: URL, configuration: ZIPUploadConfiguration, boundary: String,
                     temporaryDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        let root = temporaryDirectory.appendingPathComponent("RoomMarkerUploads", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let output = CanonicalPathContainment.resolve(relativePath: "\(UUID().uuidString).multipart", under: root),
              CanonicalPathContainment.isStrictDescendant(output, of: root, fileManager: fileManager) else {
            throw ZIPUploadError.unsafeTemporaryPath
        }
        guard fileManager.createFile(atPath: output.path, contents: nil) else { throw ZIPUploadError.unsafeTemporaryPath }
        let writer = try FileHandle(forWritingTo: output)
        do {
            let field = configuration.fieldName.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = configuration.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                try writer.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"token\"\r\n\r\n\(token)\r\n".utf8))
            }
            let fallbackName = archive.lastPathComponent.unicodeScalars.map { scalar in
                scalar.isASCII && !"\\/\r\n\"".unicodeScalars.contains(scalar) ? String(scalar) : "_"
            }.joined()
            try writer.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(fallbackName)\"\r\nContent-Type: application/zip\r\n\r\n".utf8))
            let reader = try FileHandle(forReadingFrom: archive)
            defer { try? reader.close() }
            while let chunk = try reader.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                try Task.checkCancellation()
                try writer.write(contentsOf: chunk)
            }
            try writer.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try writer.synchronize()
            try writer.close()
            return output
        } catch {
            try? writer.close()
            try? fileManager.removeItem(at: output)
            throw error
        }
    }
}

enum ZIPUploadSettings {
    private static let endpointKey = "upload.endpoint"
    private static let fieldKey = "upload.field"
    private static let account = "RoomMarkerUploadToken"
    private static let service = Bundle.main.bundleIdentifier ?? "RoomMarker"

    static func load(defaults: UserDefaults = .standard) -> ZIPUploadConfiguration {
        .init(endpoint: defaults.string(forKey: endpointKey) ?? "",
              token: readToken() ?? "", fieldName: defaults.string(forKey: fieldKey) ?? "file")
    }

    static func save(_ configuration: ZIPUploadConfiguration, defaults: UserDefaults = .standard) throws {
        _ = try ZIPUploadConfigurationValidator.validate(configuration)
        defaults.set(configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: endpointKey)
        defaults.set(configuration.fieldName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: fieldKey)
        try saveToken(configuration.token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func readToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
