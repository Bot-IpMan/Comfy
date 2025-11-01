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

# Очищуємо кеш перед стартом
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

if [[ $# -gt 0 ]]; then
  exec python -u main.py "$@"
fi

if [[ -n "${CLI_ARGS:-}" ]]; then
  # shellcheck disable=SC2086
  exec python -u main.py ${CLI_ARGS}
else
  exec python -u main.py --listen --port 8188 --cpu
fi
