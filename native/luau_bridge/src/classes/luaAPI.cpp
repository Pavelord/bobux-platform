#include "luaAPI.h"

#include "luaCoroutine.h"
#include "luaObjectMetatable.h"

#include <luaState.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <time.h>
#endif

#ifdef LAPI_GDEXTENSION
#include <godot_cpp/classes/file_access.hpp>
#endif

LuaAPI::LuaAPI() {
	lState = lua_newstate(&LuaAPI::luaAlloc, (void *)&luaAllocData);
	Ref<LuaDefaultObjectMetatable> mt;
	mt.instantiate();
	objectMetatable = mt;

	// Creating lua state instance
	state.setState(lState, this, true);
}

LuaAPI::~LuaAPI() {
	lua_State *closing_state = lState;
	lState = nullptr;
	lua_close(closing_state);
}

// Bind C++ functions to GDScript
void LuaAPI::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_runtime_name"), &LuaAPI::getRuntimeName);
	ClassDB::bind_method(D_METHOD("set_budget_callback", "callback"), &LuaAPI::setBudgetCallback);
	ClassDB::bind_method(D_METHOD("get_vm_cpu_time_usec"), &LuaAPI::getVMCPUTimeUsec);
	ClassDB::bind_method(D_METHOD("do_file", "FilePath", "Args"), &LuaAPI::doFile, DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("do_string", "Code", "Args"), &LuaAPI::doString, DEFVAL(Array()));

	ClassDB::bind_method(D_METHOD("bind_libraries", "Array"), &LuaAPI::bindLibraries);
	ClassDB::bind_method(D_METHOD("set_hook", "Hook", "HookMask", "Count"), &LuaAPI::setHook);
	ClassDB::bind_method(D_METHOD("configure_gc", "What", "Data"), &LuaAPI::configureGC);
	ClassDB::bind_method(D_METHOD("get_memory_usage"), &LuaAPI::getMemoryUsage);
	ClassDB::bind_method(D_METHOD("push_variant", "Name", "var"), &LuaAPI::pushGlobalVariant);
	ClassDB::bind_method(D_METHOD("pull_variant", "Name"), &LuaAPI::pullVariant);
	ClassDB::bind_method(D_METHOD("get_registry_value", "Name"), &LuaAPI::getRegistryValue);
	ClassDB::bind_method(D_METHOD("set_registry_value", "Name", "var"), &LuaAPI::setRegistryValue);
	ClassDB::bind_method(D_METHOD("call_function", "LuaFunctionName", "Args"), &LuaAPI::callFunction);
	ClassDB::bind_method(D_METHOD("function_exists", "LuaFunctionName"), &LuaAPI::luaFunctionExists);

	ClassDB::bind_method(D_METHOD("new_coroutine"), &LuaAPI::newCoroutine);
	ClassDB::bind_method(D_METHOD("get_running_coroutine"), &LuaAPI::getRunningCoroutine);

	ClassDB::bind_method(D_METHOD("set_use_callables", "value"), &LuaAPI::setUseCallables);
	ClassDB::bind_method(D_METHOD("get_use_callables"), &LuaAPI::getUseCallables);

	ClassDB::bind_method(D_METHOD("set_object_metatable", "value"), &LuaAPI::setObjectMetatable);
	ClassDB::bind_method(D_METHOD("get_object_metatable"), &LuaAPI::getObjectMetatable);

	ClassDB::bind_method(D_METHOD("set_memory_limit", "limit"), &LuaAPI::setMemoryLimit);
	ClassDB::bind_method(D_METHOD("get_memory_limit"), &LuaAPI::getMemoryLimit);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_callables"), "set_use_callables", "get_use_callables");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "object_metatable"), "set_object_metatable", "get_object_metatable");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "memory_limit"), "set_memory_limit", "get_memory_limit");

	BIND_ENUM_CONSTANT(HOOK_MASK_CALL);
	BIND_ENUM_CONSTANT(HOOK_MASK_RETURN);
	BIND_ENUM_CONSTANT(HOOK_MASK_LINE);
	BIND_ENUM_CONSTANT(HOOK_MASK_COUNT);

	BIND_ENUM_CONSTANT(GC_STOP);
	BIND_ENUM_CONSTANT(GC_RESTART);
	BIND_ENUM_CONSTANT(GC_COLLECT);
	BIND_ENUM_CONSTANT(GC_COUNT);
	BIND_ENUM_CONSTANT(GC_COUNTB);
	BIND_ENUM_CONSTANT(GC_STEP);
	BIND_ENUM_CONSTANT(GC_SETPAUSE);
	BIND_ENUM_CONSTANT(GC_SETSTEPMUL);
}

uint64_t LuaAPI::threadCPUTimeUsec() {
#ifdef _WIN32
	FILETIME creation, exit, kernel, user;
	if (GetThreadTimes(GetCurrentThread(), &creation, &exit, &kernel, &user)) {
		ULARGE_INTEGER kernel_time, user_time;
		kernel_time.LowPart = kernel.dwLowDateTime;
		kernel_time.HighPart = kernel.dwHighDateTime;
		user_time.LowPart = user.dwLowDateTime;
		user_time.HighPart = user.dwHighDateTime;
		return (kernel_time.QuadPart + user_time.QuadPart) / 10;
	}
	return 0;
#else
	timespec value;
	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) == 0)
		return uint64_t(value.tv_sec) * 1000000 + uint64_t(value.tv_nsec) / 1000;
	return 0;
#endif
}

uint64_t LuaAPI::getVMCPUTimeUsec() const {
	const uint64_t now = threadCPUTimeUsec();
	const uint64_t active_native = nativeCallDepth ? now - nativeCallStartedUsec : 0;
	return now >= nativeCPUTimeUsec + active_native ? now - nativeCPUTimeUsec - active_native : 0;
}

void LuaAPI::beginNativeCall() {
	if (nativeCallDepth++ == 0) nativeCallStartedUsec = threadCPUTimeUsec();
}

void LuaAPI::endNativeCall() {
	if (nativeCallDepth && --nativeCallDepth == 0) nativeCPUTimeUsec += threadCPUTimeUsec() - nativeCallStartedUsec;
}

uint32_t LuaAPI::pauseNativeCalls() {
	const uint32_t depth = nativeCallDepth;
	if (depth) {
		nativeCPUTimeUsec += threadCPUTimeUsec() - nativeCallStartedUsec;
		nativeCallDepth = 0;
	}
	return depth;
}

void LuaAPI::resumeNativeCalls(uint32_t depth) {
	if (depth) {
		nativeCallStartedUsec = threadCPUTimeUsec();
		nativeCallDepth = depth;
	}
}

// Calls LuaState::bindLibs()
void LuaAPI::setBudgetCallback(Callable callback) {
	budgetCallback = callback;
	lua_callbacks(lState)->userdata = this;
	lua_callbacks(lState)->interrupt = budgetInterrupt;
}

void LuaAPI::budgetInterrupt(lua_State *L, int gc) {
	if (gc >= 0) return;
	LuaAPI *owner = static_cast<LuaAPI *>(lua_callbacks(L)->userdata);
	if (!owner || !owner->budgetCallback.is_valid()) return;
	// Luau interrupts on every loop backedge and function entry. Crossing the
	// Godot ABI each time makes ordinary recursive Instance walks hit the budget.
	// Imported scripts spend much more time in Instance bridges than in numeric
	// loops. 128 entries can mean a 100ms frame before the 3ms slice is checked.
	if ((++owner->interruptCount & 7u) != 0) return;
	const bool can_preempt = owner->scheduledThread == L && lua_isyieldable(L);
	int action = 0;
	{
		Variant result = owner->budgetCallback.call(can_preempt);
		action = result.get_type() == Variant::INT ? int(result) : (bool(result) ? 2 : 0);
	}
	// Never execute Lua from a VM interrupt or throw across Godot temporaries.
	if (action == 2) luaL_error(L, "Script execution budget exceeded\n%s", lua_debugtrace(L));
	if (action == 1 && can_preempt) lua_break(L);
}

Ref<LuaError> LuaAPI::bindLibraries(TypedArray<String> libs) {
	return state.bindLibraries(libs);
}

void LuaAPI::setHook(Callable hook, int mask, int count) {
	return state.setHook(hook, mask, count);
}

int LuaAPI::configureGC(int what, int data) {
	return lua_gc(lState, what, data);
}

void LuaAPI::setUseCallables(bool value) {
	useCallables = value;
}

bool LuaAPI::getUseCallables() const {
	return useCallables;
}

void LuaAPI::setObjectMetatable(Ref<LuaObjectMetatable> value) {
	objectMetatable = value;
}

Ref<LuaObjectMetatable> LuaAPI::getObjectMetatable() const {
	return objectMetatable;
}

void LuaAPI::setMemoryLimit(uint64_t limit) {
	luaAllocData.memoryLimit = limit;
}

uint64_t LuaAPI::getMemoryLimit() const {
	return luaAllocData.memoryLimit;
}

Variant LuaAPI::getRegistryValue(String name) {
	return state.getRegistryValue(name);
}

Ref<LuaError> LuaAPI::setRegistryValue(String name, Variant var) {
	return state.setRegistryValue(name, var);
}

uint64_t LuaAPI::getMemoryUsage() const {
	return luaAllocData.memoryUsed;
}

// Calls LuaState::luaFunctionExists()
bool LuaAPI::luaFunctionExists(String functionName) {
	return state.luaFunctionExists(functionName);
}

// Calls LuaState::pullVariant()
Variant LuaAPI::pullVariant(String name) {
	return state.pullVariant(name);
}

// Calls LuaState::callFunction()
Variant LuaAPI::callFunction(String functionName, Array args) {
	return state.callFunction(functionName, args);
}

// Calls LuaState::pushGlobalVariant()
Ref<LuaError> LuaAPI::pushGlobalVariant(String name, Variant var) {
	return state.pushGlobalVariant(name, var);
}

// addFile() calls luaL_loadfille with the absolute file path
Variant LuaAPI::doFile(String fileName, Array args) {
	String path;
	// fileAccess never unrefs without this
	{
#ifndef LAPI_GDEXTENSION
		Error error;
		Ref<FileAccess> file = FileAccess::open(fileName, FileAccess::READ, &error);
		if (error != Error::OK) {
			return LuaError::newError(vformat("error '%s' while opening file '%s'", error_names[error], fileName), LuaError::ERR_FILE);
		}
#else
		Ref<FileAccess> file = FileAccess::open(fileName, FileAccess::READ);
		if (!file.is_valid()) {
			return LuaError::newError(vformat("error while opening file '%s'", fileName), LuaError::ERR_FILE);
		}
#endif

		path = file->get_path_absolute();
	}

	const int base = lua_gettop(lState);
	lua_pushcfunction(lState, LuaState::luaErrorHandler);
	int err = luaL_loadfile(lState, path.utf8().get_data());
	if (err != LUA_OK) {
		Variant error = state.handleError(err);
		lua_settop(lState, base);
		return error;
	}

	int argc = args.size();
	for (int i = 0; i < argc; i++) {
		state.pushVariant(args[i]);
	}

	int handlerIndex = -2 - argc;

	Variant ret = execute(argc, handlerIndex);
	lua_settop(lState, base);
	return ret;
}

// Loads string into lua state and executes the top of the stack
Variant LuaAPI::doString(String code, Array args) {
	const int base = lua_gettop(lState);
	// push the error handler onto the stack
	lua_pushcfunction(lState, LuaState::luaErrorHandler);

	int err = luaL_loadstring(lState, code.utf8().get_data());
	if (err != LUA_OK) {
		Variant error = state.handleError(err);
		lua_settop(lState, base);
		return error;
	}

	int argc = args.size();
	for (int i = 0; i < argc; i++) {
		state.pushVariant(args[i]);
	}

	int handlerIndex = -2 - argc;

	Variant ret = execute(argc, handlerIndex);
	lua_settop(lState, base);
	return ret;
}

// Execute the current lua stack, return error as string if one occurs, otherwise return String()
Variant LuaAPI::execute(int argc, int handlerIndex) {
	int err = lua_pcall(lState, argc, 1, handlerIndex);
	if (err != LUA_OK) {
		return state.handleError(err);
	}

	return state.getVar();
}

Ref<LuaCoroutine> LuaAPI::newCoroutine() {
	Ref<LuaCoroutine> thread;
	thread.instantiate();
	thread->bind(this);
	return thread;
}

Ref<LuaCoroutine> LuaAPI::getRunningCoroutine() {
	Variant top = state.getVar();
	if (top.get_type() != Variant::Type::OBJECT) {
		return nullptr;
	}

#ifndef LAPI_GDEXTENSION
	Ref<LuaCoroutine> thread = Object::cast_to<LuaCoroutine>(top);
#else
	Ref<LuaCoroutine> thread = dynamic_cast<LuaCoroutine *>(top.operator Object *());
#endif
	return thread;
}

// Creates a new thread staee
lua_State *LuaAPI::newThreadState() {
	return lua_newthread(lState);
}

// returns state
lua_State *LuaAPI::getState() {
	return lState;
}

void *LuaAPI::luaAlloc(void *ud, void *ptr, size_t osize, size_t nsize) {
	LuaAllocData *data = (LuaAllocData *)ud;
	if (nsize == 0) {
		if (ptr != nullptr) {
			data->memoryUsed -= osize;
			memfree(ptr);
		}
		return nullptr;
	}

	if (ptr == nullptr) {
		if (data->memoryLimit != 0 && data->memoryUsed + (uint64_t)nsize > data->memoryLimit) {
			return nullptr;
		}

		data->memoryUsed += (uint64_t)nsize;
		return memalloc(nsize);
	}

	if (data->memoryLimit != 0 && data->memoryUsed - (uint64_t)osize + (uint64_t)nsize > data->memoryLimit) {
		return nullptr;
	}

	data->memoryUsed -= (uint64_t)osize;
	data->memoryUsed += (uint64_t)nsize;
	return memrealloc(ptr, nsize);
}
