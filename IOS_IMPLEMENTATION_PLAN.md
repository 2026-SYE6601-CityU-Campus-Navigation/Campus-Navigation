# RoomMarker iOS Implementation Plan

> **Historical status — original phased plan.** This document preserves the plan written at Phase 0. Implementation subsequently progressed through Phase 9; see [IOS_PHASE9_DEVICE_ACCEPTANCE.md](IOS_PHASE9_DEVICE_ACCEPTANCE.md) for the accepted application baseline.

## Plan rules

- This document defines future work; only Phase 0 is performed now.
- Work stays on `iOS-Application`. Do not merge `main`, `Harmony-Application`, or any other implementation branch into it.
- Read HarmonyOS files through Git refs when clarification is needed; do not edit HarmonyOS files.
- Each phase should be a reviewable vertical increment with passing tests and a physical-device check where sensors or camera are involved.
- Use native Apple frameworks and add no third-party dependency without a recorded reason and team approval.
- Preserve generated/exported data fixtures, not build products, as source-controlled evidence.

## Phase 0 — Repository study and architecture plan (complete)

### Exact scope

- Verify the active branch and repository status without switching or merging.
- Inspect history and the completed HarmonyOS source from `origin/main`/`origin/Harmony-Application`.
- Document product scope, model/export compatibility, native architecture, platform gaps, privacy, background execution, repository hygiene, phases, validation, and risks.
- Make the explicit decision that iOS will not collect or fabricate nearby Wi-Fi fingerprints.

### Files expected

- `IOS_PROJECT_BRIEF.md`
- `IOS_ARCHITECTURE.md`
- `IOS_IMPLEMENTATION_PLAN.md`

### Validation criteria

- Only the three planning files are added.
- No Xcode project, Swift source, assets, entitlements, or dependency files exist.
- `git diff --check` passes.
- The branch remains `iOS-Application`; no other branch/ref is modified.

### Known risks

- Export v2 capability metadata needs downstream owner agreement.
- Apple framework behaviour still needs physical-device proof.

### Explicitly deferred

Everything in Phases 1–7, including `.gitignore` creation and any application/test code.

---

## Phase 1 — Xcode/SwiftUI foundation, domain models, and persistence

### Exact scope

- Add the agreed iOS `.gitignore` before opening/creating the project.
- Create one iOS 17+ SwiftUI app target and one unit-test target with a shared scheme.
- Establish typed navigation shell and dependency container, with placeholder area-list content only.
- Implement the seven SwiftData entities, stable marker/tag raw values, relationships, delete rules, millisecond timestamps, and an initial versioned schema.
- Implement repository protocols and SwiftData repository operations needed by later phases, using an in-memory store in tests.
- Add explicit v1/v2 export DTO definitions and small, anonymised HarmonyOS JSON fixtures, but do not build export UI or ZIP generation.
- Add capability enums/protocols as seams only; do not start sensors.

### Files/modules expected

- `.gitignore`
- `RoomMarkerIOS.xcodeproj` with shared scheme
- `RoomMarkerIOS/App/{RoomMarkerApp,AppEnvironment,AppRoute}.swift`
- `RoomMarkerIOS/Domain/Models/*.swift`
- `RoomMarkerIOS/Domain/{MarkerType,TrackTagType}.swift`
- `RoomMarkerIOS/Domain/Protocols/RoomMarkerRepository.swift`
- `RoomMarkerIOS/Persistence/{RoomMarkerSchema,SwiftDataRepository,PersistenceError}.swift`
- `RoomMarkerIOS/Export/ExportDTOs.swift`
- `RoomMarkerIOSTests/Fixtures/{harmony_manifest_v1,harmony_track_v1,ios_track_v2}.json`
- `RoomMarkerIOSTests/{PersistenceTests,ExportCompatibilityTests}.swift`

Exact Xcode-generated filenames may vary, but no package manager files should appear unless deliberately required.

### Validation criteria

- Clean clone builds with the documented Xcode version and no external packages.
- Unit tests create all seven entity types, persist/reload optional fields, preserve `Int64` millisecond values, and validate relationships.
- Tests cover cascade deletion, moving an area to unassigned, unknown raw marker/tag labels, and interrupted tracks.
- Fixture tests decode HarmonyOS v1, encode/decode iOS v2, and prove unsupported Wi-Fi is explicit and not represented as zero/empty observations.
- `xcodebuild` build and unit-test commands pass; `git status` contains no DerivedData, user settings, local database, or captured data.

### Known risks

- SwiftData relationship and migration behaviour can surprise when models are actor-isolated or cascades mix with external photo files.
- Xcode project files can create merge conflicts; keep target settings minimal and share only team-relevant schemes.
- A HarmonyOS fixture copied from real collection data could leak location; create a minimal synthetic fixture with the same structure.

### Explicitly deferred

- CRUD screens beyond navigation placeholders.
- Sensor framework objects, permission prompts, recording, camera, ZIP, share UI, and background capability.
- Database import from Android/HarmonyOS.

---

## Phase 2 — Area and Room CRUD

### Exact scope

- Build the area list, synthetic unassigned entry, create-area sheet, and area detail.
- Create rooms within an area or unassigned, show room detail, and edit the room name/note if the team agrees editing is needed.
- Implement delete confirmations: move an area's children to unassigned or permanently delete; cascade room markers on room deletion.
- Display empty, loading, and recoverable error states.
- Use repository/domain snapshots only; no sensors yet. Baseline/marker controls appear disabled or are omitted until Phase 3.

### Files/modules expected

- `Features/Areas/{AreaListView,AreaDetailView,AreaEditor,AreaViewModel}.swift`
- `Features/Rooms/{RoomDetailView,RoomEditor,RoomViewModel}.swift`
- `Features/Shared/{EmptyStateView,ErrorView,DestructiveConfirmation}.swift`
- Repository query/operation additions and CRUD tests
- A small UI-test flow for create/open/delete, if stable in CI

### Validation criteria

- A user can create multiple areas/rooms, relaunch, and see identical data.
- Unassigned is never stored as a fake Area row; moving an area clears child relationships without deleting children.
- Permanent area deletion removes rooms/tracks and their children in test data after explicit confirmation.
- Names are trimmed, empty names rejected, and long names/notes do not break layouts.
- VoiceOver labels and Dynamic Type work on core controls.

### Known risks

- SwiftData query refresh and relationship changes can produce stale UI if view models keep managed objects too long.
- Permanent deletion will later need coordinated photo-file cleanup; Phase 2 tests should use metadata only and leave a clear integration point.

### Explicitly deferred

- Room baseline capture, markers, live sensor values, track start/recording, tags/photos, path preview, and export.

---

## Phase 3 — Sensor snapshot and live sensors

### Exact scope

- Implement `LocationService`, `MotionService`, `AltimeterService`, and a reference-counted `SensorHub` behind protocols.
- Add capability and permission state models, on-demand location authorization, and required purpose strings.
- Implement bounded `SnapshotService` with per-reading timestamps/freshness rules and partial-result semantics.
- Enable room baseline capture and marker creation using snapshot data.
- Build the live-sensor screen for supported iOS data: location/accuracy/altitude, pressure/relative altitude, accelerometer, gyroscope, magnetic field, attitude/heading, and optional pedometer only if justified.
- Show Wi-Fi fingerprint as a concise “Not available on iOS” explanation or omit the card; never show a scan spinner/list.

### Files/modules expected

- `Sensors/{LocationService,MotionService,AltimeterService,SensorHub,SnapshotService,SensorCapability}.swift`
- `Features/LiveSensors/{LiveSensorsView,LiveSensorsViewModel,SensorReadingView}.swift`
- `Features/Rooms/{MarkerEditor,RoomSnapshotView}.swift`
- Info.plist privacy strings for location and any authorization-gated motion service
- Mock service implementations and sensor/snapshot tests

### Validation criteria

- On a physical iPhone, available readings update and stop when the last consumer leaves.
- Pressure is verified as hPa (`kPa × 10`) and relative altitude is not exported as location altitude.
- Magnetic axes and heading reference/orientation are documented and tested in a repeatable physical-device checklist.
- Location denied, reduced precision, unavailable hardware, indoor timeout, and simulator all produce explicit degraded states without crashes.
- Marker and baseline captures return within the timeout and save available fields even if location is missing.
- No Access Wi-Fi Information or Hotspot Helper entitlement exists.

### Known risks

- Sensor availability differs across iPhone models and the simulator.
- Raw magnetic coordinates and UI/device orientation can make values incomparable with HarmonyOS until normalisation is validated.
- Permission prompts cannot be reliably reset in ordinary unit tests; maintain a manual clean-install matrix.

### Explicitly deferred

- Persistent track sampling, background location mode, active recording UI, tags/photos during recording, ZIP export.

---

## Phase 4 — Track recording

### Exact scope

- Implement the single-session `RecordingCoordinator` state machine and `SampleAssembler`.
- Require an actual area before start; prevent concurrent sessions.
- Start sensors/location in the foreground, create logical samples nominally at 1 Hz with actual timestamps, batch-save about five points, and await final flush on stop.
- Build start/stop flows, root recording banner, elapsed display, and session error/interrupted state.
- Enable Location Updates background mode only for active recording and only after capability/permission UX is in place.
- Reconcile an unfinished track on relaunch; mark it interrupted rather than silently resuming.
- Add fake-clock/fake-sensor tests and a documented real-device background matrix.

### Files/modules expected

- `Recording/{RecordingCoordinator,RecordingState,SampleAssembler}.swift`
- `Features/Tracks/{TrackListView,StartRecordingSheet,RecordingBanner}.swift`
- Repository batch/finalise/recovery operations
- Background capability/Info.plist changes
- `RoomMarkerIOSTests/{RecordingStateTests,SampleAssemblerTests,InterruptedTrackTests}.swift`
- `docs/IOS_DEVICE_TEST_MATRIX.md` or an equivalent section in the main README

### Validation criteria

- Ten-minute foreground recording produces ordered points near the expected count, preserving real timestamps and missing values.
- Batch-save tests prove no loss on normal stop and no duplicate insertion on retry.
- App switching and a short screen-lock test on a physical iPhone either continue recording or visibly record a gap/degraded result; no synthetic points are backfilled.
- Stopping disables sensors/background delivery and finalises count/end time.
- Force termination/relaunch leaves readable points and a visibly interrupted track.
- Denied background prerequisites do not block foreground recording.

### Known risks

- iOS can suspend timers, particularly indoors when location updates are sparse; exact background 1 Hz is not guaranteed.
- SwiftData context isolation and concurrent flush/stop operations can race without a single writer.
- Continuous location and sensors consume battery and may trigger App Review/privacy scrutiny if poorly explained.

### Explicitly deferred

- Tags and photos, detailed track visualisation, area ZIP export, long-duration/background guarantees, terminated-app automatic resume.

---

## Phase 5 — Tags and photos

### Exact scope

- Add track tag selection/note flow using the six stable raw values and the current fresh recorder snapshot.
- Add new-photo capture, camera authorization, durable app-owned JPEG storage, optional note, and track association.
- Add thumbnail display, full-photo preview, delete, discard, and orphan cleanup.
- Ensure track/area deletion coordinates metadata cascades with file cleanup.
- Optionally add “Choose Existing Photo” through PhotosPicker only if time allows; it is not needed for MVP success.

### Files/modules expected

- `Media/{CameraCaptureView,PhotoCaptureCoordinator,PhotoFileStore}.swift`
- `Features/Tracks/{TrackTagSheet,PhotoNoteSheet,TrackMediaStrip,PhotoPreview}.swift`
- Camera purpose string
- Tag/photo repository operations and cleanup tests
- Small generated test images, not real campus photos

### Validation criteria

- A physical-device track can receive tags and captured photos with action timestamp and fresh optional location/heading.
- Camera denial/cancellation creates neither metadata nor orphan files.
- Failed durable write does not create photo metadata; failed metadata save removes or queues cleanup of the file.
- Deleting a photo, track, or permanently deleted area removes owned files idempotently.
- App relaunch displays saved thumbnails and full images with correct orientation.

### Known risks

- SwiftUI has no complete camera-capture control; a small UIKit/AVFoundation bridge requires lifecycle care.
- Large images can cause memory pressure if decoded at full size for thumbnails or export.
- Database and filesystem changes cannot share one transaction, so cleanup/reconciliation is required.

### Explicitly deferred

- Video/audio, annotation/editing, cloud photo storage, automatic Photos-library save, and broad library permission.
- Final track path/detail polish and ZIP export.

---

## Phase 6 — Track detail and compatible export

### Exact scope

- Build track detail statistics, chronological tags/photos, sample list, and simple normalised path Canvas.
- Implement immutable export snapshots, iOS v2 JSON encoding, manifest, photo path validation, missing-file metadata, and collision-safe filenames.
- Implement an incremental ZIP `STORED` writer with CRC32 and path-safety checks, then integrate file save and share UI.
- Finalise the Wi-Fi capability extension with downstream owner approval and document it.
- Compare iOS output against checked-in HarmonyOS v1 fixtures using a compatibility reader.

### Files/modules expected

- `Features/Tracks/{TrackDetailView,TrackStatisticsView,TrackPathView,TrackPointList}.swift`
- `Export/{RoomMarkerExporter,ZipArchiveWriter,ExportDocument,ExportError}.swift`
- Extended export/ZIP fixtures and tests
- Export-format documentation or JSON Schema files if the downstream team will consume them

### Validation criteria

- Standard Archive Utility and command-line unzip open the archive with no warnings.
- Every manifest track reference and non-missing photo reference resolves to exactly one ZIP entry.
- JSON key names, units, timestamps, ordering, raw labels, optional omission, and UTF-8 handling match the contract.
- iOS v2 includes explicit platform/capability metadata and contains no `wifiCount`/`wifiTop` samples.
- Export handles no tracks, missing photos, duplicate/sanitised names, Unicode names, cancellation, low disk space, and a realistically large photo set without corrupting source data.
- Golden tests decode HarmonyOS v1 and iOS v2 through the shared compatibility reader.

### Known risks

- A custom ZIP writer is format-sensitive; ZIP64 may be required for very large exports and should either be supported or rejected with a clear size limit.
- Downstream consumers may have hard-coded the HarmonyOS v1 Wi-Fi fields.
- Holding entire archives/photos in memory can crash; implementation must stream to disk.

### Explicitly deferred

- Cloud upload, encryption, import/restore, compressed DEFLATE optimisation, cross-device database transfer, route inference, and AI processing.

---

## Phase 7 — UI polish, tests, documentation, and demo readiness

### Exact scope

- Refine layouts, empty/error/permission states, accessibility, localisation readiness, and consistent destructive confirmations.
- Complete unit, integration, limited UI, and manual physical-device matrices.
- Measure battery, memory, archive size/time, and long-session persistence; fix data-loss and crash issues before cosmetic work.
- Write setup, signing, permissions, architecture, export-contract, device-test, and demo instructions.
- Verify privacy manifest/App Privacy answers and remove unused entitlements/framework access.
- Prepare a deterministic demo dataset and script without real personal/location data.

### Files/modules expected

- App README and developer setup guide
- Export-format/device-test documentation
- Accessibility/localisation resources as needed
- Final test suites, launch arguments, and synthetic demo fixtures
- CI workflow only if the team already has a suitable macOS runner; do not add unmaintainable CI for appearance

### Validation criteria

- Clean clone build and all automated tests pass with documented commands.
- Two physical-device models, if available, complete the MVP acceptance flow; one must test no/weak indoor GPS.
- VoiceOver, Dynamic Type, dark mode, portrait/orientation policy, denial flows, and low-storage/export cancellation are checked.
- A 30–60 minute recording does not lose final buffered points or exhibit unbounded memory growth.
- Repository is free of user settings, DerivedData, archives, exported/captured data, secrets, and local signing material.
- Demo can be completed from a clean install using the written script.

### Known risks

- Hardware/OS variation can reveal late lifecycle and sensor issues.
- App Review/privacy requirements may require wording or behaviour changes even for a student-distributed build.
- Polish can expand scope; prioritise data integrity, permissions clarity, and demo reliability.

### Explicitly deferred

- All post-MVP product features, including routing, floor maps, sync, accounts, analytics, remote configuration, data import, and unsupported Wi-Fi scanning.

## Cross-phase quality gates

Every implementation phase should end with:

1. `git status` reviewed for generated/local files.
2. Formatter/linter (if deliberately configured), build, and applicable tests passing.
3. `git diff --check` passing.
4. A note of physical devices/OS versions used for sensor-facing changes.
5. No unrelated HarmonyOS file modifications and no branch switch/merge.
6. Updated architecture/format documentation when a decision changes.

## Five highest-risk technical issues

1. **Wi-Fi format incompatibility:** iOS cannot perform the HarmonyOS nearby Wi-Fi scan; downstream readers must accept explicit unsupported/missing fields in iOS v2 rather than interpreting zeros as observations.
2. **Background recording reliability:** iOS scheduling and indoor location sparsity make exact 1 Hz motion/pressure sampling in the background impossible to guarantee; gaps and interrupted sessions must be first-class.
3. **Sensor semantic parity:** pressure units, magnetic coordinate frames, heading reference north, device orientation, freshness, and hardware availability can make apparently identical fields incomparable.
4. **Persistence plus file consistency:** SwiftData cascades cannot atomically include photo-file writes/deletes, and final point-buffer flushes can race with stop/termination unless there is one coordinated writer and reconciliation.
5. **Export correctness and scale:** custom ZIP records, relative paths, Unicode/colliding names, large photos, and schema versioning can produce corrupt or misleading packages unless export is streamed and fixture-tested.

## Recommended Phase 1 starting point

Begin Phase 1 with one small “contract and persistence” change set: add `.gitignore`, create the minimal iOS 17 SwiftUI project/test target, check in synthetic HarmonyOS v1 fixtures, define v1/v2 export DTOs, and prove the seven SwiftData models plus delete/unassigned/interrupted semantics in tests. Do not start UI CRUD or sensors until that foundation builds from a clean clone and the iOS v2 Wi-Fi capability contract is accepted.
