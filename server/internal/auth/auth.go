// Package auth 负责账号注册、登录、令牌签发与设备绑定。
//
// 权威边界：账号与令牌由后端权威。接口见 shared/openapi/openapi.yaml。
package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"lifetextsandbox/server/internal/id"
)

var (
	ErrUsernameTaken     = errors.New("username taken")
	ErrInvalidCredential = errors.New("invalid credentials")
	ErrRefreshInvalid    = errors.New("refresh token invalid")
	ErrValidation        = errors.New("validation failed")
)

// Account 对应 openapi 的 Account。
type Account struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"`
	Disabled     bool      `json:"disabled"`
	CreatedAt    time.Time `json:"created_at"`
}

// RefreshRecord 是存储中的 refresh 令牌（仅存摘要）。
type RefreshRecord struct {
	Hash      string
	AccountID string
	DeviceID  string
	ExpiresAt time.Time
	CreatedAt time.Time
}

// Tokens 对应 openapi 的 AuthTokens。
type Tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	AccountID    string `json:"account_id"`
}

// Store 抽象账号与 refresh 的持久化，内存实现用于测试，PG 实现后续接入。
type Store interface {
	CreateAccount(ctx context.Context, a Account) error
	AccountByUsername(ctx context.Context, username string) (Account, bool)
	AccountByID(ctx context.Context, id string) (Account, bool)
	SetDisabled(ctx context.Context, accountID string, disabled bool) error
	SaveRefresh(ctx context.Context, r RefreshRecord) error
	RefreshByHash(ctx context.Context, hash string) (RefreshRecord, bool)
	DeleteRefresh(ctx context.Context, hash string) error
	Devices(ctx context.Context, accountID string) []RefreshRecord
	RevokeDevice(ctx context.Context, accountID, deviceID string) error
	RevokeAllDevices(ctx context.Context, accountID string) error
	ListAccounts(ctx context.Context, limit int, afterID string) ([]Account, string)
	Count(ctx context.Context) (total int, disabled int)
}

// Service 编排账号与令牌逻辑。
type Service struct {
	store      Store
	secret     string
	accessTTL  time.Duration
	refreshTTL time.Duration
	now        func() time.Time
}

// NewService 构造 auth 服务。
func NewService(store Store, secret string, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{
		store:      store,
		secret:     secret,
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		now:        time.Now,
	}
}

// Register 注册新账号并返回令牌对。
func (s *Service) Register(ctx context.Context, username, password, deviceID string) (Tokens, error) {
	username = strings.TrimSpace(username)
	if err := validateCredentials(username, password); err != nil {
		return Tokens{}, err
	}
	if _, ok := s.store.AccountByUsername(ctx, username); ok {
		return Tokens{}, ErrUsernameTaken
	}
	hash, err := HashPassword(password)
	if err != nil {
		return Tokens{}, err
	}
	account := Account{
		ID:           id.NewUUIDv7(),
		Username:     username,
		PasswordHash: hash,
		Role:         "player",
		CreatedAt:    s.now().UTC(),
	}
	if err := s.store.CreateAccount(ctx, account); err != nil {
		return Tokens{}, err
	}
	return s.issue(ctx, account, deviceID)
}

// Login 校验口令并签发令牌对。
func (s *Service) Login(ctx context.Context, username, password, deviceID string) (Tokens, error) {
	account, ok := s.store.AccountByUsername(ctx, strings.TrimSpace(username))
	if !ok || account.Disabled || !VerifyPassword(password, account.PasswordHash) {
		return Tokens{}, ErrInvalidCredential
	}
	return s.issue(ctx, account, deviceID)
}

// Refresh 轮换 refresh：旧令牌作废，签发新的令牌对。
func (s *Service) Refresh(ctx context.Context, refreshToken, deviceID string) (Tokens, error) {
	rec, ok := s.store.RefreshByHash(ctx, hashToken(refreshToken))
	if !ok {
		return Tokens{}, ErrRefreshInvalid
	}
	if s.now().After(rec.ExpiresAt) {
		_ = s.store.DeleteRefresh(ctx, rec.Hash)
		return Tokens{}, ErrRefreshInvalid
	}
	account, ok := s.store.AccountByID(ctx, rec.AccountID)
	if !ok {
		return Tokens{}, ErrRefreshInvalid
	}
	_ = s.store.DeleteRefresh(ctx, rec.Hash)
	if deviceID == "" {
		deviceID = rec.DeviceID
	}
	return s.issue(ctx, account, deviceID)
}

// Logout 撤销指定 refresh 令牌。
func (s *Service) Logout(ctx context.Context, refreshToken string) error {
	return s.store.DeleteRefresh(ctx, hashToken(refreshToken))
}

// Authenticate 校验访问令牌并返回账号。
func (s *Service) Authenticate(ctx context.Context, accessToken string) (Account, error) {
	claims, err := ParseAccess(s.secret, accessToken, s.now())
	if err != nil {
		return Account{}, err
	}
	account, ok := s.store.AccountByID(ctx, claims.Sub)
	if !ok || account.Disabled {
		return Account{}, ErrInvalidToken
	}
	return account, nil
}

// ListAccounts 返回账号分页（admin）。
func (s *Service) ListAccounts(ctx context.Context, limit int, afterID string) ([]Account, string) {
	return s.store.ListAccounts(ctx, limit, afterID)
}

// Count 返回账号总数与封禁数（admin 仪表盘）。
func (s *Service) Count(ctx context.Context) (total int, disabled int) {
	return s.store.Count(ctx)
}

// Account 返回单个账号（admin）。
func (s *Service) Account(ctx context.Context, accountID string) (Account, bool) {
	return s.store.AccountByID(ctx, accountID)
}

// SetDisabled 封禁/解封账号（admin）。封禁后吊销其全部 refresh。
func (s *Service) SetDisabled(ctx context.Context, accountID string, disabled bool) (Account, error) {
	account, ok := s.store.AccountByID(ctx, accountID)
	if !ok {
		return Account{}, ErrInvalidToken
	}
	if err := s.store.SetDisabled(ctx, accountID, disabled); err != nil {
		return Account{}, err
	}
	if disabled {
		_ = s.store.RevokeAllDevices(ctx, accountID)
	}
	account.Disabled = disabled
	return account, nil
}

// Devices 返回账号的在线设备（refresh 记录）。
func (s *Service) Devices(ctx context.Context, accountID string) []RefreshRecord {
	return s.store.Devices(ctx, accountID)
}

// RevokeDevice 吊销指定设备的 refresh。
func (s *Service) RevokeDevice(ctx context.Context, accountID, deviceID string) error {
	return s.store.RevokeDevice(ctx, accountID, deviceID)
}

// RevokeAllDevices 吊销账号全部 refresh。
func (s *Service) RevokeAllDevices(ctx context.Context, accountID string) error {
	return s.store.RevokeAllDevices(ctx, accountID)
}

// EnsureAdmin 幂等创建管理员账号（首次启动时用密钥初始化）。
func (s *Service) EnsureAdmin(ctx context.Context, username, password string) error {
	if username == "" || password == "" {
		return nil
	}
	if _, ok := s.store.AccountByUsername(ctx, username); ok {
		return nil
	}
	hash, err := HashPassword(password)
	if err != nil {
		return err
	}
	return s.store.CreateAccount(ctx, Account{
		ID:           id.NewUUIDv7(),
		Username:     username,
		PasswordHash: hash,
		Role:         "admin",
		CreatedAt:    s.now().UTC(),
	})
}

func (s *Service) issue(ctx context.Context, account Account, deviceID string) (Tokens, error) {
	access, err := SignAccess(s.secret, account.ID, account.Role, s.now(), s.accessTTL)
	if err != nil {
		return Tokens{}, err
	}
	refresh, err := newOpaqueToken()
	if err != nil {
		return Tokens{}, err
	}
	rec := RefreshRecord{
		Hash:      hashToken(refresh),
		AccountID: account.ID,
		DeviceID:  deviceID,
		ExpiresAt: s.now().Add(s.refreshTTL).UTC(),
		CreatedAt: s.now().UTC(),
	}
	if err := s.store.SaveRefresh(ctx, rec); err != nil {
		return Tokens{}, err
	}
	return Tokens{
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresIn:    int(s.accessTTL.Seconds()),
		AccountID:    account.ID,
	}, nil
}

func validateCredentials(username, password string) error {
	if len(username) < 3 || len(username) > 32 {
		return ErrValidation
	}
	if len(password) < 8 || len(password) > 128 {
		return ErrValidation
	}
	return nil
}
