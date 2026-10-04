# scripts

开发脚本。均以 `bash scripts/<name>.sh` 运行。

- `doctor.sh`：工具链自检，打印主要组件版本与路径。
- `services.sh start|stop|status`：启停本地 PostgreSQL 与 Redis。
- `test.sh`：运行客户端 headless 测试与后端 Go 测试（含跨语言一致性）；先执行一次 Godot 导入。
