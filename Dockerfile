# syntax=docker/dockerfile:1.7

FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
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
    wget \
    curl \
    cuda-nvrtc-12-4 \
    cuda-nvrtc-dev-12-4 \
    && rm -rf /var/lib/apt/lists/*

# Підстраховка для libnvrtc-builtins під sm_61 (GTX 1050 Ti)
RUN set -eux; \
    for libdir in /usr/local/cuda/lib64 /usr/local/cuda/targets/x86_64-linux/lib; do \
        if [ -f "${libdir}/libnvrtc-builtins.so" ] && [ ! -e "${libdir}/libnvrtc-builtins-sm_61.so" ]; then \
            ln -sf libnvrtc-builtins.so "${libdir}/libnvrtc-builtins-sm_61.so"; \
        fi; \
    done

RUN groupadd -g 1000 comfyui && \
    useradd -m -u 1000 -g comfyui comfyui

WORKDIR /opt
COPY --chown=comfyui:comfyui ComfyUI /opt/ComfyUI
WORKDIR /opt/ComfyUI

RUN python3 -m venv /opt/ComfyUI/venv && \
    /opt/ComfyUI/venv/bin/pip install --upgrade pip==24.0

# Встановлюємо PyTorch (колеса під CUDA 12.4)
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124
ARG TORCH_VERSION=2.4.1
ARG TORCH_VARIANT=+cu124
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir --no-deps \
    torch==${TORCH_VERSION}${TORCH_VARIANT} \
    torchvision==0.19.1${TORCH_VARIANT} \
    torchaudio==2.4.1${TORCH_VARIANT} \
    --extra-index-url ${TORCH_INDEX_URL}

# Базові залежності Python
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
    filelock typing-extensions sympy networkx jinja2 fsspec numpy pillow

# Прибираємо xformers з requirements.txt та інсталюємо решту
RUN <<'BASH'
set -euo pipefail
if [ -f requirements.txt ]; then
  /opt/ComfyUI/venv/bin/python - <<'PY'
from pathlib import Path
import re

req_path = Path('requirements.txt')
pattern = re.compile(r"^\s*xformers(?:\s|[<>=!~;#]|$)", re.IGNORECASE)
if req_path.exists():
    lines = req_path.read_text().splitlines()
    filtered = [line for line in lines if not pattern.match(line)]
    if filtered != lines:
        req_path.write_text("\n".join(filtered) + ("\n" if filtered else ""))
PY
  /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt
fi
BASH

# Симлінки на інструменти з venv
RUN ln -sf /opt/ComfyUI/venv/bin/pip /usr/local/bin/pip && \
    ln -sf /opt/ComfyUI/venv/bin/python /usr/local/bin/python && \
    ln -sf /opt/ComfyUI/venv/bin/python3 /usr/local/bin/python3

ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

FROM base AS runtime

USER root
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output \
             /opt/ComfyUI/custom_nodes /opt/ComfyUI/user && \
    chown -R comfyui:comfyui /opt/ComfyUI

RUN echo 'export PATH="/opt/ComfyUI/venv/bin:${PATH}"' >> /home/comfyui/.bashrc

USER comfyui

EXPOSE 8188

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
