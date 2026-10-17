#include "lua_libraries.h"
bool loadLuaLibrary(lua_State *L, godot::String name) {
    struct Library { const char *name; lua_CFunction open; };
    static const Library libraries[] = {
        {"base", luaopen_base}, {"coroutine", luaopen_coroutine},
        {"math", luaopen_math}, {"string", luaopen_string},
        {"table", luaopen_table}, {"utf8", luaopen_utf8},
        {"debug", luaopen_debug}, {"bit32", luaopen_bit32}, {"buffer", luaopen_buffer}
    };
    for (auto &lib : libraries) {
        if (name != lib.name) continue;
        int top = lua_gettop(L);
        lua_pushcfunction(L, lib.open);
        lua_pushstring(L, name == "base" ? "" : lib.name);
        lua_call(L, 1, 0);
        lua_settop(L, top);
        if (name == "debug") bobux_install_debug_bridge(L);
        if (name == "base") bobux_install_base_bridge(L);
        return true;
    }
    return false;
}
