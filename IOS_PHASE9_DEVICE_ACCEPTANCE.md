# RoomMarker iOS Phase 9 Device Acceptance

## Acceptance status

Phase 9 physical-device acceptance is **not complete**. On 25 September 2026 (Asia/Hong Kong), Apple device tooling exposed no connected physical iPhone. The only iOS device returned by `xcrun devicectl list devices` was `iPhone 18 Pro`, explicitly classified as `simulated`; `xcrun xctrace list devices` listed the Mac under Devices and all iOS targets under Simulators.

No Simulator result in this document is presented as evidence of physical-device behavior. Hardware-dependent tests were skipped instead of fabricated.

## Repository and build baseline

- Branch: `iOS-Application`
- Starting HEAD: `3997df8 feat(ios): add background track recording lifecycle`
- After `git fetch origin`: local and `origin/iOS-Application` were synchronized (`0` ahead, `0` behind).
- Xcode project listing succeeded and exposed the `RoomMarker` and `RoomMarkerTests` targets plus the `RoomMarker` scheme.
- Debug application build succeeded for the iPhone 18 Pro / iOS 27.0 Simulator with signing disabled.
- Complete automated suite: 178 tests in 9 suites passed; 0 failures.
- One benign build warning reported that AppIntents metadata extraction was skipped because the app has no AppIntents framework dependency.

## Static authorization and background configuration

Static inspection confirmed:

- `NSLocationWhenInUseUsageDescription` is present with understandable user-facing language.
- `NSLocationAlwaysAndWhenInUseUsageDescription` is absent.
- Production code requests When In Use authorization and contains no request for Always authorization.
- `UIBackgroundModes` contains only `location`.
- The existing location manager owns `allowsBackgroundLocationUpdates` configuration.
- `CoreLocationBackgroundSession` owns the single `CLBackgroundActivitySession` abstraction and releases it through its existing lifecycle.
- Camera permission remains limited to `NSCameraUsageDescription`; no Photo Library permission is declared.

These are static and deterministic-test observations. They do not validate actual iOS scheduling, permission presentation, background delivery, or hardware behavior.

## Device and iOS environment

- Physical iPhone model: unavailable; no physical iPhone detected.
- Physical iOS version: unavailable.
- Trust state: not testable.
- Developer Mode: not testable.
- Development signing: not tested against a device.
- Physical install: not performed.
- Physical launch: not performed.
- Simulator available: iPhone 18 Pro, iOS 27.0, explicitly simulated.

No device identifiers, serial numbers, Apple IDs, signing identities, or provisioning secrets are recorded here.

## Location authorization result

Physical permission presentation and authorization-state transitions were not performed. In particular, clean-install When In Use grant, denial, restriction, reduced accuracy, Settings recovery, and repeated-prompt behavior remain unvalidated on hardware.

## Foreground sensor result

Not performed on a physical iPhone. Latitude, longitude, altitude, horizontal accuracy, heading, magnetic X/Y/Z, pressure, freshness behavior, and unavailable-state handling were not observed from real hardware. Existing deterministic tests remain passing but are not substitutes for this validation.

## Pressure result

Not performed. Physical CMAltimeter availability, live readings, plausible kPa-to-hPa behavior, and elevation response remain unvalidated. No atmospheric value was assumed or hard-coded for acceptance.

## Heading and magnetometer result

Not performed. Device rotation, normalized heading range, invalid-accuracy rejection, and changing magnetic axes remain unvalidated on hardware. The Apple/HarmonyOS coordinate-frame caveat remains applicable.

## Foreground Track result

The requested `真机测试区` / `真机前台轨迹` flow was not created because no physical iPhone was available. Thirty-second movement recording, real sample growth, batching, tail flush, stop, and Track Detail were not physically validated.

## Home-background result

Not performed. There is no observed physical background duration or sample count. Home-screen continuation, the system location indicator, real timestamp gaps, ordering, absence of catch-up points, and return-to-foreground behavior remain unvalidated.

## Lock-screen result

Not performed. Screen-lock location delivery, suspension behavior, timestamp gaps, coherent recovery, and successful Stop remain unvalidated.

## Background lease and lifecycle result

No physical lifecycle logging was collected. Deterministic tests passed for one lease on Track start, release on Stop/failure, no idle lease, no duplicate ticker after foreground return, authorization degradation, and real-gap preservation. Physical confirmation of those behaviors remains outstanding.

## Battery and thermal observation

Not performed. No battery-life or thermal claim is made, and no physical Core Location warnings were observed because no device run occurred.

## Camera and recording lifecycle result

Not performed on a physical iPhone. Real capture, the `真机照片` note, JPEG existence, relative `filePath`, orientation, approximate file size, thumbnail, preview, absence from Photos, and Track continuity around camera presentation remain unvalidated.

## Tag result

Not performed on a physical iPhone. The `门` / `真机测试门` tag flow and real fresh-or-nil sensor metadata behavior remain unvalidated.

## ZIP, Share Sheet, and archive result

Real device export was not performed. Share Sheet presentation, Files destination, exactly-one-ZIP behavior, and inspection of a device-generated archive remain unvalidated. Deterministic tests passed for ZIP structure, manifest and Track JSON, non-empty copied photo bytes, relative paths, derived point counts, tags, incomplete/complete semantics, explicit unsupported Wi-Fi capability, absence of fake Wi-Fi values, and source immutability.

## Photo and Track cleanup result

Not performed on physical-device Phase 9 data. No real device photo or Track was created, so there was no authorized disposable Phase 9 data to delete. Individual JPEG cleanup, unrelated-photo preservation, and Track-owned directory cleanup remain physically unvalidated.

## Permission degradation result

Not performed on hardware. No permission state was changed. Deterministic tests still cover denied location without claiming background success, missing background mode, pending authorization, and runtime authorization degradation.

## Force-quit and incomplete Track result

Not performed. No claim is made that recording survives force-quit. Deterministic tests continue to cover detection of `endedAt == nil`, absence of automatic false completion, and explicit recovery finalization.

## Defects and corrections

No reproducible defect was discovered by the safe static, build, or automated checks. No application code, project setting, signing configuration, or test code was changed. Speculative hardening was intentionally avoided without physical-device evidence.

## Unresolved physical-device risks

- When In Use background continuation may vary with real iOS scheduling, lock state, motion, authorization, and system policy.
- Real Core Location, heading, magnetometer, and CMAltimeter freshness and availability remain unknown.
- Camera orientation, JPEG size, memory behavior, and interaction-related sampling gaps remain unknown.
- Real Share Sheet and Files workflows, archive handoff, and source-photo immutability remain unobserved.
- Battery, thermal behavior, system location indication, force-quit boundaries, and permission recovery remain unobserved.

## Required continuation

Repeat Phase 9 with a trusted, Developer-Mode-enabled physical iPhone visible to Xcode. Begin with install/launch and clean When In Use authorization, then execute the foreground sensor/Track baseline before the Home-background, lock-screen, camera/tag, export, cleanup, degradation, and optional force-quit tests. Record actual durations, counts, timestamp gaps, file size, and observed states without overstating accuracy.
