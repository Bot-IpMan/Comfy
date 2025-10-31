# syntax=docker/dockerfile:1

FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

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

# Створюємо користувача comfyui з UID 1000 (типовий для першого користувача)
RUN groupadd -g 1000 comfyui && \
    useradd -m -u 1000 -g comfyui comfyui

WORKDIR /opt
COPY --chown=comfyui:comfyui ComfyUI /opt/ComfyUI
WORKDIR /opt/ComfyUI

# Виконуємо збірку від імені користувача
USER comfyui

RUN python3 -m venv /opt/ComfyUI/venv \
    && /opt/ComfyUI/venv/bin/pip install --upgrade pip wheel

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
        torch==2.5.1 \
        torchvision==0.20.1 \
        torchaudio==2.5.1 \
        --index-url ${TORCH_INDEX_URL}

RUN if [ -f requirements.txt ]; then \
        /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; \
    fi

RUN PYTHON_VERSION=$(/opt/ComfyUI/venv/bin/python3 -c "import sys; print(f'python{sys.version_info.major}.{sys.version_info.minor}')") && \
    echo "import os; os.environ['CUDA_VISIBLE_DEVICES'] = ''" > /opt/ComfyUI/venv/lib/${PYTHON_VERSION}/site-packages/sitecustomize.py && \
    cat /opt/ComfyUI/sitecustomize.py >> /opt/ComfyUI/venv/lib/${PYTHON_VERSION}/site-packages/sitecustomize.py && \
    echo "Installed sitecustomize.py to force CPU mode" >&2

ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

# Повертаємося до root для копіювання entrypoint
USER root
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Створюємо необхідні каталоги з правильними правами
RUN mkdir -p /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output \
             /opt/ComfyUI/custom_nodes /opt/ComfyUI/user && \
    chown -R comfyui:comfyui /opt/ComfyUI

# Знову переключаємося на користувача
USER comfyui

EXPOSE 8188

ENTRYPOINT ["docker-entrypoint.sh"]
CMD []
