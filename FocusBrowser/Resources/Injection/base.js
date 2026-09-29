// Base user script (documentStart, focus content world, main frame only).
// Forces a fixed viewport and installs the base CSS. It never removes page nodes.
(function () {
  "use strict";

  var VIEWPORT = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover";
  var CSS =
    "html, body { overscroll-behavior: none; } " +
    "body { touch-action: manipulation; } " +
    "input, textarea { font-size: 16px !important; }";

  var headObserver = null;

  function installStyle(root) {
    if (document.getElementById("focus-base-style")) return;
    var style = document.createElement("style");
    style.id = "focus-base-style";
    style.textContent = CSS;
    root.appendChild(style);
  }

  function forceViewport(head) {
    var metas = head.querySelectorAll('meta[name="viewport"]');
    if (metas.length === 0) {
      var meta = document.createElement("meta");
      meta.setAttribute("name", "viewport");
      meta.setAttribute("content", VIEWPORT);
      head.appendChild(meta);
      return;
    }
    for (var i = 0; i < metas.length; i++) {
      if (metas[i].getAttribute("content") !== VIEWPORT) {
        metas[i].setAttribute("content", VIEWPORT);
      }
    }
  }

  // Returns true once <head> exists and everything is installed.
  function sync() {
    var root = document.documentElement;
    if (!root) return false;
    installStyle(root);
    var head = document.head;
    if (!head) return false;
    forceViewport(head);
    if (!headObserver) {
      // Head only: mutations there are rare, so this stays cheap.
      headObserver = new MutationObserver(function () { forceViewport(head); });
      headObserver.observe(head, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["content"]
      });
    }
    return true;
  }

  if (!sync()) {
    var boot = new MutationObserver(function () {
      if (sync()) boot.disconnect();
    });
    boot.observe(document, { childList: true, subtree: true });
  }
})();
