package blob

import (
	"bytes"
	"context"
	"io"
	"strings"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// MinIOOptions 描述 S3 兼容对象存储的连接参数。
// MinIO、Cloudflare R2、阿里云 OSS 与腾讯云 COS 均使用同一套 S3 API。
type MinIOOptions struct {
	Endpoint     string
	AccessKey    string
	SecretKey    string
	Bucket       string
	Region       string
	UseSSL       bool
	CreateBucket bool
}

// MinIOStore 使用 S3 兼容对象存储（R37.8）。
type MinIOStore struct {
	client *minio.Client
	bucket string
}

// NewMinIOStore 连接 S3 兼容存储；CreateBucket 为 true 时自动建桶。
// Endpoint 可带 http:// 或 https:// 前缀，前缀会覆盖 UseSSL。
func NewMinIOStore(ctx context.Context, opts MinIOOptions) (*MinIOStore, error) {
	endpoint, secure := normalizeEndpoint(opts.Endpoint, opts.UseSSL)
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(opts.AccessKey, opts.SecretKey, ""),
		Secure: secure,
		Region: strings.TrimSpace(opts.Region),
	})
	if err != nil {
		return nil, err
	}
	if opts.CreateBucket {
		exists, err := client.BucketExists(ctx, opts.Bucket)
		if err != nil {
			return nil, err
		}
		if !exists {
			if err := client.MakeBucket(ctx, opts.Bucket, minio.MakeBucketOptions{Region: strings.TrimSpace(opts.Region)}); err != nil {
				return nil, err
			}
		}
	}
	return &MinIOStore{client: client, bucket: opts.Bucket}, nil
}

// Put 上传对象。
func (s *MinIOStore) Put(ctx context.Context, key string, data []byte) error {
	_, err := s.client.PutObject(ctx, s.bucket, key, bytes.NewReader(data), int64(len(data)),
		minio.PutObjectOptions{ContentType: "application/octet-stream"})
	return err
}

// Get 下载对象，不存在时返回 ErrNotFound。
func (s *MinIOStore) Get(ctx context.Context, key string) ([]byte, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, mapMinIOError(err)
	}
	defer obj.Close()
	data, err := io.ReadAll(obj)
	if err != nil {
		return nil, mapMinIOError(err)
	}
	return data, nil
}

// Open 以可随机读取的流打开对象，供 HTTP Range 下载使用。
func (s *MinIOStore) Open(ctx context.Context, key string) (io.ReadSeekCloser, int64, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, 0, mapMinIOError(err)
	}
	info, err := obj.Stat()
	if err != nil {
		_ = obj.Close()
		return nil, 0, mapMinIOError(err)
	}
	return obj, info.Size, nil
}

// Delete 删除对象。
func (s *MinIOStore) Delete(ctx context.Context, key string) error {
	return s.client.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{})
}

func normalizeEndpoint(endpoint string, useSSL bool) (string, bool) {
	e := strings.TrimSpace(endpoint)
	e = strings.TrimSuffix(e, "/")
	switch {
	case strings.HasPrefix(e, "https://"):
		return strings.TrimPrefix(e, "https://"), true
	case strings.HasPrefix(e, "http://"):
		return strings.TrimPrefix(e, "http://"), false
	default:
		return e, useSSL
	}
}

func mapMinIOError(err error) error {
	resp := minio.ToErrorResponse(err)
	if resp.Code == "NoSuchKey" || resp.StatusCode == 404 {
		return ErrNotFound
	}
	return err
}
