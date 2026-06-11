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

  const guestSaveAndAuthSelector = "button, a[href], [role='button'], [aria-label]";
  const labelFor = function (element) {
    return [
      element && element.textContent,
      element && element.innerText,
      element && element.getAttribute && element.getAttribute("aria-label"),
      element && element.getAttribute && element.getAttribute("title"),
    ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
  };
  const isGuestSaveOrAuthControl = function (element) {
    if (!element || !element.matches || !element.getAttribute || !element.matches(guestSaveAndAuthSelector)) {
      return false;
    }
    if (element.getAttribute("data-binder-grist-fenced") === "true") {
      return true;
    }
    const rawHref = element.getAttribute("href") || "";
    const label = labelFor(element);
    return /^(Save Document|Sign in|Sign up)$/i.test(label) || /^\/(signin|login|signup)([/?#]|$)/i.test(rawHref);
  };
  const fenceGuestSaveOrAuthControl = function (element) {
    if (!isGuestSaveOrAuthControl(element)) {
      return false;
    }
    element.setAttribute("data-binder-grist-fenced", "true");
    element.setAttribute("aria-disabled", "true");
    element.setAttribute("tabindex", "-1");
    element.setAttribute("title", "Disabled in this ephemeral Binder Grist sidecar");
    if ("disabled" in element) {
      element.disabled = true;
    }
    if (element.style) {
      element.style.display = "none";
    }
    return true;
  };
  const fenceGuestSaveAndAuthSurfaces = function (root) {
    if (!root) {
      return;
    }
    if (root.matches) {
      fenceGuestSaveOrAuthControl(root);
    }
    if (!root.querySelectorAll) {
      return;
    }
    for (const element of root.querySelectorAll(guestSaveAndAuthSelector)) {
      fenceGuestSaveOrAuthControl(element);
    }
  };

  rewriteAnchors(document);
  fenceGuestSaveAndAuthSurfaces(document);
  document.addEventListener("DOMContentLoaded", function () {
    rewriteAnchors(document);
    fenceGuestSaveAndAuthSurfaces(document);
  });
  document.addEventListener("click", function (event) {
    const target = event && event.target;
    const control = target && target.closest ? target.closest(guestSaveAndAuthSelector) : target;
    if (!fenceGuestSaveOrAuthControl(control)) {
      return;
    }
    if (event.preventDefault) { event.preventDefault(); }
    if (event.stopPropagation) { event.stopPropagation(); }
    if (event.stopImmediatePropagation) { event.stopImmediatePropagation(); }
  }, true);
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
              fenceGuestSaveAndAuthSurfaces(node);
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
          fenceGuestSaveAndAuthSurfaces(mutation.target);
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
