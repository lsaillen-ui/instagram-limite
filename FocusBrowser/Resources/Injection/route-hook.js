// Route hook (documentStart, .page content world, main frame only).
// The site is a single-page app: client-side route changes never reach
// WKNavigationDelegate, so we report location.pathname to native instead.
// Payload: { path, kind } with kind one of push, replace, pop, initial.
(function () {
  "use strict";

  if (window.__focusRouteHook) return;
  var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.route;
  if (!bridge) return;
  Object.defineProperty(window, "__focusRouteHook", { value: true });

  function post(kind) {
    try {
      bridge.postMessage({ path: location.pathname, kind: kind });
    } catch (e) {}
  }

  ["pushState", "replaceState"].forEach(function (name) {
    var original = history[name];
    var kind = name === "pushState" ? "push" : "replace";
    history[name] = function () {
      var result = original.apply(this, arguments);
      post(kind);
      return result;
    };
  });

  window.addEventListener("popstate", function () { post("pop"); });

  // Initial route, once the document has been parsed (documentEnd equivalent).
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { post("initial"); }, { once: true });
  } else {
    post("initial");
  }
})();
