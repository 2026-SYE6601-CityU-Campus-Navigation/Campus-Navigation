import Foundation
import Testing
@testable import RoomMarker

@Suite("HarmonyOS JSON compatibility")
struct CompatibilityTests {
    @Test("Marker raw values match HarmonyOS")
    func markerRawValues() {
        #expect(MarkerType.allCases.map(\.rawValue) == [
            "前门", "后门", "窗户", "墙角", "插座", "自定义",
        ])
    }

    @Test("Track tag raw values match HarmonyOS")
    func trackTagRawValues() {
        #expect(TrackTagType.allCases.map(\.rawValue) == [
            "厕所", "楼梯", "门", "门禁", "电梯", "教室",
        ])
    }

    @Test("HarmonyOS v1 track fixture decodes with Wi-Fi observations")
    func harmonyTrackV1Decodes() throws {
        let data = try TestFixtures.data(named: "harmony_track_v1")
        let track = try JSONDecoder().decode(ExportedTrackDTO.self, from: data)

        #expect(track.version == 1)
        #expect(track.sourcePlatform == nil)
        #expect(track.capabilities == nil)
        #expect(track.points.first?.wifiCount == 2)
        #expect(track.points.first?.wifiTop?.contains("02:00:00:00:00:01") == true)
        #expect(track.tags.first?.tagType == TrackTagType.door.rawValue)
        #expect(track.photos.first?.file == "photos/synthetic/1700000003000.jpg")
    }

    @Test("HarmonyOS v1 manifest fixture decodes")
    func harmonyManifestV1Decodes() throws {
        let data = try TestFixtures.data(named: "harmony_manifest_v1")
        let manifest = try JSONDecoder().decode(ExportManifestDTO.self, from: data)

        #expect(manifest.version == nil)
        #expect(manifest.app == "RoomMarker")
        #expect(manifest.trackCount == 1)
        #expect(manifest.tracks.first?.pointCount == 1)
    }

    @Test("iOS v2 fixture omits Wi-Fi observations and declares capability")
    func iosTrackV2Decodes() throws {
        let data = try TestFixtures.data(named: "ios_track_v2")
        let track = try JSONDecoder().decode(ExportedTrackDTO.self, from: data)

        #expect(track.version == 2)
        #expect(track.sourcePlatform == "ios")
        #expect(track.capabilities?.nearbyWifiFingerprint == .unsupported)
        #expect(track.points.first?.wifiCount == nil)
        #expect(track.points.first?.wifiTop == nil)
    }

    @Test("Interrupted iOS fixture has no end time")
    func interruptedTrackFixtureDecodes() throws {
        let data = try TestFixtures.data(named: "ios_interrupted_track_v2")
        let track = try JSONDecoder().decode(ExportedTrackDTO.self, from: data)

        #expect(track.endedAt == nil)
        #expect(track.pointCount == 0)
    }

    @Test("Unassigned room fixture carries a null area")
    func unassignedRoomFixtureDecodes() throws {
        struct RoomFixture: Decodable {
            let id: UUID
            let name: String
            let note: String
            let areaId: UUID?
            let createdAt: Int64
        }

        let data = try TestFixtures.data(named: "unassigned_room")
        let room = try JSONDecoder().decode(RoomFixture.self, from: data)

        #expect(room.areaId == nil)
        #expect(room.name == "Synthetic Unassigned Room")
        #expect(room.createdAt == 1_700_000_300_000)
        #expect(room.note == "No real location data")
        #expect(room.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    @Test("iOS DTO encoding does not fabricate Wi-Fi fields")
    func iosEncodingOmitsWiFiObservations() throws {
        let point = ExportedPointDTO(
            timeMs: 1_700_000_400_000,
            pressureHpa: 1008.0,
            headingDeg: 90.0
        )
        let track = ExportedTrackDTO(
            version: 2,
            sourcePlatform: "ios",
            capabilities: ExportCapabilitiesDTO(nearbyWifiFingerprint: .unsupported),
            name: "Synthetic iOS Track",
            area: "Synthetic Area",
            startedAt: 1_700_000_400_000,
            endedAt: nil,
            pointCount: 1,
            points: [point],
            tags: [],
            photos: []
        )

        let data = try JSONEncoder().encode(track)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let points = try #require(root["points"] as? [[String: Any]])
        let encodedPoint = try #require(points.first)

        #expect(encodedPoint["wifiCount"] == nil)
        #expect(encodedPoint["wifiTop"] == nil)
        #expect((root["capabilities"] as? [String: Any])?["nearbyWifiFingerprint"] as? String == "unsupported")
    }
}
