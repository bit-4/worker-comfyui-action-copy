FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04
ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv git git-lfs curl ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
RUN pip install --upgrade pip setuptools wheel && pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && pip install -r /opt/ComfyUI/requirements.txt
RUN mkdir -p /opt/ComfyUI/custom_nodes && git clone --depth 1 https://github.com/vjumpkung/comfyui-wan-animate-2-loop-sampler.git /opt/ComfyUI/custom_nodes/comfyui-wan-animate-2-loop-sampler
RUN pip install runpod requests boto3 && if [ -f /opt/ComfyUI/custom_nodes/comfyui-wan-animate-2-loop-sampler/requirements.txt ]; then pip install -r /opt/ComfyUI/custom_nodes/comfyui-wan-animate-2-loop-sampler/requirements.txt; fi
WORKDIR /app
COPY handler.py workflow_api.json entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh
# Download model weights only when requested. Recommended: bake models during image build for cold-start speed.
COPY download_models.sh verify_baked_models.sh /app/
RUN chmod +x /app/download_models.sh /app/verify_baked_models.sh
# Always embed the four model files in the image at build time.
# RunPod's Dockerfile builder must have enough disk for the final OCI archive and layers.
RUN bash /app/download_models.sh
ENV MODEL_DOWNLOAD_MODE=skip
CMD ["/app/entrypoint.sh"]
