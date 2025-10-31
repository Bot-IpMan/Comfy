#!/usr/bin/env bash
set -euo pipefail

cd /opt/ComfyUI

if [[ $# -gt 0 ]]; then
  exec python -u main.py "$@"
fi

if [[ -n "${CLI_ARGS:-}" ]]; then
  # shellcheck disable=SC2086
  exec python -u main.py ${CLI_ARGS}
else
  exec python -u main.py --listen --port 8188
fi
