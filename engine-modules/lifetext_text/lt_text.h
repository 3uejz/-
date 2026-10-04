#pragma once

#include "core/object/ref_counted.h"
#include "core/string/ustring.h"

// CJK 文本辅助。契约见 engine-modules/README.md。
// 目标：高级断行、IME 归一化与候选词辅助（design「中文支持」）。
class LTText : public RefCounted {
	GDCLASS(LTText, RefCounted);

public:
	static constexpr int API_VERSION = 1;

	static int get_api_version();

	// 按显示宽度估算：CJK 与全角字符计 2，其余计 1。
	static int visible_width(const String &p_text);

	// 截断到指定显示宽度，超出时追加后缀（后缀宽度计入上限）。
	static String truncate_to_width(const String &p_text, int p_max_width, const String &p_suffix);

protected:
	static void _bind_methods();
};
