import CryptoKit
import Foundation
import ImageIO

// No SwiftData objects, UIImage objects, source writes or actor hops in this worker.
nonisolated enum V3StreamingExporter {
    static func stage(_ input: V3PreparedExport, base: URL, sessionID: UUID) throws -> V3StagedExport {
        let fm = FileManager.default
        guard let root = CanonicalPathContainment.resolve(relativePath: sessionID.uuidString.lowercased(), under: base) else {
            throw ExportV3Error.invalid("staging root")
        }
        guard !fm.fileExists(atPath: root.path) else { throw ExportValidationError.stagingSessionAlreadyExists }
        var metrics = V3ExportMetrics(ranOnMainThread: Thread.isMainThread)
        var tracks = input.skeleton.tracks
        var manifest = input.skeleton.manifest
        manifest.photoIndex = "index.html"
        var photoURLs: [URL] = [], trackURLs: [URL] = []
        var paths: Set<String> = ["manifest.json", "index.html"]
        do {
            try Task.checkCancellation()
            // Includes all cross-Track ID, count, metadata and relationship checks.
            try ExportV3Validator.validate(input.skeleton, validateSamples: false, validatePhotoBytes: false)
            let expectedPhotos = Set(tracks.flatMap { $0.photos.map(\.file) })
            let expectedBatches = Set(tracks.flatMap { $0.imu.batches.map(\.id) })
            guard expectedPhotos == Set(input.photos.keys), expectedBatches == Set(input.imuPayloads.keys) else {
                throw ExportV3Error.invalid("prepared payload inventory")
            }
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for ti in tracks.indices {
                try Task.checkCancellation()
                for pi in tracks[ti].photos.indices {
                    let photo = tracks[ti].photos[pi]
                    guard let source = input.photos[photo.file], paths.insert(photo.file).inserted else {
                        throw ExportV3Error.invalid("prepared photo")
                    }
                    let destination = try child(photo.file, root: root)
                    let result = try copyPhoto(source, path: photo.file, to: destination, metrics: &metrics)
                    tracks[ti].photos[pi].byteCount = result.count
                    tracks[ti].photos[pi].sha256 = result.hash
                    photoURLs.append(destination)
                }
                let track = tracks[ti]
                guard paths.insert(track.file).inserted else { throw ExportV3Error.invalid("duplicate file") }
                let url = try child(track.file, root: root)
                try writeTrack(track, payloads: input.imuPayloads, to: url, metrics: &metrics)
                trackURLs.append(url)
            }
            let manifestURL = try child("manifest.json", root: root)
            try ExportJSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
            let indexURL = try child("index.html", root: root)
            try PhotoHTMLIndex.make(manifest: manifest, tracks: tracks).write(to: indexURL, options: .atomic)
            try Task.checkCancellation()
            return .init(staging: .init(sessionDirectory: root, manifestURL: manifestURL,
                trackURLs: trackURLs, photoURLs: photoURLs, auxiliaryURLs: [indexURL]),
                name: manifest.scope.name, exportedAt: manifest.exportedAt, metrics: metrics)
        } catch {
            if CanonicalPathContainment.isStrictDescendant(root, of: base), fm.fileExists(atPath: root.path) {
                try? fm.removeItem(at: root)
            }
            throw error
        }
    }

    private static func child(_ path: String, root: URL) throws -> URL {
        guard let url = CanonicalPathContainment.resolve(relativePath: path, under: root) else {
            throw ExportV3Error.invalid("staging path")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard CanonicalPathContainment.isStrictDescendant(url, of: root) else { throw ExportV3Error.invalid("staging escape") }
        return url
    }

    private static func copyPhoto(_ source: V3PhotoSource, path: String, to destination: URL,
                                   metrics: inout V3ExportMetrics) throws -> (count: Int, hash: String) {
        guard CanonicalPathContainment.relativePath(of: source.url, under: source.root) == path else {
            throw ExportV3Error.invalid("source photo containment")
        }
        let values = try source.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true else { throw ExportV3Error.invalid("source photo file") }
        let input = try FileHandle(forReadingFrom: source.url)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hash = SHA256(), count = 0
        while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty {
            try Task.checkCancellation()
            metrics.maxCopyChunkBytes = max(metrics.maxCopyChunkBytes, bytes.count)
            count += bytes.count; hash.update(data: bytes)
            try output.write(contentsOf: bytes)
        }
        try output.close()
        let after = try source.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard count > 0, count == values.fileSize, after.fileSize == values.fileSize,
              after.contentModificationDate == values.contentModificationDate else { throw ExportV3Error.invalid("photo changed during export") }
        try autoreleasepool {
            guard let image = CGImageSourceCreateWithURL(destination as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(image) as String? == "public.jpeg",
                  CGImageSourceGetCount(image) == 1,
                  CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil,
                  CGImageSourceGetStatus(image) == .statusComplete else { throw ExportV3Error.invalid("photo JPEG integrity") }
        }
        metrics.copiedPhotoCount += 1
        return (count, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private static func writeTrack(_ t: ExportV3Track, payloads: [String: Data], to url: URL,
                                    metrics: inout V3ExportMetrics) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let w = StreamingJSONObject(handle)
        try w.begin()
        try w.field("version", t.version); try w.field("sourcePlatform", t.sourcePlatform)
        try w.field("capabilities", t.capabilities); try w.field("id", t.id); try w.field("name", t.name)
        try w.field("startedAt", t.startedAt); if let value = t.endedAt { try w.field("endedAt", value) }
        try w.field("isGlobalRecording", t.isGlobalRecording)
        if let value = t.legacyAreaId { try w.field("legacyAreaId", value) }
        if let value = t.legacyAreaName { try w.field("legacyAreaName", value) }
        try w.field("isSegmentedRecording", t.isSegmentedRecording); try w.field("counts", t.counts)
        try w.field("points", t.points); try w.field("tags", t.tags); try w.field("photos", t.photos)
        try w.field("segments", t.segments); try w.field("corners", t.corners)
        try w.key("imu")
        let i = StreamingJSONObject(handle), imu = t.imu
        try i.begin(); try i.field("requested", imu.requested)
        if let value = imu.requestedIntervalSeconds { try i.field("requestedIntervalSeconds", value) }
        try i.field("accelerometerUnit", imu.accelerometerUnit); try i.field("gyroscopeUnit", imu.gyroscopeUnit)
        try i.field("accelerometerIncludesGravity", imu.accelerometerIncludesGravity)
        try i.field("coordinateFrame", imu.coordinateFrame); try i.field("sensorTimeBase", imu.sensorTimeBase)
        try i.field("measurementTimeMapping", imu.measurementTimeMapping); try i.field("backgroundPolicy", imu.backgroundPolicy)
        try i.field("accelerometerState", imu.accelerometerState); try i.field("gyroscopeState", imu.gyroscopeState)
        try i.field("rejectedCount", imu.rejectedCount); try i.field("sampleCount", imu.sampleCount)
        try i.field("accelerationCount", imu.accelerationCount); try i.field("gyroscopeCount", imu.gyroscopeCount)
        try i.key("batches"); try i.raw("[")
        var times: [RawIMUKind: Set<Double>] = [:]
        for (index, metadata) in imu.batches.enumerated() {
            try Task.checkCancellation()
            guard let payload = payloads[metadata.id] else { throw ExportV3Error.invalid("missing IMU payload") }
            try autoreleasepool {
                let raw = try JSONDecoder().decode([RawIMUSample].self, from: payload)
                guard raw.count <= RawIMUPolicy.batchSize else { throw ExportV3Error.invalid("IMU batch size") }
                let samples = raw.map { s in
                    ExportV3IMUSample(kind: s.kind, sensorTimeSeconds: s.sensorTimeSeconds, timeMs: s.timeMs,
                        receivedAtMs: s.receivedAtMs, segmentId: s.segmentID.uuidString.lowercased(), x: s.x, y: s.y, z: s.z)
                }
                let batch = ExportV3IMUBatch(id: metadata.id, sampleCount: metadata.sampleCount,
                    accelerationCount: metadata.accelerationCount, gyroscopeCount: metadata.gyroscopeCount,
                    firstTimeMs: metadata.firstTimeMs, lastTimeMs: metadata.lastTimeMs,
                    lastAccelerationTime: metadata.lastAccelerationTime, lastGyroscopeTime: metadata.lastGyroscopeTime, samples: samples)
                try ExportV3Validator.validateIMUBatch(batch, track: t, times: &times)
                metrics.maxDecodedIMUSamples = max(metrics.maxDecodedIMUSamples, samples.count)
                metrics.encodedIMUSamples += samples.count
                if index > 0 { try i.raw(",") }
                try handle.write(contentsOf: ExportJSONEncoder().encode(batch))
            }
        }
        try i.raw("]"); try i.end(); try w.end(); try handle.synchronize()
    }
}

private nonisolated final class StreamingJSONObject {
    let handle: FileHandle
    var first = true
    init(_ handle: FileHandle) { self.handle = handle }
    func raw(_ s: String) throws { try handle.write(contentsOf: Data(s.utf8)) }
    func begin() throws { try raw("{") }
    func end() throws { try raw("}") }
    func key(_ name: String) throws {
        try Task.checkCancellation()
        if !first { try raw(",") }; first = false
        try handle.write(contentsOf: JSONEncoder().encode(name)); try raw(":")
    }
    func field<T: Encodable>(_ name: String, _ value: T) throws {
        try key(name); try handle.write(contentsOf: ExportJSONEncoder().encode(value))
    }
}
