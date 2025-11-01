#!/usr/bin/env bash
set -euo pipefail

cd /opt/ComfyUI

# Агресивна оптимізація пам'яті
export MALLOC_ARENA_MAX=2
export MALLOC_MMAP_THRESHOLD_=131072
export MALLOC_TRIM_THRESHOLD_=131072
export MALLOC_TOP_PAD_=131072
export MALLOC_MMAP_MAX_=65536

# Python оптимізації
export PYTHONHASHSEED=0
export PYTHONMALLOC=malloc

ensure_source_tree() {
  if [[ -f main.py ]]; then
    return
  fi

  local repo="${COMFYUI_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
  local ref="${COMFYUI_REF:-master}"

  echo "[docker-entrypoint] ComfyUI sources missing, cloning ${repo} (${ref})" >&2

  local tmp_dir
  tmp_dir=$(mktemp -d)

  git clone --depth 1 --branch "${ref}" "${repo}" "${tmp_dir}"
  (cd "${tmp_dir}" && git submodule update --init --recursive)

  shopt -s dotglob
  for item in "${tmp_dir}"/*; do
    local name
    name=$(basename "${item}")
    if [[ "${name}" == ".git" ]]; then
      continue
    fi
    if [[ -e "${name}" ]]; then
      continue
    fi
    cp -r "${item}" "${name}"
  done
  shopt -u dotglob

  rm -rf "${tmp_dir}"
}

ensure_source_tree

# Очищуємо кеш перед стартом (якщо можливо)
sync
if [[ -f /proc/sys/vm/drop_caches && -w /proc/sys/vm/drop_caches ]]; then
  echo 3 > /proc/sys/vm/drop_caches || true
else
  echo "[docker-entrypoint] Skipping cache drop: /proc/sys/vm/drop_caches is not writable" >&2
fi

check_cuda_available() {
  if ! command -v python >/dev/null 2>&1; then
    return 1
  fi

  python - <<'PY'
import sys

try:
    import torch
except Exception:
    sys.exit(1)

try:
    available = torch.cuda.is_available() and torch.cuda.device_count() > 0
except Exception:
    available = False

sys.exit(0 if available else 1)
PY
}

if [[ $# -gt 0 ]]; then
  if [[ "$1" == -* ]]; then
    exec python -u main.py "$@"
  else
    exec "$@"
  fi
fi

declare -a args
if [[ -n "${CLI_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  args=( ${CLI_ARGS} )
fi

if [[ ${#args[@]} -eq 0 ]]; then
  args=(--listen --port 8188)
fi

if ! check_cuda_available; then
  if [[ " ${args[*]} " != *" --cpu "* ]]; then
    args+=(--cpu)
  fi
fi

exec python -u main.py "${args[@]}"
