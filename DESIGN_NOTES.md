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
→ tier-colored → back and forth. **Current resolution (don't relitigate without
reason):** a speedometer with **three zone bands** (Elite green / On Track green-muted
/ Elevated amber), the band you're in **lit**, others receded; numeric marks at
**8** and **15**; a **knob in the verdict color** at your value; and center text
(HRV-CV %, verdict label) **in the verdict color**. So the *scale* states the fact
(where you are) and the *color* states the meaning (what it implies). This lets
"Elevated zone" + "LEVELING UP" coexist.

> Note: an earlier version used a fully **neutral** track (no zone colors) on the
> logic that "CV has no intrinsic good/bad." That was later revised back toward
> colored zones. If you're tempted to go neutral again, know it was tried.

### The evidence chart (`HRVBandChart`)
Nightly HRV (dots + line) travelling through its **typical range** (a band = mean
± rolling SD over trailing 7 nights). Last week's baseline is **ghosted** (dashed)
so a baseline step-up is visible. Hover **scrubs**: shows that night's date, HRV
(ms), and WHOOP recovery. This is "the evidence" that explains *why* CV is what it
is. It's open (no box), grouped tightly with the gauge as one visual unit.

- Gotcha we already fixed: **scrub jitter.** Animating the whole VStack on the
  `scrubbing` flag caught the chart and made it twitch. Fix: scope the dim
  animation to *only the dimmed elements* (gauge, legend, status card) and give
  the chart header a **fixed height** so the default↔hover swap can't reflow.

### The verdict card (`statusCard`)
The one contained/tinted card. Accent bar + headline (verdict color) + one tight
sentence + SIGNALS + an (i) that opens the WHOOP HRV-CV article. Prose was
deliberately **trimmed to one sentence** per verdict — the SIGNALS carry the rest.

### SIGNALS (`signalsList`)
Three qualitative rows: **Baseline** (Rising/Steady/Falling), **Variability**
(Tight/Expected/Elevated/Concerning by verdict), **Recovery** (Strong/Moderate/Low).
Labels are `.tertiary`, values `.secondary` (softened so they don't shout).

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
Shows **`CV 22%`** as a **single `Text`**. Two hard-won lessons:
1. **No trend arrow.** An arrow (↗) asserts a good/bad *direction*, but (a) "up"
   for CV is exactly the ambiguity the app exists to resolve, and (b) the menu bar
   strips color so it *can't* honestly show the verdict. An arrow there is a claim
   it can't back up. ChatGPT flagged this as "not honest"; we agree.
2. **One `Text`, not an HStack of two.** A status-bar label splits an HStack of
   `Text`s unreliably and **dropped the number**, leaving a bare `CV`. Combining
   into `Text("CV \(n)%")` fixed it. Don't re-split it.
   - We prototyped glyphs (`SpreadGlyph` = spread-width bar, `MiniArc` = position
     arc) and removed them: at ~16px they failed to register (read as "just the
     number"). Text identity (`CV`) proved more reliable. Don't reintroduce a
     glyph without a legibility plan.

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
- **Secrets:** `Secrets.swift` is **git-ignored** and holds the real client secret;
  `Secrets.swift.example` is the committed template. Verified only the `.example`
  is tracked. Client **ID** is hardcoded in `WHOOPService.swift` (IDs aren't secret).
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

## 8. Open threads / possible future work

- **Adaptation-state taxonomy** (Stable / Transitioning / Unstable / Suppressed)
  with **hysteresis** so the verdict doesn't flip-flop day to day, plus a
  **confidence** signal. Agreed as a good direction, not yet built.
- **Personalized "normal range"** instead of fixed 8/15 thresholds — needs more
  of the user's own history to compute.
- `ServiceManagement` was recently imported — likely **launch-at-login** in progress.
- A deeper "restraint pass" is mostly done; keep an eye on spacing rhythm if you add sections.

## 9. Working style the user expects

- Bring a point of view. He shares ChatGPT/Gemini feedback and wants an **honest
  take** — build the genuinely good ideas, **push back** on the bad ones with reasons.
- He iterates visually and will say when something is "a step back." Ship, let him
  ⌘R, react.
- Commit when asked; he'll handle the push.
