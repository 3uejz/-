package httpx

import "context"

type ctxKey int

const requestIDKey ctxKey = 0

func withRequestID(ctx context.Context, rid string) context.Context {
	return context.WithValue(ctx, requestIDKey, rid)
}

// RequestIDFrom 从上下文取出请求 ID（不存在时返回空串）。
func RequestIDFrom(ctx context.Context) string {
	if v, ok := ctx.Value(requestIDKey).(string); ok {
		return v
	}
	return ""
}
