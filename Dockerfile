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

COPY . ${HOME}
RUN chown -R ${NB_UID}:${NB_UID} ${HOME}

RUN chmod +x ${HOME}/.binder/start

USER ${NB_USER}
WORKDIR ${HOME}

# If this image is used by Binder/repo2docker, a Dockerfile disables repo2docker's
# automatic .binder/start wiring. Make it explicit so runtime behavior matches
# the repo2docker/Binder expectation.
ENTRYPOINT ["/home/jovyan/.binder/start"]
CMD ["jupyterhub-singleuser"]
