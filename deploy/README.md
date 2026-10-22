# deploy/ — 私有服务器部署

在私有服务器（非本开发容器）用 Docker Compose 部署后端、数据库、对象存储与管理后台。

- `docker-compose.yml`：PostgreSQL、Redis、自建 MinIO 对象存储与 Go 后端（同源托管 `/admin` 管理后台）。
- `Dockerfile`：多阶段构建，Node 构建 `admin/`，Go 构建 `server`，运行镜像基于 `postgres:16-alpine`（自带 `pg_dump`/`pg_restore`）。
- `minio-init.sh`：首次启动自动创建 bucket、启用版本控制、创建服务账号与权限。
- `upload-packs.sh`：按清单版本与哈希上传内容包，校验失败即中止。
- `minio-policies/`：`lifetext-server` 与 `ci-rw` 的最小权限策略。
- `.env.example`：环境变量模板，复制为 `.env` 后填写。
- Docker 在本开发容器内不可用，构建请在私有服务器执行。
- 本地开发（旧电脑）用 `scripts/dev-setup.sh` 起依赖容器，完整步骤见 `LOCAL_DEV.md`；本文其余部分是私有服务器部署。

## MinIO 版本说明

MinIO 社区版已停止预编译镜像分发，Docker Hub 上的 `minio/minio` 与 `minio/mc` 已移除。本配置固定到 quay.io 的最后一个社区版标签：

- `quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z`
- `quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z`

该组合只建议在内网使用，控制台不暴露公网。新部署后续可评估 RustFS、SeaweedFS 等仍在维护的 S3 兼容实现，后端代码通过 S3 API 对接，迁移时主要改 `OBJECT_ENDPOINT`。

## 外部 S3（R2 / OSS / COS）

旧电脑或内网 MinIO 不可用时，后端可直接对接公网 S3 兼容存储。已支持 Cloudflare R2、阿里云 OSS、腾讯云 COS 与 Backblaze B2 的 S3 API。

在 `.env` 中设置：

```env
OBJECT_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
OBJECT_REGION=auto
OBJECT_USE_SSL=true
OBJECT_CREATE_BUCKET=false
OBJECT_BUCKET=lifetext-assets
OBJECT_ACCESS_KEY=<scoped-access-key>
OBJECT_SECRET_KEY=<scoped-secret-key>
```

要点：

- `OBJECT_ENDPOINT` 可带 `https://`，带协议时自动启用 TLS。
- R2 的 region 填 `auto`；OSS/COS 填对应地域，例如 `oss-cn-hangzhou`。
- 公网桶由控制台预先创建，`OBJECT_CREATE_BUCKET=false`，避免受限令牌因建桶失败而拒绝启动。
- 令牌只授予该 bucket 的对象读写权限，不要授予账号级管理权限。
- 使用外部 S3 时，`minio` 与 `minio-init` 两个服务可以移除或改用 compose override 停用；后端只需要上面的变量。
- 对象存储不保存 `.env`，密钥只存在服务器环境变量或密钥文件。

对象键约定：

```text
packs/<pack-name>/<version>.ltpack
```

内容清单里的 `url` 使用稳定地址 `/api/v1/content/packs/<pack-name>`，后端按清单中的 version 找到对象并流式返回，支持 HTTP Range 断点续传。

## 服务器准备

- 2 核 4GB 起步，推荐 4 核 8GB
- 数据盘 500GB 起步，推荐 1TB SSD/NVMe
- Debian 12 或 Ubuntu 22.04
- Docker Engine 与 Compose 插件
- 数据目录 `/srv/lifetext/minio/data`

单机 MinIO 没有副本冗余，数据盘建议使用 RAID 或 ZFS，并配置异地备份。

### 旧电脑部署

旧电脑适合做私有 MinIO 与后端主机，按以下配置准备：

- 64 位 CPU，4 核以上，内存 8GB 推荐，最低 4GB
- 系统盘 SSD 128GB 以上，数据盘 1TB SSD 或企业级 HDD
- 有线千兆网络，固定局域网 IP
- BIOS 设置断电恢复自动开机，系统关闭休眠与自动关机
- 建议接 UPS，避免写入过程中断电
- Debian 12 最小安装，只跑 Docker 与备份任务

数据盘挂到 `/srv/lifetext`，`MINIO_DATA_DIR` 指向 `/srv/lifetext/minio/data`。旧电脑同时承担 PostgreSQL、Redis 与 Go 后端时，构建任务仍放在开发机或独立构建机，避免占满 CPU 与内存。

当前包体以顺序读取为主，企业级 HDD 可以胜任；正在使用的城市包放 SSD，历史版本与冷备放 HDD。

## 目录与配置

创建数据目录：

```bash
install -d -m 0750 /srv/lifetext/minio/data
```

复制环境变量模板：

```bash
cp deploy/.env.example deploy/.env
```

生成强随机密钥：

```bash
openssl rand -base64 32
```

把生成值填入 `deploy/.env`，至少替换以下字段：

```env
JWT_SECRET=
ADMIN_PASSWORD=
POSTGRES_PASSWORD=
MINIO_ROOT_USER=lifetext-admin
MINIO_ROOT_PASSWORD=
MINIO_DATA_DIR=/srv/lifetext/minio/data
OBJECT_ENDPOINT=minio:9000
OBJECT_REGION=
OBJECT_USE_SSL=false
OBJECT_CREATE_BUCKET=true
OBJECT_BUCKET=lifetext
OBJECT_ACCESS_KEY=lifetext-server
OBJECT_SECRET_KEY=
CI_ACCESS_KEY=ci-rw
CI_SECRET_KEY=
```

`.env` 已被忽略，不要提交。

## 启动

```bash
cd deploy
docker compose up -d --build
```

初始化流程：

1. `minio` 启动并监听 9000/9001，端口只绑定 `127.0.0.1`。
2. `minio-init` 等待 MinIO 就绪，创建 `lifetext` bucket。
3. 启用版本控制，关闭匿名访问。
4. 创建 `lifetext-server` 与 `ci-rw` 账号并绑定最小权限策略。
5. `server` 在初始化完成后启动。

查看状态：

```bash
docker compose ps
docker compose logs minio-init
```

健康检查：

```bash
curl -fsS http://127.0.0.1:9000/minio/health/live
curl -fsS http://127.0.0.1:8080/api/v1/health
```

管理后台：

```text
http://127.0.0.1:8080/admin
```

MinIO 控制台：

```text
http://127.0.0.1:9001
```

控制台仅限本机或内网访问。需要远程管理时，用 Caddy/Nginx 反代到 HTTPS 并加独立认证。

## 账号与权限

| 账号 | 用途 | 权限 |
|---|---|---|
| `MINIO_ROOT_USER` | 初始化与运维 | 管理员 |
| `lifetext-server` | Go 后端读写存档与内容包 | `lifetext` bucket 读写 |
| `ci-rw` | 构建机上传 source、packs、manifests | `lifetext` bucket 读写 |

客户端不直接持有对象存储密钥。内容包由后端按清单从对象存储读取并流式转发，下载地址稳定为 `/api/v1/content/packs/<name>`；对象存储本身只对后端开放。

轮换账号密钥时，新建一个服务账号并更新 `.env`，重启后端后再禁用旧账号。`mc admin user add` 负责创建用户，已有用户的密钥不会被覆盖。

```bash
mc admin user add local lifetext-server-v2 '<NEW_SECRET>'
mc admin policy attach local lifetext-server-rw --user lifetext-server-v2
```

更新 `.env` 中的 `OBJECT_ACCESS_KEY` 与 `OBJECT_SECRET_KEY` 后：

```bash
docker compose up -d server
mc admin user disable local lifetext-server
```

## Bucket 规划

```text
lifetext/
├─ source/                         原始模型、贴图、音频，按城市分目录
├─ packs/                          运行时内容包
│  └─ <pack-name>/
│     └─ <version>.ltpack
└─ manifests/                      版本、哈希、分片清单
```

清单进 Git，二进制进对象存储。`packs/` 的目录名与版本号必须和清单一致，后端按 `packs/<name>/<version>.ltpack` 读取。

## 构建机上传

构建机安装 `mc` 后配置 `ci-rw`：

```bash
mc alias set lifetext https://assets.example.com ci-rw '<CI_SECRET_KEY>'
```

按清单批量上传，脚本会先校验 SHA256，再写入 `packs/<name>/<version>.ltpack`：

```bash
deploy/upload-packs.sh build/content/manifest.json build/content lifetext/lifetext
```

上传后校验：

```bash
mc stat lifetext/lifetext/packs/jobs/1855ee94dff20a4b.ltpack
mc stat lifetext/lifetext/manifests/manifest.json
```

## 备份与恢复

准备第二台 MinIO 或对象存储：

```bash
mc alias set backup https://backup.example.com '<ACCESS_KEY>' '<SECRET_KEY>'
```

镜像整个 bucket：

```bash
mc mirror --overwrite --preserve lifetext/lifetext backup/lifetext
```

恢复时先进入维护窗口，停止构建与上传，再反向镜像：

```bash
mc mirror --overwrite backup/lifetext lifetext/lifetext
```

不要直接复制运行中的 `/srv/lifetext/minio/data`。备份保留三份：本机、异地、冷备。每季度做一次恢复演练，并用清单中的 SHA256 校验关键包。

## 容量规划

| 项目 | 空间 |
|---|---:|
| 六城运行时包 | 36–48GB |
| 六城源资产 | 100GB 以上 |
| 版本、差量、临时文件 | 50GB 以上 |
| 推荐数据盘 | 500GB 起步，1TB 更稳 |

后续每增加一个 5–8GB 城市，按 10–15GB 预留空间。

## 常用运维

查看日志：

```bash
docker compose logs -f server
docker compose logs -f minio
```

重启后端：

```bash
docker compose restart server
```

停止服务：

```bash
docker compose stop
```

升级镜像前先备份，并把新版本标签写回 `docker-compose.yml`，不要使用 `latest`。

## 数据库备份

后端每 24 小时自动执行一次 `pg_dump` 到 `backups` 卷，保留最近 7 份；也可经 `POST /api/v1/admin/system/backup` 手动触发。
