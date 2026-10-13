# RoomMarker — Campus Indoor-Navigation Data Collection

RoomMarker is a cross-platform field application for collecting structured indoor-navigation evidence: Rooms, reference points, Markers, sensor Tracks, tags, and photographs.

## Why RoomMarker exists

Indoor-navigation work needs more than a floor-plan image. A field team must associate physical places with repeatable observations, record how sensor readings change along a route, and preserve contextual evidence for later analysis.

RoomMarker organises that work around Areas and Rooms. It captures best-effort device readings without inventing missing values, keeps Track media under application ownership, and exports a portable JSON/JPEG archive. The original implementation targets HarmonyOS; the iOS version preserves the data meaning while adapting the workflow to Apple's APIs, permissions, and lifecycle rules.

## Current status

The native iOS student-project product now covers the current portable HarmonyOS data-collection workflow. Earlier Room/Marker/Track behavior completed physical-device acceptance; the later cross-building, catalog, JSON v3, visualisation, recognition and upload work completed offline implementation and full automated regression. A one-route teammate pilot remains the recommended gate before large-scale field collection.

The current implementation is maintained on the `iOS-Application` branch.

- Native Swift 6, SwiftUI, and SwiftData implementation
- Deployment target: iOS 17 or later
- Final validation toolchain: Xcode 27.0 with the iOS 27 SDK
- Automated baseline: **447 logical tests; 0 failed; 0 skipped** (559 parameterized instances)
- Simulator regression: iPhone 18 Pro / iOS 27.0
- Physical acceptance: iPhone 15 Pro / iOS 26.7
- No third-party runtime dependencies

This is an accepted course-project baseline, not a claim of universal production hardening or continuous-integration coverage.

## Core capabilities

- Create and organise Areas, Rooms, and typed Room Markers.
- Capture a Room reference snapshot and a sensor-backed Marker snapshot.
- Inspect live location, pressure, magnetometer, and heading states.
- Take a bounded one-time sensor snapshot with per-source outcomes.
- Record one cross-building Track in the foreground and during supported Home-background or lock-screen intervals.
- Capture 11 typed nodes with explicit building, floor, optional Room binding, one-to-one photo evidence and rollback compensation; retain historical standalone tags and scenery photos.
- Capture corners, switch indoor/outdoor/unknown segments, and correct/split/merge completed segments without changing sensor measurements.
- Capture bounded raw accelerometer/gyroscope batches with real timestamps, delivery delays and gap semantics.
- Import a building/classroom catalog idempotently and generate Rooms from eligible classroom nodes.
- Inspect completed or interrupted Tracks, samples, nodes, photos, raw IMU, interactive 2.5D/3D evidence and a grouped full-screen gallery.
- Produce conservative current-place candidates from Core Location, accuracy and optional pressure without pretending to provide Wi-Fi fingerprinting.
- Export immutable JSON v3, JPEGs and an offline HTML photo index inside a validated STORED ZIP, by area, all Tracks or selected UUIDs.
- Share exactly one final ZIP through the native Share Sheet or upload it to a configured private HTTP(S) receiver.
- Delete individual photos or cascade-delete a Track and its owned data.
- Detect a Track left incomplete by process termination without fabricating an end time or automatically resuming it.

## RoomMarker in action

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/images/01-area-room-marker.png" alt="Area, Room, and sensor-backed Marker" width="360"><br>
      <strong>Structured indoor-space capture</strong><br>
      Area, Room, and sensor-backed Marker evidence.
    </td>
    <td align="center" width="50%">
      <img src="docs/images/02-live-sensors.png" alt="Live Sensors status screen" width="360"><br>
      <strong>Native sensor collection</strong><br>
      Honest authorization and hardware-availability states.
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/images/03-active-track.png" alt="Active Track recording" width="360"><br>
      <strong>Active field recording</strong><br>
      Elapsed state, sampling, tags, and photo capture.
    </td>
    <td align="center" width="50%">
      <img src="docs/images/04-track-detail.png" alt="Completed Track detail with evidence" width="360"><br>
      <strong>Track evidence</strong><br>
      Samples, tags, and an application-owned photo.
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img src="docs/images/05-export-share.png" alt="RoomMarker ZIP in the native iOS Share Sheet" width="360"><br>
      <strong>Secure ZIP export</strong><br>
      One final archive shared through the native iOS Share Sheet.
    </td>
  </tr>
</table>

## HarmonyOS and iOS feature map

The implementations share product concepts and export semantics, but each uses its platform's native facilities.

| Capability | HarmonyOS | iOS |
| --- | --- | --- |
| Area management | Create and organise; deletion can preserve or cascade-delete contents | Create/edit; deletion preserves Rooms and Tracks under `未分区` |
| Room management | Create, inspect, and delete with Marker cleanup | Create, edit, move, inspect, and delete with Marker cascade |
| Room reference capture | Location, altitude, and pressure snapshot | Bounded snapshot with explicit replacement semantics |
| Marker management | Create and delete | Create, edit, and delete |
| Marker sensor capture | Location, accuracy, altitude, pressure, magnetic axes | Equivalent optional fields; metadata edits preserve the capture |
| Live sensors | Native live sensors plus nearby Wi-Fi results | Location, pressure, magnetic axes, and heading |
| Snapshot capture | Used by Room and Marker workflows | Dedicated snapshot screen plus Room and Marker workflows |
| Foreground recording | Nominal one-second Track sampling | Nominal one-second Track sampling, physically validated |
| Home-background recording | HarmonyOS location long-running task | Foreground-started Core Location background activity |
| Lock-screen recording | Supported by the HarmonyOS background workflow | Physically validated as one continuous active session |
| GPS/location | Supported | Core Location; optional when denied or unavailable |
| Pressure | Supported | `CMAltimeter`, where supported |
| Magnetometer | Supported | Core Motion magnetometer |
| Heading | Sensor fusion with location fallback | Core Location device heading when available |
| Nodes/tags | 11 node types plus historical standalone tags | Same 11 semantic node types; explicit node/photo and optional Room binding; old standalone evidence remains independent |
| Camera/photos | System camera picker and app-owned copy | User-initiated camera capture and app-owned JPEG |
| Track structure | Corners and indoor/outdoor segments | Corners, indoor/outdoor/unknown segments, plus completed-segment correction/split/merge |
| Raw IMU | Per-point acceleration/gyro series | Bounded batches with both clocks, delivery delay and explicit units; background gaps are not filled |
| Catalog / Rooms | Building/classroom import and room generation | Idempotent catalog preview/import, explicit node-room binding and classroom-node room generation |
| Track detail | Statistics, points, media and Track3D | Sensor-rich detail, raw IMU, grouped gallery and evidence-gated interactive 2.5D/3D view |
| Place recognition | Nearby Wi-Fi fingerprint matching | Conservative Core Location/accuracy/pressure candidates; not continuous indoor positioning |
| ZIP export | Extended v2 JSON, photos, manifest and selected Track export | JSON v3, photos, HTML index, area/all/selected scope and compatibility metadata |
| Sharing/upload | Document save and upload modules | Native Share Sheet or configurable private ZIP upload; token stored in Keychain |
| Cleanup | Area/Track cascades and photo-file cleanup | Individual photo and Track cascade cleanup |
| Incomplete Track | Missing end time can remain displayed as active | Explicit `需要处理` state; manual finalise or delete |
| Wi-Fi fingerprinting | Nearby AP count and Top-5 BSSID/RSSI | Intentionally unsupported; no fabricated observations |

Normal iOS applications do not have a supported general-purpose equivalent to HarmonyOS nearby BSSID/RSSI scanning. The iOS v3 capability declaration therefore states:

```text
nearbyWifiFingerprint: unsupported
```

This is an intentional platform difference, not an implementation failure.

## Architecture

The application separates UI, workflow state, persistence, hardware services, media ownership, and export serialization. SwiftData models are not encoded directly into export files.

```mermaid
flowchart TD
    UI[SwiftUI Views] --> WF[Workflows / Coordinators]
    WF --> DB[SwiftData]
    WF --> HUB[SensorHub]
    WF --> PHOTO[App-owned Photo Storage]
    HUB --> LOC[Core Location]
    HUB --> MOTION[Core Motion]
    HUB --> ALT[CMAltimeter]
    DB --> SNAP[Immutable Export Snapshot]
    PHOTO --> SNAP
    SNAP --> STAGE[Validated Staging]
    STAGE --> ZIP[STORED ZIP]
    ZIP --> SHARE[Native Share Sheet]
```

Technical details are in [IOS_ARCHITECTURE.md](IOS_ARCHITECTURE.md).

## Quick Start

### Requirements

- macOS with Xcode 27.0 for the final validated configuration
- An iOS 17-or-later simulator, or a compatible physical iPhone
- An Apple development team selected locally when installing on a physical device

The project intentionally leaves `DEVELOPMENT_TEAM` unset. Do not commit personal signing settings, profiles, or identifiers.

### Build and run

1. Clone the repository and check out `iOS-Application`.
2. Open `RoomMarker.xcodeproj` in Xcode.
3. Select the shared `RoomMarker` scheme.
4. Choose an installed iOS Simulator and run the application.
5. For a physical iPhone, select a development team locally and use a bundle identifier available to that team if Xcode requires it.
6. Accept permissions only when the corresponding feature is used.

The simulator is suitable for navigation and deterministic tests, but absent or synthetic simulator readings are not evidence of physical sensor behavior. Use a physical device for camera, pressure, magnetometer, heading, and background/lock-screen validation.

### Run tests

In Xcode, select the `RoomMarker` scheme and choose **Product → Test**. The current baseline used the iPhone 18 Pro / iOS 27.0 Simulator and completed 447 logical tests (559 parameterized instances) with no failures or skips. Receiver/upload tooling adds 32 Python tests.

## Suggested 3–5 minute demo

Use non-sensitive, prepared demo data so the workflow—not setup time—is the focus.

1. Open an existing Area and Room.
2. Capture or replace the Room reference snapshot.
3. Create or show a sensor-backed Marker.
4. Open `实时传感器` and move or rotate the physical device.
5. Start a short Area-bound Track.
6. Add one Tag.
7. Capture one Photo and add a note.
8. Stop recording.
9. Inspect Track Detail, samples, the Tag, and the Photo preview.
10. Export the Area.
11. Show the native Share Sheet and final ZIP.
12. Briefly explain the iOS Wi-Fi platform difference.

Keep permission-denial, destructive cleanup, force-quit recovery, and minute-long lock-screen scenarios as recorded evidence rather than normal live-demo steps.

## Permissions and lifecycle behavior

| Concern | Implemented behavior |
| --- | --- |
| Location | Requests When In Use authorization; the app does not request Always authorization |
| Background recording | Must be explicitly started by the user in the foreground; Core Location background activity is owned only while recording |
| Scheduling | iOS controls execution opportunities; exact one-second background sampling is not promised |
| Core Motion | Protected by `NSMotionUsageDescription` |
| Camera | Requested only after the user initiates Track photo capture |
| Photos Library | No Photos Library permission and no automatic save to Photos |
| Denied/unavailable sensors | Values remain absent; the app does not substitute synthetic zeros |
| Force quit | Recording stops; the persisted Track remains incomplete without a fabricated end time or automatic resume |

Location denial degrades location fields without preventing independent supported sensors from reporting. Permission recovery is user-driven and does not repeatedly prompt.

## Platform differences and known limitations

- Nearby Wi-Fi fingerprint scanning is available in the HarmonyOS implementation but unsupported in the normal iOS application.
- Background delivery and timing remain controlled by iOS; the app records actual timestamps and creates no catch-up points.
- Force-quit survival and automatic recording restart are intentionally unsupported.
- Only one physical device/OS combination completed the earlier Phase 9 acceptance procedure. The latest visualisation, recognition, completed-segment editing and upload additions passed offline regression but still need the planned one-route teammate pilot.
- Multi-hour, poor-signal, low-power, thermal-pressure, reboot, and storage-exhaustion scenarios remain outside the accepted baseline.
- The custom archive writer produces STORED ZIP32 archives. Very large field collections require separate scale validation.
- The 2.5D/3D view is an evidence display, not a floor-plan-matched navigation route. Weak or missing coordinates remain weak/omitted.
- GPS/pressure place candidates do not replace HarmonyOS Wi-Fi fingerprints and do not provide continuous indoor navigation.

## Testing and physical-device evidence

The accepted Phase 9 baseline covers:

- Room reference replacement and persistence after relaunch
- Marker capture and sensor preservation during metadata editing
- Live Sensors and bounded snapshot capture
- Foreground, Home-background, and lock-screen Track recording
- Tag and real camera/photo association
- Track Detail, thumbnail, metadata, and full-size preview
- ZIP creation, Share Sheet presentation, saved-archive inspection, and source immutability
- Individual photo deletion and Track cascade cleanup
- Graceful location-denied behavior without fake coordinates or prompt loops
- Force-quit detection of an incomplete Track without automatic resume
- Export defenses against traversal, absolute paths, sibling-prefix attacks, symlink escape, and filesystem aliases

See [IOS_PHASE9_DEVICE_ACCEPTANCE.md](IOS_PHASE9_DEVICE_ACCEPTANCE.md) for the bounded physical evidence and remaining risks. This evidence does not claim universal production reliability or hosted CI coverage.

## Export format

An iOS JSON v3 export contains:

- `manifest.json`
- one JSON file per Track under `tracks/`
- app-owned JPEG files under relative `photos/` paths when present
- `index.html` for offline photo review
- full cross-building Track data, nodes/room snapshots, corners, segments and raw IMU
- `sourcePlatform: ios`
- a capabilities declaration including `nearbyWifiFingerprint: unsupported`

Manifest references and photo paths are relative. Staging, archive sources, upload multipart bodies and cleanup remain within RoomMarker-owned canonical directories. Export works from an immutable snapshot, does not mutate SwiftData source models, and does not move or delete source photos. The Share Sheet or uploader receives one completed ZIP, not its staging directory.

## Documentation

- [iOS project brief](IOS_PROJECT_BRIEF.md) — historical Phase 0 product and compatibility brief
- [iOS architecture](IOS_ARCHITECTURE.md) — as-built technical architecture
- [iOS implementation plan](IOS_IMPLEMENTATION_PLAN.md) — historical phased plan
- [HarmonyOS parity closure](IOS_PHASE9_5_PARITY_NOTES.md) — Room/Marker sensor parity record
- [Physical-device acceptance](IOS_PHASE9_DEVICE_ACCEPTANCE.md) — final Phase 9 evidence and limits
- [JSON v3 contract](IOS_JSON_V3_CONTRACT.md) — current cross-building archive semantics and migration rules
- [Full product parity](IOS_FULL_PRODUCT_PARITY.md) — HarmonyOS feature follow-up, honest platform differences and latest regression
- [Team installation and collection](IOS_TEAM_COLLECTION_GUIDE.md) — signing options, field workflow and ZIP handoff
