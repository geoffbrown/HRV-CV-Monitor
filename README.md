# HRV-CV Monitor

A macOS menu bar app that tracks your **7-day rolling HRV coefficient of
variation** from WHOOP — a measure of how *consistent* your recovery has been,
night to night. Lower is better.

The menu bar shows `HRV-CV 22%` with a trend arrow; clicking it opens a dashboard
with a gauge, a plain-language status, your 7-night window stats, and a per-night
table of WHOOP recovery + HRV.

> **What is HRV-CV?** The standard deviation of your nightly HRV over 7 days,
> divided by the mean, as a percent. Low = steady autonomic recovery; high tracks
> inconsistent sleep, stress, alcohol, or training load. Targets: **≤15% on track,
> ≤8% elite.** ([background](https://www.whoop.com/us/en/thelocker/hrv-cv-recovery-metric/))

## Requirements

- macOS (Apple Silicon or Intel), Xcode 16+
- A WHOOP account and a WHOOP developer app

## Setup

1. **Register a WHOOP developer app** at <https://developer.whoop.com>:
   - **Redirect URI:** `hrvcv://callback`
   - **Scopes:** `read:recovery`
   - Note the **Client ID** and reveal the **Client Secret**.

2. **Add your Client ID** in `HRV-CV Monitor/WHOOPService.swift`:
   ```swift
   static let clientId = "your-client-id"
   ```

3. **Add your Client Secret** (kept out of git):
   ```sh
   cp Secrets.swift.example "HRV-CV Monitor/Secrets.swift"
   # then paste your secret into HRV-CV Monitor/Secrets.swift
   ```
   `Secrets.swift` is git-ignored, so your secret never lands in the repo.

4. **Open, sign, and run** in Xcode:
   - Open `HRV-CV Monitor.xcodeproj`
   - Target → **Signing & Capabilities** → pick your **Team** (a free Apple ID
     works). A stable signing identity keeps macOS from re-prompting for keychain
     access on every rebuild.
   - **Run** (⌘R). Find the heart / `HRV-CV …%` item in the menu bar and click
     **Connect WHOOP**.

## Architecture

| File | Role |
|------|------|
| `HRVCVApp.swift` | `MenuBarExtra` entry point + menu bar label (value + trend) |
| `ContentView.swift` | Dashboard UI: gauge, tier scale, stats, recovery/HRV table |
| `HRVCalculator.swift` | Parses recoveries → 7-night mean/SD/CV, tiers, week-over-week trend |
| `WHOOPService.swift` | OAuth (PKCE via `ASWebAuthenticationSession`), Keychain tokens, WHOOP v2 API |
| `Secrets.swift` | Your client secret (git-ignored; see `Secrets.swift.example`) |
| `broker/` | Optional serverless token broker for sharing (see below) |

- **Auth:** Authorization Code + PKCE, presented in an in-app `ASWebAuthenticationSession`
  sheet. Tokens live in the Keychain (one item), auto-refreshed before expiry.
- **Data:** WHOOP API **v2** `GET /recovery` (max `limit` 25).
- **Menu-bar only:** `LSUIElement` is set, so there's no Dock icon; quit from the
  panel (⋯ menu or ⌘Q).

## Sharing with friends

The catch: **a client secret can't be safely embedded in a distributed app** — it
ends up in the binary. Two ways to share:

- **Each friend registers their own WHOOP app** and fills their own `Secrets.swift`,
  then builds from source. No backend. Best for a few technical friends.

- **Run the token broker** (recommended for non-technical friends). Deploy the
  serverless functions in [`broker/`](broker/README.md), set
  `WHOOPConfig.brokerBaseURL` to your deployment, and the app stops embedding the
  secret entirely — you can hand friends a built `.app`. See
  [`broker/README.md`](broker/README.md).

> **⚠️ WHOOP multi-user note:** verify your WHOOP developer app is permitted to
> authorize users beyond your own account. Some developer apps are limited until
> approved by WHOOP for wider/production use — confirm this before sharing widely.

## License

Personal project. No warranty.
