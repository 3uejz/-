package auth

import (
	"context"
	"errors"
	"testing"
	"time"
)

func newTestService() *Service {
	return NewService(NewMemoryStore(), "test-secret-at-least-32-bytes-long!!", 15*time.Minute, 24*time.Hour)
}

func TestRegisterLoginAuthenticate(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()

	tokens, err := svc.Register(ctx, "alice", "password123", "device-1")
	if err != nil {
		t.Fatalf("注册失败: %v", err)
	}
	if tokens.AccessToken == "" || tokens.RefreshToken == "" || tokens.AccountID == "" {
		t.Fatalf("令牌字段不完整: %+v", tokens)
	}
	account, err := svc.Authenticate(ctx, tokens.AccessToken)
	if err != nil {
		t.Fatalf("鉴权失败: %v", err)
	}
	if account.Username != "alice" || account.Role != "player" {
		t.Fatalf("账号不符: %+v", account)
	}

	if _, err := svc.Login(ctx, "alice", "wrong-password", ""); !errors.Is(err, ErrInvalidCredential) {
		t.Fatalf("错误口令应拒绝，得到 %v", err)
	}
	if _, err := svc.Login(ctx, "alice", "password123", "device-2"); err != nil {
		t.Fatalf("正确口令应登录: %v", err)
	}
}

func TestRegisterValidationAndDuplicate(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()
	if _, err := svc.Register(ctx, "ab", "password123", ""); !errors.Is(err, ErrValidation) {
		t.Fatalf("短用户名应校验失败: %v", err)
	}
	if _, err := svc.Register(ctx, "alice", "short", ""); !errors.Is(err, ErrValidation) {
		t.Fatalf("短口令应校验失败: %v", err)
	}
	if _, err := svc.Register(ctx, "alice", "password123", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Register(ctx, "alice", "password456", ""); !errors.Is(err, ErrUsernameTaken) {
		t.Fatalf("重复用户名应冲突: %v", err)
	}
}

func TestRefreshRotationAndLogout(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()
	tokens, _ := svc.Register(ctx, "alice", "password123", "d1")

	rotated, err := svc.Refresh(ctx, tokens.RefreshToken, "")
	if err != nil {
		t.Fatalf("刷新失败: %v", err)
	}
	if rotated.RefreshToken == tokens.RefreshToken {
		t.Fatalf("refresh 应轮换")
	}
	if _, err := svc.Refresh(ctx, tokens.RefreshToken, ""); !errors.Is(err, ErrRefreshInvalid) {
		t.Fatalf("旧 refresh 应失效，得到 %v", err)
	}

	if err := svc.Logout(ctx, rotated.RefreshToken); err != nil {
		t.Fatalf("登出失败: %v", err)
	}
	if _, err := svc.Refresh(ctx, rotated.RefreshToken, ""); !errors.Is(err, ErrRefreshInvalid) {
		t.Fatalf("登出后 refresh 应失效: %v", err)
	}
}

func TestAccessTokenExpiry(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()
	base := time.Now()
	svc.now = func() time.Time { return base }
	tokens, _ := svc.Register(ctx, "alice", "password123", "")

	svc.now = func() time.Time { return base.Add(16 * time.Minute) }
	if _, err := svc.Authenticate(ctx, tokens.AccessToken); !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("过期令牌应报 ErrTokenExpired，得到 %v", err)
	}

	tampered := tokens.AccessToken[:len(tokens.AccessToken)-2] + "xx"
	if _, err := svc.Authenticate(ctx, tampered); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("篡改令牌应报 ErrInvalidToken，得到 %v", err)
	}
}

func TestEnsureAdmin(t *testing.T) {
	svc := newTestService()
	ctx := context.Background()
	if err := svc.EnsureAdmin(ctx, "root", "admin-password"); err != nil {
		t.Fatal(err)
	}
	if err := svc.EnsureAdmin(ctx, "root", "admin-password"); err != nil {
		t.Fatalf("幂等创建失败: %v", err)
	}
	account, ok := svc.store.AccountByUsername(ctx, "root")
	if !ok || account.Role != "admin" {
		t.Fatalf("管理员角色错误: %+v", account)
	}
}

func TestPasswordHashRoundTrip(t *testing.T) {
	h, err := HashPassword("s3cret-password")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword("s3cret-password", h) {
		t.Fatal("正确口令校验失败")
	}
	if VerifyPassword("wrong", h) {
		t.Fatal("错误口令不应通过")
	}
	if VerifyPassword("s3cret-password", "garbage") {
		t.Fatal("非法哈希不应通过")
	}
}
