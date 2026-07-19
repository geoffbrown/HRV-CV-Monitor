# HRV-CV Monitor — Design & Thinking Notes

A handoff for the next Claude Code instance. This captures the *why* behind the
current design, not just the *what*. Read this before making UI or product
changes — a lot of the "obvious" simplifications here were tried and rejected
for real reasons.

---

## 1. What the app is

A macOS **menu-bar-only** app (`LSUIElement`, `MenuBarExtra(.window)`) that reads
your WHOOP recovery data and shows **HRV-CV**: the coefficient of variation of
your nightly HRV over a 7-night window (`SD / mean`, as a %).

It is deliberately **not** "a number tracker." The product thesis is that it's an
**interpretation engine**: it renders a *verdict* and *exposes its reasoning*, so
you learn to read your own autonomic stability, not just watch a metric.

Menu bar shows `CV 22%`. Click → a popover with gauge, evidence chart, verdict
card, stats, and a 7-day table.

## 2. The core conceptual model (most important idea)

**HRV-CV is direction-blind on its own.** Lower CV = more consistent = usually
good. But a *rising* CV is ambiguous, and this is the entire intellectual core of
the app (from Marco Altini / HRV4Training — see the WHOOP article the (i) links to):

> Interpret CV **together with the baseline (mean HRV) direction.**
> - CV↑ **and** baseline↑ → you're **leveling up** (adapting to a higher level). Good.
> - CV↑ **and** baseline↓ → you're **destabilizing** (fatigue/stress accumulating). Warning.
> - CV↑ with flat baseline → just **elevated**. Watch it.

This produces the `Verdict` enum in `HRVCalculator.swift`:
`elite · onTrack · levelingUp · elevated · destabilizing`, computed as
`tier × baselineDirection`. **Everything in the UI flows from this.** If you
"simplify" the app back to a single colored number, you destroy the point.

Tiers (the raw CV scale, kept from WHOOP/literature): **Elite ≤8% · On Track ≤15% · Elevated >15%.**

## 3. Design principles we converged on

- **Beauty = subtraction, not decoration.** Multiple rounds of AI feedback
  (ChatGPT + Gemini) proposed frosted glass, glassmorphic charts, glyph heroes,
  pulsing "corridor" gauges. All rejected. Both external models eventually
  *backtracked* and agreed: the win is restraint (whitespace, trimmed prose,
  quiet chrome), not added material. If Apple/WHOOP shipped this, they'd remove,
  not add.
- **Separate the metric from the verdict.** Position/magnitude = *fact*; color =
  *meaning*. They can disagree without contradiction ("in the amber zone" **and**
  "leveling up" is coherent).
- **Reasoning as logic, not telemetry.** The SIGNALS block gives qualitative
  reasons (Rising / Tight / Strong), not raw numbers — the numbers already live
  in the stats row and table.
- **No em dashes in user-facing copy.** (User preference. Code comments are fine.)
- **Don't say "your target."** The user doesn't set targets; the scale is a
  neutral reference ladder, not a goal the app assigns.
- **Opaque panel, not translucent.** Rich solid surface (`popoverBackground`),
  not washed-out `.regularMaterial`. Tried translucency; rejected.

## 4. Key UI decisions & why

### The gauge (`CVGauge`)
This one went through a long feedback loop — rainbow → single-hue → neutral gray
→ tier-colored → back to neutral. **Current resolution (user-confirmed; don't
relitigate):** the track is a **neutral gray ruler** — the user explicitly
rejected zone-colored bands ("HRV-CV isn't about good or bad", and multiple hues
on the arc read as unrefined). The segment problem ("what do the segments
mean?") is solved by **labeling, not coloring**, speedometer-style: the track is
drawn as **three sub-arcs with rounded caps**, separated by small breaks at 8
and 15 that act as tick marks, with small **tertiary numerals tucked just inside
the ring** beneath each break (`innerNumeral`). The half-break is computed from
geometry — `g = (lw + 3) / (2πr)` — so the rounded caps (which extend `lw/2`
past each trim point) leave a ~3pt sliver of panel. The fill breaks where the
track breaks, caps matching. Rejected along the way: numerals floating *outside*
the arc (not integrated); wide breaks with numerals *in* the arc line (chopped
the sweep, read busy); and hairline seams sliced through a continuous arc
(square-cut edges against the arc's rounded ends — no corner radii, unrefined).
The **fill sweeps to the value in neutral ink** (`primary @ 0.32` over the `0.1`
track) — a verdict-hued fill was tried and rejected: a mostly-full arc in a
judgment color pre-attentively reads as "a lot of good/bad", the exact
misreading the app exists to avoid. **"The instrument is ink; the reading is
colored":** the verdict hue appears only in the knob, the center number, and
the verdict label. The **knob** is a solid dot in the verdict hue with a
panel-colored ring to lift it off the fill (user preferred filled over punched)
— the one colored point on the instrument, marking the reading. The legend
directly beneath (Elite ≤8 · On Track 8–15 · Elevated >15, **no colored dots**)
is the ruler's key, tying back to the on-arc numerals — and it reads like a
**segmented control**: the active tier sits in a quiet neutral chip
(`primary @ 0.09`, radius 5.5) plus bold text. Added because knob position +
bare bold text under-communicated "where you are on the ladder" (the tier is a
fact, so it gets stated — in ink, never in judgment color).

> The tier-colored-zones variant (green/green-muted/amber bands, lit active
> zone, verdict-colored knob) was built and rejected by the user: different
> colors for segments vs knob felt unrefined, and coloring the scale asserts a
> good/bad reading the metric doesn't have. Color belongs to the verdict only.

### The evidence chart (`HRVBandChart`)
Nightly HRV (dots + line) travelling through its **typical range** (a band = mean
± rolling SD over trailing 7 nights). Last week's baseline is **ghosted** (dashed)
so a baseline step-up is visible. Hover **scrubs**: shows that night's date, HRV
(ms), and WHOOP recovery. This is "the evidence" that explains *why* CV is what it
is. It's open (no box), grouped tightly with the gauge as one visual unit.

- **Color scoping rule:** per-**night** elements are tinted by that night's
  WHOOP recovery band (table bars, scrub-readout ms + dot); per-**week**
  elements are tinted by the verdict (gauge knob/number/label, card, chart
  line). The scrub readout's ms value follows the *night* (user call — it
  previously leaked the week's verdict color onto a single night).
- Gotcha we already fixed: **scrub jitter.** Animating the whole VStack on the
  `scrubbing` flag caught the chart and made it twitch. Fix: scope the dim
  animation to *only the dimmed elements* (gauge, legend, status card) and give
  the chart header a **fixed height** so the default↔hover swap can't reflow.

### The verdict card (`statusCard`)
The one contained/tinted card. Accent bar + headline (verdict color) + one tight
sentence + SIGNALS + an (i) that opens the WHOOP HRV-CV article. Prose was
deliberately **trimmed to one sentence** per verdict — the SIGNALS carry the rest.

### SIGNALS (`signalsList`)
Three qualitative rows, written for a WHOOP user who doesn't know HRV-CV:
**HRV baseline** (Rising/Steady/Falling — the 7-night average vs last week),
**Night-to-night swing** (Widening/Steady/Settling — the week-over-week direction
of the CV), **Recovery** (Strong/Moderate/Low — avg WHOOP recovery; context, not
a verdict input). Labels are `.tertiary`, values `.secondary`; each row has a
`.help` tooltip with the actual numbers (qualitative visible, telemetry on hover).

Naming rules learned the hard way:
- Never label the swing row **"Variability"** — to a WHOOP user that word IS HRV,
  so "variability of the variability" reads as nonsense. "Night-to-night swing"
  matches the verdict copy ("the wider swing is a step up").
- Say "HRV baseline", not bare "Baseline" (baseline *of what?*).
- Words state **facts** (directions), not judgments — the judgment is the tint,
  and it's contextual: a **Widening** swing is `.secondary` while CV is in range
  or the baseline is rising, amber only when elevated with a flat baseline, coral
  when elevated with a falling baseline. The two HRV rows together *are* the
  verdict logic (swing widening + baseline rising = leveling up), which is the
  teaching moment of the block.
- **Arrow glyphs = fact, tint = judgment** (settled after a full round trip:
  arrows → dots → arrows). The arrows were removed once because they double-
  encode the direction the word states and risk the "up = good" misreading; the
  user liked them and asked for them back, with the semantics now explicit:
  the arrow (and the word restating it) says which way the quantity moved; the
  tint says how the app judges it — green good, amber watch, coral concern.
  Neutral ("no judgment") is `primary @ 0.35` — dimmer than the value text, so
  the hierarchy reads "colored glyph = the app has an opinion, faint glyph =
  just context". Gray never means bad; bad is always coral. Recovery is a
  level, not a direction, so it keeps a dot.
  Under Differentiate Without Color the glyph becomes the judgment itself
  (check / minus / ! / warning), so color is never the only judgment channel.
  (The menu-bar arrow ban still stands — there, no word disambiguates.)

### Accessibility (user requirement: never color-only)
Color is always a **redundant** channel, never the sole one:
- Facts live in words/numbers everywhere (verdict label + headline, signal words,
  legend ranges, stat values, table percentages).
- The active tier in the legend is **bold**, not just tinted.
- Signal-row judgments honor **Differentiate Without Color**
  (`accessibilityDifferentiateWithoutColor`): dots become glyphs
  (✓ good / – neutral / ! watch / ⚠ concern). `HRVCV_A11Y=1` forces this
  rendering in snapshots (the env key is read-only, so it can't be injected).
- VoiceOver: the gauge is one element ("HRV CV 22.0 percent, Leveling up. In the
  Elevated, over 15 percent range."), the evidence chart has a spoken summary
  (`chartA11yLabel`), signal rows speak fact + judgment ("HRV baseline: Rising.
  A good sign."), stat cells speak value + trend, recovery bars are hidden (the
  row's % text carries the value), icon-only buttons are labeled.

### Stats row + 7-day table
AVG HRV (with baseline-direction arrow), SPREAD (SD), RECOVERY (color-coded).
**Tabular digits** so decimals hold their column. The **7-day table is inline and
always visible** — we tried folding it behind a disclosure and the user pushed
back hard: pattern-matching nightly HRV against the WHOOP recovery color bars is a
*core* use, not "details on demand." **Keep it exposed by default.**

### Colors (`adaptiveTier`)
One hue per tier, muted (status colors, not alarms), **adaptive to light/dark**
via an `NSColor(name:)` dynamic provider (brighter/more saturated in dark mode).
`tierGreen / tierAmber / tierRed(muted coral)`. WHOOP **recovery** uses its own
red/yellow/green (≥67 green, 34–66 amber, <34 red) — matches WHOOP's own scale.

### Menu bar label (`MenuBarLabel`)
Shows **`CV 22%` inside one outlined rounded-rect badge** (1.2pt stroke, corner
radius 5.5, 11pt text; the whole label is encapsulated). The lineage: loose
"CV" + filled capsule → whole-label filled badge → **outline** (user: the solid
fill was too heavy in the bar). Rendered as **one template `NSImage`**
(`isTemplate`, alpha = ink, `ImageRenderer` at 2x). Hard-won lessons:
1. **No trend arrow.** An arrow (↗) asserts a good/bad *direction*, but (a) "up"
   for CV is exactly the ambiguity the app exists to resolve, and (b) the menu bar
   strips color so it *can't* honestly show the verdict. An arrow there is a claim
   it can't back up. ChatGPT flagged this as "not honest"; we agree.
2. **One view, not an HStack of `Text`s.** A status-bar label splits multi-Text
   layouts unreliably and once **dropped the number**, leaving a bare `CV`. A
   single rendered image sidesteps splitting entirely and survives template
   rendering (light/dark/tinted bars) — that's why the pill is an image, not
   live SwiftUI shapes.
   - We prototyped abstract glyphs (`SpreadGlyph` = spread-width bar, `MiniArc` =
     position arc) and removed them: at ~16px they failed to register. The pill
     passes the legibility bar because its content is literally the text.
   - Snapshots emit the label alongside the popover (`<path>-menubar.png`) for
     headless verification.

## 5. Ideas we explicitly rejected (so you don't re-propose them)

- Frosted glass / translucent panel.
- Glassmorphic or shaded "area under the curve" chart drama.
- A giant glyph "hero" replacing the number.
- A linear "Target Corridor" gauge with grid lines (read as lab equipment).
- Pulsing circles / motion decoration.
- Folding the 7-day table behind a disclosure.
- A menu-bar trend arrow.
- Gutting the data table into an abstract list.

## 6. Technical / infra state

- **Auth:** OAuth 2.0 Authorization Code + PKCE via `ASWebAuthenticationSession`
  (`prefersEphemeralWebBrowserSession: true` — avoids stale Safari cookies).
  WHOOP is a **confidential client**, so token requests **must include
  `client_secret`**. Scope string: `offline read:recovery` (offline → refresh token).
- **API:** WHOOP developer API **v2** (`/recovery`). **`limit` max is 25** (30 → HTTP 400).
- **Secrets:** `Secrets.swift` is **git-ignored** and holds **both** the client ID
  and client secret (one "your credentials" file for people building from source);
  `Secrets.swift.example` is the committed template. Verified only the `.example`
  is tracked. `WHOOPConfig` reads both from `Secrets`.
- **Dev hooks (`MockData.swift`):** `HRVCV_MOCK=1` runs the app on a built-in
  14-night demo dataset (no WHOOP auth, no keychain, no network) — also useful as
  a demo mode for people without an account. `HRVCV_SNAPSHOT=/path.png` renders
  the popover to a PNG via `ImageRenderer` and exits (`HRVCV_LIGHT=1` for light
  mode; dynamic `NSColor`s are resolved inside
  `performAsCurrentDrawingAppearance`). Together they give headless UI
  verification without clicking the menu bar.
- **Keychain:** single consolidated item `whoop_tokens`,
  `kSecAttrAccessibleAfterFirstUnlock`, cached in `TokenStore`. (Repeated "Always
  Allow" prompts during dev are a code-signing artifact — set a signing Team to stop them.)
- **Token refresh:** `refreshIfNeeded` only clears tokens on `tokenRejected`
  (400/401), **keeps** them on network errors (so a flaky connection doesn't sign you out).
- **Broker (`broker/`):** optional Vercel serverless proxy (TypeScript) that keeps
  the client secret server-side, for distributing the app to friends without
  handing them a secret. Toggled by `brokerBaseURL` in `WHOOPService`.
- **Bundle plumbing:** `Info.plist` at repo root wired via `INFOPLIST_FILE`;
  `CFBundleURLTypes` = `hrvcv://callback`; `ENABLE_OUTGOING_NETWORK_CONNECTIONS`
  (App Sandbox) in both Debug/Release. Xcode 16 file-system-synchronized groups.
- **Refresh cadence:** hourly `Timer` **plus** a `NSWorkspace.didWakeNotification`
  observer → `loadIfStale()` (reloads only if data >15 min old), since the timer
  doesn't fire during sleep.
- **Data hygiene:** `HRVCalculator` **dedupes to one record per calendar day** (latest
  wins) so an updated/extra recovery can't double-count a night in the 7-window.

## 7. Build & repo gotchas

- **Build:** `xcode-select` may point at CommandLineTools (breaks `xcodebuild`).
  Prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Build
  with `CODE_SIGNING_ALLOWED=NO` for CI-style checks.
- **Push is blocked for the agent:** there is **no git remote**. Creating the
  GitHub repo (name + public/private) is the user's call — the permission
  classifier denies the agent running `gh repo create`. Local commits are fine;
  the user runs:
  `gh repo create HRV-CV-Monitor --private --source=. --remote=origin --push`
- Stale Xcode Issue-navigator errors clear with ⇧⌘K. `.onOpenURL` on a `Scene`
  doesn't compile; the app uses `ASWebAuthenticationSession` instead (no URL handler needed).
- **codesign "resource fork / detritus" failures** in CLI builds: files written by
  agent tooling carry `com.apple.provenance` xattrs that leak into the product.
  Fix: `xattr -cr` the product (or sources) and re-sign, or build with
  `CODE_SIGNING_ALLOWED=NO` and ad-hoc sign afterward. Xcode GUI builds are unaffected.

## 8. Open threads / possible future work

- **Adaptation-state taxonomy** (Stable / Transitioning / Unstable / Suppressed)
  with **hysteresis** so the verdict doesn't flip-flop day to day, plus a
  **confidence** signal. Agreed as a good direction, not yet built.
- **Personalized "normal range"** instead of fixed 8/15 thresholds — needs more
  of the user's own history to compute.
- **Launch at Login** shipped: a `Toggle` in the footer ⋯ menu backed by
  `SMAppService.mainApp`.
- A deeper "restraint pass" is mostly done; keep an eye on spacing rhythm if you add sections.
- **iOS companion app — Phase 1 landed** (shared core + basic iOS build; see
  below). **Sleep consistency signal also landed**: `read:sleep` scope added,
  `Sleep`/`SleepCollection` models + `WHOOPService.fetchSleep`, and a fourth
  SIGNALS row (`sleepConsistencySignalRow`) averaging WHOOP's own
  `sleep_consistency_percentage` over the same 7-night windows as the HRV-CV
  calculation — deliberately reusing WHOOP's own score rather than deriving a
  duration-variability metric ourselves. **Caveat:** existing sign-ins issued
  before this scope was added won't have `read:sleep` on their token; the row
  just stays hidden (`avgSleepConsistency == nil`) until the user signs out
  and reconnects WHOOP to re-consent — there's no migration path, and that's
  fine, it degrades silently rather than erroring.
  Still to come: an App Group + shared snapshot, a Widget Extension (home
  screen + lock screen: `accessoryCircular`/`accessoryRectangular`/
  `accessoryInline`), and a `BGAppRefreshTask` that fires one local
  notification per day when a new recovery record lands. None of that is
  built yet — don't assume it exists.
- **SIGNALS wording**: "Night-to-night swing" values are past-tense
  ("Widened"/"Settled"/"Steady"), not present-progressive ("Widening") —
  deliberate, because all SIGNALS comparisons are rolling-7-night-window vs
  the prior rolling-7-night-window, not a live trend, and "-ing" reads as
  "happening right now" even when the chart's tail is already recovering.
  The `SIGNALS · VS. PRIOR 7 NIGHTS` caption and the `.help()` tooltip copy
  ("over the last 7 nights" / "the 7 nights before that", not "this week" /
  "last week") exist for the same reason — "week" implies a calendar week,
  which this isn't. Keep any new SIGNALS row consistent with both of these.

### iOS Phase 1 architecture (for the next instance)

The project turned out to already be Xcode's **single-target multiplatform
app** template (`SUPPORTED_PLATFORMS` includes `iphoneos`/`iphonesimulator`
alongside `macosx`) — there's no separate iOS `PBXNativeTarget`. Both
platforms are built from the *same* target and the *same* source files, split
with `#if os(macOS)` / `#if os(iOS)` inline, not by target membership. Keep
using that pattern rather than introducing a second native target — a Widget
Extension will be the first thing that actually needs one (WidgetKit
extensions can't share a target with the host app).

Shared, platform-neutral logic (HRV math, WHOOP OAuth/networking/Keychain,
mock data, tier colors) now lives in a local Swift package, **`HRVCVCore/`**,
consumed by the app target via a package product dependency
(`packageProductDependencies` in the pbxproj). Types crossing the
package/app boundary had to be marked `public` — if you add a new field to
`HRVCVResult`/`HRVDay`/etc. that `ContentView.swift` needs to read, remember
the `public` keyword or it'll only fail to compile from the app side, not the
package side.

`WHOOPService.presentationAnchorProvider` is the one place the platform split
threads through the package cleanly: the package only imports
`AuthenticationServices` (cross-platform) and never AppKit/UIKit — each
platform's `HRVViewModel.init()` sets the closure (mac: `NSApp.keyWindow`; iOS:
the foreground `UIWindowScene`'s key window). If you ever add another
platform-specific hook to `WHOOPService`, follow this same injected-closure
shape rather than reaching for `#if os()` inside the package itself.

`Secrets.swift` moved from `HRV-CV Monitor/` to
`HRVCVCore/Sources/HRVCVCore/` (still git-ignored, `.example` template still
committed) — one WHOOP developer app/credential pair now serves both
platforms, since they share the redirect URI scheme.

`LSUIElement` (menu-bar-only, no Dock icon) is scoped to macOS only via
`"INFOPLIST_KEY_LSUIElement[sdk=macosx*]"` in the build settings, not the
static `Info.plist` — the iOS build is an ordinary foreground app.

### Typography — scalable, not semantic (`Typography.swift`)

Content text uses a custom **`.scaledFont(size:weight:design:)`** modifier
(in `HRVCVCore`, backed by `@ScaledMetric`) rather than fixed
`.font(.system(size:))`. It keeps the exact tuned sizes at the default
setting but grows them with the user's Dynamic Type setting. We deliberately
did **not** switch to semantic text styles (`.caption`/`.footnote`/…): those
would snap the fine-grained 8/9/9.5/10/11/12/13 scale onto iOS's coarser
fixed rungs and flatten the hierarchy. This is an **iOS-facing** change —
macOS has no Dynamic Type control, so `.scaledFont` is inert there (size
stays as given), which is fine.

Two things stay **fixed on purpose**: the **gauge** (`CVGauge`) internals and
the **menu bar label**. The gauge is a positioned graphical instrument (its
center number and dial numerals are laid out by geometry, like Apple's
Activity rings, whose center text doesn't Dynamic-Type-scale either); scaling
them would break the bowl composition. The menu bar label is macOS-only and
image-rendered. If the gauge should ever scale, that's a real layout job
(responsive bowl geometry), not a font swap.

Scaling is **clamped** to the standard range via
`.dynamicTypeSize(.xSmall ... .xxxLarge)` on the root, because the panel is
dense with fixed frames (table column widths, gauge/chart heights) that the
full accessibility sizes (2-3x) would clip. Lifting that clamp is a
follow-up that needs the fixed frames made flexible first.

**Not yet verified in Xcode** (this was built headless, no Xcode GUI
available): open the project, let it resolve the new local package, confirm
the iOS destination actually builds and runs in Simulator, and do a real
WHOOP OAuth login on both destinations before trusting this is solid.

## 9. Working style the user expects

- Bring a point of view. He shares ChatGPT/Gemini feedback and wants an **honest
  take** — build the genuinely good ideas, **push back** on the bad ones with reasons.
- He iterates visually and will say when something is "a step back." Ship, let him
  ⌘R, react.
- Commit when asked; he'll handle the push.
