# RoomMarker iOS Phase 4 Notes

## Scope delivered

Phase 4 adds foreground-only track recording, an explicit recording state machine, nominal one-second sample assembly, five-point SwiftData batching, and functional Track list/detail/delete UI. Recording requires a real `Area`, matching the HarmonyOS start flow even though the persistence model still permits a nil area for tracks moved to 未分区 after an Area is deleted.

This phase does not enable Background Modes, request Always location permission, set `allowsBackgroundLocationUpdates`, or claim continued recording while iOS suspends the app. It also does not add camera/photo capture, track-tag capture, Wi-Fi scanning, maps/path drawing, ZIP creation, or final export UI.

## RecordingCoordinator state machine

`RecordingCoordinator` owns the one active session and publishes these states to SwiftUI:

```text
idle -> preparing -> recording -> stopping -> idle
                    |          |
                    +-> failed <-+
```

Start validates a trimmed nonempty name and a real Area before entering `preparing`. It creates exactly one incomplete `Track`, acquires the `.recording` SensorHub consumer, starts exactly one ticker, and then enters `recording`. A second start is rejected. Stop is accepted only from `recording`; idle/repeated stop calls are safely rejected.

On a clean stop, the coordinator changes to `stopping` before awaiting ticker shutdown. This prevents queued ticks from being accepted. It then flushes the tail, sets `endedAt`, saves, releases only the `.recording` sensor consumer, clears transient session state, and returns to `idle`. SensorHub reference-counting means a concurrent Live Sensors or snapshot consumer remains active.

## Clock and nominal 1 Hz policy

`RecordingTicking` is a small native Swift protocol. `ForegroundRecordingTicker` sleeps for one second and then delivers one wall-clock Unix-millisecond timestamp. Tests inject `ManualRecordingTicker`, which delivers ticks immediately and never waits for real time.

One delivered, strictly newer tick produces at most one logical sample. Duplicate or out-of-order timestamps are ignored. If the process is delayed or suspended, no catch-up loop, interpolation, or synthetic historical samples are created. Therefore “1 Hz” is nominal scheduling intent, not an accuracy or background-delivery guarantee.

## SampleAssembler and sensor staleness

`SampleAssembler` is separate from SwiftData. It maps the latest `LiveSensorState` into a `TrackPointDraft` containing `timeMs` plus optional location, altitude, accuracy, pressure, magnetic components, and heading.

Only `.available` Phase 3 readings are usable. `.stale`, `.waiting`, `.unsupported`, `.unavailable`, `.permissionDenied`, and `.restricted` values become nil. Non-finite values are also omitted; accuracy and pressure must be nonnegative. A missing source never becomes numeric zero. A partial point remains valid, including a timestamp-only point when every physical measurement is unavailable.

The coordinator reuses the application-wide `SensorHub` rather than constructing another Core Location/Core Motion/CMAltimeter stack. Recording requests When In Use location only as a consequence of the explicit Start action.

## Wi-Fi compatibility behavior

Normal iOS applications cannot perform the HarmonyOS-style scan of nearby access points. Every Phase 4 draft therefore uses:

- `wifiAvailability = .unsupported`
- `wifiCount = nil`
- `wifiTop = nil`

No BSSID, RSSI, count, empty scan, or fake observation is generated.

## Buffered SwiftData persistence

The first four drafts remain in the coordinator's in-memory buffer. The fifth causes one `RecordingPersisting.append` call, and `SwiftDataRecordingStore` inserts the five `TrackPoint` objects followed by one `ModelContext.save()`. Subsequent complete groups behave the same way. Stop persists a final one-to-four-point tail before finalizing the Track.

The buffer is removed only after a successful append. There is no automatic batch retry that could duplicate points. Arrival order is retained, and Track detail sorts by `timeMs`. `Track.pointCount` remains the relationship-derived `points.count`; no stored counter can drift from persisted SwiftData rows. The active banner's sample count includes both persisted and pending samples and is transient UI state only.

## Failure and interruption behavior

If a batch append or clean finalization fails, recording stops accepting ticks, releases the recording sensor lease, and enters `failed`. The Track is not deleted and `endedAt` is not falsely assigned by the coordinator, so it remains visibly incomplete; any batches already saved remain readable. Pending memory that could not be committed is not presented as persisted data. Full relaunch recovery and retry orchestration remain deferred.

An existing Track with `endedAt == nil` is displayed as `未完整结束`. Phase 4 does not silently resume it after relaunch.

## Track and recording UI

The Area list toolbar now provides a Track entry. The start sheet requires a name and Area. A foreground status banner remains visible across the app's existing navigation stack and shows the active name, elapsed wall time, current logical sample count, and Stop control. Elapsed display uses `TimelineView`; it does not create a second sampling timer.

The Track list displays name, Area, start time, ended/active/incomplete status, and relationship-derived point count. Track detail shows summary fields and a timestamp-ordered debug list containing only measurements that actually exist. Timestamp-only samples are called out explicitly. Map/polyline analytics are deferred.

Track deletion requires confirmation and uses the existing SwiftData cascade relationships for points, tags, and photo metadata. Delete controls are disabled/rejected for the active Track.

## Validation

- The app and test bundle compile for iPhone 18 Pro / iOS 27.0 Simulator.
- All 36 pre-existing tests remain green.
- Twenty-three deterministic Phase 4 tests cover state transitions, invalid operations, manual ticks, partial/stale/missing readings, five-point batching, all tail sizes, order/deduplication, stop adjacency, finalization, incomplete failure, cascade deletion, shared sensor leases, and Wi-Fi omission.
- The requested Simulator golden flow creates `录制测试区`, records `前台测试轨迹` for several real foreground ticks, verifies the count and timestamps, stops, opens detail, and deletes the Track. Simulator sensor values are allowed to be absent and are never injected.

## Known limitations and Phase 5+ deferrals

- Foreground timers pause when the process is suspended; no background continuity is promised.
- Simulator execution does not validate real pressure, magnetic axes, heading, or indoor location accuracy.
- A process termination can lose an unflushed in-memory tail of at most four points; already committed batches and the incomplete Track remain. Relaunch reconciliation is future work.
- Phase 5 should begin with tags and camera/photo file ownership, using the active coordinator's fresh optional sensor context without weakening the Phase 4 state and persistence boundaries.
- Background-location design and physical-device lifecycle testing require a separate explicit review before any capability or Always-authorization change.
