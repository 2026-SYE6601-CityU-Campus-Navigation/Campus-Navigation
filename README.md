# Campus Navigation / RoomMarker

RoomMarker is a cross-platform indoor-navigation data-collection application developed for the CityU Campus Navigation project.

The repository contains native implementations for both HarmonyOS and iOS. Each platform uses its own system APIs and lifecycle model while sharing the same overall goal: collecting structured indoor-navigation evidence such as Areas, Rooms, Markers, Tracks, sensor observations, tags, and photos.

## Platform implementations

### HarmonyOS

The HarmonyOS implementation includes native RoomMarker workflows for area and room management, sensor collection, track recording, photos, export, and related field-data workflows.

For the complete HarmonyOS documentation, see:

**[HARMONY_README.md](HARMONY_README.md)**

### iOS

The iOS implementation is built with Swift 6, SwiftUI, SwiftData, Core Location, Core Motion, and native iOS media/export APIs.

The accepted iOS baseline includes automated tests, simulator validation, and physical-device acceptance.

For the complete iOS documentation, architecture, validation evidence, screenshots, and usage instructions, see:

**[IOS_README.md](IOS_README.md)**

Additional iOS technical documents:

- [IOS_ARCHITECTURE.md](IOS_ARCHITECTURE.md)
- [IOS_IMPLEMENTATION_PLAN.md](IOS_IMPLEMENTATION_PLAN.md)
- [IOS_PROJECT_BRIEF.md](IOS_PROJECT_BRIEF.md)
- [IOS_PHASE9_DEVICE_ACCEPTANCE.md](IOS_PHASE9_DEVICE_ACCEPTANCE.md)

## Repository branches

- `main` — integrated project branch
- `Harmony-Application` — HarmonyOS development branch
- `iOS-Application` — iOS development branch

## Platform differences

HarmonyOS and iOS expose different hardware, permission, background-execution, Wi-Fi, camera, and file-sharing APIs. The two implementations therefore preserve shared product concepts where practical while using native platform behavior rather than forcing identical implementation details.

Refer to the platform-specific documentation above for exact behavior, capabilities, limitations, build requirements, and validation results.
