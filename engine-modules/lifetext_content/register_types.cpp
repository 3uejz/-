#include "register_types.h"

#include "lt_content.h"

#include "core/object/class_db.h"

void initialize_lifetext_content_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LTContentPack);
}

void uninitialize_lifetext_content_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
