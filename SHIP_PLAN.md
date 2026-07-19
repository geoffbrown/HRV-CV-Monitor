# Ship Plan — DMG release for friends via GitHub

Goal: a friend with zero technical skill downloads a DMG from GitHub, drags the
app to Applications, launches it, connects their WHOOP, done. No Xcode, no
secrets, no Gatekeeper hoops.

## Decisions Geoffrey makes first (blockers for everything else)

1. **Apple Developer Program** — required for a clean install experience.
   Without it, the app can't be Developer ID-signed or notarized, and macOS
   tells friends the app is "damaged" or from an unidentified developer.
   $99/yr. **If not already enrolled, enroll ASAP — approval can take hours to
   days and it blocks steps 4–6.** (Side benefit: a stable signing identity
   finally kills the keychain re-prompt on every rebuild.)
   - Fallback if we skip it: ship the DMG anyway and give friends the
     right-click → Open (or `xattr -d com.apple.quarantine`) ritual. Works, but
     it's exactly the kind of friction this plan exists to remove.
2. **Repo visibility** — public repo makes the release page a clean shareable
   link (github.com/geoffbrown/HRV-CV-Monitor/releases). Private means each
   friend needs a GitHub account + repo access to download assets. Recommend:
   public (history is clean — Secrets.swift was never committed; verified).
3. **Broker deployment name** — e.g. `hrvcv-auth-broker.vercel.app`. Any
   Vercel account works; it's ~zero traffic.

## Build steps (in order)

### 1. Deploy the token broker (removes the secret from the app)
- [ ] `cd broker && vercel login && vercel` then `vercel env add WHOOP_CLIENT_ID`
      / `WHOOP_CLIENT_SECRET` (Production), `vercel --prod`
- [ ] Set `WHOOPConfig.brokerBaseURL = "https://<deployment>/api"` in
      `WHOOPService.swift`
- [ ] Local end-to-end test: sign out, sign back in through the broker, confirm
      refresh works (broker README has a curl for `/api/refresh`)
- [ ] Optional hardening: Vercel rate limit or a shared header check (broker
      README notes the endpoints are otherwise unauthenticated)

### 2. Verify WHOOP multi-user access (can silently kill the whole plan)
- [ ] Check the WHOOP developer dashboard: is the app limited to the owner's
      account, or approved for other users? Request production/wider access if
      needed — **do this early, approval latency is unknown**
- [ ] Best test: one friend authorizes successfully before we bother with DMGs

### 3. App polish for strangers
- [ ] **App icon** — AppIcon asset is currently empty; a Dock-less app still
      shows an icon in the DMG, Applications, and the auth window. Design one
      (the arc-gauge motif in a rounded rect is the obvious candidate)
- [ ] Set marketing version `1.0.0` + build number, `CFBundleDisplayName`
- [ ] Add a small "About / v1.0.0 (check for updates → GitHub releases)" item
      in the ⋯ menu — no auto-update infra yet, just a link
- [ ] Friendly error copy if the broker is unreachable
- [ ] Review first-run flow once more in a fresh macOS user account

### 4. Signing + notarization (needs decision 1 complete)
- [ ] In Xcode: set the Team on the target; confirm App Sandbox +
      outgoing-network entitlement still on
- [ ] Release build: `xcodebuild archive` + `-exportArchive` with the
      **Developer ID Application** certificate, hardened runtime on
- [ ] Notarize: `xcrun notarytool submit --wait` (needs an app-specific
      password or App Store Connect API key), then `xcrun stapler staple`

### 5. DMG
- [ ] Build the DMG (`create-dmg` or plain `hdiutil`): app + /Applications
      symlink, volume icon, sensible background-free layout
- [ ] Sign and notarize **the DMG too**, staple it
- [ ] Test on a machine (or fresh user account) that has never seen the app:
      download from a browser (so quarantine applies), mount, drag, launch —
      zero warnings is the acceptance bar

### 6. GitHub release
- [ ] Tag `v1.0.0`, `gh release create v1.0.0 HRV-CV-Monitor.dmg --notes ...`
- [ ] README: add a **Download** section up top for non-technical friends
      (download link, drag-to-Applications, "connect WHOOP", where the app
      lives — menu bar, no Dock icon)
- [ ] Make repo public (if decision 2 says so)

### 7. Repeatability (do it while it's fresh)
- [ ] `scripts/release.sh`: archive → export → dmg → notarize → staple →
      `gh release create`, driven by the version number. One command next time
- [ ] Note the gotchas in DESIGN_NOTES (notarytool credentials setup, xattr
      detritus workaround for CLI builds)

## Stretch / later
- Sparkle (real auto-update) — only if friends actually use it
- GitHub Action to build + notarize on tag push
- Per-friend broker usage visibility (Vercel logs are probably enough)

## Known constraints
- The agent can build, sign, and script everything, but Apple enrollment,
  the Vercel login, and the WHOOP dashboard check are Geoffrey-only steps.
- `Secrets.swift` still needs the real client ID at build time (auth URL);
  the secret field can be empty once the broker is live.
