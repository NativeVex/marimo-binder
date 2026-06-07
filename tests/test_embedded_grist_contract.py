from pathlib import Path
import re
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

    def test_dockerfile_embeds_pinned_grist_runtime(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")

        self.assertIn("FROM gristlabs/grist:1.7.14 AS grist", dockerfile)
        self.assertIn("COPY --from=grist /grist /grist", dockerfile)
        self.assertIn("COPY --from=grist /node_modules /node_modules", dockerfile)
        self.assertIn("COPY --from=grist /usr/local/bin/node /usr/local/bin/node", dockerfile)
        self.assertIn("GRIST_IN_SERVICE=true", dockerfile)
        self.assertIn("GRIST_DATA_DIR=/home/jovyan/grist-persist/docs", dockerfile)
        self.assertIn("TYPEORM_DATABASE=/home/jovyan/grist-persist/home.sqlite3", dockerfile)

    def test_dockerfile_handles_repo2docker_uid_collision(self) -> None:
        dockerfile = read_text(".binder/Dockerfile")

        # BinderHub/repo2docker commonly injects NB_UID=1000.  The base
        # JupyterHub image already ships an Ubuntu user at that UID, so the
        # Dockerfile must reuse/rename the existing user instead of blindly
        # adding another UID 1000 account.
        self.assertIn("ARG NB_UID=1000", dockerfile)
        self.assertIn('existing_for_uid="$(getent passwd "${NB_UID}"', dockerfile)
        self.assertIn("usermod --login", dockerfile)
        self.assertIn("--move-home", dockerfile)
        self.assertIn("adduser --disabled-password", dockerfile)

    def test_start_script_launches_grist_with_binder_safe_defaults(self) -> None:
        start = read_text(".binder/start")

        self.assertIn('APP_NOTEBOOK="${MARIMO_APP:-marimo_app.py}"', start)
        self.assertIn("GRIST_PORT=\"${GRIST_PORT:-8484}\"", start)
        self.assertIn("GRIST_IN_SERVICE=\"${GRIST_IN_SERVICE:-true}\"", start)
        self.assertIn("GRIST_DEFAULT_EMAIL=\"${GRIST_DEFAULT_EMAIL:-jovyan@example.invalid}\"", start)
        self.assertIn('export PORT="${GRIST_PORT}"', start)
        self.assertIn("cd /grist && ./sandbox/run.sh", start)
        self.assertRegex(start, re.compile(r"\n\) &", re.MULTILINE))
        self.assertIn("port 8484", start)

    def test_redirect_extension_exposes_grist_entrypoint(self) -> None:
        redirect = read_text("marimo_redirect.py")

        self.assertIn('grist_target = url_path_join(hub_prefix, "proxy/8484/")', redirect)
        self.assertIn('url_path_join(base_url, r"/grist/?")', redirect)
        self.assertIn("_RedirectToGrist", redirect)

    def test_smoke_script_checks_grist_process_and_http_health(self) -> None:
        smoke = read_text("scripts/docker-smoke.sh")

        self.assertIn("gristlabs/grist 1.7.14", smoke)
        self.assertIn("marimo run marimo_app.py", smoke)
        self.assertIn("marimo edit marimo_app.py", smoke)
        self.assertIn("grep -F \"node _build/stubs/app/server/server.js\"", smoke)
        self.assertIn("http://127.0.0.1:8484", smoke)
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
        self.assertIn("cd /grist && ./sandbox/run.sh", smoke)
        self.assertIn("grist http status", smoke)
        self.assertIn("BOOT KEY: )[[:alnum:]]+", smoke)
        self.assertIn("[REDACTED]", smoke)


if __name__ == "__main__":
    unittest.main()
