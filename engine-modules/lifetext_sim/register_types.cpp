#include "register_types.h"

#include "lt_sim.h"

#include "core/object/class_db.h"

void initialize_lifetext_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(LTSim);
}

void uninitialize_lifetext_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
