# 本地开发指南

开发已从云端容器切到旧电脑本地。依赖服务用 Docker 跑，Go 后端与管理端在宿主机直接运行，Godot 打开 `client/`。所有本地数据落在仓库的 `.data/`，已被 Git 忽略；旧电脑的磁盘就是内容主存储，不再需要对象存储或远程穿透。

## 环境要求

- Debian 12 / Ubuntu 22.04 及以上，x86_64
- Docker Engine + Compose 插件
- Go 1.25+（`server` 依赖会经 `GOTOOLCHAIN` 自动拉取 1.26）
- Node.js 22 + npm
- Python 3.11
- Godot 4.7.2-stable（客户端）、Blender 4.5 LTS（可选，资产工具）
- 可用磁盘建议 100GB 以上，MinIO 数据在 `.data/minio`

本地开发包已包含 `.toolchain/godot`，解包后脚本会直接使用它。

## 首次准备

```bash
tar -xzf lifetext-local-dev.tar.gz
cd lifetext
bash scripts/doctor.sh
bash scripts/dev-setup.sh
```

`dev-setup.sh` 会做四件事：

1. 从 `deploy/.env.example` 生成 `deploy/.env`，写入随机本地密钥并设为 0600
2. 启动 PostgreSQL、Redis、MinIO，创建 `lifetext` 桶与服务账号
3. 下载 `server`、`tools/contentbuilder`、`tools/genbaseline` 的 Go 依赖
4. 在 `admin/` 下执行 `npm ci`

这些步骤可重复执行；已有 `.env` 会保留。

## 日常启动

```bash
# 终端 1：Go 后端，127.0.0.1:8080
bash scripts/dev-server.sh

# 终端 2：React 管理端，127.0.0.1:5173
bash scripts/dev-web.sh

# 终端 3：Godot 编辑器
bash scripts/dev-client.sh
```

服务地址：

- 后端 API：http://127.0.0.1:8080
- 管理端：http://127.0.0.1:5173（`/api` 代理到后端）
- MinIO 控制台：http://127.0.0.1:9001

管理端登录账号取自 `deploy/.env` 的 `ADMIN_USERNAME` 与 `ADMIN_PASSWORD`。

## 依赖服务

```bash
bash scripts/dev-deps.sh status
bash scripts/dev-deps.sh logs
bash scripts/dev-deps.sh stop
bash scripts/dev-deps.sh start
```

`stop` 只停容器，保留 PostgreSQL、Redis 与 MinIO 数据。MinIO 的宿主机目录由 `.env` 的 `MINIO_DATA_DIR` 指定，默认是仓库下的 `.data/minio`。

## 测试

```bash
# 全量：schema、OpenAPI、内容工具链、Godot、Go，约 8 分钟
bash scripts/test.sh

# 单个 Godot 套件
./.toolchain/godot --headless --path client --script res://tests/intent_executor_test.gd

# 单个 Go 包
cd server && go test ./internal/api
```

首次全量测试前会执行一次 Godot 导入，生成 `client/.godot/`。

## 数据与内容包

- `.data/minio`：物体存储数据，放全量美术与音频包
- `.data/server`：后端本地文件兜底
- `.data/backups`：数据库备份
- `deploy/.env`：本地密钥，已在 `.gitignore` 中

内容包的稳定下载地址是 `/api/v1/content/packs/<name>`，对象键是 `packs/<name>/<version>.ltpack`。本地可以直接把内容包上传到 MinIO 的 `lifetext` 桶，清单放到 `manifests/manifest.json`。构建机上传仍可用 `deploy/upload-packs.sh`。

## 从云端迁回本地

1. 下载 `lifetext-local-dev.tar.gz`，或用 Git 拉取仓库后单独复制 `.toolchain/godot`
2. 按上面的首次准备执行
3. 全量测试通过后，再把内容资产从云端或备份盘拷入 `.data/minio`
4. 云端工作区可以停用；后续提交直接从旧电脑推到 GitHub

不需要路由器端口映射、SSH 反向隧道或第三方内网穿透。

## 常见问题

- `docker: permission denied`：把当前用户加入 `docker` 组后重新登录
- 端口被占用：改 `deploy/.env` 的端口映射，或停掉占用 5432/6379/9000/8080/5173 的进程
- Godot 打不开：确认有桌面会话；纯命令行测试用 `--headless`
- `npm ci` 慢：配置 npm 镜像后重试
- Go 首次构建慢：`go mod download` 会缓存到 `~/go/pkg/mod`
- 全量测试偶发超时：单独重跑对应套件，或给 Godot 测试设置 `timeout 900`
