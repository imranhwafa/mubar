# MUBAR — macOS Menu Bar System Stats App

A native macOS menu bar app that lives next to the battery icon, surfaces toggleable system stats (battery, Bluetooth/headphones, disk I/O, CPU, RAM, network), and supports switchable popover materials (auto/tinted glass/frosted/solid).

## Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI with `MenuBarExtra` (macOS 13+) — `NSStatusItem` + `NSPopover` fallback path kept available for menu bar customization the SwiftUI API can't reach (e.g., custom status item view, drag/drop into the bar).
- **Min target:** macOS 13 Ventura (covers `MenuBarExtra`).
- **Build:** Xcode project, single app target. No third-party deps in v1; SPM-ready for later.
- **Persistence:** `@AppStorage` (UserDefaults) for toggles and material preference.
- **Distribution (later):** Developer ID signed `.app`, eventual notarization. Out of scope for v1.

## Architecture

```
MUBARApp (App)
└── MenuBarExtra("MUBAR", systemImage: …)
    └── PopoverRoot (SwiftUI)
        ├── HeaderBar (app name, settings gear)
        ├── StatsList (ForEach enabled stats)
        │   ├── BatteryRow
        │   ├── BluetoothRow / HeadphonesRow
        │   ├── DiskRow
        │   ├── CPURow
        │   ├── MemoryRow
        │   └── NetworkRow
        └── SettingsSheet
            ├── Toggle each stat on/off
            └── Material picker (Auto / Tinted / Frosted / Solid)

Services (ObservableObjects, injected via @EnvironmentObject)
├── BatteryService     — IOKit IOPSCopyPowerSourcesInfo
├── BluetoothService   — IOBluetooth + CoreBluetooth (device list, RSSI)
├── HeadphoneService   — AirPods/BT audio battery via IOBluetooth properties
├── DiskService        — host_statistics64 / IOKit disk stats
├── CPUService         — host_processor_info / host_statistics
├── MemoryService      — host_statistics64 (vm_statistics64)
├── NetworkService     — getifaddrs + delta sampling for up/down bytes
└── SamplerCoordinator — single Timer (1s) fanning out to enabled services
```

Each service exposes `@Published` snapshot structs. Services pause sampling when their toggle is off to save battery.

## Phases

### Phase 1 — Skeleton (1–2h)
- New Xcode project, SwiftUI app, target macOS 13.
- `MenuBarExtra` with `.window` style popover.
- Hardcoded "Hello" content; verify it appears next to battery icon.
- App is `LSUIElement = true` (no Dock icon).

### Phase 2 — Sampler + Battery (2h)
- `SamplerCoordinator` with 1s tick, weak service refs.
- `BatteryService` via `IOPSCopyPowerSourcesInfo`: percentage, charging, time-to-empty/full.
- `BatteryRow` view with icon + % + secondary line.

### Phase 3 — System stats (3–4h)
- `CPUService` — sample `host_processor_info` deltas → % busy.
- `MemoryService` — `host_statistics64(HOST_VM_INFO64)` → used / pressure.
- `DiskService` — IOKit `IOServiceGetMatchingServices("IOBlockStorageDriver")` read/write byte counters → MB/s deltas.
- `NetworkService` — `getifaddrs` byte counters per interface → up/down KB/s, prefer active interface.
- Rows for each.

### Phase 4 — Bluetooth + Headphones (3h)
- `BluetoothService` — `IOBluetoothDevice.pairedDevices()` enumeration; connected state; name/RSSI.
- `HeadphoneService` — read AirPods battery via IOBluetooth device properties (`BatteryPercentCase`, `BatteryPercentLeft`, `BatteryPercentRight`); fall back to generic BT battery characteristic for non-Apple headphones.
- Permission prompt handling (Bluetooth usage description in Info.plist).

### Phase 5 — Settings & toggles (2h)
- `SettingsSheet` accessible via gear in popover header.
- Per-stat enable toggles bound to `@AppStorage`.
- Reorder stats (drag handle, persisted order).
- Disabled services skip their sample tick.

### Phase 6 — Material switcher (1–2h)
- `MaterialMode` enum: `.auto`, `.tinted`, `.frosted`, `.solid`.
- Apply via `NSVisualEffectView` wrapped in `NSViewRepresentable` (since SwiftUI's `.background(.ultraThinMaterial)` can't fully replicate vibrancy modes inside a `MenuBarExtra` window).
- Auto = follow `NSApp.effectiveAppearance` (light/dark) and pick a sensible material.
- Live preview when changing in settings.

### Phase 7 — Polish (2h)
- Menu bar icon: SF Symbol that hints at active state (e.g., changes when on battery vs charging).
- Optional compact label next to icon (battery % or one chosen stat) — toggle in settings.
- Launch at login via `SMAppService.mainApp`.
- About panel; quit item.

### Phase 8 — Test pass (1h)
- Manual matrix: light/dark, on AC vs battery, AirPods connected/disconnected, no network, all stats off (popover should still render gracefully).
- Profile sampler CPU cost — target <1% idle.

## Key design decisions

- **One timer, many consumers.** Avoid per-service timers; coordinator fans out so disabled stats truly cost zero.
- **Snapshot structs, not live refs.** Services publish immutable snapshots — views never touch IOKit handles.
- **Material via NSVisualEffectView.** SwiftUI materials inside `MenuBarExtra` are limited; the wrapper gives true tinted/frosted/solid control and lets "auto" track appearance changes.
- **No background daemon.** Single app process; sampling only while popover open OR user opted into "always sample for menu bar label."

## Open questions / deferred

- Notarization + DMG packaging (post-v1).
- Per-app network breakdown (would need `nettop`-style sampling or system extension — out of scope).
- Custom themes / colors beyond the four materials (post-v1).
- Sparkline history charts (post-v1).

## File layout (proposed)

```
MUBAR/
├── MUBAR.xcodeproj
├── MUBAR/
│   ├── MUBARApp.swift
│   ├── Info.plist
│   ├── Views/
│   │   ├── PopoverRoot.swift
│   │   ├── Rows/{Battery,Bluetooth,Headphone,Disk,CPU,Memory,Network}Row.swift
│   │   ├── SettingsSheet.swift
│   │   └── VisualEffectBackground.swift
│   ├── Services/
│   │   ├── SamplerCoordinator.swift
│   │   ├── BatteryService.swift
│   │   ├── BluetoothService.swift
│   │   ├── HeadphoneService.swift
│   │   ├── DiskService.swift
│   │   ├── CPUService.swift
│   │   ├── MemoryService.swift
│   │   └── NetworkService.swift
│   └── Model/
│       ├── MaterialMode.swift
│       └── StatToggle.swift
└── PLAN.md
```

## Total estimate

~14–17 hours of focused work for v1.
