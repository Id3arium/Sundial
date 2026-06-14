# Sundial

A macOS menu bar app that schedules your monitor's brightness, contrast, and Night Shift by time of day — so your screen matches the room as it shifts from morning to night, without you ever touching a slider.

Sundial drives your monitor's **hardware** brightness and contrast over DDC (via the [BetterDisplay](https://github.com/waydabber/BetterDisplay) CLI), not a software dimming overlay — so it's the real backlight changing, the same as the buttons on the monitor itself. Night Shift warmth is driven through macOS's built-in Night Shift.

## What it does

- **Time-of-day presets** — define presets like _Morning_, _Day_, _Evening_, _Night_, each with a brightness, contrast, and Night Shift strength.
- **Scheduling** — assign a preset to a time; Sundial applies it automatically and smoothly interpolates between presets so the change is gradual, not a jarring jump.
- **Live control** — drag a slider in the menu bar to adjust the current display immediately.
- **Wake handling** — re-applies the correct preset when your Mac wakes, so the screen is right the moment you return.
- **Launch at login** — optional; lives quietly in the menu bar (no Dock icon).

Presets and schedule live in `config.json` under `~/Library/Application Support/Sundial/`.

## Requirements

- macOS 14 (Sonoma) or later
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) installed (provides the CLI Sundial uses to set hardware brightness/contrast). Hardware brightness and contrast control are free features.
- A monitor that supports DDC/CI (most external displays do)
- For building: [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode

## Build & install

```bash
./build.sh          # build, install to /Applications, and relaunch
```

`build.sh` regenerates the Xcode project from `project.yml`, builds a Release `.app`, copies it to `/Applications`, and relaunches it. Other options:

```bash
./build.sh -n       # build only, stage into ./build/Sundial.app (no install)
./build.sh -v       # verbose xcodebuild output
./build.sh --help   # usage
```

> Install via `./build.sh` (not by running a Debug build from Xcode) so launch-at-login binds the app in `/Applications` rather than a transient DerivedData path.

## First run

1. Click the sun icon in the menu bar → **Settings**.
2. Set the **BetterDisplay CLI path** (default: `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`) and the **display name** — a partial match of the monitor name shown in BetterDisplay.
3. Edit the presets and schedule to taste. Sundial takes over from there.

## How it works

| Setting     | Driven by                                                        |
| ----------- | --------------------------------------------------------------- |
| Brightness  | BetterDisplay CLI → DDC VCP `0x10` (real backlight)             |
| Contrast    | BetterDisplay CLI → DDC VCP `0x12`                              |
| Night Shift | macOS Night Shift (CoreBrightness)                              |

The scheduler picks the active preset for the current time and interpolates between presets for smooth transitions. On wake, it forces a full re-apply so the display state always matches the schedule.
