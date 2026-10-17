#include "bobux_luau_compat.h"
#include <Luau/Compiler.h>

int luaL_loadstring(lua_State *L, const char *source) {
    std::string bytecode = Luau::compile(source);
    return luau_load(L, "=Bobux", bytecode.data(), bytecode.size(), 0);
}
static int source_loader(lua_State *L) {
    size_t size = 0;
    const char *source = luaL_checklstring(L, 1, &size);
    if (size > 1024 * 1024) return luaL_error(L, "Script exceeds source size limit"), 0;
    // Compile source only; never accept externally supplied bytecode.
    int status = luaL_loadstring(L, source);
    if (status == LUA_OK) return 1;
    lua_pushnil(L);
    lua_insert(L, -2);
    return 2;
}
static int collect_garbage(lua_State *L) {
    const char *mode = luaL_optstring(L, 1, "collect");
    if (strcmp(mode, "count") == 0) { lua_pushnumber(L, lua_gc(L, LUA_GCCOUNT, 0)); return 1; }
    if (strcmp(mode, "collect") == 0) lua_gc(L, LUA_GCCOLLECT, 0);
    return 0;
}
void bobux_install_base_bridge(lua_State *L) {
    lua_pushcfunction(L, source_loader); lua_setglobal(L, "load");
    lua_pushcfunction(L, source_loader); lua_setglobal(L, "loadstring");
    lua_pushcfunction(L, collect_garbage); lua_setglobal(L, "collectgarbage");
}
int luaL_loadfile(lua_State *L, const char *path) {
    auto file = godot::FileAccess::open(path, godot::FileAccess::READ);
    if (file.is_null()) { lua_pushstring(L, "Cannot open script file"); return LUA_ERRFILE; }
    auto code = file->get_as_text().utf8();
    return luaL_loadstring(L, code.get_data());
}

// Internal only. The runtime removes the debug table before user scripts run.
static int raw_getmetatable(lua_State *L) {
    if (!lua_getmetatable(L, 1)) lua_pushnil(L);
    return 1;
}
static int private_sethook(lua_State *L) {
    // Kept for setup compatibility; the host owns Luau's interrupt callback.
    return 0;
}
void bobux_install_debug_bridge(lua_State *L) {
    lua_getglobal(L, "debug");
    lua_pushcfunction(L, raw_getmetatable); lua_setfield(L, -2, "getmetatable");
    lua_pushcfunction(L, private_sethook); lua_setfield(L, -2, "sethook");
    lua_pop(L, 1);
}
void lua_sethook(lua_State *, lua_Hook, int, int) {
    // The engine's private Lua hook above is authoritative; no public debug hooks.
}
