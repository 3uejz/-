# deploy/ — 私有服务器部署

在私有服务器（非本开发容器）用 Docker Compose 部署后端、数据库与后台。

- `docker-compose.yml`：PostgreSQL、Redis、自建 MinIO 对象存储；Go 后端与 Admin 的 service 定义随后端持久化适配（PG/Redis/MinIO Store 实现）落地后补齐。
- Docker 在本开发容器内不可用，构建请在私有服务器执行。

> 服务定义随 `tasklist.md` 推进逐步补齐。
