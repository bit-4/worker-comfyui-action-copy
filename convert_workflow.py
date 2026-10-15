import json, sys
from pathlib import Path
src=Path(sys.argv[1] if len(sys.argv)>1 else 'Wan_Animate2_Distilled.json')
out=Path(sys.argv[2] if len(sys.argv)>2 else 'workflow_api.json')
d=json.loads(src.read_text(encoding='utf-8'))
nodes={n['id']:n for n in d['nodes']}
links={x[0]:x for x in d['links']}
# Exclude UI-only compare branch and unused nodes. Trace backward from primary SaveVideo.
keep=set()
def visit(nid):
 if nid in keep:return
 keep.add(nid)
 for x in nodes[nid].get('inputs',[]):
  if x.get('link') in links:visit(links[x['link']][1])
visit(246)
# Preserve the two string source nodes; exclude comparison node 291 and SaveVideo 292.
api={}
for nid in sorted(keep):
 n=nodes[nid]; inp={}
 named=n.get('widgets_values_named') or {}
 # Named widget keys mirror ComfyUI's API input names, except composite widget keys.
 for key,val in named.items():
  if '.' not in key and key not in ('upload','control_after_generate'):
   inp[key]=val
 for x in n.get('inputs',[]):
  lid=x.get('link')
  if lid in links:
   l=links[lid]
   inp[x['name']]=[str(l[1]),l[2]]
 api[str(nid)]={'class_type':n['type'],'inputs':inp,'_meta':{'title':n.get('title',n['type'])}}
# Correct loop sampler widgets: the uploaded widgets_values_named has a shifted cfg/add_noise mapping.
if '2000' in api:
 v=nodes[2000]['widgets_values']
 for key,val in zip(('width','height','segment_length','noise_seed','_control_after_generate','cfg','add_noise','pose_strength','pose_start_percent','pose_end_percent','reference_image_strength'),v):
  if not key.startswith('_'):api['2000']['inputs'][key]=val
api['2000']['inputs']['cfg']=1.0
api['2000']['inputs']['add_noise']=True
# Set clear request file placeholders.
api['189']['inputs']['image']='reference.png'
api['240']['inputs']['file']='pose.mp4'
api['246']['inputs']['filename_prefix']='wan2_generated'
# Remove unconnected UI-only widget keys from LoadImage/LoadVideo.
for k in ('189','240'):
 api[k]['inputs'].pop('upload',None)
out.write_text(json.dumps(api,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Converted {len(api)} reachable nodes to {out}. MUST validate with the installed ComfyUI /prompt endpoint.')
