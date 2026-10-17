# Независимый review архитектуры и EnumItem prototype

14 октября 2026. READ-ONLY review production/native. Godot/Studio в этой подзадаче не запускались. Проанализированы `docs/ROBLOX_CHARACTER_ARCHITECTURE_RU.md`, четыре `addons/roblox_runtime/enums/*.gd`, isolated validator и Luau contract draft. Existing prototype report — 18 PASS / 0 FAIL в Luau 0.719, **только isolated kernel**, не production A3.

## Что подтверждается чтением

- Архитектура честно помечена IN_PROGRESS и не объявляет A3, ordinary-Part climbing, R15, lifecycle или backward network compatibility готовыми. Реальные прежние 35 сценариев и 48/5/18 не переименованы в новые holdout.
- Lua-facing `__index` перечисляет только разрешённые EnumItem/EnumType/Enums члены. `__newindex` возвращает LuaError. Не обнаружено прямого Lua доступа к `add_item`, `_value`, `get_script` или `_types` через эти маршруты. Общая native `mt_Object` защищена `__metatable`.
- Canonical lookup и equality используют идентичность объектов; `_get_enum_items` возвращает копию массива, сохраняя canonical items. Одного `__eq` для table keys недостаточно, текущий native identity cache необходим для повторного push того же объекта.
- `coerce` проверяет тип, expected EnumType и canonical lookup конкретного registry. Другая enum область и fake table не считаются корректным EnumItem. Числовая проверка отсеивает fractional/NaN/Inf.
- В prototype профиль хранится в разных `PropertyFixture` и нет записи общего current_profile в Node/BobuxInstance. При этом тест использует **два разных fixture**, поэтому не доказывает production isolation для одного общего BobuxInstance/BobuxEvent.

## Официальные определения

Проверено автоматически чтением GDScript definition pairs против pinned `Roblox/creator-docs` commit `031b2f91d3d47274c255f3ed5691c29f792c181d`:

| Домен | Name/Value pairs | Статический результат | Runtime порядок |
|---|---:|---|---|
| HumanoidStateType | 17 | STATIC_MATCH, нет пропусков/лишних/дубликатов | NOT_RUN здесь |
| CameraType | 8 | STATIC_MATCH, включая Orbital=7 | NOT_RUN здесь |
| AnimationPriority | 7 | STATIC_MATCH, Core=1000 | NOT_RUN здесь |
| Material | 45 | STATIC_MATCH | NOT_RUN здесь |

Пары перечислены в той же последовательности, что YAML, но YAML sequence не является новым live Studio измерением `GetEnumItems` order. Прототип этого не заявляет. Артефакт: [schema review JSON](enumitem_prototype_schema_review.json). Воспроизведение: `python tools/character_parity/review_enum_schema.py`.

По [official Enum datatype](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/datatypes/Enum.yaml) публичны GetEnumItems, FromName и FromValue. [EnumItem datatype](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/datatypes/EnumItem.yaml) задаёт Name, Value, EnumType. [Enums datatype](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/datatypes/Enums.yaml) описывает GetEnums как список всех доступных enum областей; длина 4 допустима только для явно ограниченного prototype scope.

## Findings перед production A3

### P1 — строгое numeric input не подтверждено как Roblox

`validate_enumitem_prototype.gd` требует ошибки при `fixture.State=5`. Это проверка собственной политики registry, а не измеренное поведение настоящего setter/метода. `EnumItem ~= number` не доказывает запрет numeric input: setter может принимать число и возвращать EnumItem. В corpus действительно есть `game.Workspace.CurrentCamera.CameraType = 4` и `=5` в Underground War, Source ordinal 2/3. Числа — **Follow/Custom**, не 5/6. ACF `Playlist.Priority=10` исключён как ложный AnimationTrack кандидат.

Перед production binding необходима live Studio input-матрица для CameraType/Material/Shape/RigType/AnimationPriority и ChangeState/SetStateEnabled/GetStateEnabled: canonical item, same-number other domain, integer, fractional, string name, nil, NaN/Inf, неверная arity. Возможное сохранение numeric setter coercion следует отделить от legacy numeric getter/equality. Результат пока NOT_VERIFIED; не делать несовместимое ужесточение на основании isolated assert.

### P2 — неизвестный профиль молча превращается в numeric

`roblox_enum_registry.gd:to_boundary` возвращает scalar для любой строки кроме `RobloxParity.EnumItem`. Опечатка/неизвестный profile не вызывает отказ и может незаметно менять внешний тип. До production нужен выбор из известных значений и отрицательный тест. Это пока не ломает production, поскольку registry туда не подключён.

### P2 — время жизни canonical EnumType

`roblox_enum_item.gd` хранит WeakRef к EnumType. Если retained item переживёт registry/root, `EnumType` станет nil, а tostring выдаст `<expired>`. В isolated fixture registry удерживается fixture и typeof callable, поэтому этот край не проверен. Production должен гарантировать engine-wide registry lifetime либо иной безопасный ownership без цикла. Нужны проверки teardown одного runtime, второй живой VM, retained callback/module value, GC/re-push/table-key identity.

### P2 — существующий pointer-key native cache

`native/luau_bridge/src/luaState.cpp` identity cache keyed raw `Object*`, слабые значения, для всех Object. Это **уже присутствовало в baseline**, не новая A3 регрессия. Enum RefCounted при живом userdata не освобождается, но обычный Node может быть уничтожен, пока userdata удерживается Lua таблицей. Новый Node с переиспользованным address может получить старое userdata. Требуется уникальный Godot ObjectID ключ либо проверка identity/liveness cached Variant; allocator-reuse/Node teardown regression. Это потенциальный риск по чтению, не воспроизведённый crash.

### P2 — неподключённые реальные VM boundaries

Production `LuaScriptEngine` по-прежнему push-ит `_build_enum_proxy()`; основной typeof shim классифицирует generic userdata как userdata/Instance/CFrame, а не EnumItem. Isolated validator заменяет typeof своей closure и тестирует PropertyFixture; реальные BobuxInstance getters/методы/события не использованы. `_pack_value` ImportedPlaceNetwork превращает неизвестный Object, в том числе prototype EnumItem, в nil; typed enum payload/decoder пока отсутствуют.

Обязательны реальные GetState/RigType/CameraType/Material/AnimationPriority round trips, InputObject/params/TweenInfo и callback conversion на **принимающей VM**, а не поле shared wrapper. Нужны две VM на одном BobuxInstance и одном BobuxEvent, coroutine/require/callback/Bindable/Remote routes, typed domain validation и trailing nil/arity preservation. Module value, полученный из другой VM, должен приходить как canonical item общего registry.

### P2 — namespace/domain coverage

Прототип содержит четыре области. Из восьми pinned областей отсутствуют HumanoidRigType, CameraMode, CoreGuiType, SensorMode. Luau contract draft дополнительно использует PartType, RaycastFilterType, EasingStyle/EasingDirection; production numeric namespace также содержит NormalId, BulkMoveMode, UserInputType/UserInputState, KeyCode и другие домены. Отсутствующие домены нельзя заменить fabricated values или объявить полное GetEnums. CoreGuiType исправления должны применяться к явному parity profile; legacy профиль не переключать silently.

## Непокрытые предикаты ядра

- `rawequal` canonical items/type/root, repeated FromName/FromValue/GetEnumItems/native push после GC; два parity runtime и teardown одного.
- Unknown fields/functions на всех трёх userdata, запись новых полей, `getmetatable`/`setmetatable`/raw operations и сохранение readonly после callback/network возврата.
- Точный error/nil/arity/coercion договор FromName/FromValue и receiver semantics dot/colon по native reference. `str(raw)` для FromName сейчас может принимать типы шире документированного string.
- `tostring(Enum)` отдельно: prototype возвращает `Enum`, но namespace/typeof сами по себе не доказывают native string. Тип и enum item строковые форматы проверены только isolated assertions, не новой native predicate матрицей.
- Каноничность другого registry с теми же Name/Value и запрет fake item; builder sealing после init для защиты canonical registry от случайных GDScript изменений.

## Обязательные ворота A3 completion

1. Native reference predicates/settings/version/date/raw telemetry и domain snapshots; ошибочные/недоступные probes отдельно FAIL/BLOCKED.
2. Production binding с явным VM profile, verified coercion и неизменённым default legacy profile.
3. Реальные property, method, event, input/params/TweenInfo, module/Bindable/Remote boundaries; 2+ VM shared objects и lifecycle/GC checks.
4. Scoped legacy regressions и imported map scripts, включая CameraType=4/5; существование 21 corpus файла не gameplay PASS. Dynamic aliases/12 missing Source остаются ограничением.
5. Backward network negotiation/две версии, если typed enum payload выходит в сетевой контракт; публичный сервер до этого не менять.
6. Updated API matrix/runtime assertions + protected-file/baseline preservation. Только затем A3 COMPLETE; isolated 18 PASS означает работающий kernel prototype.

Production/native/архитектурный документ этим review не изменялись. Findings требуют подтверждения/исправления по указанным границам, без объявления всех механик сломанными.
