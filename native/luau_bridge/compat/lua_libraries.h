#pragma once
#include "bobux_luau_compat.h"
#include <godot_cpp/variant/string.hpp>
bool loadLuaLibrary(lua_State *L, godot::String name);
