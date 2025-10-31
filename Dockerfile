# syntax=docker/dockerfile:1

FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CLI_ARGS="--listen --port 8188 --lowvram --preview-method auto --disable-smart-memory --force-fp16"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        git \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

ARG COMFYUI_REPO=https://github.com/comfyanonymous/ComfyUI.git
ARG COMFYUI_REF=master
ENV COMFYUI_REPO=${COMFYUI_REPO} \
    COMFYUI_REF=${COMFYUI_REF}

# Fetch the ComfyUI application source code during the image build so that the
# resulting container always has a complete installation regardless of what is
# present in the local build context.  This avoids the previous failure where
# the image only contained the volume-mounted data directory and therefore
# missed critical application files such as `main.py`.
RUN git clone --depth 1 --branch "${COMFYUI_REF}" "${COMFYUI_REPO}" ComfyUI \
    && cd ComfyUI \
    && git submodule update --init --recursive

WORKDIR /opt/ComfyUI

RUN python3 -m venv /opt/ComfyUI/venv \
    && /opt/ComfyUI/venv/bin/pip install --upgrade pip wheel \
    && if [ -f requirements.txt ]; then /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; fi

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
        torch \
        torchvision \
        torchaudio \
        --index-url ${TORCH_INDEX_URL}

ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["docker-entrypoint.sh"]
CMD []
