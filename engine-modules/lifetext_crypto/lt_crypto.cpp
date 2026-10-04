#include "lt_crypto.h"

#include "core/object/class_db.h"

int LTCrypto::get_api_version() {
	return API_VERSION;
}

int64_t LTCrypto::checksum64(const PackedByteArray &p_data) {
	const uint64_t offset_basis = 0xcbf29ce484222325ULL;
	const uint64_t prime = 0x00000100000001B3ULL;
	uint64_t hash = offset_basis;
	for (int i = 0; i < p_data.size(); i++) {
		hash ^= uint64_t(p_data[i]);
		hash *= prime;
	}
	return int64_t(hash);
}

Dictionary LTCrypto::seal(const PackedByteArray &p_key, const PackedByteArray &p_plaintext, const PackedByteArray &p_aad) {
	(void)p_key;
	(void)p_aad;
	Dictionary result;
	result["ok"] = false;
	result["code"] = "not_implemented";
	result["message"] = "AES-256-GCM 封装尚未接入加密后端";
	result["data"] = p_plaintext;
	return result;
}

Dictionary LTCrypto::open(const PackedByteArray &p_key, const PackedByteArray &p_ciphertext, const PackedByteArray &p_aad) {
	(void)p_key;
	(void)p_aad;
	Dictionary result;
	result["ok"] = false;
	result["code"] = "not_implemented";
	result["message"] = "AES-256-GCM 解封尚未接入加密后端";
	result["data"] = p_ciphertext;
	return result;
}

void LTCrypto::_bind_methods() {
	ClassDB::bind_static_method("LTCrypto", D_METHOD("get_api_version"), &LTCrypto::get_api_version);
	ClassDB::bind_static_method("LTCrypto", D_METHOD("checksum64", "data"), &LTCrypto::checksum64);
	ClassDB::bind_static_method("LTCrypto", D_METHOD("seal", "key", "plaintext", "aad"), &LTCrypto::seal);
	ClassDB::bind_static_method("LTCrypto", D_METHOD("open", "key", "ciphertext", "aad"), &LTCrypto::open);
}
