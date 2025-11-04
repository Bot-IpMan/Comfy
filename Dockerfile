# Базовий образ з CUDA 12.1 (Pascal ок) і старішим glibc ніж у Debian 13
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# мінімум для Python 3.10 + git + системні залежності
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3.10-distutils python3-pip \
    git curl ca-certificates wget unzip libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Створюємо робочий каталог і venv
WORKDIR /opt/ComfyUI
RUN python3.10 -m venv /opt/ComfyUI/venv
ENV PATH=/opt/ComfyUI/venv/bin:$PATH

# Клонуємо ComfyUI (можеш змінити на свій форк/коміт)
ARG COMFY_REPO="https://github.com/comfyanonymous/ComfyUI.git"
ARG COMFY_REF="master"
RUN git clone --depth=1 -b ${COMFY_REF} ${COMFY_REPO} /opt/ComfyUI/src

# Встановлюємо залежності (без xformers)
COPY comfyui/requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip setuptools wheel \
 && pip install -r /tmp/requirements.txt

# Пін інструментів PyTorch під CUDA 12.1 (саме 2.3.0, не 2.3.1)
# офіційний індекс для cu121
RUN pip install \
  torch==2.3.0+cu121 torchvision==0.18.0+cu121 torchaudio==2.3.0+cu121 \
  --index-url https://download.pytorch.org/whl/cu121

# Створюємо структуру каталогів під моделі/IO/user/custom_nodes
RUN mkdir -p /opt/ComfyUI/{models,input,output,custom_nodes,user}

# Енви для старого CPU (без AVX) + стабільність у LXC
ENV \
  # Жорстко відрізаємо AVX-реалізації glibc (memcpy/memmove/…)
  GLIBC_TUNABLES="glibc.cpu.hwcaps=-AVX_Usable,-AVX2_Usable,-AVX_Fast_Unaligned_Load,-ERMS" \
  # Просимо oneDNN (MKL-DNN) падати не вище SSE4.1
  ONEDNN_MAX_CPU_ISA="SSE41" \
  # Вимикаємо фічі в самій ATen (torch) на CPU
  ATEN_CPU_CAPABILITY="default" \
  ATEN_DISABLE_CPU_CAPABILITY="avx,avx2,avx512,avx512_vnni,fma4" \
  # Менше потоків — менше шансів на гонки та краші в старому софті
  OMP_NUM_THREADS="1" MKL_NUM_THREADS="1" OPENBLAS_NUM_THREADS="1" NUMEXPR_NUM_THREADS="1" \
  # Безпечні для низької VRAM режими аллокатора
  PYTORCH_CUDA_ALLOC_CONF="backend:native,max_split_size_mb:128" \
  # Вимикаємо xformers усюди
  XFORMERS_DISABLED="1" \
  # Щоб Comfy не підхоплював випадкові юзер-пакети
  PYTHONNOUSERSITE="1"

# Легка обгортка-ентрипоінт
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8188
WORKDIR /opt/ComfyUI/src

# За замовчуванням — lowvram і максимально «щадні» прапори
ENV CLI_ARGS="--listen --port 8188 --lowvram --disable-smart-memory --preview-method none --fp32-text-enc --disable-cuda-malloc --disable-all-custom-nodes"
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
