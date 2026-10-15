#!/usr/bin/env bash
set -euo pipefail
ROOT="${COMFY_MODEL_ROOT:-/opt/ComfyUI/models}"
files=(
 'diffusion_models/wan_animate_2_distill_int8_convrot.safetensors'
 'vae/Wan2_1_VAE_bf16.safetensors'
 'text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors'
 'clip_vision/clip_vision_h.safetensors'
)
minimum=(10000000000 100000000 2000000000 500000000)
for i in "${!files[@]}"; do
 path="$ROOT/${files[$i]}"
 if [[ ! -f "$path" ]]; then echo "[MODEL MISSING] $path" >&2; exit 31; fi
 size=$(stat -c %s "$path")
 if (( size < minimum[i] )); then echo "[MODEL TOO SMALL] $path actual=$size minimum=${minimum[$i]}" >&2; exit 32; fi
 echo "[MODEL OK] ${files[$i]} bytes=$size"
done
