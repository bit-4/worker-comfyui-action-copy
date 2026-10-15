#!/usr/bin/env bash
set -euo pipefail
BASE=https://huggingface.co/Comfy-Org/Wan-Animate-2/resolve/main
mkdir -p /opt/ComfyUI/models/{diffusion_models,vae,text_encoders,clip_vision}
get () { echo "Downloading $2"; curl -fL --retry 5 --retry-delay 5 -o "/opt/ComfyUI/models/$2" "$BASE/$2"; }
get diffusion_models/wan_animate_2_distill_int8_convrot.safetensors
get vae/Wan2_1_VAE_bf16.safetensors
get text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
get clip_vision/clip_vision_h.safetensors

# Reject missing or obviously incomplete model files during docker build.
python - <<'PYMODELS'
from pathlib import Path
root=Path('/opt/ComfyUI/models')
minimum={'diffusion_models/wan_animate_2_distill_int8_convrot.safetensors':10_000_000_000,
         'vae/Wan2_1_VAE_bf16.safetensors':100_000_000,
         'text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors':2_000_000_000,
         'clip_vision/clip_vision_h.safetensors':500_000_000}
for name,size in minimum.items():
    file=root/name
    assert file.is_file() and file.stat().st_size>=size, f'Model missing or incomplete: {file}'
    print('Model OK:',file,file.stat().st_size)
PYMODELS
