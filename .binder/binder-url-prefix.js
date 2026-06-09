(function () {
  const match = window.location.pathname.match(/^(\/user\/[^/]+\/proxy\/[^/]+)(?:\/|$)/);
  if (!match) {
    return;
  }
  const proxyPrefix = match[1];

  const rewrite = function (href) {
    const url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin) {
      return href;
    }

    const escapedDocWorker = url.pathname.match(/^\/dw\/self\/v\/([^/]+)(\/user\/[^/]+\/proxy\/[^/]+)(\/.*)$/);
    if (escapedDocWorker) {
      url.pathname = `${escapedDocWorker[2]}/dw/self/v/${escapedDocWorker[1]}${escapedDocWorker[3]}`;
      return url.href;
    }

    if (url.pathname.startsWith(proxyPrefix + "/")) {
      return href;
    }
    if (url.pathname.startsWith("/user/") || url.pathname.startsWith("/hub/")) {
      return href;
    }
    url.pathname = proxyPrefix + (url.pathname.startsWith("/") ? url.pathname : "/" + url.pathname);
    return url.href;
  };

  const rewriteAnchors = function (root) {
    if (!root || !root.querySelectorAll) {
      return;
    }
    for (const anchor of root.querySelectorAll("a[href]")) {
      const rawHref = anchor.getAttribute("href");
      if (!rawHref) {
        continue;
      }
      const rewritten = rewrite(rawHref);
      if (rewritten !== rawHref) {
        anchor.setAttribute("href", rewritten);
      }
    }
  };

  rewriteAnchors(document);
  document.addEventListener("DOMContentLoaded", function () {
    rewriteAnchors(document);
  });
  if (window.MutationObserver) {
    new window.MutationObserver(function (mutations) {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          for (const node of mutation.addedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) {
              if (node.matches && node.matches("a[href]")) {
                const rawHref = node.getAttribute("href");
                if (rawHref) {
                  const rewritten = rewrite(rawHref);
                  if (rewritten !== rawHref) {
                    node.setAttribute("href", rewritten);
                  }
                }
              }
              rewriteAnchors(node);
            }
          }
        } else if (mutation.type === "attributes" && mutation.target && mutation.target.matches("a[href]")) {
          const rawHref = mutation.target.getAttribute("href");
          if (rawHref) {
            const rewritten = rewrite(rawHref);
            if (rewritten !== rawHref) {
              mutation.target.setAttribute("href", rewritten);
            }
          }
        }
      }
    }).observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["href"],
    });
  }

  const patchDocWorkerResponse = async function (response, requestUrl) {
    if (!requestUrl.pathname.includes("/api/worker/")) {
      return response;
    }
    try {
      const data = await response.clone().json();
      if (!data || !data.selfPrefix || data.docWorkerUrl) {
        return response;
      }

      const workerPath = requestUrl.pathname.match(/^(\/user\/[^/]+\/proxy\/[^/]+)(\/.*)\/api\/worker\/[^/]+$/);
      if (!workerPath) {
        return response;
      }

      data.docWorkerUrl = `${requestUrl.origin}${workerPath[1]}${data.selfPrefix}${workerPath[2]}`;
      data.selfPrefix = null;
      const headers = new Headers(response.headers);
      headers.set("content-type", "application/json");
      return new Response(JSON.stringify(data), {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    } catch (_err) {
      return response;
    }
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

  const originalFetch = window.fetch && window.fetch.bind(window);
  if (originalFetch) {
    window.fetch = async function (input, init) {
      let request = input;
      if (typeof input === "string" || input instanceof URL) {
        request = rewrite(input);
      } else if (input && typeof input.url === "string") {
        const rewritten = rewrite(input.url);
        if (rewritten !== input.url) {
          request = new Request(rewritten, input);
        }
      }
      const response = await originalFetch(request, init);
      const requestUrl = new URL(
        (typeof request === "string" || request instanceof URL) ? request : request.url,
        window.location.href,
      );
      return patchDocWorkerResponse(response, requestUrl);
    };
  }

  if (window.XMLHttpRequest) {
    const originalOpen = window.XMLHttpRequest.prototype.open;
    window.XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      return originalOpen.call(this, method, rewrite(url), ...rest);
    };
  }

  if (window.WebSocket) {
    const OriginalWebSocket = window.WebSocket;
    window.WebSocket = function (url, protocols) {
      return protocols === undefined ? new OriginalWebSocket(rewrite(url)) : new OriginalWebSocket(rewrite(url), protocols);
    };
    window.WebSocket.prototype = OriginalWebSocket.prototype;
    for (const key of ["CONNECTING", "OPEN", "CLOSING", "CLOSED"]) {
      window.WebSocket[key] = OriginalWebSocket[key];
    }
  }

  if (window.EventSource) {
    const OriginalEventSource = window.EventSource;
    window.EventSource = function (url, config) {
      return new OriginalEventSource(rewrite(url), config);
    };
    window.EventSource.prototype = OriginalEventSource.prototype;
  }
}());
