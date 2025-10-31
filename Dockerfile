# syntax=docker/dockerfile:1

# Використовуйте образ, сумісний з вашим драйвером
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

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

# Копіюємо локальні файли ComfyUI
COPY ComfyUI /opt/ComfyUI

WORKDIR /opt/ComfyUI

RUN python3 -m venv /opt/ComfyUI/venv \
    && /opt/ComfyUI/venv/bin/pip install --upgrade pip wheel \
    && if [ -f requirements.txt ]; then /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; fi

# Встановлюємо PyTorch для CUDA 12.4 (сумісний з драйвером 580.x)
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
        torch \
        torchvision \
        torchaudio \
        --index-url ${TORCH_INDEX_URL}

# Додаємо CPU fallback патч
COPY ComfyUI/sitecustomize.py /opt/ComfyUI/venv/lib/python3.10/site-packages/sitecustomize.py

ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["docker-entrypoint.sh"]
CMD []
