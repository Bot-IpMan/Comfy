FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Системні залежності
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git curl ca-certificates \
    ffmpeg libglib2.0-0 libgl1 libgomp1 tini \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ComfyUI
RUN mkdir -p /opt/ComfyUI/src /opt/ComfyUI/venv

# Python venv
RUN python3 -m venv /opt/ComfyUI/venv
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

# КРИТИЧНО: PyTorch 2.3.1 (останній, який стабільніший з Pascal)
RUN python -m pip install --upgrade pip setuptools wheel \
 && pip install --index-url https://download.pytorch.org/whl/cu121 \
      torch==2.3.1+cu121 torchvision==0.18.1+cu121 torchaudio==2.3.1+cu121

# Клонуємо ComfyUI (фіксована стабільна версія, не master)
ARG COMFY_REPO=https://github.com/comfyanonymous/ComfyUI.git
ARG COMFY_REF=v0.2.2
RUN git clone --depth 1 -b ${COMFY_REF} ${COMFY_REPO} /opt/ComfyUI/src

# Мінімальні залежності (без xformers!)
RUN pip install \
      pillow==10.3.0 safetensors==0.4.3 einops==0.8.0 pyyaml==6.0.1 \
      regex==2024.4.28 tqdm==4.66.4 requests==2.32.3 psutil==5.9.8 \
      transformers==4.40.2 accelerate==0.30.1 sentencepiece==0.2.0 \
      numpy==1.26.4 scipy==1.13.1 opencv-python-headless==4.9.0.80

# Патч: примусово CLIP на GPU у fp16 (мінімізуємо CPU-шлях)
RUN python3 <<'PY'
from pathlib import Path
import re

# 1. Патч model_management.py: завжди CLIP на GPU
mm = Path("/opt/ComfyUI/src/comfy/model_management.py")
if mm.exists():
    txt = mm.read_text()
    # Знайти функцію text_encoder_device() і замінити на примусовий return gpu
    pattern = r"def text_encoder_device\(\):.*?return.*?(?=\ndef|\Z)"
    replacement = """def text_encoder_device():
    # Force CLIP to GPU (fp16) to minimize CPU path on non-AVX CPUs
    if torch.cuda.is_available():
        return torch.device(torch.cuda.current_device())
    return torch.device("cpu")
"""
    txt = re.sub(pattern, replacement, txt, flags=re.DOTALL)
    mm.write_text(txt)
    print("[patch] Forced CLIP to GPU in model_management.py")

# 2. Патч ops.py: disable_weight_init завжди True (менше CPU-обчислень)
ops = Path("/opt/ComfyUI/src/comfy/ops.py")
if ops.exists():
    txt = ops.read_text()
    txt = txt.replace(
        "disable_weight_init = False",
        "disable_weight_init = True  # Patched for non-AVX CPU"
    )
    ops.write_text(txt)
    print("[patch] Disabled weight init in ops.py")
PY

# Entrypoint (вбудований)
RUN install -d /usr/local/bin \
 && cat > /usr/local/bin/docker-entrypoint.sh <<'EOF' \
 && chmod +x /usr/local/bin/docker-entrypoint.sh
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/ComfyUI/src

# КРИТИЧНО: жорстко фіксуємо native allocator ДО імпорту torch
export PYTORCH_CUDA_ALLOC_CONF="backend:native,max_split_size_mb:64"

# Обмеження CPU (максимально консервативно)
export ATEN_CPU_CAPABILITY="default"
export ATEN_DISABLE_CPU_CAPABILITY="avx,avx2,avx512,avx512_vnni,avx512_bf16,fma4"
export ONEDNN_MAX_CPU_ISA="SSE41"
export OMP_NUM_THREADS="1"
export MKL_NUM_THREADS="1"

# Аргументи ComfyUI: все на GPU, мінімум CPU
declare -a args=(
  --listen --port 8188
  --lowvram
  --fp16-text-enc  # CLIP у fp16 на GPU
  --fp16-vae
  --disable-smart-memory
  --preview-method none
)

# Якщо передали власні аргументи
if [[ $# -gt 0 ]]; then
  args=("$@")
fi

echo "[entrypoint] Args: ${args[*]}"
echo "[entrypoint] PYTORCH_CUDA_ALLOC_CONF=$PYTORCH_CUDA_ALLOC_CONF"

exec python -u main.py "${args[@]}"
EOF

EXPOSE 8188
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/docker-entrypoint.sh"]
