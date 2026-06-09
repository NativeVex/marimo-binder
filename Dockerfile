ARG JUPYTER_BASE_IMAGE=quay.io/jupyter/pyspark-notebook:latest

FROM gristlabs/grist:1.7.14 AS grist

# Keep BinderHub push/post-build pressure lower by copying only runtime-relevant
# Grist artifacts into the final image.  These are build/dev/debug artifacts not
# needed by the embedded single-user Grist service exercised by smoke tests.
RUN rm -rf /grist/sandbox/pyodide \
    /grist/node_modules/typescript \
    /grist/node_modules/.cache \
    && find /grist -type f \
        \( -name '*.map' -o -name '*.d.ts' -o -name '*.tsbuildinfo' \) -delete \
    && find /grist -type d \
        \( -name test -o -name tests -o -name __tests__ \) -prune -exec rm -rf '{}' +

FROM ${JUPYTER_BASE_IMAGE}

USER root

ARG NB_USER=jovyan
ARG NB_UID=1000

ENV USER=${NB_USER}
ENV NB_UID=${NB_UID}
ENV HOME=/home/${NB_USER}

# The public Jupyter Docker Stacks PySpark image normally already provides the
# jovyan user at UID 1000. repo2docker/BinderHub can still inject NB_UID/NB_USER
# build args, so reuse/rename an existing UID owner instead of blindly adding
# another account.
RUN set -eux; \
    existing_for_uid="$(getent passwd "${NB_UID}" | cut -d: -f1 || true)"; \
    if id -u "${NB_USER}" >/dev/null 2>&1; then \
        true; \
    elif [ -n "${existing_for_uid}" ]; then \
        usermod --login "${NB_USER}" --home "${HOME}" --move-home "${existing_for_uid}"; \
    else \
        adduser --disabled-password --gecos "Default user" --uid "${NB_UID}" "${NB_USER}"; \
    fi; \
    mkdir -p "${HOME}"; \
    chown -R "${NB_UID}:${NB_UID}" "${HOME}"

COPY requirements.txt ${HOME}/requirements.txt

# System-level python deps baked into the image (avoid network at runtime)
RUN python3 -m pip install --no-cache-dir -r ${HOME}/requirements.txt

# Grist runtime defaults.  .binder/start maps GRIST_PORT to PORT only for
# the Grist subprocess so JupyterHub's singleuser process keeps its own port
# contract.
ENV GRIST_IN_SERVICE=true
ENV GRIST_DEFAULT_EMAIL=jovyan@example.invalid
ENV GRIST_DATA_DIR=/home/jovyan/grist-persist/docs
ENV TYPEORM_DATABASE=/home/jovyan/grist-persist/home.sqlite3
ENV GRIST_INST_DIR=/home/jovyan/grist-persist
ENV GRIST_HOST=0.0.0.0
ENV GRIST_ORG_IN_PATH=true
ENV GRIST_SINGLE_ORG=docs
ENV GRIST_SINGLE_PORT=true
ENV GRIST_SERVE_SAME_ORIGIN=true
ENV GRIST_SESSION_COOKIE=grist_binder
ENV NODE_OPTIONS=--no-deprecation

COPY --from=grist /grist /grist

# Grist is served under JupyterHub's /user/<name>/proxy/<port>/ prefix.  Bake a
# small client hook into Grist's served static bundle path so .binder/start only needs
# to reference it at runtime; the Binder user should not need write access to
# root-owned /grist.
RUN mkdir -p /grist/static
COPY .binder/binder-url-prefix.js /grist/static/binder-url-prefix.js

# Grist's document sandbox is Python code copied from the upstream Grist
# image.  Install the runtime sandbox deps needed for document creation/imports
# without installing the whole upstream sandbox requirements file, which pins
# old typing/debug packages that downgrade JupyterHub/IPython dependencies.
RUN python3 -m pip install --no-cache-dir \
    iso8601==0.1.12 \
    astroid==2.14.2 \
    friendly-traceback==0.7.48 \
    sortedcontainers==2.4.0 \
    openpyxl==3.0.10 \
    phonenumberslite==8.12.57 \
    chardet==5.1.0 \
    roman==3.3

COPY --from=grist /node_modules /node_modules
COPY --from=grist /usr/local/bin/node /usr/local/bin/node

COPY . ${HOME}
RUN mkdir -p /home/jovyan/grist-persist/docs \
    && chown -R ${NB_UID}:${NB_UID} ${HOME} /home/jovyan/grist-persist \
    && chmod +x ${HOME}/.binder/start

USER ${NB_USER}
WORKDIR ${HOME}

# If this image is used by Binder/repo2docker, a Dockerfile disables repo2docker's
# automatic .binder/start wiring. Make it explicit so runtime behavior matches
# the repo2docker/Binder expectation.
ENTRYPOINT ["/home/jovyan/.binder/start"]
CMD ["jupyterhub-singleuser"]
