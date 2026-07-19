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

- macOS (Apple Silicon or Intel), Xcode 16+
- A WHOOP account and a WHOOP developer app

## Setup

1. **Register a WHOOP developer app** at <https://developer.whoop.com>:
   - **Redirect URI:** `hrvcv://callback`
   - **Scopes:** `read:recovery offline`
   - Note the **Client ID** and reveal the **Client Secret**.

2. **Add your credentials** (kept out of git):
   ```sh
   cp Secrets.swift.example "HRV-CV Monitor/Secrets.swift"
   # then paste your Client ID and Client Secret into HRV-CV Monitor/Secrets.swift
   ```
   `Secrets.swift` is git-ignored, so your credentials never land in the repo.

3. **Open, sign, and run** in Xcode:
   - Open `HRV-CV Monitor.xcodeproj`
   - Target → **Signing & Capabilities** → pick your **Team** (a free Apple ID
     works). A stable signing identity keeps macOS from re-prompting for keychain
     access on every rebuild.
   - **Run** (⌘R). Find the heart / `CV …%` item in the menu bar and click
     **Connect WHOOP**.

Optional: the ⋯ menu in the panel has a **Launch at Login** toggle.

### Demo mode (no WHOOP account needed)

```sh
HRVCV_MOCK=1 "/path/to/HRV-CV Monitor.app/Contents/MacOS/HRV-CV Monitor"
```

Runs the app on a built-in sample dataset — useful for trying the UI before
connecting, or for development without burning API calls.

## Architecture

| File | Role |
|------|------|
| `HRVCVApp.swift` | `MenuBarExtra` entry point + menu bar label (`CV n%`) |
| `ContentView.swift` | Dashboard UI: gauge, zone legend, evidence chart, verdict card, stats, table |
| `HRVCalculator.swift` | Parses recoveries → 7-night mean/SD/CV, tiers, verdict, week-over-week baseline |
| `WHOOPService.swift` | OAuth (PKCE via `ASWebAuthenticationSession`), Keychain tokens, WHOOP v2 API |
| `MockData.swift` | Demo dataset (`HRVCV_MOCK=1`) + headless snapshot hook (dev) |
| `Secrets.swift` | Your WHOOP client ID + secret (git-ignored; see `Secrets.swift.example`) |
| `broker/` | Optional serverless token broker for sharing (see below) |

- **Auth:** Authorization Code + PKCE, presented in an in-app `ASWebAuthenticationSession`
  sheet. Tokens live in the Keychain (one item), auto-refreshed before expiry.
- **Data:** WHOOP API **v2** `GET /recovery` (max `limit` 25), deduped to one
  record per calendar day. Refreshes hourly, on wake from sleep, and when the
  panel opens with data older than 15 minutes.
- **Menu-bar only:** `LSUIElement` is set, so there's no Dock icon; quit from the
  panel (⋯ menu or ⌘Q).

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
