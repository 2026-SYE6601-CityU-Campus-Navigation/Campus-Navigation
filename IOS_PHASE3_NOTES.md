# RoomMarker iOS Phase 3 Notes

## Scope delivered

Phase 3 adds the foreground sensor platform foundation, explicit permission/capability states, bounded one-shot snapshots, and a Live Sensors screen. It uses only Apple frameworks and preserves Phase 2 Area/Room/Marker behaviour.

This phase does not add track recording, background execution, camera/photos, Wi-Fi scanning, export/ZIP, or persistence of a snapshot into `Room` or `Marker`. The Area List sensor menu opens a live screen and a developer-facing snapshot screen; both are read-only with respect to SwiftData.

## Sensor architecture

The implementation is split into small main-actor services behind native Swift protocols:

- `CoreLocationSensorService` owns one `CLLocationManager` and supplies foreground location plus device heading.
- `CoreMotionMagnetometerService` owns one `CMMotionManager` and supplies raw magnetic-field components.
- `CoreMotionPressureService` owns one `CMAltimeter` and supplies pressure.
- `SensorHub` combines the latest typed states and coordinates consumers. Starting a second consumer does not duplicate hardware sessions; services stop when the final consumer releases its lease.
- `SensorSnapshotService` reads a `SensorHubProtocol`, so tests use a deterministic fake rather than real hardware.

`SensorValueState` can represent `waiting`, `unsupported`, `unavailable`, `permissionDenied`, `restricted`, `stale`, or `available`. Hardware values are optional in `SensorSnapshot`. Missing and stale values are omitted from the snapshot rather than converted to zero.

## Apple frameworks and permission model

Phase 3 imports:

- Core Location for WGS-84 latitude/longitude, Core Location altitude, horizontal accuracy, authorization state, and magnetic heading;
- Core Motion `CMMotionManager` for raw magnetometer samples;
- Core Motion `CMAltimeter` for barometric pressure;
- SwiftUI and Observation for UI/lifecycle state;
- Swift structured concurrency for bounded snapshot waiting, cancellation, and stale-value timers.

Only `NSLocationWhenInUseUsageDescription` was added. Its user-facing text explains that RoomMarker reads location while the user uses sensor features for indoor-navigation data display and collection. Phase 3 never requests Always authorization and does not enable a background mode. Live Sensors does not prompt on appearance: a visible button requests When In Use access only while the status is `notDetermined`. Denial and restriction remain explicit, do not trigger repeated prompts, and do not block pressure or magnetic data.

No motion-purpose string is added because Phase 3 uses raw `CMMotionManager` magnetometer and `CMAltimeter` readings, not Motion & Fitness history/activity APIs such as `CMMotionActivityManager` or `CMPedometer`. No camera or photo-library purpose string is present.

## One-shot snapshot design

`SensorSnapshot` is a non-persistent value containing a Unix-millisecond `capturedAt` and optional fields for:

- latitude, longitude, altitude, and horizontal accuracy;
- `pressureHpa`;
- `magneticX`, `magneticY`, and `magneticZ`;
- `headingDeg`.

It also carries per-source outcomes for location, pressure, magnetometer, and heading. A partial result is valid. For example, available location plus unsupported pressure is returned as data rather than treated as an error.

Capture begins only after the user presses the snapshot button. The default timeout is four seconds, with a short 50 ms state poll interval. The service can return earlier when all sources have reached an available or terminal degraded state. At timeout, already-available values are preserved and still-waiting sources are marked `timedOut`. Stale samples are identified but excluded from numeric snapshot fields.

Cancellation throws `CancellationError`; a `defer` always releases the snapshot consumer. The hub then stops Core Location/Core Motion updates if no live consumer remains. Leaving the snapshot screen cancels an in-flight capture.

## Pressure units

Apple exposes `CMAltitudeData.pressure` in kilopascals (kPa). The service validates that the value is finite and non-negative, then converts it to the RoomMarker `pressureHpa` contract using:

```text
hPa = kPa × 10
```

For example, `101.325 kPa` becomes `1013.25 hPa`. Relative altitude from `CMAltimeter` is deliberately not used as Core Location altitude and is not included in the Phase 3 snapshot.

## Magnetometer units and coordinate-frame caveat

`CMMagnetometerData.magneticField` components are displayed and captured in microteslas (µT). X, Y, and Z are raw Apple device-coordinate axes. They are not claimed to have the same orientation, handedness, calibration, or screen-orientation mapping as HarmonyOS `MAGNETIC_FIELD` values. Downstream cross-platform analysis must preserve the source platform and validate frame transformations using a physical-device fixture before comparing axes.

The live update interval is 250 ms (4 Hz), avoiding the HarmonyOS page's faster reconstruction workaround while remaining responsive for inspection. Values become stale after three seconds without a new sample.

## Heading behaviour

Heading uses `CLLocationManager` heading updates and the valid `magneticHeading`, not a locally fused accelerometer/magnetometer azimuth. Values are normalised to `[0, 360)` degrees and represent magnetic north. A heading with negative `headingAccuracy` or a non-finite value is ignored. Heading becomes stale after five seconds without a valid update. No simulator or fallback heading is fabricated.

Device/interface orientation can affect how users interpret the phone's pointing direction. Phase 3 has not completed a multi-orientation physical-device comparison with HarmonyOS, so future track/export work must retain this as a real-device validation item.

## Location freshness and live lifecycle

Core Location samples require valid coordinates and non-negative horizontal accuracy. Altitude is included only when vertical accuracy is valid. A location becomes stale after 15 seconds without a new valid update.

Live Sensors starts the hub on appearance and releases it on disappearance. The hub starts each underlying service once for its first consumer and stops all three after the last consumer leaves. The screen displays actual values or named states; it never uses numeric zero as a missing placeholder. An explanatory card states that nearby Wi-Fi scanning is unsupported for a normal iOS app.

## Simulator limitations

On the iPhone 18 Pro iOS 27.0 Simulator, pressure, raw magnetometer, and physical heading are not expected to behave like real iPhone hardware. The adapters query native availability and display unsupported/unavailable/waiting states without injecting samples. Core Location depends on Simulator location and authorization configuration; the application does not set a route or hard-code CityU coordinates.

Simulator-safe completion proves compilation, state handling, bounded timeout, cancellation, and lifecycle cleanup. It does not prove pressure accuracy, magnetic-axis meaning, compass accuracy, location accuracy, or behaviour in a real indoor environment.

## Swift 6 concurrency and cleanup

The project remains in Swift 6 mode with complete strict-concurrency checking and `MainActor` default isolation. Framework managers, mutable UI-facing state, protocol calls, and callback bridging are main-actor isolated. Core Motion callbacks copy primitive values before entering a main-actor `Task`. Timeout and staleness work uses structured `Task` cancellation. No `@unchecked Sendable`, unsafe isolation escape, detached task, or warning suppression was added.

Every service has idempotent start/stop behaviour. Late Core Motion callbacks are ignored after stop, stale timers are cancelled, Core Location location/heading updates are stopped, and `SensorSnapshotService` releases its hub consumer on success, timeout, or cancellation.

## Automated validation

`Phase3SensorTests` adds 13 hardware-independent tests for:

1. complete synthetic snapshot;
2. valid partial snapshot;
3. location denied;
4. location unavailable;
5. pressure unavailable;
6. magnetometer unavailable;
7. heading unavailable;
8. bounded timeout with a partial result;
9. cancellation cleanup;
10. kPa-to-hPa conversion;
11. absence remaining nil rather than zero;
12. mixed live states;
13. shared hub start/final-consumer cleanup.

Together with the 23 Phase 1/2 tests, 36 tests in four suites run on the iPhone 18 Pro iOS 27.0 Simulator. Tests do not depend on GPS, motion, simulator location, or physical hardware.

## Physical iPhone validation still required

Before sensor readings are persisted into Room, Marker, or Track data, test on at least one supported iPhone:

- clean-install permission request, denial, Settings recovery, reduced-accuracy location, and location-services-off behaviour;
- pressure conversion against a trusted reading and hardware without an altimeter where available;
- raw magnetic axes in portrait and any supported alternate orientation;
- magnetic-heading accuracy, calibration UI, and relationship to the physical top of the phone;
- start/stop battery/lifecycle behaviour over repeated navigation and snapshot cancellation;
- weak/no indoor GPS and four-second partial snapshots.

No physical iPhone sensor validation occurred in this Phase 3 run.

## Deferred to Phase 4 and later

- `TrackRecorder`, Track creation, the 1 Hz sampling loop, point buffering/batch persistence, interrupted-recording recovery, and all background location;
- persistence of snapshot values into Room or Marker;
- tags, camera/photo capture, and media files;
- nearby Wi-Fi scanning or fabricated Wi-Fi fields;
- final JSON mapping, ZIP creation, sharing/export, routing/maps, and AI/RAG features.

The recommended Phase 4 starting point is a fake-clock `RecordingCoordinator` state machine and pure `SampleAssembler` that consume `SensorHubProtocol` snapshots. Keep it foreground-only until ordered 1 Hz samples, five-point flushes, stop/final-flush races, and interrupted-session recovery pass deterministic tests; review background location separately afterward.
