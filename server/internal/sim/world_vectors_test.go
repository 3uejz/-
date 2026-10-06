package sim_test

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"

	"lifetextsandbox/server/internal/sim"
	"lifetextsandbox/server/internal/testutil"
)

type populationVectors struct {
	Cases []struct {
		Population    float64 `json:"population"`
		BirthRate     float64 `json:"birth_rate"`
		DeathRate     float64 `json:"death_rate"`
		MigrationRate float64 `json:"migration_rate"`
		Minutes       float64 `json:"minutes"`
		ExpectedNext  float64 `json:"expected_next"`
	} `json:"cases"`
}

type economyVectors struct {
	Cases []struct {
		S            float64 `json:"S"`
		Mu           float64 `json:"mu"`
		Sigma        float64 `json:"sigma"`
		Dt           float64 `json:"dt"`
		Z            float64 `json:"Z"`
		ExpectedNext float64 `json:"expected_next"`
	} `json:"cases"`
}

func readVectorFile(t *testing.T, name string, out any) {
	t.Helper()
	dir := testutil.VectorsDir()
	if dir == "" {
		t.Fatal("未找到 shared/consistency/vectors 目录")
	}
	raw, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatalf("读取 %s 失败: %v", name, err)
	}
	if err := json.Unmarshal(raw, out); err != nil {
		t.Fatalf("解析 %s 失败: %v", name, err)
	}
}

func TestPopulationVectorConsistency(t *testing.T) {
	var v populationVectors
	readVectorFile(t, "population.json", &v)
	if len(v.Cases) == 0 {
		t.Fatal("population.json 无用例")
	}
	const tolerance = 0.001
	for i, c := range v.Cases {
		got := sim.PopulationCohortNext(c.Population, c.BirthRate, c.DeathRate, c.MigrationRate, c.Minutes)
		if math.Abs(got-c.ExpectedNext) > tolerance {
			t.Errorf("case %d: got=%.6f want=%.6f", i, got, c.ExpectedNext)
		}
	}
}

func TestEconomyVectorConsistency(t *testing.T) {
	var v economyVectors
	readVectorFile(t, "economy.json", &v)
	if len(v.Cases) == 0 {
		t.Fatal("economy.json 无用例")
	}
	const tolerance = 1e-6
	for i, c := range v.Cases {
		got := sim.GBMNext(c.S, c.Mu, c.Sigma, c.Dt, c.Z)
		if math.Abs(got-c.ExpectedNext) > tolerance {
			t.Errorf("case %d: got=%.6f want=%.6f", i, got, c.ExpectedNext)
		}
	}
}
