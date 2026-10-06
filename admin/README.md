# admin/ — React + Ant Design 管理后台

浮生录管理后台：账号与设备、存档运维、内容管理、远程配置、公告、遥测统计、审计日志、运营助手与系统运维。构建产物由 Go 服务同源托管于 `/admin`。

## 技术栈

- 构建：Vite 5
- 框架：React 18 + TypeScript
- UI：Ant Design 5 + @ant-design/icons
- 路由：React Router v6
- 数据请求：TanStack Query v5
- 轻量状态：Zustand（会话持久化到 localStorage、主题亮/暗跟随系统）
- HTTP：原生 fetch 统一封装（`src/api/client.ts`）

## 命令

```bash
# 安装依赖
npm install

# 本地开发（/api 反向代理到 http://localhost:8080）
npm run dev

# 类型检查 + 生产构建，产物输出到 dist/
npm run build

# 预览构建产物
npm run preview
```

## 目录

```
src/
├── api/         请求封装与各域 API 客户端
├── components/  通用组件（布局、表格、危险确认、JSON 展示等）
├── features/    按业务域聚合的 TanStack Query 逻辑
├── pages/       路由页面，按 11 模块分目录
├── router/      路由表与守卫
├── store/       Zustand：会话、主题
├── theme/       AntD 主题 token
└── utils/       格式化、错误处理、下载、系统外观
```

## 约定

- 登录复用 `POST /api/v1/auth/login`，随后经 `GET /api/v1/admin/me` 校验管理员身份。
- `apiFetch` 自动注入 Bearer；401 用 refresh 轮换后重试一次，失败跳登录；403 提示无后台权限并登出。
- 危险操作（封禁、回滚存档/发布/配置、清理对象、合规删除）需二次确认，并要求输入目标名称或 ID。
- 接口以 `shared/openapi/openapi.yaml` 与 `.monkeycode/specs/life-text-sandbox/admin.md` 为准。
