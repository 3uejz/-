#include "lt_content.h"

#include "core/object/class_db.h"

int LTContentPack::get_api_version() {
	return API_VERSION;
}

Dictionary LTContentPack::open(const PackedByteArray &p_data) {
	Dictionary result;
	result["ok"] = false;
	result["code"] = "no_data";
	result["message"] = "内容包为空";
	result["data"] = Variant();

	if (p_data.is_empty()) {
		return result;
	}
	if (p_data.size() < 8) {
		result["code"] = "truncated_header";
		result["message"] = "内容包头不完整";
		return result;
	}

	const uint8_t *bytes = p_data.ptr();
	const bool magic_ok = bytes[0] == 'L' && bytes[1] == 'T' && bytes[2] == 'C' && bytes[3] == '1';
	if (!magic_ok) {
		result["code"] = "bad_magic";
		result["message"] = "无法识别的内容包魔数";
		return result;
	}

	const uint32_t version = uint32_t(bytes[4]) | (uint32_t(bytes[5]) << 8) | (uint32_t(bytes[6]) << 16) | (uint32_t(bytes[7]) << 24);
	Dictionary header;
	header["format_version"] = int64_t(version);
	header["body_size"] = int64_t(p_data.size() - 8);

	result["ok"] = true;
	result["code"] = "ok";
	result["message"] = "";
	result["data"] = header;
	return result;
}

void LTContentPack::_bind_methods() {
	ClassDB::bind_static_method("LTContentPack", D_METHOD("get_api_version"), &LTContentPack::get_api_version);
	ClassDB::bind_static_method("LTContentPack", D_METHOD("open", "data"), &LTContentPack::open);
}
