// FocusYS — X web filter.
//
// Blocks opening a post's video in the full-screen media viewer
// (/<user>/status/<id>/video/<n>), which on the mobile web is the
// swipe-to-next immersive player. Videos keep playing inline inside posts,
// in the timeline and on the post page. Home, search, profiles and DMs are
// untouched, and nothing is hidden: X's web UI exposes no reliable semantic
// marker that tells "inline" and "immersive" apart other than this route.
(function () {
  "use strict";
  var MESSAGE = "Immersive video blocked";

  function blockReason(url) {
    var s = FocusYS.segments(url);
    if (s.length >= 4 && s[1] === "status" && s[3] === "video") return MESSAGE;
    if (s.length >= 5 && s[0] === "i" && s[2] === "status" && s[4] === "video") return MESSAGE;
    return null;
  }

  function isAuthPage() {
    var s = FocusYS.segments(location);
    return (s[0] === "i" && s[1] === "flow") || s[0] === "login" || s[0] === "account";
  }

  // No DOM changes on X: the core intercepts taps on links to the viewer.
  function scan() {}

  FocusYS.install({ blockReason: blockReason, isAuthPage: isAuthPage, scan: scan });
})();
