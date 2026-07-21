# HRV-CV Monitor

A macOS menu bar app that tracks your **7-day rolling HRV coefficient of
variation** from WHOOP — a measure of how *consistent* your recovery has been,
night to night. Lower is better.

The menu bar shows `CV 22%`; clicking it opens a dashboard with a zone gauge, a
nightly-HRV evidence chart, a plain-language verdict with its reasoning, your
7-night window stats, and a per-night table of WHOOP recovery + HRV.

> **What is HRV-CV?** The standard deviation of your nightly HRV over 7 days,
> divided by the mean, as a percent. Low = steady autonomic recovery; high tracks
> inconsistent sleep, stress, alcohol, or training load. Zones: **≤8% elite,
> ≤15% on track, >15% elevated.**
> ([background](https://www.whoop.com/us/en/thelocker/hrv-cv-recovery-metric/))

## Download

**[⬇ Download the latest release](https://github.com/geoffbrown/HRV-CV-Monitor/releases/latest)** —
open the `.dmg` and drag **HRV-CV Monitor** onto the **Applications** folder.

The app isn't signed with an Apple Developer ID (it's free and shared among
friends), so the first time you open it macOS says it's from an *unidentified
developer*. Clear that once, either way:

- **Right-click** the app in Applications → **Open** → **Open** in the dialog, or
- run this in Terminal (copy-paste, press Return):

  ```sh
  xattr -dr com.apple.quarantine "/Applications/HRV-CV Monitor.app"
  ```

Then launch it normally. HRV-CV Monitor lives in your **menu bar** — there's no
Dock icon. Click the `CV …%` readout to open the dashboard; on first run it asks
you to connect your WHOOP account, and that's it.

## Reading the gauge

The arc is a neutral ruler from 0 to 30%, with tick breaks at **8** and **15**
(numerals just inside the ring) and a neutral fill showing how far along it you
are. The legend beneath names the segments: Elite ≤8, On Track 8–15,
Elevated >15, with the one you're in emphasized. The scale and fill are
deliberately not color-coded, because HRV-CV is not good or bad on its own.

Color carries the *verdict* only — the knob ring, the number, and the label
share one hue that is the app's interpretation: a rising CV with a **rising**
HRV baseline is "leveling up" (green — you're adapting to a higher level),
while the same CV with a **falling** baseline is "destabilizing" (coral — a
warning). The SIGNALS block in the verdict card shows the reasoning behind
the call.

## Requirements

- macOS (Apple Silicon or Intel) or iOS 16+, Xcode 16+
- A WHOOP account and a WHOOP developer app

The project is a single multiplatform Xcode target: the same app builds and
runs as a macOS menu bar app or an iPhone app depending on the destination you
pick in Xcode, sharing the WHOOP auth/networking and HRV-CV logic via the
local `HRVCVCore` Swift package.

## Setup

1. **Register a WHOOP developer app** at <https://developer.whoop.com>:
   - **Redirect URI:** `hrvcv://callback`
   - **Scopes:** `read:recovery read:sleep offline`
   - Note the **Client ID** and reveal the **Client Secret**.
   - Already had an app registered before `read:sleep` existed here? Update
     its scopes in the WHOOP dashboard, then **sign out and reconnect WHOOP**
     in the app — an existing sign-in's token won't retroactively pick up the
     new scope, so the sleep consistency signal just stays hidden until you do.

2. **Add your credentials** (kept out of git):
   ```sh
   cp HRVCVCore/Sources/HRVCVCore/Secrets.swift.example HRVCVCore/Sources/HRVCVCore/Secrets.swift
   # then paste your Client ID and Client Secret into that new Secrets.swift
   ```
   `Secrets.swift` is git-ignored, so your credentials never land in the repo.
   Both the macOS and iOS builds read from this one file.

3. **Open, sign, and run** in Xcode:
   - Open `HRV-CV Monitor.xcodeproj`
   - Target → **Signing & Capabilities** → pick your **Team** (a free Apple ID
     works). A stable signing identity keeps macOS from re-prompting for keychain
     access on every rebuild.
   - Pick a destination — **My Mac** for the menu bar app, or an iPhone/
     Simulator for the iOS app — and **Run** (⌘R).
   - On macOS: find the heart / `CV …%` item in the menu bar and click
     **Connect WHOOP**. On iOS: tap **Connect WHOOP** on the sign-in screen.

Optional (macOS only): the ⋯ menu in the panel has a **Launch at Login** toggle.

### Demo mode (no WHOOP account needed)

```sh
HRVCV_MOCK=1 "/path/to/HRV-CV Monitor.app/Contents/MacOS/HRV-CV Monitor"
```

Runs the app on a built-in sample dataset — useful for trying the UI before
connecting, or for development without burning API calls.

## Architecture

| File | Role |
|------|------|
| `HRV-CV Monitor/HRVCVApp.swift` | App entry point: `MenuBarExtra` + menu bar label (`CV n%`) on macOS, a plain `WindowGroup` on iOS |
| `HRV-CV Monitor/ContentView.swift` | Dashboard UI: gauge, zone legend, evidence chart, verdict card, stats, table (shared, with `#if os(macOS)`/`#if os(iOS)` for platform-only bits) |
| `HRV-CV Monitor/Snapshot.swift` | Headless snapshot hook (dev, macOS-only): `HRVCV_SNAPSHOT=/path.png` renders the popover to a PNG |
| `HRVCVCore/` | Local Swift package shared by macOS + iOS: `HRVCalculator` (7-night mean/SD/CV, tiers, verdict), `WHOOPService`/`TokenStore` (OAuth + Keychain + WHOOP v2 API), `MockData` (demo dataset), tier colors |
| `HRVCVCore/Sources/HRVCVCore/Secrets.swift` | Your WHOOP client ID + secret (git-ignored; see `Secrets.swift.example` in the same folder) |
| `broker/` | Optional serverless token broker for sharing (see below) |

- **Auth:** Authorization Code + PKCE, presented in an in-app `ASWebAuthenticationSession`
  sheet. Tokens live in the Keychain (one item), auto-refreshed before expiry.
  `WHOOPService.presentationAnchorProvider` is wired up per-platform (mac key
  window vs. iOS window scene) so the shared package never imports AppKit/UIKit.
- **Data:** WHOOP API **v2** `GET /recovery` (max `limit` 25), deduped to one
  record per calendar day. Refreshes hourly, on wake from sleep (macOS), and
  when the panel opens with data older than 15 minutes.
- **Menu-bar only on macOS:** `LSUIElement` is scoped to the macOS SDK, so
  there's no Dock icon there; quit from the panel (⋯ menu or ⌘Q). The iOS
  build is a normal foreground app (no such menu-bar concept).

### Developer notes

- CLI builds: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild
  -scheme "HRV-CV Monitor" build` (add `CODE_SIGNING_ALLOWED=NO` for a
  compile-only check).
- UI snapshots without clicking anything:
  `HRVCV_MOCK=1 HRVCV_SNAPSHOT=/tmp/popover.png <app binary>` renders the panel
  to a PNG and exits (`HRVCV_LIGHT=1` for light mode).
- `DESIGN_NOTES.md` records the design rationale — read it before UI changes.

## Sharing with friends

The catch: **a client secret can't be safely embedded in a distributed app** — it
ends up in the binary. Two ways to share:

- **Each friend registers their own WHOOP app** and fills their own `Secrets.swift`,
  then builds from source. No backend. Best for a few technical friends.

- **Run the token broker** (recommended for non-technical friends). Deploy the
  serverless functions in [`broker/`](broker/README.md), set
  `WHOOPConfig.brokerBaseURL` to your deployment, and the app stops using the
  embedded secret entirely (leave it empty in `Secrets.swift`) — you can hand
  friends a built `.app`. See [`broker/README.md`](broker/README.md).

> **⚠️ WHOOP multi-user note:** verify your WHOOP developer app is permitted to
> authorize users beyond your own account. Some developer apps are limited until
> approved by WHOOP for wider/production use — confirm this before sharing widely.

## License

Personal project. No warranty.
