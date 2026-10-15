#!/usr/bin/env bash
set -euo pipefail
echo "MODEL_DOWNLOAD_MODE=${MODEL_DOWNLOAD_MODE:-auto}"
if [[ "${MODEL_DOWNLOAD_MODE:-auto}" == "auto" ]]; then
  echo "Checking and provisioning model files before starting ComfyUI"
  bash /app/download_models.sh
elif [[ "${MODEL_DOWNLOAD_MODE}" == "skip" ]]; then
  echo "Using model files baked into image"
  bash /app/verify_baked_models.sh
else
  echo "Unsupported MODEL_DOWNLOAD_MODE: $MODEL_DOWNLOAD_MODE" >&2; exit 1
fi
cd /opt/ComfyUI
python main.py --listen 127.0.0.1 --port 8188 > /tmp/comfyui.log 2>&1 &
COMFY_PID=$!
for i in $(seq 1 180); do
  if ! kill -0 "$COMFY_PID" 2>/dev/null; then tail -n 120 /tmp/comfyui.log; exit 1; fi
  if curl -fsS http://127.0.0.1:8188/object_info > /tmp/object_info.json 2>/dev/null; then break; fi
  sleep 2
done
python - <<'PY'
import json
j=json.load(open('/tmp/object_info.json'))
required=['WanAnimate2LoopSampler','LoadVideo','SaveVideo','ResizeImageMaskNode','WanAnimate2Cache','ComfySwitchNode']
missing=[x for x in required if x not in j]
if missing:raise SystemExit('Required ComfyUI nodes unavailable: '+', '.join(missing))
models={'1239':('UNETLoader','unet_name','wan_animate_2_distill_int8_convrot.safetensors'),
        '1007':('VAELoader','vae_name','Wan2_1_VAE_bf16.safetensors'),
        '1009':('CLIPLoader','clip_name','umt5_xxl_fp8_e4m3fn_scaled.safetensors'),
        '1075':('CLIPVisionLoader','clip_name','clip_vision_h.safetensors')}
for node,(cls,key,filename) in models.items():
    choices=j.get(cls,{}).get('input',{}).get('required',{}).get(key,[[]])[0]
    if filename not in choices:
        raise SystemExit(f'Model not visible in ComfyUI: {filename}; choices={choices}')
for nid in ('1243','1244'):
    assert 'resize_type.crop' in json.load(open('/app/workflow_api.json'))[nid]['inputs']
print('Required nodes and model choices verified')
PY
exec python /app/handler.py
