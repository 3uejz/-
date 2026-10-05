package telemetry

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"lifetextsandbox/server/internal/id"
)

func eventJSON(eventID, accountID, typ string, occurred time.Time) json.RawMessage {
	return json.RawMessage(fmt.Sprintf(
		`{"event_id":%q,"event_type":%q,"occurred_at":%q,"schema_version":1,"account_id":%q,"payload":{"v":1}}`,
		eventID, typ, occurred.UTC().Format(time.RFC3339), accountID))
}

func TestIngestDedupeAndValidate(t *testing.T) {
	store := NewMemoryStore()
	svc := NewService(store, 90)
	ctx := context.Background()
	acct := id.NewUUIDv7()
	now := time.Now()

	e1 := eventJSON(id.NewUUIDv7(), acct, "life.death", now)
	e2 := eventJSON(id.NewUUIDv7(), acct, "career.promotion", now)

	accepted, rejected := svc.Ingest(ctx, []json.RawMessage{e1, e2, e1, json.RawMessage(`{"event_id":"x"}`)})
	if len(accepted) != 2 {
		t.Fatalf("应接收 2 条，得到 %v", accepted)
	}
	if len(rejected) != 2 {
		t.Fatalf("应拒绝 2 条，得到 %+v", rejected)
	}
	if rejected[0].Code != "CONFLICT" {
		t.Errorf("重复事件应 CONFLICT，得到 %s", rejected[0].Code)
	}
	if rejected[1].Code != "VALIDATION_FAILED" {
		t.Errorf("非法事件应 VALIDATION_FAILED，得到 %s", rejected[1].Code)
	}
}

func TestExportAnonymizedAndDelete(t *testing.T) {
	store := NewMemoryStore()
	svc := NewService(store, 90)
	ctx := context.Background()
	acct := id.NewUUIDv7()
	ev := eventJSON(id.NewUUIDv7(), acct, "life.birth", time.Now())
	_, _ = svc.Ingest(ctx, []json.RawMessage{ev})

	exported := svc.Export(ctx, acct)
	if len(exported) != 1 {
		t.Fatalf("导出条数错误: %d", len(exported))
	}
	var m map[string]any
	if err := json.Unmarshal(exported[0], &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["account_id"]; ok {
		t.Errorf("导出应匿名化 account_id")
	}

	if n := svc.Delete(ctx, acct); n != 1 {
		t.Fatalf("删除条数错误: %d", n)
	}
	if len(svc.Export(ctx, acct)) != 0 {
		t.Errorf("删除后不应有事件")
	}
}

func TestRetentionPurge(t *testing.T) {
	store := NewMemoryStore()
	svc := NewService(store, 30)
	base := time.Now()
	svc.now = func() time.Time { return base }
	ctx := context.Background()

	old := eventJSON(id.NewUUIDv7(), "", "life.old", base.Add(-40*24*time.Hour))
	fresh := eventJSON(id.NewUUIDv7(), "", "life.fresh", base)
	_, _ = svc.Ingest(ctx, []json.RawMessage{old, fresh})

	if got := len(svc.AggregateByType(store.All())); got != 1 {
		t.Fatalf("保留期内应剩 1 类事件，得到 %d", got)
	}
}
