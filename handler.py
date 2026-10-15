"""RunPod handler that runs the prepared ComfyUI API prompt and returns an MP4 URL.
Set S3_BUCKET and optionally S3_ENDPOINT_URL to upload generated videos.
"""
import base64, copy, json, os, pathlib, time, uuid
import requests, runpod
from urllib.parse import urlsplit

COMFY='http://127.0.0.1:8188'
ROOT=pathlib.Path('/opt/ComfyUI')
INPUT=ROOT/'input'
OUTPUT=ROOT/'output'
WORKFLOW=json.loads(pathlib.Path('/app/workflow_api.json').read_text(encoding='utf-8'))
TIMEOUT=int(os.getenv('GENERATION_TIMEOUT','1800'))
MAX_INPUT_MB=int(os.getenv('MAX_INPUT_MB','100'))

def load_media(value, suffix):
    if not isinstance(value,str) or not value:raise ValueError(f'{suffix} is required as URL or base64')
    if value.startswith('https://'):
        # Block obvious local/private targets; prefer trusted media storage for production.
        import ipaddress, socket
        host=urlsplit(value).hostname
        if not host:raise ValueError('invalid input URL')
        addresses=socket.getaddrinfo(host,None)
        if any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):raise ValueError('input URL resolves to non-public address')
        with requests.get(value,timeout=(15,120),stream=True,allow_redirects=False) as r:
            r.raise_for_status()
            chunks=[]; size=0
            for chunk in r.iter_content(1024*1024):
                size+=len(chunk)
                if size>MAX_INPUT_MB*1024*1024:raise ValueError('media too large')
                chunks.append(chunk)
            return b''.join(chunks)
    if value.startswith('data:'):value=value.split(',',1)[1]
    data=base64.b64decode(value,validate=True)
    if len(data)>MAX_INPUT_MB*1024*1024:raise ValueError('media too large')
    return data

def submit(workflow):
    r=requests.post(f'{COMFY}/prompt',json={'prompt':workflow,'client_id':str(uuid.uuid4())},timeout=60)
    if not r.ok:raise RuntimeError(f'ComfyUI prompt rejected: {r.status_code}: {r.text[:4000]}')
    return r.json()['prompt_id']

def wait_history(pid):
    until=time.monotonic()+TIMEOUT
    while time.monotonic()<until:
        r=requests.get(f'{COMFY}/history/{pid}',timeout=30);r.raise_for_status()
        item=r.json().get(pid)
        if item:
            status=item.get('status',{})
            if status.get('status_str')=='error':raise RuntimeError(str(status.get('messages',[]))[:3000])
            return item
        time.sleep(3)
    raise TimeoutError(f'ComfyUI execution exceeded {TIMEOUT} seconds')

def result_file(history):
    outs=history.get('outputs',{})
    for record in outs.values():
        for category in ('videos','gifs','files','images'):
            for item in record.get(category,[]):
                name=item.get('filename','')
                if name.lower().endswith(('.mp4','.webm','.mov')):
                    sub=item.get('subfolder',''); kind=item.get('type','output')
                    if kind!='output':continue
                    base=OUTPUT.resolve(); path=(base/sub/name).resolve()
                    if not path.is_relative_to(base) or not path.is_file():continue
                    return path
    # Some ComfyUI versions report only API node results, so narrow to this request prefix
    raise RuntimeError('No generated video found in ComfyUI history. Inspect SaveVideo output schema.')

def deliver(path,pid):
    bucket=os.getenv('S3_BUCKET')
    if bucket:
        import boto3
        client=boto3.client('s3',endpoint_url=os.getenv('S3_ENDPOINT_URL') or None,
                            region_name=os.getenv('AWS_DEFAULT_REGION','us-east-1'))
        key=f'wan-animate2/{pid}.mp4'
        client.upload_file(str(path),bucket,key,ExtraArgs={'ContentType':'video/mp4'})
        expires=int(os.getenv('PRESIGNED_URL_EXPIRES','86400'))
        url=client.generate_presigned_url('get_object',Params={'Bucket':bucket,'Key':key},ExpiresIn=expires)
        return {'video_url':url,'bucket':bucket,'key':key,'prompt_id':pid}
    # Avoid returning a huge video blob if object storage is not configured.
    raise RuntimeError('S3_BUCKET not configured: configure S3 storage to return generated video URLs')

def handler(job):
    data=job.get('input') or {}
    if not isinstance(data,dict):raise ValueError('input must be an object')
    image=load_media(data.get('image'),'image')
    video=load_media(data.get('video'),'video')
    token=uuid.uuid4().hex
    image_name=f'{token}_reference.png'
    video_name=f'{token}_pose.mp4'
    INPUT.mkdir(parents=True,exist_ok=True)
    img=INPUT/image_name; vid=INPUT/video_name
    img.write_bytes(image);vid.write_bytes(video)
    try:
        flow=copy.deepcopy(WORKFLOW)
        flow['189']['inputs']['image']=image_name
        flow['240']['inputs']['file']=video_name
        if data.get('character_prompt') is not None:flow['605']['inputs']['value']=str(data['character_prompt'])
        if data.get('motion_prompt') is not None:flow['604']['inputs']['value']=str(data['motion_prompt'])
        if data.get('seed') is not None:flow['2000']['inputs']['noise_seed']=int(data['seed'])
        for key in ('width','height'):
            if data.get(key) is not None:
                v=int(data[key]);
                if v<256 or v>1280 or v%2:raise ValueError(f'{key}: expected even integer in [256,1280]')
                flow['2000']['inputs'][key]=v
                flow['1243']['inputs'][f'resize_type.{key}']=v
        flow['246']['inputs']['filename_prefix']=f'wan2_generated/{token}'
        pid=submit(flow)
        return deliver(result_file(wait_history(pid)),pid)
    finally:
        img.unlink(missing_ok=True);vid.unlink(missing_ok=True)

if __name__=='__main__':
    runpod.serverless.start({'handler':handler})
