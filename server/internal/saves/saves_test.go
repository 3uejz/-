package saves

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"lifetextsandbox/server/internal/id"
)

func makeDoc(playthrough string, marker int) []byte {
	return []byte(fmt.Sprintf(`{"meta":{"schema_version":1,"game_version":"0.1.0","playthrough_id":%q,"seed":42},"marker":%d}`,
		playthrough, marker))
}

func TestPutOptimisticLockAndIdempotency(t *testing.T) {
	svc := NewService(NewMemoryStore())
	ctx := context.Background()
	acct := id.NewUUIDv7()
	pt := id.NewUUIDv7()

	rec, created, err := svc.Put(ctx, acct, 1, makeDoc(pt, 1), "idem-1", "")
	if err != nil || !created || rec.Version != 1 {
		t.Fatalf("首次写入: rec=%+v created=%v err=%v", rec, created, err)
	}
	etag := ETag(rec)

	// 幂等重放：相同 Idempotency-Key 返回原版本、不再新建。
	replay, created2, err := svc.Put(ctx, acct, 1, makeDoc(pt, 1), "idem-1", "")
	if err != nil || created2 || replay.Version != 1 {
		t.Fatalf("幂等重放异常: %+v created=%v err=%v", replay, created2, err)
	}

	// ETag 匹配则覆盖，版本递增。
	rec2, _, err := svc.Put(ctx, acct, 1, makeDoc(pt, 2), "idem-2", etag)
	if err != nil || rec2.Version != 2 {
		t.Fatalf("覆盖失败: %+v err=%v", rec2, err)
	}

	// 过期 ETag 冲突。
	if _, _, err := svc.Put(ctx, acct, 1, makeDoc(pt, 3), "idem-3", etag); !errors.Is(err, ErrConflict) {
		t.Fatalf("陈旧 ETag 应冲突，得到 %v", err)
	}
}

func TestRollbackAndVersions(t *testing.T) {
	svc := NewService(NewMemoryStore())
	ctx := context.Background()
	acct := id.NewUUIDv7()
	pt := id.NewUUIDv7()

	v1, _, _ := svc.Put(ctx, acct, 1, makeDoc(pt, 1), "", "")
	_, _, _ = svc.Put(ctx, acct, 1, makeDoc(pt, 2), "", "")

	versions, err := svc.Versions(ctx, acct, 1)
	if err != nil || len(versions) != 2 || versions[0].Version != 2 {
		t.Fatalf("版本列表异常: %+v err=%v", versions, err)
	}

	rolled, err := svc.Rollback(ctx, acct, 1, 1)
	if err != nil {
		t.Fatalf("回滚失败: %v", err)
	}
	if rolled.Version != 3 || rolled.Hash != v1.Hash {
		t.Fatalf("回滚结果不正确: %+v 期望 hash=%s", rolled, v1.Hash)
	}
}

func TestValidationAndNotFound(t *testing.T) {
	svc := NewService(NewMemoryStore())
	ctx := context.Background()
	acct := id.NewUUIDv7()

	if _, _, err := svc.Put(ctx, acct, 1, []byte(`{}`), "", ""); !errors.Is(err, ErrValidation) {
		t.Fatalf("缺少 meta 应校验失败: %v", err)
	}
	if _, _, err := svc.Put(ctx, acct, 1, []byte(`not json`), "", ""); !errors.Is(err, ErrValidation) {
		t.Fatalf("非 JSON 应校验失败: %v", err)
	}
	if _, _, err := svc.Put(ctx, acct, 200, makeDoc(id.NewUUIDv7(), 1), "", ""); !errors.Is(err, ErrValidation) {
		t.Fatalf("越界 slot 应校验失败: %v", err)
	}
	if _, err := svc.Get(ctx, acct, 5); !errors.Is(err, ErrNotFound) {
		t.Fatalf("不存在的槽应 NotFound: %v", err)
	}
	if _, err := svc.Rollback(ctx, acct, 1, 9); !errors.Is(err, ErrNotFound) {
		t.Fatalf("回滚不存在版本应 NotFound: %v", err)
	}
}

func TestListAndResolve(t *testing.T) {
	svc := NewService(NewMemoryStore())
	ctx := context.Background()
	acct := id.NewUUIDv7()
	pt := id.NewUUIDv7()
	_, _, _ = svc.Put(ctx, acct, 1, makeDoc(pt, 1), "", "")
	_, _, _ = svc.Put(ctx, acct, 2, makeDoc(pt, 2), "", "")

	items, _ := svc.List(ctx, acct, 50, 0)
	if len(items) != 2 || items[0].Slot != 1 || items[1].Slot != 2 {
		t.Fatalf("列表异常: %+v", items)
	}

	resolved, err := svc.Resolve(ctx, acct, 1, "keep_local", 1, makeDoc(pt, 99))
	if err != nil || resolved.Version != 2 {
		t.Fatalf("keep_local 解决失败: %+v err=%v", resolved, err)
	}
	cloud, err := svc.Resolve(ctx, acct, 1, "keep_cloud", 1, nil)
	if err != nil || cloud.Version != 2 {
		t.Fatalf("keep_cloud 应返回云端现状: %+v err=%v", cloud, err)
	}
}
