FROM quay.io/jupyterhub/jupyterhub:5.3.0

ARG NB_USER=jovyan
ARG NB_UID=1000

ENV USER=${NB_USER}
ENV NB_UID=${NB_UID}
ENV HOME=/home/${NB_USER}
ENV PATH=/opt/conda/bin:${PATH}

# Core Binder/Jupyter requirements
RUN python3 -m pip install --no-cache-dir notebook jupyterlab

# Install Miniforge
RUN curl -fsSL https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -o /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh

# Install marimo in the main user environment
RUN /opt/conda/bin/pip install --no-cache-dir "marimo>=0.19.11"

# Install the JupyterLab/JupyterHub integration
RUN python3 -m pip install --no-cache-dir marimo-jupyter-extension

# Create Binder-compatible user
RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

# Put repo contents in the user's home
COPY . ${HOME}

USER root
RUN chown -R ${NB_UID}:${NB_UID} ${HOME}
USER ${NB_USER}

WORKDIR ${HOME}
