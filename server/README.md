# server/ — Go 模块化单体后端

提供账号、云存档、内容与远程配置、传承档案、埋点遥测、Admin 与 worldsim 世界模拟。

- Go 1.25.x（`/usr/local/go`）
- PostgreSQL + Redis：`bash scripts/services.sh start`
- 部署镜像与 compose 在 `deploy/`

## 骨架

```
cmd/server/          进程入口（当前仅 /api/v1/health）
internal/sim/        共享确定性模拟原语（SplitMix64、公历映射）
internal/auth/       账号与令牌
internal/saves/      云存档
internal/content/    内容清单与内容包
internal/config/     远程配置与公告
internal/legacy/     传承档案
internal/telemetry/  埋点遥测
internal/worldsim/   全球人口与宏观模拟
internal/admin/      管理后台接口
internal/testutil/   测试路径工具
```

## 测试

```bash
cd server
go build ./...
go vet ./...
go test ./...
```

跨语言一致性测试读取 `shared/consistency/vectors/`，与客户端 GDScript 实现逐位比对；统一入口 `bash scripts/test.sh`。
