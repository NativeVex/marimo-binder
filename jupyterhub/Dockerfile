FROM jupyterhub/jupyterhub:5.3.0

# Known-good minimal hub image for local dev/testing.
# We install dockerspawner so the hub can spawn our singleuser image.
RUN python3 -m pip install --no-cache-dir \
    dockerspawner==14.0.0
