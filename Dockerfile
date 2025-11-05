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

# Вхідна точка (вбудований скрипт)
RUN install -d /usr/local/bin \
 && cat > /usr/local/bin/docker-entrypoint.sh <<'EOF' \
 && chmod +x /usr/local/bin/docker-entrypoint.sh
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/ComfyUI

# Агресивні параметри glibc malloc (менше фрагментації)
export MALLOC_ARENA_MAX=2
export MALLOC_MMAP_THRESHOLD_=131072
export MALLOC_TRIM_THRESHOLD_=131072
export MALLOC_TOP_PAD_=131072
export MALLOC_MMAP_MAX_=65536

# Python дрібні оптимізації/стабільність
export PYTHONHASHSEED=0
export PYTHONMALLOC=malloc

ensure_source_tree() {
  if [[ -f main.py ]]; then return; fi
  local repo="${COMFYUI_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
  local ref="${COMFYUI_REF:-master}"
  echo "[docker-entrypoint] ComfyUI sources missing, cloning ${repo} (${ref})" >&2
  local tmp_dir; tmp_dir=$(mktemp -d)
  git clone --depth 1 --branch "${ref}" "${repo}" "${tmp_dir}"
  (cd "${tmp_dir}" && git submodule update --init --recursive)
  shopt -s dotglob
  for item in "${tmp_dir}"/*; do
    local name; name=$(basename "${item}")
    [[ "${name}" == ".git" ]] && continue
    [[ -e "${name}" ]] && continue
    cp -r "${item}" "${name}"
  done
  shopt -u dotglob
  rm -rf "${tmp_dir}"
}
ensure_source_tree

# Сумісність: якщо заданий лише PYTORCH_ALLOC_CONF — продублюємо в CUDA-варіант
if [[ -n "${PYTORCH_ALLOC_CONF:-}" && -z "${PYTORCH_CUDA_ALLOC_CONF:-}" ]]; then
  export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_ALLOC_CONF}"
fi

# Патч: безпечний fallback на CPU, якщо CUDA недоступна
ensure_cpu_fallback_patch() {
python - <<'PY'
from pathlib import Path, re
p=Path("comfy/model_management.py")
if not p.exists(): raise SystemExit(0)
s=p.read_text()
needle="return torch.device(torch.cuda.current_device())"
if needle not in s: raise SystemExit(0)
import re
m=re.search(r"^(\s*)"+re.escape(needle), s, flags=re.MULTILINE)
if not m: raise SystemExit(0)
indent=m.group(1)
patch="\n".join((
f"{indent}try:",
f"{indent}    current_device = torch.cuda.current_device()",
f"{indent}except Exception:",
f"{indent}    return torch.device(\"cpu\")",
f"{indent}return torch.device(current_device)"
))
if patch in s: raise SystemExit(0)
p.write_text(s.replace(indent+needle, patch))
PY
}
ensure_cpu_fallback_patch || true

# Патч: коректно вибирати allocator для Pascal (<7.0) — cudaMalloc замість cudaMallocAsync
ensure_allocator_patch() {
python - <<'PY'
from pathlib import Path, re
p=Path("comfy/model_management.py")
if not p.exists(): raise SystemExit(0)
s=p.read_text()
pat=re.compile(r"^(\s*)torch\.cuda\.memory\.change_current_allocator\((\"|')cudaMallocAsync\2\)", re.MULTILINE)
def repl(m):
    ind=m.group(1)
    return (
f"{ind}if torch.cuda.is_available():\n"
f"{ind}    try:\n"
f"{ind}        legacy_device = any(torch.cuda.get_device_capability(i)[0] < 7 for i in range(torch.cuda.device_count()))\n"
f"{ind}    except Exception:\n"
f"{ind}        legacy_device = False\n"
f"{ind}    if legacy_device:\n"
f"{ind}        torch.cuda.memory.change_current_allocator(\"cudaMalloc\")\n"
f"{ind}    else:\n"
f"{ind}        torch.cuda.memory.change_current_allocator(\"cudaMallocAsync\")\n"
    )
ns,c=pat.subn(repl, s)
if c: p.write_text(ns)
PY
}
ensure_allocator_patch || true

# Скидання кешу (якщо дозволено)
sync
if [[ -w /proc/sys/vm/drop_caches ]]; then
  echo 3 > /proc/sys/vm/drop_caches || true
else
  echo "[docker-entrypoint] Skipping cache drop: /proc/sys/vm/drop_caches is not writable" >&2
fi

check_cuda_available() {
python - <<'PY'
import sys
try:
    import torch
    ok = torch.cuda.is_available() and torch.cuda.device_count() > 0
except Exception:
    ok = False
sys.exit(0 if ok else 1)
PY
}

needs_legacy_allocator() {
python - <<'PY'
import sys
try:
    import torch
except Exception:
    sys.exit(1)
if not torch.cuda.is_available():
    sys.exit(1)
try:
    n=torch.cuda.device_count()
except Exception:
    sys.exit(1)
for i in range(n):
    try:
        major,_=torch.cuda.get_device_capability(i)
    except Exception:
        continue
    if major < 7:
        sys.exit(0)
sys.exit(1)
PY
}

# Збираємо аргументи для ComfyUI
declare -a args
if [[ $# -gt 0 && "$1" == -* ]]; then
  args=("$@")
elif [[ -n "${CLI_ARGS:-}" ]]; then
  # не дробимо рядок — пробіли усередині значень збережуться
  IFS=$' \t\n' read -r -a args <<< "${CLI_ARGS}"
else
  args=(--listen --port 8188)
fi

gpu=false
if check_cuda_available; then gpu=true; fi

# Вибір аллокатора до імпорту torch у main.py (щоб уникнути assert в PyTorch)
if $gpu && needs_legacy_allocator; then
  # У PyTorch валідні backend-и: native | cudaMallocAsync (за доками).
  # Для Pascal нам треба cudaMalloc (legacy), тож явно ставимо backend:cudaMalloc.
  # https://pytorch.org/docs/stable/generated/torch.cuda.memory.get_allocator_backend.html
  base="${PYTORCH_CUDA_ALLOC_CONF:-${PYTORCH_ALLOC_CONF:-}}"
  sanitized="$(PYTORCH_CONF_RAW="${base}" python - <<'PY'
import os
conf=os.environ.get("PYTORCH_CONF_RAW","")
parts=[]
for raw in conf.split(","):
    item=raw.strip()
    if not item: continue
    k=item.split(":",1)[0].strip().lower()
    if k in {"backend","expandable_segments"}:  # перезапишемо/зайве
        continue
    parts.append(item)
print(",".join(parts))
PY
)"
  if [[ -n "${sanitized}" ]]; then
    export PYTORCH_CUDA_ALLOC_CONF="backend:cudaMalloc,${sanitized}"
  else
    export PYTORCH_CUDA_ALLOC_CONF="backend:cudaMalloc"
  fi
  echo "[docker-entrypoint] Falling back to legacy cudaMalloc allocator (compute capability < 7.0)" >&2
fi

# Якщо GPU недоступний — прибираємо GPU-профілі й додаємо --cpu
if ! $gpu; then
  filtered=()
  cpu_flag=false
  for a in "${args[@]}"; do
    case "$a" in
      --gpu-only|--highvram|--normalvram|--lowvram|--novram) continue ;;
      --force-fp16) continue ;;  # на CPU fp16 не має сенсу
      --cpu) cpu_flag=true ;;
    esac
    filtered+=("$a")
  done
  args=("${filtered[@]}")
  $cpu_flag || args+=(--cpu)
fi

exec python -u main.py "${args[@]}"
EOF

EXPOSE 8188
HEALTHCHECK CMD curl -fsS http://localhost:8188/ > /dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/docker-entrypoint.sh"]
