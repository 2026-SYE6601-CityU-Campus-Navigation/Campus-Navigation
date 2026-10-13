import Foundation
import SwiftData
import UIKit

@MainActor
final class AreaExportSnapshotBuilder {
    private let photoStorage: any PhotoFileStoring
    private let validatesJPEG: (Data) -> Bool

    init(
        photoStorage: any PhotoFileStoring,
        validatesJPEG: @escaping (Data) -> Bool = {
            $0.starts(with: [0xFF, 0xD8]) &&
                $0.suffix(2).elementsEqual([0xFF, 0xD9]) &&
                UIImage(data: $0) != nil
        }
    ) {
        self.photoStorage = photoStorage
        self.validatesJPEG = validatesJPEG
    }

    func build(area: Area, exportedAt: Int64, allTracks: [Track]? = nil) throws -> AreaExportSnapshot {
        guard area.category.isEmpty, area.catalogKey == nil,
              !area.rooms.contains(where: { !$0.code.isEmpty || !$0.floor.isEmpty || $0.catalogKey != nil }) else {
            throw ExportValidationError.requiresV3Export
        }
        let availableTracks: [Track]?
        if let allTracks {
            availableTracks = allTracks
        } else if let context = area.modelContext {
            // Never silently omit persisted global members if a caller omits the query.
            availableTracks = try context.fetch(FetchDescriptor<Track>())
        } else {
            availableTracks = nil
        }
        let candidates: [Track]
        if let availableTracks {
            let memberIDs = Set(TrackAreaIndex.tracks(in: area.id, from: availableTracks).map(\.id))
            candidates = availableTracks.filter {
                (!$0.isGlobalRecording && $0.area?.id == area.id) || memberIDs.contains($0.id)
            }
        } else {
            candidates = area.tracks
        }
        return try build(
            area: ExportAreaSnapshot(id: area.id, name: area.name),
            tracks: candidates,
            exportedAt: exportedAt
        )
    }

    func buildUnassigned(
        tracks: [Track],
        exportedAt: Int64,
        displayName: String = "未分区"
    ) throws -> AreaExportSnapshot {
        try build(
            area: ExportAreaSnapshot(id: nil, name: displayName),
            tracks: tracks,
            exportedAt: exportedAt
        )
    }

    private func build(
        area: ExportAreaSnapshot,
        tracks: [Track],
        exportedAt: Int64
    ) throws -> AreaExportSnapshot {
        let sortedTracks = tracks.sorted {
            ($0.startedAt, stableID($0.id)) < ($1.startedAt, stableID($1.id))
        }
        let snapshots = try sortedTracks.map { track -> TrackExportSnapshot in
            guard !track.isGlobalRecording, !track.isSegmentedRecording,
                  !track.rawIMURequested, track.rawIMUInterval == nil, track.imuBatches.isEmpty,
                  track.rawAccelState == "notRequested", track.rawGyroState == "notRequested",
                  track.rawIMURejectedCount == 0,
                  track.segments.isEmpty, track.corners.isEmpty,
                  !track.points.contains(where: { $0.segmentID != nil }),
                  !track.tags.contains(where: {
                      $0.recordKindRawValue != "legacy" || $0.accuracy != nil || $0.pressureHpa != nil ||
                      $0.roomID != nil || $0.roomNameSnapshot != nil || $0.roomCodeSnapshot != nil || $0.roomDoorRole != nil ||
                      $0.areaStateRawValue != "unknown" || $0.areaID != nil || !$0.floor.isEmpty
                  }),
                  !track.photos.contains(where: {
                      $0.kindRawValue != "legacyUnlinked" || $0.tagID != nil || $0.accuracy != nil || $0.pressureHpa != nil
                  }) else {
                throw ExportValidationError.requiresV3Export
            }
            if let areaID = area.id {
                guard track.area?.id == areaID else {
                    throw ExportValidationError.trackOutsideArea(trackID: track.id)
                }
            } else if track.area != nil {
                throw ExportValidationError.trackOutsideArea(trackID: track.id)
            }
            return try buildTrack(track)
        }
        return AreaExportSnapshot(area: area, exportedAt: exportedAt, tracks: snapshots)
    }

    private func buildTrack(_ track: Track) throws -> TrackExportSnapshot {
        let points = try track.points
            .sorted { ($0.timeMs, stableID($0.id)) < ($1.timeMs, stableID($1.id)) }
            .map { point in
                guard point.wifiAvailability == .unsupported,
                      point.wifiCount == nil,
                      point.wifiTop == nil else {
                    throw ExportValidationError.unexpectedWiFiObservation(
                        trackID: track.id,
                        pointID: point.id
                    )
                }
                try validateFinite(
                    trackID: track.id,
                    recordID: point.id,
                    values: [
                        "latitude": point.latitude,
                        "longitude": point.longitude,
                        "altitude": point.altitude,
                        "accuracy": point.accuracy,
                        "pressureHpa": point.pressureHpa,
                        "magneticX": point.magneticX,
                        "magneticY": point.magneticY,
                        "magneticZ": point.magneticZ,
                        "headingDeg": point.headingDeg,
                    ]
                )
                return TrackPointExportSnapshot(
                    id: point.id,
                    timeMs: point.timeMs,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    accuracy: point.accuracy,
                    pressureHpa: point.pressureHpa,
                    magneticX: point.magneticX,
                    magneticY: point.magneticY,
                    magneticZ: point.magneticZ,
                    headingDeg: point.headingDeg
                )
            }

        let tags = try track.tags
            .sorted {
                ($0.timeMs, $0.createdAt, stableID($0.id)) <
                    ($1.timeMs, $1.createdAt, stableID($1.id))
            }
            .map { tag in
                guard let tagType = TrackTagType(rawValue: tag.tagTypeRawValue) else {
                    throw ExportValidationError.unsupportedTagValue(
                        trackID: track.id,
                        tagID: tag.id,
                        value: tag.tagTypeRawValue
                    )
                }
                try validateFinite(
                    trackID: track.id,
                    recordID: tag.id,
                    values: [
                        "latitude": tag.latitude,
                        "longitude": tag.longitude,
                        "altitude": tag.altitude,
                        "headingDeg": tag.headingDeg,
                    ]
                )
                return TrackTagExportSnapshot(
                    id: tag.id,
                    timeMs: tag.timeMs,
                    tagType: tagType,
                    note: tag.note,
                    latitude: tag.latitude,
                    longitude: tag.longitude,
                    altitude: tag.altitude,
                    headingDeg: tag.headingDeg,
                    createdAt: tag.createdAt
                )
            }

        let photos = try track.photos
            .sorted {
                ($0.timeMs, $0.createdAt, stableID($0.id)) <
                    ($1.timeMs, $1.createdAt, stableID($1.id))
            }
            .map { try buildPhoto($0, track: track) }

        let snapshot = TrackExportSnapshot(
            id: track.id,
            name: track.name,
            startedAt: track.startedAt,
            endedAt: track.endedAt,
            points: points,
            tags: tags,
            photos: photos
        )
        try validatePointCount(snapshot)
        return snapshot
    }

    func buildPhoto(_ photo: TrackPhoto, track: Track) throws -> TrackPhotoExportSnapshot {
        let expectedPrefix = "photos/\(track.id.uuidString.lowercased())/"
        guard photo.filePath.hasPrefix(expectedPrefix) else {
            throw ExportValidationError.invalidPhotoPath(trackID: track.id, photoID: photo.id)
        }
        do {
            try photoStorage.validate(relativePath: photo.filePath)
        } catch {
            throw ExportValidationError.invalidPhotoPath(trackID: track.id, photoID: photo.id)
        }

        let data: Data
        do {
            data = try photoStorage.read(relativePath: photo.filePath)
        } catch PhotoStorageError.missingFile {
            throw ExportValidationError.missingPhotoFile(trackID: track.id, photoID: photo.id)
        } catch PhotoStorageError.unsafeRelativePath {
            throw ExportValidationError.invalidPhotoPath(trackID: track.id, photoID: photo.id)
        } catch {
            throw ExportValidationError.unreadablePhoto(trackID: track.id, photoID: photo.id)
        }
        guard !data.isEmpty, validatesJPEG(data) else {
            throw ExportValidationError.corruptPhoto(trackID: track.id, photoID: photo.id)
        }
        try validateFinite(
            trackID: track.id,
            recordID: photo.id,
            values: [
                "latitude": photo.latitude,
                "longitude": photo.longitude,
                "altitude": photo.altitude,
                "headingDeg": photo.headingDeg,
            ]
        )
        return TrackPhotoExportSnapshot(
            id: photo.id,
            timeMs: photo.timeMs,
            relativePath: photo.filePath,
            note: photo.note,
            latitude: photo.latitude,
            longitude: photo.longitude,
            altitude: photo.altitude,
            headingDeg: photo.headingDeg,
            createdAt: photo.createdAt,
            jpegData: data
        )
    }

    private func validateFinite(
        trackID: UUID,
        recordID: UUID,
        values: [String: Double?]
    ) throws {
        for (field, value) in values {
            if let value, !value.isFinite {
                throw ExportValidationError.nonFiniteSensorValue(
                    trackID: trackID,
                    recordID: recordID,
                    field: field
                )
            }
        }
    }

    private func validatePointCount(_ track: TrackExportSnapshot) throws {
        let actual = track.points.count
        guard track.pointCount == actual else {
            throw ExportValidationError.pointCountMismatch(
                trackID: track.id,
                declared: track.pointCount,
                actual: actual
            )
        }
    }

    private func stableID(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
