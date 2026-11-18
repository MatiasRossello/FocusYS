// FocusYS — Instagram web filter.
//
// Blocks entry points to the Reels player: the Reels tab, profile Reels
// tabs, and any link to /reel/… or /reels/… (Home, Explore, profiles, DMs).
// Keeps DMs, profiles and normal posts. In DMs a shared Reel stays visible
// as a message; only opening it is blocked.
(function () {
  "use strict";
  var MESSAGE = "Reel blocked";
  var REEL = { reel: 1, reels: 1 };
  var RESERVED = {
    accounts: 1, challenge: 1, direct: 1, explore: 1, p: 1, stories: 1, about: 1,
    legal: 1, privacy: 1, help: 1, web: 1, api: 1, graphql: 1, oauth: 1, two_factor: 1
  };

  function blockReason(url) {
    var s = FocusYS.segments(url);
    if (!s.length) return null;
    if (REEL[s[0]]) return MESSAGE;
    if (s.length >= 2 && !RESERVED[s[0]] && REEL[s[1]]) return MESSAGE;
    return null;
  }

  function isTab(url) {
    // /reels/ (main tab) or /<user>/reels/ (profile tab): a section, not an item.
    var s = FocusYS.segments(url);
    return (s.length === 1 && s[0] === "reels") ||
           (s.length === 2 && !RESERVED[s[0]] && s[1] === "reels");
  }

  function isAuthPage() {
    var s = FocusYS.segments(location);
    return s[0] === "accounts" || s[0] === "challenge" || s[0] === "two_factor";
  }

  function scan(root, ctx) {
    var inDirect = FocusYS.segments(location)[0] === "direct";
    var links = root.matches && root.matches("a[href]") ? [root] : [];
    links = links.concat(Array.from(root.querySelectorAll("a[href]")));
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var url = ctx.toURL(a.getAttribute("href"));
      if (!url || !ctx.reasonForURL(url)) continue;
      if (isTab(url)) {
        ctx.hide(a);                 // Reels tab / profile Reels tab
      } else if (!inDirect) {
        ctx.dim(a);                  // Reel tile in Home / Explore / profile
      }
      // In DMs the shared Reel message stays fully visible; taps are
      // intercepted by the core.
    }
  }

  // Main Reels tab hidden from the first paint.
  var css = "a[href='/reels/'],a[href='/reels']{display:none!important}";

  FocusYS.install({ blockReason: blockReason, isAuthPage: isAuthPage, scan: scan, css: css });
})();
