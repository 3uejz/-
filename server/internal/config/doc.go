// Package config 负责后端运行时配置：从环境变量/密钥文件加载，
// 关键密钥（如 JWT_SECRET）缺失时拒绝启动（R37.12）。
//
// 远程配置（下发给客户端的 /config）由 content 包负责。
package config
