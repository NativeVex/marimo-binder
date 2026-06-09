from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class EmbeddedGristContractTest(unittest.TestCase):
    def test_binder_dockerfile_is_the_repo2docker_source_of_truth(self) -> None:
        binder_dockerfile = read_text(".binder/Dockerfile")
        root_dockerfile = read_text("Dockerfile")
        workflow = read_text(".github/workflows/ci.yaml")
        docker_build = read_text("scripts/docker-build.sh")
        docker_smoke = read_text("scripts/docker-smoke.sh")

        # When a `.binder/` directory exists, repo2docker discovers Dockerfile
        # via `.binder/Dockerfile`; a root-level Dockerfile alone is ignored by
        # BinderHub's standard repo2docker path.
        self.assertEqual(binder_dockerfile, root_dockerfile)
        self.assertIn("docker build -f .binder/Dockerfile", workflow)
        self.assertIn("DOCKERFILE=${DOCKERFILE:-.binder/Dockerfile}", docker_build)
        self.assertIn("docker build -f \"${DOCKERFILE}\"", docker_build)
        self.assertIn("DOCKERFILE=${DOCKERFILE:-.binder/Dockerfile}", docker_smoke)
        self.assertIn("docker build -f \"${DOCKERFILE}\"", docker_smoke)

    def test_dockerfile_uses_lightweight_default_base(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")
        readme = read_text("README.md")
        context = read_text(".context.md")

        self.assertIn("ARG JUPYTER_BASE_IMAGE=quay.io/jupyterhub/jupyterhub:5.4.6", dockerfile)
        self.assertIn("FROM ${JUPYTER_BASE_IMAGE}", dockerfile)
        self.assertNotIn("quay.io/jupyter/pyspark-notebook:latest", dockerfile)
        self.assertIn("quay.io/jupyterhub/jupyterhub:5.4.6", readme)
        self.assertIn("quay.io/jupyterhub/jupyterhub:5.4.6", context)
        self.assertIn("PySpark", readme)
        self.assertIn("PySpark", context)

    def test_public_repo_files_do_not_reference_private_project_context(self) -> None:
        private_context = re.compile(
            "|".join(
                [
                    re.escape("/mnt/" + "interop"),
                    r"/home/(?!jovyan\b)[A-Za-z0-9._-]+",
                    "env" + "_file",
                ]
            ),
            re.IGNORECASE,
        )
        for relative_path in [
            "Dockerfile",
            ".binder/Dockerfile",
            ".binder/start",
            ".github/workflows/ci.yaml",
            "README.md",
            ".context.md",
            "scripts/docker-build.sh",
            "scripts/docker-smoke.sh",
            "scripts/grist-runtime-smoke.sh",
        ]:
            with self.subTest(relative_path=relative_path):
                self.assertIsNone(private_context.search(read_text(relative_path)))

    def test_dockerfile_embeds_pinned_grist_runtime(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")

        self.assertIn("FROM gristlabs/grist:1.7.14 AS grist", dockerfile)
        self.assertIn("COPY --from=grist /grist /grist", dockerfile)
        self.assertIn("mkdir -p /grist/static", dockerfile)
        self.assertIn("COPY .binder/binder-url-prefix.js /grist/static/binder-url-prefix.js", dockerfile)
        self.assertIn("COPY --from=grist /node_modules /node_modules", dockerfile)
        self.assertIn("COPY --from=grist /usr/local/bin/node /usr/local/bin/node", dockerfile)
        self.assertIn("/grist/sandbox/pyodide", dockerfile)
        self.assertIn("/grist/node_modules/typescript", dockerfile)
        self.assertIn("-name '*.map'", dockerfile)
        self.assertIn("-name '*.d.ts'", dockerfile)
        self.assertIn("-name '*.tsbuildinfo'", dockerfile)
        self.assertIn("-name test", dockerfile)
        self.assertIn("-name __tests__", dockerfile)
        self.assertIn("GRIST_IN_SERVICE=true", dockerfile)
        self.assertIn("GRIST_DATA_DIR=/home/jovyan/grist-persist/docs", dockerfile)
        self.assertIn("TYPEORM_DATABASE=/home/jovyan/grist-persist/home.sqlite3", dockerfile)
        self.assertIn("GRIST_SINGLE_ORG=docs", dockerfile)

    def test_dockerfile_installs_grist_runtime_sandbox_python_deps(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")

        # Creating or importing documents exercises Grist's Python sandbox,
        # whose code is copied from the upstream Grist image.  The final
        # JupyterHub base image must also install the runtime sandbox deps;
        # otherwise the UI can load but document creation fails when
        # /grist/sandbox/grist imports modules such as iso8601, astroid, and
        # friendly_traceback.
        # Do not install the whole upstream sandbox requirements file: it pins
        # old typing/debug packages that downgrade JupyterHub/IPython deps.
        self.assertIn("COPY --from=grist /grist /grist", dockerfile)
        self.assertNotIn("-r /grist/sandbox/requirements.txt", dockerfile)
        for requirement in [
            "iso8601==0.1.12",
            "astroid==2.14.2",
            "friendly-traceback==0.7.48",
            "sortedcontainers==2.4.0",
            "openpyxl==3.0.10",
            "phonenumberslite==8.12.57",
            "chardet==5.1.0",
            "roman==3.3",
        ]:
            self.assertIn(requirement, dockerfile)

    def test_smoke_script_checks_grist_sandbox_imports(self) -> None:
        smoke = read_text("scripts/docker-smoke.sh")

        self.assertIn("cd /grist/sandbox/grist", smoke)
        self.assertIn("import iso8601", smoke)
        self.assertIn("import astroid", smoke)
        self.assertIn("import friendly_traceback", smoke)
        self.assertIn("import actions", smoke)
        self.assertIn("import codebuilder", smoke)
        self.assertIn("/o/docs/api/docs", smoke)
        self.assertIn("document create status", smoke)

    def test_dockerfile_handles_repo2docker_uid_collision(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")

        # BinderHub/repo2docker commonly injects NB_UID=1000.  Some base images
        # already ship an account at that UID, so the Dockerfile must
        # reuse/rename existing identities instead of blindly adding another
        # UID 1000 account.
        self.assertIn("ARG NB_UID=1000", dockerfile)
        self.assertIn('existing_for_uid="$(getent passwd "${NB_UID}"', dockerfile)
        self.assertIn("usermod --login", dockerfile)
        self.assertIn("--move-home", dockerfile)
        self.assertIn("adduser --disabled-password", dockerfile)

    def test_start_script_launches_grist_with_binder_safe_defaults(self) -> None:
        start = read_text(".binder/start")
        prefix_hook = read_text(".binder/binder-url-prefix.js")

        self.assertIn('APP_NOTEBOOK="${MARIMO_APP:-marimo_app.py}"', start)
        self.assertIn("GRIST_PORT=\"${GRIST_PORT:-8484}\"", start)
        self.assertIn("GRIST_IN_SERVICE=\"${GRIST_IN_SERVICE:-true}\"", start)
        self.assertIn("GRIST_DEFAULT_EMAIL=\"${GRIST_DEFAULT_EMAIL:-jovyan@example.invalid}\"", start)
        self.assertIn("GRIST_SINGLE_ORG=\"${GRIST_SINGLE_ORG:-docs}\"", start)
        self.assertIn('export PORT="${GRIST_PORT}"', start)
        self.assertIn("export GRIST_INST_DIR GRIST_HOST GRIST_ORG_IN_PATH GRIST_SINGLE_ORG GRIST_SINGLE_PORT", start)
        self.assertIn("GRIST_PROXY_URL=\"${JUPYTERHUB_PUBLIC_URL%/}/proxy/${GRIST_PORT}\"", start)
        self.assertIn("GRIST_PROXY_URL=\"${JUPYTERHUB_HOST%/}${JUPYTERHUB_SERVICE_PREFIX%/}/proxy/${GRIST_PORT}\"", start)
        self.assertIn("GRIST_PROXY_URL=\"${JUPYTERHUB_SERVICE_URL%/}/proxy/${GRIST_PORT}\"", start)
        self.assertIn("APP_HOME_URL=\"${GRIST_PROXY_URL%/}/o/${GRIST_SINGLE_ORG}\"", start)
        self.assertIn("mybinder.org exposes neither JUPYTERHUB_PUBLIC_URL nor JUPYTERHUB_HOST", start)
        self.assertIn('APP_STATIC_URL="${GRIST_PROXY_URL%/}"', start)
        self.assertIn('APP_STATIC_URL="${APP_STATIC_URL%/o/${GRIST_SINGLE_ORG}}"', start)
        self.assertIn("binder-url-prefix.js", start)
        self.assertIn('GRIST_INCLUDE_CUSTOM_SCRIPT_URL="${APP_STATIC_URL%/}/v/unknown/binder-url-prefix.js"', start)
        self.assertIn('APP_HOME_INTERNAL_URL="${APP_HOME_INTERNAL_URL:-http://127.0.0.1:${GRIST_PORT}}"', start)
        self.assertNotIn("cat > /grist/static/binder-url-prefix.js", start)
        self.assertNotIn("mkdir -p /grist/static", start)
        self.assertIn("window._urlStateLoadPage", prefix_hook)
        self.assertIn("/user\\/[^/]+\\/proxy\\/[^/]+", prefix_hook)
        self.assertIn("pushState", prefix_hook)
        self.assertIn("replaceState", prefix_hook)
        self.assertIn("querySelectorAll(\"a[href]\")", prefix_hook)
        self.assertIn("MutationObserver", prefix_hook)
        self.assertIn("/api/worker/", prefix_hook)
        self.assertIn("docWorkerUrl", prefix_hook)
        self.assertIn("selfPrefix = null", prefix_hook)
        self.assertIn("XMLHttpRequest", prefix_hook)
        self.assertIn("WebSocket", prefix_hook)
        self.assertIn("export APP_HOME_URL APP_HOME_INTERNAL_URL APP_STATIC_URL GRIST_INCLUDE_CUSTOM_SCRIPT_URL", start)
        self.assertIn("cd /grist && ./sandbox/run.sh", start)
        self.assertRegex(start, re.compile(r"\n\) &", re.MULTILINE))
        self.assertIn("port 8484", start)

    def test_prefix_hook_rewrites_root_origin_anchor_hrefs(self) -> None:
        script = r'''
const fs = require("fs");
const vm = require("vm");
const hook = fs.readFileSync(process.argv[1], "utf8");
let observerCallback = null;
function anchor(href) {
  return {
    nodeType: 1,
    attrs: {href},
    getAttribute(name) { return this.attrs[name]; },
    setAttribute(name, value) { this.attrs[name] = value; },
    matches(selector) { return selector === "a[href]"; },
    querySelectorAll() { return []; },
  };
}
const initialRootAnchor = anchor("/doc/new~abc");
const initialProxyAnchor = anchor("/user/test/proxy/8484/doc/keep");
const document = {
  documentElement: {},
  querySelectorAll(selector) { return selector === "a[href]" ? [initialRootAnchor, initialProxyAnchor] : []; },
  addEventListener() {},
};
const context = {
  URL,
  Headers,
  Request,
  Response,
  Node: {ELEMENT_NODE: 1},
  document,
  window: {
    location: new URL("https://jupyterhub.saucy.haus/user/test/proxy/8484/o/docs/"),
    history: {pushState() {}, replaceState() {}},
    MutationObserver: class {
      constructor(callback) { observerCallback = callback; }
      observe() {}
    },
  },
};
vm.runInNewContext(hook, context, {filename: "binder-url-prefix.js"});
if (initialRootAnchor.attrs.href !== "https://jupyterhub.saucy.haus/user/test/proxy/8484/doc/new~abc") {
  throw new Error("root anchor was not rewritten: " + initialRootAnchor.attrs.href);
}
if (initialProxyAnchor.attrs.href !== "/user/test/proxy/8484/doc/keep") {
  throw new Error("proxied anchor should remain unchanged: " + initialProxyAnchor.attrs.href);
}
const dynamicRootAnchor = anchor("/o/docs/api/docs");
observerCallback([{type: "childList", addedNodes: [dynamicRootAnchor]}]);
if (dynamicRootAnchor.attrs.href !== "https://jupyterhub.saucy.haus/user/test/proxy/8484/o/docs/api/docs") {
  throw new Error("dynamic root anchor was not rewritten: " + dynamicRootAnchor.attrs.href);
}
'''
        subprocess.run(
            ["node", "-e", script, str(ROOT / ".binder/binder-url-prefix.js")],
            check=True,
            cwd=ROOT,
        )

    def test_redirect_extension_exposes_grist_entrypoint(self) -> None:
        redirect = read_text("marimo_redirect.py")

        self.assertIn('grist_target = url_path_join(hub_prefix, "proxy/8484/o/docs/")', redirect)
        self.assertIn('url_path_join(base_url, r"/grist/?")', redirect)
        self.assertIn("_RedirectToGrist", redirect)

    def test_docs_use_grist_docs_subpath_not_proxy_root(self) -> None:
        readme = read_text("README.md")
        workflow = read_text(".github/workflows/ci.yaml")

        self.assertIn("urlpath=proxy%2F8484%2Fo%2Fdocs%2F", readme)
        self.assertIn("urlpath=proxy%2F8484%2Fo%2Fdocs%2F", workflow)

    def test_smoke_script_checks_grist_process_and_http_health(self) -> None:
        smoke = read_text("scripts/docker-smoke.sh")

        self.assertIn("gristlabs/grist 1.7.14", smoke)
        self.assertIn("marimo run marimo_app.py", smoke)
        self.assertIn("marimo edit marimo_app.py", smoke)
        self.assertIn("grep -F \"node _build/stubs/app/server/server.js\"", smoke)
        self.assertIn("http://127.0.0.1:8484", smoke)
        self.assertIn("/o/docs/", smoke)
        self.assertIn("JUPYTERHUB_SERVICE_URL=https://jupyterhub-internal.example.invalid/user/test/", smoke)
        self.assertIn("APP_STATIC_URL=http://127.0.0.1:8484", smoke)
        self.assertIn("APP_HOME_INTERNAL_URL=http://127.0.0.1:8484", smoke)
        self.assertIn('const baseHref = match && match[1];', smoke)
        self.assertIn('const homeUrl = configMatch && JSON.parse(configMatch[1]).homeUrl;', smoke)
        self.assertIn('/proxy/8484/o/docs', smoke)
        self.assertIn('main.bundle.js', smoke)
        self.assertIn('asset status', smoke)
        self.assertIn('binder-url-prefix.js', smoke)
        self.assertIn('custom script status', smoke)
        self.assertIn('_urlStateLoadPage', smoke)
        self.assertIn('Host: "public-binderhub.example.invalid"', smoke)
        self.assertIn('"X-Forwarded-Proto": "https,http"', smoke)
        self.assertIn("contains_grist", smoke)
        self.assertIn("/home/jovyan/.binder/start true", smoke)
        self.assertIn("BOOT KEY: )[[:alnum:]]+", smoke)
        self.assertIn("[REDACTED]", smoke)

    def test_default_requirements_stay_lightweight(self) -> None:
        requirements = read_text("requirements.txt")
        heavy_requirements = read_text("requirements-heavy.txt")

        self.assertNotIn("torch==", requirements)
        self.assertNotIn("pymde==", requirements)
        self.assertIn("torch==2.10.0", heavy_requirements)
        self.assertIn("pymde==0.3.0", heavy_requirements)

    def test_lightweight_grist_runtime_smoke_uses_same_defaults(self) -> None:
        smoke = read_text("scripts/grist-runtime-smoke.sh")

        self.assertIn("GRIST_IMAGE:-gristlabs/grist:1.7.14", smoke)
        self.assertIn("GRIST_IN_SERVICE=true", smoke)
        self.assertIn("GRIST_DEFAULT_EMAIL=jovyan@example.invalid", smoke)
        self.assertIn("GRIST_DATA_DIR=/tmp/grist-persist/docs", smoke)
        self.assertIn("TYPEORM_DATABASE=/tmp/grist-persist/home.sqlite3", smoke)
        self.assertIn("GRIST_SINGLE_ORG=docs", smoke)
        self.assertIn('APP_HOME_URL="https://jupyterhub-internal.example.invalid/user/test/proxy/${PORT}/o/docs"', smoke)
        self.assertIn('APP_HOME_INTERNAL_URL="http://127.0.0.1:${PORT}"', smoke)
        self.assertIn('APP_STATIC_URL="http://127.0.0.1:${PORT}"', smoke)
        self.assertIn('const baseHref = match && match[1];', smoke)
        self.assertIn('const homeUrl = configMatch && JSON.parse(configMatch[1]).homeUrl;', smoke)
        self.assertIn('/o/docs', smoke)
        self.assertIn('main.bundle.js', smoke)
        self.assertIn('asset status', smoke)
        self.assertIn('Host: "public-binderhub.example.invalid"', smoke)
        self.assertIn('"X-Forwarded-Proto": "https,http"', smoke)
        self.assertIn("contains_grist", smoke)
        self.assertIn("cd /grist && ./sandbox/run.sh", smoke)
        self.assertIn("grist http status", smoke)
        self.assertIn("BOOT KEY: )[[:alnum:]]+", smoke)
        self.assertIn("[REDACTED]", smoke)


if __name__ == "__main__":
    unittest.main()
