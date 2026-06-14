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

## Monitor compatibility — please read

> [!IMPORTANT]
> **Sundial has only been tested on one monitor: a Gigabyte M27Q.** Your mileage will vary.

Sundial controls brightness and contrast over **DDC/CI** (a VESA standard), driven through the BetterDisplay CLI. In principle that means it should work on most external monitors made in the last decade — but DDC support is uneven in practice, so there's no guarantee it works on yours. Common reasons it might not:

- **DDC/CI is disabled** in the monitor's on-screen menu (it often ships off — look for a "DDC/CI" setting and enable it).
- **The monitor ignores or mishandles the standard VCP codes** for brightness (`0x10`) / contrast (`0x12`) — some panels accept writes but don't honor them, or report wrong values on read.
- **DDC over HDMI on Apple Silicon** is hit or miss depending on the display and cable. It can work (the M27Q does over HDMI on an M-series Mac) — but plenty of displays don't. DisplayPort / USB-C tends to be more reliable.
- **Built-in laptop displays and most Apple displays** don't use DDC at all, so Sundial can't drive them.

Because of this, Sundial **won't let you create presets until it has verified it can actually read your monitor over DDC**. On first launch it shows a setup screen: enter your BetterDisplay path and display name, hit **Test connection**, and presets unlock only if the read succeeds. If the test fails, the error explains the likely cause. If it works for a monitor not listed here, a note (or PR) is welcome.

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

1. Click the sun icon in the menu bar — Sundial opens to a **setup screen**.
2. Confirm the **BetterDisplay path** (default: `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`) and enter your **display name** — any partial match of the monitor name shown in BetterDisplay.
3. Hit **Test connection**. If Sundial can read your monitor over DDC, presets unlock; otherwise the error tells you what to check (see [Monitor compatibility](#monitor-compatibility--please-read)).
4. Edit the presets and schedule to taste. Sundial takes over from there. You can revisit the path/name later via the **gear** icon.

## How it works

| Setting     | Driven by                                                        |
| ----------- | --------------------------------------------------------------- |
| Brightness  | BetterDisplay CLI → DDC VCP `0x10` (real backlight)             |
| Contrast    | BetterDisplay CLI → DDC VCP `0x12`                              |
| Night Shift | macOS Night Shift (CoreBrightness)                              |

The scheduler picks the active preset for the current time and interpolates between presets for smooth transitions. On wake, it forces a full re-apply so the display state always matches the schedule.
