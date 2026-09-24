# RoomMarker iOS Architecture

## Architectural goals

The iOS implementation should reproduce RoomMarker's data-collection workflow while respecting Apple's APIs and execution model. It should remain small enough for a student team, use native frameworks, keep platform services behind testable interfaces, and treat the export contract as separate from the local database schema.

Recommended deployment target: **iOS 17 or later**. This permits SwiftUI plus SwiftData without a compatibility persistence layer. If the team later needs iOS 16 support, make that decision before creating models because it implies replacing SwiftData with Core Data or SQLite; do not maintain two stores.

## Native Apple technology stack

| Concern | Recommendation |
|---|---|
| Language and UI | Swift, SwiftUI, NavigationStack, Observation (`@Observable`) |
| Persistence | SwiftData with explicit relationships/delete rules and a repository boundary |
| Concurrency | Swift structured concurrency; `@MainActor` UI state; actor-isolated recording/export coordination |
| Location and compass | Core Location (`CLLocationManager`) |
| Motion and magnetic field | Core Motion (`CMMotionManager`, device motion, raw magnetometer) |
| Pressure | Core Motion `CMAltimeter` with kPa-to-hPa conversion |
| New photo capture | AVFoundation or a minimal UIKit system-camera bridge; store returned image data in the app sandbox |
| Existing-photo selection, optional | PhotosUI `PhotosPicker`, without broad photo-library permission |
| Files | Foundation `FileManager`; Application Support for durable app data, temporary directory for exports |
| JSON | Dedicated `Codable` export DTOs and `JSONEncoder` with explicit millisecond integers |
| ZIP | Small isolated ZIP `STORED`/CRC32 writer, reused conceptually from HarmonyOS but implemented and tested in Swift |
| Save/share | SwiftUI `fileExporter` and a system share-sheet wrapper/Transferable as appropriate |
| Logging | `Logger` from OSLog with privacy annotations; never log location/photo contents by default |
| Tests | XCTest/Swift Testing as supported by the chosen Xcode; golden JSON fixtures and real-device checklists |

No third-party dependency is recommended for the MVP. Reconsider only after a measured gap, such as the ZIP writer failing compatibility or SwiftData proving unsuitable in a prototype.

## Layers and dependency direction

```text
SwiftUI Features / Navigation
          |
Application coordinators and view models
          |
Domain models + repository/service protocols + export contract
          |
SwiftData repositories | Apple sensor adapters | media/files | exporter
```

Dependencies point inward. Views do not call Core Location, Core Motion, SwiftData, or FileManager directly. Export code reads immutable domain/export snapshots rather than holding live SwiftData objects while creating an archive.

### Presentation layer

- SwiftUI screens and small feature-scoped view models.
- A root `NavigationStack` with typed routes for area, room, track list, track detail, and live sensors.
- One global recording banner driven by `RecordingCoordinator` state.
- Capability/permission UI that distinguishes unavailable, not requested, denied, restricted, reduced, stale, and available.

### Application layer

- `RecordingCoordinator`: track state machine and orchestration.
- `SnapshotService`: bounded best-effort one-shot capture for room baselines and markers.
- `LiveSensorViewModel`: subscribes only while the live screen is visible.
- `PhotoCaptureCoordinator`: permission, capture, durable copy, metadata association, and cleanup.
- `ExportCoordinator`: creates immutable export snapshots, JSON, archive, and share/save result.

### Domain layer

- Plain value types/enums for sensor samples, capability states, and stable raw marker/tag values.
- Protocols for repositories, clocks, sensors, photo storage, and archive writing.
- Versioned `Codable` export DTOs independent of SwiftData annotations.

### Infrastructure layer

- SwiftData model/repository implementation.
- Core Location/Core Motion adapters.
- Application Support and temporary-file stores.
- JSON and ZIP implementations.

## Recommended project structure

The Phase 1 Xcode project should use a single app target and one unit-test target. Add UI tests only for a few stable critical flows.

```text
RoomMarkerIOS/
├── App/
│   ├── RoomMarkerApp.swift
│   ├── AppEnvironment.swift
│   └── AppRoute.swift
├── Domain/
│   ├── Models/
│   │   ├── Area.swift
│   │   ├── Room.swift
│   │   ├── Marker.swift
│   │   ├── Track.swift
│   │   ├── TrackPoint.swift
│   │   ├── TrackTag.swift
│   │   └── TrackPhoto.swift
│   ├── MarkerType.swift
│   ├── TrackTagType.swift
│   ├── SensorSample.swift
│   └── Protocols/
├── Persistence/
│   ├── RoomMarkerSchema.swift
│   ├── SwiftDataRepository.swift
│   └── PersistenceError.swift
├── Sensors/
│   ├── LocationService.swift
│   ├── MotionService.swift
│   ├── AltimeterService.swift
│   ├── SensorHub.swift
│   ├── SnapshotService.swift
│   └── SensorCapability.swift
├── Recording/
│   ├── RecordingCoordinator.swift
│   ├── RecordingState.swift
│   └── SampleAssembler.swift
├── Media/
│   ├── CameraCaptureView.swift
│   ├── PhotoCaptureCoordinator.swift
│   └── PhotoFileStore.swift
├── Export/
│   ├── ExportDTOs.swift
│   ├── RoomMarkerExporter.swift
│   ├── ZipArchiveWriter.swift
│   └── ExportDocument.swift
├── Features/
│   ├── Areas/
│   ├── Rooms/
│   ├── Tracks/
│   ├── LiveSensors/
│   └── Shared/
└── Resources/

RoomMarkerIOSTests/
├── Fixtures/
│   ├── harmony_track_v1.json
│   ├── harmony_manifest_v1.json
│   └── ios_track_v2.json
├── PersistenceTests.swift
├── ExportCompatibilityTests.swift
├── RecordingStateTests.swift
└── ZipArchiveTests.swift
```

Names can be adjusted to Xcode conventions, but boundaries should remain. Avoid a large generic `Utilities` directory.

## HarmonyOS-to-iOS module mapping

| HarmonyOS source | Responsibility understood | Proposed iOS equivalent |
|---|---|---|
| `README.md` | Product behaviour, environment, limitations | Root README section plus these iOS planning docs; later iOS run/demo guide |
| `data/Entities.ets` | Seven entities and two stable type enums | `Domain/Models/*`, `MarkerType.swift`, `TrackTagType.swift`, plus separate export DTOs |
| `data/Store.ets` | Schema/migration, CRUD, cascades, subscriptions, photo cleanup | SwiftData schema and `SwiftDataRepository`; SwiftUI observation replaces manual listeners; file cleanup remains explicit and transactional in application services |
| `sensors/SensorSnapshotter.ets` | Timed one-shot location/pressure/magnetic snapshot | `SnapshotService` aggregating current values from `SensorHub` with freshness thresholds and timeout |
| `sensors/LiveStream.ets` | Live location and many sensors, polling, Wi-Fi list | `SensorHub` with AsyncStreams and `LiveSensorViewModel`; only public iOS sensor APIs; no Wi-Fi card/list |
| `sensors/TrackRecorder.ets` | Singleton, 1 Hz logical samples, five-point flush, current snapshot, background location | Actor-isolated `RecordingCoordinator`, `SampleAssembler`, repository batch saves, lifecycle recovery, Core Location background mode |
| `sensors/TrackMedia.ets` | System photo capture and durable sandbox copy | `PhotoCaptureCoordinator`, camera UI bridge, `PhotoFileStore` |
| `common/Exporter.ets` | DTO mapping, manifest, track JSON, photo collection, save picker | `RoomMarkerExporter`, versioned `ExportDTOs`, `ExportDocument`, share/save presentation |
| `common/ZipWriter.ets` | ZIP STORED entries with CRC32 | Isolated Swift `ZipArchiveWriter` with conformance tests; do not translate ArkTS mechanically |
| `common/Utils.ets` | Formatting, filename safety, heading math/context | `Formatters`, `SafeFilename`, Apple fused heading; no global application context singleton |
| `pages/Index.ets` | Area list, unassigned entry, root navigation | `AreaListView` and typed `NavigationStack` routes |
| `pages/AreaDetail.ets` | Area rooms/tracks, start/export/delete | `AreaDetailView` and feature view model |
| `pages/RoomDetail.ets` | Baseline and marker capture/delete | `RoomDetailView`, `MarkerEditor`, `SnapshotService` |
| `pages/TrackList.ets` | All tracks and area-required start dialog | `TrackListView`, `StartRecordingSheet` |
| `pages/TrackDetail.ets` | Stats, path canvas, samples, tags/photos | `TrackDetailView`, SwiftUI Canvas/path preview, photo preview |
| `pages/RecordingBanner.ets` | Global active-session controls | Root overlay bound to `RecordingCoordinator`; no heartbeat reconstruction workaround |
| `pages/CaptureDialogs.ets` | Tag and photo-note dialogs | SwiftUI sheets/confirmation flows |
| `pages/LiveSensors.ets` | Live cards and device sensor list | iOS-supported `LiveSensorsView`; no generic sensor inventory or nearby Wi-Fi list |
| `module.json5` | Phone target, location/motion/Wi-Fi/background permissions | Xcode capabilities and Info.plist usage descriptions; omit Wi-Fi entitlements |

## Persistence design

### SwiftData entities and relationships

- `Area` has optional-to-many rooms and tracks with cascade only when the user chooses permanent deletion.
- A room/track may have a null area to represent unassigned data. Moving an area to unassigned must clear relationships before deleting the area.
- `Room` owns markers with cascade deletion.
- `Track` owns points, tags, and photo metadata with cascade deletion.
- Photo bytes live under Application Support. Deleting metadata and files is a coordinated operation; failed file deletion is logged and retried/cleaned later rather than rolling the database into an invalid state.
- Store UUID identity. Derived counts come from relationships/fetches. Store `startedAtMs`, `endedAtMs`, `timeMs`, and `createdAtMs` as `Int64` so export does not depend on floating-point `Date` conversion.
- Store raw enum labels as strings to preserve unknown future values; expose safe enum wrappers in the domain/UI.
- Make sensor fields optional `Double`. Wi-Fi fingerprint fields should not exist in the iOS persistence model unless a future supported data source is approved.

### Repository boundary

Views receive domain snapshots and invoke repository operations. The repository provides scoped queries and atomic operations such as:

- create/delete/move area;
- create/delete room, capture baseline, create/delete marker;
- create/append/finalise/recover/delete track;
- create/delete tag and photo association;
- materialise an immutable export snapshot.

For 1 Hz points, persist batches of about five in one repository transaction. On stop, synchronously await the final buffer flush before setting the track's end time and final count. On launch, detect a track with no `endedAtMs` and present a recovered/interrupted state rather than claiming it completed normally.

Use a versioned SwiftData schema and explicit migration plan from the first release, even if the first migration is empty. Add an in-memory container for tests.

## Sensor architecture

### Services

- `LocationService` owns one `CLLocationManager`, permission state, accuracy state, location updates, and device headings. It publishes timestamped readings and staleness.
- `MotionService` owns the app's single `CMMotionManager`. It publishes raw magnetometer values and processed device motion/heading when available. Start only the streams required by an active consumer.
- `AltimeterService` owns `CMAltimeter`, reports capability, converts pressure from kPa to hPa, and keeps relative altitude separate from Core Location altitude.
- `SensorHub` combines the latest readings without rewriting their source timestamps. It reference-counts live view, snapshot, and recorder consumers so sensors stop when unused.
- All services expose protocol-based streams so tests can inject deterministic readings and time.

### Snapshot semantics

`SnapshotService.capture(timeout:)` should begin required streams if needed, request a current location, wait up to the configured timeout, and return all fresh readings available. It should never require GPS success before returning pressure or magnetic data. Each reading should have a freshness threshold; do not attach an arbitrarily old recorder value to a new marker, tag, or photo.

### Units and frames

- Latitude/longitude: WGS-84 decimal degrees.
- Location altitude/accuracy: metres.
- Pressure: convert `CMAltitudeData.pressure` from kPa to hPa.
- Magnetic components: µT, with the Apple device coordinate frame documented in code/tests.
- Heading: `[0, 360)`, preferably magnetic north for parity with magnetic-field fusion. Store the heading source and accuracy internally if useful, but export the established `headingDeg` value only when valid.
- Update heading orientation when device interface orientation changes. A portrait-only MVP is acceptable if declared and enforced; otherwise test all supported orientations.

No fake “latest” value should be generated for absent hardware or denied access.

## Track recording architecture

`RecordingCoordinator` is a single actor-backed state machine:

```text
idle -> preparing -> recording -> stopping -> completed -> idle
                       |             |
                       +-> interrupted/error
```

Start validates a real area, creates the track record, starts required sensors/location in the foreground, and enables background location only for the active session. A monotonic clock triggers nominal 1 Hz logical samples while the process is scheduled. `SampleAssembler` snapshots the latest fresh readings and stamps actual wall-clock milliseconds. It must not duplicate or interpolate samples after a scheduling gap.

Five points are buffered and committed in one transaction. Flush on app backgrounding when time permits, stop, errors, and lifecycle transitions. The UI derives elapsed time from start/current clocks instead of depending on a one-second published counter.

The coordinator retains the latest valid snapshot for tags/photos, including per-field age. Track tags and photos use the action timestamp, not the timestamp of the last location event.

Prevent concurrent recordings. If the app relaunches with an unfinished track, mark it interrupted at the last persisted point time (or launch time with an explicit recovery flag) and let the user inspect it. Do not silently resume a session after process termination in the MVP.

## Tags and photos

Tags preserve the six HarmonyOS raw values and optional notes. Capture snapshot metadata when the user confirms the tag.

For photos:

1. Check/request camera authorization only after the user chooses Take Photo.
2. Present the native capture UI and receive encoded image data.
3. Write first to a temporary file, then atomically move to `Application Support/RoomMarker/photos/{track-token}/{timeMs}.jpg`.
4. Persist `TrackPhoto` only after the durable move succeeds.
5. If the user discards or metadata persistence fails, delete the orphaned file.
6. On deletion, remove metadata and enqueue best-effort file cleanup.

Capture and store orientation-correct image data. Bound export memory by streaming files into the archive rather than reading every photo at once. The HarmonyOS implementation reads complete photos and the whole ZIP into memory; iOS should avoid carrying that limitation forward.

## JSON and export architecture

`ExportDTOs.swift` defines HarmonyOS v1 fixture types and the iOS v2 output described in `IOS_PROJECT_BRIEF.md`. It must not encode SwiftData objects directly.

Export pipeline:

1. Repository creates an immutable, chronologically sorted area snapshot.
2. Validate counts, timestamps, finite numbers, stable raw labels, and relative photo paths.
3. Encode each track using a configured `JSONEncoder`; timestamps are already `Int64` milliseconds and nil optional readings are omitted.
4. Verify each photo exists. Add it under the referenced relative path or set `fileMissing: true`.
5. Encode the manifest with platform/capability metadata.
6. Write entries incrementally to a temporary ZIP using UTF-8 names, `STORED` records, CRC32, and duplicate/path-traversal checks.
7. Validate the completed archive, then return an export document/URL to the save or share UI.
8. Remove temporary output after completion or cancellation.

Use `/` as the ZIP path separator. Reject absolute paths and `..`. Sanitize visible filenames, add a stable collision suffix where needed, and keep manifest references authoritative.

Compatibility tests should decode checked-in HarmonyOS v1 fixtures, encode/decode iOS v2, inspect archive entries, compare units/key spelling, and verify missing Wi-Fi fields plus explicit unsupported capability metadata.

## Background execution

Enable Background Modes > Location updates only if Phase 4 includes the background acceptance test. A recording must start in the foreground. Set background delivery only during an active session and stop it immediately when recording ends.

When In Use location authorization can support a foreground-started active background location session; do not request Always merely because the option exists. The UI should explain the visible system location indicator and battery impact. If the team later needs the system to relaunch the app for location events, that is a separate scope and privacy review.

iOS may suspend or terminate the app, and indoor location events may be sparse. Timers, barometer, and motion delivery alone are not a durable background-execution guarantee. Therefore:

- persist frequently and flush on lifecycle transitions;
- tolerate timestamp gaps;
- never promise exact 1 Hz background sampling;
- record/derive an interrupted status;
- test screen lock, app switching, reduced accuracy, low-power mode, and no-GPS indoor conditions on real hardware;
- present foreground-only recording as a clear degraded mode if background prerequisites are not met.

## Error-handling principles

- Use typed domain errors with an actionable user message and a more detailed private log message.
- Treat cancellation separately from failure for camera and export flows.
- Never use empty catches for data writes, final flushes, archive creation, or file moves.
- Treat partial sensor snapshots as successful degraded results; preserve which fields are absent.
- Validate finite numeric values before persistence/export.
- Make destructive actions explicit and idempotent. Reconcile orphaned photo files at launch or in a maintenance action.
- Keep the last good persisted track readable if sampling later fails.
- Surface permission recovery with a Settings link only after denial; do not repeatedly prompt.
- Avoid logging coordinates, BSSIDs, notes, or photo paths at public log privacy levels.
- Export to a new temporary URL and use atomic replacement; never overwrite the only durable photo/data copy.

## Architectural decision checkpoints

Before application implementation grows beyond Phase 1, validate these spikes/tests:

1. SwiftData relationship/delete and interrupted-track behaviour in an in-memory and disk store.
2. HarmonyOS v1 fixture decoding and agreed iOS v2 Wi-Fi capability semantics.
3. Pressure units and raw magnetic/heading frames on a physical iPhone.
4. Ten-minute foreground recording and short lock/background recording with actual timestamps.
5. ZIP output opened by macOS Archive Utility, command-line unzip, and the intended downstream parser.

Failures at these checkpoints should change the design early rather than add workarounds in views.
