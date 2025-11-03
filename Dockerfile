# syntax=docker/dockerfile:1

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
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 comfyui && \
    useradd -m -u 1000 -g comfyui comfyui

WORKDIR /opt
COPY --chown=comfyui:comfyui ComfyUI /opt/ComfyUI
WORKDIR /opt/ComfyUI

RUN python3 -m venv /opt/ComfyUI/venv && \
    /opt/ComfyUI/venv/bin/pip install --upgrade pip==24.0

# Встановлюємо PyTorch БЕЗ залежностей (стабільна гілка 2.3 для Pascal GPU).
# За потреби перейдіть на інший індекс/версії (наприклад, колеса +cu124).
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir --no-deps \
    torch==2.3.1+cu121 \
    torchvision==0.18.1+cu121 \
    torchaudio==2.3.1+cu121 \
    --extra-index-url ${TORCH_INDEX_URL}

# Додаємо базові залежності
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
    filelock typing-extensions sympy networkx jinja2 fsspec numpy pillow

# Встановлюємо requirements БЕЗ xformers
RUN if [ -f requirements.txt ]; then \
        grep -v "xformers" requirements.txt > requirements_no_xformers.txt || true; \
        if [ -s requirements_no_xformers.txt ]; then \
            /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements_no_xformers.txt; \
        fi; \
    fi

# НЕ встановлюємо xformers - він тягне torch 2.8.0!

# Створюємо симлінки
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
