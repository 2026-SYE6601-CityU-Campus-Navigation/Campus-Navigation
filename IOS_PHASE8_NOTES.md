# iOS Phase 8 Notes

## Scope

Phase 8 continues a Track that the user explicitly starts in the foreground while iOS permits location delivery. It adds no autonomous monitoring, Always authorization, significant-location-change service, geofencing, Wi-Fi scanning, networking, cloud upload, route planning, or synthetic sensor data.

## Apple background API choice

RoomMarker keeps its existing `CLLocationManager` inside `CoreLocationSensorService`. While a Track is active, that manager enables `allowsBackgroundLocationUpdates`, keeps the system location indicator visible, and disables automatic pausing. A single `CLBackgroundActivitySession` expresses the user-visible, foreground-originated background activity on iOS 17 and later.

This is deliberately smaller than replacing SensorHub with `CLLocationUpdate.liveUpdates()`: the existing manager already owns authorization, accuracy, freshness, and consumer sharing. Phase 8 does not create a competing location manager.

## Authorization boundary

The app requests only When In Use authorization through its existing foreground flow. It does not request Always authorization and does not add `NSLocationAlwaysAndWhenInUseUsageDescription`. A not-determined state is shown as pending; denied and restricted states are shown honestly and do not claim successful background recording. If authorization degrades while recording, the coordinator releases the background lease when it observes that state. It does not repeatedly prompt.

Always authorization is deferred. It should be considered only if a future, explicitly approved product requirement cannot be met by a foreground-started session, with a separate privacy review and user-facing rationale.

## Background capability and ownership

The target declares only the `location` value in `UIBackgroundModes`. `CoreLocationBackgroundSession` verifies that value before setting `allowsBackgroundLocationUpdates`, preventing the documented runtime failure caused by enabling background updates without the capability.

`RecordingCoordinator`, which is owned at application scope, owns one protocol-backed logical lease. Starting one Track acquires it once. Clean stop, recording persistence failure, or failure reset releases it. Idle use never acquires it. Background delivery is therefore enabled only while a user-started Track is active.

## SensorHub interaction

Recording remains a normal SensorHub consumer. Live Sensors and Snapshot retain independent consumer leases, so stopping recording does not stop sensors still needed by another consumer, and stopping another consumer does not stop an active recording. The background session configures the same location service already used by SensorHub.

Location is the primary background service. Pressure, magnetic field, heading, and other readings are used only when the existing freshness model says they are valid. Missing or stale values remain `nil`; they are never changed to zero or copied to fabricate continuity.

## Sampling and timestamp gaps

Foreground sampling remains nominally once per second while the process executes. Background execution is not promised at an exact frequency. Every `TrackPoint` represents an actual ticker cycle and stores that cycle's real timestamp.

Suspension or delayed execution therefore appears as a real timestamp gap. RoomMarker does not generate historical catch-up points, repeat the last sample to fill time, or smooth an eight-second gap into one-second observations. Track Detail and export treat these gaps as valid because a Track is a collection of observed samples, not a fabricated uniform time series.

## Buffering and persistence

The normal five-point batch remains unchanged and there is still one pending buffer. Stop flushes the remaining tail. On transition to background, the coordinator opportunistically flushes the current tail once to reduce loss if suspension follows. This lifecycle flush does not create, duplicate, reorder, or rewrite points; subsequent samples continue through the same buffer. `pointCount` remains derived from the Track relationship.

## Lifecycle handling

The app maps active, inactive, and background scene phases into the application-scoped coordinator. Entering the background does not change an active recording to idle and returning does not start a second ticker or background session. Elapsed duration is calculated from timestamps rather than accumulated UI ticks.

The session supports only a Track explicitly started while the app is in the foreground. It does not start Tracks from background events. The system location indicator remains enabled and no private API attempts to hide it.

## Incomplete Track recovery

On launch, Tracks with `endedAt == nil` that are not the current in-memory active Track are listed as interrupted and need user attention. They are not silently resumed or marked complete. The user may explicitly finalize one; the selected recovery time is clamped so it cannot precede `startedAt`. Existing active-Track deletion protection remains in force.

Force-quit or arbitrary process termination is not a supported continuity guarantee. A process death does not manufacture a clean `endedAt`, and Phase 8 does not claim to restore an active Core Location session after force-quit.

## User transparency, privacy, and battery

Recording UI states that location may continue in the background while iOS permits it, that exact one-second delivery is not guaranteed, that gaps are retained, that battery usage may increase, and that stopping the Track stops background location ownership. Data remains local under the existing architecture; Phase 8 adds no analytics or upload.

## Validation boundary

Automated tests use fake tickers, lifecycle transitions, stores, sensor states, and background sessions. They validate ownership, failure cleanup, batching, gaps, partial sensor values, recovery, and export without pretending to reproduce device scheduling.

The iOS Simulator can validate installation, launch, UI state continuity, explicit stop, stored timestamps, Track Detail, and export compatibility. It is not proof of real background reliability.

A physical iPhone is still required to validate screen lock, Home gesture, several minutes of background duration, the system indicator, battery and thermal behavior, foreground return, camera interaction, denied permission, reduced accuracy, device motion, real sampling gaps, and phone-call or comparable interruptions.
