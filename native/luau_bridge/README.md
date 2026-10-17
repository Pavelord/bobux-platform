# Bobux Luau bridge

Executes Luau bytecode, retaining the `LuaAPI` GDExtension class names used by
the existing Godot integration. It is based on Godot LuaAPI (see LICENSE).

Pinned source checkouts expected under `.codex-tools/sources`:

- `luau`: luau-lang/luau, 0.719, `54426c4217740440c25d51fd579a4746028551c3`
- `godot_luaAPI`: WeaselGames/godot_luaAPI, `edf4afe7665a03978e8a4a3a15b727a66c4dc03d`
- `godot_luaAPI/external/godot-cpp`: `78ffea5b136f3178c31cddb28f6b963ceaa89420`

From the repository root with Python, SCons and the platform C++ toolchain:

```
python -m SCons -C native/luau_bridge platform=windows target=template_debug arch=x86_64 -j6
```

Use `build_library=no` only when the matching godot-cpp library already exists.
Use `target=template_release` for the Windows release library. Other platforms
must be built and tested before changing their mappings in luaAPI.gdextension.

The VM uses Luau's supported `LUA_USE_LONGJMP` error mode. Interrupt callbacks
release Godot temporaries before raising an error. Scheduled Luau coroutines can
return `LUA_BREAK` to pause at an instruction boundary: their live stacks are
preserved until the next frame. A normal script yield resets the cumulative
watchdog; scheduler preemption does not. Non-yieldable callbacks retain the
short, protected-call watchdog.

Regression checks: `validate_luau_scheduling.gd`,
`validate_lua_instruction_budget.gd`, `validate_lua_runtime_regressions.gd`,
`validate_lua_service_compatibility.gd`, `validate_roblox_import_contracts.gd`.
