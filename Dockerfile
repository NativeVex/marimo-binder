FROM quay.io/jupyterhub/jupyterhub:latest

RUN cd /srv/jupyterhub && jupyterhub --generate-config && \
    echo "c.JupyterHub.authenticator_class = 'dummy'" >> jupyterhub_config.py && \
    echo "c.DummyAuthenticator.password = 'demo'" >> jupyterhub_config.py && \
    pip install --no-cache-dir notebook

ENV PATH=/opt/conda/bin:$PATH
RUN curl -fsSL https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -o /root/miniforge.sh && \
    bash /root/miniforge.sh -b -p /opt/conda && rm /root/miniforge.sh

# marimo in conda environment (user packages available)
RUN /opt/conda/bin/pip install --no-cache-dir 'marimo>=0.19.11'

# marimo-jupyter-extension in Jupyter's environment
RUN /usr/bin/pip install --no-cache-dir marimo-jupyter-extension

RUN useradd -ms /bin/bash demo
