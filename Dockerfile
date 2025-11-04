# CUDA 12.1 runtime (сумісно з torch 2.3.x + cu121)
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# ---- Аргументи збірки (можеш перевизначати з compose) ----
ARG DEBIAN_FRONTEND=noninteractive
ARG COMFY_REPO=https://github.com/comfyanonymous/ComfyUI.git
ARG COMFY_REF=master

# Під PyTorch cu121: існують версії 2.3.x, індекс має бути саме cu121
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121
ARG TORCH_VERSION=2.3.1
ARG TORCHVISION_VERSION=0.18.1
ARG TORCHAUDIO_VERSION=2.3.1

# ---- Базові пакети + Python 3.10 ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3-pip \
    git curl ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

# ---- Дерево проєкту ----
WORKDIR /opt/ComfyUI
RUN mkdir -p /opt/ComfyUI/src \
    /opt/ComfyUI/models /opt/ComfyUI/input /opt/ComfyUI/output \
    /opt/ComfyUI/custom_nodes /opt/ComfyUI/user

# ---- Клонуємо ComfyUI (апстрім) ----
RUN git clone --depth 1 -b ${COMFY_REF} ${COMFY_REPO} /opt/ComfyUI/src

# ---- Віртуальне середовище ----
RUN python3.10 -m venv /opt/ComfyUI/venv
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

# ---- Оновлюємо pip та ставимо залежності ComfyUI з апстріму ----
# (це офіційний спосіб: pip install -r requirements.txt у каталозі репозиторію)
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r /opt/ComfyUI/src/requirements.txt

# ---- Ставимо PyTorch під CUDA 12.1 (Pascal сумісно) ----
RUN pip install --index-url ${TORCH_INDEX_URL} \
    torch==${TORCH_VERSION}+cu121 \
    torchvision==${TORCHVISION_VERSION}+cu121 \
    torchaudio==${TORCHAUDIO_VERSION}+cu121

# ---- Копіюємо твій локальний список (щоб не падало на COPY у compose) ----
# Цей файл може містити додаткові плагіни/піни; за замовчуванням — мінімальний.
COPY comfyui/requirements.txt /tmp/requirements.txt
RUN if [ -s /tmp/requirements.txt ]; then pip install -r /tmp/requirements.txt; fi

# ---- Енви за замовчуванням (можеш перевизначати в compose) ----
# Аллокатор PyTorch: native — стабільніший на старих GPU/драйверах
ENV PYTORCH_CUDA_ALLOC_CONF="backend:native,max_split_size_mb:128" \
    # Старий CPU без AVX → обмежуємо oneDNN та гілки glibc IFUNC
    ONEDNN_MAX_CPU_ISA="SSE41" \
    GLIBC_TUNABLES="glibc.cpu.hwcaps=-AVX2_Usable,-AVX_Usable,-AVX_Fast_Unaligned_Load,-ERMS" \
    # Відрізаємо «важкі» шляхи в ATen
    ATEN_CPU_CAPABILITY="default" \
    ATEN_DISABLE_CPU_CAPABILITY="avx,avx2,avx512,avx512_vnni,fma4" \
    # Менше потоків у BLAS — стабільніше на старих CPU
    OMP_NUM_THREADS="1" \
    MKL_NUM_THREADS="1" \
    OPENBLAS_NUM_THREADS="1" \
    NUMEXPR_NUM_THREADS="1" \
    # xFormers часто зібрані з AVX2: на твоєму CPU краще без них
    XFORMERS_DISABLED="1" \
    # Стандартні директорії моделей/IO
    COMFYUI_MODELS_DIR="/opt/ComfyUI/models" \
    CLI_ARGS="--listen --port 8188 --lowvram --disable-smart-memory --disable-cuda-malloc --fp32-text-enc --preview-method none --disable-all-custom-nodes"

# ---- Невеличкий entrypoint, щоб красиво стартувати ComfyUI ----
# Використовуємо tini (init-процес) і віртуалку, щоб ловити сигнали/здуття пам’яті коректно
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'export PYTHONUNBUFFERED=1' \
  'cd /opt/ComfyUI/src' \
  'exec python main.py ${CLI_ARGS}' \
  > /usr/local/bin/docker-entrypoint.sh && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/docker-entrypoint.sh"]
