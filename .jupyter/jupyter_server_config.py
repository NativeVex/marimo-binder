import os

from jupyter_server.utils import url_path_join


def _load_jupyter_server_extension(server_app):
    web_app = server_app.web_app
    base_url = web_app.settings.get("base_url", "/")
    hub_prefix = os.environ.get("JUPYTERHUB_SERVICE_PREFIX", base_url)
    target = url_path_join(hub_prefix, "proxy/2718/")

    import tornado.web

    class RootRedirectHandler(tornado.web.RequestHandler):
        def get(self):
            self.redirect(target, permanent=False)

    web_app.add_handlers(".*$", [(url_path_join(base_url, r"/?"), RootRedirectHandler)])


c = get_config()  # noqa: F821
c.ServerApp.jpserver_extensions = {"jupyter_server_config": True}
