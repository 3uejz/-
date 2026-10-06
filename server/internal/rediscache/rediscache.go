// Package rediscache 提供 Redis 客户端与基于 Redis 的共享限流，
// 用于单机多进程/多实例场景下统一限流与缓存（R37）。
package rediscache

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Client 包装 go-redis 客户端。
type Client struct {
	*redis.Client
}

// Open 连接 Redis 并做一次 Ping（带超时）。
func Open(ctx context.Context, url string) (*Client, error) {
	opt, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("解析 REDIS_URL: %w", err)
	}
	c := redis.NewClient(opt)
	pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := c.Ping(pingCtx).Err(); err != nil {
		_ = c.Close()
		return nil, err
	}
	return &Client{Client: c}, nil
}

// RateLimiter 是基于 Redis INCR 的固定窗口限流，实现 httpx.Limiter。
type RateLimiter struct {
	client *redis.Client
	limit  int
	window time.Duration
}

// NewRateLimiter 创建每分钟 limit 次的限流器。
func NewRateLimiter(c *Client, limitPerMinute int) *RateLimiter {
	return &RateLimiter{client: c.Client, limit: limitPerMinute, window: time.Minute}
}

// Allow 判断 key 当前是否放行；Redis 故障时降级放行，避免限流组件拖垮服务。
func (l *RateLimiter) Allow(ctx context.Context, key string) bool {
	if l.limit <= 0 {
		return true
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	bucket := time.Now().Unix() / int64(l.window.Seconds())
	k := fmt.Sprintf("rl:%s:%d", key, bucket)
	n, err := l.client.Incr(ctx, k).Result()
	if err != nil {
		return true
	}
	if n == 1 {
		_ = l.client.Expire(ctx, k, l.window).Err()
	}
	return n <= int64(l.limit)
}
