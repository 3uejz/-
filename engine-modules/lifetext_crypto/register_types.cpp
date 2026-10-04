#include "register_types.h"

#include "lt_crypto.h"

#include "core/object/class_db.h"

void initialize_lifetext_crypto_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LTCrypto);
}

void uninitialize_lifetext_crypto_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
