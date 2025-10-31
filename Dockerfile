# syntax=docker/dockerfile:1

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

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

# Створюємо venv
RUN python3 -m venv /opt/ComfyUI/venv \
    && /opt/ComfyUI/venv/bin/pip install --upgrade pip wheel

# Встановлюємо PyTorch для CUDA 12.4
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
        torch \
        torchvision \
        torchaudio \
        --index-url ${TORCH_INDEX_URL}

# Встановлюємо requirements.txt якщо є
RUN if [ -f requirements.txt ]; then \
        /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; \
    fi

# КРИТИЧНО: Копіюємо sitecustomize.py ПІСЛЯ встановлення torch
# Знаходимо правильну версію Python і копіюємо туди
RUN PYTHON_VERSION=$(/opt/ComfyUI/venv/bin/python3 -c "import sys; print(f'python{sys.version_info.major}.{sys.version_info.minor}')") && \
    cp /opt/ComfyUI/sitecustomize.py /opt/ComfyUI/venv/lib/${PYTHON_VERSION}/site-packages/sitecustomize.py && \
    echo "Copied sitecustomize.py to /opt/ComfyUI/venv/lib/${PYTHON_VERSION}/site-packages/"

ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["docker-entrypoint.sh"]
CMD []
