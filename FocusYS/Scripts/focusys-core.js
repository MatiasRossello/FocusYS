// FocusYS — shared web-layer filter core.
//
// Runs at document start, in the main frame only, inside an isolated
// JavaScript world (WKContentWorld.defaultClient): the page can't see these
// functions or post messages to FocusYS. The DOM is shared, so we can read
// links and hide elements.
//
// Each platform script calls FocusYS.install({...}) with:
//   blockReason(url: URL) -> string | null   route rules (mirror of Swift)
//   scan(root: Element, ctx)                 hide/dim blocked entry points
//   clickReason?(el: Element) -> string|null extra non-link entry points
//   isAuthPage?() -> bool                    extra sign-in detection
//   css?: string                             extra CSS
(function () {
  "use strict";
  if (window.FocusYS) return;

  var cfg = window.__focusysConfig || {};
  var host = location.hostname.toLowerCase();
  var onSite = (cfg.domains || []).some(function (d) {
    return host === d || host.slice(-(d.length + 1)) === "." + d;
  });

  // Inert outside the platform's own domains (e.g. sign-in on google.com).
  if (!onSite) {
    window.FocusYS = { install: function () {} };
    return;
  }

  var HIDDEN = "data-focusys-hidden";
  var DIM = "data-focusys-dim";

  function post(message) {
    try {
      window.webkit.messageHandlers[cfg.handler].postMessage(message);
    } catch (e) { /* handler unavailable */ }
  }

  function segments(url) {
    return url.pathname.split("/").filter(Boolean).map(function (s) {
      return s.toLowerCase();
    });
  }

  function hostIn(url, domains) {
    var h = url.hostname.toLowerCase();
    return domains.some(function (d) {
      return h === d || h.slice(-(d.length + 1)) === "." + d;
    });
  }

  function toURL(href) {
    try { return new URL(href, location.href); } catch (e) { return null; }
  }

  function hide(el) { if (el && !el.hasAttribute(HIDDEN)) el.setAttribute(HIDDEN, ""); }
  function dim(el) { if (el && !el.hasAttribute(DIM)) el.setAttribute(DIM, ""); }

  // Generic sign-in detection: a visible password field or a one-time-code
  // field means we are on a login / verification screen and must not touch it.
  function genericAuthPage() {
    return !!document.querySelector(
      'input[type="password"], input[autocomplete="one-time-code"], input[autocomplete="current-password"]'
    );
  }

  function install(platform) {
    var domains = cfg.domains || [];

    function reasonForURL(url) {
      if (!url || !hostIn(url, domains)) return null;
      return platform.blockReason(url);
    }

    function isAuth() {
      return genericAuthPage() || (platform.isAuthPage ? platform.isAuthPage() : false);
    }

    // ---- CSS ---------------------------------------------------------------
    var style = document.createElement("style");
    style.textContent =
      "[" + HIDDEN + "]{display:none!important}" +
      "[" + DIM + "]{opacity:.35!important;filter:grayscale(1)!important}" +
      (platform.css || "");
    (document.head || document.documentElement).appendChild(style);

    // ---- Tap interception (before the site's own handlers) -----------------
    function onActivate(event) {
      if (isAuth()) return;
      var path = event.composedPath ? event.composedPath() : [event.target];
      // Nearest link or button. A button nested inside a link (mute, menu…)
      // is not a navigation, so it wins and the link is ignored; the native
      // layer still catches any route change such a button might cause.
      var link = null;
      for (var i = 0; i < path.length; i++) {
        var n = path[i];
        if (!n || n.nodeType !== 1) continue;
        if (n.tagName === "A" && n.hasAttribute("href")) { link = n; break; }
        if (n.tagName === "BUTTON" || n.getAttribute("role") === "button") break;
      }

      var reason = link ? reasonForURL(toURL(link.getAttribute("href"))) : null;
      if (!reason && platform.clickReason) {
        var el = event.target && event.target.nodeType === 1 ? event.target : null;
        if (el) reason = platform.clickReason(el);
      }
      if (reason) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (event.type === "click") post({ type: "blocked", message: reason });
      }
    }
    window.addEventListener("click", onActivate, true);
    window.addEventListener("auxclick", onActivate, true);

    // ---- Batched DOM scanning ----------------------------------------------
    var pending = new Set();
    var fullScanPending = true;
    var scheduled = false;
    var lastHref = location.href;
    var ctx = { hide: hide, dim: dim, reasonForURL: reasonForURL, toURL: toURL, segments: segments, location: location };

    function schedule() {
      if (scheduled) return;
      scheduled = true;
      setTimeout(flush, 150);
    }

    function flush() {
      scheduled = false;
      if (location.href !== lastHref) {
        lastHref = location.href;
        fullScanPending = true;
      }
      if (isAuth()) { pending.clear(); return; }
      if (fullScanPending) {
        fullScanPending = false;
        pending.clear();
        if (document.body) platform.scan(document.body, ctx);
        return;
      }
      var roots = Array.from(pending);
      pending.clear();
      for (var i = 0; i < roots.length; i++) {
        var r = roots[i];
        if (r.isConnected) platform.scan(r, ctx);
      }
    }

    var observer = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var rec = records[i];
        if (rec.type === "attributes") {
          if (rec.target.nodeType === 1) pending.add(rec.target);
          continue;
        }
        var added = rec.addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j].nodeType === 1) pending.add(added[j]);
        }
      }
      if (pending.size > 400) { fullScanPending = true; }
      schedule();
    });

    function start() {
      observer.observe(document.documentElement, {
        childList: true, subtree: true, attributes: true, attributeFilter: ["href"]
      });
      fullScanPending = true;
      schedule();
    }

    if (document.documentElement) start();
    else document.addEventListener("DOMContentLoaded", start, { once: true });

    // Same-document route changes (history.pushState is in the page's world,
    // so we check the URL cheaply instead of patching it). The native layer
    // also watches the URL and leaves blocked routes.
    window.addEventListener("popstate", function () { fullScanPending = true; schedule(); });
    setInterval(function () { if (location.href !== lastHref) schedule(); }, 400);
  }

  window.FocusYS = { install: install, segments: segments };
})();
