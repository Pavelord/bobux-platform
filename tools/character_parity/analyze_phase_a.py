"""Derive Phase A inventory from immutable own Studio markers; never calibrate.

The metadata probe's numeric regexp captures prefixes of expressions. Retain
these candidates as lexical observations, never as evaluated script constants.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "CHARACTER_EXPERIMENT_JSON "
DEFAULT_STEM = ROOT / "tests/roblox_humanoid/phase_a/2026-10-14-studio-run02"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    """Stable, type-preserving comparison; EnumItem never equals its number."""
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def distribution(values):
    counts = Counter(canonical(v) for v in values)
    result = {"n": len(values), "unique": [
        {"value": json.loads(value), "count": count}
        for value, count in sorted(counts.items())], "stable": len(counts) == 1}
    if values and all(type(v) in (int, float) and math.isfinite(v) for v in values):
        result.update(min=min(values), max=max(values), median=statistics.median(values))
    return result


def flatten(value, prefix=""):
    result = {}
    for key, item in sorted(value.items()):
        name = f"{prefix}.{key}" if prefix else key
        # Enum identity and absence/error tags are indivisible typed values.
        if isinstance(item, dict) and not any(k in item for k in ("type", "status", "is_nil")):
            result.update(flatten(item, name))
        else:
            result[name] = item
    return result


def field_distributions(records, key):
    values = defaultdict(list)
    for record in records:
        for field, value in flatten(record.get(key, {})).items():
            values[field].append(value)
    return {field: distribution(items) for field, items in sorted(values.items())}


def parse_raw(path, observed):
    if digest(path) != observed["raw_sha256"]:
        raise ValueError("raw SHA differs from validated observed report")
    if observed.get("status") != "OBSERVED" or observed.get("parser_issues"):
        raise ValueError("input report is incomplete or has parser issues")
    rows = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line.startswith(PREFIX):
            raise ValueError("non-probe line in immutable raw")
        rows.append(json.loads(line[len(PREFIX):]))
    if len(rows) != observed["raw_records"]:
        raise ValueError("raw record count differs from observed report")
    for index, row in enumerate(rows, 1):
        if row.get("seq") != index or row.get("run_id") != observed["run_id"]:
            raise ValueError("sequence or run identity mismatch")
    if rows[-1].get("kind") != "run_result":
        raise ValueError("raw does not end with run_result")
    return rows


def source_ref(relative, fragment):
    path = ROOT / relative
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if fragment in line:
            return {"file": relative, "line": line_no, "sha256": digest(path)}
    raise ValueError(f"expected static audit anchor missing: {relative}: {fragment}")


def parse_config():
    path = ROOT / "scripts/player/humanoid/humanoid_config.tres"
    # Only primitive assignments in the values block; no arbitrary code eval.
    text = path.read_text(encoding="utf-8").split("values = {", 1)[1].split("\n}", 1)[0]
    result = {}
    for name, literal in re.findall(r'^"([^"]+)": ([^\n,]+),?$', text, re.M):
        try:
            result[name] = json.loads(literal)
        except ValueError:
            pass
    return result


def bobux_static_comparison(groups):
    config = parse_config()
    native = groups["fresh_humanoid"]["properties"]
    mapping = {"WalkSpeed": "WalkSpeed", "JumpPower": "JumpPower", "JumpHeight": "Humanoid.JumpHeight",
               "MaxSlopeAngle": "MaxSlopeAngle", "HipHeight": "HipHeight"}
    entries = []
    for prop, key in mapping.items():
        summary = native[prop]
        value = summary["unique"][0]["value"] if summary["stable"] else None
        matches = type(value) in (int, float) and type(config[key]) in (int, float) and math.isclose(value, config[key], abs_tol=1e-6)
        entries.append({"property": prop, "native_observed": value, "bobux_value": config[key],
                        "comparison": "STATIC_VALUE_MATCH" if matches else "STATIC_VALUE_MISMATCH",
                        "functional_parity": "NOT_TESTED", "source": source_ref(
                            "scripts/player/humanoid/humanoid_config.tres", f'"{key}":')})
    return {"status": "READ_ONLY_SOURCE_AUDIT", "value_comparisons": entries,
            "gaps": [
                {"finding": "Editor R6 factory explicit HipHeight2 differs from fresh/native R6 HipHeight0",
                 "status": "STATIC_VALUE_MISMATCH", "source": source_ref("addons/roblox_studio/roblox_character_factory.gd", '"HipHeight": 2.0')},
                {"finding": "RigType getter returns numeric0/1, native getter returns EnumItem",
                 "status": "STATIC_TYPE_MISMATCH", "source": source_ref("autoload/lua_script_engine.gd", 'return {"R6": 0, "R15": 1}.get(rig, 0)')},
                {"finding": "CameraOffset getter stores metadata; application to actual camera still requires Phase H test",
                 "status": "FUNCTIONAL_NOT_TESTED", "source": source_ref("autoload/lua_script_engine.gd", '"CameraOffset":')},
                {"finding": "BobuxAnimationTrack is bookkeeping object; no native length/time/mixer behavior proven",
                 "status": "PARTIAL", "source": source_ref("autoload/lua_script_engine.gd", 'class BobuxAnimationTrack extends RefCounted:')},
                {"finding": "StarterPlayer binding clones script containers; ordinary property inheritance must be measured separately",
                 "status": "BLOCKED_NATIVE_REFERENCE", "source": source_ref("autoload/lua_script_engine.gd", 'var starter_character_scripts := starter_player.get_node_or_null("StarterCharacterScripts")')}
            ]}


def analyze_a2(rows):
    server = [r["server"] for r in rows if r.get("kind") == "server_record"]
    buckets = {"fresh_humanoid": [r for r in server if r.get("kind") == "a2_fresh_humanoid"]}
    for rig in ("R6", "R15"):
        buckets[f"official_model_{rig}"] = [r for r in server if r.get("kind") == "a2_official_model" and r.get("rig") == rig]
        for profile in ("default", "modified"):
            buckets[f"template_spawn_{rig}_{profile}"] = [r for r in rows if r.get("kind") == "a2_native_getters" and r.get("rig") == rig and r.get("profile") == profile]
    groups = {}
    for key, records in buckets.items():
        if len(records) != 5:
            raise ValueError(f"expected five records for {key}, received {len(records)}")
        groups[key] = {"n": len(records), "repeat_kind": "same_spawn_repeated_getters" if key.startswith("template_spawn") else "independent_created_instances",
                       "source_sequence_namespace": "client_raw_seq" if key.startswith("template_spawn") else "server_seq_inside_server_record",
                       "source_seqs": [r.get("seq", r.get("server_seq")) for r in records],
                       "properties": field_distributions(records, "properties")}
        if records[0].get("parts"):
            parts = defaultdict(list)
            for record in records:
                for part in record.get("parts", []):
                    # Animated/world transforms are telemetry, not default settings.
                    fields = {name: value for name, value in part.items() if name not in
                              ("CFrame", "root_relative_cf", "AssemblyCenterOfMass", "name")}
                    parts[part["name"]].append({"properties": fields})
            groups[key]["part_default_properties"] = {name: field_distributions(samples, "properties")
                                                       for name, samples in sorted(parts.items())}
        if key.startswith("template_spawn"):
            for field in ("starter_player", "player_properties"):
                groups[key][field] = field_distributions(records, field)
    pairs = {"CharacterWalkSpeed": "WalkSpeed", "CharacterJumpPower": "JumpPower", "CharacterJumpHeight": "JumpHeight",
             "CharacterUseJumpPower": "UseJumpPower", "CharacterMaxSlopeAngle": "MaxSlopeAngle", "CharacterBreakJointsOnDeath": "BreakJointsOnDeath"}
    inheritance = []
    for rig in ("R6", "R15"):
        a, b = groups[f"template_spawn_{rig}_default"], groups[f"template_spawn_{rig}_modified"]
        for starter, prop in pairs.items():
            inheritance.append({"rig": rig, "starter_property": starter, "humanoid_property": prop,
                                "starter_default": a["starter_player"][starter], "starter_modified": b["starter_player"][starter],
                                "humanoid_default": a["properties"][prop], "humanoid_modified": b["properties"][prop],
                                "observed_humanoid_changed": a["properties"][prop]["unique"] != b["properties"][prop]["unique"],
                                "scope": "custom StarterCharacter template; already joined Player; one spawn per profile"})
    return {"status": "OBSERVED", "groups": groups, "template_inheritance": inheritance,
            "ordinary_spawn_inheritance": {"status": "BLOCKED", "reason": "Custom StarterCharacter supplies Humanoid values; StarterPlayer modified after Player joined. Need independent ordinary spawn/no template and new Player admission cases."}}


def category(path):
    if path.endswith(".R6.Animate"): return "Animate_R6"
    if path.endswith(".R15.Animate"): return "Animate_R15"
    if path.startswith("Workspace.") and path.endswith(".Animate"): return "Animate_current_duplicate_R15"
    if path.endswith(".Health"): return "Health"
    if ".RbxCharacterSounds" in path: return "CharacterSounds"
    if ".CameraModule" in path: return "Camera"
    if ".ControlModule" in path: return "Controls"
    if ".PlayerModule" in path: return "PlayerModule_and_common"
    return "Other"


def analyze_a4(metadata, rows):
    strict = metadata.get("schema") == 2 and metadata.get("extractor_version") == "standalone_single_line_literals_v2"
    inventory = []
    for row in metadata["scripts"]:
        exact = strict and row.get("literal_extraction", {}).get("status") == "EXACT_LITERAL_DECLARATIONS_ONLY"
        inventory.append({"path": row["path"], "class": row["class"], "category": category(row["path"]),
                          "status": row["status"], "source_length": row.get("source_length"),
                          "provenance": "STANDARD_SCRIPT", "literal_extraction_status": "EXACT_LOCAL_INITIALIZERS_NOT_BEHAVIOR" if exact else "PROVISIONAL_LEXICAL_PREFIX_ONLY",
                          "numeric_bool_candidates": row.get("literal_constants", {}),
                          "literal_extraction": row.get("literal_extraction"),
                          "dependencies": row.get("dependencies", []), "enum_identifiers": row.get("enum_identifiers", []),
                          "method_identifiers": row.get("public_method_identifiers", []), "signal_identifiers": row.get("signal_identifiers", [])})
    observations = []
    for row in rows:
        if row["kind"] == "a4_animation_observation":
            observations.append({"rig": row["rig"], "profile": row["profile"], "seq": row["seq"],
                                 "Motor6D_count": len(row["joints"]), "tracks": row["tracks"],
                                 "quality_flags": ["Length0 track observed; loading/completion unresolved"] if any(t.get("Length") == 0 for t in row["tracks"]) else []})
    literal_complete = strict and all(r["literal_extraction_status"] == "EXACT_LOCAL_INITIALIZERS_NOT_BEHAVIOR" for r in inventory)
    semantic = {"status": "OBSERVED_EXACT_LOCAL_INITIALIZERS", "reason": "Strict standalone literal declarations with repeated names excluded. Not runtime behavior, immutable constants, physical thresholds, sound settings or full animation configuration."} if literal_complete else {
        "status": "BLOCKED", "reason": "Probe regex captures numeric prefix of expressions, overwrites scoped identifiers and includes initialization values. Numeric values are not evaluated STANDARD_SCRIPT constants. Strict expression-aware recapture required."}
    return {"status": "OBSERVED_METADATA_EXACT_INITIALIZERS" if literal_complete else "OBSERVED_METADATA_PROVISIONAL", "rows": len(inventory), "categories": dict(Counter(r["category"] for r in inventory)),
            "script_statuses": dict(Counter(r["status"] for r in inventory)), "inventory": inventory,
            "animation_observations": observations, "semantic_constants": semantic,
            "runtime_configuration_behavior": "NOT_MEASURED",
            "identifier_limitations": "Lexical identifier presence is not proof of an executed API, public API ownership, coverage, rate, sound settings or controller behavior. Legacy connect signals not captured by Connect-only regex."}


def fmt(value):
    if isinstance(value, dict) and value.get("type") == "EnumItem":
        return value["tostring"]
    return json.dumps(value, ensure_ascii=False)


def representative(group, field):
    d = group["properties"][field]
    return fmt(d["unique"][0]["value"]) if d["stable"] else "VARIABLE"


def render_a2(data):
    groups = data["a2"]["groups"]
    lines = ["# Phase A2: измеренные defaults персонажа", "", f"Studio `{data['studio_version']}`, run `{data['run_id']}`. Статус **OBSERVED**, функциональная совместимость Bobux **NOT_TESTED**.", "",
             f"Проверено {data['raw_records']} исходных записей, SHA-256 `{data['raw_sha256']}`. Анализ не меняет raw и не подбирает параметры.", "",
             "5 fresh Humanoid и по5 независимо созданных official-description моделей R6/R15. Четыре template spawn дают по5 getter samples одного спавна, а не5 независимых спавнов. Это разные категории повторения.", "",
             "| Поле | Fresh Humanoid | Модель R6 | Модель R15 |", "|---|---|---|---|"]
    for field in ("WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "HipHeight", "MaxSlopeAngle", "Health", "MaxHealth", "AutoRotate", "AutoJumpEnabled", "BreakJointsOnDeath", "RequiresNeck", "EvaluateStateMachine", "AutomaticScalingEnabled", "CameraOffset", "RigType", "NameDisplayDistance", "HealthDisplayDistance", "DisplayDistanceType", "NameOcclusion", "HealthDisplayType"):
        lines.append("| " + field + " | " + " | ".join(representative(groups[k], field) for k in ("fresh_humanoid", "official_model_R6", "official_model_R15")) + " |")
    lines += ["", "Во всех пяти fresh экземплярах все17 публичных GetStateEnabled возвращали true, включая None. Это наблюдение getter, оно не доказывает, что каждый state достижим или разрешён для ChangeState.", "",
              "**BLOCKED: наследование обычного spawn.** Изменённые StarterPlayer values23/61/9/false/37/false наблюдаются на StarterPlayer, но Humanoid из template остаётся16/50/7.199999809265137/true/89/true. Player camera zoom и AutoJump также остались первоначальными. Нельзя на основании этого отключать наследование: template и момент изменения после входа Player смешивают причины. Нужны новые Player и обычный spawn без StarterCharacter.", "",
              "Bobux: статическое совпадение пяти config values в JSON не означает проверенное поведение. Editor R6 factory хранит HipHeight2 при измеренном R6 HipHeight0; RigType возвращается числом; CameraOffset требует реального camera test; AnimationTrack пока объект учёта. Производственный код здесь не менялся.", "",
              "R15 модель имеет16 BasePart, measured HipHeight2.192423105239868 относится именно к пустому HumanoidDescription этой Studio, а не к любому R15. Snapshot Motor6D_count0 и треки Length0 требуют проверки skeleton/загрузки до фазы D/G.", "",
              f"Детальные распределения, seq и ссылки на текущие исходники: `{data['output_json']}`."]
    return "\n".join(lines) + "\n"


def render_a4(data):
    a4 = data["a4"]
    strict = a4["semantic_constants"]["status"] == "OBSERVED_EXACT_LOCAL_INITIALIZERS"
    lines = ["# ROBLOX_ANIMATE_CONFIG — предварительный measured inventory", "", f"Studio `{data['studio_version']}`, run `{data['run_id']}`, 14 октября 2026. **{a4['status']}**, Phase A4 не закрыта.", "",
             "Чтение публичных стандартных скриптов выполнено внутри официальной Studio Command Bar. В репозитории сохранены только идентификаторы, числовые/boolean кандидаты и длина Source. Текст функций, Source snippets, animation assets и keyframes не перенесены.", "",
             f"Метаданные: {a4['rows']} rows, {a4['script_statuses']}. Текущий R15 Animate дублирует cached R15; это не третий независимый script implementation.", "",
             ("Strict v2 принимает только полные standalone local initializer literals и исключает повторяющиеся names. STANDARD_SCRIPT относится к точным литералам и происхождению, не к доказанному runtime behavior. Обычные expression значения не вычисляются; старые prefix evidence сохранены отдельно." if strict else
              "**BLOCKED semantic constants:** regexp исходного probe извлекает начальное число выражения, а не результат. Например значение 2 у TAU может быть префиксом 2×π; значение 1 у REGEN_RATE нельзя считать 1/сек. Имена разных scopes могут перезаписываться. Эти факты сохранены как lexical candidates, не применяются к конфигурации и не получают статус проверенных STANDARD_SCRIPT constants."), "",
             "| Script inventory | Source length | Числовые/boolean кандидаты |", "|---|---|---|"]
    for row in a4["inventory"]:
        if row["category"] in ("Animate_R6", "Animate_R15", "Health", "CharacterSounds"):
            lines.append(f"| {row['category']}: {row['path']} | {row['source_length']} | {fmt(row['numeric_bool_candidates'])} |")
    lines += ["", "Ключи jumpAnimDuration, fallTransitionTime, toolTransitionTime, EMOTE_TRANSITION_TIME, normalizedWalkSpeed и normalizedRunSpeed приведены в таблице только при наличии в этой capture. Даже полный RHS literal требует отдельной проверки его назначения; static initializer не доказывает переходы и скорости анимаций.", "",
              "R6 identifiers включают LoadAnimation, AdjustSpeed, SetDesiredAngle; R15 дополнительно AdjustWeight, GetVelocityAtPosition и GetPropertyChangedSignal. Оба упоминают Priority Core/Idle/Action. Sound script упоминает StateChanged и11 Humanoid states. Такая lexical inventory не доказывает вызов, его условия, sound volume/playback settings или полноценный Animator.", "",
              "PlayerModule: отдельно Camera и Controls. В derived JSON сохранён полный набор dependencies/methods/signals для каждого row, включая BaseCamera, ClassicCamera, ZoomController, Popper, Keyboard, Gamepad, DynamicThumbstick, TouchJump, ClickToMove. Инициализационные переменные не являются настройками физического мотора.", "",
              "Сырые animation observations содержат timing/weight/priority aggregates: R6 snapshots имеют6 Motor6D; R15 snapshots0 и дополнительные Length0 tracks. Это BLOCKED для утверждений о полном R15 skeleton/загрузке, а не доказательство отсутствия skeleton у Roblox.", "",
              "Следующий шаг: strict metadata recapture, независимый обычный spawn, затем собственные анимационные аналоги без переноса оригинальных keyframes. Текущие настройки Bobux не изменены.", "",
              f"Факты и provenance: `{data['output_json']}`; оригинальный metadata SHA-256 `{data['metadata_sha256']}`."]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, default=DEFAULT_STEM.with_suffix(".raw.log"))
    parser.add_argument("--observed", type=Path, default=DEFAULT_STEM.parent / (DEFAULT_STEM.name + "-verified.observed.json"))
    parser.add_argument("--metadata", type=Path, default=DEFAULT_STEM.with_suffix(".metadata.json"))
    parser.add_argument("--output", type=Path, default=DEFAULT_STEM.with_suffix(".analysis.json"))
    parser.add_argument("--a2-report", type=Path, default=ROOT / "docs/ROBLOX_CHARACTER_DEFAULTS_OBSERVED_RU.md")
    parser.add_argument("--a4-report", type=Path, default=ROOT / "docs/ROBLOX_ANIMATE_CONFIG_RU.md")
    args = parser.parse_args()
    observed = json.loads(args.observed.read_text(encoding="utf-8-sig"))
    rows = parse_raw(args.raw, observed)
    metadata = json.loads(args.metadata.read_text(encoding="utf-8-sig"))
    if metadata["run_id"] != observed["run_id"] or metadata["studio_version"] != observed["studio_version"]:
        raise ValueError("metadata and raw refer to different runs/Studio versions")
    data = {"schema": 1, "analysis_status": "OBSERVED_NOT_PARITY_PASS", "run_id": observed["run_id"],
            "studio_version": observed["studio_version"], "raw_records": observed["raw_records"], "raw_sha256": digest(args.raw),
            "metadata_sha256": digest(args.metadata), "output_json": str(args.output.relative_to(ROOT)).replace("\\", "/"),
            "a2": analyze_a2(rows), "a4": analyze_a4(metadata, rows)}
    data["bobux_static_comparison"] = bobux_static_comparison(data["a2"]["groups"])
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.a2_report.write_text(render_a2(data), encoding="utf-8")
    args.a4_report.write_text(render_a4(data), encoding="utf-8")
    print(json.dumps({"status": data["analysis_status"], "groups": len(data["a2"]["groups"]), "metadata_rows": data["a4"]["rows"],
                      "ordinary_spawn": data["a2"]["ordinary_spawn_inheritance"]["status"],
                      "semantic_constants": data["a4"]["semantic_constants"]["status"], "output": str(args.output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
