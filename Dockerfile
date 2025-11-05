# Dockerfile
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Системні залежності
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git curl ca-certificates \
    ffmpeg libglib2.0-0 libgl1 libssl3 tini \
 && rm -rf /var/lib/apt/lists/*

# Директорії
WORKDIR /opt/ComfyUI
RUN mkdir -p /opt/ComfyUI/src /opt/ComfyUI/venv

# Python venv
RUN python3 -m venv /opt/ComfyUI/venv
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

# PyTorch 2.4.1 + cu124 (без побічної збірки)
RUN python -m pip install --upgrade pip setuptools wheel \
 && pip install --index-url https://download.pytorch.org/whl/cu124 \
      torch==2.4.1+cu124 torchvision==0.19.1+cu124 torchaudio==2.4.1+cu124

# Клонуємо ComfyUI (апстрім)
ARG COMFY_REPO=https://github.com/comfyanonymous/ComfyUI.git
ARG COMFY_REF=master
RUN git clone --depth 1 -b ${COMFY_REF} ${COMFY_REPO} /opt/ComfyUI/src

# Мінімальні залежності ComfyUI (без xformers)
# (requirements.txt у репо часто плаває — ставимо стабільне мінімум)
RUN pip install \
      pillow==10.* safetensors==0.4.* einops==0.8.* pyyaml==6.* \
      regex==2024.* tqdm==4.* requests==2.* psutil==5.* \
      transformers==4.* accelerate==0.34.* sentencepiece==0.1.* \
      numpy==1.26.* scipy==1.11.* opencv-python-headless==4.10.*

# Вхідна точка
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188
HEALTHCHECK CMD curl -fsS http://localhost:8188/ > /dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/docker-entrypoint.sh"]
