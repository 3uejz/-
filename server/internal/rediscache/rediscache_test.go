package rediscache

import (
	"context"
	"fmt"
	"testing"
	"time"

	"lifetextsandbox/server/internal/httpx"
)

var _ httpx.Limiter = (*RateLimiter)(nil)

func TestRedisRateLimiter(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	client, err := Open(ctx, "redis://127.0.0.1:6379/0")
	if err != nil {
		t.Skipf("本地 Redis 不可用，跳过: %v", err)
	}
	defer client.Close()

	// 仅允许 2 次/分钟；使用唯一 key 避免污染其他测试。
	limiter := NewRateLimiter(client, 2)
	key := "test:" + time.Now().Format("150405.000000000")
	defer client.Del(ctx, fmt.Sprintf("rl:%s:%d", key, time.Now().Unix()/60))

	if !limiter.Allow(ctx, key) {
		t.Fatal("第 1 次应放行")
	}
	if !limiter.Allow(ctx, key) {
		t.Fatal("第 2 次应放行")
	}
	if limiter.Allow(ctx, key) {
		t.Fatal("第 3 次应被限流")
	}
	if !limiter.Allow(ctx, key+":other") {
		t.Fatal("不同 key 应独立计数")
	}
}
