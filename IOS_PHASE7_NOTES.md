# iOS Phase 7 Notes

## Scope

Phase 7 adds ZIP archive creation, Area and conceptual `未分区` export UI, the native iOS Share Sheet, owned temporary-file cleanup, and end-to-end archive validation. It does not add background location, Always authorization, Wi-Fi scanning, networking, cloud upload, navigation, or AI functionality.

## ZIP implementation choice

Foundation and the iOS 17 SDK do not expose a general public API that writes a multi-file ZIP container. The `Compression` framework provides codecs, not the ZIP container format. Shelling out is unavailable and inappropriate inside the iOS sandbox. To avoid a large package for this small contract, RoomMarker uses a reviewed, isolated ZIP32 `STORED` writer with UTF-8 names and CRC32.

The implementation follows the architectural decision already recorded before Phase 1. No external dependency was added.

## Archive layout and ordering

The ZIP root contains only:

```text
manifest.json
tracks/{lowercase-track-uuid}.json
photos/{lowercase-track-uuid}/{image}.jpg
```

Entries are supplied explicitly rather than discovered through directory enumeration. Their logical order is deterministic:

1. `manifest.json`
2. Track JSON files in the Phase 6 snapshot order
3. Photos in Track order and the Phase 6 photo order

ZIP headers use a fixed valid DOS timestamp. Unchanged input therefore currently produces stable ordering and content; consumers should rely on logical content and ordering rather than byte identity as a long-term contract.

## Archive path safety

Every source URL must resolve below the validated Phase 6 staging session. Entry names must be non-empty relative paths using forward slashes. Absolute paths, backslashes, empty components, `.` and `..` are rejected. Session parent folders, sandbox paths, hidden filesystem metadata, DerivedData, and unrelated files are never enumerated or included.

## Output filename rules

Archives use:

```text
RoomMarker-{sanitized-area}-{UTC-yyyyMMdd-HHmmss}-{session-prefix}.zip
```

Area names retain letters and numbers, including Chinese characters, plus hyphen and underscore. Other characters become separators, names are bounded, and an empty result becomes `未分区`. A numeric suffix resolves an unexpected collision without overwriting an existing archive. Formatting uses Gregorian `en_US_POSIX` and UTC rather than the user locale.

## Export state machine

`AreaExportCoordinator` owns the explicit states:

- `idle`
- `preparingSnapshot`
- `staging`
- `archiving`
- `readyToShare`
- `failed`

The busy states reject duplicate starts. The coordinator builds exactly one immutable Phase 6 snapshot, stages that value, archives the validated staging result, and never returns to live SwiftData relationships during ZIP creation.

## Share Sheet integration

Area Detail and conceptual `未分区` both contain a compact export section. It shows the selected scope and plain-language progress rather than invented percentage precision. A successful export presents `UIActivityViewController` through a small SwiftUI bridge. Its activity payload contains exactly one item: the final ZIP URL. The staging directory is never shared, and no upload or network action occurs automatically.

Simulator share targets differ from a physical device. AirDrop and physical-device Files behavior are not claimed as validated by simulator tests.

## Lifetime and cleanup

RoomMarker owns only these temporary locations:

```text
tmp/RoomMarkerExports/staging/
tmp/RoomMarkerExports/archives/
```

Staging is removed immediately after successful archiving and after failures. The archive remains while the Share Sheet is presented, then is removed when sharing completes or is cancelled and the sheet dismisses. Starting a new export or leaving the screen without an active Share Sheet cleans the previous session. Cleanup is idempotent where practical.

At app launch, stale children under the dedicated `RoomMarkerExports` root are removed. Cleanup never targets Application Support, SwiftData, permanent `TrackPhoto` storage, or arbitrary temporary siblings.

## Failure behavior and user messages

ZIP creation writes to a `.partial` file and only moves it to the final `.zip` name after the central directory and end record are complete. Failure removes partial and misleading final output. The coordinator also cleans staging while preserving original source files and SwiftData.

Phase 6 errors are mapped to concise messages for missing, unsafe, unreadable, or corrupt photos. Archive errors are typed for unsafe paths, sources outside staging, missing or oversized input, ZIP32 entry limits, and output failures. Internal stack traces are not shown to users.

## Memory and streaming behavior

The writer uses two sequential passes per source file: one bounded-buffer pass calculates CRC32 and size, then a second bounded-buffer pass copies bytes into the archive. The default chunk is 64 KiB. It does not assemble the full archive or full photo collection into one `Data` value.

Phase 6 snapshots currently retain validated photo bytes in memory by design. Phase 7 does not add another archive-sized buffer, but very large photo collections may still be bounded by the existing snapshot design. The current writer implements ZIP32 `STORED`, so an individual file and archive offsets are limited to 4 GiB and entry count to 65,535. Those limits are well above the intended MVP collection size; ZIP64 would require a later reviewed change.

## Validation and next boundary

Automated tests inspect ZIP local entries directly without installed desktop commands. They decode the manifest and Track JSON, compare photo bytes, verify capability metadata and absent Wi-Fi observations, exercise cleanup/failure behavior, and prove model/source-file preservation.

Physical-device validation remains required for real camera photos, large field exports, Files destinations, AirDrop targets, and memory/thermal behavior. A later phase may perform that acceptance work; it must not weaken the immutable snapshot, capability honesty, path validation, or cleanup boundaries.
