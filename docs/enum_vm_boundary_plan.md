# A3: минимальное включение EnumItem на границе VM

Дата аудита: 14 октября 2026. Статус: **DESIGN / NOT_IMPLEMENTED**. Это план небольшого opt-in slice, не заявление о завершении фазы A3. Production-файлы при этом аудите не изменены; Godot и UI не запускались.

## Источники и область

- Текущий `autoload/lua_script_engine.gd`, существующая native Luau bridge и изолированный registry `addons/roblox_runtime/enums/`.
- Архитектура `docs/ROBLOX_CHARACTER_ARCHITECTURE_RU.md` и аудит `docs/character_parity_enum_audit.md`.
- Native Studio 0.742.0.7421053: run `c475020d-1687-4cb5-9b53-2ecbe4d5a2f7`, 543 observations, `tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-coercion-run01.raw.json`, SHA256 `bf6f00d2dd18a509353347852a76aec14ae5778e81e23eb2773923961e154e19`.
- Дополнительные 6 observations: run `06e5b50d-dbad-4187-bf85-12d34a204bc8`, `2026-10-14-studio-enum-extra-run01.raw.json`, SHA256 `bf0cfd177f200ded653b4423d5acdbd99e346aa24cd582599c9bc4f9c1f56306`.

Первый production slice: Enum namespace/type strings и только Humanoid `GetState`, `ChangeState`, `GetStateEnabled`, `SetStateEnabled`, `StateChanged`, `StateEnabledChanged`. Внутреннее состояние мотора, Node metadata и typed Humanoid RPC остаются числовыми. Остальные enum properties, Material renderer, InputObject, Animator и wire codec имеют отдельные ворота.

## Фактические пути исполнения

| Точка | Текущий код | Следствие для минимального slice |
|---|---|---|
| `run_script` :3306 | Сразу возвращает `start_script(...,{realm='studio',retain=true})`; старый sync body ниже недостижим | Рабочий путь один. Не вносить только в недостижимый body |
| `start_script` :3448 | Опции копируются для deferred start; затем создаётся LuaAPI, bindings, type setup, coroutine и runtime | Проверить/зафиксировать профиль до очереди; owner registry прикрепить к **LuaAPI**, а не coroutine |
| `_push_runtime_bindings` :4243 | Enum всегда `_build_enum_proxy()`; общие BobuxInstance/BobuxEvent | Опциональное представление namespace плюс VM-local callbacks; default branch точно прежний |
| `_native_lua_type_setup` :4458 | VM-local metatable shims; native debug удаляется после setup | Установить адаптер до `debug=nil`, сохранить raw Object index приватно; typeof Enum проверять до ClassName/LookVector |
| scheduled prelude :4714 | `require` компилирует модуль внутри вызывающей VM; local cache per VM | Профиль, registry и Lua closures наследуются автоматически. RoomModule не запускать отдельной VM |
| `_require_module` :5179 | Старый helper создаёт отдельную VM и имеет global `_module_cache` | В актуальном дереве `.gd` нет callers. Не использовать для parity; при будущем вызове нужен отдельный контракт, а не молчаливый fallback |
| `_rewrite_lua_async_calls` :6260 | Переписывает только colon calls | Извлечённые/dot `Connect`, `Once`, `Wait` обходят rewrites и требуют metatable route |
| `_owned_lua_bindings` :4207 | Оборачивает Callable в LuaCallableExtra с finalizer | Новые tuple exports тоже LuaCallableExtra; не экспортировать голые callable без lifetime |

`BobuxInstance.wrap` :771 кеширует единственный wrapper в Node. `_shared_event` :797 кеширует BobuxEvent в Node. Профиль нельзя записывать ни туда, ни в `lua_metatable` общего wrapper, ни в engine-wide current-profile. Native `mt_Object` принадлежит конкретной LuaAPI VM; его Lua shim не меняет соседнюю VM.

## Профиль и владение

Предлагаемые совместимые сигнатуры:

```gdscript
func run_script(lua_code: String, context_node: Node, options: Dictionary = {}) -> Dictionary
func start_script(lua_code: String, context_node: Node, options: Dictionary = {}) -> Dictionary
func _validate_enum_profile(options: Dictionary) -> Dictionary
func _push_runtime_bindings(target: Object, context_node: Node, options: Dictionary) -> void
```

Отсутствующий `enum_profile` означает `ExistingNumericEnums`. Только точная строка `RobloxParity.EnumItem` включает адаптер. Explicit null, пустая строка, неверный тип и неизвестная строка возвращают `ok=false,error=...`; их нельзя превращать в default через `str()`/пустой fallback. Валидация выполняется после проверки context, до realm skip, очереди и резервирования runtime ID. Deferred-start options сохраняют уже проверенную строку.

`run_script` с третьим optional аргументом объединяет старые `{realm:'studio',retain:true}` с переданными options; существующие двухаргументные callers сохраняют прежний результат. Для опции достаточно `start_script(..., {'enum_profile':'RobloxParity.EnumItem'})`; документация не должна обещать переключение через mutable global.

В parity VM создаются registry и новый VM-bound adapter. Registry `attach_to_vm(lua)` — существующий metadata lease. Adapter также хранится в LuaAPI metadata, например `bobux_enum_boundary_owner`; он владеет registry, но не VM. Runtime dictionary содержит диагностический `enum_profile`. Owner metadata живёт и при переносе LuaAPI в `_retained_lua_states`; `Enum=nil`, coroutine GC и завершение main thread не закрывают lease. Registry/item/type не должны образовывать RefCounted cycle. Detached Godot EnumItem после VM teardown требует явного registry owner либо scalar/tag; хранить такой объект в persistent Node metadata нельзя.

## Контракт нового VM adapter

Новый файл, например `addons/roblox_runtime/enums/roblox_enum_vm_boundary.gd`, изолирует coercion и typed outputs. Не расширять BobuxInstance второй системой состояний.

```gdscript
func _init(registry: RefCounted, profile: String) -> void
func kind(value: Variant) -> String
func is_humanoid(value: Variant) -> bool
func call_humanoid(method_name: String, tuple: Variant) -> Variant
func state_argument(value: Variant, method_name: String, present: bool) -> Dictionary
func bool_argument(value: Variant, present: bool) -> Dictionary
```

`call_humanoid` экспортируется как LuaCallableExtra с `set_info(Callable(adapter,'call_humanoid'), 2, true, false)`: один fixed argument `method_name`, остальные Lua arguments становятся LuaTuple. `tuple.to_array()` сохраняет missing versus explicit nil и лишние аргументы. Plain fixed GDScript arguments с default null этой информации не сохраняют. Return void должен быть **empty LuaTuple**, не один nil: native `ChangeState`/`SetStateEnabled` измерены с return_count=0. Getter возвращает один enum item или bool. LuaError используется для ошибки, а не null, который выглядит как успешный nil.

Receiver Humanoid проверяется отдельно до доступа к Node. Для штатного colon и explicit dot call это первый tuple element. Native поведение извлечённого метода с отсутствующим/чужим receiver пока NOT_OBSERVED: не выдавать новую permissive policy за Roblox. Если до дополнительного probe сохраняется текущий Bobux bound-dot convenience, это ENGINE_APPROXIMATION и ограничение slice.

VM-local `mt_Object.__index` сначала проверяет **конкретные ключи** четырёх методов и Humanoid receiver, затем возвращает Lua closure над tuple export. Не опираться на `type(member)=='function'`: существующий raw index выдаёт callable userdata. Для остальных объектов/ключей вызывается сохранённый raw index без преобразований. В том же shim namespace Enum methods получают существующие tuple closures; операторы EnumItem используют уже проверенную isolated shim policy.

## Вызовы Humanoid

| API | Вход/выход boundary | Вызов существующей реализации после нормализации |
|---|---|---|
| `h:GetState()` | Один canonical item HumanoidStateType по scalar результата | `h.GetState()` :2792, затем `registry.to_boundary(value,'HumanoidStateType',profile)` |
| `h:ChangeState(state)` | Typed/domain-aware state input; zero returns | `h.ChangeState(state_id)` :2766 |
| `h:GetStateEnabled(state)` | Typed state input; один bool | `h.GetStateEnabled(state_id)` :2788 |
| `h:SetStateEnabled(state,enabled)` | Typed state input + native bool cast; zero returns | `h.SetStateEnabled(state_id,enabled_bool)` :2776 |

Все calls идут в тот же cached wrapper и motor. Адаптер не отождествляет значения разных доменов: CameraType.Custom=5 нельзя принять как HumanoidStateType.Freefall=5. Он не превращает произвольную table с Name/Value в EnumItem и не вызывает `int(Object)`.

Native coercion отдельно от `registry.coerce` (он только identity kernel): matching item, canonical number, bare state Name и измеренные положительные fractions поддерживаются. Wrong enum domain даёт `Unable to cast CameraType to HumanoidStateType`; invalid numeric/NaN/Inf — `Unable to cast double to HumanoidStateType`; boolean — `Unable to cast bool...`; table — `Unable to cast Array...`. Это измеренный semantic error text, caller-location prefix исключается.

Не переносить property setter conversion на methods: numeric string `'8'`, full `Enum.HumanoidStateType.Running` string и unknown string имеют pcall=true, но `SetStateEnabled(...,false)` не выключает ни один canonical state. `GetStateEnabled` этих строк возвращает true. `int(string)` даст неверный FallingDown=0; canonical parse `'8'` даст неверный Running=8. Для этих строк нужен отдельно измеренный opaque/invalid-state результат, либо явно OPEN policy до probe.

Missing/nil: `ChangeState(nil)` и missing state pcall=true; GetStateEnabled при nil/missing — `Argument 1 missing or nil`. SetStateEnabled сначала проверяет второй argument: missing/nil bool — `Argument 2 missing or nil`, даже если state также отсутствует. При present false и nil state — `Argument 1 missing or nil`. Extra args игнорируются. Bool input `'false'` и number 0 измерены как false; Lua truthiness и GDScript `bool('false')` для этого не подходят. Остальные string/number bool casts требуют своей таблицы наблюдений.

Преобразование scalar `GetState` не исправляет физику или значение fresh Humanoid: native fresh fixture имеет None=18, а текущий backend fallback часто Running=8. Это отдельный A2/physical lifecycle gap; wrapper не должен скрывать его под typed enum.

## События: одна конверсия в каждой VM

На чтении `h.StateChanged`/`h.StateEnabledChanged` raw index возвращает **тот же BobuxEvent**. VM-local weak-key map запоминает только сигнатуру signal:

```lua
signal_domains[signal] = {"HumanoidStateType", "HumanoidStateType"} -- StateChanged
signal_domains[signal] = {"HumanoidStateType", false}               -- StateEnabledChanged
```

Никакой профиль/schema mutation на shared BobuxEvent не нужен. Map принадлежит VM. Перевод enum scalar через её registry выполняется в зарегистрированной Lua closure **до** task.spawn либо до заполнения `received` в Wait. Bool вторым аргументом сохраняется. Running/Climbing/Swimming speed, Jumping boolean, Seated boolean+Instance/nil этим map не затрагиваются.

Нужно согласованно изменить три scheduler helpers и routing signal methods:

1. Parity Object-index shim для `Connect`, `connect`, `Once`, `Wait`, `wait` у наблюдённого typed signal возвращает Lua function к тем же helpers. Это закрывает `local c=s.Connect; c(s,fn)` и `local w=s.Wait; w(s)`.
2. `__bobux_connect`/`__bobux_once` берут **raw** Connect/Once через сохранённый raw Object index, а не `signal:Connect` внутри shim. Иначе вызов рекурсивен. Existing origin coroutine upvalue и task.spawn сохраняются.
3. `__bobux_signal_wait` берёт raw Once; callback конвертирует typed packed args до `received`, цикл task.wait и unpack c `.n` сохраняют trailing nil. Нельзя ждать raw numbers и конвертировать только Connect.
4. Converting callback вызывается ровно один раз. Helper route и metatable route не должны независимо оборачивать один callback дважды. Table-backed custom signals сохраняют текущий table path.
5. Отсоединение connection/Once выполняется существующим BobuxConnection. Stop cleanup и origin-thread retention остаются прежними.

Если typed signal попадает в VM внешним способом без чтения Humanoid property, map не знает его domain. Это явно вне минимального slice; следующий общий event schema контракт может хранить immutable domains на signal, но не VM profile. Методы Signal:Wait/Connect должны также проверяться через require/coroutine и после завершения main script.

## Обязательный локальный fixture

Один scene tree, **один настоящий Humanoid Node**, cached `BobuxInstance.wrap(node)` и shared event. Запустить A с absent profile (legacy), B с explicit parity. Базовые assertions:

- A: `type(Enum.HumanoidStateType.Running)=='number'`; GetState numeric; старые `GetState()==3/8` и numeric setter fixtures неизменны.
- B: userdata/typeof EnumItem; GetState identity равно `Enum.HumanoidStateType.<actualState>`; типы, Name/Value/EnumType, table keys, readonly и unknown-member errors.
- A и B независимо подключают StateChanged Connect + StateEnabledChanged Once/Wait; один scalar motor/event emission даёт A numbers, B её canonical items и неизменный bool. Подключения в обратном порядке дают тот же результат. Nested callback B→A→B не меняет профиль.
- First-class `Connect`, `Once`, `Wait`, lowercase connect и colon rewrites получают одинаковые типы. Once ровно один вызов; Disconnect прекращает вызовы; Wait можно task.spawn; main script может завершиться раньше callback.
- Один `RoomModule` содержит функцию, читающую state и подключающую callback; require дважды в каждой VM возвращает одну и ту же table **внутри этой VM**. Между VM разные module results/closures; profile не переносится из первого caller. Module не вытаскивается в GDScript `_module_cache`.
- `coroutine.create/resume`, `task.spawn`, `task.defer`, `task.delay`, coroutine.wrap и coroutine, созданный внутри module, используют исходный профиль после yield/resume.
- Unknown/null/empty profile fail до queue/runtime allocation; отложенный parity script сохраняет профиль. Двухаргументный run_script legacy и трёхаргументный parity работают одинаковым scheduler path.
- Drop globals Enum + collectgarbage; close A while B remains; callbacks B still canonical; Stop disconnects event callables, затем VM teardown и weakrefs adapter/registry/type/item освобождаются.

Проверить fixture на настоящей LuaAPI, затем player40/NPC16 и существующие network/replication regressions. Исторические 48 PASS/5 FAIL/18 SKIP calibration не переписывать. Report явно разделяет registry observations, production boundary PASS и physical gaps.

## Открытые ворота

| Пункт | Статус / необходимое доказательство |
|---|---|
| Humanoid receiver/extracted method | NOT_OBSERVED: native wrong/missing self и другой Humanoid receiver |
| Unknown/full/numeric method strings | OPEN: native StateEnabledChanged payload + GetStateEnabled той же raw string после SetStateEnabled; canonical-state effects уже наблюдены |
| Bool cast beyond `'false'`/0 | NOT_OBSERVED: true/false strings, arbitrary strings, positive/negative number, EnumItem и extra arity |
| Enum root completeness | PARTIAL: prototype 7 domains/85 items против 648 native enum types; minimal slice не объявлять полным namespace |
| Other enum properties | OPEN: typed getters/setters отдельно по ClassName+property. Особенно Material string renderer: не передавать в него EnumItem через общий to_boundary |
| RemoteEvent/RemoteFunction | OPEN: `_pack_value` превращает generic Object в null. Tagged enum codec + capability negotiation и old/new peer combinations — следующий slice; до этого parity нельзя сделать production default |
| Native pointer cache | PREEXISTING / phase F: raw Object* userdata cache reuse требует ObjectID/lifecycle проверки; не менять C++ в этом slice |
| Fresh GetState/fизика | A2/B/F gap: typed return не доказывает native state behavior |

Без закрытия этих ворот opt-in local fixture может быть PASS в своей явной области. Полная A3, глобальная Roblox parity и безопасный rollout на опубликованный сервер остаются незавершёнными.
