// Package httpx 提供 JSON 响应、稳定错误码与通用 HTTP 中间件。
package httpx

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"lifetextsandbox/server/internal/id"
)

// ErrorCode 是 common.schema.json 定义的稳定机器错误码。
type ErrorCode string

const (
	CodeValidationFailed    ErrorCode = "VALIDATION_FAILED"
	CodeUnauthenticated     ErrorCode = "UNAUTHENTICATED"
	CodeTokenExpired        ErrorCode = "TOKEN_EXPIRED"
	CodeForbidden           ErrorCode = "FORBIDDEN"
	CodeNotFound            ErrorCode = "NOT_FOUND"
	CodeConflict            ErrorCode = "CONFLICT"
	CodeSaveConflict        ErrorCode = "SAVE_CONFLICT"
	CodeSaveHashMismatch    ErrorCode = "SAVE_HASH_MISMATCH"
	CodeIdempotencyReplay   ErrorCode = "IDEMPOTENCY_REPLAY"
	CodeRateLimited         ErrorCode = "RATE_LIMITED"
	CodeInternal            ErrorCode = "INTERNAL"
	CodeUpstreamUnavailable ErrorCode = "UPSTREAM_UNAVAILABLE"
)

// APIError 是 common.schema.json 中 error 的映射。
type APIError struct {
	Code      ErrorCode      `json:"code"`
	Message   string         `json:"message"`
	Details   map[string]any `json:"details,omitempty"`
	RequestID string         `json:"request_id,omitempty"`
}

// StatusError 把 HTTP 状态码与 APIError 绑定，便于处理器返回。
type StatusError struct {
	Status int
	Err    APIError
}

func (e *StatusError) Error() string { return string(e.Err.Code) + ": " + e.Err.Message }

// NewError 构造带状态码的错误。
func NewError(status int, code ErrorCode, message string) *StatusError {
	return &StatusError{Status: status, Err: APIError{Code: code, Message: message}}
}

// WriteJSON 写出 JSON 响应。
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	_ = json.NewEncoder(w).Encode(v)
}

// WriteError 写出统一错误响应，并带上 request id。
func WriteError(w http.ResponseWriter, r *http.Request, status int, code ErrorCode, message string) {
	WriteJSON(w, status, APIError{
		Code:      code,
		Message:   message,
		RequestID: RequestIDFrom(r.Context()),
	})
}

// DecodeJSON 解析请求体并拒绝未知字段（对齐 additionalProperties:false）。
func DecodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

// MaxBody 限制请求体大小，超限时解码返回错误（R37.14 存档大小上限）。
func MaxBody(limit int64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if limit > 0 && r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, limit)
		}
		next.ServeHTTP(w, r)
	})
}

// ---- 中间件 ----

// RequestID 为每个请求分配 UUIDv7 并注入响应头与上下文。
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rid := r.Header.Get("X-Request-Id")
		if rid == "" || !id.IsValid(rid) {
			rid = id.NewUUIDv7()
		}
		w.Header().Set("X-Request-Id", rid)
		next.ServeHTTP(w, r.WithContext(withRequestID(r.Context(), rid)))
	})
}

// Recover 捕获 panic，返回 500 而非断开连接。
func Recover(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				logger.Error("panic recovered", "request_id", RequestIDFrom(r.Context()), "panic", rec)
				WriteError(w, r, http.StatusInternalServerError, CodeInternal, "服务器内部错误")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// AccessLog 记录结构化访问日志。
func AccessLog(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)
		logger.Info("http",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"request_id", RequestIDFrom(r.Context()),
		)
	})
}

// Limiter 抽象限流后端，便于在内存实现与 Redis 实现间切换。
type Limiter interface {
	Allow(ctx context.Context, key string) bool
}

// RateLimiter 是进程内固定窗口限流（单机单实例足够；多实例可换 Redis）。
type RateLimiter struct {
	mu       sync.Mutex
	limit    int
	window   time.Duration
	counters map[string]*counter
	now      func() time.Time
}

var _ Limiter = (*RateLimiter)(nil)

type counter struct {
	n     int
	start time.Time
}

// NewRateLimiter 创建每分钟 limit 次的限流器。
func NewRateLimiter(limitPerMinute int) *RateLimiter {
	return &RateLimiter{
		limit:    limitPerMinute,
		window:   time.Minute,
		counters: map[string]*counter{},
		now:      time.Now,
	}
}

// Allow 判断 key（通常为账号或客户端 IP）当前是否放行。
func (l *RateLimiter) Allow(_ context.Context, key string) bool {
	if l.limit <= 0 {
		return true
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	c, ok := l.counters[key]
	if !ok || now.Sub(c.start) >= l.window {
		l.counters[key] = &counter{n: 1, start: now}
		return true
	}
	if c.n >= l.limit {
		return false
	}
	c.n++
	return true
}

// Limit 返回限流中间件；超限返回 429 RATE_LIMITED。
func Limit(l Limiter, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if l != nil && !l.Allow(r.Context(), clientKey(r)) {
			WriteError(w, r, http.StatusTooManyRequests, CodeRateLimited, "请求过于频繁")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func clientKey(r *http.Request) string {
	if ip := r.Header.Get("X-Forwarded-For"); ip != "" {
		return ip
	}
	return r.RemoteAddr
}
