# RoomMarker iOS Phase 9 Device Acceptance

## Acceptance status

Phase 9 physical-device acceptance was completed on 26 September 2026 (Asia/Hong Kong) with an iPhone 15 Pro running iOS 26.7. The app was built with Xcode 27.0 and the iOS 27 SDK, installed as a Debug build, and exercised with real location, motion, pressure, camera, foreground, Home-background, and lock-screen behavior.

Three reproducible physical-device defects were found and corrected before acceptance continued: missing modern launch-screen configuration, missing Motion usage disclosure, and false rejection of a valid export staging path caused by `/var` versus `/private/var` canonicalization. Each correction remained narrowly scoped and the full automated suite passed afterward.

The test data was disposable and was cleaned up where the procedure required it. Three completed Tracks were intentionally retained for review. No device identifier, serial number, Apple ID, signing identity, or provisioning secret is recorded here.

## Repository and build baseline

- Branch: `iOS-Application`
- HEAD before the uncommitted Phase 9 corrections: `dcaab63 feat(ios): add room and marker sensor capture parity`
- Local branch and `origin/iOS-Application`: synchronized (`0` ahead, `0` behind)
- Xcode: 27.0 (`27A266a`)
- Physical target: iPhone 15 Pro / iOS 26.7
- Simulator regression target: iPhone 18 Pro / iOS 27.0
- Final full automated suite: 203 tests in 11 suites passed; 0 failures and 0 skipped
- The local physical signing override was supplied only to the build/install invocation and was not written to the project.
- No commit, push, merge, rebase, reset, or branch switch was performed during acceptance.

## Static authorization and background configuration

- `NSLocationWhenInUseUsageDescription` remains present; no Always-location purpose string or request was added.
- `UIBackgroundModes` remains limited to `location`.
- `NSCameraUsageDescription` remains present and no Photo Library permission is requested.
- `NSMotionUsageDescription` was added after the physical device proved that iOS 26.7 enforces the disclosure for this sensor entry point.
- `UILaunchScreen` was added as an empty dictionary to the custom Info.plist. No launch storyboard, legacy launch image, hard-coded device size, status-bar manipulation, window-frame manipulation, or safe-area offset was introduced.

## Physical launch and layout

The initial physical install launched but was rendered in a legacy-sized region with a black unused band at the top. The custom Info.plist had no modern launch-screen declaration. Adding the native `UILaunchScreen` declaration and reinstalling after deleting the cached app corrected full-screen sizing on the iPhone 15 Pro. The navigation title/status-bar region and bottom safe area then rendered normally. The iPhone 18 Pro Simulator also launched without a layout regression.

## Room reference snapshot

In `真机测试区` / `真机房间`, two real Room reference captures completed after the legitimate permission prompts. The second capture replaced the first rather than appending a second baseline. After relaunch, the second capture's persisted optional sensor values remained visible and unchanged. No Wi-Fi fingerprint values were created.

## Marker sensor snapshot

Marker `真机门` of type `前门` was created through `采集并保存` during real device movement. Its physical sensor summary was recorded. The Marker was then edited to `真机门已编辑` / `后门` without another capture. Name and type changed, while every stored sensor field remained equal to the original capture. Editing did not silently recapture or clear unavailable fields.

## Live Sensors and Sensor Snapshot

The Live Sensors entry point remained stable while the phone was moved and rotated. Real pressure and magnetic-axis values changed, and device heading/location were shown only when available. The bounded Sensor Snapshot action completed and displayed a successful collection state without creating fake readings.

The first physical Core Motion launch exposed a missing Motion usage disclosure and produced TCC termination reports. Adding `NSMotionUsageDescription` fixed the crash. No new crash report appeared in subsequent Live Sensors, snapshot, Track, camera, export, cleanup, denial, or force-quit testing.

## Foreground Track result

Two completed foreground Tracks remain in `真机测试区`:

- Start 1:54:03 AM, end 1:54:22 AM: 17 persisted points.
- Start 1:58:15 AM, end 1:59:47 AM: 88 persisted points.

The accepted retest stayed in one active session, showed increasing elapsed time and sample count, stopped cleanly, flushed its final tail, and reopened in Track Detail. The exported accepted Track duration is 92.028 seconds. Its point timestamps are strictly increasing and unique; adjacent intervals are 1002–1077 ms. Physical location, altitude, accuracy, pressure, heading, and magnetic X/Y/Z values were plausible and optional rather than fabricated.

## Home-background recording result

`真机后台轨迹` started at 2:06:38 AM, continued through an approximately 30-second Home-screen interval, returned to the same active banner, and stopped at 2:10:25 AM with 220 persisted points. No duplicate Track or second recording session appeared.

The exported duration is 227.430 seconds. Every timestamp is strictly increasing and unique; adjacent intervals are 1001–1089 ms. This run continued receiving real sampling opportunities rather than exhibiting a suspension-sized gap. There is no compressed burst, duplicate timestamp, fabricated historical point, or one-second catch-up sequence after foreground return.

## Lock-screen recording result

`真机锁屏轨迹` started at 2:20:26 AM. The phone was locked for approximately 60 seconds and moved during part of that interval. The user observed the location-use indicator. After unlock, the same recording session was active, continued sampling, accepted a tag and a real camera photo, then stopped at 2:29:00 AM with 498 persisted points.

The exported duration is 514.920 seconds. Timestamps are strictly increasing and unique; adjacent intervals are 1000–1100 ms. The physical run therefore continued with normal scheduling jitter and did not produce a suspension-sized gap or synthetic catch-up burst.

## Background lease and lifecycle result

Foreground, Home-background, lock-screen, camera presentation, tag creation, photo-note presentation, and return to the app all retained one logical active recording session. Stop removed the banner and ended user-started background ownership. Idle UI showed no recording banner. The app does not claim exact one-second background scheduling or force-quit survival.

## Camera and tag result

While `真机锁屏轨迹` was active:

- Tag type `门` with note `真机测试门` was saved once. Exported metadata contains the real event timestamp and the location, altitude, and heading that were available at that moment.
- A real camera image with note `真机照片` was saved once. Recording continued across camera and note presentation.
- Track Detail showed one tag and one photo. The thumbnail, metadata row, and larger preview were readable and correctly oriented.
- The JPEG was 2,165,296 bytes, baseline JPEG/JFIF with EXIF orientation `upper-left`, and 3024×4032 pixels.
- The image remained in RoomMarker-owned Application Support storage. RoomMarker has no Photo Library permission or write path; the Photos app itself was not separately inspected during this run.

## ZIP, Share Sheet, Files, and archive result

The first physical export failed before the Share Sheet with `导出暂存路径不安全`. DEBUG-only diagnostics isolated the exact rejection to the not-yet-created `manifest.json` destination. The existing staging directory canonicalized through `/var/...`, while the candidate manifest retained the equivalent `/private/var/...` spelling. The previous string-prefix comparison therefore rejected a legitimate child.

The fix introduced one reusable canonical containment implementation. It resolves the nearest existing ancestor, resolves symlinks with the same semantics for root and child, appends validated nonexistent components, compares path components, and requires a strict descendant. Staging, ZIP source validation, owned temporary cleanup, and photo storage now share these semantics. Absolute paths, empty/dot components, `..`, backslashes, sibling-prefix paths, and symlink escapes remain rejected. Path validation was not disabled.

The physical retest reached a Share Sheet offering exactly one 2.5 MB ZIP and no staging directory. Saving to Files succeeded. The exact saved archive was then copied unchanged to the Mac and inspected:

- Archive size: 2,478,449 bytes
- Archive SHA-256: `296753bc66d280cb2523ff42c8859236688cd7e7cc0eb28d8a8a9e4a04401f64`
- Six unique CRC-valid entries: `manifest.json`, four `tracks/*.json` files, and one relative `photos/.../*.jpg` file
- No absolute entry, traversal component, duplicate entry, sandbox path, staging path, or staging-parent leakage
- Manifest `version: 2`, `sourcePlatform: ios`, `trackCount: 4`, and `nearbyWifiFingerprint: unsupported`
- Manifest references exactly the four Track files; names, `startedAt`, and point counts match each file
- Exact Track point counts: 17, 88, 220, and 498
- All point timestamps are ordered and unique
- The `门` / `真机测试门` tag and `真机照片` metadata are present in the lock-screen Track
- No BSSID, RSSI, `wifiCount`, `wifiTop`, or fabricated Wi-Fi observation is present
- The exported JPEG is readable and has the same dimensions and orientation as the source
- Exported and app-owned JPEGs are byte-for-byte identical with SHA-256 `6eb3a48d9052bec08e7102a774100df507a0b27fdd0dfea042212c656444f495`
- The source Track and source JPEG remained present after export; export did not mutate SwiftData or move, overwrite, or delete the source image
- After Share Sheet completion, the owned staging and archive directories were empty

## Photo and Track cleanup result

The individual photo deletion test used only `真机照片`. After `删除照片及文件`, Track Detail showed 498 points, one tag, and zero photos. The JPEG disappeared from app-owned storage while the tag and Track remained. The empty per-Track directory remained until Track deletion, as expected.

Deleting only the completed `真机锁屏轨迹` then removed it from the Track list. Its 498 points, remaining tag, already-removed photo metadata, and per-Track photo directory were cascade/coordinate-owned cleanup targets. The other Tracks remained with 220, 88, and 17 points, and the shared empty `photos` root remained. The externally saved ZIP stayed unchanged.

## Permission degradation result

Location permission was changed to `Never` in Settings and Live Sensors was reopened. It displayed authorization `已拒绝`, location `权限已拒绝`, an explanatory message, and one `前往系统设置` recovery action. It displayed no fake location values and did not enter a prompt loop. Other available hardware continued working, including a visible 1006.03 hPa pressure reading and live magnetometer values. No crash occurred. Permission was restored to While Using the App before the force-quit test.

## Force-quit and incomplete Track result

Disposable `真机强退测试轨迹` was started at 4:46:29 PM. Before force-quit, the list showed 73 persisted points while the live banner showed 77 logical samples; the Track continued running before the actual force-quit and ultimately retained 108 persisted points.

RoomMarker was removed through the app switcher without Stop. After normal relaunch, the Track appeared under `需要处理` with status `未完整结束` and 108 points. It had no fabricated end time, did not auto-resume, and showed no active recording banner. The app explicitly required manual finalization or deletion. No crash report was generated. The disposable incomplete Track was then deleted, leaving the three intended completed Tracks unchanged.

## Defects and corrections

1. **Legacy-sized physical layout:** custom Info.plist lacked a modern launch-screen declaration. Fixed with native `UILaunchScreen`.
2. **Physical sensor TCC termination:** Motion disclosure was missing. Fixed with `NSMotionUsageDescription`.
3. **Physical export false positive:** `/var` and `/private/var` aliases were compared using inconsistent string representations for existing versus nonexistent staging paths. Fixed with consistent canonical component containment while preserving traversal and symlink-escape defenses.

The export correction added 12 deterministic regression tests for canonical children, filesystem aliases, manifest/Track/photo destinations, sibling prefixes, traversal, absolute paths, symlink escape, nonexistent safe/unsafe children, and owned cleanup boundaries. Temporary path diagnostics were removed before the final build.

## Remaining physical-device risks

- Long-duration, poor-signal, low-power, thermal-pressure, reboot, and multi-hour background behavior were not tested.
- Reduced-accuracy location, parental/restriction authorization, camera denial, storage exhaustion, and interrupted Files destinations were not tested.
- Only one physical device/OS combination was exercised; iOS scheduling remains system-controlled.
- The ZIP writer intentionally uses stored ZIP32 entries and the current snapshot layer retains validated photo bytes in memory; unusually large field collections still need scale testing.
- The saved archive proves this dataset and path boundary, not compatibility with every downstream consumer.

## Conclusion

Phase 9 physical acceptance is complete for the stated student-project MVP scope on the tested iPhone 15 Pro / iOS 26.7. The tested launch, sensor, snapshot, marker, foreground recording, Home-background recording, lock-screen recording, camera, tag, export, Files, source immutability, cleanup, denial, and force-quit boundaries behaved coherently after the three narrow fixes. The app is suitable for the next review/commit decision, subject to the remaining risks above and the final automated regression recorded with this document.
