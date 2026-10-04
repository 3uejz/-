class_name Uuid
extends RefCounted
## UUIDv7（时间有序）。约定见 shared/conventions.md。

static var _rng := RandomNumberGenerator.new()
static var _seeded: bool = false

static func _ensure_rng() -> void:
	if not _seeded:
		_rng.randomize()
		_seeded = true

static func v7() -> String:
	_ensure_rng()
	var ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var rand_a: int = _rng.randi() & 0xFFF
	var rand_b_hi: int = _rng.randi() & 0x3FFFFFFF
	var rand_b_lo: int = _rng.randi() & 0xFFFFFFFF

	var b := PackedByteArray()
	b.resize(16)
	b[0] = (ms >> 40) & 0xFF
	b[1] = (ms >> 32) & 0xFF
	b[2] = (ms >> 24) & 0xFF
	b[3] = (ms >> 16) & 0xFF
	b[4] = (ms >> 8) & 0xFF
	b[5] = ms & 0xFF
	b[6] = 0x70 | ((rand_a >> 8) & 0x0F)
	b[7] = rand_a & 0xFF
	b[8] = 0x80 | ((rand_b_hi >> 24) & 0x3F)
	b[9] = (rand_b_hi >> 16) & 0xFF
	b[10] = (rand_b_hi >> 8) & 0xFF
	b[11] = rand_b_hi & 0xFF
	b[12] = (rand_b_lo >> 24) & 0xFF
	b[13] = (rand_b_lo >> 16) & 0xFF
	b[14] = (rand_b_lo >> 8) & 0xFF
	b[15] = rand_b_lo & 0xFF

	var hex: String = b.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
