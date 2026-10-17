#pragma once
#include <lua.h>
#include <lualib.h>
#include <cstring>
#include <godot_cpp/classes/file_access.hpp>

// Keep the existing Godot bridge API while executing real Luau bytecode.
#define LUA_MASKCALL 1
#define LUA_MASKRET 2
#define LUA_MASKLINE 4
#define LUA_MASKCOUNT 8
#define LUA_ERRFILE 7
#define LUA_GCSETPAUSE LUA_GCSETGOAL
#undef lua_pushcfunction
#undef lua_pushcclosure
#define lua_pushcfunction(L, fn) lua_pushcclosurek(L, fn, nullptr, 0, nullptr)
#define lua_pushcclosure(L, fn, n) lua_pushcclosurek(L, fn, nullptr, n, nullptr)
#define lua_register(L, name, fn) (lua_pushcfunction(L, fn), lua_setglobal(L, name))
#define lua_pushglobaltable(L) lua_pushvalue(L, LUA_GLOBALSINDEX)
inline void lua_len(lua_State *L, int index) { lua_pushinteger(L, lua_objlen(L, index)); }
inline void lua_geti(lua_State *L, int index, int key) { lua_rawgeti(L, index, key); }
inline void luaL_setmetatable(lua_State *L, const char *name) { luaL_getmetatable(L, name); lua_setmetatable(L, -2); }
inline int luaL_ref(lua_State *L, int) { int ref = lua_ref(L, -1); lua_pop(L, 1); return ref; }
inline void luaL_unref(lua_State *L, int, int ref) { lua_unref(L, ref); }
inline int bobux_resume(lua_State *L, int argc, int *results) {
    int status = lua_resume(L, nullptr, argc);
    *results = lua_gettop(L);
    return status;
}
int luaL_loadstring(lua_State *L, const char *source);
int luaL_loadfile(lua_State *L, const char *path);
void lua_sethook(lua_State *L, lua_Hook hook, int mask, int count);
void bobux_install_debug_bridge(lua_State *L);
void bobux_install_base_bridge(lua_State *L);
