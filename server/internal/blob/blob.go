// Package blob 提供对象存储抽象：本地文件系统实现与自建 MinIO 实现。
package blob

import (
	"context"
	"errors"
)

// ErrNotFound 表示对象不存在。
var ErrNotFound = errors.New("blob not found")

// Store 是对象存储接口。key 为斜杠分隔的逻辑路径，如 saves/<account>/<slot>/<version>。
type Store interface {
	Put(ctx context.Context, key string, data []byte) error
	Get(ctx context.Context, key string) ([]byte, error)
	Delete(ctx context.Context, key string) error
}
