// Focus engine (documentStart, focus content world, main frame only).
//
// Three layers, from most to least stable:
//   1. Route guard: native. This file only publishes the current route class (setRoute) and
//      stops clicks on links to blocked routes before the site renders anything (click guard).
//   2. Declarative CSS: each rule of the config hides what its selector matches.
//   3. Behavior layer: a MutationObserver (throttled with requestAnimationFrame) for what CSS
//      cannot do: locking the vertical swipe of an infinite reel feed.
//
// The config is data only. This file never evaluates a config string as code and never removes
// a node: React owns the page's DOM, so everything is hidden with CSS or neutralized with attributes.
(function () {
  "use strict";

  if (window.__focus) return;

  var LOCK_ATTRIBUTE = "data-focus-lock";
  var ROUTE_ATTRIBUTE = "data-focus-route";
  var HEALTH_HANDLER = "focusHealth";

  var state = {
    config: null,
    route: null,
    loggedIn: false,
    blockedPatterns: [],
    healthDelay: 5000,
    report: { applied: 0, skipped: [] }
  };
  var styleElement = null;
  var healthTimers = [];
  var reported = Object.create(null);

  // ---------------------------------------------------------------- health reporting

  function postHealth(ruleId, reason) {
    var key = ruleId + "|" + location.pathname + "|" + reason;
    if (reported[key]) return;
    reported[key] = true;
    try {
      window.webkit.messageHandlers[HEALTH_HANDLER].postMessage({
        ruleId: ruleId,
        path: location.pathname,
        reason: reason
      });
    } catch (e) {}
  }

  function compile(pattern) {
    try { return new RegExp(pattern); } catch (e) { return null; }
  }

  function scheduleHealthChecks() {
    healthTimers.forEach(clearTimeout);
    healthTimers = [];
    if (!state.config) return;
    var path = location.pathname;
    state.config.rules.forEach(function (rule) {
      var patterns = (rule.expectOn || []).map(compile).filter(Boolean);
      if (!patterns.some(function (regex) { return regex.test(path); })) return;
      healthTimers.push(setTimeout(function () {
        if (location.pathname !== path) return; // the route moved on: nothing to conclude
        try {
          if (document.querySelector(rule.hide) === null) postHealth(rule.id, "nomatch");
        } catch (e) {}
      }, state.healthDelay));
    });
  }

  // ---------------------------------------------------------------- declarative CSS

  function validSelector(selector) {
    try {
      document.createDocumentFragment().querySelector(selector);
      return true;
    } catch (e) {
      return false;
    }
  }

  function scoped(selector, scopes) {
    if (!scopes || scopes.length === 0) return selector;
    var attributes = scopes.map(function (name) {
      return "[" + ROUTE_ATTRIBUTE + "=\"" + name + "\"]";
    });
    return "html:is(" + attributes.join(",") + ") :is(" + selector + ")";
  }

  function ensureStyle() {
    var host = document.documentElement;
    if (!host) return null;
    if (styleElement && styleElement.isConnected) return styleElement;
    styleElement = document.createElement("style");
    styleElement.id = "focus-rules";
    (document.head || host).appendChild(styleElement);
    return styleElement;
  }

  // Returns false while the document is not ready to hold the style element.
  function rebuild() {
    var config = state.config;
    if (!config) return true;
    var style = ensureStyle();
    if (!style || !style.sheet) return false;

    var sheet = style.sheet;
    while (sheet.cssRules.length) sheet.deleteRule(0);
    var report = { applied: 0, skipped: [] };

    // Engine rule: the neutralized reel feed does not scroll.
    try {
      sheet.insertRule("[" + LOCK_ATTRIBUTE + "=\"reel\"] { overflow-y: hidden !important; }", sheet.cssRules.length);
    } catch (e) {}

    config.rules.forEach(function (rule) {
      // Each rule goes in on its own: one invalid selector never breaks the others.
      try {
        if (!validSelector(rule.hide)) throw new Error("invalid selector");
        sheet.insertRule(
          scoped(rule.hide, rule.routeScope) + " { display: none !important; }",
          sheet.cssRules.length
        );
        report.applied++;
      } catch (e) {
        report.skipped.push(rule.id);
        postHealth(rule.id, "invalid");
      }
    });
    state.report = report;
    return true;
  }

  // ---------------------------------------------------------------- click guard

  function isBlockedPath(pathname) {
    return state.blockedPatterns.some(function (regex) { return regex.test(pathname); });
  }

  // Capture phase on the document: it runs before the site's own handlers, so a blocked link
  // never starts a navigation and the site never renders the blocked surface.
  document.addEventListener("click", function (event) {
    if (!state.loggedIn || state.blockedPatterns.length === 0) return;
    var target = event.target;
    if (!target || typeof target.closest !== "function") return;
    var anchor = target.closest("a[href]");
    if (!anchor) return;
    var url;
    try { url = new URL(anchor.href, location.href); } catch (e) { return; }
    if (url.host !== location.host) return;
    if (isBlockedPath(url.pathname)) {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
    }
  }, true);

  // ---------------------------------------------------------------- behavior layer

  // A reel feed scroller: the nearest vertically scrollable ancestor of a video, when that video
  // is a full-size slide and there is more below. A chat with video messages does not qualify
  // (its videos are smaller than the scroller).
  function feedScrollerOf(video) {
    for (var node = video.parentElement; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
      if (node.hasAttribute(LOCK_ATTRIBUTE)) return null;
      if (node.clientHeight === 0 || node.scrollHeight <= node.clientHeight + 1) continue;
      var overflow = getComputedStyle(node).overflowY;
      if (overflow !== "auto" && overflow !== "scroll") continue;
      var box = video.getBoundingClientRect();
      var isFeed = node.scrollHeight >= node.clientHeight * 1.4 &&
        box.height >= node.clientHeight * 0.75 &&
        box.width >= node.clientWidth * 0.9;
      return isFeed ? node : null; // the nearest scroller decides
    }
    return null;
  }

  function lock(scroller) {
    scroller.setAttribute(LOCK_ATTRIBUTE, "reel");
    var top = scroller.scrollTop;
    // The CSS rule stops touch scrolling; this stops scripted scrolling (auto-advance).
    scroller.addEventListener("scroll", function () {
      if (Math.abs(scroller.scrollTop - top) > 1) scroller.scrollTop = top;
    }, { passive: true });
  }

  function scan() {
    var videos = document.querySelectorAll("video");
    for (var i = 0; i < videos.length; i++) {
      var scroller = feedScrollerOf(videos[i]);
      if (scroller) lock(scroller);
    }
  }

  // A vertical drag inside a locked feed does nothing, unless it starts in a nested scroller
  // (a comments list, for example), which must keep working.
  function insideNestedScroller(target, lockedRoot) {
    for (var node = target; node && node !== lockedRoot; node = node.parentElement) {
      if (node.scrollHeight > node.clientHeight + 1) {
        var overflow = getComputedStyle(node).overflowY;
        if (overflow === "auto" || overflow === "scroll") return true;
      }
    }
    return false;
  }

  document.addEventListener("touchmove", function (event) {
    var target = event.target;
    if (!event.cancelable || !target || typeof target.closest !== "function") return;
    var locked = target.closest("[" + LOCK_ATTRIBUTE + "=\"reel\"]");
    if (locked && !insideNestedScroller(target, locked)) event.preventDefault();
  }, { capture: true, passive: false });

  var scanScheduled = false;
  function scheduleScan() {
    if (scanScheduled) return;
    scanScheduled = true;
    var run = function () {
      if (!scanScheduled) return;
      scanScheduled = false;
      scan();
    };
    requestAnimationFrame(run);
    setTimeout(run, 100); // rAF pauses when the page is not being rendered
  }

  var observing = false;
  function startObserving() {
    if (observing || !document.documentElement) return;
    observing = true;
    new MutationObserver(scheduleScan).observe(document.documentElement, { childList: true, subtree: true });
    scheduleScan();
  }

  // ---------------------------------------------------------------- lifecycle

  function applyRouteAttribute() {
    if (state.route && document.documentElement) {
      document.documentElement.setAttribute(ROUTE_ATTRIBUTE, state.route);
    }
  }

  // documentStart can run before <html> exists: retry until the document can hold our style.
  var booting = false;
  function sync() {
    var ready = rebuild();
    applyRouteAttribute();
    startObserving();
    return ready && document.documentElement !== null;
  }

  function boot() {
    if (sync() || booting) return;
    booting = true;
    var observer = new MutationObserver(function () {
      if (sync()) {
        observer.disconnect();
        booting = false;
      }
    });
    observer.observe(document, { childList: true, subtree: true });
  }

  window.__focus = {
    version: 1,

    // (Re)builds the style from `config` and returns { applied, skipped }.
    apply: function (config) {
      state.config = config;
      state.blockedPatterns = [];
      var patterns = (config.routes && config.routes.patterns) || {};
      ((config.routes && config.routes.blocked) || []).forEach(function (kind) {
        (patterns[kind] || []).forEach(function (pattern) {
          var regex = compile(pattern);
          if (regex) state.blockedPatterns.push(regex);
        });
      });
      boot();
      scheduleHealthChecks();
      return state.report;
    },

    // Publishes the current route class as data-focus-route on <html> (not React-owned).
    setRoute: function (name) {
      state.route = String(name).slice(0, 32);
      applyRouteAttribute();
      scheduleHealthChecks();
    },

    // The session cookie is HttpOnly, so native tells the page whether the user is logged in.
    setLoggedIn: function (value) {
      state.loggedIn = value === true;
    },

    // For tests only: the delay is not part of the config.
    setHealthDelay: function (milliseconds) {
      state.healthDelay = milliseconds;
    }
  };
})();
