#include "lt_text.h"

#include "core/object/class_db.h"

static int _char_width(char32_t p_char) {
	if (p_char == 0) {
		return 0;
	}
	// 组合附加符号与零宽控制符不占宽度。
	if ((p_char >= 0x0300 && p_char <= 0x036F) || p_char == 0x200B || p_char == 0x200D || p_char == 0xFEFF) {
		return 0;
	}
	// CJK、全角标点与常见宽字符区间粗略判定为 2。
	if ((p_char >= 0x1100 && p_char <= 0x115F) ||
			(p_char >= 0x2E80 && p_char <= 0xA4CF) ||
			(p_char >= 0xAC00 && p_char <= 0xD7A3) ||
			(p_char >= 0xF900 && p_char <= 0xFAFF) ||
			(p_char >= 0xFE30 && p_char <= 0xFE4F) ||
			(p_char >= 0xFF00 && p_char <= 0xFF60) ||
			(p_char >= 0xFFE0 && p_char <= 0xFFE6) ||
			(p_char >= 0x20000 && p_char <= 0x3FFFD)) {
		return 2;
	}
	return 1;
}

int LTText::get_api_version() {
	return API_VERSION;
}

int LTText::visible_width(const String &p_text) {
	int width = 0;
	for (int i = 0; i < p_text.length(); i++) {
		width += _char_width(p_text[i]);
	}
	return width;
}

String LTText::truncate_to_width(const String &p_text, int p_max_width, const String &p_suffix) {
	if (p_max_width <= 0) {
		return String();
	}
	int suffix_width = visible_width(p_suffix);
	int width = 0;
	for (int i = 0; i < p_text.length(); i++) {
		int next = width + _char_width(p_text[i]);
		if (next + suffix_width > p_max_width) {
			return p_text.substr(0, i) + p_suffix;
		}
		width = next;
	}
	return p_text;
}

void LTText::_bind_methods() {
	ClassDB::bind_static_method("LTText", D_METHOD("get_api_version"), &LTText::get_api_version);
	ClassDB::bind_static_method("LTText", D_METHOD("visible_width", "text"), &LTText::visible_width);
	ClassDB::bind_static_method("LTText", D_METHOD("truncate_to_width", "text", "max_width", "suffix"), &LTText::truncate_to_width);
}
