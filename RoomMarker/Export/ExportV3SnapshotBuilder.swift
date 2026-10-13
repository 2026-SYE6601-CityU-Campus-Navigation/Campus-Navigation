import CryptoKit
import Foundation
import SwiftData

@MainActor
final class ExportV3SnapshotBuilder {
    private let photoBuilder: AreaExportSnapshotBuilder
    private let photoStorage: any PhotoFileStoring
    init(photoStorage: any PhotoFileStoring) {
        self.photoStorage = photoStorage
        photoBuilder = AreaExportSnapshotBuilder(photoStorage: photoStorage)
    }

    func build(
        area: Area? = nil, kind: String = "all", tracks: [Track]? = nil,
        areas: [Area]? = nil, rooms: [Room]? = nil, exportedAt: Int64, activeTrackID: UUID? = nil,
        selectedIDs: Set<UUID>? = nil, preparation: V3ExportPreparation? = nil
    ) throws -> ExportV3Snapshot {
        let context = area?.modelContext ?? tracks?.compactMap(\.modelContext).first ??
            areas?.compactMap(\.modelContext).first ?? rooms?.compactMap(\.modelContext).first
        let available = try unique(tracks ?? context?.fetch(FetchDescriptor<Track>()) ?? area?.tracks ?? [])
        let selected: [Track]
        let scope: ExportV3Scope
        if let selectedIDs {
            guard !selectedIDs.isEmpty, selectedIDs.isSubset(of: Set(available.map(\.id))) else {
                throw ExportV3Error.invalid("empty or unavailable selection")
            }
            selected = available.filter { selectedIDs.contains($0.id) }
            scope = .init(kind: "selected", areaId: nil, name: "已选轨迹", trackIds: selectedIDs.map(key).sorted())
        } else if let area {
            selected = available.filter { track in
                (!track.isGlobalRecording && track.area?.id == area.id) ||
                    track.tags.contains { $0.areaStateRawValue == "assigned" && $0.areaID == area.id }
            }
            scope = .init(kind: "area", areaId: key(area.id), name: area.name)
        } else if kind == "unassigned" {
            selected = available.filter { track in
                (!track.isGlobalRecording && track.area == nil) ||
                    track.tags.contains { $0.areaStateRawValue == "unassigned" && $0.areaID == nil }
            }
            scope = .init(kind: "unassigned", areaId: nil, name: "未分区")
        } else {
            guard kind == "all" else { throw ExportV3Error.invalid("scope") }
            selected = available
            scope = .init(kind: "all", areaId: nil, name: "全部轨迹")
        }
        guard !selected.contains(where: { $0.id == activeTrackID }) else { throw ExportV3Error.activeTrack }

        let catalog = try areas ?? context?.fetch(FetchDescriptor<Area>()) ?? []
        var byID: [UUID: Area] = [:]
        for value in catalog + (area.map { [$0] } ?? []) + selected.compactMap(\.area) {
            if let existing = byID[value.id], existing !== value { throw ExportV3Error.invalid("duplicate area") }
            byID[value.id] = value
        }
        var referenced = Set(selected.compactMap { $0.area?.id })
        for track in selected { referenced.formUnion(track.tags.compactMap(\.areaID)) }
        if let area { referenced.insert(area.id) }
        let roomCatalog = try rooms ?? context?.fetch(FetchDescriptor<Room>()) ?? Array(byID.values).flatMap(\.rooms)
        let linkedRoomIDs = Set(selected.flatMap(\.tags).compactMap(\.roomID))
        var roomsByID: [UUID: Room] = [:]
        for room in roomCatalog {
            if let old = roomsByID[room.id], old !== room { throw ExportV3Error.invalid("duplicate room") }
            roomsByID[room.id] = room
        }
        let selectedRooms = roomsByID.values.filter { room in
            linkedRoomIDs.contains(room.id) || (selectedIDs != nil ? false : area != nil ? room.area?.id == area?.id :
                kind == "unassigned" ? room.area == nil : true)
        }.sorted { key($0.id) < key($1.id) }
        if selectedIDs == nil && area == nil && kind == "all" { referenced.formUnion(byID.keys) }
        for room in selectedRooms {
            if let owner = room.area {
                if let existing = byID[owner.id], existing !== owner { throw ExportV3Error.invalid("duplicate room area") }
                byID[owner.id] = owner
                referenced.insert(owner.id)
            }
        }
        let roomDTOs = selectedRooms.map {
            ExportV3Room(id: key($0.id), areaId: $0.area.map { key($0.id) }, name: $0.name,
                code: $0.code, floor: $0.floor, note: $0.note, catalogKey: $0.catalogKey, createdAt: $0.createdAt,
                latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude, pressureHpa: $0.pressureHpa)
        }
        let areaDTOs = try referenced.sorted { key($0) < key($1) }.map { id in
            guard let value = byID[id] else { throw ExportV3Error.invalid("missing area reference") }
            return ExportV3Area(id: key(value.id), name: value.name, note: value.note, createdAt: value.createdAt,
                                category: value.category, catalogKey: value.catalogKey)
        }
        var photos: [ExportV3PhotoFile] = []
        let trackDTOs = try selected.sorted {
            ($0.startedAt, key($0.id)) < ($1.startedAt, key($1.id))
        }.map { try makeTrack($0, rooms: roomsByID, photos: &photos, preparation: preparation) }
        let manifest = ExportV3Manifest(
            version: 3, app: "RoomMarker", sourcePlatform: "ios", capabilities: ExportContract.capabilities,
            exportedAt: exportedAt, scope: scope, areas: areaDTOs, trackCount: trackDTOs.count,
            tracks: trackDTOs.map {
                .init(id: $0.id, file: $0.file, name: $0.name, startedAt: $0.startedAt, endedAt: $0.endedAt, counts: $0.counts)
            }, rooms: roomDTOs
        )
        let result = ExportV3Snapshot(manifest: manifest, tracks: trackDTOs, photos: photos)
        // Prepared skeletons are internal only, validated completely by the worker
        // before any archive is published. The synchronous reference path is unchanged.
        if preparation == nil { try ExportV3Validator.validate(result) }
        return result
    }

    private func unique(_ tracks: [Track]) throws -> [Track] {
        var seen: [UUID: Track] = [:]
        for track in tracks {
            if let existing = seen[track.id], existing !== track { throw ExportV3Error.invalid("duplicate track") }
            seen[track.id] = track
        }
        return Array(seen.values)
    }

    private func makeTrack(_ track: Track, rooms: [UUID: Room], photos files: inout [ExportV3PhotoFile],
                           preparation: V3ExportPreparation?) throws -> ExportV3Track {
        let points = try track.points.sorted { ($0.timeMs, key($0.id)) < ($1.timeMs, key($1.id)) }.map { p in
            guard p.track?.id == track.id else { throw ExportV3Error.invalid("point owner") }
            guard p.wifiAvailabilityRawValue == "unsupported", p.wifiCount == nil, p.wifiTop == nil else {
                throw ExportValidationError.unexpectedWiFiObservation(trackID: track.id, pointID: p.id)
            }
            return ExportV3SensorRecord(id: key(p.id), timeMs: p.timeMs, segmentId: p.segmentID.map(key), note: nil,
                                        latitude: p.latitude, longitude: p.longitude, altitude: p.altitude, accuracy: p.accuracy,
                                        pressureHpa: p.pressureHpa, magneticX: p.magneticX, magneticY: p.magneticY,
                                        magneticZ: p.magneticZ, headingDeg: p.headingDeg)
        }
        let tags = try track.tags.sorted { ($0.timeMs, $0.createdAt, key($0.id)) < ($1.timeMs, $1.createdAt, key($1.id)) }.map { tag in
            guard tag.track?.id == track.id else { throw ExportV3Error.invalid("tag owner") }
            guard TrackTagType(rawValue: tag.tagTypeRawValue) != nil else {
                throw ExportValidationError.unsupportedTagValue(trackID: track.id, tagID: tag.id, value: tag.tagTypeRawValue)
            }
            let photoID = tag.isNode ? try NodePhotoAssociation.photo(for: tag).id : nil
            let binding: ExportV3RoomBinding?
            if let roomID = tag.roomID {
                guard let name = tag.roomNameSnapshot, let code = tag.roomCodeSnapshot else {
                    throw ExportV3Error.invalid("room binding snapshot")
                }
                binding = .init(roomId: key(roomID), nameSnapshot: name, codeSnapshot: code,
                    doorRole: tag.roomDoorRole, status: NodeRoomBinding.status(for: tag, room: rooms[roomID]))
            } else {
                guard tag.roomNameSnapshot == nil, tag.roomCodeSnapshot == nil, tag.roomDoorRole == nil else {
                    throw ExportV3Error.invalid("orphan room binding snapshot")
                }
                binding = nil
            }
            return ExportV3Tag(id: key(tag.id), timeMs: tag.timeMs, tagType: tag.tagTypeRawValue, note: tag.note,
                               latitude: tag.latitude, longitude: tag.longitude, altitude: tag.altitude,
                               headingDeg: tag.headingDeg, createdAt: tag.createdAt, recordKind: tag.recordKindRawValue,
                               areaId: tag.areaID.map(key), areaState: tag.areaStateRawValue, floor: tag.floor,
                               photoId: photoID.map(key), accuracy: tag.accuracy, pressureHpa: tag.pressureHpa,
                               roomBinding: binding)
        }
        let photos = try track.photos.sorted { ($0.timeMs, $0.createdAt, key($0.id)) < ($1.timeMs, $1.createdAt, key($1.id)) }.map { photo in
            guard photo.track?.id == track.id else { throw ExportV3Error.invalid("photo owner") }
            let byteCount: Int, sha256: String
            if let preparation, let storage = photoStorage as? LocalPhotoFileStore {
                guard NodePhotoAssociation.isOwnedFilePath(photo.filePath, trackID: track.id) else {
                    throw ExportValidationError.invalidPhotoPath(trackID: track.id, photoID: photo.id)
                }
                preparation.photos[photo.filePath] = try storage.exportSource(relativePath: photo.filePath)
                byteCount = 0; sha256 = ""
            } else {
                let source = try photoBuilder.buildPhoto(photo, track: track)
                files.append(.init(path: source.relativePath, data: source.jpegData))
                byteCount = source.jpegData.count; sha256 = digest(source.jpegData)
            }
            return ExportV3Photo(id: key(photo.id), timeMs: photo.timeMs, file: photo.filePath,
                                 note: photo.note, latitude: photo.latitude, longitude: photo.longitude,
                                 altitude: photo.altitude, headingDeg: photo.headingDeg, createdAt: photo.createdAt,
                                 kind: photo.kindRawValue, tagId: photo.tagID.map(key), byteCount: byteCount,
                                 sha256: sha256, accuracy: photo.accuracy, pressureHpa: photo.pressureHpa)
        }
        let segments = try track.segments.sorted { $0.ordinal < $1.ordinal }.map { segment in
            guard segment.track?.id == track.id else { throw ExportV3Error.invalid("segment owner") }
            return ExportV3Segment(id: key(segment.id), ordinal: segment.ordinal, startedAt: segment.startedAt,
                                   endedAt: segment.endedAt, environment: segment.environmentRawValue)
        }
        let corners = try track.corners.sorted { ($0.timeMs, key($0.id)) < ($1.timeMs, key($1.id)) }.map { c in
            guard c.track?.id == track.id else { throw ExportV3Error.invalid("corner owner") }
            return ExportV3SensorRecord(id: key(c.id), timeMs: c.timeMs, segmentId: c.segmentID.map(key), note: c.note,
                                        latitude: c.latitude, longitude: c.longitude, altitude: c.altitude, accuracy: c.accuracy,
                                        pressureHpa: c.pressureHpa, magneticX: c.magneticX, magneticY: c.magneticY,
                                        magneticZ: c.magneticZ, headingDeg: c.headingDeg)
        }
        let batches = try track.imuBatches.sorted { ($0.firstTimeMs, key($0.id)) < ($1.firstTimeMs, key($1.id)) }.map { batch in
            guard batch.track?.id == track.id else { throw ExportV3Error.invalid("IMU owner") }
            if let preparation { preparation.imuPayloads[key(batch.id)] = batch.payload }
            let samples = try (preparation == nil ? batch.decodedSamples() : []).map { sample in
                ExportV3IMUSample(kind: sample.kind, sensorTimeSeconds: sample.sensorTimeSeconds, timeMs: sample.timeMs,
                                  receivedAtMs: sample.receivedAtMs, segmentId: key(sample.segmentID), x: sample.x, y: sample.y, z: sample.z)
            }
            return ExportV3IMUBatch(id: key(batch.id), sampleCount: batch.sampleCount, accelerationCount: batch.accelerationCount,
                                    gyroscopeCount: batch.gyroscopeCount, firstTimeMs: batch.firstTimeMs, lastTimeMs: batch.lastTimeMs,
                                    lastAccelerationTime: batch.lastAccelerationTime, lastGyroscopeTime: batch.lastGyroscopeTime, samples: samples)
        }
        let imu = ExportV3IMU(
            requested: track.rawIMURequested, requestedIntervalSeconds: track.rawIMUInterval,
            accelerometerUnit: "g", gyroscopeUnit: "rad/s", accelerometerIncludesGravity: true,
            coordinateFrame: "device-right-top-out", sensorTimeBase: "secondsSinceBoot",
            measurementTimeMapping: "utcMillisecondsFixedSessionAnchor", backgroundPolicy: "foregroundOnlyNoCatchUp",
            accelerometerState: track.rawAccelState, gyroscopeState: track.rawGyroState, rejectedCount: track.rawIMURejectedCount,
            sampleCount: batches.reduce(0) { $0 + $1.sampleCount }, accelerationCount: batches.reduce(0) { $0 + $1.accelerationCount },
            gyroscopeCount: batches.reduce(0) { $0 + $1.gyroscopeCount }, batches: batches
        )
        return ExportV3Track(
            version: 3, sourcePlatform: "ios", capabilities: ExportContract.capabilities,
            id: key(track.id), name: track.name, startedAt: track.startedAt, endedAt: track.endedAt,
            isGlobalRecording: track.isGlobalRecording, legacyAreaId: track.area.map { key($0.id) },
            legacyAreaName: track.legacyAreaName, isSegmentedRecording: track.isSegmentedRecording,
            counts: .init(pointCount: points.count, tagCount: tags.count, nodeCount: tags.filter { $0.recordKind == "node" }.count,
                          photoCount: photos.count, segmentCount: segments.count, cornerCount: corners.count, imuSampleCount: imu.sampleCount),
            points: points, tags: tags, photos: photos, segments: segments, corners: corners, imu: imu
        )
    }

    private func key(_ id: UUID) -> String { id.uuidString.lowercased() }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
