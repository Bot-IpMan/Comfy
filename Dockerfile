FROM ubuntu:22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 comfyui && useradd -m -u 1000 -g comfyui comfyui
WORKDIR /opt
COPY --chown=comfyui:comfyui ComfyUI /opt/ComfyUI
WORKDIR /opt/ComfyUI

RUN python3 -m venv /opt/ComfyUI/venv && \
    /opt/ComfyUI/venv/bin/pip install --upgrade pip==24.0

# CPU-only PyTorch
RUN /opt/ComfyUI/venv/bin/pip install --no-cache-dir \
    torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1

RUN if [ -f requirements.txt ]; then \
        /opt/ComfyUI/venv/bin/pip install --no-cache-dir -r requirements.txt; \
    fi

RUN ln -sf /opt/ComfyUI/venv/bin/pip /usr/local/bin/pip && \
    ln -sf /opt/ComfyUI/venv/bin/python /usr/local/bin/python
ENV PATH="/opt/ComfyUI/venv/bin:${PATH}"

FROM base AS runtime
USER root
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN mkdir -p /opt/ComfyUI/{models,input,output,custom_nodes,user} && \
    chown -R comfyui:comfyui /opt/ComfyUI
USER comfyui
EXPOSE 8188
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
