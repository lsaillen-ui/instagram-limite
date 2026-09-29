// Route hook (documentStart, .page content world, main frame only).
// The site is a single-page app: client-side route changes never reach
// WKNavigationDelegate, so we report location.pathname to native instead.
(function () {
  "use strict";

  if (window.__focusRouteHook) return;
  var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.route;
  if (!bridge) return;
  Object.defineProperty(window, "__focusRouteHook", { value: true });

  function post() {
    try {
      bridge.postMessage(location.pathname);
    } catch (e) {}
  }

  ["pushState", "replaceState"].forEach(function (name) {
    var original = history[name];
    history[name] = function () {
      var result = original.apply(this, arguments);
      post();
      return result;
    };
  });

  window.addEventListener("popstate", post);

  // Initial route, once the document has been parsed (documentEnd equivalent).
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", post, { once: true });
  } else {
    post();
  }
})();
