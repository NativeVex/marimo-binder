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

RUN python3 -c "import sys; print(sys.executable)" && \
    jupyter lab path && \
    jupyter labextension list && \
    jupyter server extension list

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

COPY . ${HOME}
RUN chown -R ${NB_UID}:${NB_UID} ${HOME}
RUN chmod +x ${HOME}/entrypoint.sh

USER ${NB_USER}
WORKDIR ${HOME}

ENTRYPOINT ["/home/jovyan/entrypoint.sh"]
EXPOSE 8888
