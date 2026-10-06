# deploy/ — 私有服务器部署

在私有服务器（非本开发容器）用 Docker Compose 部署后端、数据库、对象存储与管理后台。

- `docker-compose.yml`：PostgreSQL、Redis、自建 MinIO 对象存储与 Go 后端（同源托管 `/admin` 管理后台）。
- `Dockerfile`：多阶段构建 —— Node 构建 `admin/` 前端，Go 构建 `server`，最终以 `postgres:16-alpine` 为运行基础（自带 `pg_dump`/`pg_restore`，供每日备份与恢复演练）。
- Docker 在本开发容器内不可用，构建请在私有服务器执行。

## 准备

在同目录创建 `.env`（不要提交）：

```env
# 必填：至少 32 字节
JWT_SECRET=change-me-to-a-long-random-secret-value
# 首次启动幂等创建的管理员
ADMIN_USERNAME=admin
ADMIN_PASSWORD=change-me
# 可覆盖的默认值
POSTGRES_USER=life
POSTGRES_PASSWORD=change-me
POSTGRES_DB=life
MINIO_ROOT_USER=life
MINIO_ROOT_PASSWORD=change-me
OBJECT_BUCKET=lifetext
TELEMETRY_RETENTION_DAYS=90
```

## 启动

```bash
docker compose up -d --build
```

- 健康检查：`GET http://127.0.0.1:8080/api/v1/health`
- 管理后台：`http://127.0.0.1:8080/admin`
- 指标：`GET http://127.0.0.1:8080/metrics`

## 备份

后端每 24 小时自动执行一次 `pg_dump` 到 `backups` 卷，保留最近 7 份；也可经 `POST /api/v1/admin/system/backup` 手动触发。

> 服务定义随 `tasklist.md` 推进逐步补齐。
