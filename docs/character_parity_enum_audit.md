# A3: аудит EnumItem и план совместимой миграции

Дата: 14 октября 2026. Состояние: A3 OPEN; production изучается без изменений, изолированный прототип выполняется отдельно. Защищены `studio.gd`, `main.gd`, `rbxl_runtime_importer.gd`, `map_format.gd`. Исходные измерения 13 октября и SHA-256 из `ROBLOX_HUMANOID_EMPIRICAL_RU.md` сохраняются.

## Что существует

Production VM — Luau 0.719, commit `54426c4217740440c25d51fd579a4746028551c3`, с адаптером LuaAPI в `native/luau_bridge`. Имена LuaAPI/LuaCoroutine — совместимый интерфейс существующего Godot проекта; это не Lua 5.4 вместо Luau.

`autoload/lua_script_engine.gd::_build_enum_proxy` создаёт Dictionary-of-Dictionary с числами. Он публикуется в legacy `run_script` и в `_push_runtime_bindings`; ModuleScript получает те же runtime bindings. Namespace сейчас включает 16 типов: CameraType, Material, PartType, NormalId, EasingStyle, EasingDirection, BulkMoveMode, RaycastFilterType, CoreGuiType, UserInputType, UserInputState, KeyCode, HumanoidStateType, HumanoidRigType, ThumbnailType, ThumbnailSize. Число типов нельзя считать показателем совместимости.

Дополнительные таблицы: `material_cache.gd::NAMED_MATERIAL_ENUMS`, `state_machine.gd::STATES`, `roblox_input_bridge.gd::key_codes`. Материалы поддерживают как настоящие Roblox Value (Plastic=256), так и прежние локальные ordinal 0–17 в отдельной rendering таблице. Их нельзя внезапно переинтерпретировать как новые Roblox EnumItems.

`_native_lua_type_setup` реализует собственный typeof для Vector2, Vector3, Color3, Instance, CFrame. Для будущего EnumItem сегодня получится userdata. `tostring` generic userdata вызывает `LuaDefaultObjectMetatable::__tostring`, затем GDScript `__tostring` объекта. `__eq` аналогично передаётся объекту. Dictionary превращается в обычную Lua table: произвольная table c Name/Value сама по себе не становится Roblox EnumItem.

## Native bridge и идентичность

`native/luau_bridge/src/luaState.cpp::pushVariant`:

- Array/Dictionary рекурсивно превращаются в Lua tables.
- Object создаёт userdata с Godot Variant и `mt_Object`.
- Registry `bobux_object_identity` с weak values intern-ит живые userdata по Godot Object pointer. Это уже решает равенство и ключи table для одного Object внутри VM.
- `getVariant` возвращает Object из userdata; EnumItem не теряет тип на GDScript boundary.
- Для разных VM получается отдельный userdata одного registry Object; этот userdata нельзя переносить как LuaFunctionRef между независимыми VM.

`metatables.cpp::createObjectMetatable` выбирает `obj.lua_metatable` либо `LuaAPI.object_metatable`. `__index/__newindex/__tostring/__eq` получают LuaAPI, поэтому native layer уже может различать runtime. Стандартный metatable умеет вызывать объектные GDScript metamethods. Read-only требует `__newindex` возвращать LuaError; простое `_set=false` не гарантирует Lua error.

Достаточен собственный bounded registry RefCounted Enums/Enum/EnumItem. Никакого изменения bytecode/VM, копирования Roblox source или native engine implementation не требуется. Registry должен выдавать одни singleton objects для `(EnumType, Name)`; item.Value не является уникальным ключом между enum types. EnumType содержит items; обратная ссылка item→EnumType вычисляется registry или WeakRef, чтобы не создавать RefCounted cycle. `GetEnumItems()` выдаёт новую Array singleton items, не изменяемый внутренний массив. Порядок и alias канонизация подтверждаются Studio отдельно; нельзя сортировать произвольно и назвать это измерением.

### Lifetime policy прототипа

Weak parent безопасен только при явном owner. `registry.attach_to_vm(lua)` хранит сильную ссылку registry в metadata LuaAPI (`bobux_enum_registry_owner`); это owner VM lifetime, не Lua global, поэтому `Enum=nil` и Lua GC его не уничтожают. Registry не хранит ссылку на VM. Направление владения: LuaAPI→registry→Enums/Enum→EnumItem, EnumItem→Enum через WeakRef. Retained native states сохраняют owner до настоящего LuaAPI teardown. `LuaAPI::~LuaAPI` закрывает native state до уничтожения Object metadata, поэтому registry ещё жив во время уничтожения userdata.

В production registry дополнительно должен принадлежать Luau engine session; освобождать его только после disconnect callbacks и закрытия всех active/retained/quarantined states. Godot код, удерживающий EnumItem после завершения VM, обязан удерживать registry owner/lease тоже. Для постоянной metadata, сетевого payload, export и cache использовать scalar ID/typed tag, не отсоединённый EnumItem Object. Это ограничение lifetime engine/session, не циклическая сильная обратная ссылка item→type.

Новый тест удерживает два parity VM одновременно, удаляет namespace globals, отпускает внешний registry owner и запускает полный native GC через `LuaAPI.configure_gc(GC_COLLECT)`. Затем проверяет EnumType/table keys, закрывает первый VM, повторяет GC во втором и после последнего teardown требует исчезновения registry/type/item из WeakRefs. `typeof` helper больше не захватывает `Callable(registry, "kind")`: такая closure сама удерживала бы owner и скрывала дефект lease. Classifier теста знает только Script identity и не владеет registry. Отрицательный контроль запускает третью изолированную VM без metadata lease: после удаления Enum global и registry owner полный GC должен освободить registry/type, хотя отдельный item userdata ещё жив; это доказывает чувствительность проверки owner, а не Roblox internal architecture. Эти ownership/GC/teardown проверки получили **PASS в r03**. Existing native pointer identity cache потенциально требует отдельного lifecycle audit в фазе F; C++ в A3 prototype не меняется.

## Собственное наблюдение в Studio: run02

Официальная Studio **0.742.0.7421053**, 14 октября 2026, run `56d7b7d5-beac-4f26-ba3e-d771a14ece51`. Собственный `a3_enum_probe` находится в seq=2 файла `tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.raw.log`. SHA-256 полного immutable raw файла: `36226a4f7dde505e224e5fbccefb26c8584ffd4ef752a02f9d5e9a771243237b`. Это наблюдения настоящего Roblox API, не копия engine/standard-script source.

| Проверенное значение | Native наблюдение | Coverage |
|---|---|---|
| `type(Enum)` / `typeof(Enum)` / `tostring(Enum)` | `userdata` / `Enums` / `Enums` | root |
| `type(Enum.Domain)` / `typeof` / `tostring` | `userdata` / `Enum` / имя домена без `Enum.` | 6 доменов |
| `type(item)` / `typeof` / `tostring` | `userdata` / `EnumItem` / `Enum.Domain.Item` | 83 items |
| `Name`, `Value`, `EnumType`; повторный lookup | совпадают с `GetEnumItems`; parent singleton identity true | 83 items |
| `item == item.Value` | false | 83 items |
| запись `Name` / `Value` | ошибка `Name/Value is not a valid member of EnumItem` | 83 items |
| запись отсутствующего member типа/root | ошибка `<member> is not a valid member of Enum/Enums` | 6 типов + root |

Порядок `GetEnumItems` измерен целиком для HumanoidStateType (17), AnimationPriority (7), CameraType (8), Material (45), SensorMode (4), SensorUpdateType (2). Prototype definitions используют именно эти последовательности; статическое сравнение ordered pairs с raw observation уже выполнено для всех 83 items. Pinned official API schema и supplement теперь дополнительно подтверждают все шесть доменов: **83 pair STATIC_MATCH**. Schema-проверка и выполненная native observation — разные критерии.

`GetEnums` всего Roblox и его порядок, aliases, `FromName`/`FromValue`, чтение неизвестных members, запись существующего member типа, `EnumType` readonly и coercion property/method input **не измерены в этом probe**. Они исследованы отдельным probe ниже. Исходное `item ~= number` не доказывает, что API setter отказывается принимать number.

Улучшенный validator читает immutable raw reference, проверяет SHA-256/run/seq и сравнивает реальные userdata внутри VM с каждым наблюдённым item и exact readonly error text. Checks с `provenance=MEASURED` означают сравнение с наблюдением; прочие checks остаются `ENGINE_APPROXIMATION` и проверяют только kernel/isolation/lifetime. Ошибка digest прекращает native comparison с FAIL, не обновляет эталон автоматически.

## Дополнительный native coercion probe: 543 наблюдения

Официальная Studio **0.742.0.7421053**, run `c475020d-1687-4cb5-9b53-2ecbe4d5a2f7`. Источник `tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-coercion-run01.raw.json`, SHA-256 `bf6f00d2dd18a509353347852a76aec14ae5778e81e23eb2773923961e154e19`; parser status OBSERVED, 543 rows, 0 BLOCKED. Это conversion/error/getter observations, **не Bobux parity PASS и не physics calibration**.

- `Enum:FromValue` принимает только number. Измеренные положительные дробные values 0.5 и 256.5 возвращают item с 0/256; прежний отказ prototype для любой дроби был неверен. NaN/±Inf/unknown numeric дают nil. EnumItem/string/nil/boolean/table дают `invalid argument #2 to 'FromValue' (number expected, got <type>)`; отсутствующий аргумент отличается `missing argument #2...`. Extra args игнорируются. `FromName` аналогичен, но требует string; invalid/full/numeric string возвращает nil, wrong types дают error.
- Root `GetEnums` вернул **648 типов**, имена в alphabetical sequence. Prototype возвращает alphabetical subset из реализованных типов; это явный PARTIAL, не якобы полный GetEnums. `GetEnums` допускает extra args, отвергает wrong receiver.
- RaycastFilterType `GetEnumItems` содержит Exclude=0 и Include=1. Dot aliases Blacklist/Whitelist возвращают canonical Name Exclude/Include. Эти два items и aliases добавлены в prototype (всего 7 доменов / 85 canonical items). Alias `FromName('Blacklist')`/`FromName('Whitelist')` ещё NOT_OBSERVED; его поведение не входит в PASS.
- Unknown **read** отличается от readonly **write**: `X is not a valid member of "Enum.Domain.Item"`, `"Enum.Domain"` или `"Enum"`. Readonly writes используют EnumItem/Enum/Enums без quoted path. `EnumType`, existing type/root members действительно readonly.
- Сравнение EnumItem с number/cross-domain item false; `tonumber(item)` nil. Arithmetic, unary minus, concat, `<` и `<=` дают errors. Generic native Object `__lt/__le` возвращают bool, поэтому GDScript return LuaError не может их корректно пробросить. Изолированный VM shim перехватывает только EnumItem operands до generic native compare; production/native source не меняется. Enum methods возвращаются как Lua closures над tuple binding, сохраняя missing/explicit nil/extra argument arity.

Setter conversion нужно реализовывать **по boundary**, а не через один глобальный strict coerce:

| Native API | Принимает с наблюдаемым canonical getter | Отвергает |
|---|---|---|
| Camera.CameraType, Part.Material, Humanoid.RigType, AnimationTrack.Priority | matching EnumItem, valid number, bare Name, numeric string, положительную fractional number (6.5→6 и т.п.) | full `Enum.Domain.Item` string, wrong domain, unknown number/name, nil/bool/table, NaN/±Inf |
| Humanoid:SetStateEnabled | matching item/number/bare Name/измеренная fraction реально изменяют нужный enabled state | wrong domain, unknown number, nil/bool/table/NaN/Inf; отсутствующий bool |
| Humanoid:GetStateEnabled / ChangeState | conversion pcall/returns наблюдаются отдельно | conversion success не доказывает требуемый state transition |

`SetStateEnabled('Running', false)` выключает Running в fresh и live fixtures. Full enum string, numeric string `'8'` и unknown string получают pcall=true, но ни один из 17 перечисленных states не выключается. Их нельзя молча превращать в canonical Running и объявлять parity. `ChangeState(nil/missing)` pcall=true, а Get/SetStateEnabled при nil/missing дают error. Bool input строка `'false'` и number 0 для SetStateEnabled в этих cases выключают Running: нельзя использовать Lua truthiness как bool cast.

Live fixture — отдельный **anchored rig**, не настоящий player character. After-heartbeat GetState=FallingDown даже при valid item/number input; это влияние fixture/physics, а не доказательство, что conversion выбирает FallingDown. Fresh unparented Humanoid остаётся None. Фаза B обязана отдельно проверить физически живой humanoid и события.

Validator сравнивает все измеренные FromName/FromValue/extra arity cases, readonly/read/operator/alias cases и alphabetical covered subset с этим immutable JSON. Динамический `CommandBar:<line>:` caller prefix снимается при сравнении, **semantic error text остаётся точным**. Properties/Humanoid production methods пока не реализованы: их native observations включены в design, но strict PropertyFixture policy остаётся ENGINE_APPROXIMATION.

Дополнительные шесть native cases затем закрыли отрицательные fractions, FromName aliases и другой Enum receiver; см. ниже. Большие числовые conversion boundaries и function/Vector3 input conversion остаются NOT_OBSERVED.

### Native supplement: ещё шесть наблюдений

Run `06e5b50d-dbad-4187-bf85-12d34a204bc8`, Studio 0.742.0.7421053. Сохранены только anchored собственные `ENUM_EXTRA_JSON`/`ENUM_EXTRA_DONE` markers, strict UTF-8, seq 1–6 и completion records=6; 0 integrity issues. `tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-extra-run01.raw.log` SHA-256 `eac64122882d9dd8676acb467dc02cd2d7bfdc1d07f2ab6e1906ab51c07f4264`; structured `.raw.json` SHA-256 `bf0cfd177f200ded653b4423d5acdbd99e346aa24cd582599c9bc4f9c1f56306`.

| Case | Native result |
|---|---|
| HumanoidStateType.FromValue(-0.5) | FallingDown=0: truncation toward zero |
| HumanoidStateType.FromValue(-1.5) | nil |
| RaycastFilterType.FromName(Blacklist/Whitelist) | canonical Exclude=0 / Include=1 |
| Enum.Material.FromValue(Enum.CameraType, 6) | CameraType.Scriptable=6 |
| Enum.Material.GetEnumItems(Enum.CameraType) | 8 CameraType items in its measured order |

Enum method receiver определяет реальный домен, а не enum, из которого извлекли method. Prototype tuple binding выполняет dispatch по проверенному receiver; эти cases отдельно сравниваются с immutable supplement в r03.

## Обязательные домены на API boundaries

| Boundary | Domain | Текущее представление / опасность |
|---|---|---|
| Humanoid:GetState | HumanoidStateType | int из body/metadata |
| ChangeState, GetStateEnabled, SetStateEnabled input | HumanoidStateType | прямой int(value), wrong-domain не различается |
| StateChanged args 1,2 | HumanoidStateType | `_fire_existing_runtime_event` отправляет два int |
| StateEnabledChanged arg 1 | HumanoidStateType | BobuxInstance вызывает Fire(state,enabled) |
| Humanoid.RigType | HumanoidRigType | string R6/R15 или int getter |
| Humanoid.FloorMaterial | Material | специального getter нет; требуется measured/default contact source, имя не равно реализации |
| Camera.CameraType | CameraType | meta value; setter int 6/5 или string; getter default сейчас не гарантирован |
| Player.CameraMode | CameraMode | enum отсутствует; generic stored property |
| BasePart.Material | Material | generic stored property; setter/appearance adapters должны получать прежнее numeric/string representation |
| RaycastResult.Material, legacy FindPartOnRay arg 4 | Material | `_perform_roblox_raycast` возвращает meta material string |
| Terrain Fill* input, ReadVoxels output | Material | material_cache принимает number/string/Dictionary, Object пока теряется |
| Part.Shape | PartType | сравнение str(value); Ball enum tostring пока не принят; Cylinder строкой принят |
| Top/Bottom/Left/Right/Front/BackSurface | SurfaceType | material_cache legacy strings/Value dict; namespace отсутствует |
| Decal/Texture.Face | NormalId | generic property downstream adapters |
| RaycastParams.FilterType, OverlapParams.FilterType | RaycastFilterType | typed int; `params.FilterType==1` |
| TweenInfo.EasingStyle/EasingDirection | EasingStyle/EasingDirection | Dictionary; Play использует int(info.*) |
| Tween.PlaybackState / Completed arg1 | PlaybackState | typed int 0/2/3/4/5; enum namespace отсутствует |
| AnimationTrack.Priority | AnimationPriority | namespace и полноценное Priority/mixing отсутствуют |
| InputObject.KeyCode | KeyCode | `InputObject._get` возвращает data int |
| InputObject.UserInputType/UserInputState | соответствующие enum | raw int; внутренний `_input` использует int/таблицы |
| UserInputService:IsKeyDown input | KeyCode | прямой int(value) |
| StarterGui:Set/GetCoreGuiEnabled input | CoreGuiType | str(value) как dictionary key; All semantics не реализованы |
| Players:GetUserThumbnailAsync inputs | ThumbnailType, ThumbnailSize | namespace есть; функциональный API не подтверждён |
| Workspace:BulkMoveTo input | BulkMoveMode | namespace есть; audit метода нужен в регрессии |
| KeyframeSequence, UI, Constraints enum properties | class-specific schema | generic props; registry helper без property domain не даёт полной поддержки |

Внутри motor/network/property metadata сохраняются numeric IDs. Внешние parity getters/events/results должны возвращать EnumItem; renderer не должен получать Object вместо material ID. В событиях Running/Climbing/Swimming передаётся speed, в Jumping/FreeFalling/GettingUp boolean, в Seated boolean+Instance/nil: их нельзя преобразовывать в enum по одному event name substring.

## Обнаруженные расхождения таблиц

По официальной документации от 14 октября:

- CameraType содержит Orbital=7, которого сейчас нет в Bobux.
- PartType содержит Wedge=3 и CornerWedge=4; namespace отсутствующие значения не следует путать с фактическим созданием правильного collider.
- AnimationPriority: Idle=0, Movement=1, Action=2, Action2=3, Action3=4, Action4=5, Core=1000. Core имеет нижний приоритет несмотря на Value=1000; numeric sorting неправильна.
- CoreGuiType сейчас сдвинут: настоящий All=4, EmotesMenu=5, SelfView=6, Captures=7. В Bobux All=7, EmotesMenu=4, SelfView=5, Captures=6. Новые AvatarSwitcher=8, ExperienceShop=9 документированы отдельно.
- Material NAMED_MATERIAL_ENUMS совпадает с текущими 45 документированными items; локальные legacy rendering ordinals не включать в parity `GetEnumItems`.
- HumanoidStateType уже содержит все 17 измеренных items, включая gaps 9/17 и None=18; Standing/LedgeGrab не добавлять.
- RaycastFilterType Blacklist/Whitelist — прежние alias: канонический Name и наличие aliases в GetEnumItems надо снимать в Studio, не считать отдельными значениями.

## Два явных профиля

`ExistingNumericEnums` сохраняет прежние Enum tables, getters, event args и numeric equality для существующих Bobux VM. `RobloxParity.EnumItem` публикует userdata EnumItem и типизированные результаты. На первом внедрении default остаётся ExistingNumericEnums до проверки corpus и миграции.

Профиль — immutable runtime option `enum_profile`, сохранённый в `_script_runtimes[id]` и VM-local binding closure / LuaAPI metadata. Он наследуется `require`, task coroutines и event callbacks. На shared BobuxInstance (wrapper кешируется в Node) и shared BobuxEvent профиль НЕ хранить: две VM могут читать один Node. Глобальный `_current_enum_profile` тоже небезопасен при nested callbacks.

Возможный адаптер без native rebuild: VM-local `mt_Object.__index` shim в `_native_lua_type_setup` (проект уже делает такие shims для Vector/Color), с central schema `(ClassName, property)` и enum method return schemas. Для event callbacks `__bobux_connect/__bobux_once/__bobux_signal_wait` захватывают профиль вызывающей VM и преобразуют явно размеченные domain args; shared event хранит только domain schema, не профиль. Синхронный run_script и module runtime должны применять тот же профиль/типовую настройку, иначе API различается по способу запуска.

Альтернатива — отдельный LuaObjectMetatable per VM с теми же schemas, если тесты выявят проблемы Lua shim. Не нужно менять `obj.lua_metatable` на общий профиль. Нормализатор ввода обязан знать `(class, property/method, argument)` policy: matching EnumItem всегда проверяет domain, а numeric/string/fractional conversion следует собственному native probe этой boundary. Нынешний registry `coerce(value, expected_domain, allow_legacy_numeric)` — только scalar identity kernel прототипа, не Roblox setter/method cast. Даже в parity property setters принимают измеренные numbers/Names/numeric strings/fractions. Fake Value dict нужен лишь явно названному old/import adapter, если прежний контракт этого требует; arbitrary tables не становятся EnumItem.

Просто принимать числовые setters недостаточно для обратной совместимости: userdata==number в Lua не вызывает __eq, и numeric table keys не равны userdata keys. Поэтому `Enum.HumanoidStateType.Jumping==3` сохраняется только в ExistingNumericEnums; parity — отдельный осознанный профиль. Неизвестный/пустой profile теперь отклоняется `to_boundary` с null, а не молча превращается в numeric. В production runtime creation должен выдавать явную ошибку configuration при неизвестном profile. Исходники карт не переписывать.

## Network и persistence

`ImportedPlaceNetwork._pack_value` сейчас превращает любой Object кроме Node/BobuxInstance в null. Без codec EnumItem в RemoteEvent/RemoteFunction исчезнет. Нужен tagged record, например `{"$enum":{"type":"HumanoidStateType","name":"Jumping","value":3}}`, до generic Object branch. Decode проверяет whitelist type+name+value по registry, отклоняет неизвестные/несогласованные tags, intern-ит канонический item. Сериализация не может принимать клиентский classname/набор произвольных свойств как Object.

Record нужно версионировать или capability negotiate, поскольку старый peer видит обычный Dictionary. Нельзя незаметно включить enum wire на опубликованном старом сервере. Внутренние typed Humanoid RPC state/property payload остаются прежними int, domain проверяется ещё до RPC. В ExistingNumericEnums enum remote arguments старой VM по-прежнему обычные numbers. Parity receiver преобразует tagged item в объект; legacy receiver не должен молча получать Dictionary. Смешанная версия без negotiation — BLOCKED; безопасный rollout сначала capability-aware server, затем client.

Generic node metadata, `roblox_properties`, snapshot `var_to_bytes`, authored map JSON не должны хранить живой EnumItem Object. Setter нормализует в scalar ID или прежний serialized representation до metadata. Это сохраняет importer/renderer/network contracts и не требует редактировать четыре защищённых файла.

## Внедрение по проверяемым шагам

1. Зафиксировать исходные real Luau runtime тесты и 21-map inventory. Подготовить независимый EnumItem reference probe в Studio: Name/Value/EnumType/typeof/tostring/equality/items order/alias/readonly/error semantics.
2. Registry и scalar coercion как новый модуль с source tags; enum values из официальных docs+Studio. Никаких авто-generated fake values для неизвестных enum.
3. Только opt-in runtime профиль и VM-local typeof/tostring. Сразу проверить cross-VM isolation и table-key identity.
4. Полный проход Humanoid getters/methods/events + RigType, CameraType, Material/Shape, raycast params/results, input, TweenInfo/PlaybackState. Unsupported floor/Animator APIs остаются PARTIAL/BLOCKED; не объявлять readiness по новому class.
5. Tagged codec unit+integration tests, explicit negotiation design. Production wire включать только после старый↔новый peer тестов.
6. Corpus real Luau execution/regressions, счётчики errors до/после; stable ExistingNumericEnums по умолчанию. Затем выбирать migration policy для imported Roblox maps без изменения authored source.

## Тесты — функциональные, не имена

`tools/character_parity/enumitem_contract.luau` — собственный тестовый дизайн, пригодный для Studio и будущего Bobux parity fixture. Он пока NOT_RUN. Predicates readonly/unknown member/type string дополнительно сверяются со Studio, прежде чем использовать их как эталон. Он проверяет реальные properties, userdata type, equality/table keys, readonly, GetEnumItems, mutation isolation, Humanoid states/events, CameraType/Material round-trips и RaycastParams. Каждый сценарий должен выполняться через настоящий Luau VM; чтение названия GDScript method не PASS.

Дополнительно обязательны: второй VM legacy рядом с parity VM на одном Node; два связанных event callbacks разных профилей; require/task сохраняют профиль; numeric setter explicit compatibility; wrong enum domain не изменяет объект; completed Tween arg type; input enum compare; RemoteEvent nested item round-trip, wrong/unknown wire tags; old client↔new server/new client↔old server; реальные части карт из 21-map inventory. Physics, floor contact и animation priority mixing требуют своих наблюдаемых сцен и не проверяются пустым stub getter.

Изолированный прототип подготовлен в `addons/roblox_runtime/enums/` без binding в production LuaScriptEngine. Он охватывает HumanoidStateType, CameraType, AnimationPriority, Material, SensorMode, SensorUpdateType и RaycastFilterType. `tools/character_parity/validate_enumitem_prototype.gd` использует две независимые настоящие LuaAPI VM, существующий numeric namespace и новый userdata namespace; проверяет значение/идентичность/readonly/coercion и независимые facades одного scalar backing. Эти facades — тестовый kernel, не production Humanoid или network integration. Профиль production по-прежнему прежний.

После остановки Studio Play запущен fast isolated validator на Godot 4.7 / Luau 0.719. **18 PASS / 0 FAIL**, exit 0, 2,6 с. Две VM одновременно сохраняют разные namespace representations и читают общий scalar backing; readonly действительно вызывает перехватываемый Lua error, Name/Value/EnumType/GetEnumItems/GetEnums выполняются native userdata methods. Прямая повторная инъекция singleton item из Godot возвращает тот же userdata для table key. Это проверка возможностей bridge/kernel, не доказательство совпадения ещё не измеренных Enum semantics с Roblox.

Лог: `.codex-tmp/character_parity/enumitem-prototype.log`. Машиночитаемый отчёт: `.codex-tmp/character_parity/enumitem_prototype.json`. Повторение:

```powershell
& .\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/character_parity/validate_enumitem_prototype.gd
```

Этот результат **18 PASS** относится к историческому первому прогону. Его JSON и log сохранены. Новый r02 остановился на GDScript typed warning/parse errors в validator; log сохранён, он не объявлен успешным. После explicit bool/WeakRef annotations выполнен r03 на **Godot 4.7 / Luau 0.719: 54 PASS / 0 FAIL, exit 0, 4.28 с**. Строки `tostring`, measured items/order/FromName/FromValue/arity/errors/aliases/operators, native supplement, VM isolation, negative ownership control и genuine full GC/teardown сравнения проходят.

Свежие log/JSON: `.codex-tmp/character_parity/enumitem-prototype-native-r03.log` и `.json`. Tracked отчёт с SHA-256 собственных sources и runtime log: `tests/roblox_humanoid/phase_a/enumitem-prototype-native-r03.report.json`. В нём 20 aggregate checks сравнивают native observations (`MEASURED`); остальные 34 — kernel/isolation/lifetime engineering checks. Один aggregate check проверяет много raw cases/items; **54 — число checks, не число отдельных native rows**. Это Windows desktop validator; Android binary и production shared Humanoid не были этим прогоном проверены.

Для повторения нужен новый report path, поскольку validator отказывается перезаписывать прежние отчёты:

```powershell
& .\.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tools/character_parity/validate_enumitem_prototype.gd -- --report=res://.codex-tmp/character_parity/enumitem-prototype-next.json
```

Production bindings, Humanoid getters/events, network codec и остальные прежние namespace domains ещё не мигрированы. Default остаётся numeric, никакой код авторских карт не менялся. `tostring(Enum)` теперь `Enums`, `tostring(Enum.Domain)` — имя домена без prefix; обе строки подтверждены run02. Existing baseline сохранён parent agent в `.codex-tmp/character_parity/baseline_2026-10-14`; статус A3 остаётся OPEN.

## Минимальный plan внедрения VM boundary после prototype

1. Runtime creation проверяет immutable profile по whitelist; неизвестный profile выдаёт configuration error. Одна registry принадлежит engine session, каждая живая VM получает metadata lease. `run_script`, runtime setup и `require` используют один путь bindings, без duplicate registry на каждый ModuleScript.
2. В VM `typeof` сначала классифицирует Enum userdata через Script identity. Затем применяет прежние Instance/CFrame probes; иначе readonly unknown member EnumItem может вызвать ошибку при попытке прочесть `ClassName`. Native generic metatable и map files остаются прежними.
3. VM-local property/method shim захватывает profile и registry, а shared wrapper хранит только исходный scalar. Первый реальный вертикальный срез — `Humanoid:GetState` / ChangeState / enabled state methods / StateChanged / StateEnabledChanged. Callables bridge бывают userdata: адаптер не ограничивается `type(method)=='function'`, проверяет colon/dot фактическими тестами. Native input coercion сначала измеряется по каждому API, затем помещается в domain-aware policy; numeric отказ нельзя навязать из одного equality test.
4. Callback adapter хранится на стороне вызывающей VM и захватывает её profile, применяя явные event domain schemas к Connect/Once/Wait. Shared BobuxEvent и cached BobuxInstance не получают profile fields. Два VM должны читать один настоящий Humanoid Node и получать одно событие как number/EnumItem соответственно; нынешние PropertyFixture facades этот production test не заменяют.
5. Getter schemas расширяются на RigType, CameraType/Material/Input/Tween/raycast без изменения internal IDs. Legacy boundary возвращает прежний результат getter без автоматической нормализации: некоторые существующие Material/raycast getters возвращают строки, а не числа. Prototype `to_boundary` — helper для заранее нормализованных scalar IDs, не универсальный wrapper всех production properties. Parity adapter сначала получает domain-aware canonical scalar через явный import/material adapter, затем EnumItem; это не должно превращать прежнюю строку или rendering ordinal в null либо другое число в legacy VM. Authored serialized properties нормализуются до согласованного stored representation перед metadata/render/RPC. `FloorMaterial` и Animator требуют настоящей реализации contact/animation, не stored stub.
6. Только после этих локальных проверок вводится typed enum wire codec с explicit capability negotiation. Проверяются same/new/old peer pairs и отказ mismatch. До их PASS parity profile не становится default и не включается на опубликованном сервере.

Readiness A3 требует production shared-wrapper/event/module/coroutine проверки и весь ранее существующий namespace corpus, а не только успешный новый registry. До этого любые «полная EnumItem совместимость» или «безопасная migration всех карт» — недоказанные утверждения.

## Primary источники

- [EnumItem: Name, Value, EnumType](https://create.roblox.com/docs/reference/engine/datatypes/EnumItem)
- [Enum: GetEnumItems, FromName, FromValue](https://create.roblox.com/docs/reference/engine/datatypes/Enum)
- [Enums: GetEnums](https://create.roblox.com/docs/reference/engine/datatypes/Enums)
- [CameraType](https://create.roblox.com/docs/reference/engine/enums/CameraType)
- [AnimationPriority](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority)
- [CoreGuiType](https://create.roblox.com/docs/reference/engine/enums/CoreGuiType)
- [PartType](https://create.roblox.com/docs/reference/engine/enums/PartType)
- [Material](https://create.roblox.com/docs/reference/engine/enums/Material)
- [BulkMoveMode](https://create.roblox.com/docs/reference/engine/enums/BulkMoveMode)

Документация перечисляет API и values; детали readonly/errors/order/aliases, equality и type в конкретной Studio должны дополнительно попасть в собственную сырую телеметрию. База 13 октября уже подтверждает EnumItem в StateEnabledChanged, но не весь EnumItem contract.
