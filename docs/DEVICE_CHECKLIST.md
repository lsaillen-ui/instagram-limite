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
- [ ] Cookie banner on first launch (logged out, fresh install): tapping "Allow all cookies" (and "Decline optional cookies") does not crash; the banner goes away and the login page stays usable. Read the DEBUG console for `decidePolicyFor` / `createWebViewWith` lines and note every host that ends in `openInSafari`.
- [ ] An external link opened in `SFSafariViewController` can be dismissed with Done; a second external link afterwards opens normally; rapid double taps present only one.
