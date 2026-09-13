# Packaged Lua runtime

The distributed game uses WeaselGames/godot_luaAPI (Lua 5.4), source revision
`edf4afe7665a03978e8a4a3a15b727a66c4dc03d`.
Apply `tools/patches/luaapi-callback-lifetime.patch` to that checkout.
It also fixes a dangling CharString pointer in the standard-library name loader.
Optimized release builds could omit math/string/table despite loading the DLL.
It retains the main Lua state for callbacks, checks the owner's lifetime before
unreferencing callbacks and restores the Lua stack after a callback. Previously,
callbacks could retain a destroyed coroutine or leave error handlers on the stack.

Build with the upstream SConstruct and initialized submodules:

```
scons platform=windows target=template_release arch=x86_32 -j4
scons platform=windows target=template_debug arch=x86_32 -j4
scons platform=windows target=template_release arch=x86_64 -j4
scons platform=windows target=template_debug arch=x86_64 -j4
scons platform=linux target=template_release arch=x86_64 -j4
scons platform=linux target=template_debug arch=x86_64 -j4
scons platform=android target=template_release arch=arm64 -j4
scons platform=android target=template_debug arch=arm64 -j4
scons platform=android target=template_release arch=arm32 -j4
scons platform=android target=template_debug arch=arm32 -j4
```

Use the upstream required Android NDK and set ANDROID_NDK_ROOT. Windows builds
use MSVC. Copy results from `project/addons/luaAPI/bin` into `addons/luaAPI/bin`.
The Windows x64 debug binary is named `.bobux.dll` in the extension descriptor
so the previous DLL can remain loaded in an open editor during an update.
Restart Godot to load the new extension. macOS/iOS and Linux x86 are not release
targets of this patch.

The Windows release is x86_32, not x86_64. Its DLL must match the exported engine.
Packaging copies the DLL explicitly and verifies its checksum in the manifest.
Both staging and the extracted ZIP must run:

```
Bobux.exe --headless --audio-driver Dummy -- --verify-lua-runtime
```

Exit 0 and `BOBUX_LUA_SMOKE_OK` require actual Lua execution, an Instance mutation,
an event callback and asynchronous task continuation. Missing DLLs and GDScript
parse errors fail the release. Merely finding a DLL is not a successful test.
