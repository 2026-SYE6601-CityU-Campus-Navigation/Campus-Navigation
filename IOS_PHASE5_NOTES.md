# RoomMarker iOS Phase 5 Notes

## Scope delivered

Phase 5 adds TrackTag capture, native new-photo capture, app-owned JPEG storage, TrackPhoto persistence, Track Detail media sections, and coordinated cleanup. These actions are available only while the existing single foreground recording session is active. The phase adds no background mode, Always location authorization, nearby Wi-Fi collection, Photo Library access, network service, analytics, ZIP/share export, route planning, or AI feature.

## TrackTag architecture and exact values

`RecordingCoordinator.addTag` requires the coordinator to be in its existing `.recording` state with the matching unfinished `activeTrack`. It creates no sensor manager, track, coordinator, or ticker. `TrackMediaPersisting` keeps metadata writes replaceable in tests, while `SwiftDataRecordingStore` supplies the production implementation.

`TrackTagType` continues to store the six exact HarmonyOS-compatible raw strings, in this order:

- `厕所`
- `楼梯`
- `门`
- `门禁`
- `电梯`
- `教室`

Notes are optional in product terms and represented by a trimmed string; an empty string means no note. `timeMs` and `createdAt` use integer Unix epoch milliseconds. The active Track relationship is mandatory for the creation path.

## Tag and photo sensor metadata

`TrackCaptureMetadataAssembler` reuses Phase 4's `SampleAssembler`, which reads the shared `SensorHub` state and accepts only `.available`, finite values under the established freshness rules. Tags and photos can therefore retain latitude, longitude, altitude, and heading when usable. Waiting, stale, unsupported, unavailable, denied, restricted, non-finite, or otherwise invalid values become nil, never zero.

Capture is immediate and bounded: it reads the current state once and does not wait for GPS or restart sensors. A completely metadata-free tag or photo remains valid. Pressure and magnetic axes are not part of the existing cross-platform TrackTag/TrackPhoto contract and are not added.

## Camera abstraction and permission behavior

`CameraServicing` abstracts authorization and camera availability. `SystemCameraService` maps AVFoundation states to not determined, authorized, denied, or restricted, requests video authorization only after Take Photo, and checks whether the native camera source exists. Deterministic fakes replace this service in tests.

`CameraCaptureView` is a small `UIImagePickerController` bridge using the system camera only. Outcomes explicitly distinguish success, cancellation, unavailability, and failure. Cancellation, denial, restriction, unavailable hardware, and capture failure create neither a file nor TrackPhoto metadata. The generated Info.plist contains only the added `NSCameraUsageDescription`: “RoomMarker 使用相机拍摄并保存轨迹现场照片。” No Photo Library permission is present, and captured images are not saved to Apple Photos.

## Photo ownership and storage paths

`LocalPhotoFileStore` owns durable media under:

```text
Application Support/RoomMarker/photos/{lowercase-track-uuid}/{timeMs}-{random-uuid}.jpg
```

Only the relative `photos/...` portion is stored in `TrackPhoto.filePath`. The current application-container absolute path is never persisted or shown. Directories are created as required; filenames combine the action timestamp with a UUID for collision resistance; data is written with Foundation's atomic option.

Every read and delete validates a non-absolute, slash-separated path rooted under `photos`, rejects empty, dot, dot-dot, and backslash components, standardizes the path, and checks resolved symlinks against the owned photo root. Track-directory deletion constructs its target from the Track UUID rather than accepting an arbitrary path. Tests inject unique temporary roots and never touch production storage.

## JPEG strategy and orientation

The UIKit camera returns a `UIImage`. Before encoding, RoomMarker redraws non-up-oriented images into an up-oriented render context so the stored pixel data has a consistent display orientation. JPEG compression quality is `0.82`, chosen as a student-project balance between readable documentation photos and storage size. The original pixel dimensions are retained; the app does not keep an uncompressed durable copy.

This implementation compiles and its deterministic data paths are tested, but actual camera orientation, quality, memory use, and file size still require physical-iPhone validation. Thumbnails currently decode the saved JPEG and let SwiftUI scale it; downsampled thumbnail generation is a future optimization for large media sets.

## Database/file consistency and orphan cleanup

The save order is intentionally file first, metadata second:

1. Camera success returns in-memory JPEG bytes; no durable object exists yet.
2. `LocalPhotoFileStore` atomically writes the owned file.
3. `SwiftDataRecordingStore` inserts and saves TrackPhoto metadata.
4. If metadata persistence fails, the coordinator attempts to delete the just-written file and rethrows the original error.

This produces the requested outcomes: capture failure creates nothing; write failure creates no metadata; successful write plus metadata save creates one association. A cleanup failure after a metadata failure can still leave an orphan because SwiftData and the filesystem cannot share a transaction. The failed operation remains reported; automatic launch-time orphan reconciliation is deferred.

## Individual deletion and Track cleanup

Deleting a TrackTag removes only its SwiftData metadata. Deleting a TrackPhoto first commits metadata deletion and then removes its validated owned file. The operation is reported as successful only if both steps complete. If the second step fails, metadata is already gone and an orphan file can remain; this unavoidable split-store edge case is documented rather than hidden.

Track deletion retains the Phase 4 SwiftData cascade for points, tags, and photo metadata, then removes the constructed `photos/{track-uuid}` directory. A successful Track deletion therefore leaves no owned directory or photo files. If directory cleanup fails after the database commit, the Track remains deleted and the error is surfaced; later orphan reconciliation remains deferred. Active Tracks still cannot be deleted.

## Active recording integration

The root recording banner now offers Add Tag, Take Photo, and Stop while the one existing coordinator is recording. Neither media action starts a second session, starts a second ticker, requests a second sensor lease, restarts sampling, synthesizes catch-up points, or intentionally pauses recording. Unit tests interleave tag/photo actions with seven manual ticks and retain the original five-plus-two persistence batches.

The native camera can change application lifecycle state. Phase 5 remains explicitly foreground-only: iOS may pause the nominal timer while camera/system UI is presented. RoomMarker stores only ticks actually delivered, with their real timestamps, and makes no claim of guaranteed continuous sampling around camera presentation.

## Track Detail integration

Track Detail now shows relationship-derived counts and chronological sections for tags and photos. Tag rows show raw type, optional note, timestamp, and only the location, altitude, or heading values that exist. Photo rows show a thumbnail plus the same available metadata, with a larger preview on tap.

`PhotoContentLoader` distinguishes readable, missing, and corrupt image files. Missing or corrupt media shows an explicit placeholder while retaining visible metadata; the UI never crashes or generates a replacement. Swipe actions use confirmation before deleting individual tags or photos.

## Simulator and automated validation

Phase 5 adds 27 deterministic Swift Testing cases using fake camera state, fake sensors, fake recording/media stores, fake file failure behavior, manual ticks, SwiftData in-memory stores, and temporary directories. They cover active/no-active tag creation, all raw values, complete/partial/absent metadata, path safety and uniqueness, capture/write/metadata failures, cleanup, cascades, missing/corrupt files, recording continuity, and batch semantics.

Together with the existing 59 tests, all 86 tests pass on the iPhone 18 Pro / iOS 27.0 Simulator. The Simulator may expose no usable camera; the manual flow treats a clear unavailable response and zero photo metadata as the correct result. No bundled or generated image is injected into production to simulate capture success.

## Manual Simulator golden flow and cleanup

The final manual flow used the synthetic Area `媒体测试区` and Track `标签照片测试轨迹`. One representative recording finished with 70 TrackPoints and one `门` tag whose note was `测试门`. The point count continued from 32 before the media interaction to 63 after opening and cancelling the system camera, then to 70 at Stop, confirming that tag/camera actions did not create a second Track or recording session.

The Simulator displayed the real camera permission prompt and native camera UI, but supplied no usable camera frame; cancelling produced no JPEG and no TrackPhoto metadata. This is the expected degraded Simulator outcome and is not evidence of physical-device capture success.

Two same-named synthetic Tracks created during manual validation were then deleted through the product UI after explicit confirmation. The Tracks screen returned to its empty state. A read-only SQLite check found zero rows in `ZTRACK`, `ZTRACKPOINT`, `ZTRACKTAG`, and `ZTRACKPHOTO`, and zero orphan child rows. The app-owned `Application Support/RoomMarker/photos` root had zero descendants and zero disk usage, so no per-Track directory or owned photo file remained. The synthetic Area was intentionally retained because cleanup scope was limited to Tracks and their owned data.

## Physical-iPhone validation still required

A supported physical iPhone is still required to validate:

- clean-install camera authorization, denial, restriction, and Settings recovery;
- actual system camera capture and cancellation;
- front/back-camera behavior if the product later exposes a choice;
- JPEG orientation in portrait and supported alternate orientations;
- `0.82` quality, representative file sizes, and memory pressure;
- timer and sensor delivery during camera lifecycle transitions;
- freshness and meaning of location/altitude/heading around real capture time.

No physical-camera result is claimed by this phase.

## Phase 6+ deferrals

Phase 6 should start with immutable, chronologically sorted Track-detail/export snapshots and explicit photo-path validation before JSON or archive writing. Final iOS v2 JSON, ZIP creation, Share Sheet/file export, path visualization, and downstream compatibility checks remain unimplemented. Background location, Always authorization, background recovery, nearby Wi-Fi scanning, route planning, campus maps, network upload, RAG, and AI features also remain outside Phase 5.
