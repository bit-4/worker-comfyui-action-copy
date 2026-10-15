#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[BUILD MODEL ERROR] line=$LINENO status=$? command=$BASH_COMMAND" >&2' ERR
ROOT="${COMFY_MODEL_ROOT:-/opt/ComfyUI/models}"
BASE="${HF_MODEL_BASE:-https://huggingface.co/Comfy-Org/Wan-Animate-2/resolve/main}"
FILES=(
  'diffusion_models/wan_animate_2_distill_int8_convrot.safetensors'
  'vae/Wan2_1_VAE_bf16.safetensors'
  'text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors'
  'clip_vision/clip_vision_h.safetensors'
)
MIN_BYTES=(10000000000 100000000 2000000000 500000000)
for i in "${!FILES[@]}"; do
  rel="${FILES[$i]}"; target="$ROOT/$rel"; part="${target}.part"
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && (( $(stat -c %s "$target") >= MIN_BYTES[i] )); then
    echo "[MODEL PRESENT] $rel bytes=$(stat -c %s "$target")"; continue
  fi
  echo "[MODEL DOWNLOAD] $rel"
  # The retry is external to curl to give a new clean connection if an intermediary breaks resume.
  success=0
  for attempt in 1 2 3 4 5 6; do
    echo "[MODEL ATTEMPT] $rel $attempt/6"
    if curl -fL --show-error --connect-timeout 40 --max-time 0 \
      --retry 3 --retry-all-errors --retry-delay 8 \
      --continue-at - --output "$part" \
      --write-out '[MODEL HTTP] status=%{http_code} downloaded=%{size_download} bytes\n' \
      "$BASE/$rel"; then
      if [[ -f "$part" ]] && (( $(stat -c %s "$part") >= MIN_BYTES[i] )); then
        mv -f "$part" "$target"
        echo "[MODEL COMPLETE] $rel bytes=$(stat -c %s "$target")"
        success=1; break
      fi
      echo "[MODEL FILE TOO SMALL] $rel bytes=$(stat -c %s "$part") min=${MIN_BYTES[$i]}" >&2
    else
      echo "[MODEL TRANSFER FAILED] $rel attempt=$attempt" >&2
    fi
    sleep 10
  done
  if (( success == 0 )); then
    echo "[MODEL FATAL] $rel failed after 6 attempts; inspect HTTP errors, storage capacity, and Hugging Face connectivity." >&2
    exit 21
  fi
done
bash /app/verify_baked_models.sh
