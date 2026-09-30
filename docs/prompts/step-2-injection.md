# Step 2 — Route guard + JS/CSS injection engine

Read `CLAUDE.md` and the current code first to get the full status (Step 1 is done and verified on device, see `docs/DEVICE_CHECKLIST.md`).

This step has **two phases with a hard stop between them**. Nobody has yet observed how the real mobile site behaves (reel opened as an overlay or as a navigation, story URL shapes, which DOM anchors exist). Selectors and route rules must be based on observation, not guesses. So:

- **Phase A**: build DEBUG-only reconnaissance tooling, commit, then **STOP** and wait for me to paste a recon log.
- **Phase B**: once I paste the log, implement the route policy and the injection engine from what the log shows.

If something is ambiguous, ask instead of improvising (CLAUDE.md working rules). Everything added for recon is `#if DEBUG` only and never ships.

---

## Phase A — Recon tooling (DEBUG only)

### A1. Richer route messages
- The page-world route hook posts an object instead of a bare string: `{ path, kind }`, with `kind` one of `push`, `replace`, `pop`, `initial`.
- Update `RouteMessage` to validate this untrusted payload (dictionary, known `kind`, same path rules as today) and return a small value type (`RouteEvent`). Update its tests.
- `BrowserEngine` keeps `currentPath`, and now also keeps the last `RouteEvent`.

### A2. Redacted logging
Real paths contain usernames and thread ids, and I will paste these logs into chats. Add a pure `PathRedactor`, used by **every** DEBUG print that shows a path:
- Keep the structure; replace identifying segments with a short token that stays **stable within one app session** (so "reel A → reel B" stays visible): e.g. `/reel/#3fa/`, `/direct/t/#91c/`, `/stories/#u7d/#e02/`, `/p/#b11/`, and a profile `/{user}/` → `/@#4e2/`.
- Known non-username first segments stay readable: `accounts`, `direct`, `explore`, `reels`, `reel`, `p`, `stories`, `challenge`, and any other obvious reserved ones.
- Unit-test it.

### A3. DOM snapshot script
Add `Resources/Injection/recon.js`, installed **only in DEBUG**, in the `focus` world, main frame only. It exposes `__focusRecon.snapshot()`, which returns a compact JSON object:
- `path` (location.pathname) and `historyLength`;
- `links`: unique `a[href]` values (max 60), each with: redacted href (same rules as A2, reimplemented in JS), `aria-label` of the link or of an `svg[aria-label]` inside it (max 40 chars), and whether it sits inside `nav`, `[role=navigation]`, `[role=dialog]` or `main`;
- `labels`: `aria-label` values of buttons, links and svgs (max 60, max 40 chars each). Never `innerText` of messages;
- `dialogs`: count of `[role=dialog]`, and for each its direct structure (tags + roles, 2 levels);
- `scrollers`: up to 10 elements that are really scrollable vertically (`overflow-y` auto/scroll and `scrollHeight > clientHeight`), described by tag, role, aria-label, depth, size, and whether they contain `video`;
- `videos`: count of `video` elements, and how many are playing.

`BrowserEngine` (DEBUG): 1.5 s after each route event, call `__focusRecon.snapshot()` in the focus world with `callAsyncJavaScript`, and print one line: `[FocusRecon] <kind> <redacted path> <json>`.

### A4. Mark button
A small DEBUG-only floating button ("Mark") over the web view. Each tap prints `[FocusRecon] ---- MARK <n> ----` and takes a snapshot immediately. Placeholder look is fine.

### A5. Recon guide for me
Write `docs/RECON_STEP2.md`. The scenario section is **in French** (it is for me). It tells me to build on my iPhone, logged in, press **Mark** before each numbered step, then copy the whole Xcode console. Scenario:
1. Launch the app (inbox).
2. Open a DM conversation.
3. Tap a reel received in that conversation. Wait 3 s.
4. Swipe up once on that reel. Wait 3 s.
5. Go back to the conversation (with whatever back control the page offers).
6. Tap a post (`/p/`) received in DM, if there is one. Go back.
7. Open the contact's profile from the conversation. Open its Reels tab. Tap one reel. Swipe up once. Go back twice.
8. Open a profile with an active story, tap the avatar, and let the story run into the next person's story. Close it.
9. Tap each icon of the site's navigation bar, one at a time: Home, Explore/Search, Reels. Come back to the DMs between each.
10. Open the search field, if one exists.

It also tells me to skim the log before pasting it and to remove anything personal the redaction missed (aria-labels can contain names).

### A6. Close Phase A
Build, tests, commit `step-2a: DEBUG recon tooling`. Then **stop**, and tell me in one short paragraph (in French) what to do: run `docs/RECON_STEP2.md` and paste the console here.

---

## Phase B — Implementation (only after I paste the recon log)

### B0. Record findings
Summarize the log into `docs/RECON_STEP2.md` (a "Findings" section, English, redacted): the real URL shape and `kind` for each scenario step, whether reels and stories open as overlay (dialog) or page, the stable anchors found for each thing we hide, and the scroll container used by the reel viewer.

**If a finding contradicts the policy table in `CLAUDE.md`** (for example, a DM reel does not change the URL at all), stop and ask me before coding the policy.

### B1. Route policy (pure Swift, `Routing/`)
- `RouteClassifier`: path → `RouteKind`: `inbox`, `thread`, `profile`, `post`, `reel(id)`, `story(user, id?)`, `homeFeed`, `reelsFeed`, `explore` (includes search), `auth`, `unknown`. Hubs = `inbox`, `thread`, `profile`, `post`. Content = `reel`, `story`. Use the reserved-segment list shared with `PathRedactor`.
- `RoutePolicy` + a small `NavigationState` (last allowed route, current content identity, origin hub): input = new `RouteEvent`, `isLoggedIn`; output = `allow`, `redirect(path)` or `goBack`. Rules, from the `CLAUDE.md` table, adjusted to B0 findings:
  - Logged out: allow every Instagram route, never redirect.
  - `homeFeed`, `reelsFeed`, `explore` → `redirect("/direct/inbox/")`.
  - Content reached from a hub → allow, remember it.
  - Content → **different** content (another reel id, another story user), by push or replace → `goBack`. Same id/user again (replace noise, next story of the same user) → allow.
  - Content reached cold (first route of the session, or after a blocked route) → redirect to inbox.
  - `pop` to a hub → always allow. `pop` to content → allow only if it is the content currently remembered; otherwise redirect to inbox. **Never answer a `pop` with `goBack`** (loops).
  - Hub → hub (e.g. reel → post → profile): allowed. Manual taps are fine; only automatic chaining is blocked.
  - `unknown` → allow + DEBUG log (redacted).
  - Loop guard: more than 3 forced navigations within 2 s → stop forcing, redirect to inbox once, DEBUG log.
- Unit tests covering every row and transition above, including the loop guard.

### B2. Applying decisions (`BrowserEngine`)
- Route events from the hook go through `RoutePolicy`. `goBack` → `webView.goBack()` if possible, else redirect. `redirect` → `location.replace(...)` in the page (a reload is acceptable: CSS and the click guard should make redirects rare).
- Full-page navigations in `decidePolicyFor` go through the same policy (kind `initial`), after `NavigationHygiene`.
- After each decision, tell the focus-world engine the current route class (`__focus.setRoute("reel")`, etc.), which sets `data-focus-route` on `<html>`. The `<html>` attributes are not React-owned, so this is safe.

### B3. Filter data (bundled, data only)
- `Resources/filters.default.json`, following the schema sketch in `CLAUDE.md` (`schema`, `minEngine`, `revision`, `routes`, `rules[] {id, css, routeScope?, expectOn?}`, `i18n`). Adjust field names if needed and update the `CLAUDE.md` sketch to match.
- `RemoteConfig/FilterConfig.swift`: strict `Codable` + validation (size ≤ 64 KB, every regex compiles, `minEngine` ≤ app engine version, unique rule ids). Unit tests with valid and invalid fixtures.
- Step 3 will only add fetch, cache, signature and hot swap. Do not add networking now.
- Route regexes used by `RouteClassifier` come from this file, with the classifier falling back to built-in defaults if a regex is missing.

### B4. Injection engine (`Resources/Injection/focus-engine.js`, focus world, `documentStart`, main frame only)
- `__focus.apply(config)`: (re)builds one `<style id="focus-rules">` (appended to `document.documentElement` until `<head>` exists). Each rule goes in with `sheet.insertRule` inside `try/catch`; an invalid selector is skipped and reported, never breaks the others. `routeScope` rules are prefixed with `html[data-focus-route="…"]`.
- `__focus.setRoute(name)`.
- **Click guard**: one capture-phase `click` listener on `document`. If the click target is inside an `a[href]` whose path is classified as blocked (`homeFeed`, `reelsFeed`, `explore`, when logged in), `preventDefault()` + `stopPropagation()`. This stops the navigation before the site renders anything.
- **Behavior layer** (`MutationObserver`, throttled with `requestAnimationFrame`), only for what CSS cannot do, based on B0 findings: on the single-reel route, block vertical swiping to the next reel (lock the scroll container found in recon; block vertical `touchmove` on it) without breaking taps (play, pause, sound, comments, close). Optional text-based hiding of "Suggested for you" blocks using the `i18n` table (fr + en).
- **Health check**: each rule with `expectOn` must match at least one element within 5 s on a matching route; otherwise post `{ruleId, path}` to a `focusHealth` handler registered **in the focus world**. Native keeps the last failures in memory and prints them in DEBUG (redacted). Step 3 will use this to trigger a config refresh.
- Rules: never `remove()` a node, never obfuscated classes, anchors in the `CLAUDE.md` stability order. Initial rules (confirm or correct with the recon log): hide nav entries for Home, Explore/Search and the Reels feed (`a[href="/"]`, `a[href^="/explore"]`, `a[href="/reels/"]` and their wrappers via `:has()`); on the reel route, hide "more reels" UI if present.

### B5. Passing the config to the page
- At script install time, native appends `__focus.apply(<json>)` to the engine source. The JSON **must be re-encoded with `JSONEncoder` from the validated `FilterConfig` value**, never the raw file bytes. So a config can only ever carry data. Add a test for this.
- Keep the DEBUG recon tooling from Phase A (it will be reused when Meta changes the site).

### B6. Tests, docs, commit
- WebKit integration tests (offline `WKWebView`, local HTML fixtures that mimic the nav structure seen in recon): a hidden rule has computed `display: none`; an invalid selector does not break the other rules; the click guard prevents navigation for a blocked href and not for `/direct/…`; a missing `expectOn` rule posts a health message; `setRoute` sets the attribute.
- Add a "Step 2" section to `docs/DEVICE_CHECKLIST.md`: every scenario step of the recon guide with its expected result (blocked, allowed, returned to hub), plus: no flash of the blocked nav icons on launch, taps inside a DM reel still work, the loop guard never triggers in normal use.
- Update `CLAUDE.md`: Roadmap (Step 2 checked), the policy table if B0 changed it, the schema sketch, and a Decisions log entry (what was observed, what was chosen, what is left for the device).
- `xcodegen generate` clean, build, tests, no new warnings. Commit `step-2: route policy and injection engine`.
- Report: findings in short, the route table as implemented, the rules shipped, tests added, and what still needs my iPhone.
