# scripts

开发脚本。均以 `bash scripts/<name>.sh` 运行。

- `doctor.sh`：工具链自检，打印主要组件版本与路径。
- `dev-setup.sh`：本地开发一键准备（生成 `.env`、启动依赖、拉取 Go/Node 依赖）。
- `dev-deps.sh start|stop|status|logs`：管理 PostgreSQL / Redis / MinIO 容器。
- `dev-server.sh`：本地启动 Go 后端。
- `dev-web.sh`：本地启动 React 管理端。
- `dev-client.sh`：用 Godot 编辑器打开客户端。
- `services.sh start|stop|status`：启停宿主机 PostgreSQL 与 Redis（无 Docker 时使用）。
- `test.sh`：运行客户端 headless 测试与后端 Go 测试（含跨语言一致性）；先执行一次 Godot 导入。
- `setup-engine.sh` / `build-engine.sh`：拉取并构建自定义 Godot 引擎。
- `setup-blender.sh` / `blender.sh`：Blender 工具链。
