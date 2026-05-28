import os

import tornado.web
from jupyter_server.utils import url_path_join


def _load_jupyter_server_extension(server_app):
    web_app = server_app.web_app
    base_url = web_app.settings.get("base_url", "/")
    hub_prefix = os.environ.get("JUPYTERHUB_SERVICE_PREFIX", base_url)
    target = url_path_join(hub_prefix, "proxy/2718/")

    class _RedirectToMarimo(tornado.web.RequestHandler):
        def get(self):
            self.redirect(target, permanent=False)

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
        ],
    )
