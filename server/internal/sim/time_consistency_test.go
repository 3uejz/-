package sim_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"lifetextsandbox/server/internal/sim"
	"lifetextsandbox/server/internal/testutil"
)

type timeVectors struct {
	Cases []struct {
		AbsoluteMinutes int64 `json:"absolute_minutes"`
		Expected        struct {
			Date        string `json:"date"`
			Year        int    `json:"year"`
			Month       int    `json:"month"`
			Day         int    `json:"day"`
			Hour        int    `json:"hour"`
			Minute      int    `json:"minute"`
			WeekdayISO  int    `json:"weekday_iso"`
			SeasonNorth string `json:"season_north"`
		} `json:"expected"`
	} `json:"cases"`
}

func TestTimeConsistency(t *testing.T) {
	dir := testutil.VectorsDir()
	if dir == "" {
		t.Fatal("未找到 shared/consistency/vectors 目录")
	}
	raw, err := os.ReadFile(filepath.Join(dir, "time.json"))
	if err != nil {
		t.Fatalf("读取 time.json 失败: %v", err)
	}
	var v timeVectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("解析 time.json 失败: %v", err)
	}
	for _, c := range v.Cases {
		got := sim.FromAbsoluteMinutes(c.AbsoluteMinutes)
		want := c.Expected
		if got.Date != want.Date || got.Year != want.Year || got.Month != want.Month ||
			got.Day != want.Day || got.Hour != want.Hour || got.Minute != want.Minute ||
			got.WeekdayISO != want.WeekdayISO || got.SeasonNorth != want.SeasonNorth {
			t.Errorf("minutes=%d: got=%+v want=%+v", c.AbsoluteMinutes, got, want)
		}
	}
}
