#!/usr/bin/env bash
set -Eeuo pipefail

# === Базові налаштування пам'яті/GLIBC/BLAS (безпечні дефолти) ===
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"
export PYTHONHASHSEED=0
export PYTHONMALLOC=malloc

# Де лежить ComfyUI (джерела мають бути тут: main.py)
COMFY_ROOT="/opt/ComfyUI/src"
VENV_PY="/opt/ComfyUI/venv/bin/python"

cd "$COMFY_ROOT" 2>/dev/null || {
  echo "[entrypoint] ComfyUI sources not found in $COMFY_ROOT" >&2
  echo "[entrypoint] Please check Dockerfile COPY or bind mount to $COMFY_ROOT" >&2
  exit 1
}

# --- Корисний лог: поточні моделі/шляхи ---
echo "[entrypoint] CWD=$PWD"
echo "[entrypoint] USER=$(id -u):$(id -g)"

# === Обираємо бекенд аллокатора ДО першого імпорту torch ===
# Для Pascal (compute capability 6.x) потрібен 'native'; для >=7.0 — 'cudaMallocAsync'.
choose_allocator() {
  local cc=""; local cc_major=""; local backend="native"

  if command -v nvidia-smi >/dev/null 2>&1; then
    # compute_cap повертає типу "6.1" або "7.5"
    cc="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 || true)"
  fi

  if [[ -n "$cc" ]]; then
    cc_major="${cc%%.*}"
  else
    # якщо не можемо визначити — залишаємо safe default для Pascal
    cc_major="6"
  fi

  if [[ "$cc_major" =~ ^[0-9]+$ ]] && (( cc_major >= 7 )); then
    backend="cudaMallocAsync"
  else
    backend="native"
  fi

  # Чистимо можливі старі значення і задаємо обране
  export PYTORCH_CUDA_ALLOC_CONF="backend:${backend},max_split_size_mb:${PYTORCH_MAX_SPLIT_SIZE_MB:-128}"
  echo "[entrypoint] Selected CUDA allocator backend: ${backend} (CC major=${cc_major})"
}

choose_allocator

# === Скидання кешів (не критично, просто інфо) ===
sync || true
if [[ -w /proc/sys/vm/drop_caches ]]; then
  echo 3 > /proc/sys/vm/drop_caches || true
else
  echo "[entrypoint] Skipping cache drop: /proc/sys/vm/drop_caches is not writable"
fi

# === Формуємо аргументи ComfyUI з CLI_ARGS та прибираємо конфлікти ===
# Взаємовиключні: --gpu-only | --highvram | --normalvram | --lowvram | --novram | --cpu
sanitize_cli_args() {
  local -a in_args=("$@")
  local -a out=()
  local chosen_vram=""
  local need_fp32_text_enc=true

  # прапорці, які заборонено міксувати/взагалі змінювати аллокатор зсередини
  local drop_flags=(
    "--cuda-malloc" "--disable-cuda-malloc"
  )

  for a in "${in_args[@]}"; do
    # Викидаємо прапорці, які змінюють аллокатор у рантаймі ComfyUI
    for bad in "${drop_flags[@]}"; do
      if [[ "$a" == "$bad" ]]; then
        echo "[entrypoint] Dropping flag '$a' (allocator controlled via env only)"
        continue 2
      fi
    done

    case "$a" in
      --gpu-only|--highvram|--normalvram|--lowvram|--novram|--cpu)
        if [[ -z "$chosen_vram" ]]; then
          chosen_vram="$a"
          out+=("$a")
        else
          echo "[entrypoint] Removing extra VRAM mode '$a' (already have '$chosen_vram')"
        fi
        ;;
      --fp32-text-enc) need_fp32_text_enc=false; out+=("$a");;
      *) out+=("$a");;
    esac
  done

  # Якщо жодного режиму не задано — дефолт для 4GB карт: --lowvram
  if [[ -z "$chosen_vram" ]]; then
    out+=("--lowvram")
    echo "[entrypoint] No VRAM mode specified → adding --lowvram"
  fi

  # На Pascal/старих CPU стабільніше залишити текстовий енкодер у FP32
  if $need_fp32_text_enc; then
    out+=("--fp32-text-enc")
  fi

  printf '%s\n' "${out[@]}"
}

# Аргументи з ENV або дефолтні
declare -a ARGS=()
if [[ $# -gt 0 && "$1" == -* ]]; then
  ARGS=("$@")
elif [[ -n "${CLI_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  ARGS=( ${CLI_ARGS} )
else
  ARGS=( --listen --port 8188 )
fi

# Нормалізуємо
mapfile -t ARGS < <(sanitize_cli_args "${ARGS[@]}")

# Якщо GPU реально недоступний — прибираємо усі GPU-режими і ставимо --cpu
if ! "$VENV_PY" - <<'PY' >/dev/null 2>&1
import sys
try:
    import torch
    sys.exit(0 if (torch.cuda.is_available() and torch.cuda.device_count()>0) else 1)
except Exception:
    sys.exit(1)
PY
then
  echo "[entrypoint] CUDA not available → forcing --cpu"
  # фільтруємо і додаємо --cpu (рівно один)
  tmp=(); have_cpu=false
  for a in "${ARGS[@]}"; do
    case "$a" in
      --gpu-only|--highvram|--normalvram|--lowvram|--novram) continue ;;
      --cpu) have_cpu=true ;;
    esac
    tmp+=("$a")
  done
  ARGS=("${tmp[@]}")
  $have_cpu || ARGS+=(--cpu)
fi

echo "[entrypoint] Final CLI args: ${ARGS[*]}"
echo "[entrypoint] PYTORCH_CUDA_ALLOC_CONF=${PYTORCH_CUDA_ALLOC_CONF}"

# === Запуск ComfyUI ===
exec "$VENV_PY" -u main.py "${ARGS[@]}"
