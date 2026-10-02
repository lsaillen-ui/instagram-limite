# Device checklist

Items that need a real iPhone or a logged-in Instagram account to verify. Filled in from Step 1.

## Step 1: web view foundation
- [x] Cold launch on device: the login page (or the inbox when already logged in) loads; no "open the app" banner, no degraded layout (checks the UA `Safari/` token).
- [x] Log in through instagram.com's own UI, kill the app, relaunch: still logged in (persistent cookies).
- [x] Safe areas: the page is inset by SwiftUI's safe area; check nothing is clipped at the notch or home indicator, and whether `viewport-fit=cover` should instead let content run edge to edge.
- [x] Viewport lock: no pinch zoom, no zoom on focusing a text field, no rubber-band overscroll.
- [ ] Videos and reels do not autoplay; a tap plays inline (no fullscreen takeover).
- [ ] "Log in with Facebook": external hosts open in `SFSafariViewController`, whose cookies are not shared with the app. Verify whether this flow is usable; if not, decide on an allowlist.
- [ ] A link shared in a DM (`l.instagram.com/?u=…`) opens the real target in `SFSafariViewController`.
- [ ] A `target=_blank` link to an external site opens in `SFSafariViewController`; the app never gets a second web view.
- [ ] "Open in app" / App Store links do nothing (no jump to the Instagram app or the App Store).
- [ ] Route hook: with Safari Web Inspector (Develop → device → page), navigating inside the app changes `BrowserEngine.currentPath` (breakpoint or temporary debug print). Confirms `pushState` calls are seen on the real site.
- [ ] Web process termination (Safari inspector, or memory pressure): the page reloads instead of staying blank.
- [ ] `isLoggedIn` flips to true after login and false after logout (cookie `sessionid`), checked with a temporary debug print.
- [x] Cookie banner on first launch (logged out, fresh install): tapping "Allow all cookies" (and "Decline optional cookies") does not crash; the banner goes away and the login page stays usable. Read the DEBUG console for `decidePolicyFor` / `createWebViewWith` lines and note every host that ends in `openInSafari`.
- [ ] An external link opened in `SFSafariViewController` can be dismissed with Done; a second external link afterwards opens normally; rapid double taps present only one.

## Step 3: over-the-air config
Needs the real Pages URL in `RemoteConfigEndpoint.baseURL` and `remote-config/` published.

- [ ] Launch with Wi-Fi on: the DEBUG log shows `config refresh: …` (`unchanged` when the published revision equals the bundled one, `updated` after publishing a newer one).
- [ ] Publish a config with a newer revision that hides one more selector: reopen the app, the rule is active on the current page without a reload (or after the next navigation).
- [ ] Publish a config with a wrong signature (edit `config.json` without re-signing): the log shows `rejected`, nothing changes.
- [ ] Airplane mode at launch: the app loads at once with the cached/bundled config, no delay, no error.
- [ ] A second launch sends `If-None-Match` and gets `unchanged` (304) from Pages.
- [ ] Put the app in the background for more than 6 h (or change `staleAfter` temporarily): coming back triggers a refresh.

## Step 2: route policy and injection engine
Logged in, on the iPhone, with the DEBUG log open (`[FocusBrowser] route: … -> allow|goBack|redirect(…)`). "Returned to hub" means the page is back on the conversation, profile or post you came from.

- [ ] No flash of the Home, Explore and Reels icons of the bottom bar when a page with the bar loads (profile, post, reel).
- [ ] The Home, Explore and Reels icons are gone from the bottom bar on profiles, posts and reels; the Messages icon and the profile icon are still there and work. Note how the bar looks with three icons missing (placeholder UI, the owner designs the real one).
- [ ] Inbox Back arrow (top left): you stay on the inbox (the log shows `push /` then `redirect`); no home feed, no long reload.
- [ ] Tapping a hashtag, location or "audio" link inside a reel or a caption does nothing (no `/explore/…` or `/reels/audio/…` page).
- [ ] Recon scenario A: a reel received in a conversation opens; play, pause, sound, like, comment and the Close cross work; **swiping up does not move to another reel**; the conversation is intact after Close. Opening a second reel afterwards works and is locked too.
- [ ] Recon scenario A, comments and emoji panel of the overlay still scroll (the lock must not swallow nested scrollers).
- [ ] The conversation itself still scrolls normally, including with a video message in it (the lock must not touch the chat).
- [ ] Recon scenario B: a reel opened from a profile's Reels tab opens as a page; swiping does nothing; Back returns to the profile (returned to hub).
- [ ] Recon scenario C: a story opened from a profile avatar plays; when it ends and would advance to another person, the page goes back to the profile (returned to hub), not into the next person's story. Tapping through several stories of the same person works.
- [ ] A story reply or mention received in a conversation opens, and closing returns to the conversation.
- [ ] Reel → post → profile, tapped by hand (hub → hub), is allowed at every step.
- [ ] Opening a post from a conversation, then Back, returns to the conversation.
- [ ] Explore: the search entry points are unreachable from the bottom bar; if you land on `/explore/…` by any other path, you end on the inbox.
- [ ] Log in from scratch (logged out): the login flow is never redirected; right after logging in you land on the inbox, not the home feed.
- [ ] Relaunch the app while a reel or story was open: it starts on the inbox (cold content is redirected).
- [ ] Web process termination while a reel is open: the page reloads on the inbox, not on the reel.
- [ ] The loop guard never triggers in normal use: no `loop` line and no burst of `goBack` / `redirect` lines in the DEBUG log.
- [ ] `[FocusBrowser] health:` lines: none on a post page after 5 s (the bottom-bar rules match). Note any rule listed, and the page it was on.
- [ ] Unknown routes: skim the log for `unknown route` lines and note each path shape.

