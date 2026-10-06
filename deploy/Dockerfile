# 浮生录后端 + 管理后台镜像（单机单实例，R37）。
# 多阶段：Node 构建 admin，Go 构建 server，最终运行镜像以 postgres:16-alpine 为基础
# （自带 pg_dump/pg_restore，供每日备份与恢复演练使用）。

FROM node:22-alpine AS admin-build
WORKDIR /src/admin
COPY admin/package.json admin/package-lock.json ./
RUN npm ci
COPY admin/ ./
RUN npm run build

FROM golang:1.26 AS server-build
WORKDIR /src/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -trimpath -o /out/server ./cmd/server

FROM postgres:16-alpine
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=server-build /out/server /usr/local/bin/server
COPY --from=admin-build /src/admin/dist /app/admin/dist
ENV ADMIN_DIR=/app/admin/dist \
    DATA_DIR=/app/data \
    BACKUP_DIR=/app/backups \
    SERVER_ADDR=:8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/server"]
