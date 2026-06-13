# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview

BtnQ is a macOS menu-bar-only app that controls a BenQ monitor over DDC/CI.
There is no settings window — the entire UI is the `NSStatusItem` menu, built
generically from a JSON monitor config. The design goal is a tiny, native
alternative to BenQ's Display Pilot 2.

## Build / Run

```bash
xcodebuild -project BtnQ.xcodeproj -scheme BtnQ -configuration Debug build
open BtnQ.xcodeproj
```

The app is a menu-bar agent (`INFOPLIST_KEY_LSUIElement = YES`); on launch it
adds an icon to the menu bar and has no dock icon or window.

## Architecture

```
BtnQApp.swift            @main + AppDelegate: NSStatusItem, builds the NSMenu
                         generically from the active display's config
MonitorConfig.swift      Codable models for Monitors/*.json + the loader
                         (bundle + ~/Library/Application Support/BtnQ/Monitors)
DisplayController.swift  One matched display: DDC service, config, value cache.
                         All DDC I/O on a private serial queue; cache is @MainActor
SliderMenuItemView.swift Custom NSView (NSMenuItem.view) for `range` controls
DDCProbe.swift           Candidate VCP codes for Listen mode (discovery)
DDCListener.swift        Polls codes / snapshot-diff, decodes changes for Listen mode
ListenWindowController.swift  Listen-mode logging window
AppleSiliconDDC.swift    Vendored DDC transport (MIT, github.com/waydabber/AppleSiliconDDC)
AppleSiliconDDCBridge.swift  @_silgen_name decls for private CoreDisplay/IOKit symbols
Monitors/BenQ-RD280UG.json   The monitor spec (community can add more)
```

Data flow: configs load → `CGGetOnlineDisplayList` + `AppleSiliconDDC.getServiceMatches`
match displays to configs by product name → a `DisplayController` per match →
menu rendered from `config.controls`, values from the controller's cache.

## Key facts / gotchas

- **Not sandboxed** (`ENABLE_APP_SANDBOX = NO`): DDC needs raw IOKit; the sandbox
  blocks it. Don't re-enable the sandbox.
- **CoreDisplay link**: `OTHER_LDFLAGS = -framework CoreDisplay` resolves the
  private `IOAVService*` / `CoreDisplay_DisplayCreateInfoDictionary` symbols
  declared via `@_silgen_name`. Without it the app fails to launch.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`**: the Xcode template defaulted
  to `MainActor`, which would force the DDC transport onto the main thread. UI
  classes (`AppDelegate`, the views) are explicitly `@MainActor`.
- **Apple Silicon only** — the transport is `IOAVService`-based.
- **`FileSystemSynchronizedRootGroup`**: any file added under `BtnQ/` is picked
  up by the target automatically. No need to edit `project.pbxproj` to add
  sources or the `Monitors/*.json` resources.
- **16-bit multiplexed registers**: `channel` in the config → BtnQ writes
  `(channel << 8) | value` (Moon Halo's `d9`). See `DisplayController.performWrite`.
- **noRead controls** (e.g. Moon Halo on/off) can't be read back; their last-set
  value is persisted in `UserDefaults` (`btnq.state.<displayID>.<vcp>/<channel>`).

## Adding monitors

No code — see `README.md`. Configs are JSON; values are decimal as numbers, hex
as strings; `vcp` is always hex.

## References

- DDC/VCP map ported from https://github.com/iurev/bebenqli
- DDC transport from https://github.com/waydabber/AppleSiliconDDC
- BenQ Display Pilot 2 screenshots (feature parity reference): `~/Downloads/2026-06-13/Display Pilot 2`
