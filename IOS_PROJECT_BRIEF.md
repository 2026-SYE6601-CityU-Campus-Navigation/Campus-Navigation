# RoomMarker iOS Project Brief

> **Historical status — Phase 0 record.** This brief captured the product and migration decisions before implementation. The iOS MVP has since been completed and physically validated; see [IOS_PHASE9_DEVICE_ACCEPTANCE.md](IOS_PHASE9_DEVICE_ACCEPTANCE.md) for the accepted result.

## Status and purpose

This document is the Phase 0 brief for a native iOS version of RoomMarker, the campus indoor-navigation data collection application already implemented for HarmonyOS. Phase 0 produces architecture and migration documentation only. It does not create an Xcode project or application code.

The iOS app will let a student field team organise collection work by area and room; record room baselines and markers; record timed tracks with available location, pressure, magnetic-field, and heading data; attach tags and photos during a track; inspect the result; and export a machine-readable package for later indoor-navigation work.

The implementation should be a native Apple application, not a line-for-line ArkTS translation. Behaviour and exported-data meaning are the compatibility targets. Platform-specific implementation details and unsupported sensors must be represented honestly.

## Relationship to the HarmonyOS implementation

The planning baseline is the completed source at `origin/main` and `origin/Harmony-Application`, inspected with read-only Git commands. The two refs contain the same application implementation; `origin/main` additionally contains the legacy one-line `README` file. No source from either ref has been merged or copied into `iOS-Application`.

The HarmonyOS app establishes these behaviours:

- `Area` is the top-level folder for rooms and tracks. A null area relationship is shown as the synthetic “unassigned” area with UI identifier `0`.
- Rooms contain an optional location/pressure baseline and child markers.
- Saving a marker captures a best-effort location, pressure, and magnetic-field snapshot.
- A track is assigned to a real area, sampled nominally once per second, and flushed to persistence every five samples.
- Tags and photos record their own timestamp and the recorder's current location and heading snapshot.
- Area export produces `manifest.json`, one JSON file per track, and original photos under relative `photos/...` paths inside a ZIP archive.
- Missing sensor values are valid and are omitted from HarmonyOS JSON because they are `undefined` before `JSON.stringify`.

The iOS app should preserve those user concepts and export semantics. It does not need database-file compatibility with HarmonyOS or Android; cross-platform interchange occurs through exported JSON and photo packages.

## MVP feature scope

### Included

- Create, list, view, and delete areas; move an area's children to unassigned or delete them with confirmation.
- Create, list, view, and delete rooms.
- Capture a room baseline and create/delete typed room markers.
- Show a live view for iOS-exposed location, pressure, accelerometer, gyroscope, magnetometer, attitude, and heading values when available.
- Start and stop an area-bound track; collect one logical sample per second while execution is available; batch-save points.
- Add one of the six existing track tag types with an optional note.
- Capture a photo, store an app-owned copy, add an optional note, and associate the current track snapshot.
- List tracks, show track statistics, tags, photos, samples, and a simple normalised path preview.
- Export a versioned JSON/photo package, create a ZIP, and save or share it with the system UI.
- Clearly show permission, hardware availability, degraded-mode, and recording state.

### Explicitly outside the MVP

- Indoor route calculation, turn-by-turn navigation, floor-plan editing, cloud sync, team accounts, backend upload, AI analysis, and data import.
- Wi-Fi fingerprint scanning on iOS.
- Private APIs, special-purpose Hotspot Helper entitlements, or attempts to infer nearby access points.
- Pixel-identical HarmonyOS UI, generic enumeration of all device sensors, and HarmonyOS-only environmental sensors.
- Guaranteed uninterrupted sampling after force-quit, reboot, permission revocation, low-power intervention, or operating-system termination.
- Direct migration of `room_marker.db` between operating systems.

## Domain model compatibility

Persistence models may use SwiftData relationships and UUIDs, but export DTOs must use the established names, units, optionality, and labels below. Relationships should use delete rules that reproduce the current manual cascades.

| Model | Required compatibility meaning |
|---|---|
| `Area` | `name`, `note`, creation time; owns rooms and tracks. “Unassigned” is a query/UI state backed by a null relationship, not a persisted Area row. Counts are derived, not authoritative stored values. |
| `Room` | `name`, `note`, optional area, optional WGS-84 latitude/longitude, metres altitude, hPa pressure, Unix-millisecond creation time. |
| `Marker` | Parent room, `name`, the existing Chinese `markerType` label, optional location/accuracy, hPa pressure, magnetic X/Y/Z, and Unix-millisecond creation time. |
| `Track` | `name`, area, Unix-millisecond start/end times, and point count. Point count should be derived or reconciled with persisted points rather than trusted blindly after an interrupted session. |
| `TrackPoint` | Unix-millisecond `timeMs`; optional location, metres altitude/accuracy, hPa pressure, magnetic X/Y/Z in µT, and `headingDeg` normalised to `[0, 360)`; Wi-Fi is discussed below. |
| `TrackTag` | Existing Chinese `tagType` label, note, timestamp, optional location and heading, and creation time. |
| `TrackPhoto` | Track-relative file path, note, timestamp, optional location and heading, and creation time. The database must never be the sole owner of photo bytes. |

The exact stored labels remain:

- Marker types: `前门`, `后门`, `窗户`, `墙角`, `插座`, `自定义`.
- Track tag types: `厕所`, `楼梯`, `门`, `门禁`, `电梯`, `教室`.

Do not localise these persisted/exported values. The UI can display localised strings through a mapping while the stable raw values remain unchanged.

## JSON and package compatibility contract

The HarmonyOS export format is the reference fixture, not an informal example.

- All timestamps are integer Unix epoch milliseconds, never Swift reference dates or ISO strings.
- Coordinates and sensor values remain JSON numbers in the units listed above.
- Unsupported or unavailable optional readings are absent, not zero, empty text, or last-known values outside an explicitly documented freshness limit.
- Arrays are chronological by `timeMs`.
- Each track document keeps `name`, `area`, `startedAt`, optional `endedAt`, `pointCount`, `points`, `tags`, and `photos`.
- Photo objects keep the relative `file` path and may set `fileMissing: true`; ZIP entry paths must exactly match successful photo references.
- The manifest keeps `app`, `exportedAt`, `area`, `trackCount`, and `tracks`; each track entry points to its JSON filename.
- JSON is UTF-8, filenames are sanitised, and generated names must be collision-safe.
- Persistence-only identifiers and SwiftData implementation details must not leak into the JSON contract unless required for a relative filename.

### iOS schema version and Wi-Fi representation

HarmonyOS track documents use `version: 1` and require `wifiCount: number` plus `wifiTop: string` at every point. Normal iOS applications have no general-purpose API to scan nearby Wi-Fi networks. `NEHotspotNetwork.fetchCurrent` can, under specific authorization and entitlement conditions, report only the currently associated network; it is not a nearby scan and does not provide the HarmonyOS Top-5 BSSID/RSSI fingerprint. It must not be used as a substitute.

The recommended iOS export is therefore a deliberately versioned compatible extension:

- Emit track `version: 2` and add top-level `sourcePlatform: "ios"` and `capabilities.nearbyWifiFingerprint: "unsupported"` metadata. Mirror capability metadata in the manifest.
- Omit `wifiCount` and `wifiTop` from iOS points. Do not emit `0`, an empty string, invented BSSIDs, current-network-only data, or stale scan data.
- Preserve all other shared v1 keys and meanings.
- Build a small shared compatibility reader/test fixture that accepts HarmonyOS v1 and iOS v2. A consumer must distinguish missing/unsupported from a real scan containing zero networks.
- Do not advertise the iOS v2 package as byte-for-byte v1 compatible. It is semantically compatible for shared sensors and explicitly self-describing for the unavailable capability.

Before Phase 6 implementation, this v2 extension should be reviewed with whoever owns downstream ingestion. If an immutable v1 consumer exists, change that consumer or agree on an explicit sidecar capability declaration; do not silently manufacture v1 Wi-Fi values.

## Important platform differences

| HarmonyOS behaviour | iOS decision or limitation |
|---|---|
| Relational store with integer IDs | SwiftData on iOS 17+ with relationships and UUID identity. Export DTOs isolate the wire format from persistence. |
| Nearby Wi-Fi scan and Top-5 BSSID/RSSI | Unsupported for a normal iOS app; omitted and declared unsupported in v2 exports. No special entitlement should be requested for this project. |
| Generic sensor list and many environmental sensors | iOS exposes purpose-specific APIs. Only show supported Core Location/Core Motion readings after runtime capability checks. No generic vendor/name list equivalent. |
| Barometer absolute pressure | `CMAltimeter` reports pressure in kPa and relative altitude; convert pressure to hPa (`kPa × 10`). Barometer availability varies by device. Do not treat relative altitude as GPS altitude. |
| Acceleration + magnetic-field heading | Prefer Apple-provided heading/device-motion fusion. Define whether exported heading is magnetic or true north and correct for device orientation. Raw axis signs and reference frames require fixture testing rather than direct copying. |
| Location-driven long-running task | iOS has no general foreground service or wakelock. A user-started Core Location session with the Location Updates background mode can continue, but the OS controls suspension and termination. Background motion-only 1 Hz execution is not guaranteed indoors. |
| System camera picker without camera permission | Capturing a new photo on iOS requires camera authorization and `NSCameraUsageDescription`. Selecting an existing photo through PhotosPicker can be offered separately without broad library access. |
| Document save picker | Build the archive in a temporary app location, then use a SwiftUI file exporter and/or system share sheet. Clean temporary exports after completion. |
| Handwritten uncompressed ZIP | Use a small, reviewed ZIP `STORED` writer if Apple SDK support does not meet the target. Keep it isolated and verify archives with standard unzip tools; avoid a dependency solely for this small format unless testing proves the native approach too risky. |

## Unsupported and degraded features

- Wi-Fi fingerprint UI and data are unavailable on iOS and should be shown as unsupported, not perpetually “scanning.”
- Location may be absent or reduced-accuracy indoors. Samples remain valid with location fields missing.
- Pressure, magnetic field, heading, and motion values depend on device hardware and authorization. Simulator support is insufficient for acceptance.
- A track may contain gaps after suspension or system termination. Store actual timestamps; never backfill synthetic points to make the sample rate appear continuous.
- Heading values from different platforms may not be numerically comparable until coordinate-frame and device-orientation tests pass.
- Background continuation is best effort. The recording UI must state when background permission/capability is unavailable and reconcile an unfinished session on next launch.

## Privacy and permissions

Request access only at the moment the user invokes a dependent feature, with plain-language purpose strings.

- Location: provide `NSLocationWhenInUseUsageDescription`; enable the Location Updates background mode only for active recording. Start with When In Use authorization for a foreground-started session. Request Always only if a later, reviewed requirement genuinely needs relaunch/location events outside a user-active session.
- Precise location: operate with reduced accuracy, but explain why precise accuracy improves collection and allow the user to continue in degraded mode.
- Motion: include `NSMotionUsageDescription` when using authorization-gated motion/fitness services and handle denial without blocking unrelated features.
- Camera: provide `NSCameraUsageDescription`; check authorization only when “Take Photo” is chosen. Saving to the app sandbox needs no photo-library permission.
- Photo library: avoid requesting broad library access for MVP. If “Choose Existing Photo” is added, use PhotosPicker, which grants access only to selected items.
- Wi-Fi: do not request Access Wi-Fi Information or Hotspot Helper entitlements for the MVP.
- App privacy disclosures must match actual on-device use. No collected location, photo, or sensor data leaves the device unless the user explicitly exports or shares it.

Permission denial, hardware absence, and temporary sensor failure are normal states. They must be visible and must not cause a crash or corrupt a recording.

## Repository hygiene strategy

`origin/main` currently tracks substantial generated and local HarmonyOS output, including 99 files under `entry/build/`, 22 under `.hvigor/`, seven under `.idea/`, signed/unsigned HAP files, compiler caches, logs, reports, and `local.properties`. The iOS branch must not repeat this pattern or modify those HarmonyOS files.

At the start of Phase 1, add a root `.gitignore` in the iOS branch that ignores at least:

```gitignore
# Xcode per-user and build output
DerivedData/
build/
*.xcuserstate
xcuserdata/
*.moved-aside
*.xccheckout
*.xcscmblueprint

# Swift Package Manager generated state
.build/
.swiftpm/
Package.resolved

# Dependency managers, only if introduced
Pods/
Carthage/Build/

# Local configuration and secrets
*.xcconfig.local
Secrets.xcconfig
*.mobileprovision
*.p12

# OS/editor files
.DS_Store
*.swp
```

`Package.resolved` may be committed later if the team deliberately adopts Swift packages and wants reproducible app builds; with the recommended dependency-free MVP, it should not exist. Shared Xcode schemes and project metadata should be committed; `xcuserdata`, DerivedData, archives, `.ipa` files, test-result bundles, exported ZIPs, captured sample photos, and local databases should not. Test fixtures must be small, anonymised, and placed intentionally under the test target rather than ignored wholesale.

## Definition of a successful iOS MVP

The MVP is successful when, on at least one supported physical iPhone and from a clean install, a student can:

1. Create an area and room, record a partial or complete room baseline, and add a typed marker.
2. Inspect available live sensors with clear unavailable/denied states.
3. Start an area-bound track, collect timestamped points for at least ten minutes, background or lock the device for a short documented test, resume, and stop without database corruption.
4. Add a tag and a newly captured photo during the track, then view both afterward.
5. Export a valid ZIP whose manifest, track JSON, and photo paths pass schema/fixture tests and open with standard tools.
6. Demonstrate that Wi-Fi fingerprint capability is explicitly `unsupported`, with no fabricated Wi-Fi observations.
7. Recover predictably from denied permissions, sensor absence, interrupted recording, missing photo files, export cancellation, and app relaunch.

MVP acceptance requires real-device tests; a simulator-only demonstration is not sufficient.

## Official Apple references used for platform decisions

- [TN3111: iOS Wi-Fi API overview](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)
- [NEHotspotNetwork.fetchCurrent](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:))
- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [Core Motion](https://developer.apple.com/documentation/coremotion)
- [Requesting authorization to capture and save media](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Selecting photos and videos in iOS](https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios)
