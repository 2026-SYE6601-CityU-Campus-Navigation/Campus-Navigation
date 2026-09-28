import Foundation

enum ExportContract {
    static let version = 2
    static let applicationName = "RoomMarker"
    static let sourcePlatform = "ios"
    static let capabilities = ExportCapabilitiesDTO(nearbyWifiFingerprint: .unsupported)
}

struct ExportDTOMapper {
    func manifest(from snapshot: AreaExportSnapshot) -> ExportManifestDTO {
        ExportManifestDTO(
            version: ExportContract.version,
            app: ExportContract.applicationName,
            sourcePlatform: ExportContract.sourcePlatform,
            capabilities: ExportContract.capabilities,
            exportedAt: snapshot.exportedAt,
            area: ManifestAreaDTO(
                id: nil,
                name: snapshot.area.name,
                sourceId: snapshot.area.id?.uuidString.lowercased()
            ),
            trackCount: snapshot.tracks.count,
            tracks: snapshot.tracks.map {
                ManifestTrackDTO(
                    file: $0.fileName,
                    name: $0.name,
                    startedAt: $0.startedAt,
                    pointCount: $0.pointCount
                )
            }
        )
    }

    func track(from snapshot: TrackExportSnapshot, areaName: String) -> ExportedTrackDTO {
        ExportedTrackDTO(
            version: ExportContract.version,
            sourcePlatform: ExportContract.sourcePlatform,
            capabilities: ExportContract.capabilities,
            name: snapshot.name,
            area: areaName,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            pointCount: snapshot.pointCount,
            points: snapshot.points.map {
                ExportedPointDTO(
                    timeMs: $0.timeMs,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    accuracy: $0.accuracy,
                    pressureHpa: $0.pressureHpa,
                    magneticX: $0.magneticX,
                    magneticY: $0.magneticY,
                    magneticZ: $0.magneticZ,
                    headingDeg: $0.headingDeg
                )
            },
            tags: snapshot.tags.map {
                ExportedTagDTO(
                    timeMs: $0.timeMs,
                    tagType: $0.tagType.rawValue,
                    note: $0.note,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    headingDeg: $0.headingDeg,
                    createdAt: $0.createdAt
                )
            },
            photos: snapshot.photos.map {
                ExportedPhotoDTO(
                    timeMs: $0.timeMs,
                    file: $0.relativePath,
                    note: $0.note,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    headingDeg: $0.headingDeg,
                    createdAt: $0.createdAt,
                    fileMissing: nil
                )
            }
        )
    }
}

enum ExportContractValidator {
    static func validate(track: ExportedTrackDTO, trackID: UUID) throws {
        guard track.pointCount == track.points.count else {
            throw ExportValidationError.pointCountMismatch(
                trackID: trackID,
                declared: track.pointCount,
                actual: track.points.count
            )
        }
    }
}
