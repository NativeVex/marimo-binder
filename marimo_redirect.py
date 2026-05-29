import os
from urllib.parse import urlencode

import tornado.web
from jupyter_server.utils import url_path_join


def _load_jupyter_server_extension(server_app):
    web_app = server_app.web_app
    base_url = web_app.settings.get("base_url", "/")
    hub_prefix = os.environ.get("JUPYTERHUB_SERVICE_PREFIX", base_url)
    target = url_path_join(hub_prefix, "proxy/2718/")
    dev_target = url_path_join(hub_prefix, "proxy/2719/")

    class _RedirectToMarimo(tornado.web.RequestHandler):
        def get(self):
            # Preserve the Jupyter Server token query param if present.
            #
            # Why:
            # - On some BinderHub/JupyterHub deployments, the "ready" URL is opened as
            #   /user/<server>/ (optionally with ?token=...). If we drop the token when
            #   redirecting, the user lands on Jupyter Server's /login page instead of
            #   reaching the proxied marimo app.
            # - Under a real JupyterHub-authenticated browser session the token is
            #   irrelevant, so preserving it is harmless.
            token = self.get_query_argument("token", default="")
            dest = target
            if token:
                dest = dest + "?" + urlencode({"token": token})
            self.redirect(dest, permanent=False)

    class _RedirectToMarimoDev(tornado.web.RequestHandler):
        def get(self):
            # Dev/editor entrypoint.
            #
            # Keep the same token-preservation behavior as the root redirect so
            # environments that still rely on a ?token=... query param keep
            # working when the user switches into dev mode.
            token = self.get_query_argument("token", default="")
            dest = dev_target
            if token:
                dest = dest + "?" + urlencode({"token": token})
            self.redirect(dest, permanent=False)

    # Key behavior: redirect the Jupyter Server *root* (/) into the Hub proxy path
    # for marimo. This avoids having to know the runtime user prefix ahead of time.
    #
    # NOTE: we intentionally do NOT try to override /lab here: jupyterlab registers
    # its own handlers early, and trying to “steal” /lab is brittle across versions.
    # Binder’s recommended mechanism for “open a non-lab app” is the Binder link’s
    # `?urlpath=...` query parameter (documented in README/.context.md).
    web_app.add_handlers(
        ".*$",
        [
            (url_path_join(base_url, r"/?"), _RedirectToMarimo),
            (url_path_join(base_url, r"/dev/?"), _RedirectToMarimoDev),
        ],
    )
