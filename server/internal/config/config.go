// Package config 负责从环境变量/密钥文件加载后端配置。
//
// 权威边界：账号与令牌由后端权威。关键密钥缺失时拒绝启动（R37.12）。
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// ErrMissingSecret 在关键密钥缺失时返回，调用方应拒绝启动。
var ErrMissingSecret = errors.New("缺少关键密钥")

// Config 是后端运行时配置。所有字段均有安全默认值，密钥类字段必填。
type Config struct {
	Addr           string
	AccessTTL      time.Duration
	RefreshTTL     time.Duration
	JWTSecret      string
	RateLimitRPS   int
	SaveMaxBytes   int64
	AdminUsername  string
	AdminPassword  string
	DatabaseURL    string
	RedisURL       string
	ObjectEndpoint string
	ObjectKey      string
	ObjectSecret   string
	ObjectBucket   string
	DataDir        string
	BackupDir      string
	AdminDir       string
	TelemetryDays  int
}

// Load 读取配置。getenv 为 nil 时使用 os.Getenv，便于测试注入。
func Load(getenv func(string) string) (Config, error) {
	if getenv == nil {
		getenv = os.Getenv
	}
	cfg := Config{
		Addr:           getOr(getenv, "SERVER_ADDR", ":8080"),
		AccessTTL:      dur(getenv, "ACCESS_TTL", 15*time.Minute),
		RefreshTTL:     dur(getenv, "REFRESH_TTL", 30*24*time.Hour),
		JWTSecret:      strings.TrimSpace(getenv("JWT_SECRET")),
		RateLimitRPS:   intval(getenv, "RATE_LIMIT_RPS", 30),
		SaveMaxBytes:   int64val(getenv, "SAVE_MAX_BYTES", 100*1024*1024),
		AdminUsername:  getOr(getenv, "ADMIN_USERNAME", "admin"),
		AdminPassword:  getenv("ADMIN_PASSWORD"),
		DatabaseURL:    getenv("DATABASE_URL"),
		RedisURL:       getenv("REDIS_URL"),
		ObjectEndpoint: getenv("OBJECT_ENDPOINT"),
		ObjectKey:      getenv("OBJECT_ACCESS_KEY"),
		ObjectSecret:   getenv("OBJECT_SECRET_KEY"),
		ObjectBucket:   getOr(getenv, "OBJECT_BUCKET", "lifetext"),
		DataDir:        getOr(getenv, "DATA_DIR", "data"),
		BackupDir:      getOr(getenv, "BACKUP_DIR", "backups"),
		AdminDir:       getOr(getenv, "ADMIN_DIR", "admin/dist"),
		TelemetryDays:  intval(getenv, "TELEMETRY_RETENTION_DAYS", 90),
	}
	if cfg.JWTSecret == "" {
		return Config{}, fmt.Errorf("%w: JWT_SECRET", ErrMissingSecret)
	}
	if len(cfg.JWTSecret) < 32 {
		return Config{}, fmt.Errorf("%w: JWT_SECRET 至少 32 字节", ErrMissingSecret)
	}
	return cfg, nil
}

// HasObjectStore 返回是否配置了对象存储；未配置时使用本地目录兜底。
func (c Config) HasObjectStore() bool {
	return c.ObjectEndpoint != "" && c.ObjectKey != "" && c.ObjectSecret != ""
}

func getOr(getenv func(string) string, key, def string) string {
	if v := strings.TrimSpace(getenv(key)); v != "" {
		return v
	}
	return def
}

func intval(getenv func(string) string, key string, def int) int {
	v := strings.TrimSpace(getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return def
	}
	return n
}

func int64val(getenv func(string) string, key string, def int64) int64 {
	v := strings.TrimSpace(getenv(key))
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil || n <= 0 {
		return def
	}
	return n
}

func dur(getenv func(string) string, key string, def time.Duration) time.Duration {
	v := strings.TrimSpace(getenv(key))
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil || d <= 0 {
		return def
	}
	return d
}
