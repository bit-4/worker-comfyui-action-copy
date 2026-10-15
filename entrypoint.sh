#!/usr/bin/env bash
set -euo pipefail
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
print('Required nodes verified')
PY
exec python /app/handler.py
