# syntax=docker/dockerfile:1

# Використовуємо CUDA 11.8 runtime для максимальної сумісності та уникнення конфліктів libnvJitLink
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

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
    && rm -rf /var/lib/apt/lists/*

# Створюємо користувача comfyui з UID 1000
RUN groupadd -g 1000 comfyui && \
    useradd -m -u 1000 -g comfyui comfyui

WORKDIR /opt
COPY --chown=comfyui:comfyui ComfyUI /opt/ComfyUI
WORKDIR /opt/ComfyUI

# Створюємо venv
RUN python3 -m venv /opt/ComfyUI/venv && \
    /opt/ComfyUI/venv/bin/pip install --upgrade pip wheel setuptools

# Використовуємо cu118 для CUDA 11.8 - стабільна зв'язка без конфліктів символів
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu118
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
    torch==2.4.1 \
    torchvision==0.19.1 \
    torchaudio==2.4.1 \
    --index-url ${TORCH_INDEX_URL}

RUN if [ -f requirements.txt ]; then \
        /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; \
    fi

# xformers для cu118 (версія 0.0.27.x сумісна з PyTorch 2.4.1+cu118)
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir xformers==0.0.27.post2 || true

# Створюємо глобальні симлінки для pip/python, щоб ComfyUI-Manager бачив їх
RUN ln -sf /opt/ComfyUI/venv/bin/pip /usr/local/bin/pip && \
    ln -sf /opt/ComfyUI/venv/bin/python /usr/local/bin/python && \
    ln -sf /opt/ComfyUI/venv/bin/python3 /usr/local/bin/python3

# Додаємо venv/bin до PATH глобально
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

FROM base AS runtime

USER root
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Створюємо каталоги
RUN mkdir -p /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output \
             /opt/ComfyUI/custom_nodes /opt/ComfyUI/user && \
    chown -R comfyui:comfyui /opt/ComfyUI

# Додаємо PATH у .bashrc для користувача comfyui
RUN echo 'export PATH="/opt/ComfyUI/venv/bin:${PATH}"' >> /home/comfyui/.bashrc

USER comfyui

EXPOSE 8188

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
