# Wan Animate 2 · RunPod Serverless v6（Docker 构建时下载模型）

本包从 v4 修复过的 API 工作流和 Handler 构建。**不需要 Network Volume**；四个模型在 `docker build` 的 `RUN bash /app/download_models.sh` 阶段直接下载进 `/opt/ComfyUI/models`，并成为镜像的一部分。Worker 启动时仅校验模型，不再次下载。

## 发布方法

1. 解压全部文件，将文件提交到实际 RunPod Dockerfile 构建仓库的同一目录（`Dockerfile` 与 `download_models.sh` 等需处于同一构建上下文）。
2. 在 RunPod 创建新构建，确认 Dockerfile 使用本包中的版本，并查看 `[MODEL DOWNLOAD]`、`[MODEL COMPLETE]` 和 `[MODEL OK]` 日志。
3. 构建成功后，将生成的 Docker 镜像用于 Serverless Endpoint；不必挂载 Network Volume。若旧 Endpoint 曾设置 `MODEL_VOLUME_ROOT`，可以删除；`MODEL_DOWNLOAD_MODE=skip` 已在镜像内设置。
4. 继续配置 `S3_BUCKET`、S3 凭据及其他 Handler 使用的环境变量，才能得到视频 URL。
5. 以原 Postman JSON 调用 Endpoint 的 `/run`，再用 `/status/{job_id}` 查询。

## 注意

- 模型文件合计可能超过 20GB，构建容器、镜像层、OCI 打包及缓存会需要**明显大于模型总大小**的可用磁盘空间。RunPod 的托管 Dockerfile Builder 如果因磁盘空间、网络或执行时间限制而失败，应在有充足存储的机器/CI 上构建并推送镜像，再让 Endpoint 拉取镜像；不要把镜像构建错误理解为 ComfyUI 节点错误。
- 大模型的下载地址来自 Comfy-Org/Wan-Animate-2；脚本通过文件最小长度过滤明显不完整的下载，但**没有校验官方 SHA256**，所以不能保证文件内容完整无损。
- 即使构建成功，GPU 执行仍需验证节点版本、模型加载和生成效果。
- 无论是否设置 `BAKE_MODELS`，v6 都强制下载模型；不要用旧版 Dockerfile 覆盖本版。
