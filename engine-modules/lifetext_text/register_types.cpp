#include "register_types.h"

#include "lt_text.h"

#include "core/object/class_db.h"

void initialize_lifetext_text_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LTText);
}

void uninitialize_lifetext_text_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
