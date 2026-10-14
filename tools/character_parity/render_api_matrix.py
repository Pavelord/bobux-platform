"""Render Phase A1 factual inventory with conservative, manually reviewed routes.

The route registry below is an audit judgement, not automatic name detection.
Unknown/generic metadata storage never earns functional support. No member is
marked full until all relevant contract aspects and profiles have been tested.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from inventory_character_api import ROOT, OUT, BASE_CLASSES, member_name

LUA = "autoload/lua_script_engine.gd"
PLAYER = "scripts/player/player.gd"
NPC = "addons/roblox_runtime/roblox_humanoid_motor.gd"
RULES: dict[tuple[str, str], dict] = {}


def rule(cls: str, members: str, status: str, path: str, anchor: str, limitation: str, tests: tuple[str, ...] = ()) -> None:
    for name in members.split():
        RULES[cls, name] = {"status": status, "path": path, "anchor": anchor, "limitation": limitation, "tests": list(tests)}


PTEST = "tools/validate_humanoid_player_contract.gd"
NTEST = "tools/validate_humanoid_npc_contract.gd"
NETTEST = "tools/validate_humanoid_commands.gd"
PHYSTEST = "tools/validate_imported_physics.gd"
SEATTEST = "tools/validate_seat_authority.gd"
INPUTTEST = "tools/validate_lua_input.gd"
TOOLTEST = "tools/validate_roblox_inventory_runtime.gd"
SPAWNTEST = "tools/validate_studio_respawn_checkpoint.gd"

rule("Humanoid", "Health MaxHealth", "частично", LUA, '"Health":', "Дробные значения и +Inf логически поддержаны; NaN/-Inf намеренно отклонены. Lifecycle и порядок всех Roblox-событий не доказаны.", (PTEST, NTEST, NETTEST))
rule("Humanoid", "WalkSpeed JumpPower JumpHeight UseJumpPower HipHeight AutoRotate", "частично", LUA, '"WalkSpeed":', "Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены.", (PTEST, NTEST, NETTEST))
rule("Humanoid", "MaxSlopeAngle", "частично", LUA, '"MaxSlopeAngle":', "Getter/setter и numeric guard; 89° cap отличается от наблюдённого верхнего Roblox 89.9°. Полная slope-матрица отсутствует.", (NTEST,))
rule("Humanoid", "MoveDirection RootPart", "частично", LUA, '"MoveDirection":', "Живое направление/HRP прокси R6; не полная многотельная assembly/R15.", (PTEST, NTEST))
rule("Humanoid", "WalkToPoint WalkToPart", "частично", LUA, "func MoveTo(", "MoveTo обновляет поля и moving target. Прямое присваивание этих полей не равно запуску цели.", (PTEST, NTEST, NETTEST))
rule("Humanoid", "Jump PlatformStand Sit", "частично", LUA, '"Jump":', "Есть физический маршрут и state bridge; не все состояния, owner-side ограничения и восстановление измерены.", (PTEST, NTEST))
rule("Humanoid", "SeatPart", "частично", LUA, '"PrimaryPart", "Part0"', "Occupancy reference и Seated bridge; NPC seat motor и все случаи удаления/движения ещё требуют проверки.", (PTEST, SEATTEST))
rule("Humanoid", "BreakJointsOnDeath", "частично", PLAYER, 'get_meta("BreakJointsOnDeath"', "Сохраняет/разбирает собственный visual rig; не Roblox физическое разрывание всех Motor6D.", (PTEST,))
rule("Humanoid", "AutoJumpEnabled RequiresNeck", "нет", LUA, '"AutoJumpEnabled", "BreakJointsOnDeath", "RequiresNeck"', "Свойство хранится/читается; полноценный mobile AutoJump или смерть от отсутствующего Neck не реализованы этим маршрутом.", ())
rule("Humanoid", "RigType", "частично", LUA, '"RigType":', "R6/R15 label читается; R15 риг и масштабирование не реализованы этим getter.", (NTEST,))
rule("Humanoid", "CameraOffset", "нет", LUA, '"CameraOffset":', "Getter читает metadata; player camera не использует Humanoid.CameraOffset, поэтому сохранение значения не camera parity.", ())
rule("Humanoid", "FloorMaterial", "частично", PLAYER, 'set_meta("FloorMaterial"', "Player floor sampling есть; NPC, enum-представление и смена материалов имеют неполное покрытие.", ())
rule("Humanoid", "DisplayName", "частично", NPC, 'get_meta("DisplayName"', "NPC health label читает имя; все Roblox name-display distance/occlusion правила не восстановлены.", ())
rule("Humanoid", "Move MoveTo", "частично", LUA, "func _humanoid_move(", "Реальное движение, camera-relative и moving-part цель/timeout; разные player/NPC motors и нет полной obstacle/autojump parity.", (PTEST, NTEST, NETTEST))
rule("Humanoid", "ChangeState GetState SetStateEnabled GetStateEnabled", "частично", LUA, "func ChangeState(", "17 state IDs и live motor; специальные состояния не все имеют физическое Roblox-поведение. Baseline возвращает числовые enum.", (PTEST, NTEST, NETTEST))
rule("Humanoid", "TakeDamage", "частично", LUA, "func TakeDamage(", "Есть fractional damage/heal, hierarchy ForceField, death; NaN/Inf damage guard и весь lifecycle отличаются.", (NTEST,))
rule("Humanoid", "EquipTool UnequipTools", "частично", LUA, "func EquipTool(", "Реальный inventory reparent/event маршрут; полные Tool constraints/right grip/replication не доказаны.", (TOOLTEST,))
rule("Humanoid", "LoadAnimation", "нет", LUA, "func LoadAnimation(", "Возвращает новый BobuxAnimationTrack без загрузки AnimationId/ключей и без связи с ригом: заглушка, не проигрывание.", ())
rule("Humanoid", "StateChanged StateEnabledChanged Jumping FreeFalling FallingDown GettingUp PlatformStanding Ragdoll Strafing Seated", "частично", LUA, "func notify_humanoid_state_changed(", "Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены.", (PTEST, NTEST))
rule("Humanoid", "Running Climbing Swimming MoveToFinished HealthChanged Died", "частично", PLAYER, "_sync_humanoid_runtime_properties", "Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта.", (PTEST, NTEST, NETTEST))

rule("Animator", "LoadAnimation", "нет", LUA, "func LoadAnimation(", "Общий метод возвращает bookkeeping track; ключи, rig playback, priority, fade и репликация отсутствуют.")
rule("AnimationController", "LoadAnimation", "нет", LUA, "func LoadAnimation(", "Тот же bookkeeping stub; не Animator/AnimationController pipeline.")
rule("AnimationTrack", "IsPlaying Looped Speed WeightCurrent Play Stop AdjustSpeed AdjustWeight Stopped", "частично", LUA, "class BobuxAnimationTrack", "Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression.")
rule("AnimationTrack", "KeyframeReached", "нет", LUA, "class BobuxAnimationTrack", "Сигнал существует, но track не читает keyframes и не производит событие по анимации.")
rule("Animation", "AnimationId", "нет", LUA, "func LoadAnimation(", "Сохраняемое metadata значение не используется LoadAnimation для проигрывания.")

for cls in ("Seat", "VehicleSeat"):
    rule(cls, "Disabled Occupant Sit", "частично", PLAYER, "func _enter_seat(", "Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены.", (PHYSTEST, SEATTEST))
rule("VehicleSeat", "Throttle ThrottleFloat Steer SteerFloat", "частично", PLAYER, "func _set_seat_input(", "Ввод живого игрока и RPC; физика vehicle motor собственная, точная wheel/torque parity не установлена.", (PHYSTEST,))
rule("VehicleSeat", "MaxSpeed Torque TurnSpeed AreHingesDetected", "частично", "addons/roblox_runtime/roblox_legacy_motor.gd", "MaxSpeed", "Читаются legacy vehicle/hinge адаптером; силовая модель и типы assemblies ограничены.", (PHYSTEST,))
rule("VehicleSeat", "HeadsUpDisplay", "нет", LUA, "func _get_impl(", "Metadata не рисует штатный Roblox VehicleSeat HUD.")

rule("Tool", "Grip GripPos GripForward GripUp", "частично", LUA, "func _position_equipped_tool(", "Собственная установка Handle позы; не полноценный RightGrip/Motor6D animation pipeline.", ())
rule("Tool", "ToolTip", "частично", "addons/roblox_runtime/roblox_inventory_controller.gd", "button.tooltip_text", "Inventory UI читает tooltip; desktop/mobile parity и все live property обновления не доказаны.", (TOOLTEST,))
rule("Tool", "Activated Equipped Unequipped", "частично", LUA, "func activate_local_tool(", "События inventory маршрута; не весь Enabled/RequiresHandle/drop/deactivation контракт.", (TOOLTEST,))
rule("Tool", "Activate Deactivate", "нет", LUA, "func activate_local_tool(", "Native inventory helper есть, публичных Tool:Activate/Deactivate методов нет.")
rule("Tool", "Enabled ManualActivationOnly RequiresHandle CanBeDropped", "нет", LUA, "func activate_local_tool(", "Defaults/metadata есть, но activation helper не применяет все эти gates/правила Tool.")
rule("Accoutrement", "AttachmentPoint", "нет", LUA, "func _get_impl(", "Нет generic Accoutrement attachment motor; cosmetic Bobux avatar mechanism отдельный.")

rule("SpawnLocation", "Enabled Neutral TeamColor", "частично", LUA, "func refresh_local_team_spawns(", "Выбор team/neutral spawn и RespawnLocation; без доказанного Roblox spawn распределения/lifecycle.", ())
rule("SpawnLocation", "Duration AllowTeamChangeOnTouch", "нет", LUA, "func refresh_local_team_spawns(", "Нет spawn ForceField duration и team-change-on-touch маршрута в этой реализации.")
rule("ForceField", "Visible", "нет", LUA, "func humanoid_is_forcefield_protected(", "Иерархическая защита Humanoid есть, но Visible не создаёт штатный ForceField эффект.", ())

rule("Player", "Character", "частично", LUA, "func bind_local_player_character(", "Привязка/CharacterAdded работают; setter/новая модель/CharacterRemoving/номер жизни ещё неполны.", (PTEST, NETTEST))
rule("Player", "UserId DisplayName", "частично", LUA, "func bind_network_player_character(", "Bobux account identity metadata; UserId может быть string, не Roblox numeric identity.")
rule("Player", "Team TeamColor Neutral RespawnLocation", "частично", LUA, "func refresh_local_team_spawns(", "Команды и team spawn selection; неполная история lifecycle и TeamColor тип/enum.", (SPAWNTEST,))
rule("Player", "LoadCharacter", "частично", LUA, "func LoadCharacter(", "Вызов существующего respawn, возможно повторное использование Godot Node; не полный Roblox LoadCharacter lifecycle.", (PTEST,))
rule("Player", "GetMouse", "частично", LUA, "func GetMouse(", "Собственный raycast/события mouse; не все Mouse/InputObject APIs, icon и lock modes.", (INPUTTEST,))
rule("Player", "CharacterAdded", "частично", LUA, "func bind_network_player_character(", "Реальный producer при bind; повторный respawn той же модели и порядок appearance events не доказаны.", (NETTEST,))
rule("Player", "CharacterRemoving CharacterAppearanceLoaded", "нет", LUA, "func unbind_local_player_character(", "Публичное имя/сигнал не доказывает producer: unbind сейчас отправляет PlayerRemoving, не полный character lifecycle.")
rule("Players", "LocalPlayer GetPlayers GetPlayerFromCharacter PlayerAdded PlayerRemoving", "частично", LUA, "func GetPlayers(", "Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты.", (NETTEST,))
rule("Players", "CharacterAutoLoads RespawnTime", "нет", LUA, "func bind_local_player_character(", "Metadata не управляет автоматической загрузкой/временем респауна Roblox.")

rule("Workspace", "Gravity", "частично", LUA, 'prop_str == "Gravity"', "Live gravity для player/NPC/parts; discrete Godot solver и finite guard, не полный Roblox world solver.", (PTEST, NTEST))
rule("Workspace", "CurrentCamera", "частично", LUA, '"CurrentCamera":', "Получается камера активного viewport; setter/все режимы камеры не восстановлены.", ())
rule("WorldRoot", "Raycast FindPartOnRay FindPartOnRayWithIgnoreList FindPartsInRegion3 GetPartBoundsInBox GetPartBoundsInRadius BulkMoveTo", "частично", LUA, "func Raycast(", "Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы.", ("tools/validate_halloween_spatial_contract.gd", "tools/validate_render_batches.gd"))
rule("WorldRoot", "GetPartsInPart", "нет", LUA, "func GetPartBoundsInBox(", "GetPartBoundsInBox не реализует exact GetPartsInPart; публичного метода нет.")

rule("BasePart", "Position Rotation CFrame Size Anchored CanCollide CanQuery CanTouch Transparency Color BrickColor", "частично", LUA, "func _get_impl(", "Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox.", (PHYSTEST,))
rule("BasePart", "Velocity AssemblyLinearVelocity RotVelocity AssemblyAngularVelocity", "частично", LUA, '"RotVelocity", "AssemblyAngularVelocity"', "Запись преобразуется/передаётся физике. Angular getter не полностью отражает live assembly; R6 proxy не multipart assembly.", (PTEST, PHYSTEST))
rule("BasePart", "Touched", "частично", "addons/roblox_runtime/roblox_part_physics.gd", "func _deliver_touch(", "Contact/sweep producer и CanTouch; Humanoid parts/очередь/TouchEnded не полная Roblox contact semantics.", (PHYSTEST,))
rule("BasePart", "TouchEnded", "нет", "addons/roblox_runtime/roblox_part_physics.gd", "func _on_body_entered(", "Есть public signal fallback, но part physics не имеет body-exit producer.")
rule("BasePart", "GetMass ApplyImpulse GetConnectedParts BreakJoints MakeJoints", "частично", LUA, "func GetMass(", "Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox.", (PHYSTEST,))
rule("BasePart", "AssemblyMass Massless CustomPhysicalProperties CurrentPhysicalProperties CollisionGroup Friction Elasticity", "нет", "addons/roblox_runtime/roblox_part_physics.gd", "func refresh_properties(", "Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver.")
rule("Part", "Shape", "частично", LUA, '"Shape":', "Box/Sphere/Cylinder mesh adapter; геометрия/масса/shape properties Roblox не полностью доказаны.")

rule("JointInstance", "Part0 Part1 C0 C1 Enabled", "частично", "addons/roblox_runtime/roblox_joint_runtime.gd", "func _refresh(", "Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives.", (PHYSTEST,))
rule("Motor6D", "Transform", "частично", "addons/roblox_runtime/roblox_joint_runtime.gd", 'wrapper._get(&"Transform")', "Frame участвует при refresh joint; не Animator batched Transform/приоритеты/физический персонаж.")
rule("Motor", "DesiredAngle MaxVelocity", "нет", "addons/roblox_runtime/roblox_joint_runtime.gd", "func _refresh(", "Joint refresh не применяет Motor drive/DesiredAngle/MaxVelocity; отдельные Bobux vehicle motors не полный Motor API.")
rule("WeldConstraint", "Part0 Part1 Enabled", "частично", "addons/roblox_runtime/roblox_joint_runtime.gd", "func _refresh(", "Реальный rigid joint mesh-to-mesh; не constraints всей character assembly и не полный Roblox solver.", (PHYSTEST,))
rule("Attachment", "CFrame Position Rotation", "частично", LUA, '"CFrame":', "Node3D общий маршрут использует global coordinates; Attachment local-space semantics отличаются.")

rule("UserInputService", "KeyboardEnabled MouseEnabled TouchEnabled IsKeyDown GetMouseLocation InputBegan InputChanged InputEnded JumpRequest", "частично", LUA, "func _input(", "Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements.", (INPUTTEST,))
rule("ContextActionService", "BindAction BindActionAtPriority UnbindAction", "нет", LUA, "func _input(", "Service-node создаётся, но action callback/priority/sink/touch button implementation отсутствует.")
rule("Camera", "CFrame CameraType", "частично", LUA, '"CameraType":', "Scriptable/Custom transform ownership есть; остальные CameraType представлены не полностью и отсутствуют полноценные camera motors.", ("tools/validate_lua_cframe_runtime.gd",))
rule("Camera", "ScreenPointToRay ViewportPointToRay", "частично", LUA, "func ScreenPointToRay(", "Godot camera ray преобразуется; screen inset отличается, ViewportPointToRay пока alias ScreenPointToRay.")

# Shared inherited contracts are declared once and linked from each class.
rule("Object", "ClassName", "частично", LUA, '"ClassName", "className"', "Из roblox_class metadata; не независимая immutable schema/type model.")
rule("Object", "IsA", "частично", LUA, "func IsA(", "Классы сопоставляются ограниченными списками, не всей official inheritance database.")
rule("Instance", "Name Parent", "частично", LUA, "func _set_impl(", "Name/parenting hooks; Parent=nil и ancestry timing требуют полного контракта.")
rule("Instance", "FindFirstChild FindFirstChildOfClass FindFirstChildWhichIsA FindFirstAncestor FindFirstAncestorOfClass FindFirstAncestorWhichIsA GetChildren GetDescendants GetFullName IsDescendantOf IsAncestorOf ClearAllChildren Destroy Clone WaitForChild", "частично", LUA, "func FindFirstChild(", "Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны.")
rule("Instance", "GetAttribute SetAttribute GetAttributes GetAttributeChangedSignal GetPropertyChangedSignal", "частично", LUA, "func GetAttribute(", "Metadata attributes/signals; не все allowed types/serialization/replication/read-only constraints Roblox.", (PTEST, NTEST))
rule("Instance", "ChildAdded ChildRemoved AncestryChanged Destroying Changed", "частично", LUA, "func _init(n: Node)", "Есть native node event bridge; полные Roblox ancestor/order/timing/generic Changed контракты не доказаны.")
rule("Instance", "DescendantAdded DescendantRemoving", "нет", LUA, "func _get_impl(", "Сигналы доступны через generic event fallback; рекурсивный Roblox producer не подтверждён.")
rule("PVInstance", "GetPivot PivotTo", "частично", LUA, "func GetPivot(", "Node3D/Model transform routines; PrimaryPart/pivot и physics assemblies имеют ограничения.", ("tools/validate_lua_service_compatibility.gd",))
rule("Model", "PrimaryPart WorldPivot GetModelCFrame GetModelSize SetPrimaryPartCFrame MoveTo BreakJoints MakeJoints", "частично", LUA, "func PivotTo(", "Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен.", (PHYSTEST,))


def reference(path: str, anchor: str) -> dict:
    text = (ROOT / path).read_text(encoding="utf-8")
    index = text.find(anchor)
    return {"path": path, "line": text.count("\n", 0, index) + 1 if index >= 0 else None, "anchor": anchor, "file_sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest()}


def signature(member: dict) -> str:
    name = member_name(member["name"])
    if member["kind"] == "properties":
        return name + ": " + str(member["type"])
    params = ", ".join(str(p.get("name", "?")) + ":" + str(p.get("type", "?")) for p in member["parameters"])
    returns = ",".join(str(p.get("type", "?")) for p in member["returns"])
    return name + "(" + params + ")" + (" → " + returns if returns else "")


def priority(cls: str, name: str, usage: list) -> str:
    if name in {"Health", "TakeDamage", "Died", "Character", "CharacterAdded", "CharacterRemoving", "LoadCharacter", "Move", "MoveTo", "GetState", "ChangeState", "Climbing", "SensorMode", "SensedPart", "HitFrame", "HitNormal", "LoadAnimation", "Play", "Stop", "CFrame", "AssemblyLinearVelocity", "Part0", "Part1", "Attachment0", "Attachment1", "BindAction", "CreatePath", "ComputeAsync", "Blocked"}:
        return "критично"
    if usage or cls in {"Humanoid", "HumanoidDescription", "Animator", "AnimationTrack", "Attachment", "ControllerPartSensor", "ControllerManager"}:
        return "высоко"
    return "средне"


def main() -> None:
    api = json.loads((OUT / "creator_docs_api.json").read_text(encoding="utf-8"))
    corpus = json.loads((OUT / "map_api_candidates.json").read_text(encoding="utf-8"))
    enums = json.loads((OUT / "map_enum_candidates.json").read_text(encoding="utf-8"))
    refs: dict[str, dict] = {}
    tests: dict[str, str] = {}
    rows = []
    classes = list(dict.fromkeys(BASE_CLASSES + sorted(set(api["classes"]) - set(BASE_CLASSES))))
    for cls in classes:
        for member in api["classes"][cls]["members"]:
            name = member_name(member["name"])
            route = RULES.get((cls, name))
            if route is None:
                profile = "CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует." if cls.startswith("Controller") or cls in {"GroundController", "AirController", "ClimbController", "SwimController", "SensorBase"} else "Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка."
                if cls == "HumanoidDescription":
                    profile = "Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline."
                if cls.endswith("Constraint") or cls in {"VectorForce", "LinearVelocity", "AngularVelocity", "Torque", "LineForce", "AlignPosition", "AlignOrientation"}:
                    profile = "Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику."
                route = {"status": "нет", "path": LUA, "anchor": "func _get_impl(", "limitation": profile, "tests": []}
            evidence = reference(route["path"], route["anchor"])
            if evidence["line"] is None:
                raise ValueError(f"Stale manual evidence anchor for {cls}.{name}: {evidence}")
            key = json.dumps(evidence, sort_keys=True)
            if key not in refs:
                refs[key] = {"id": f"E{len(refs)+1:02}", **evidence}
            test_ids = []
            for path in route["tests"]:
                if path not in tests:
                    tests[path] = f"T{len(tests)+1:02}"
                test_ids.append(tests[path])
            usage = corpus["member_candidates"].get(name, [])
            restrictions = []
            if member.get("security") and isinstance(member["security"], dict):
                restrictions = [f"{k}:{v}" for k, v in member["security"].items() if str(v) != "None"]
            restrictions += [t for t in member["tags"] if t in {"Deprecated", "ReadOnly", "NotScriptable", "Hidden", "NotReplicated"}]
            rows.append({"class": cls, "member": name, "kind": member["kind"], "signature": signature(member), "status": route["status"], "evidence_id": refs[key]["id"], "map_lexical_candidates": usage, "automatic_test_ids": test_ids, "priority": priority(cls, name, usage), "limitation": route["limitation"], "official_restrictions": restrictions})
    result = {"schema_version": 1, "audit_utc": datetime.now(timezone.utc).isoformat(), "creator_docs_commit": api["commit"], "baseline_only": True, "support_policy": "Full only after relevant contract tests. Partial only explicitly reviewed real route. Names, generic metadata, Node fallback, stubs never imply behavior. No full public contracts asserted in this audit.", "evidence": list(refs.values()), "tests": [{"id": id_, "path": path, "file_sha256": hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), "execution_this_audit": "NOT_RUN", "scope": "Limited assertions reviewed; presence is not fresh PASS or full API coverage"} for path, id_ in tests.items()], "members": rows}
    # A structural audit PASS is not a gameplay/API PASS. Reject omissions and
    # broken evidence before emitting the machine-readable decisions.
    assert len(rows) == sum(len(c["members"]) for c in api["classes"].values())
    assert len({(r["class"], r["kind"], r["member"]) for r in rows}) == len(rows)
    assert all(r["status"] in {"нет", "частично", "полностью"} for r in rows)
    assert len(corpus["maps"]) == 21
    assert all(m["original_matches_historical"] for m in corpus["maps"])
    (OUT / "api_matrix.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    write_doc(api, corpus, enums, result, classes)
    print(json.dumps({"classes": len(classes), "members": len(rows), "statuses": dict(Counter(x["status"] for x in rows)), "missing_anchors": [e for e in refs.values() if e['line'] is None]}, ensure_ascii=False))


def write_doc(api: dict, corpus: dict, enums: dict, result: dict, classes: list[str]) -> None:
    counts = Counter(row["status"] for row in result["members"])
    out = ["# Roblox Character: матрица публичного API Bobux", "", "Аудит Phase A1, 14 октября 2026. Это снимок исходной реализации, а не утверждение о полной совместимости и не итог фаз A–J. Production код и карты этим аудитом не менялись; Godot/Studio gameplay в этой подзадаче не запускались.", "", "## Происхождение и критерии", "", f"Список публичных членов получен из официальных YAML [Roblox/creator-docs](https://github.com/Roblox/creator-docs/tree/{api['commit']}/content/en-us/reference/engine/classes), commit `{api['commit']}`. Снимок включает **{len(classes)} классов и {len(result['members'])} собственных публичных свойств/методов/событий/колбэков**. Унаследованные члены перечислены один раз в разделе класса-родителя; цепочка `inherits` приведена для каждого класса. В snapshot сохранены signatures, ограничения security/tags и SHA-256 каждого YAML; описания/исходный код Roblox не копируются.", "", "Включены члены с `security=None` хотя бы для чтения или записи; запрещённая другая сторона доступа и deprecated/read-only/not-scriptable tags видны в строке. Nonpublic API не считается отсутствующей поддержкой: отдельно сохранён в JSON для проверки границ. Camera, Path и промежуточные классы добавлены для полноты связанных контрактов; физические Constraints/силы включены из descendant-цепочки официального Constraint.", "", "- **Полностью** — проверен соответствующий публичный контракт во всех заявленных профилях. Таких утверждений в этом первичном аудите нет.", "- **Частично** — вручную прослежена реальная работающая часть маршрута в исходниках; ограничения указаны. Не устанавливается автоматически по присутствию имени.", "- **Нет** — отсутствует dedicated функциональный маршрут в изученном wrapper/runtime либо есть только metadata/заглушка/доступное имя сигнала без нужного producer. Это не отрицание сохранности экземпляра в importer/Explorer.", "", f"Исходный снимок: частично `{counts['частично']}`, нет `{counts['нет']}`, полностью `0`. Количество имён не показатель качества. Source evidence имеет хеш файла: параллельные последующие изменения A3 могут сделать baseline устаревшим. После реализации матрицу нужно обновлять с новыми assertions и данными, а не менять статус на основании новой функции.", "", "## Тестовые карты: реальная доступность", "", "Найдены все **21 оригинальных файла** в `C:/Users/Pavel/Downloads`; текущие SHA-256 совпали со снимком 3 октября. Одна пара Plane Wars имеет одинаковое содержимое: 21 файлов, **20 уникальных оригиналов**. Не запускались все карты: исторически сцена строилась у 20, ограниченный playtest был у четырёх. Эти прежние результаты не являются новыми gameplay PASS.", "", f"Статически прочитаны **{sum(m['sources_scanned'] for m in corpus['maps'])} Source-полей**, из них **{sum(m['nonempty_sources'] for m in corpus['maps'])} непустых**, в сохранённых corpus JSON. Всего script instances по historical manifest: {sum(m['historical_scripts_total'] for m in corpus['maps'])}. У карты №18 двенадцать объектов не имеют Source-поля в JSON; ещё два Source пусты. Их API usage **BLOCKED**, отсутствие совпадений не означает отсутствия кода/поведения. JSON не пересоздавались и исходники карт не исправлялись.", "", "В столбце «Карты» указаны **лексические кандидаты** `.Member`/`:Member`: номера файлов и число script Source с хотя бы одним совпадением. Receiver type/исполнение не доказаны. Например `.Play` может принадлежать Sound, `.Priority` — пользовательской таблице. Динамические обращения/алиасы и внешние `require(assetId)` не покрыты. `—` означает отсутствие прямого совпадения в доступном Source, а не доказанное «никогда не используется». Поэтому точное typed usage для всей матрицы ещё требует Luau AST/data-flow и runtime instrumentation.", "", "| № | Оригинальный файл | Script instances | Source поля / непустые | SHA original сейчас |", "|---:|---|---:|---:|---|" ]
    for m in corpus["maps"]:
        out.append(f"| {m['index']:02} | {m['file']} | {m['historical_scripts_total']} | {m['sources_scanned']} / {m['nonempty_sources']} | {'совпадает' if m.get('original_matches_historical') else 'BLOCKED/изменён'} |")
    out += ["", "## Существенные ограничения исходной архитектуры", "", "- `Humanoid` игрока и NPC уже имеют live motor/state/event маршруты, но player/NPC физические контроллеры различаются. 35 реальных R6 сценариев от 13 октября сохранены в [эмпирическом отчёте](ROBLOX_HUMANOID_EMPIRICAL_RU.md): 48 PASS, 5 FAIL Landed, 18 SKIP. Это не измерения ordinary-Part climbing, R15 или CCL.", "- `LoadAnimation` возвращает `BobuxAnimationTrack` без AnimationId/KeyframeSequence playback. Изменение `IsPlaying` не движение суставов. Нет полноценного Animator priority/fade/blend/markers pipeline.", "- `HumanoidDescription`/R15 scaling остаются metadata; `RigType=R15` не создаёт R15.", "- CCL классы и sensor `Ladder`/`ClassicLadder` не подключены к публичному Luau/physical pipeline. Собственные GDScript `GroundController`/`ClimbController` не являются реализацией одноимённых Roblox API.", "- Joint runtime создаёт жёсткий Generic6DOF для ограниченного mesh-to-mesh пути. Это не BallSocket/Hinge/Spring ragdoll, не Attachment-based constraints и не полноценный Motor6D animation rig.", "- `CharacterRemoving`/`CharacterAppearanceLoaded` отсутствуют как полный lifecycle producer; повторное использование одного Node при respawn требует номера жизни либо создания новой модели.", "- `ContextActionService` service-node и `PathfindingService` имя не дают BindAction/CreatePath/Path вычислений. Physics mass/friction/CustomPhysicalProperties/collision groups также не выводятся из сохранения metadata.", "", "## Enum/камера: baseline и corpus риск", "", "Baseline enum proxy — числовые ID, без полного Name/Value/EnumType/typeof/tostring/GetEnumItems. CameraType содержит Fixed…Scriptable, но отсутствует Orbital. CameraMode нельзя смешивать с CameraType. Исправление EnumItem должно иметь отдельный профиль/миграцию: native EnumItem не равен числу. Это раздел исходного снимка; новая A3 реализация проверяется отдельно.", "", "| Regex категория | Кандидатов | Карты |", "|---|---:|---|" ]
    for name, item in enums["categories"].items():
        out.append(f"| `{name}` | {item['matches']} | {','.join(f'{i:02}' for i in item['maps']) or '—'} |")
    out += ["", "В Underground War вручную подтверждён прямой numeric CameraType setter (4/5, Follow/Custom), Source ordinal 2 и 3. `.Priority=10` в ACF, Source ordinal 625 — `Playlist.Priority` внутри `Module:AddPlaylist`, пользовательская таблица, **ложный кандидат AnimationTrack исключён**. Подтверждённых numeric AnimationPriority assignments здесь нет. Нулевые GetState()==number/ChangeState(number) regex результаты не покрывают сравнения через переменные. 118 обращений к Enum.*.*.{Name,Value,EnumType} и 39 GetEnumItems/GetEnums кандидатов делают отсутствие EnumItem существенным.", "", "Официальные значения ключевых доменов в том же pinned snapshot:", ""]
    for name, domain in api["enums"].items():
        out.append(f"- [{name}]({domain['source_url']}): " + ", ".join(f"`{item['name']}={item['value']}`" for item in domain["items"]) + ".")
    out += ["", "CoreGuiType baseline после Chat имеет неверную нумерацию: official All=4, EmotesMenu=5, SelfView=6, Captures=7, AvatarSwitcher=8, ExperienceShop=9. Legacy consumers нельзя silently переключать без соответствующего профиля и тестов.", "", "## Как читать evidence и автоматические тесты", "", "E — вручную просмотренный участок текущего production исходника (точный хеш в JSON). T — существующий автоматический тест с ограниченными assertions, прочитанными при аудите. **NOT_RUN здесь:** никакие свежие PASS по наличию файла не присваиваются. В частности старый inventory harness имел autoload/preload проблему в прежнем прогоне; его существование не исправляет этот BLOCKED.", "", "| Evidence | Файл / строка |", "|---|---|" ]
    for e in result["evidence"]:
        suffix = f"#L{e['line']}" if e["line"] else ""
        out.append(f"| {e['id']} | [{e['path']}:{e['line'] or '?'}](../{e['path']}{suffix}) — `{e['anchor'].replace('|', '&#124;')}` |")
    out += ["", "| Тест | Существующий файл | Выполнение здесь |", "|---|---|---|"]
    for test in result["tests"]:
        out.append(f"| {test['id']} | [{test['path']}](../{test['path']}) | NOT_RUN; scoped assertions, не полный контракт |")
    out += ["", "## Полная таблица собственных публичных членов", "", "Унаследованные строки искать по цепочке `inherits`; общий Instance API не дублируется 69 раз. Колбэки сохранены так же, как методы/события; если в YAML класса публичных callbacks нет, вымышленные не добавлены.", ""]
    for cls in classes:
        source = api["classes"][cls]
        rows = [r for r in result["members"] if r["class"] == cls]
        out += [f"### {cls}", "", f"[Официальный YAML]({source['source_url']}). inherits: `{', '.join(source['inherits']) or '—'}`. Профиль: {'CCL отдельно от классического Humanoid' if cls.startswith('Controller') or cls in {'GroundController', 'AirController', 'ClimbController', 'SwimController', 'SensorBase'} else 'общий/классический (R15 не подразумевается)' }.", "", "| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |", "|---|---|---|---|---|---|---|"]
        for r in rows:
            kind = {"properties":"P", "methods":"M", "events":"E", "callbacks":"C"}[r["kind"]]
            usage = ",".join(f"{x['map_index']:02}:{x['source_count']}" for x in r["map_lexical_candidates"]) or "—"
            restrict = " [" + ", ".join(r["official_restrictions"]) + "]" if r["official_restrictions"] else ""
            out.append(f"| {kind} `{r['signature'].replace('|','&#124;')}`{restrict} | {r['status']} | {r['evidence_id']} | {usage} | {','.join(r['automatic_test_ids']) or 'нет'} | {r['priority']} | {r['limitation'].replace('|','&#124;')} |")
        if not rows:
            out.append("| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |")
        out.append("")
    out += ["## Воспроизводимость", "", "`python tools/character_parity/inventory_character_api.py` читает pinned schema и без запуска Luau/игры обновляет static corpus candidates. `--refresh-docs` явно обновляет официальный snapshot. `python tools/character_parity/render_api_matrix.py` строит эту таблицу и JSON из ручного route registry; после production изменений registry следует рецензировать.", "", "Артефакты: [official schema](../tests/roblox_humanoid/phase_a/creator_docs_api.json), [typed audit decisions и source hashes](../tests/roblox_humanoid/phase_a/api_matrix.json), [corpus/Source hashes](../tests/roblox_humanoid/phase_a/map_api_candidates.json), [enum regex candidates](../tests/roblox_humanoid/phase_a/map_enum_candidates.json). Все regex ограничения записаны в артефактах. Factual API перечисления не заменяют обязательные собственные измерения/holdout/видео и фазовые регрессии.", ""]
    (ROOT / "docs/ROBLOX_CHARACTER_API_MATRIX_RU.md").write_text("\n".join(out), encoding="utf-8")


if __name__ == "__main__":
    main()
