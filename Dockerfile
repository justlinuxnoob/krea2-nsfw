# AI Empire · Krea 2 NSFW pod
# Base: the public aiorbust/krea2-nsfw image (CUDA 12.4, torch 2.6, ComfyUI + custom nodes — no models inside).
# We only swap /start.sh, which decides what gets downloaded at boot (3 LoRAs, no Civitai key).
#
# NOTE: CI does NOT run this Dockerfile (a COPY would make the runner unpack ~20 GB and run out of disk).
# .github/workflows/build.yml does the same thing with `crane append`: it stacks start.sh as one
# tiny layer on top of the base. Kept here so a local `docker build .` gives the identical image.
FROM aiorbust/krea2-nsfw:latest
COPY --chmod=755 start.sh /start.sh
CMD ["/start.sh"]
