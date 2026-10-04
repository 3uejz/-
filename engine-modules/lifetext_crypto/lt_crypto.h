#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// 存档加密与完整性辅助。契约见 engine-modules/README.md。
// 目标算法：AES-256-GCM + Argon2id 密钥派生（design「存档加密」）。
// 当前为骨架：已实现确定性的 FNV-1a 64 位校验；seal/open 待接入加密后端。
class LTCrypto : public RefCounted {
	GDCLASS(LTCrypto, RefCounted);

public:
	static constexpr int API_VERSION = 1;

	static int get_api_version();

	// 确定性 64 位 FNV-1a 校验（用于完整性快速比对，不用于安全场景）。
	static int64_t checksum64(const PackedByteArray &p_data);

	// 对称封装：返回 {ok, code, message, data}。data 为 ciphertext 的 PackedByteArray。
	static Dictionary seal(const PackedByteArray &p_key, const PackedByteArray &p_plaintext, const PackedByteArray &p_aad);

	// 对称解封：返回 {ok, code, message, data}。data 为 plaintext 的 PackedByteArray。
	static Dictionary open(const PackedByteArray &p_key, const PackedByteArray &p_ciphertext, const PackedByteArray &p_aad);

protected:
	static void _bind_methods();
};
