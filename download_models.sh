#!/usr/bin/env bash
set -euo pipefail
BASE=https://huggingface.co/Comfy-Org/Wan-Animate-2/resolve/main
mkdir -p /opt/ComfyUI/models/{diffusion_models,vae,text_encoders,clip_vision}
get () { echo "Downloading $2"; curl -fL --retry 5 --retry-delay 5 -o "/opt/ComfyUI/models/$2" "$BASE/$2"; }
get diffusion_models/wan_animate_2_distill_int8_convrot.safetensors
get vae/Wan2_1_VAE_bf16.safetensors
get text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
get clip_vision/clip_vision_h.safetensors
