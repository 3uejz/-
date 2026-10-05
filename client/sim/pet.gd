class_name PetSystem
extends RefCounted
## 宠物独立子系统：领养/购买、喂养、就医、训练、走失与死亡（R51.6、R51.7）。
##
## 宠物为独立实体，拥有生命周期、属性与日程影响；存活时影响心情与日常，
## 死亡触发情绪事件。

## 物种表：寿命（年）、购买费用、日粮费用、可训练度 0..1、每日照护分钟。
const SPECIES: Dictionary = {
	"dog": {"name": "狗", "lifespan": 13.0, "buy_cost": 200000, "feed_cost": 3000, "trainability": 0.9, "daily_minutes": 60},
	"cat": {"name": "猫", "lifespan": 15.0, "buy_cost": 150000, "feed_cost": 2500, "trainability": 0.5, "daily_minutes": 30},
	"bird": {"name": "鸟", "lifespan": 10.0, "buy_cost": 80000, "feed_cost": 1000, "trainability": 0.6, "daily_minutes": 20},
	"fish": {"name": "鱼", "lifespan": 5.0, "buy_cost": 20000, "feed_cost": 500, "trainability": 0.1, "daily_minutes": 10},
	"rabbit": {"name": "兔", "lifespan": 8.0, "buy_cost": 60000, "feed_cost": 1200, "trainability": 0.3, "daily_minutes": 20},
	"hamster": {"name": "仓鼠", "lifespan": 3.0, "buy_cost": 30000, "feed_cost": 800, "trainability": 0.2, "daily_minutes": 10},
	"reptile": {"name": "爬宠", "lifespan": 20.0, "buy_cost": 500000, "feed_cost": 2000, "trainability": 0.2, "daily_minutes": 15},
}

const HUNGER_DECAY_PER_DAY: float = 12.0
const STARVATION_HEALTH_LOSS: float = 8.0
const LOST_BASE_RISK: float = 0.01
const DEATH_MOOD_DELTA: float = -20.0
const DEATH_HAPPINESS_DELTA: float = -15.0


func _clamp100(v: float) -> float:
	return clampf(v, 0.0, 100.0)


func species_count() -> int:
	return SPECIES.size()


## 领养/购买宠物（R51.6）。
func acquire(species: String, name: String, age: float = 0.0, gender: String = "male") -> Dictionary:
	if not SPECIES.has(species):
		return {"ok": false, "reason": "unknown_species"}
	var s: Dictionary = SPECIES[species]
	return {
		"ok": true, "pet": {
			"species": species, "name": name, "gender": gender, "age": age,
			"hunger": 80.0, "health": 80.0, "mood": 80.0, "training": 0.0,
			"bond": 0.0, "alive": true, "lost": false, "cost": int(s["buy_cost"]),
		}
	}


func daily_cost(pet: Dictionary) -> int:
	var s: Dictionary = SPECIES.get(str(pet.get("species", "")), {})
	return int(s.get("feed_cost", 0))


func daily_minutes(pet: Dictionary) -> int:
	var s: Dictionary = SPECIES.get(str(pet.get("species", "")), {})
	return int(s.get("daily_minutes", 0))


## 喂养（R51.6）。
func feed(pet: Dictionary, amount: float = 30.0) -> Dictionary:
	if not bool(pet.get("alive", true)):
		return {"ok": false, "reason": "dead"}
	pet["hunger"] = _clamp100(float(pet.get("hunger", 0.0)) + amount)
	pet["mood"] = _clamp100(float(pet.get("mood", 50.0)) + amount * 0.2)
	pet["bond"] = _clamp100(float(pet.get("bond", 0.0)) + amount * 0.1)
	return {"ok": true, "hunger": float(pet["hunger"]), "mood": float(pet["mood"])}


## 就医（R51.6）。
func vet(pet: Dictionary, heal: float = 30.0) -> Dictionary:
	if not bool(pet.get("alive", true)):
		return {"ok": false, "reason": "dead"}
	pet["health"] = _clamp100(float(pet.get("health", 0.0)) + heal)
	return {"ok": true, "health": float(pet["health"]), "cost": 50000}


## 训练（R51.6）。
func train(pet: Dictionary, hours: float, rng = null) -> Dictionary:
	if not bool(pet.get("alive", true)):
		return {"ok": false, "reason": "dead"}
	var s: Dictionary = SPECIES.get(str(pet.get("species", "")), {})
	var gain: float = maxf(0.0, hours) * 2.0 * float(s.get("trainability", 0.3))
	var roll: float = rng.next_float() if rng != null else 0.0
	if roll < 0.15:
		gain *= 0.5
	pet["training"] = _clamp100(float(pet.get("training", 0.0)) + gain)
	pet["mood"] = _clamp100(float(pet.get("mood", 50.0)) - maxf(0.0, hours - 2.0) * 3.0)
	return {"ok": true, "training": float(pet["training"])}


## 走失判定（R51.6）：照护不足提高风险。
func check_lost(pet: Dictionary, care_level: float, rng) -> bool:
	if not bool(pet.get("alive", true)):
		return false
	var risk: float = LOST_BASE_RISK * (1.0 + maxf(0.0, 50.0 - care_level) / 50.0)
	var roll: float = rng.next_float() if rng != null else 1.0
	if roll < risk:
		pet["lost"] = true
		return true
	return false


## 推进宠物生命周期（R51.6）：饥饿衰减、饥饿致死、衰老死亡。
func advance(pet: Dictionary, days: float, rng = null) -> Dictionary:
	if not bool(pet.get("alive", true)):
		return {"alive": false, "reason": "already_dead"}
	pet["age"] = float(pet.get("age", 0.0)) + days / 365.0
	pet["hunger"] = _clamp100(float(pet.get("hunger", 0.0)) - HUNGER_DECAY_PER_DAY * days)
	if float(pet["hunger"]) <= 0.0:
		pet["health"] = _clamp100(float(pet.get("health", 0.0)) - STARVATION_HEALTH_LOSS * days)
	var s: Dictionary = SPECIES.get(str(pet.get("species", "")), {})
	if float(pet["health"]) <= 0.0 or float(pet["age"]) >= float(s.get("lifespan", 15.0)):
		pet["alive"] = false
		return {"alive": false, "reason": "death", "event": "pet_death"}
	return {"alive": true}


## 宠物对玩家心情/幸福的影响（R51.7）。存活提升，死亡触发情绪事件。
func mood_effect(pet: Dictionary) -> Dictionary:
	if bool(pet.get("alive", true)):
		return {"mood": 2.0, "happiness": 1.0}
	return {"mood": DEATH_MOOD_DELTA, "happiness": DEATH_HAPPINESS_DELTA, "event": "pet_death"}


func to_dict(pet: Dictionary) -> Dictionary:
	return pet.duplicate(true)
