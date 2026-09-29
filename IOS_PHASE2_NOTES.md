# RoomMarker iOS Phase 2 Notes

## Scope delivered

Phase 2 adds native SwiftUI management for Areas, Rooms, and manually entered Markers on top of the Phase 1 SwiftData foundation. The application now launches into a usable `NavigationStack` instead of the foundation placeholder.

This phase intentionally does not add production sensor services, track recording, background execution, camera/photo capture, Wi-Fi collection, or final JSON/ZIP export.

## UI structure

```text
Area list
├── Area detail
│   └── Room detail
│       └── Marker create/edit sheet
└── 未分区 rooms
    └── Room detail
        └── Marker create/edit sheet
```

SwiftUI `List`, `Section`, `NavigationStack`, toolbar buttons, sheets, swipe actions, and confirmation dialogs provide the core interaction. Empty states provide an explanation and a creation action instead of leaving a blank screen. Semantic system colours and standard controls preserve Dynamic Type, light/dark mode, and baseline accessibility behaviour.

## Area CRUD behaviour

- The home screen lists persisted Areas in creation order with derived Room and Track counts.
- A sheet creates or edits an Area name and optional note.
- Names and notes are trimmed before persistence; an empty or whitespace-only name produces visible inline feedback and is not saved.
- Area rows expose edit and delete actions.
- Deleting an Area always uses `deleteAreaPreservingContents`: Rooms and Tracks are moved to nil-area state before the Area is removed. Phase 2 provides no permanent cascade-delete option for an Area.

## Room CRUD behaviour

- An Area detail screen lists its Rooms, note, and Track count. Track recording remains a labelled, non-functional future-phase message.
- Rooms can be created from a real Area or from the 未分区 screen.
- A Room editor supports name, optional note, and reassignment to any current Area or 未分区.
- Room names and notes follow the same trim and empty-name rules as Areas.
- Room deletion requires confirmation and uses the Phase 1 cascade relationship, removing associated Markers.
- Existing Room sensor fields are displayed only when non-nil. Missing readings are described as not collected; the UI never substitutes zero.

## Marker CRUD behaviour

- Room detail lists Markers and supports manual create, edit, and confirmed delete.
- Marker type selection uses the existing `MarkerType` cases and exact HarmonyOS-compatible raw labels: `前门`, `后门`, `窗户`, `墙角`, `插座`, `自定义`.
- Manual creation persists only the trimmed name, selected type, relationship, UUID, and timestamp.
- Latitude, longitude, altitude, accuracy, pressure, and magnetic values remain nil. The editor explicitly explains that Phase 2 performs no sensor capture.

## 未分区 behaviour

未分区 is a computed UI grouping for Rooms whose `area` relationship is nil. It is never inserted as an `Area` row and has no magic UUID. The home entry appears when at least one unassigned Room exists. Users can create an unassigned Room, edit it, move it to a real Area, or move an assigned Room back to 未分区.

Deleting a real Area preserves its Rooms and Tracks by clearing their relationships. Preserved Rooms and their Markers then remain accessible through 未分区.

## Validation and errors

`Phase2DataStore` centralises trimmed-input validation and the persistence operations used by the views. It throws `Phase2ValidationError.emptyName` before any insert or update. Editor sheets display validation/save errors inline; list/detail persistence failures use an alert.

Destructive actions state their effect explicitly:

- Area deletion explains that Rooms and Tracks are preserved under 未分区.
- Room deletion explains that associated Markers are permanently deleted.
- Marker deletion requires confirmation.

## Architecture decisions

- Views use SwiftData queries and observable model relationships directly because the Phase 2 dataset and team scope are small.
- Mutations go through a compact main-actor `Phase2DataStore`, which delegates destructive Area/Room operations to `SwiftDataRepository`.
- Creation timestamps remain Unix epoch milliseconds.
- No schema migration was needed; Phase 1 already modelled all requested concepts and delete rules.
- No third-party dependency, entitlement, privacy purpose string, or background mode was added.

## Tests added

`Phase2DataStoreTests` adds ten persistence-focused tests covering:

1. Area creation and trimming;
2. Area editing;
3. empty Area-name rejection;
4. assigned Room creation;
5. unassigned Room creation without a fake Area;
6. Room Area reassignment;
7. Area deletion preserving Rooms as unassigned;
8. Marker creation and raw-value compatibility;
9. Room deletion cascading to Markers;
10. nil sensor values in Phase 2 creation flows.

Together with the 13 Phase 1 tests, 23 tests execute in three suites.

## Simulator validation

The app was built, installed, and launched on an iPhone 18 Pro simulator running iOS 27.0. The complete golden flow was performed with synthetic data:

1. created `教学楼A` with note `Phase 2 test area`;
2. created and opened Room `A101`;
3. created Marker `正门` with type `前门` and verified the UI described it as manually created with no sensor data;
4. deleted `教学楼A` using the preserve-content action;
5. verified the home screen showed `未分区` with one Room, then opened it and verified `A101` still contained the `正门` Marker;
6. deleted `A101` using the confirmation that explicitly reported one associated Marker;
7. verified the `未分区` screen returned to zero Rooms. The persistence test separately verifies that the associated Marker entity is absent after Room deletion.

## Deferred to Phase 3 and later

- Core Location and device heading;
- Core Motion accelerometer, gyroscope, attitude, and magnetometer;
- CMAltimeter pressure capture;
- one-shot Room/Marker sensor snapshots and live sensor streaming;
- production track recording and background location;
- tags, camera/photos, route or map UI;
- Wi-Fi scanning or fabricated Wi-Fi values;
- final JSON mapping, ZIP creation, sharing, or export.
