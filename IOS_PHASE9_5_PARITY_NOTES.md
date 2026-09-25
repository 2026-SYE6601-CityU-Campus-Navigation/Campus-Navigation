# RoomMarker iOS Phase 9.5 HarmonyOS Parity Notes

## Scope and boundary

Phase 9.5 closes one narrowly defined parity gap: Room reference sensor snapshots and sensor-backed Marker creation. It reuses the Phase 3 sensor stack and does not begin Phase 10, change Track recording, add schema fields, or alter export formats.

## HarmonyOS behavior compared

The implementation was compared directly with `origin/main` using read-only Git operations. In the HarmonyOS application:

- `RoomDetail.ets` requests one `SensorSnapshotter.captureSnapshot()` operation when a Room reference point is captured, then persists latitude, longitude, altitude, and pressure through `Store.updateRoomBase`.
- Marker creation requests one snapshot, then persists latitude, longitude, altitude, horizontal accuracy, pressure, and magnetic X/Y/Z with the Marker.
- `SensorSnapshotter.ets` may return a partial snapshot because individual hardware sources can be unavailable or time out.
- The Store and entity definitions permit missing sensor values instead of requiring fabricated defaults.

## Previous iOS parity gap

Before Phase 9.5, the iOS Room Detail screen displayed previously stored Room sensor values but could not capture or refresh them. Marker creation saved only the name and type, even though the Marker model already contained compatible optional sensor fields. Track sensor collection existed separately and remains unchanged.

## Room reference snapshot semantics

- A user explicitly starts capture from Room Detail.
- One bounded `SensorSnapshotService.capture()` call supplies the whole operation.
- The persisted Room fields are latitude, longitude, altitude, and pressure only.
- The new snapshot fully replaces the previous reference snapshot. If a field is absent in the new snapshot, that stored field becomes `nil`; old and new readings are never blended.
- A snapshot with no available Room fields is still a completed capture and clears the previous reference values. The UI reports that no usable Room reference data was available.
- No missing value is converted to zero.

## Marker snapshot semantics

- A new Marker validates its name, then performs exactly one bounded sensor snapshot before insertion.
- The Marker persists every available compatible field from that single snapshot: latitude, longitude, altitude, horizontal accuracy, pressure, and magnetic X/Y/Z.
- Partial snapshots are valid. Available values are saved and unavailable values remain `nil`.
- A fully unavailable or permission-denied snapshot still permits Marker creation with all sensor fields `nil`; the app does not fake readings or block basic data entry.
- A capture or persistence error is presented to the user and does not create a partially saved Marker.

## Edit and recapture behavior

Editing an existing Marker changes only its name and type. Existing sensor fields are preserved, and opening or saving the edit form does not trigger capture. An explicit Marker recapture action is intentionally deferred so users cannot accidentally replace provenance-bearing readings while making a metadata edit.

Room recapture is explicit and uses the same full-replacement rule as first capture. The button changes from “采集房间参考点” to “更新参考点” once any Room reference value exists.

## Sensor architecture reuse

The app creates one `SensorHub` and one shared `SensorSnapshotService` at the composition root. The service is passed through the SwiftUI hierarchy and injected into a small `RoomMarkerSnapshotWorkflow`. No additional `CLLocationManager`, `CMMotionManager`, or `CMAltimeter` is created. Snapshot acquisition therefore continues to use the existing lease, timeout, freshness, authorization, and cleanup behavior.

The workflow depends on the `SensorSnapshotCapturing` protocol so persistence mapping and failure behavior can be tested deterministically without hardware or extra framework managers.

## Field mapping

| Snapshot field | Room | Marker |
| --- | --- | --- |
| `latitude` | `latitude` | `latitude` |
| `longitude` | `longitude` | `longitude` |
| `altitude` | `altitude` | `altitude` |
| `accuracy` | Not stored | `accuracy` |
| `pressureHpa` | `pressureHpa` | `pressureHpa` |
| `magneticX` | Not stored | `magneticX` |
| `magneticY` | Not stored | `magneticY` |
| `magneticZ` | Not stored | `magneticZ` |

The model schema and JSON field names remain unchanged, preserving the existing HarmonyOS/iOS interchange contract.

## Unavailable and permission-denied sensors

Sensor availability is evaluated field by field. Location denial can yield a snapshot containing pressure or magnetic data; unavailable motion or altimeter hardware can yield location-only data. These combinations are persisted without substitution. UI text describes missing values as unavailable and never implies a zero reading.

The bounded capture can be cancelled when its owning screen disappears. The existing snapshot service releases its sensor lease on success, timeout, error, or cancellation.

## Wi-Fi platform exception

Phase 9.5 does not scan nearby Wi-Fi networks and does not add Wi-Fi capture to Rooms or Markers. Normal third-party iOS applications do not have a supported general-purpose equivalent to HarmonyOS nearby access-point fingerprint scanning. Existing `wifiCount` and `wifiTop` compatibility fields remain absent/empty according to the established export contract; the application does not fabricate SSIDs, BSSIDs, counts, signal strengths, or placeholder fingerprints.

## UI integration

Room Detail now shows a dedicated Room reference section, a bounded-capture progress state, available stored values, and clear replacement semantics. New Marker creation labels its action “采集并保存,” shows progress, and explains that missing readings remain empty. Marker rows display altitude and horizontal accuracy when available. Existing Marker editing explains that sensor values are preserved.

The Simulator smoke test also confirmed that existing Area export controls and Track Detail still open. Track Detail continued to show overview, tag, photo, and sample-point sections.

## Automated validation

`Phase9_5ParityTests` adds deterministic coverage for:

- complete, partial, and fully unavailable Room snapshots;
- full replacement and clearing of stale Room values;
- complete, location-only, pressure/magnetic-only, and unavailable Marker snapshots;
- absence of fake zero values;
- Marker creation after location denial;
- edit preservation of existing sensor fields;
- reuse of the production sensor hub lifecycle without duplicate manager ownership;
- unchanged Room-to-Marker cascade deletion and individual Marker deletion.

The complete automated suite passed: 191 tests in 10 suites, with zero failures.

## Simulator validation

The Debug app built, installed, and launched on an iPhone 18 Pro / iOS 27.0 Simulator. A disposable `Phase9.5` Area and `Room95` Room were used for UI validation. Because Simulator sensor data was unavailable, Room capture reported no usable reference data and displayed no fake numbers. Creating `M95` still succeeded and its row reported no available sensor data. Opening Marker edit showed the sensor-preservation policy. Existing Track Detail and export entry points remained accessible.

Simulator behavior is not evidence of real Core Location, heading, magnetometer, or altimeter behavior.

## Physical-iPhone validation still required

On a trusted, Developer-Mode-enabled physical iPhone, validate:

- first-run and denied When In Use location authorization behavior;
- complete and partial Room reference capture, including explicit replacement of older values;
- Marker capture with plausible location, horizontal accuracy, altitude, pressure, and magnetic readings;
- changes in heading/magnetic axes as the device rotates and pressure response where CMAltimeter is available;
- the four-second bound, cancellation, lease release, and repeated captures;
- preservation of existing Track recording, tag/photo, export, and background behavior after these UI additions.

No physical-device success claim is made in Phase 9.5.

## Deferred work

- Explicit recapture of an existing Marker is deferred.
- Any schema migration or export-format change is deferred.
- Wi-Fi scanning or synthetic Wi-Fi data is unsupported and will not be implemented.
- Phase 10 work is not started.

