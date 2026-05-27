FROM quay.io/jupyterhub/jupyterhub:5.3.0

ARG NB_USER=jovyan
ARG NB_UID=1000

ENV USER=${NB_USER}
ENV NB_UID=${NB_UID}
ENV HOME=/home/${NB_USER}

RUN python3 -m pip install --no-cache-dir \
    notebook \
    jupyterlab \
    "marimo>=0.19.11" \
    marimo-jupyter-extension

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

COPY . ${HOME}
RUN chown -R ${NB_UID}:${NB_UID} ${HOME}

RUN chmod +x ${HOME}/.binder/start

USER ${NB_USER}
WORKDIR ${HOME}
