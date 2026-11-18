// FocusYS — YouTube web filter (m.youtube.com and www.youtube.com).
//
// Blocks the Shorts tab, Shorts shelves/items on Home, search and channels,
// channel "Shorts" tabs and navigation to /shorts/. Keeps search, channels,
// playlists, subscriptions and normal /watch playback.
//
// Signals used: link paths (/shorts/…) and YouTube's component element
// names (ytm-reel-shelf-renderer, ytm-pivot-bar-item-renderer…), which are
// semantic custom-element tags, not generated CSS classes.
(function () {
  "use strict";
  var MESSAGE = "Short blocked";
  var CHANNEL_PREFIX = { channel: 1, c: 1, user: 1, hashtag: 1 };

  function blockReason(url) {
    var s = FocusYS.segments(url);
    if (!s.length) return null;
    if (s[0] === "shorts") return MESSAGE;
    if (s[0].charAt(0) === "@" && s[1] === "shorts") return MESSAGE;
    if (CHANNEL_PREFIX[s[0]] && s[2] === "shorts") return MESSAGE;
    return null;
  }

  // Whole Shorts shelves.
  var SHELVES = [
    "ytm-reel-shelf-renderer", "ytd-reel-shelf-renderer",
    "ytm-shorts-shelf-renderer", "ytd-shorts-shelf-renderer"
  ].join(",");

  // Generic shelves that may contain only Shorts (hidden only when every
  // video link inside them is a Short).
  var MIXED_SHELVES = [
    "grid-shelf-view-model", "ytm-rich-section-renderer", "ytd-rich-section-renderer",
    "ytd-rich-shelf-renderer", "ytm-item-section-renderer"
  ].join(",");

  // Single items that wrap a Shorts link.
  var ITEMS = [
    "ytm-shorts-lockup-view-model", "ytm-shorts-lockup-view-model-v2",
    "ytd-shorts-lockup-view-model", "ytm-reel-item-renderer", "ytd-reel-item-renderer",
    "ytm-video-with-context-renderer", "ytm-compact-video-renderer", "ytm-rich-item-renderer",
    "ytd-rich-item-renderer", "ytd-video-renderer", "ytd-grid-video-renderer"
  ].join(",");

  // Tabs / navigation entries.
  var TABS = [
    "ytm-pivot-bar-item-renderer", "ytd-guide-entry-renderer", "ytd-mini-guide-entry-renderer",
    "yt-tab-shape", "ytm-tab-renderer", "tp-yt-paper-tab", "[role='tab']"
  ].join(",");

  function isVideoLink(url) {
    var s = FocusYS.segments(url);
    return s[0] === "watch" || s[0] === "shorts";
  }

  // The bottom-bar Shorts entry on m.youtube.com is not always a link; its
  // icon uses the semantic "pivot-shorts" name.
  function shortsPivot(el) {
    var item = el.closest && el.closest("ytm-pivot-bar-item-renderer");
    return item && item.querySelector("[class*='pivot-shorts']") ? item : null;
  }

  function clickReason(el) {
    return shortsPivot(el) ? MESSAGE : null;
  }

  function scan(root, ctx) {
    // 1. Known Shorts shelves.
    if (root.matches && root.matches(SHELVES)) ctx.hide(root);
    root.querySelectorAll(SHELVES).forEach(ctx.hide);

    // 2. Bottom-bar Shorts entry.
    root.querySelectorAll("ytm-pivot-bar-item-renderer [class*='pivot-shorts']").forEach(function (icon) {
      ctx.hide(icon.closest("ytm-pivot-bar-item-renderer"));
    });

    // 3. Every link to a blocked route.
    var links = root.matches && root.matches("a[href]") ? [root] : [];
    links = links.concat(Array.from(root.querySelectorAll("a[href]")));
    var shelvesToCheck = new Set();
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var url = ctx.toURL(a.getAttribute("href"));
      if (!url || !ctx.reasonForURL(url)) continue;
      var tab = a.closest(TABS);
      var item = tab ? null : a.closest(ITEMS);
      ctx.hide(tab || item || a);
      var shelf = a.closest(MIXED_SHELVES);
      if (shelf) shelvesToCheck.add(shelf);
    }

    // 4. Mixed shelves that turned out to be Shorts-only.
    shelvesToCheck.forEach(function (shelf) {
      var videos = Array.from(shelf.querySelectorAll("a[href]")).filter(function (a) {
        var u = ctx.toURL(a.getAttribute("href"));
        return u && isVideoLink(u);
      });
      if (videos.length && videos.every(function (a) {
        return ctx.reasonForURL(ctx.toURL(a.getAttribute("href")));
      })) ctx.hide(shelf);
    });
  }

  // Applied from the first paint (before any scan) so the Shorts tab and
  // shelves never flash while the page is still building.
  var css =
    "ytm-pivot-bar-item-renderer:has([class*='pivot-shorts'])," +
    "ytm-pivot-bar-item-renderer:has(a[href^='/shorts'])," +
    SHELVES + "{display:none!important}";

  FocusYS.install({ blockReason: blockReason, clickReason: clickReason, scan: scan, css: css });
})();
