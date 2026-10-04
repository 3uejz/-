#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// 列式二进制内容包读取器。契约见 engine-modules/README.md。
// 当前为骨架：仅校验魔数与版本头；实际列式解码 + zstd 解压在后续冻结进模块。
class LTContentPack : public RefCounted {
	GDCLASS(LTContentPack, RefCounted);

public:
	static constexpr int API_VERSION = 1;

	static int get_api_version();

	// 打开内容包：校验魔数 "LTC1" 与版本头，返回 {ok, code, message, data}。
	static Dictionary open(const PackedByteArray &p_data);

protected:
	static void _bind_methods();
};
