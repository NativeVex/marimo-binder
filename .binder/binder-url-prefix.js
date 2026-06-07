(function () {
  const match = window.location.pathname.match(/^(\/user\/[^/]+\/proxy\/[^/]+)(?:\/|$)/);
  if (!match) {
    return;
  }
  const proxyPrefix = match[1];
  const rewrite = function (href) {
    const url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin || url.pathname.startsWith(proxyPrefix + "/")) {
      return href;
    }
    if (url.pathname.startsWith("/user/") || url.pathname.startsWith("/hub/")) {
      return href;
    }
    url.pathname = proxyPrefix + (url.pathname.startsWith("/") ? url.pathname : "/" + url.pathname);
    return url.href;
  };

  window._urlStateLoadPage = function (href) {
    window.location.href = rewrite(href);
  };

  for (const method of ["pushState", "replaceState"]) {
    const original = window.history[method];
    window.history[method] = function (state, title, url) {
      if (url !== undefined && url !== null) {
        url = rewrite(url);
      }
      return original.call(this, state, title, url);
    };
  }
}());
