"""Runtime patches for ComfyUI when CUDA is unavailable.

This module is imported automatically by Python (via ``site``) when it is
present on ``sys.path``.  We use this hook to wrap ``comfy.model_management`` so
that it gracefully falls back to CPU execution in environments where CUDA is
not available or when querying CUDA devices raises a runtime error.  Without
this patch ComfyUI crashes during start-up because it blindly calls
``torch.cuda.current_device()``.
"""
from __future__ import annotations

import importlib.abc
import importlib.machinery
import sys
from types import ModuleType
from typing import Any

try:
    import torch
except Exception:  # pragma: no cover - torch import errors are not expected
    torch = None  # type: ignore[assignment]


def _fallback_device() -> "torch.device":  # type: ignore[name-defined]
    """Return a CPU device object even if ``torch`` is ``None``.

    The return type is annotated using a string literal so the module can be
    imported even when ``torch`` failed to import (for example while building
    documentation).  In such a scenario the return value is never used, but we
    still provide a best-effort ``repr`` to avoid surprising behaviour.
    """

    class _DummyDevice:
        def __repr__(self) -> str:  # pragma: no cover - defensive programming
            return "torch.device('cpu')"

    if torch is None:
        return _DummyDevice()  # type: ignore[return-value]
    return torch.device("cpu")


def _make_safe_get_torch_device(original: Any):
    """Wrap ``get_torch_device`` so it falls back to CPU when CUDA is unusable."""

    def safe_get_torch_device(*args: Any, **kwargs: Any):
        if torch is None:
            return _fallback_device()
        try:
            if torch.cuda.is_available():
                return original(*args, **kwargs)
        except Exception:
            # ``torch.cuda.is_available`` or the original function can raise
            # (for example ``cudaGetDeviceCount`` returning an error).  We
            # swallow the exception and fall back to CPU.
            pass
        return _fallback_device()

    return safe_get_torch_device


def _patch_module(module: ModuleType) -> None:
    original = getattr(module, "get_torch_device", None)
    if original is None:
        return

    safe_get_torch_device = _make_safe_get_torch_device(original)
    module.get_torch_device = safe_get_torch_device  # type: ignore[assignment]

    # Keep module level caches (if any) consistent with the patched function.
    for attribute in ("TORCH_DEVICE", "torch_device"):
        if hasattr(module, attribute):
            try:
                setattr(module, attribute, safe_get_torch_device())
            except Exception:
                setattr(module, attribute, _fallback_device())


class _ComfyModelManagementFinder(importlib.abc.MetaPathFinder):
    target_module = "comfy.model_management"

    def find_spec(self, fullname: str, path: Any | None, target: ModuleType | None = None):
        if fullname != self.target_module:
            return None

        spec = importlib.machinery.PathFinder.find_spec(fullname, path)
        if spec is None or spec.loader is None:
            return None
        original_loader = spec.loader

        class _Loader(importlib.abc.Loader):
            def create_module(self, spec):
                if hasattr(original_loader, "create_module"):
                    return original_loader.create_module(spec)
                return None

            def exec_module(self, module):
                original_loader.exec_module(module)
                _patch_module(module)

        spec.loader = _Loader()
        return spec


# Insert our finder at the front so it runs before the default path finder.
sys.meta_path.insert(0, _ComfyModelManagementFinder())
