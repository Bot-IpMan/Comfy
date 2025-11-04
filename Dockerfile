# CUDA 12.1 + cuDNN runtime (Torch 2.3.x + cu121)
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121
ARG TORCH_VERSION=2.3.1
ARG TORCHVISION_VERSION=0.18.1
ARG TORCHAUDIO_VERSION=2.3.1
ARG COMFY_REF=master

# Базові пакети
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3-pip \
    ca-certificates curl tini tar \
 && rm -rf /var/lib/apt/lists/*

# Дерево каталогу
WORKDIR /opt/ComfyUI
RUN mkdir -p /opt/ComfyUI/src /opt/ComfyUI/{models,input,output,custom_nodes,user}

# ⬇️ Завантажуємо архів репозиторію ComfyUI (через Docker daemon, без seccomp-проблем всередині контейнера)
# Документація: ADD підтримує віддалені URL (на відміну від COPY). 
ADD https://github.com/comfyanonymous/ComfyUI/archive/refs/heads/${COMFY_REF}.tar.gz /tmp/comfyui.tar.gz
RUN tar -xzf /tmp/comfyui.tar.gz -C /opt/ComfyUI/src --strip-components=1 && rm -f /tmp/comfyui.tar.gz

# Віртуалка
RUN python3.10 -m venv /opt/ComfyUI/venv
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1

# Залежності ComfyUI з апстріму (офіційний спосіб)
RUN pip install --upgrade pip setuptools wheel \
 && pip install -r /opt/ComfyUI/src/requirements.txt

# PyTorch під CUDA 12.1 (саме cu121-індекс!)
RUN pip install --index-url ${TORCH_INDEX_URL} \
    torch==${TORCH_VERSION}+cu121 \
    torchvision==${TORCHVISION_VERSION}+cu121 \
    torchaudio==${TORCHAUDIO_VERSION}+cu121

# Локальні додаткові залежності (необов’язково)
COPY comfyui/requirements.txt /tmp/requirements.txt
RUN if [ -s /tmp/requirements.txt ]; then pip install -r /tmp/requirements.txt; fi

# Енви для старого CPU (без AVX) і стабільного аллокатора
ENV PYTORCH_CUDA_ALLOC_CONF="backend:native,max_split_size_mb:128" \
    ONEDNN_MAX_CPU_ISA="SSE41" \
    GLIBC_TUNABLES="glibc.cpu.hwcaps=-AVX2_Usable,-AVX_Usable,-AVX_Fast_Unaligned_Load,-ERMS" \
    ATEN_CPU_CAPABILITY="default" \
    ATEN_DISABLE_CPU_CAPABILITY="avx,avx2,avx512,avx512_vnni,fma4" \
    OMP_NUM_THREADS="1" MKL_NUM_THREADS="1" OPENBLAS_NUM_THREADS="1" NUMEXPR_NUM_THREADS="1" \
    XFORMERS_DISABLED="1" \
    COMFYUI_MODELS_DIR="/opt/ComfyUI/models" \
    CLI_ARGS="--listen --port 8188 --lowvram --disable-smart-memory --disable-cuda-malloc --fp32-text-enc --preview-method none --disable-all-custom-nodes"

# Простий entrypoint
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'cd /opt/ComfyUI/src' \
  'exec python main.py ${CLI_ARGS}' \
  > /usr/local/bin/docker-entrypoint.sh && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
