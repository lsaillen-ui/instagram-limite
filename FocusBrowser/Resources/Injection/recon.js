// DEBUG-only reconnaissance script (documentStart, focus world, main frame only).
// Never installed in Release. Exposes __focusRecon.snapshot(salt): a compact JSON-safe object
// describing the navigation-relevant structure of the page, with identifying segments redacted
// exactly like PathRedactor.swift does (same salt => same tokens).
// It never reads message text: only paths, aria-labels and element structure.
(function () {
  "use strict";

  if (window.__focusRecon) return;

  var MAX_LINKS = 60;
  var MAX_LABELS = 60;
  var MAX_LABEL_LENGTH = 40;
  var MAX_SCROLLERS = 10;
  var MAX_CHILDREN = 8;

  // Keep in sync with ReservedSegments.swift (PathRedactorTests checks the parity).
  var FIRST_SEGMENTS = [
    "accounts", "direct", "explore", "reels", "reel", "p", "stories", "challenge",
    "about", "legal", "privacy", "terms", "help", "safety", "press", "web", "api", "graphql",
    "directory", "developer", "emails", "oauth", "session", "login", "logout", "download",
    "tv", "tags", "locations", "nametag", "ajax", "static", "data", "cookies", "security",
    "your_activity", "archive", "professional", "ads", "threads"
  ];
  var KNOWN_SUBSEGMENTS = [
    "inbox", "t", "requests", "new", "general", "hidden",
    "search", "tags", "locations", "people",
    "login", "emailsignup", "password", "reset", "onetap", "edit", "activity", "settings",
    "comments", "liked_by", "reels", "reel", "tagged", "saved", "following", "followers",
    "highlights", "audio", "channel", "guides", "feed", "suggested"
  ];

  function toSet(list) {
    var set = Object.create(null);
    list.forEach(function (item) { set[item] = true; });
    return set;
  }
  var firstSet = toSet(FIRST_SEGMENTS);
  var subSet = toSet(KNOWN_SUBSEGMENTS);
  var encoder = new TextEncoder();

  // FNV-1a (32 bit) over salt, a zero byte and the segment, folded to 16 bits.
  function token(salt, segment) {
    var hash = 2166136261;
    var bytes = Array.prototype.slice.call(encoder.encode(salt))
      .concat([0], Array.prototype.slice.call(encoder.encode(segment)));
    for (var i = 0; i < bytes.length; i++) {
      hash = Math.imul((hash ^ bytes[i]) >>> 0, 16777619) >>> 0;
    }
    var folded = ((hash ^ (hash >>> 16)) & 0xffff).toString(16);
    return "#" + ("0000" + folded).slice(-4);
  }

  function redactPath(path, salt) {
    var cut = path.search(/[?#]/);
    var pathOnly = cut === -1 ? path : path.slice(0, cut);
    var segments = pathOnly.split("/").slice(1);
    var out = [""];
    segments.forEach(function (segment, index) {
      var lower = segment.toLowerCase();
      if (segment === "") {
        out.push("");
      } else if (index === 0) {
        out.push(firstSet[lower] ? segment : "@" + token(salt, segment));
      } else {
        out.push(subSet[lower] ? segment : token(salt, segment));
      }
    });
    return out.join("/");
  }

  function redactHref(href, salt) {
    try {
      var url = new URL(href, location.href);
      var suffix = url.search ? "?" : "";
      if (url.host === location.host) return redactPath(url.pathname, salt) + suffix;
      return url.host + "/…" + suffix; // external: host only, path and query dropped
    } catch (e) {
      return "(unparsable)";
    }
  }

  // Usernames seen in profile hrefs since the page loaded (a single-page app keeps this alive
  // across snapshots). Labels mentioning them are masked with the same token the path gets.
  var knownNames = Object.create(null);
  var currentSalt = "";

  function learnNames() {
    var anchors = document.querySelectorAll("a[href]");
    for (var i = 0; i < anchors.length; i++) {
      var href = anchors[i].getAttribute("href") || "";
      var match = /^\/([A-Za-z0-9._]{3,30})(?:\/|$)/.exec(href);
      if (match && !firstSet[match[1].toLowerCase()]) knownNames[match[1]] = true;
    }
  }

  function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  // "React to message from bob" carries a name the hrefs of the page may not (your own account).
  var NAME_AFTER = /(message from |profile page of |story by |photo by |video by |reel by |photo shared by |options for message from )([^\s,]+)/gi;
  var NAME_BEFORE_REELS = /^(\S+) reels$/i;
  var HIGHLIGHT = /^(View ).+( highlight)$/i;

  function maskLabel(text) {
    var out = String(text);
    var names = Object.keys(knownNames);
    if (names.length) {
      var alternation = names.map(escapeRegExp).join("|");
      out = out.replace(
        new RegExp("(^|[^A-Za-z0-9._])(" + alternation + ")(?![A-Za-z0-9._])", "g"),
        function (all, before, name) { return before + "@" + token(currentSalt, name); }
      );
    }
    out = out.replace(NAME_AFTER, function (all, prefix, name) {
      return name.charAt(0) === "@" ? all : prefix + "@" + token(currentSalt, name);
    });
    out = out.replace(NAME_BEFORE_REELS, function (all, name) {
      return name.charAt(0) === "@" ? all : "@" + token(currentSalt, name) + " reels";
    });
    out = out.replace(HIGHLIGHT, "$1#highlight$2");
    return out;
  }

  function clip(text) {
    return maskLabel(String(text)).replace(/\s+/g, " ").trim().slice(0, MAX_LABEL_LENGTH);
  }

  function labelOf(element) {
    var own = element.getAttribute("aria-label");
    if (own) return clip(own);
    var icon = element.querySelector && element.querySelector("svg[aria-label]");
    return icon ? clip(icon.getAttribute("aria-label")) : "";
  }

  function contextOf(element) {
    var context = [];
    if (element.closest("nav, [role='navigation']")) context.push("nav");
    if (element.closest("[role='dialog']")) context.push("dialog");
    if (element.closest("main")) context.push("main");
    return context;
  }

  function links(salt) {
    var seen = Object.create(null);
    var found = [];
    var anchors = document.querySelectorAll("a[href]");
    for (var i = 0; i < anchors.length; i++) {
      var href = redactHref(anchors[i].getAttribute("href"), salt);
      if (seen[href]) continue;
      seen[href] = true;
      var context = contextOf(anchors[i]);
      var label = labelOf(anchors[i]);
      var entry = { href: href };
      if (label) entry.label = label;
      if (context.length) entry.in = context;
      found.push(entry);
    }
    // A long inbox would fill the cap before the navigation bar: keep nav, dialog and main first.
    function rank(entry) {
      var context = entry.in || [];
      if (context.indexOf("nav") !== -1) return 0;
      if (context.indexOf("dialog") !== -1) return 1;
      if (context.indexOf("main") !== -1) return 2;
      return 3;
    }
    return found
      .map(function (entry, index) { return { entry: entry, index: index }; })
      .sort(function (a, b) { return rank(a.entry) - rank(b.entry) || a.index - b.index; })
      .slice(0, MAX_LINKS)
      .map(function (item) { return item.entry; });
  }

  function labels() {
    var seen = Object.create(null);
    var found = [];
    var elements = document.querySelectorAll(
      "button[aria-label], [role='button'][aria-label], a[aria-label], svg[aria-label]"
    );
    for (var i = 0; i < elements.length && found.length < MAX_LABELS; i++) {
      var text = clip(elements[i].getAttribute("aria-label"));
      if (!text) continue;
      var key = elements[i].tagName.toLowerCase() + ":" + text;
      if (seen[key]) continue;
      seen[key] = true;
      found.push(key);
    }
    return found;
  }

  function describe(element, depth) {
    var node = { tag: element.tagName.toLowerCase() };
    var role = element.getAttribute("role");
    if (role) node.role = role;
    if (depth > 0 && element.children.length) {
      node.children = Array.prototype.slice.call(element.children, 0, MAX_CHILDREN)
        .map(function (child) { return describe(child, depth - 1); });
    }
    return node;
  }

  function dialogs() {
    var elements = document.querySelectorAll("[role='dialog']");
    return {
      count: elements.length,
      structure: Array.prototype.slice.call(elements, 0, 5).map(function (element) {
        return describe(element, 2);
      })
    };
  }

  // Up to 8 ancestors, nearest first: tag[role], plus @fixed / @abs for positioned ones. This is
  // what tells a full-screen overlay apart from the page, and gives a structural anchor.
  function ancestorsOf(element) {
    var chain = [];
    for (var node = element.parentElement; node && chain.length < 8; node = node.parentElement) {
      var text = node.tagName.toLowerCase();
      var role = node.getAttribute("role");
      if (role) text += "[" + role + "]";
      var position = getComputedStyle(node).position;
      if (position === "fixed") text += "@fixed";
      else if (position === "absolute") text += "@abs";
      chain.push(text);
    }
    return chain;
  }

  function depthOf(element) {
    var depth = 0;
    for (var node = element.parentElement; node; node = node.parentElement) depth++;
    return depth;
  }

  function scrollers() {
    var found = [];
    var all = document.querySelectorAll("*");
    for (var i = 0; i < all.length; i++) {
      var element = all[i];
      if (element.clientHeight === 0 || element.scrollHeight <= element.clientHeight + 1) continue;
      // A feed the engine locked is `overflow-y: hidden` now, but it is still the scroller we want to see.
      var locked = element.hasAttribute("data-focus-lock");
      var overflow = getComputedStyle(element).overflowY;
      if (!locked && overflow !== "auto" && overflow !== "scroll") continue;
      var entry = {
        tag: element.tagName.toLowerCase(),
        depth: depthOf(element),
        size: element.clientWidth + "x" + element.clientHeight,
        scrollTop: Math.round(element.scrollTop),
        scrollHeight: element.scrollHeight,
        video: element.querySelector("video") !== null,
        ancestors: ancestorsOf(element),
        children: element.children.length
      };
      if (locked) entry.locked = true;
      var videoChildren = 0;
      for (var c = 0; c < element.children.length; c++) {
        if (element.children[c].querySelector("video")) videoChildren++;
      }
      if (videoChildren) entry.videoChildren = videoChildren;
      var role = element.getAttribute("role");
      if (role) entry.role = role;
      var label = element.getAttribute("aria-label");
      if (label) entry.label = clip(label);
      entry.area = element.clientWidth * element.clientHeight;
      found.push(entry);
    }
    return found
      .sort(function (a, b) { return b.area - a.area; })
      .slice(0, MAX_SCROLLERS)
      .map(function (entry) { delete entry.area; return entry; });
  }

  // Fixed-position elements covering most of the viewport: how a full-screen overlay (for example
  // a reel opened from a conversation) shows up when the URL does not change.
  function overlays() {
    var found = [];
    var all = document.querySelectorAll("body *");
    var width = window.innerWidth;
    var height = window.innerHeight;
    for (var i = 0; i < all.length; i++) {
      var element = all[i];
      if (getComputedStyle(element).position !== "fixed") continue;
      var rect = element.getBoundingClientRect();
      if (rect.width < width * 0.8 || rect.height < height * 0.6) continue;
      var entry = {
        tag: element.tagName.toLowerCase(),
        depth: depthOf(element),
        size: Math.round(rect.width) + "x" + Math.round(rect.height),
        video: element.querySelector("video") !== null,
        zIndex: getComputedStyle(element).zIndex
      };
      var role = element.getAttribute("role");
      if (role) entry.role = role;
      var label = element.getAttribute("aria-label");
      if (label) entry.label = clip(label);
      found.push(entry);
      if (found.length >= 5) break;
    }
    return found;
  }

  function videos() {
    var all = document.querySelectorAll("video");
    var playing = 0;
    var inView = -1; // index of the video covering the middle of the viewport
    var middleX = window.innerWidth / 2;
    var middleY = window.innerHeight / 2;
    for (var i = 0; i < all.length; i++) {
      if (!all[i].paused && !all[i].ended && all[i].readyState > 2) playing++;
      var rect = all[i].getBoundingClientRect();
      if (inView === -1 && rect.left <= middleX && rect.right >= middleX && rect.top <= middleY && rect.bottom >= middleY) {
        inView = i;
      }
    }
    return { count: all.length, playing: playing, inView: inView };
  }

  function section(build) {
    try {
      return build();
    } catch (error) {
      return { error: String(error && error.message || error).slice(0, 80) };
    }
  }

  window.__focusRecon = {
    redactPath: redactPath,
    maskLabel: function (text, salt) { currentSalt = String(salt); return maskLabel(text); },
    learnNames: learnNames,
    snapshot: function (salt) {
      salt = String(salt);
      currentSalt = salt;
      learnNames();
      return {
        path: redactPath(location.pathname, salt),
        historyLength: history.length,
        links: section(function () { return links(salt); }),
        labels: section(labels),
        dialogs: section(dialogs),
        scrollers: section(scrollers),
        overlays: section(overlays),
        videos: section(videos)
      };
    }
  };
})();
