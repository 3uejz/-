package config

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadRejectsMissingSecret(t *testing.T) {
	_, err := Load(env(map[string]string{}))
	if !errors.Is(err, ErrMissingSecret) {
		t.Fatalf("缺少 JWT_SECRET 应报错，得到 %v", err)
	}
}

func TestLoadRejectsShortSecret(t *testing.T) {
	_, err := Load(env(map[string]string{"JWT_SECRET": "too-short"}))
	if !errors.Is(err, ErrMissingSecret) {
		t.Fatalf("短密钥应报错，得到 %v", err)
	}
}

func TestLoadDefaultsAndOverrides(t *testing.T) {
	secret := strings.Repeat("a", 40)
	cfg, err := Load(env(map[string]string{
		"JWT_SECRET":  secret,
		"ACCESS_TTL":  "5m",
		"SERVER_ADDR": ":9090",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Addr != ":9090" {
		t.Errorf("Addr=%q", cfg.Addr)
	}
	if cfg.AccessTTL != 5*time.Minute {
		t.Errorf("AccessTTL=%v", cfg.AccessTTL)
	}
	if cfg.RefreshTTL != 30*24*time.Hour {
		t.Errorf("RefreshTTL 默认值错误: %v", cfg.RefreshTTL)
	}
	if cfg.HasObjectStore() {
		t.Errorf("未配置对象存储时 HasObjectStore 应为 false")
	}
}
