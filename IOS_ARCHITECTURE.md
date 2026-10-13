# RoomMarker iOS Architecture

## Status

This document describes the current as-built iOS application: the accepted Phase 9 baseline plus the cross-building, JSON v3, catalog, structure, raw-IMU, visualisation, recognition and upload follow-up. It replaces the earlier proposed structure while preserving the design reasoning that shaped the implementation.

The implementation uses native Apple frameworks, has one application target and one unit-test target, and has no third-party runtime dependency. The deployment target is iOS 17 or later.

## Architectural goals

- Preserve the meaning of the HarmonyOS RoomMarker workflow without translating ArkTS line by line.
- Keep missing or denied sensor data optional; never manufacture zeros or Wi-Fi observations.
- Give one owner to each Apple framework manager and share readings through a testable sensor hub.
- Separate SwiftData persistence models from versioned export DTOs.
- Keep camera files under application ownership and coordinate metadata/file cleanup.
- Export from an immutable snapshot so sharing cannot mutate live source data.
- Validate every filesystem boundary used by photos, staging, archives, and cleanup.
- Model recording and background ownership explicitly enough to recover an incomplete Track honestly.

## Native technology stack

| Concern | As-built implementation |
| --- | --- |
| Language and UI | Swift 6, SwiftUI, `NavigationStack`, Observation |
| Persistence | SwiftData with explicit relationships and delete rules |
| Location and heading | Core Location through one `CoreLocationSensorService` |
| Magnetic field | Core Motion through `CoreMotionMagnetometerService` |
| Pressure | `CMAltimeter` through `CoreMotionPressureService`, converted to hPa |
| Background activity | Foreground-started Core Location updates and `CLBackgroundActivitySession` |
| Camera | Minimal UIKit camera bridge behind `CameraServicing` |
| Durable photos | Foundation file storage under Application Support |
| JSON | Dedicated legacy v2 and current streaming v3 DTOs with configured Foundation encoding |
| ZIP | In-project streaming STORED ZIP32 writer with CRC32 |
| Sharing/upload | UIKit Share Sheet or disk-streamed HTTP(S) multipart upload; token stored in Keychain |
| Tests | Deterministic app, persistence, sensor, recording, media, export, and parity tests |

## Composition root and dependency direction

`RoomMarkerApp` is the composition root. At launch it:

1. creates the SwiftData `ModelContainer`;
2. creates one Core Location service and one shared `SensorHub`;
3. creates the background-location session around the same location service;
4. creates the SwiftData recording/media store;
5. creates application-owned photo storage;
6. removes stale owned export temporary files on a best-effort basis;
7. injects the shared services into the root `AreaListView`.

The main dependency direction is:

```text
SwiftUI Views
    -> workflow/data-store/coordinator APIs
        -> SwiftData repositories
        -> SensorHub and native sensor adapters
        -> camera and photo-file storage
        -> immutable export snapshot/staging/archive services
```

Views observe SwiftData and coordinator state, but hardware and file operations remain behind protocols or focused services. Export DTOs do not import or encode SwiftData models directly.

## As-built project structure

```text
RoomMarker/
├── App/
│   └── RoomMarkerApp.swift
├── Models/
│   ├── Area.swift
│   ├── Room.swift
│   ├── Marker.swift
│   ├── Track.swift
│   ├── TrackPoint.swift
│   ├── TrackTag.swift
│   ├── TrackPhoto.swift
│   ├── TrackSegment.swift
│   ├── TrackCorner.swift
│   ├── TrackIMUBatch.swift
│   └── stable marker/tag/Wi-Fi capability enums
├── Persistence/
│   ├── RoomMarkerSchema.swift
│   ├── RoomMarkerRepository.swift
│   ├── SwiftDataRepository.swift
│   ├── Phase2DataStore.swift
│   ├── CampusCatalog.swift / CatalogImportStore.swift
│   └── TrackRoomPlanning.swift
├── Sensors/
│   ├── SensorTypes.swift
│   ├── SensorServiceProtocols.swift
│   ├── LocationSensorService.swift
│   ├── MagnetometerSensorService.swift
│   ├── PressureSensorService.swift
│   ├── SensorHub.swift
│   ├── SensorSnapshotService.swift
│   ├── RoomMarkerSnapshotWorkflow.swift
│   └── RawIMUSensorService.swift
├── Recording/
│   ├── RecordingTypes.swift
│   ├── RecordingCoordinator.swift
│   ├── RecordingTicker.swift
│   ├── RecordingPersistence.swift
│   ├── RecordingLifecycle.swift
│   ├── BackgroundLocationSession.swift
│   ├── SampleAssembler.swift
│   ├── TrackMediaSupport.swift
│   ├── RawIMURecorder.swift
│   └── TrackStructureEditor.swift
├── Media/
│   ├── CameraCaptureView.swift
│   ├── CameraService.swift
│   └── PhotoFileStore.swift
├── DTOs/
│   ├── ExportDTOs.swift
│   └── ExportV3DTOs.swift
├── Export/
│   ├── AreaExportCoordinator.swift
│   ├── AreaExportSnapshotBuilder.swift
│   ├── ExportSnapshots.swift
│   ├── ExportDTOMapper.swift
│   ├── ExportJSONEncoder.swift
│   ├── ExportStagingService.swift
│   ├── StoredZIPArchive.swift
│   ├── ExportTemporaryCleanup.swift
│   ├── ExportV3SnapshotBuilder.swift / ExportV3Validator.swift
│   ├── V3StreamingExporter.swift
│   └── PhotoHTMLIndex.swift
├── Recognition/
│   └── PlaceRecognitionEngine.swift
├── Visualization/
│   └── Track3DPlan.swift
├── Upload/
│   └── ZIPUploadService.swift
├── Views/
│   └── Area, Room, Marker, sensor, recording, Track, media, and export views
└── Info.plist

RoomMarkerTests/
├── Fixtures/
│   ├── HarmonyOS v1 compatibility fixtures
│   └── iOS v2/v3 export fixtures
└── persistence, migration, sensor, recording, media, export, background, catalog, recognition, 3D, upload, and parity suites
```

The folders reflect runtime responsibilities rather than an abstract framework hierarchy. Small workflow objects remain close to the models or infrastructure they coordinate.

## Domain and persistence

The seven original shared product entities remain recognisable across platforms:

- `Area`
- `Room`
- `Marker`
- `Track`
- `TrackPoint`
- `TrackTag`
- `TrackPhoto`

iOS v7 adds three owned Track evidence models—`TrackSegment`, `TrackCorner`, and `TrackIMUBatch`—without rewriting the original entities. Catalog identity and node-room binding are conservative scalar additions so old data can migrate with no inferred meaning.

SwiftData uses UUID identity and `Int64` Unix-millisecond timestamps. Sensor fields are optional `Double` values. Stable Marker and Track-tag labels retain the established Chinese raw values used by the HarmonyOS export contract.

Relationships implement the required ownership rules:

- an Area owns Rooms only through an explicit current relation; a cross-building Track uses node Area IDs and a derived area index rather than one owning Area;
- a null Area relation is presented as synthetic `未分区`, not stored as a real Area;
- deleting an Area through the current iOS UI clears its child relations and preserves the Rooms and Tracks;
- a Room owns Markers through cascade deletion;
- a Track owns TrackPoints, TrackTags, TrackPhoto metadata, segments, corners, and IMU batches through cascade deletion;
- photo bytes are outside SwiftData, so Track and photo deletion coordinate database changes with `PhotoFileStore` cleanup.

`Phase2DataStore` contains Area/Room/Marker validation and mutations. `SwiftDataRecordingStore` implements recording and media persistence. Repository protocols and in-memory containers let tests exercise semantics without a physical device.

Counts such as `Track.pointCount` are derived from persisted relationships rather than trusted as a separate mutable counter.

## Sensor services

`SensorHub` is the shared observable sensor boundary. It owns no framework manager itself; instead, it combines three focused adapters:

- `CoreLocationSensorService` owns `CLLocationManager`, When In Use authorization, location, heading, and background-update configuration.
- `CoreMotionMagnetometerService` owns the magnetometer stream.
- `CoreMotionPressureService` owns `CMAltimeter` and reports pressure in hPa.

Consumers are reference-counted by identity (`live`, `snapshot`, or `recording`). The first consumer starts the native services and the final consumer stops them. This prevents a Live Sensors screen, bounded snapshot, and active recording from creating competing framework managers.

`LiveSensorState` represents each source as waiting, available, stale, denied, restricted, unavailable, or unsupported as appropriate. UI and recording code consume those states without changing an unavailable value into zero.

Nearby Wi-Fi scanning is not part of the iOS sensor layer. A normal iOS application cannot reproduce the HarmonyOS general nearby BSSID/RSSI scan, so the export capability is explicitly unsupported.

## Bounded snapshots and Room/Marker workflows

`SensorSnapshotService` acquires the shared hub as a snapshot consumer, waits for individual sources to settle, and returns after at most four seconds. Its result contains optional readings plus a per-source outcome. Success can therefore be partial or fully unavailable without being dishonest.

`RoomMarkerSnapshotWorkflow` maps one captured snapshot into persistence:

- Room reference capture stores latitude, longitude, altitude, and pressure.
- A new Room snapshot fully replaces the previous values; absent new fields clear stale old values rather than blending captures.
- Marker creation stores latitude, longitude, altitude, horizontal accuracy, pressure, and magnetic X/Y/Z.
- Marker metadata editing changes only name and type and preserves the original sensor snapshot.

The same sensor service also supports the standalone Sensor Snapshot screen. Task cancellation and `defer`-based lease release prevent an abandoned capture from keeping the native streams active.

## Track recording

`RecordingCoordinator` is a single `@MainActor` observable state machine. Its important states are idle, preparing, recording, stopping, and failed. Only one Track can be active.

Start performs these operations in order:

1. validate a non-empty name and requested initial environment;
2. persist a global Track and its first environment segment with no end time;
3. acquire the recording sensor consumer;
4. acquire foreground-started background-location ownership;
5. optionally start the foreground raw-IMU recorder and start the nominal one-second ticker.

`SampleAssembler` takes the current optional sensor state and stamps the actual tick time. The coordinator rejects non-increasing tick times, buffers five points, and flushes them through the recording store. It also flushes the current tail before expected background suspension and again before finalisation.

Stop waits for the ticker, persists the final tail, writes the real end time, releases background ownership, stops its sensor lease, and returns to idle. No point is interpolated after a scheduling gap and no synthetic catch-up sequence is generated.

Nodes freeze their selected Area/floor/optional Room together with one JPEG and sensor metadata. Corners and environment transitions are separate evidence. `TrackStructureEditor` permits completed-segment correction, split at a real node timestamp, or merge with the previous segment; it updates point, corner and IMU segment references atomically without changing measurements or timestamps.

Elapsed UI time is derived from the Track start and current clock. The active recording banner is inserted at the root safe area so it remains available across navigation, tag entry, and camera presentation.

## Background lifecycle and incomplete Tracks

The app declares only the `location` background mode and asks for When In Use location authorization. `CoreLocationBackgroundSession` enables background location updates and owns a `CLBackgroundActivitySession` only for a user-started active recording.

iOS determines real execution opportunities. The architecture does not treat a timer, pressure stream, or motion stream as an independent background guarantee and does not promise exact one-second delivery while backgrounded.

If permission is denied or restricted, background status becomes unavailable and ownership is released. Foreground data entry and independent supported sensors continue to degrade gracefully.

Force quitting terminates the in-memory coordinator. On the next launch, `IncompleteTrackRecovery` finds persisted Tracks with no end time that are not the current active Track. The Track list places them under `需要处理`; the user may inspect, manually finalise, or delete them. The app does not invent an end time or silently resume recording.

## Tags, camera, and photo storage

New nodes and scenery photos are accepted only for the active Track. Each action receives its own real timestamp and the currently available location, accuracy, altitude, pressure and heading metadata. Historical standalone tags/photos retain their old independent meaning.

Camera capture is user initiated through a UIKit bridge. Successful JPEG data is validated and written atomically under:

```text
Application Support/RoomMarker/photos/{track-uuid}/{timestamp}-{uuid}.jpg
```

Only the relative `photos/...` path is stored in SwiftData or exported. RoomMarker does not request Photos Library permission and does not automatically write to the system photo library.

Photo metadata is created only after durable storage succeeds. If metadata persistence then fails, the newly written file is removed. Individual photo deletion removes metadata and the owned file; Track deletion additionally removes its owned photo directory.

Track Detail loads owned data through `PhotoContentLoader`, distinguishes available/missing/corrupt content, and presents thumbnails and a larger orientation-correct preview.

## Immutable export pipeline

Export is coordinated by `AreaExportCoordinator`, which exposes preparing, staging, archiving, ready-to-share, and failed states.

The pipeline is:

1. `ExportV3SnapshotBuilder` freezes sorted model values, owned photo URLs and raw IMU payloads for the selected area/all/UUID Track scope.
2. `ExportV3Validator` verifies identities, counts, relationships, segment membership, unsupported Wi-Fi semantics and source ownership before publication.
3. `V3StreamingExporter` writes deterministic manifest/Track JSON while decoding at most one bounded IMU batch at a time.
4. Photos are copied in 64 KiB chunks with ImageIO validation and SHA-256; `PhotoHTMLIndex` creates a static relative-link review page.
5. `StoredZIPArchiveService` enumerates only the owned session's validated descendants and streams one STORED ZIP32 archive with CRC32 records.
6. The user explicitly chooses `ExportSharePayload` or `URLSessionZIPUploader`; upload constructs a contained disk multipart body in 64 KiB chunks and never moves the source archive.
7. Staging and archive files are removed after completion, cancellation, view departure, or the next launch's stale-export cleanup.

The current manifest declares `version: 3`, `sourcePlatform: ios`, scope, catalog and platform capabilities. The Wi-Fi capability remains `nearbyWifiFingerprint: unsupported`; iOS Track JSON contains no BSSID/RSSI, `wifiCount`, or `wifiTop` observations. Legacy v2 readers/tests remain for old records; structured v3 data is never silently downgraded to v2.

Export is not constant memory: frozen model arrays, raw bounded-batch payloads and uniqueness sets still scale with the Track. It does avoid retaining all decoded IMU samples or all photo bytes at once.

## Filesystem security boundary

`CanonicalPathContainment` provides one containment policy shared by photo storage, export staging, ZIP source validation, and temporary cleanup.

It:

- rejects empty, absolute, backslash, dot, and `..` relative paths;
- canonicalises the nearest existing ancestor and resolves its symbolic links;
- appends validated components for destinations that do not yet exist;
- compares complete path components rather than string prefixes;
- accepts equivalent filesystem aliases such as `/var` and `/private/var` after canonicalisation;
- requires a strict descendant, so the root itself and sibling-prefix paths are rejected;
- rejects a symbolic-link escape from an owned root.

This boundary fixed a physical-device false rejection without disabling path validation. Archive paths are independently checked before writing and always use `/` separators.

Temporary cleanup enumerates only children of the RoomMarker-owned export root. It never treats a shared system temporary directory as owned.

## Error and degradation principles

- User-facing errors are actionable and avoid revealing private container paths.
- Cancellation is distinct from failure for camera and export workflows.
- Partial snapshots are valid results; unavailable values remain nil.
- Persistence failure does not intentionally leave a partially created Marker, tag, or photo association.
- The final recording tail is persisted before a Track is marked complete.
- Destructive actions require explicit confirmation and avoid deleting an active Track.
- Permission denial offers recovery through Settings without a prompt loop.
- Export failure removes owned temporary output and leaves SwiftData and source photos unchanged.
- No normal diagnostic persists coordinates, BSSIDs, Apple account data, signing data, or photo contents.

## HarmonyOS compatibility boundary

The local databases are platform-specific. Compatibility occurs through versioned exports and stable domain meaning, not by sharing a SQLite or SwiftData store.

Checked-in HarmonyOS v1 and iOS v2/v3 fixtures verify legacy field names and optionality. iOS v3 adds cross-building scope, catalog, node-photo/room relationships, segments, corners and raw IMU while keeping capability metadata so downstream readers distinguish unsupported iOS Wi-Fi from a real empty HarmonyOS scan.

The implementations deliberately differ where native platform behavior differs: SwiftData replaces HarmonyOS relational storage, SwiftUI observation replaces manual store listeners, Core Location owns iOS background behavior, and the Share Sheet replaces the HarmonyOS document-save flow.

## Testability and accepted evidence

Hardware, clocks, tickers, persistence, background ownership, camera outcomes, photo storage, ZIP creation, and export session identifiers have protocol or closure seams for deterministic tests.

The current baseline is 447 logical tests (559 parameterized instances) with no failures or skips. It includes the accepted Phase 9 suite plus V1→V7 migration, global Track indexing, node/photo compensation, catalog import, room binding/generation, segment/corner/raw-IMU integrity, v3 streaming and receiver validation, 3D evidence planning, conservative place recognition, ZIP upload staging and the original filesystem defenses.

Physical acceptance on an iPhone 15 Pro / iOS 26.7 validated the sensor, camera, foreground, Home-background, lock-screen, Share Sheet, saved archive, cleanup, denied-location, and force-quit boundaries. See [IOS_PHASE9_DEVICE_ACCEPTANCE.md](IOS_PHASE9_DEVICE_ACCEPTANCE.md) for the bounded evidence and remaining risks.

## Known architectural boundaries

- Background execution remains controlled by iOS and is not guaranteed at exact one-second intervals.
- The application does not request Always location authorization or system relaunch after termination.
- General nearby Wi-Fi fingerprint scanning is intentionally unsupported on iOS.
- The archive writer is STORED ZIP32 rather than a compression or ZIP64 implementation.
- Export model freezing and uniqueness sets still grow with a collection; multi-hour device export and upload remain a field-performance check.
- 2.5D/3D rendering uses recorded coordinates and accuracy gates but does not map-match a floor plan.
- Core Location/pressure place candidates are not a replacement for HarmonyOS Wi-Fi fingerprint positioning.
- The accepted physical matrix contains one iPhone and OS version; it is not a production device lab.
