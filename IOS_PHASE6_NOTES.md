# iOS Phase 6 Notes

## Scope

Phase 6 adds immutable Area export snapshots, HarmonyOS v1-compatible decoding, an explicit iOS v2 JSON contract, manifest generation, photo validation, and deterministic temporary staging. ZIP creation, sharing UI, Files integration, background location, and Wi-Fi scanning remain outside this phase.

## Architecture

The export path has three small boundaries:

1. `AreaExportSnapshotBuilder` reads SwiftData models and owned photo bytes once, validates them, and returns immutable value types.
2. `ExportDTOMapper` converts only those snapshots into manifest and Track DTOs.
3. `ExportStagingService` encodes DTOs and copies captured photo bytes into a unique temporary session directory.

After snapshot creation, later SwiftData or source-file changes cannot alter that snapshot. Export is read-only: it neither mutates models nor moves or deletes permanent photos.

## HarmonyOS v1 compatibility and iOS v2

The existing v1 field names and types remain decodable: `version`, `name`, `area`, `startedAt`, `endedAt`, `pointCount`, `points`, `tags`, and `photos`; the manifest retains `app`, `exportedAt`, `area`, `trackCount`, and `tracks`. Legacy `wifiCount` and `wifiTop` observations remain optional and decodable.

iOS output uses `version: 2`, `sourcePlatform: "ios"`, and:

```json
{"capabilities":{"nearbyWifiFingerprint":"unsupported"}}
```

This distinguishes an unavailable platform capability from a real scan that observed zero networks. iOS output omits `wifiCount` and `wifiTop`; it never fabricates BSSID, RSSI, or scan results. V2 also carries `createdAt` for tags/photos and an optional manifest `area.sourceId` for the source UUID. The legacy numeric `area.id` remains optional so v1 manifests still decode without changing its type.

## Determinism and record semantics

- Tracks: `startedAt`, then lowercase UUID.
- Points: `timeMs`, then lowercase UUID.
- Tags and photos: `timeMs`, then `createdAt`, then lowercase UUID.
- JSON: UTF-8, pretty printed, sorted keys, unescaped slashes, integer Unix epoch milliseconds.

`pointCount` is derived from the immutable point array and validated against the DTO before writing. A completed Track has a non-nil `endedAt`; an interrupted/incomplete Track retains `endedAt: null` or omission through Codable and is never silently excluded. Missing sensor readings remain nil rather than zero. NaN and Infinity cause a typed validation failure.

All six tag raw values remain exact: `厕所`, `楼梯`, `门`, `门禁`, `电梯`, `教室`.

## Area scope

Exports are built at Area scope. Conceptual `未分区` export is supported with a nil area identifier and without creating a fake persisted Area. A Track assigned to a different real Area is rejected.

## Photos and validation

Every photo path must pass the existing `PhotoFileStoring` validation boundary and must be under `photos/{lowercase-track-uuid}/`. Absolute paths, traversal, dot components, backslashes, symlink escape, and paths outside owned storage are rejected. The source must exist, be readable, non-empty, and decode as a JPEG. Missing, unreadable, and corrupt photos fail validation with Track and TrackPhoto identifiers; they are never silently omitted or replaced with empty files.

Photo bytes are captured in the immutable snapshot, then copied into staging. Originals remain untouched.

## Validation errors

`ExportValidationError` provides typed cases suitable for a later UI: wrong Area scope, invalid/missing/unreadable/corrupt photo, non-finite sensor data, unsupported tag data, unexpected iOS Wi-Fi observations, point-count mismatch, unsafe staging path, duplicate staging session, and staging failure.

## Manifest and staging

The v2 manifest uses `app: "RoomMarker"`, a fixed caller-supplied `exportedAt`, Area metadata, deterministic Track entries, platform metadata, and capability metadata. It adds no random volatile contract fields.

Each staging call creates a unique app-owned temporary session:

```text
RoomMarkerExports/{session-uuid}/
  manifest.json
  tracks/{track-uuid}.json
  photos/{track-uuid}/{image}.jpg
```

Relative paths are revalidated against the session root. Files use atomic writes. Mid-stage failure attempts to remove the whole partial session. Explicit cleanup removes only a validated child session directory. Permanent photo storage and SwiftData are never cleanup targets.

## Fixtures and Phase 7 boundary

Deterministic synthetic fixtures cover full and partial sensors, incomplete recording, tags, photo metadata, unsupported iOS Wi-Fi capability, conceptual `未分区`, multiple ordered Tracks, and HarmonyOS v1 decoding.

Phase 7 should consume `ExportStagingResult` to add ZIP creation and a Share Sheet. Those features should not weaken snapshot validation, path containment, atomic cleanup, or honest capability metadata.
