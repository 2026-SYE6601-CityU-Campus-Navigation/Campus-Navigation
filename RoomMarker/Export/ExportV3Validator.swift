import CryptoKit
import Foundation

nonisolated
enum ExportV3Validator {
    static func validate(_ snapshot: ExportV3Snapshot, validateSamples: Bool = true, validatePhotoBytes: Bool = true) throws {
        let m = snapshot.manifest
        try require(m.version == 3 && m.app == "RoomMarker" && m.sourcePlatform == "ios" &&
                    m.capabilities.nearbyWifiFingerprint == .unsupported, "manifest version/platform")
        try require(["all", "area", "unassigned", "selected"].contains(m.scope.kind), "scope")
        try require(m.photoIndex == nil || m.photoIndex == "index.html", "photo index")
        if m.scope.kind == "selected" {
            let ids = m.scope.trackIds ?? []
            try unique(ids, "selected IDs")
            try require(!ids.isEmpty && Set(ids) == Set(snapshot.tracks.map(\.id)), "selection")
        } else { try require(m.scope.trackIds == nil, "unexpected selection") }
        try unique(m.areas.map(\.id), "area IDs")
        let areas = Set(m.areas.map(\.id))
        let rooms = m.rooms ?? []
        try unique(rooms.map(\.id), "room IDs")
        for room in rooms {
            if let areaID = room.areaId { try require(areas.contains(areaID), "room area") }
            try finite([room.latitude, room.longitude, room.altitude, room.pressureHpa])
        }
        if m.scope.kind == "area" {
            try require(m.scope.areaId.map(areas.contains) == true, "scope area")
        } else { try require(m.scope.areaId == nil, "scope area") }
        try unique(snapshot.tracks.map(\.id), "track IDs")
        try require(m.trackCount == snapshot.tracks.count && m.tracks.count == snapshot.tracks.count, "manifest count")
        for (entry, track) in zip(m.tracks, snapshot.tracks) {
            try require(entry == ExportV3ManifestTrack(id: track.id, file: track.file, name: track.name,
                                                      startedAt: track.startedAt, endedAt: track.endedAt, counts: track.counts), "manifest track")
            try validate(track, areas: areas, rooms: rooms, validateSamples: validateSamples)
            if m.scope.kind == "area" {
                try require((!track.isGlobalRecording && track.legacyAreaId == m.scope.areaId) ||
                            track.tags.contains { $0.areaState == "assigned" && $0.areaId == m.scope.areaId }, "track outside scope")
            } else if m.scope.kind == "unassigned" {
                try require((!track.isGlobalRecording && track.legacyAreaId == nil) ||
                            track.tags.contains { $0.areaState == "unassigned" && $0.areaId == nil }, "track outside scope")
            }
        }
        // IDs remain unique per model across the whole archive, not just each Track.
        try unique(snapshot.tracks.flatMap { $0.points.map(\.id) }, "point IDs")
        try unique(snapshot.tracks.flatMap { $0.tags.map(\.id) }, "tag IDs")
        try unique(snapshot.tracks.flatMap { $0.photos.map(\.id) }, "photo IDs")
        try unique(snapshot.tracks.flatMap { $0.segments.map(\.id) }, "segment IDs")
        try unique(snapshot.tracks.flatMap { $0.corners.map(\.id) }, "corner IDs")
        try unique(snapshot.tracks.flatMap { $0.imu.batches.map(\.id) }, "IMU batch IDs")
        let metadata = snapshot.tracks.flatMap(\.photos)
        try require(Set(metadata.map(\.file)).count == metadata.count, "photo paths")
        if !validatePhotoBytes { return } // Worker verifies every file before publication.
        try require(
                    Set(snapshot.photos.map(\.path)).count == snapshot.photos.count && metadata.count == snapshot.photos.count, "photo paths")
        let files = Dictionary(uniqueKeysWithValues: snapshot.photos.map { ($0.path, $0.data) })
        for photo in metadata {
            guard let data = files[photo.file] else { throw ExportV3Error.invalid("missing photo payload") }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try require(data.count == photo.byteCount && hash == photo.sha256 && NodeJPEGValidation.isReadable(data), "photo integrity")
        }
    }

    private static func validate(_ t: ExportV3Track, areas: Set<String>, rooms: [ExportV3Room], validateSamples: Bool) throws {
        try require(t.version == 3 && t.sourcePlatform == "ios" && t.capabilities.nearbyWifiFingerprint == .unsupported, "track version/platform")
        try require(t.endedAt.map { $0 >= t.startedAt } ?? true, "track time")
        if let area = t.legacyAreaId { try require(areas.contains(area), "legacy area") }
        try require(t.counts == ExportV3Counts(pointCount: t.points.count, tagCount: t.tags.count,
                                              nodeCount: t.tags.filter { $0.recordKind == "node" }.count,
                                              photoCount: t.photos.count, segmentCount: t.segments.count,
                                              cornerCount: t.corners.count, imuSampleCount: t.imu.sampleCount), "track counts")
        try unique(t.tags.map(\.id), "tag IDs")
        try unique(t.photos.map(\.id), "photo IDs")
        try unique(t.segments.map(\.id), "segment IDs")
        try require(ordered(t.points.map(\.timeMs)) && ordered(t.tags.map(\.timeMs)) &&
                    ordered(t.photos.map(\.timeMs)) && ordered(t.corners.map(\.timeMs)), "record ordering")
        if t.isSegmentedRecording {
            try require(!t.segments.isEmpty && t.segments.first?.startedAt == t.startedAt, "segment start")
            for (index, s) in t.segments.enumerated() {
                try require(s.ordinal == index && TrackEnvironment(rawValue: s.environment) != nil, "segment ordinal/environment")
                if index + 1 < t.segments.count {
                    try require(s.endedAt == t.segments[index + 1].startedAt && t.segments[index + 1].startedAt > s.startedAt, "segment boundary")
                } else {
                    try require(s.endedAt == t.endedAt && (s.endedAt.map { $0 >= s.startedAt } ?? true), "segment end")
                }
            }
        } else { try require(t.segments.isEmpty && t.corners.isEmpty, "legacy structure") }
        for p in t.points + t.corners {
            try finite([p.latitude, p.longitude, p.altitude, p.accuracy, p.pressureHpa,
                        p.magneticX, p.magneticY, p.magneticZ, p.headingDeg])
            try membership(p.segmentId, time: p.timeMs, track: t)
        }
        for tag in t.tags {
            if let binding = tag.roomBinding {
                try require(tag.recordKind == "node" && !binding.nameSnapshot.isEmpty && UUID(uuidString: binding.roomId) != nil,
                            "room binding identity")
                try require(["教室", "门", "门禁"].contains(tag.tagType), "room binding type")
                try require(tag.tagType == "教室" ? binding.doorRole == nil : ["前门", "后门"].contains(binding.doorRole ?? ""), "room door role")
                let room = rooms.first { $0.id == binding.roomId }
                let sameArea = room != nil && tag.areaState == "assigned" && room?.areaId == tag.areaId
                switch binding.status {
                case "linked": try require(sameArea, "linked room")
                case "missing": try require(room == nil, "missing room")
                case "relocated": try require(room != nil && !sameArea, "relocated room")
                default: throw ExportV3Error.invalid("room binding status")
                }
            }
            try finite([tag.latitude, tag.longitude, tag.altitude, tag.headingDeg])
            try quality(accuracy: tag.accuracy, pressureHpa: tag.pressureHpa)
            try require(TrackTagType(rawValue: tag.tagType) != nil && ["legacy", "node"].contains(tag.recordKind), "tag kind/type")
            if tag.areaState == "assigned" {
                try require(tag.areaId.map(areas.contains) == true, "tag area")
            } else {
                try require(["unknown", "unassigned"].contains(tag.areaState) && tag.areaId == nil, "tag area state")
            }
            if tag.recordKind == "node" {
                let linked = t.photos.filter { $0.tagId == tag.id }
                try require(linked.count == 1 && linked.first?.id == tag.photoId && linked.first?.kind == "node", "node photo link")
            } else { try require(tag.photoId == nil && !t.photos.contains { $0.tagId == tag.id }, "legacy tag link") }
        }
        for photo in t.photos {
            try finite([photo.latitude, photo.longitude, photo.altitude, photo.headingDeg])
            try quality(accuracy: photo.accuracy, pressureHpa: photo.pressureHpa)
            try require(ArchivePathValidator.isSafe(photo.file) &&
                        photo.file.hasPrefix("photos/\(t.id)/") && photo.file.hasSuffix(".jpg"), "photo path")
            try require(["node", "scenery", "legacyUnlinked"].contains(photo.kind), "photo kind")
            if photo.kind == "node" {
                guard let tag = t.tags.first(where: { $0.id == photo.tagId }) else { throw ExportV3Error.invalid("orphan node photo") }
                try require(tag.recordKind == "node" && tag.photoId == photo.id && tag.timeMs == photo.timeMs &&
                            tag.latitude == photo.latitude && tag.longitude == photo.longitude &&
                            tag.altitude == photo.altitude && tag.headingDeg == photo.headingDeg &&
                            tag.accuracy == photo.accuracy && tag.pressureHpa == photo.pressureHpa, "node photo evidence")
            } else { try require(photo.tagId == nil, "independent photo link") }
        }
        try validateIMU(t, validateSamples: validateSamples)
    }

    private static func validateIMU(_ t: ExportV3Track, validateSamples: Bool) throws {
        let imu = t.imu
        try require(imu.accelerometerUnit == "g" && imu.gyroscopeUnit == "rad/s" && imu.accelerometerIncludesGravity &&
                    imu.coordinateFrame == "device-right-top-out" && imu.sensorTimeBase == "secondsSinceBoot" &&
                    imu.measurementTimeMapping == "utcMillisecondsFixedSessionAnchor" && imu.backgroundPolicy == "foregroundOnlyNoCatchUp", "IMU semantics")
        try require(RawIMUChannelState(rawValue: imu.accelerometerState) != nil &&
                    RawIMUChannelState(rawValue: imu.gyroscopeState) != nil && imu.rejectedCount >= 0, "IMU status")
        if !imu.requested {
            try require(imu.batches.isEmpty && imu.requestedIntervalSeconds == nil && imu.rejectedCount == 0 &&
                        imu.accelerometerState == "notRequested" && imu.gyroscopeState == "notRequested", "legacy IMU")
        } else {
            try require(t.isSegmentedRecording && imu.requestedIntervalSeconds.map { $0.isFinite && $0 > 0 } == true, "IMU request")
        }
        var times: [RawIMUKind: Set<Double>] = [:]
        for batch in imu.batches {
            try require(batch.sampleCount > 0 && batch.sampleCount <= RawIMUPolicy.batchSize &&
                        batch.accelerationCount >= 0 && batch.gyroscopeCount >= 0 &&
                        batch.accelerationCount + batch.gyroscopeCount == batch.sampleCount, "IMU metadata")
            if validateSamples { try validateIMUBatch(batch, track: t, times: &times) }
        }
        try require(imu.sampleCount == imu.batches.reduce(0) { $0 + $1.sampleCount } &&
                    imu.accelerationCount == imu.batches.reduce(0) { $0 + $1.accelerationCount } &&
                    imu.gyroscopeCount == imu.batches.reduce(0) { $0 + $1.gyroscopeCount }, "IMU totals")
    }

    static func validateIMUBatch(_ batch: ExportV3IMUBatch, track t: ExportV3Track,
                                 times: inout [RawIMUKind: Set<Double>]) throws {
            let samples = batch.samples
            try require(!samples.isEmpty && samples.count <= RawIMUPolicy.batchSize && batch.sampleCount == samples.count &&
                        batch.accelerationCount == samples.filter { $0.kind == .accelerometer }.count &&
                        batch.gyroscopeCount == samples.filter { $0.kind == .gyroscope }.count &&
                        batch.firstTimeMs == samples.map(\.timeMs).min() && batch.lastTimeMs == samples.map(\.timeMs).max(), "IMU batch counts/time")
            for kind in RawIMUKind.allCases {
                let channel = samples.filter { $0.kind == kind }.map(\.sensorTimeSeconds)
                let last = kind == .accelerometer ? batch.lastAccelerationTime : batch.lastGyroscopeTime
                try require(last == channel.max() && zip(channel, channel.dropFirst()).allSatisfy { $0 < $1 }, "IMU channel order")
            }
            for sample in samples {
                try finite([sample.sensorTimeSeconds, sample.x, sample.y, sample.z])
                try require(sample.sensorTimeSeconds >= 0 && times[sample.kind, default: []].insert(sample.sensorTimeSeconds).inserted, "IMU duplicate time")
                try membership(sample.segmentId, time: sample.timeMs, track: t)
            }
    }

    private static func membership(_ id: String?, time: Int64, track: ExportV3Track) throws {
        if !track.isSegmentedRecording { try require(id == nil, "legacy segment reference"); return }
        guard let segment = track.segments.first(where: { $0.id == id }) else { throw ExportV3Error.invalid("segment reference") }
        let upperOK = segment.endedAt.map {
            time < $0 || (segment.ordinal == track.segments.count - 1 && time == $0)
        } ?? true
        try require(time >= segment.startedAt && upperOK, "segment sample time")
    }

    private static func quality(accuracy: Double?, pressureHpa: Double?) throws {
        try require(accuracy.map { $0.isFinite && $0 >= 0 } ?? true, "invalid accuracy")
        try require(pressureHpa.map { $0.isFinite && $0 > 0 } ?? true, "invalid pressure")
    }

    private static func finite(_ values: [Double?]) throws { try require(values.allSatisfy { $0?.isFinite ?? true }, "nonfinite sensor") }
    private static func ordered(_ times: [Int64]) -> Bool { zip(times, times.dropFirst()).allSatisfy { $0 <= $1 } }
    private static func unique(_ ids: [String], _ category: String) throws {
        try require(Set(ids).count == ids.count && ids.allSatisfy { UUID(uuidString: $0)?.uuidString.lowercased() == $0 }, category)
    }
    private static func require(_ condition: Bool, _ category: String) throws {
        guard condition else { throw ExportV3Error.invalid(category) }
    }
}
