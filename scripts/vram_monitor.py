#!/usr/bin/env python3
"""Lightweight VRAM monitor for Pascal-era GPUs.

The script mimics ``nvidia-smi -l`` by sampling memory usage at a fixed
interval and optionally calling ``torch.cuda.empty_cache()`` whenever the
available memory goes below the configured threshold.

It is intended to be executed *inside* the ComfyUI container so that it
uses the same PyTorch build as the application itself.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from typing import Optional

try:
    import torch
except Exception as exc:  # pragma: no cover - runtime dependency check
    print("[vram_monitor] Failed to import torch:", exc, file=sys.stderr)
    sys.exit(1)


def query_nvidia_smi(binary: str) -> Optional[str]:
    """Return a concise utilisation line from ``nvidia-smi`` or ``None``."""

    if shutil.which(binary) is None:
        return None

    cmd = [
        binary,
        "--query-gpu=timestamp,name,memory.total,memory.used,memory.free,utilization.gpu",
        "--format=csv,noheader,nounits",
    ]
    try:
        completed = subprocess.run(  # noqa: S603,S607 - local command
            cmd,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:  # pragma: no cover - runtime guard
        return f"nvidia-smi failed: {exc}"

    return completed.stdout.strip().splitlines()[0] if completed.stdout else ""


def human_readable(info: tuple[int, int]) -> str:
    free, total = info
    return f"{(total - free) / 1024:.1f}/{total / 1024:.1f} GB used"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--threshold-mb",
        type=int,
        default=3400,
        help="Free VRAM threshold (in MB) that triggers torch.cuda.empty_cache().",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Sampling interval in seconds (similar to nvidia-smi -l).",
    )
    parser.add_argument(
        "--nvidia-smi",
        default="nvidia-smi",
        help="Path to the nvidia-smi binary.",
    )
    parser.add_argument(
        "--no-empty-cache",
        action="store_true",
        help="Disable torch.cuda.empty_cache() calls; useful for passive monitoring.",
    )
    args = parser.parse_args()

    if not torch.cuda.is_available():  # pragma: no cover - runtime guard
        print("[vram_monitor] CUDA is not available; nothing to monitor.", file=sys.stderr)
        sys.exit(1)

    device = torch.device("cuda:0")
    print(f"[vram_monitor] Monitoring {torch.cuda.get_device_name(device)}", file=sys.stderr)
    print(
        f"[vram_monitor] Interval={args.interval:.2f}s threshold={args.threshold_mb} MB",
        file=sys.stderr,
    )

    try:
        while True:
            torch.cuda.synchronize()
            free, total = torch.cuda.mem_get_info(device)
            free_mb = free // (1024 * 1024)
            stats_line = query_nvidia_smi(args.nvidia_smi)
            usage_line = human_readable((free // (1024 * 1024), total // (1024 * 1024)))
            if stats_line:
                print(f"{time.strftime('%H:%M:%S')} | {stats_line} | {usage_line}")
            else:
                print(f"{time.strftime('%H:%M:%S')} | {usage_line}")

            if free_mb < args.threshold_mb and not args.no_empty_cache:
                torch.cuda.empty_cache()
                torch.cuda.ipc_collect()
                print(
                    f"[vram_monitor] Cache cleared (free={free_mb} MB < {args.threshold_mb} MB)",
                    file=sys.stderr,
                )

            time.sleep(max(args.interval, 0.1))
    except KeyboardInterrupt:  # pragma: no cover - interactive loop
        print("[vram_monitor] Stopped by user.", file=sys.stderr)


if __name__ == "__main__":
    main()
