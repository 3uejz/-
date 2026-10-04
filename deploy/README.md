# deploy/ — 私有服务器部署

在私有服务器（非本开发容器）用 Docker Compose 部署后端、数据库与后台。

- `docker-compose.yml`：PostgreSQL、Redis、Go 后端、Admin（待后端骨架就绪后补 service 定义）。
- Docker 在本开发容器内不可用，构建请在私有服务器执行。

> 服务定义随 `tasklist.md` 推进逐步补齐。
