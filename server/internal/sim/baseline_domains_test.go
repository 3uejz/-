package sim_test

import (
	"encoding/json"
	"fmt"
	"math"
	"testing"

	"lifetextsandbox/server/internal/sim"
)

// TestBaselineDomainsConsistency 校验新迁移域（survival/region/geo_transport/
// climate_weather/era/economy）的生成常量与共享向量 baseline_domains.json 一致。
func TestBaselineDomainsConsistency(t *testing.T) {
	var v struct {
		Domains map[string]map[string]any `json:"domains"`
	}
	readVectorFile(t, "baseline_domains.json", &v)
	if len(v.Domains) == 0 {
		t.Fatal("baseline_domains.json 无 domains")
	}

	code := map[string]map[string]any{
		"survival": {
			"HUNGER_DECAY_PER_MIN":      sim.BaselineHungerDecayPerMin,
			"THIRST_DECAY_PER_MIN":      sim.BaselineThirstDecayPerMin,
			"CLEANLINESS_DECAY_PER_MIN": sim.BaselineCleanlinessDecayPerMin,
			"SLEEP_DEBT_THRESHOLD":      sim.BaselineSleepDebtThreshold,
			"MOOD_RECOVER_PER_HOUR":     sim.BaselineMoodRecoverPerHour,
			"LIFESPAN_BASE_YEARS":       sim.BaselineLifespanBaseYears,
			"DYING_HEALTH_THRESHOLD":    sim.BaselineDyingHealthThreshold,
			"ADDICTION_DEPENDENT_MIN":   sim.BaselineAddictionDependentMin,
			"NUTRITION_LIGHT_THRESHOLD": sim.BaselineNutritionLightThreshold,
		},
		"region": {
			"REGION_BIRTH_RATE_ANNUAL":     sim.BaselineRegionBirthRateAnnual,
			"REGION_DEATH_RATE_ANNUAL":     sim.BaselineRegionDeathRateAnnual,
			"REGION_MIGRATION_RATE_ANNUAL": sim.BaselineRegionMigrationRateAnnual,
			"REGION_ECONOMY_GROWTH_ANNUAL": sim.BaselineRegionEconomyGrowthAnnual,
			"REGION_DAYS_PER_YEAR":         sim.BaselineRegionDaysPerYear,
		},
		"geo_transport": {
			"EARTH_RADIUS_KM":                    sim.BaselineEarthRadiusKm,
			"GEO_MIN_TOTAL_LOCATIONS":            sim.BaselineGeoMinTotalLocations,
			"TRANSPORT_CONGESTION_PEAK_FACTOR":   sim.BaselineTransportCongestionPeakFactor,
			"TRANSPORT_TRANSFER_MINUTES_DEFAULT": sim.BaselineTransportTransferMinutesDefault,
			"TRANSPORT_MODE_ORDER":               sim.BaselineTransportModeOrder,
		},
		"climate_weather": {
			"WEATHER_TEMP_MIN":           sim.BaselineWeatherTempMin,
			"WEATHER_TEMP_MAX":           sim.BaselineWeatherTempMax,
			"WEATHER_HUMIDITY_MAX":       sim.BaselineWeatherHumidityMax,
			"WEATHER_FORECAST_DAYS":      sim.BaselineWeatherForecastDays,
			"WEATHER_MARKOV_PERSISTENCE": sim.BaselineWeatherMarkovPersistence,
			"WEATHER_DAYS_PER_YEAR":      sim.BaselineWeatherDaysPerYear,
			"CLIMATE_ZONE_ORDER":         sim.BaselineClimateZoneOrder,
		},
		"era": {
			"ERA_COUNT": sim.BaselineEraCount,
		},
		"economy": {
			"MONEY_MINOR_SCALE":    sim.BaselineMoneyMinorScale,
			"FX_ANNUAL_VOLATILITY": sim.BaselineFxAnnualVolatility,
			"PRICE_FLOOR_RATIO":    sim.BaselinePriceFloorRatio,
			"PRICE_CEIL_RATIO":     sim.BaselinePriceCeilRatio,
			"TAX_CORPORATE_RATE":   sim.BaselineTaxCorporateRate,
			"TAX_VAT_RATE":         sim.BaselineTaxVatRate,
			"LOTTERY_WIN_CHANCE":   sim.BaselineLotteryWinChance,
			"MACRO_BASE_INFLATION": sim.BaselineMacroBaseInflation,
			"GBM_DRIFT_DEFAULT":    sim.BaselineGbmDriftDefault,
			"BANK_CREDIT_START":    sim.BaselineBankCreditStart,
		},
		"epidemic": {
			"SEIR_BETA_REDUCTION_CAP":        sim.BaselineSeirBetaReductionCap,
			"SEIR_SURGE_EXTRA_SLOPE":         sim.BaselineSeirSurgeExtraSlope,
			"SEIR_BEDS_DIVISOR":              sim.BaselineSeirBedsDivisor,
			"SEIR_DEFAULT_VACCINE_HESITANCY": sim.BaselineSeirDefaultVaccineHesitancy,
			"SEIR_POLICY_TRUST_PENALTY":      sim.BaselineSeirPolicyTrustPenalty,
			"SEIR_IMMUNITY_WANE_RATE":        sim.BaselineSeirImmunityWaneRate,
			"SEIR_ALERT_WATCH_PREVALENCE":    sim.BaselineSeirAlertWatchPrevalence,
			"SEIR_ALERT_ALERT_OCCUPANCY":     sim.BaselineSeirAlertAlertOccupancy,
			"SEIR_ALERT_EMERGENCY_OCCUPANCY": sim.BaselineSeirAlertEmergencyOccupancy,
			"SEIR_DEFAULT_PARAMS":            sim.BaselineSeirDefaultParams,
			"SEIR_POLICY_BETA_REDUCTION":     sim.BaselineSeirPolicyBetaReduction,
		},
		"environment": {
			"ENV_DEFAULT_CARBON_PRICE":   sim.BaselineEnvDefaultCarbonPrice,
			"ENV_CARBON_FINE_MULTIPLIER": sim.BaselineEnvCarbonFineMultiplier,
			"ENV_FOOTPRINT_SCOPE1":       sim.BaselineEnvFootprintScope1,
			"ENV_FOOTPRINT_SCOPE2":       sim.BaselineEnvFootprintScope2,
			"ENV_FOOTPRINT_SCOPE3":       sim.BaselineEnvFootprintScope3,
			"ENV_ESG_SCORE_MAX":          sim.BaselineEnvEsgScoreMax,
			"ENV_ESG_GRADE_A":            sim.BaselineEnvEsgGradeA,
			"ENV_ESG_GRADE_B":            sim.BaselineEnvEsgGradeB,
			"ENV_ESG_GRADE_C":            sim.BaselineEnvEsgGradeC,
		},
		"engineering": {
			"ENGINEERING_ACCEPTANCE_QUALITY_THRESHOLD": sim.BaselineEngineeringAcceptanceQualityThreshold,
			"ENGINEERING_CHAIN":                        sim.BaselineEngineeringChain,
			"ENGINEERING_ZONE_TYPES":                   sim.BaselineEngineeringZoneTypes,
		},
		"medical": {
			"MEDICAL_UNTREATED_FREE_DAYS":            sim.BaselineMedicalUntreatedFreeDays,
			"MEDICAL_UNTREATED_HEALTH_DECAY_PER_DAY": sim.BaselineMedicalUntreatedHealthDecayPerDay,
			"MEDICAL_MISDIAGNOSIS_CHANCE":            sim.BaselineMedicalMisdiagnosisChance,
			"MEDICAL_SERVICE_COST":                   sim.BaselineMedicalServiceCost,
		},
		"sports": {
			"SPORTS_PEAK_MIN_AGE":      sim.BaselineSportsPeakMinAge,
			"SPORTS_PEAK_MAX_AGE":      sim.BaselineSportsPeakMaxAge,
			"SPORTS_AGE_DECLINE_RATE":  sim.BaselineSportsAgeDeclineRate,
			"SPORTS_AGE_FLOOR":         sim.BaselineSportsAgeFloor,
			"SPORTS_TRAIN_RATE":        sim.BaselineSportsTrainRate,
			"SPORTS_INJURY_PENALTY":    sim.BaselineSportsInjuryPenalty,
			"SPORTS_INJURY_BASE_RISK":  sim.BaselineSportsInjuryBaseRisk,
			"SPORTS_DOPING_BOOST":      sim.BaselineSportsDopingBoost,
			"SPORTS_DOPING_BAN_CHANCE": sim.BaselineSportsDopingBanChance,
		},
		"aesthetics": {
			"AESTHETICS_OVER_MEDICALIZATION_THRESHOLD": sim.BaselineAestheticsOverMedicalizationThreshold,
			"AESTHETICS_STIFFNESS_PER_PROCEDURE":       sim.BaselineAestheticsStiffnessPerProcedure,
			"AESTHETICS_ILLEGAL_SUCCESS_MULT":          sim.BaselineAestheticsIllegalSuccessMult,
			"AESTHETICS_ILLEGAL_COMPLICATION_MULT":     sim.BaselineAestheticsIllegalComplicationMult,
			"AESTHETICS_MALPRACTICE_COMPENSATION":      sim.BaselineAestheticsMalpracticeCompensation,
		},
	}

	for domain, expected := range v.Domains {
		gots, ok := code[domain]
		if !ok {
			t.Errorf("代码缺少域 %s", domain)
			continue
		}
		for key, want := range expected {
			got, ok := gots[key]
			if !ok {
				t.Errorf("%s.%s 常量缺失", domain, key)
				continue
			}
			compareVectorValue(t, fmt.Sprintf("%s.%s", domain, key), got, want)
		}
	}
}

func compareVectorValue(t *testing.T, label string, got, want any) {
	t.Helper()
	switch w := want.(type) {
	case []any:
		g, ok := got.([]any)
		if !ok {
			t.Errorf("%s: 类型应为数组，got %T", label, got)
			return
		}
		if len(g) != len(w) {
			t.Errorf("%s: 长度 got=%d want=%d", label, len(g), len(w))
			return
		}
		for i := range w {
			if fmt.Sprint(g[i]) != fmt.Sprint(w[i]) {
				t.Errorf("%s[%d]: got=%v want=%v", label, i, g[i], w[i])
			}
		}
	case float64:
		gf, ok := toFloat(got)
		if !ok {
			t.Errorf("%s: 类型应为数值，got %T", label, got)
			return
		}
		if math.Abs(gf-w) > 1e-9 {
			t.Errorf("%s: got=%v want=%v", label, gf, w)
		}
	default:
		if fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("%s: got=%v want=%v", label, got, want)
		}
	}
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case json.Number:
		f, err := n.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}
