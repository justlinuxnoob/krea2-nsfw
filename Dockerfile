# Krea 2 NSFW pod image — straight copy of the public aiorbust/krea2-nsfw image.
# Only FROM + labels on purpose: with no RUN steps the build never unpacks the
# ~20 GB of layers, it just re-pushes them to GHCR, so it fits on a GitHub runner.
# Add your own changes later (RUN/COPY) — that will need much more runner disk.
FROM aiorbust/krea2-nsfw:latest

LABEL org.opencontainers.image.source="https://github.com/justlinuxnoob/krea2-nsfw" \
      org.opencontainers.image.description="Krea 2 NSFW RunPod image (FROM aiorbust/krea2-nsfw)"
