FROM gristlabs/grist:1.7.14 AS grist

FROM quay.io/jupyterhub/jupyterhub:5.4.6

ARG NB_USER=jovyan
ARG NB_UID=1001

ENV USER=${NB_USER}
ENV NB_UID=${NB_UID}
ENV HOME=/home/${NB_USER}

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

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
ENV GRIST_SINGLE_PORT=true
ENV GRIST_SERVE_SAME_ORIGIN=true
ENV GRIST_SESSION_COOKIE=grist_binder
ENV NODE_OPTIONS=--no-deprecation

COPY --from=grist /grist /grist
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
