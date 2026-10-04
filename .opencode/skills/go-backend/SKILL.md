---
name: go-backend
description: Use when working on the Go modular-monolith backend under server/ — Go modules, HTTP/gRPC APIs, PostgreSQL, Redis, migrations, backend tests, and the React admin API. Trigger keywords: Go, golang, server/, go.mod, PostgreSQL, psql, Redis, migration, backend API.
---

# Go 后端技能

## 运行时

- Go **1.25.x**（`/usr/local/go`）。
- PostgreSQL 与 Redis 本地已装：`bash scripts/services.sh start|stop|status`。
- Docker 在本容器不可用；镜像与 compose 只写进 `deploy/`，在私有服务器执行。

## 架构约定

- **模块化单体**：按设计中的模块划分（账号、云存档、内容与远程配置、传承档案、遥测、worldsim 世界模拟、Admin）。
- 后端只权威「全球人口与宏观经济统计」等客户端无法承担的部分；本地玩法由客户端权威，不要搬到后端。
- 共享规格放 `shared/`，配跨语言一致性测试，防止两端数值漂移。

## 常用命令

```bash
# 在 server/ 内
go build ./...
go test ./...
go vet ./...

# 本地服务
bash scripts/services.sh start
```

## 注意

实现前确认 `design.md` 与 `tasklist.md` 已覆盖该模块；未定稿不写代码。
