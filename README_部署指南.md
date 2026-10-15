# Wan Animate 2 Distilled → RunPod Serverless 部署指南

## 文件说明
- `workflow_api.json`：根据上传的 UI JSON 自动转换的**待验证** API 图；已去掉视频对比支路（291/292），仅保留主视频保存节点 246。
- `convert_workflow.py`：从 UI JSON 生成初始 API 图的工具。**不能代替 ComfyUI 原生 Export (API) 的校验**。
- `Dockerfile`：ComfyUI + V3 Loop Sampler + RunPod Python handler。
- `download_models.sh`：按原始工作流提供的 Hugging Face 地址下载 4 个模型。
- `entrypoint.sh`：启动 ComfyUI、检测关键节点，再启动 RunPod Worker。
- `handler.py`：接受图片和视频 URL/Base64、提示词等，调用 ComfyUI 并将 MP4 上传 S3。

## 重要限制（上线前必看）
1. 工作流来自 ComfyUI **UI Format**；转换得到的 API JSON 是静态转换结果，**尚未通过 GPU 或 ComfyUI `/prompt` 实测**。如出现 `invalid_prompt`，应在与镜像相同版本的 ComfyUI 中加载原始 UI JSON，选择 **Workflow → Export (API)**，用生成的 API 图替换 `workflow_api.json`，然后重新构建。若节点缺失，先确认插件安装成功。
2. 该工作流中的 `WanAnimate2LoopSampler` 为 **V3 ComfyUI 扩展**，必须使用兼容版本；启动脚本将检查关键节点，不兼容即启动失败。
3. `LoadVideo`、`SaveVideo`、`ResizeImageMaskNode` 的具体 API 字段名在不同 ComfyUI 版本可能变化；最终以 `/object_info` 返回的节点定义和原生 Export (API) 为准。
4. 输出上传使用 S3 兼容存储；未配置 `S3_BUCKET` 的任务将生成后报错，不会直接把大 MP4 塞入响应。
5. 动作一致性不仅取决于 `pose_strength=1`，还取决于姿态预处理、人物对齐、输入视频清晰度与分辨率；上线前应实测动作同步效果。
6. 默认只接受公共 HTTPS 输入 URL（禁止自动跟随跳转）或 Base64；推荐 S3 预签名输入 URL。生产环境还应根据需要增加域名白名单/文件格式校验。

## 1. 准备模型
由 `download_models.sh` 下载：
- `diffusion_models/wan_animate_2_distill_int8_convrot.safetensors`
- `vae/Wan2_1_VAE_bf16.safetensors`
- `text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors`
- `clip_vision/clip_vision_h.safetensors`

### 建议：镜像内预置模型
在当前目录执行：
```bash
docker buildx build --platform linux/amd64 --build-arg BAKE_MODELS=1 -t YOUR_DOCKERHUB/wan-animate2-runpod:v1 --load .
docker push YOUR_DOCKERHUB/wan-animate2-runpod:v1
```
模型文件很大，请预留磁盘及镜像仓库存储。`BAKE_MODELS=0` 构建的镜像**不包含模型**，不能直接执行此工作流（除非运行环境另行挂载模型并正确映射路径）。首次构建时需要可访问 Hugging Face、PyTorch 和 GitHub。

## 2. 在 RunPod 创建 Serverless Endpoint
1. RunPod Console → Serverless → New Endpoint。
2. 选择自定义容器镜像 `YOUR_DOCKERHUB/wan-animate2-runpod:v1`（或先创建 Template）。
3. GPU 建议先用 **48GB 显存或以上**进行兼容性试运行，若出现 OOM 则提高显存/降低帧数及分辨率；此为试运行建议，不是经实测得出的最低配置。
4. Worker 数量建议 `Min/Active 0`、`Max 1` 起步；容器磁盘大小按镜像层与运行缓存增加。
5. 设置环境变量：
   - `S3_BUCKET`：结果存储 Bucket 名称（必需）
   - `AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`：S3 凭证（必需）
   - `AWS_DEFAULT_REGION`：区域，默认 `us-east-1`
   - `S3_ENDPOINT_URL`：非 AWS S3 的兼容存储可设置
   - `GENERATION_TIMEOUT=1800`：ComfyUI 任务等待上限，秒
   - `MAX_INPUT_MB=100`：允许的单个源媒体最大体积，MB
6. 部署后查看 Worker 日志，确认 `Required nodes verified`；如果没有出现，阅读 ComfyUI 的 `/tmp/comfyui.log` 报错。

## 3. 调用方式
使用异步接口 `/run`。请求中的 `image`、`video` 可以是 HTTPS URL 或 Base64 数据串。较大视频**推荐预签名 HTTPS URL**，避免 RunPod API JSON 请求体限制。
```bash
curl -X POST "https://api.runpod.ai/v2/ENDPOINT_ID/run" \
 -H "Authorization: Bearer RUNPOD_API_KEY" \
 -H "Content-Type: application/json" \
 -d '{"input":{"image":"https://YOUR_STORAGE/reference.png","video":"https://YOUR_STORAGE/pose.mp4","character_prompt":"A dancer in a black jacket","motion_prompt":"Keep movement faithful to the source video","seed":42}}'
```
获取任务状态：
```bash
curl -H "Authorization: Bearer RUNPOD_API_KEY" "https://api.runpod.ai/v2/ENDPOINT_ID/status/JOB_ID"
```
成功时 `output.video_url` 为带有效期的 S3 下载链接，`output.prompt_id` 为 ComfyUI 执行任务编号。

## 4. 推荐的验证流程
1. 在与 Docker 镜像相同的 ComfyUI 版本中打开原始 `Wan_Animate2_Distilled.json` 并确认能完整生成视频。
2. 原生 Export (API)，替换包里的 `workflow_api.json`，并核对输入节点 IDs、文件参数名及输出节点 ID 是否与本 handler 一致。
3. 在容器中用 `/object_info` 检查 `WanAnimate2LoopSampler` 节点及其输入定义。
4. 调用 `/prompt` 验证 API JSON 的所有节点参数。
5. 从 2～3 秒的姿态视频开始，再用 10 秒视频验证自动分段结果帧数和动作一致性。
6. 再构建发布镜像并用 `/run` 做端到端测试。

## 常见问题
- `Node WanAnimate2LoopSampler not found`：插件未安装或 ComfyUI 版本不支持 V3 插件。
- `invalid_prompt`：API JSON 中有字段/类型不匹配；重新从 ComfyUI 原生导出。
- `Cannot find model`：没有下载模型或模型目录不正确。
- `No generated video found`：当前 ComfyUI 的视频历史输出结构与 handler 预期不同；检查 `/history/{prompt_id}` 中保存视频节点输出。
- `OOM`：降低目标分辨率、截短输入视频、升级显卡。分段循环并不保证显存占用恒定。
- 视频动作与源视频不一致：检查人物姿态预处理，保持输入动作视频比例与输出分辨率一致；单纯提升 pose_strength 不保证精确复制动作。


## v2 修复（针对 HTTP 400 验证失败）
- 已修正 1243/1244 节点必填的 `resize_type.crop=center`，并补齐 1243 的 `resize_type.width/height`。
- 已修复转换脚本错误丢弃带点号参数的问题。
- Docker 默认 `BAKE_MODELS=1`，构建时下载 4 个模型；模型尺寸异常时立即终止构建。
- Worker 启动时从 `/object_info` 检查实际可见的四个模型名称，不存在就直接启动失败，防止用户任务反复报错。
- **如果挂载了网络卷并覆盖 `/opt/ComfyUI/models`，需要确认挂载后仍包含四个文件。**
- 修改后请重新构建镜像并使用新的版本 tag 更新 RunPod endpoint。
- 本次仅静态验证，不代表已在 RunPod GPU 实测。
