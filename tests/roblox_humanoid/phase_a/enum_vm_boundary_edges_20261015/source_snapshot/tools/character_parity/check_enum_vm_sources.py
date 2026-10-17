"""Compile own embedded Luau and preserve a diff against the dirty snapshot.

No Godot/Studio execution; source-only check suitable during native experiments.
"""
from pathlib import Path
import difflib
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".codex-tmp/character_parity/pre_vm_integration"
ENGINE = ROOT / "autoload/lua_script_engine.gd"
ADAPTER = ROOT / "addons/roblox_runtime/enums/roblox_enum_vm_boundary.gd"


def body(text: str, function: str) -> str:
    section = text.split(f"func {function}", 1)[1]
    return section.split('\nfunc ', 1)[0]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    source = ENGINE.read_text(encoding="utf-8")
    adapter = ADAPTER.read_text(encoding="utf-8")
    setup = body(source, "_native_lua_type_setup(")
    # Godot has exactly two string literals around the isolated typed shim.
    pieces = setup.split('"""')
    assert len(pieces) == 5
    shim = body(adapter, "type_setup()").split('"""')[1]
    (OUT / "type_setup.luau").write_text(pieces[1] + shim + pieces[3], encoding="utf-8")
    prelude = body(source, "_prepare_scheduled_lua_source(").split('"""')[1]
    prelude = prelude.replace("\\\\", "\\")
    (OUT / "scheduled_contract.luau").write_text(
        prelude + "\n" + (ROOT / "tools/character_parity/enum_vm_contract.luau").read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    compiler = ROOT / "tools/roblox_character_experiments/.compiler/luau-compile.exe"
    for file in [OUT / "type_setup.luau", OUT / "scheduled_contract.luau",
                 ROOT / "tools/character_parity/enum_vm_cyclic_contract.luau",
                 ROOT / "tools/character_parity/enum_vm_humanoid_edges_contract.luau"]:
        subprocess.run([str(compiler), "--null", str(file)], check=True)
    before = (OUT / "lua_script_engine.gd").read_text(encoding="utf-8")
    diff = "".join(difflib.unified_diff(before.splitlines(True), source.splitlines(True),
                                     fromfile="dirty-snapshot/autoload/lua_script_engine.gd",
                                     tofile="production/autoload/lua_script_engine.gd"))
    (OUT / "vm_boundary_only.patch").write_text(diff, encoding="utf-8")
    manifest = {"snapshot_sha256": hashlib.sha256((OUT / "lua_script_engine.gd").read_bytes()).hexdigest(),
                "current_sha256": hashlib.sha256(ENGINE.read_bytes()).hexdigest(),
                "scoped_patch_sha256": hashlib.sha256(diff.encode()).hexdigest(),
                "scope": "new production enum VM slice only; prior dirty changes excluded"}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
