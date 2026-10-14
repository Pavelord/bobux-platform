# Roblox Character: матрица публичного API Bobux

Аудит Phase A1, 14 октября 2026. Это снимок исходной реализации, а не утверждение о полной совместимости и не итог фаз A–J. Production код и карты этим аудитом не менялись; Godot/Studio gameplay в этой подзадаче не запускались.

## Происхождение и критерии

Список публичных членов получен из официальных YAML [Roblox/creator-docs](https://github.com/Roblox/creator-docs/tree/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes), commit `031b2f91d3d47274c255f3ed5691c29f792c181d`. Снимок включает **69 классов и 1045 собственных публичных свойств/методов/событий/колбэков**. Унаследованные члены перечислены один раз в разделе класса-родителя; цепочка `inherits` приведена для каждого класса. В snapshot сохранены signatures, ограничения security/tags и SHA-256 каждого YAML; описания/исходный код Roblox не копируются.

Включены члены с `security=None` хотя бы для чтения или записи; запрещённая другая сторона доступа и deprecated/read-only/not-scriptable tags видны в строке. Nonpublic API не считается отсутствующей поддержкой: отдельно сохранён в JSON для проверки границ. Camera, Path и промежуточные классы добавлены для полноты связанных контрактов; физические Constraints/силы включены из descendant-цепочки официального Constraint.

- **Полностью** — проверен соответствующий публичный контракт во всех заявленных профилях. Таких утверждений в этом первичном аудите нет.
- **Частично** — вручную прослежена реальная работающая часть маршрута в исходниках; ограничения указаны. Не устанавливается автоматически по присутствию имени.
- **Нет** — отсутствует dedicated функциональный маршрут в изученном wrapper/runtime либо есть только metadata/заглушка/доступное имя сигнала без нужного producer. Это не отрицание сохранности экземпляра в importer/Explorer.

Исходный снимок: частично `188`, нет `857`, полностью `0`. Количество имён не показатель качества. Source evidence имеет хеш файла: параллельные последующие изменения A3 могут сделать baseline устаревшим. После реализации матрицу нужно обновлять с новыми assertions и данными, а не менять статус на основании новой функции.

## Тестовые карты: реальная доступность

Найдены все **21 оригинальных файла** в `C:/Users/Pavel/Downloads`; текущие SHA-256 совпали со снимком 3 октября. Одна пара Plane Wars имеет одинаковое содержимое: 21 файлов, **20 уникальных оригиналов**. Не запускались все карты: исторически сцена строилась у 20, ограниченный playtest был у четырёх. Эти прежние результаты не являются новыми gameplay PASS.

Статически прочитаны **14203 Source-полей**, из них **14145 непустых**, в сохранённых corpus JSON. Всего script instances по historical manifest: 14215. У карты №18 двенадцать объектов не имеют Source-поля в JSON; ещё два Source пусты. Их API usage **BLOCKED**, отсутствие совпадений не означает отсутствия кода/поведения. JSON не пересоздавались и исходники карт не исправлялись.

В столбце «Карты» указаны **лексические кандидаты** `.Member`/`:Member`: номера файлов и число script Source с хотя бы одним совпадением. Receiver type/исполнение не доказаны. Например `.Play` может принадлежать Sound, `.Priority` — пользовательской таблице. Динамические обращения/алиасы и внешние `require(assetId)` не покрыты. `—` означает отсутствие прямого совпадения в доступном Source, а не доказанное «никогда не используется». Поэтому точное typed usage для всей матрицы ещё требует Luau AST/data-flow и runtime instrumentation.

| № | Оригинальный файл | Script instances | Source поля / непустые | SHA original сейчас |
|---:|---|---:|---:|---|
| 00 | Build a Boat FULLY WORKING (Subscribe to FrenchBread).rbxl | 1843 | 1843 / 1837 | совпадает |
| 01 | ACF_-_VANGUARD_2.rbxl | 3601 | 3601 / 3598 | совпадает |
| 02 | Natural Disaster Survival (Subscribe to FrenchBread).rbxlx | 496 | 496 / 496 | совпадает |
| 03 | 2017 - Lego's Plane Wars (1).rbxl | 113 | 113 / 113 | совпадает |
| 04 | 2017 - Lego's Plane Wars.rbxl | 113 | 113 / 113 | совпадает |
| 05 | 2011 - Natural disasters survival.rbxl | 26 | 26 / 26 | совпадает |
| 06 | PKil(Alpha).rbxl | 24 | 24 / 24 | совпадает |
| 07 | Combat-system-UNCOPYLOCKED.rbxl | 52 | 52 / 52 | совпадает |
| 08 | Grw-a-garden-UNCOPYLOCKED.rbxl | 1248 | 1248 / 1248 | совпадает |
| 09 | Steal-A-Brainrot-Modded-Uncopylocked.rbxl | 1451 | 1451 / 1451 | совпадает |
| 10 | 2017 - Doomspire Brickbattle.rbxl | 42 | 42 / 42 | совпадает |
| 11 | Doomspire Brickbattle.rbxl | 42 | 42 / 42 | совпадает |
| 12 | Murder Mystery 2.rbxl | 200 | 200 / 169 | совпадает |
| 13 | 2015 - Epic Minigames.rbxl | 3590 | 3590 / 3590 | совпадает |
| 14 | 2018 - Tower_Of_Hell_Full.rbxl | 93 | 93 / 78 | совпадает |
| 15 | Roblox - Rocket Arena.rbxl | 15 | 15 / 15 | совпадает |
| 16 | NowDoTheHarlemShake - The Normal Elevator.rbxl | 194 | 194 / 193 | совпадает |
| 17 | Stickmasterluke - The Underground War.rbxl | 20 | 20 / 20 | совпадает |
| 18 | Reignwolf - Escape the facility obby.rbxl | 297 | 285 / 283 | совпадает |
| 19 | NintendoZACHERY - Be crushed by speeding wall.rbxl | 375 | 375 / 375 | совпадает |
| 20 | Nikilis - Murder Mystery 2.rbxl | 380 | 380 / 380 | совпадает |

## Существенные ограничения исходной архитектуры

- `Humanoid` игрока и NPC уже имеют live motor/state/event маршруты, но player/NPC физические контроллеры различаются. 35 реальных R6 сценариев от 13 октября сохранены в [эмпирическом отчёте](ROBLOX_HUMANOID_EMPIRICAL_RU.md): 48 PASS, 5 FAIL Landed, 18 SKIP. Это не измерения ordinary-Part climbing, R15 или CCL.
- `LoadAnimation` возвращает `BobuxAnimationTrack` без AnimationId/KeyframeSequence playback. Изменение `IsPlaying` не движение суставов. Нет полноценного Animator priority/fade/blend/markers pipeline.
- `HumanoidDescription`/R15 scaling остаются metadata; `RigType=R15` не создаёт R15.
- CCL классы и sensor `Ladder`/`ClassicLadder` не подключены к публичному Luau/physical pipeline. Собственные GDScript `GroundController`/`ClimbController` не являются реализацией одноимённых Roblox API.
- Joint runtime создаёт жёсткий Generic6DOF для ограниченного mesh-to-mesh пути. Это не BallSocket/Hinge/Spring ragdoll, не Attachment-based constraints и не полноценный Motor6D animation rig.
- `CharacterRemoving`/`CharacterAppearanceLoaded` отсутствуют как полный lifecycle producer; повторное использование одного Node при respawn требует номера жизни либо создания новой модели.
- `ContextActionService` service-node и `PathfindingService` имя не дают BindAction/CreatePath/Path вычислений. Physics mass/friction/CustomPhysicalProperties/collision groups также не выводятся из сохранения metadata.

## Enum/камера: baseline и corpus риск

Baseline enum proxy — числовые ID, без полного Name/Value/EnumType/typeof/tostring/GetEnumItems. CameraType содержит Fixed…Scriptable, но отсутствует Orbital. CameraMode нельзя смешивать с CameraType. Исправление EnumItem должно иметь отдельный профиль/миграцию: native EnumItem не равен числу. Это раздел исходного снимка; новая A3 реализация проверяется отдельно.

| Regex категория | Кандидатов | Карты |
|---|---:|---|
| `get_state_direct_numeric_compare` | 0 | — |
| `get_state_reverse_numeric_compare` | 0 | — |
| `camera_type_numeric` | 4 | 17 |
| `material_numeric` | 0 | — |
| `animation_priority_numeric` | 1 | 01 |
| `change_state_numeric` | 0 | — |
| `enum_item_field` | 118 | 00,01,02,07,08,09,12,20 |
| `enum_typeof` | 2 | 00 |
| `enum_tostring` | 0 | — |
| `enum_items` | 39 | 00,01,02,07,08,09 |
| `enum_material` | 1074 | 00,01,02,07,08,09,10,11,13,14,16,18 |
| `enum_humanoid_state` | 164 | 00,01,02,06,07,08,09,12,13,14,20 |
| `enum_camera_type` | 90 | 00,01,02,06,07,08,09,12,13,20 |
| `enum_animation_priority` | 200 | 01,06,07,08,09,16 |
| `enum_core_gui_type` | 82 | 00,01,02,08,09,12,13,16,20 |

В Underground War вручную подтверждён прямой numeric CameraType setter (4/5, Follow/Custom), Source ordinal 2 и 3. `.Priority=10` в ACF, Source ordinal 625 — `Playlist.Priority` внутри `Module:AddPlaylist`, пользовательская таблица, **ложный кандидат AnimationTrack исключён**. Подтверждённых numeric AnimationPriority assignments здесь нет. Нулевые GetState()==number/ChangeState(number) regex результаты не покрывают сравнения через переменные. 118 обращений к Enum.*.*.{Name,Value,EnumType} и 39 GetEnumItems/GetEnums кандидатов делают отсутствие EnumItem существенным.

Официальные значения ключевых доменов в том же pinned snapshot:

- [HumanoidStateType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/HumanoidStateType.yaml): `FallingDown=0`, `Ragdoll=1`, `GettingUp=2`, `Jumping=3`, `Swimming=4`, `Freefall=5`, `Flying=6`, `Landed=7`, `Running=8`, `RunningNoPhysics=10`, `StrafingNoPhysics=11`, `Climbing=12`, `Seated=13`, `PlatformStanding=14`, `Dead=15`, `Physics=16`, `None=18`.
- [HumanoidRigType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/HumanoidRigType.yaml): `R6=0`, `R15=1`.
- [AnimationPriority](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/AnimationPriority.yaml): `Idle=0`, `Movement=1`, `Action=2`, `Action2=3`, `Action3=4`, `Action4=5`, `Core=1000`.
- [CameraType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/CameraType.yaml): `Fixed=0`, `Attach=1`, `Watch=2`, `Track=3`, `Follow=4`, `Custom=5`, `Scriptable=6`, `Orbital=7`.
- [CameraMode](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/CameraMode.yaml): `Classic=0`, `LockFirstPerson=1`.
- [Material](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/Material.yaml): `Plastic=256`, `SmoothPlastic=272`, `Neon=288`, `Wood=512`, `WoodPlanks=528`, `Marble=784`, `Basalt=788`, `Slate=800`, `CrackedLava=804`, `Concrete=816`, `Limestone=820`, `Granite=832`, `Pavement=836`, `Brick=848`, `Pebble=864`, `Cobblestone=880`, `Rock=896`, `Sandstone=912`, `CorrodedMetal=1040`, `DiamondPlate=1056`, `Foil=1072`, `Metal=1088`, `Grass=1280`, `LeafyGrass=1284`, `Sand=1296`, `Fabric=1312`, `Snow=1328`, `Mud=1344`, `Ground=1360`, `Asphalt=1376`, `Salt=1392`, `Ice=1536`, `Glacier=1552`, `Glass=1568`, `ForceField=1584`, `Air=1792`, `Water=2048`, `Cardboard=2304`, `Carpet=2305`, `CeramicTiles=2306`, `ClayRoofTiles=2307`, `RoofShingles=2308`, `Leather=2309`, `Plaster=2310`, `Rubber=2311`.
- [CoreGuiType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/CoreGuiType.yaml): `PlayerList=0`, `Health=1`, `Backpack=2`, `Chat=3`, `All=4`, `EmotesMenu=5`, `SelfView=6`, `Captures=7`, `AvatarSwitcher=8`, `ExperienceShop=9`.
- [SensorMode](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/SensorMode.yaml): `Floor=0`, `Ladder=1`, `ClassicFloor=2`, `ClassicLadder=3`.

CoreGuiType baseline после Chat имеет неверную нумерацию: official All=4, EmotesMenu=5, SelfView=6, Captures=7, AvatarSwitcher=8, ExperienceShop=9. Legacy consumers нельзя silently переключать без соответствующего профиля и тестов.

## Как читать evidence и автоматические тесты

E — вручную просмотренный участок текущего production исходника (точный хеш в JSON). T — существующий автоматический тест с ограниченными assertions, прочитанными при аудите. **NOT_RUN здесь:** никакие свежие PASS по наличию файла не присваиваются. В частности старый inventory harness имел autoload/preload проблему в прежнем прогоне; его существование не исправляет этот BLOCKED.

| Evidence | Файл / строка |
|---|---|
| E01 | [autoload/lua_script_engine.gd:1224](../autoload/lua_script_engine.gd#L1224) — `"AutoJumpEnabled", "BreakJointsOnDeath", "RequiresNeck"` |
| E02 | [autoload/lua_script_engine.gd:1010](../autoload/lua_script_engine.gd#L1010) — `func _get_impl(` |
| E03 | [autoload/lua_script_engine.gd:1189](../autoload/lua_script_engine.gd#L1189) — `"WalkSpeed":` |
| E04 | [scripts/player/player.gd:4041](../scripts/player/player.gd#L4041) — `get_meta("BreakJointsOnDeath"` |
| E05 | [autoload/lua_script_engine.gd:1219](../autoload/lua_script_engine.gd#L1219) — `"CameraOffset":` |
| E06 | [addons/roblox_runtime/roblox_humanoid_motor.gd:138](../addons/roblox_runtime/roblox_humanoid_motor.gd#L138) — `get_meta("DisplayName"` |
| E07 | [scripts/player/player.gd:3660](../scripts/player/player.gd#L3660) — `set_meta("FloorMaterial"` |
| E08 | [autoload/lua_script_engine.gd:1175](../autoload/lua_script_engine.gd#L1175) — `"Health":` |
| E09 | [autoload/lua_script_engine.gd:1226](../autoload/lua_script_engine.gd#L1226) — `"Jump":` |
| E10 | [autoload/lua_script_engine.gd:1217](../autoload/lua_script_engine.gd#L1217) — `"MaxSlopeAngle":` |
| E11 | [autoload/lua_script_engine.gd:1203](../autoload/lua_script_engine.gd#L1203) — `"MoveDirection":` |
| E12 | [autoload/lua_script_engine.gd:1221](../autoload/lua_script_engine.gd#L1221) — `"RigType":` |
| E13 | [autoload/lua_script_engine.gd:1048](../autoload/lua_script_engine.gd#L1048) — `"PrimaryPart", "Part0"` |
| E14 | [autoload/lua_script_engine.gd:2724](../autoload/lua_script_engine.gd#L2724) — `func MoveTo(` |
| E15 | [autoload/lua_script_engine.gd:2766](../autoload/lua_script_engine.gd#L2766) — `func ChangeState(` |
| E16 | [autoload/lua_script_engine.gd:2649](../autoload/lua_script_engine.gd#L2649) — `func EquipTool(` |
| E17 | [autoload/lua_script_engine.gd:2818](../autoload/lua_script_engine.gd#L2818) — `func LoadAnimation(` |
| E18 | [autoload/lua_script_engine.gd:2708](../autoload/lua_script_engine.gd#L2708) — `func _humanoid_move(` |
| E19 | [autoload/lua_script_engine.gd:2755](../autoload/lua_script_engine.gd#L2755) — `func TakeDamage(` |
| E20 | [scripts/player/player.gd:627](../scripts/player/player.gd#L627) — `_sync_humanoid_runtime_properties` |
| E21 | [autoload/lua_script_engine.gd:7039](../autoload/lua_script_engine.gd#L7039) — `func notify_humanoid_state_changed(` |
| E22 | [autoload/lua_script_engine.gd:376](../autoload/lua_script_engine.gd#L376) — `class BobuxAnimationTrack` |
| E23 | [scripts/player/player.gd:1366](../scripts/player/player.gd#L1366) — `func _enter_seat(` |
| E24 | [addons/roblox_runtime/roblox_legacy_motor.gd:63](../addons/roblox_runtime/roblox_legacy_motor.gd#L63) — `MaxSpeed` |
| E25 | [scripts/player/player.gd:1414](../scripts/player/player.gd#L1414) — `func _set_seat_input(` |
| E26 | [autoload/lua_script_engine.gd:6894](../autoload/lua_script_engine.gd#L6894) — `func activate_local_tool(` |
| E27 | [autoload/lua_script_engine.gd:7242](../autoload/lua_script_engine.gd#L7242) — `func _position_equipped_tool(` |
| E28 | [addons/roblox_runtime/roblox_inventory_controller.gd:307](../addons/roblox_runtime/roblox_inventory_controller.gd#L307) — `button.tooltip_text` |
| E29 | [autoload/lua_script_engine.gd:6695](../autoload/lua_script_engine.gd#L6695) — `func refresh_local_team_spawns(` |
| E30 | [autoload/lua_script_engine.gd:7053](../autoload/lua_script_engine.gd#L7053) — `func humanoid_is_forcefield_protected(` |
| E31 | [autoload/lua_script_engine.gd:6587](../autoload/lua_script_engine.gd#L6587) — `func bind_local_player_character(` |
| E32 | [autoload/lua_script_engine.gd:6630](../autoload/lua_script_engine.gd#L6630) — `func bind_network_player_character(` |
| E33 | [autoload/lua_script_engine.gd:2646](../autoload/lua_script_engine.gd#L2646) — `func GetMouse(` |
| E34 | [autoload/lua_script_engine.gd:2635](../autoload/lua_script_engine.gd#L2635) — `func LoadCharacter(` |
| E35 | [autoload/lua_script_engine.gd:6968](../autoload/lua_script_engine.gd#L6968) — `func unbind_local_player_character(` |
| E36 | [autoload/lua_script_engine.gd:2586](../autoload/lua_script_engine.gd#L2586) — `func GetPlayers(` |
| E37 | [autoload/lua_script_engine.gd:1038](../autoload/lua_script_engine.gd#L1038) — `"CurrentCamera":` |
| E38 | [autoload/lua_script_engine.gd:1014](../autoload/lua_script_engine.gd#L1014) — `prop_str == "Gravity"` |
| E39 | [autoload/lua_script_engine.gd:7005](../autoload/lua_script_engine.gd#L7005) — `func _input(` |
| E40 | [autoload/lua_script_engine.gd:1455](../autoload/lua_script_engine.gd#L1455) — `"RotVelocity", "AssemblyAngularVelocity"` |
| E41 | [addons/roblox_runtime/roblox_part_physics.gd:76](../addons/roblox_runtime/roblox_part_physics.gd#L76) — `func refresh_properties(` |
| E42 | [autoload/lua_script_engine.gd:2684](../autoload/lua_script_engine.gd#L2684) — `func GetMass(` |
| E43 | [addons/roblox_runtime/roblox_part_physics.gd:130](../addons/roblox_runtime/roblox_part_physics.gd#L130) — `func _deliver_touch(` |
| E44 | [addons/roblox_runtime/roblox_part_physics.gd:124](../addons/roblox_runtime/roblox_part_physics.gd#L124) — `func _on_body_entered(` |
| E45 | [addons/roblox_runtime/roblox_joint_runtime.gd:42](../addons/roblox_runtime/roblox_joint_runtime.gd#L42) — `wrapper._get(&"Transform")` |
| E46 | [autoload/lua_script_engine.gd:1090](../autoload/lua_script_engine.gd#L1090) — `"CFrame":` |
| E47 | [addons/roblox_runtime/roblox_joint_runtime.gd:16](../addons/roblox_runtime/roblox_joint_runtime.gd#L16) — `func _refresh(` |
| E48 | [autoload/lua_script_engine.gd:1408](../autoload/lua_script_engine.gd#L1408) — `"CameraType":` |
| E49 | [autoload/lua_script_engine.gd:2806](../autoload/lua_script_engine.gd#L2806) — `func ScreenPointToRay(` |
| E50 | [autoload/lua_script_engine.gd:1304](../autoload/lua_script_engine.gd#L1304) — `func _set_impl(` |
| E51 | [autoload/lua_script_engine.gd:1892](../autoload/lua_script_engine.gd#L1892) — `func FindFirstChild(` |
| E52 | [autoload/lua_script_engine.gd:2456](../autoload/lua_script_engine.gd#L2456) — `func GetAttribute(` |
| E53 | [autoload/lua_script_engine.gd:775](../autoload/lua_script_engine.gd#L775) — `func _init(n: Node)` |
| E54 | [autoload/lua_script_engine.gd:2856](../autoload/lua_script_engine.gd#L2856) — `func PivotTo(` |
| E55 | [autoload/lua_script_engine.gd:1057](../autoload/lua_script_engine.gd#L1057) — `"ClassName", "className"` |
| E56 | [autoload/lua_script_engine.gd:2089](../autoload/lua_script_engine.gd#L2089) — `func IsA(` |
| E57 | [autoload/lua_script_engine.gd:2827](../autoload/lua_script_engine.gd#L2827) — `func GetPivot(` |
| E58 | [autoload/lua_script_engine.gd:1620](../autoload/lua_script_engine.gd#L1620) — `"Shape":` |
| E59 | [autoload/lua_script_engine.gd:2214](../autoload/lua_script_engine.gd#L2214) — `func Raycast(` |
| E60 | [autoload/lua_script_engine.gd:2261](../autoload/lua_script_engine.gd#L2261) — `func GetPartBoundsInBox(` |

| Тест | Существующий файл | Выполнение здесь |
|---|---|---|
| T01 | [tools/validate_humanoid_player_contract.gd](../tools/validate_humanoid_player_contract.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T02 | [tools/validate_humanoid_npc_contract.gd](../tools/validate_humanoid_npc_contract.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T03 | [tools/validate_humanoid_commands.gd](../tools/validate_humanoid_commands.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T04 | [tools/validate_seat_authority.gd](../tools/validate_seat_authority.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T05 | [tools/validate_roblox_inventory_runtime.gd](../tools/validate_roblox_inventory_runtime.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T06 | [tools/validate_imported_physics.gd](../tools/validate_imported_physics.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T07 | [tools/validate_studio_respawn_checkpoint.gd](../tools/validate_studio_respawn_checkpoint.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T08 | [tools/validate_lua_input.gd](../tools/validate_lua_input.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T09 | [tools/validate_lua_cframe_runtime.gd](../tools/validate_lua_cframe_runtime.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T10 | [tools/validate_lua_service_compatibility.gd](../tools/validate_lua_service_compatibility.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T11 | [tools/validate_halloween_spatial_contract.gd](../tools/validate_halloween_spatial_contract.gd) | NOT_RUN; scoped assertions, не полный контракт |
| T12 | [tools/validate_render_batches.gd](../tools/validate_render_batches.gd) | NOT_RUN; scoped assertions, не полный контракт |

## Полная таблица собственных публичных членов

Унаследованные строки искать по цепочке `inherits`; общий Instance API не дублируется 69 раз. Колбэки сохранены так же, как методы/события; если в YAML класса публичных callbacks нет, вымышленные не добавлены.

### Humanoid

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Humanoid.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AutoJumpEnabled: boolean` | нет | E01 | — | нет | высоко | Свойство хранится/читается; полноценный mobile AutoJump или смерть от отсутствующего Neck не реализованы этим маршрутом. |
| P `AutomaticScalingEnabled: boolean` | нет | E02 | 01:1,07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AutoRotate: boolean` | частично | E03 | 02:1,07:1,08:1,09:2,12:1,13:1,14:1,20:1 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `BreakJointsOnDeath: boolean` | частично | E04 | 01:2,09:2 | T01 | высоко | Сохраняет/разбирает собственный visual rig; не Roblox физическое разрывание всех Motor6D. |
| P `CameraOffset: Vector3` | нет | E05 | 01:2,07:1,08:2,09:2,12:1,13:2,20:2 | нет | высоко | Getter читает metadata; player camera не использует Humanoid.CameraOffset, поэтому сохранение значения не camera parity. |
| P `CollisionType: HumanoidCollisionType` [write:PluginSecurity, Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DisplayDistanceType: HumanoidDisplayDistanceType` | нет | E02 | 00:2,01:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DisplayName: string` | частично | E06 | 00:12,01:2,08:4,09:26,16:1 | нет | высоко | NPC health label читает имя; все Roblox name-display distance/occlusion правила не восстановлены. |
| P `EvaluateStateMachine: boolean` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FloorMaterial: Material` [ReadOnly, NotReplicated] | частично | E07 | 00:2,07:1,14:2 | нет | высоко | Player floor sampling есть; NPC, enum-представление и смена материалов имеют неполное покрытие. |
| P `Health: float` [NotReplicated] | частично | E08 | 00:237,01:27,02:7,03:9,04:9,05:2,06:9,07:2,08:1,09:36,10:8,11:8,12:3,13:943,14:8,15:8,16:18,17:7,18:104,19:169,20:20 | T01,T02,T03 | критично | Дробные значения и +Inf логически поддержаны; NaN/-Inf намеренно отклонены. Lifecycle и порядок всех Roblox-событий не доказаны. |
| P `HealthDisplayDistance: float` | нет | E02 | 20:8 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HealthDisplayType: HumanoidHealthDisplayType` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HipHeight: float` | частично | E03 | 00:3,01:2,02:1,07:1,08:1,09:2,16:1 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `Jump: boolean` [NotReplicated] | частично | E09 | 00:4,01:6,02:3,03:1,04:1,05:1,07:4,08:3,09:9,12:4,13:96,16:2,18:6,19:4,20:4 | T01,T02 | высоко | Есть физический маршрут и state bridge; не все состояния, owner-side ограничения и восстановление измерены. |
| P `JumpHeight: float` | частично | E03 | 00:2,01:4,07:3,09:3 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `JumpPower: float` | частично | E03 | 00:2,01:3,07:5,08:2,09:5,14:2 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `LeftLeg: BasePart` [Hidden, NotReplicated, Deprecated] | нет | E02 | 01:2,02:2,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MaxHealth: float` | частично | E08 | 00:4,01:6,03:1,04:1,09:1,10:1,11:1,13:22,14:4,17:1,18:15,19:5,20:3 | T01,T02,T03 | высоко | Дробные значения и +Inf логически поддержаны; NaN/-Inf намеренно отклонены. Lifecycle и порядок всех Roblox-событий не доказаны. |
| P `maxHealth: float` [NotReplicated, Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MaxSlopeAngle: float` | частично | E10 | 00:1 | T02 | высоко | Getter/setter и numeric guard; 89° cap отличается от наблюдённого верхнего Roblox 89.9°. Полная slope-матрица отсутствует. |
| P `MoveDirection: Vector3` [ReadOnly, NotReplicated] | частично | E11 | 00:1,01:1,06:2,07:1,08:1,09:4,16:1 | T01,T02 | высоко | Живое направление/HRP прокси R6; не полная многотельная assembly/R15. |
| P `NameDisplayDistance: float` | нет | E02 | 20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NameOcclusion: NameOcclusion` | нет | E02 | 17:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PlatformStand: boolean` | частично | E09 | 00:6,07:1,09:8,12:2,13:1,16:3,19:1,20:4 | T01,T02 | высоко | Есть физический маршрут и state bridge; не все состояния, owner-side ограничения и восстановление измерены. |
| P `RequiresNeck: boolean` | нет | E01 | 07:1 | нет | высоко | Свойство хранится/читается; полноценный mobile AutoJump или смерть от отсутствующего Neck не реализованы этим маршрутом. |
| P `RightLeg: BasePart` [Hidden, NotReplicated, Deprecated] | нет | E02 | 01:2,02:2,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RigType: HumanoidRigType` | частично | E12 | 00:4,01:6,02:2,07:1,08:1,09:2,16:4 | T02 | высоко | R6/R15 label читается; R15 риг и масштабирование не реализованы этим getter. |
| P `RootPart: BasePart` [ReadOnly, NotReplicated] | частично | E11 | 00:2,01:23,02:1,07:10,08:10,09:15 | T01,T02 | высоко | Живое направление/HRP прокси R6; не полная многотельная assembly/R15. |
| P `SeatPart: BasePart` [ReadOnly, NotReplicated] | частично | E13 | 00:2,01:3,02:4,07:1,08:1,09:1 | T01,T04 | высоко | Occupancy reference и Seated bridge; NPC seat motor и все случаи удаления/движения ещё требуют проверки. |
| P `Sit: boolean` | частично | E09 | 00:2,01:4,02:3,03:1,04:1,07:1,08:3,09:5,12:1,13:97,16:2,18:7,19:4,20:2 | T01,T02 | высоко | Есть физический маршрут и state bridge; не все состояния, owner-side ограничения и восстановление измерены. |
| P `TargetPoint: Vector3` | нет | E02 | 00:2,01:1,07:1,08:1,09:2,13:5,14:1,17:4,18:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Torso: BasePart` [Hidden, NotReplicated, Deprecated] | нет | E02 | 00:2,01:5,02:1,03:1,04:1,05:1,07:4,08:5,09:9,10:1,11:1,12:14,13:109,14:2,16:2,17:1,18:33,19:16,20:32 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `UseJumpPower: boolean` | частично | E03 | 09:1 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `WalkSpeed: float` | частично | E03 | 00:10,01:10,02:1,03:1,04:1,06:7,07:4,08:2,09:8,12:1,13:18,14:5,16:9,18:20,19:10,20:9 | T01,T02,T03 | высоко | Есть реальный player/NPC motor; физика, коллизии и поворот инженерные. Калибровка R6 не доказательство R15/всех FPS; неконечные actuators запрещены. |
| P `WalkToPart: BasePart` | частично | E14 | — | T01,T02,T03 | высоко | MoveTo обновляет поля и moving target. Прямое присваивание этих полей не равно запуску цели. |
| P `WalkToPoint: Vector3` | частично | E14 | — | T01,T02,T03 | высоко | MoveTo обновляет поля и moving target. Прямое присваивание этих полей не равно запуску цели. |
| M `AddAccessory(accessory:Instance) → ()` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `AddCustomStatus(status:string) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `AddStatus(status:Status) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyDescription(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` [Deprecated] | нет | E02 | 00:5,01:2,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyDescriptionAsync(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyDescriptionReset(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` [Deprecated] | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyDescriptionResetAsync(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BuildRigFromAttachments() → ()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ChangeState(state:HumanoidStateType) → ()` | частично | E15 | 00:3,01:2,06:2,07:1,09:4,13:1,14:1 | T01,T02,T03 | критично | 17 state IDs и live motor; специальные состояния не все имеют физическое Roblox-поведение. Baseline возвращает числовые enum. |
| M `EquipTool(tool:Instance) → ()` | частично | E16 | 00:6,01:5,09:5 | T05 | высоко | Реальный inventory reparent/event маршрут; полные Tool constraints/right grip/replication не доказаны. |
| M `GetAccessories() → Array` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetAppliedDescription() → HumanoidDescription` | нет | E02 | 00:1,01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetBodyPartR15(part:Instance) → BodyPartR15` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetLimb(part:Instance) → Limb` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMoveVelocity() → Vector3` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPlayingAnimationTracks() → Array` [Deprecated] | нет | E02 | 01:1,06:7,07:3,08:1,09:1,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRelativeVelocityAtFloor() → Vector3` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetState() → HumanoidStateType` | частично | E15 | 00:1,01:10,06:3,07:7,08:10,09:10,12:2,20:2 | T01,T02,T03 | критично | 17 state IDs и live motor; специальные состояния не все имеют физическое Roblox-поведение. Baseline возвращает числовые enum. |
| M `GetStateEnabled(state:HumanoidStateType) → boolean` | частично | E15 | 01:1,07:1,08:1,09:1 | T01,T02,T03 | высоко | 17 state IDs и live motor; специальные состояния не все имеют физическое Roblox-поведение. Baseline возвращает числовые enum. |
| M `GetStatuses() → Array` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `HasCustomStatus(status:string) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `HasStatus(status:Status) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadAnimation(animation:Animation) → AnimationTrack` [Deprecated] | нет | E17 | 00:10,01:12,06:11,07:11,08:5,09:50,12:7,13:13,14:1,16:41,18:2,20:7 | нет | критично | Возвращает новый BobuxAnimationTrack без загрузки AnimationId/ключей и без связи с ригом: заглушка, не проигрывание. |
| M `loadAnimation(animation:Animation) → AnimationTrack` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Move(moveDirection:Vector3, relativeToCamera:boolean) → ()` | частично | E18 | 00:8,01:2,02:4,07:2,08:3,09:12,12:6,13:1,18:10,20:8 | T01,T02,T03 | критично | Реальное движение, camera-relative и moving-part цель/timeout; разные player/NPC motors и нет полной obstacle/autojump parity. |
| M `MoveTo(location:Vector3, part:Instance) → ()` | частично | E18 | 00:3,01:1,02:1,03:1,04:1,05:1,07:1,08:22,09:5,12:1,13:523,14:1,16:13,18:5,19:4,20:1 | T01,T02,T03 | критично | Реальное движение, camera-relative и moving-part цель/timeout; разные player/NPC motors и нет полной obstacle/autojump parity. |
| M `PlayEmote(emoteName:string) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `PlayEmoteAsync(emoteName:string) → boolean` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemoveAccessories() → ()` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemoveCustomStatus(status:string) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemoveStatus(status:Status) → boolean` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ReplaceBodyPartR15(bodyPart:BodyPartR15, part:BasePart) → boolean` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetStateEnabled(state:HumanoidStateType, enabled:boolean) → ()` | частично | E15 | 00:1,02:1 | T01,T02,T03 | высоко | 17 state IDs и live motor; специальные состояния не все имеют физическое Roblox-поведение. Baseline возвращает числовые enum. |
| M `TakeDamage(amount:float) → ()` | частично | E19 | 00:8,01:10,07:2,09:6,10:4,11:4,13:7,17:3,18:5,19:2,20:5 | T02 | критично | Есть fractional damage/heal, hierarchy ForceField, death; NaN/Inf damage guard и весь lifecycle отличаются. |
| M `takeDamage(amount:float) → ()` [Deprecated] | нет | E02 | 18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnequipTools() → ()` | частично | E16 | 01:9,02:1,08:4,09:4 | T05 | высоко | Реальный inventory reparent/event маршрут; полные Tool constraints/right grip/replication не доказаны. |
| E `AnimationPlayed(animationTrack:AnimationTrack)` [Deprecated] | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `ApplyDescriptionFinished(description:HumanoidDescription)` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Climbing(speed:float)` | частично | E20 | 01:2,06:4,07:4,08:3,09:2,12:3,14:2,16:15,17:1,18:1,20:5 | T01,T02,T03 | критично | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `CustomStatusAdded(status:string)` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `CustomStatusRemoved(status:string)` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Died()` | частично | E20 | 00:3,01:13,03:1,04:1,06:6,07:4,08:4,09:5,10:3,11:3,12:7,13:3,14:3,15:1,16:39,17:2,18:2,19:2,20:15 | T01,T02,T03 | критично | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `FallingDown(active:boolean)` | частично | E21 | 00:2,01:1,06:4,07:4,08:3,09:2,12:2,14:3,16:24,17:1,18:1,20:4 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `FreeFalling(active:boolean)` | частично | E21 | 01:1,06:4,07:4,08:3,09:2,12:1,14:3,16:24,17:1,18:1,20:3 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `GettingUp(active:boolean)` | частично | E21 | 00:2,01:1,06:4,07:3,08:2,09:3,12:2,13:1,14:3,16:24,17:1,18:1,20:4 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `HealthChanged(health:float)` | частично | E20 | 00:2,01:1,20:1 | T01,T02,T03 | высоко | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `Jumping(active:boolean)` | частично | E21 | 00:3,01:3,02:1,05:1,06:7,07:6,08:4,09:5,10:1,11:1,12:1,14:5,16:24,17:1,18:1,20:3 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `MoveToFinished(reached:boolean)` | частично | E20 | 09:1,16:1 | T01,T02,T03 | высоко | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `PlatformStanding(active:boolean)` | частично | E21 | 06:4,07:3,08:1,14:1,16:23,20:1 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `Ragdoll(active:boolean)` | частично | E21 | 00:2,01:6,07:3,09:35,12:1,20:2 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `Running(speed:float)` | частично | E20 | 00:8,01:1,06:4,07:3,08:2,09:8,12:7,14:5,16:25,17:1,18:1,20:9 | T01,T02,T03 | высоко | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `Seated(active:boolean, currentSeatPart:BasePart)` | частично | E21 | 01:3,06:4,07:5,08:4,09:3,12:2,14:2,16:23,17:1,18:1,20:4 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `StateChanged(old:HumanoidStateType, new:HumanoidStateType)` | частично | E21 | 00:2,01:2,06:1,08:2,09:3,12:1,20:2 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `StateEnabledChanged(state:HumanoidStateType, isEnabled:boolean)` | частично | E21 | 01:1,07:1,08:1,09:1 | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `StatusAdded(status:Status)` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `StatusRemoved(status:Status)` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Strafing(active:boolean)` | частично | E21 | — | T01,T02 | высоко | Есть entry/exit сигналы и Seated(false,nil); время/порядок всех переходов/EnumItem representation не полностью подтверждены. |
| E `Swimming(speed:float)` | частично | E20 | 01:2,06:4,07:4,08:3,09:2,12:2,16:19,20:4 | T01,T02,T03 | высоко | Сигналы идут от живого motor. Есть scoped assertions; не автоматический PASS для полного публичного контракта. |
| E `Touched(touchingPart:BasePart, humanoidPart:BasePart)` | нет | E02 | 00:235,01:11,02:1,03:53,04:53,05:3,06:2,07:3,08:6,09:11,10:6,11:6,13:865,14:2,15:9,16:34,17:6,18:158,19:174,20:28 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### HumanoidDescription

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/HumanoidDescription.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccessoryBlob: string` [NotReplicated, NotScriptable] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `BackAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `BodyTypeScale: float` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `ClimbAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `DepthScale: float` | нет | E02 | 00:2 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `Face: int64` | нет | E02 | 00:15,01:1,02:3,06:1,08:2,09:8,13:3,16:1,18:1,20:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `FaceAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `FallAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `FrontAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `GraphicTShirt: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `HairAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `HatAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `Head: int64` [NotReplicated] | нет | E02 | 00:5,01:15,02:7,03:1,04:1,07:3,08:9,09:5,10:2,11:2,12:3,13:11,14:4,16:26,17:4,18:17,19:9,20:28 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `HeadColor: Color3` [NotReplicated] | нет | E02 | 20:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `HeadScale: float` | нет | E02 | 00:4,02:1,07:4,08:4,09:6,16:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `HeightScale: float` | нет | E02 | 00:2 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `IdleAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `JumpAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `LeftArm: int64` [NotReplicated] | нет | E02 | 01:1,02:2,18:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `LeftArmColor: Color3` [NotReplicated] | нет | E02 | 20:5 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `LeftLeg: int64` [NotReplicated] | нет | E02 | 01:2,02:2,18:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `LeftLegColor: Color3` [NotReplicated] | нет | E02 | 20:5 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `MoodAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `NeckAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `Pants: int64` | нет | E02 | 00:2,01:4,16:3,18:1,20:4 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `ProportionScale: float` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `RightArm: int64` [NotReplicated] | нет | E02 | 01:1,02:2,18:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `RightArmColor: Color3` [NotReplicated] | нет | E02 | 20:5 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `RightLeg: int64` [NotReplicated] | нет | E02 | 01:2,02:2,18:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `RightLegColor: Color3` [NotReplicated] | нет | E02 | 20:5 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `RunAnimation: int64` | нет | E02 | 16:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `Shirt: int64` | нет | E02 | 00:2,01:4,16:3,18:1,20:4 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `ShouldersAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `StaticFacialAnimation: boolean` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `SwimAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `Torso: int64` [NotReplicated] | нет | E02 | 00:2,01:5,02:1,03:1,04:1,05:1,07:4,08:5,09:9,10:1,11:1,12:14,13:109,14:2,16:2,17:1,18:33,19:16,20:32 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `TorsoColor: Color3` [NotReplicated] | нет | E02 | 20:5 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `UseAvatarSettings: boolean` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `WaistAccessory: string` [NotReplicated] | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `WalkAnimation: int64` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| P `WidthScale: float` | нет | E02 | 00:3,08:1 | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `AddEmote(name:string, assetId:int64) → ()` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `GetAccessories(includeRigidAccessories:boolean) → List<AccessoriesInfo>` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `GetEmotes() → Dictionary` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `GetEquippedEmotes() → Array` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `RemoveEmote(name:string) → ()` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `SetAccessories(accessories:Array, includeRigidAccessories:boolean) → ()` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `SetEmotes(emotes:Dictionary) → ()` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| M `SetEquippedEmotes(equippedEmotes:Array) → ()` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| E `EmotesChanged(newEmotes:Dictionary)` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |
| E `EquippedEmotesChanged(newEquippedEmotes:Array)` | нет | E02 | — | нет | высоко | Metadata container не применяет Roblox avatar description, scaling/body parts/accessory pipeline. |

### Animator

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Animator.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `EvaluationThrottled: boolean` [ReadOnly, NotReplicated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PreferLodEnabled: boolean` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyJointVelocities(motors:Variant) → ()` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPlayingAnimationTracks() → Array` | нет | E02 | 01:1,06:7,07:3,08:1,09:1,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetTrackByAnimationId(animationId:ContentId) → AnimationTrack?` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadAnimation(animation:Animation) → AnimationTrack` | нет | E17 | 00:10,01:12,06:11,07:11,08:5,09:50,12:7,13:13,14:1,16:41,18:2,20:7 | нет | критично | Общий метод возвращает bookkeeping track; ключи, rig playback, priority, fade и репликация отсутствуют. |
| M `StepAnimations(deltaTime:float) → ()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `AnimationPlayed(animationTrack:AnimationTrack)` | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### AnimationTrack

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AnimationTrack.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Animation: Animation` [ReadOnly, NotReplicated] | нет | E02 | 00:3,01:4,06:2,08:2,09:4,13:3,14:2,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `IsPlaying: boolean` [ReadOnly, NotReplicated] | частично | E22 | 00:1,01:4,02:1,06:2,07:1,08:2,09:8,12:4,13:1,16:6,20:3 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| P `Length: float` [ReadOnly, NotReplicated] | нет | E02 | 00:2,01:6,06:2,08:1,09:7,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Looped: boolean` | частично | E22 | 00:1,01:10,06:5,07:1,08:4,09:27,12:6,13:13,14:1,15:1,16:3,18:1,20:6 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| P `Priority: AnimationPriority` | нет | E02 | 01:9,02:1,06:11,07:10,08:2,09:6,16:22 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Speed: float` [ReadOnly, NotReplicated] | частично | E22 | 00:2,01:13,07:1,08:3,09:5,13:3,14:2,18:1,20:1 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| P `TimePosition: float` [NotReplicated] | нет | E02 | 00:1,02:1,08:32,09:5,16:26 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WeightCurrent: float` [ReadOnly, NotReplicated] | частично | E22 | — | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| P `WeightTarget: float` [ReadOnly, NotReplicated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `AdjustSpeed(speed:float) → ()` | частично | E22 | 00:1,06:6,07:7,08:2,09:4,14:1,16:23,20:2 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| M `AdjustWeight(weight:float, fadeTime:float) → ()` | частично | E22 | 01:1,14:1,16:22 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| M `GetMarkerReachedSignal(name:string) → RBXScriptSignal` | нет | E02 | 09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetParameter(key:string) → Variant` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetParameterDefaults() → Dictionary` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetTimeOfKeyframe(keyframeName:string) → double` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Play(fadeTime:float, weight:float, speed:float) → ()` | частично | E22 | 00:409,01:167,02:36,05:1,06:15,07:12,08:93,09:96,10:7,11:7,12:38,13:230,14:8,16:84,17:2,18:13,19:1,20:40 | нет | критично | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| M `SetParameter(key:string, value:Variant) → ()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Stop(fadeTime:float) → ()` | частично | E22 | 00:40,01:21,02:10,06:12,07:13,08:22,09:59,12:18,13:38,14:2,16:50,18:4,20:19 | нет | критично | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |
| E `DidLoop()` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Ended()` | нет | E02 | 01:1,09:2,10:2,11:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `KeyframeReached(keyframeName:string)` | нет | E22 | 01:1,06:4,07:6,08:1,16:23,20:1 | нет | высоко | Сигнал существует, но track не читает keyframes и не производит событие по анимации. |
| E `Stopped()` | частично | E22 | 00:4,01:2,09:5,14:1 | нет | высоко | Меняются только bookkeeping поля; Stop отправляет сигнал. Нет pose playback/fade/blending/time progression. |

### Animation

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Animation.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AnimationContent: Content` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AnimationId: ContentId` | нет | E17 | 01:5,06:13,07:4,08:2,09:28,12:7,13:1,14:1,16:24,20:5 | нет | высоко | Сохраняемое metadata значение не используется LoadAnimation для проигрывания. |

### AnimationController

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AnimationController.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| M `GetPlayingAnimationTracks() → Array` [Deprecated] | нет | E02 | 01:1,06:7,07:3,08:1,09:1,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadAnimation(animation:Animation) → AnimationTrack` [Deprecated] | нет | E17 | 00:10,01:12,06:11,07:11,08:5,09:50,12:7,13:13,14:1,16:41,18:2,20:7 | нет | критично | Тот же bookkeeping stub; не Animator/AnimationController pipeline. |
| E `AnimationPlayed(animationTrack:AnimationTrack)` [Deprecated] | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Seat

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Seat.yaml). inherits: `Part`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Disabled: boolean` | частично | E23 | 00:13,01:18,02:4,03:18,04:18,05:2,08:1,09:2,10:3,11:3,13:428,14:3,15:1,16:10,17:6,18:31,19:8,20:6 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |
| P `Occupant: Humanoid` [ReadOnly, NotReplicated] | частично | E23 | 01:2,02:1,07:2,08:2,09:2 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |
| M `Sit(humanoid:Instance) → ()` | частично | E23 | 00:2,01:4,02:3,03:1,04:1,07:1,08:3,09:5,12:1,13:97,16:2,18:7,19:4,20:2 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |

### VehicleSeat

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/VehicleSeat.yaml). inherits: `BasePart`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AreHingesDetected: int` [ReadOnly, NotReplicated] | частично | E24 | — | T06 | средне | Читаются legacy vehicle/hinge адаптером; силовая модель и типы assemblies ограничены. |
| P `Disabled: boolean` | частично | E23 | 00:13,01:18,02:4,03:18,04:18,05:2,08:1,09:2,10:3,11:3,13:428,14:3,15:1,16:10,17:6,18:31,19:8,20:6 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |
| P `HeadsUpDisplay: boolean` | нет | E02 | — | нет | средне | Metadata не рисует штатный Roblox VehicleSeat HUD. |
| P `MaxSpeed: float` | частично | E24 | 00:8,01:1,02:1,07:1,08:2,09:3,19:1 | T06 | высоко | Читаются legacy vehicle/hinge адаптером; силовая модель и типы assemblies ограничены. |
| P `Occupant: Humanoid` [ReadOnly, NotReplicated] | частично | E23 | 01:2,02:1,07:2,08:2,09:2 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |
| P `Steer: int` [NotReplicated] | частично | E25 | 12:1,20:2 | T06 | высоко | Ввод живого игрока и RPC; физика vehicle motor собственная, точная wheel/torque parity не установлена. |
| P `SteerFloat: float` | частично | E25 | 01:1,02:1,07:1,08:1,09:1 | T06 | высоко | Ввод живого игрока и RPC; физика vehicle motor собственная, точная wheel/torque parity не установлена. |
| P `Throttle: int` [NotReplicated] | частично | E25 | 12:1,20:2 | T06 | высоко | Ввод живого игрока и RPC; физика vehicle motor собственная, точная wheel/torque parity не установлена. |
| P `ThrottleFloat: float` | частично | E25 | 01:1,02:1,07:1,08:1,09:1 | T06 | высоко | Ввод живого игрока и RPC; физика vehicle motor собственная, точная wheel/torque parity не установлена. |
| P `Torque: float` | частично | E24 | 00:5,09:2 | T06 | высоко | Читаются legacy vehicle/hinge адаптером; силовая модель и типы assemblies ограничены. |
| P `TurnSpeed: float` | частично | E24 | 00:4,09:2 | T06 | высоко | Читаются legacy vehicle/hinge адаптером; силовая модель и типы assemblies ограничены. |
| M `Sit(humanoid:Instance) → ()` | частично | E23 | 00:2,01:4,02:3,03:1,04:1,07:1,08:3,09:5,12:1,13:97,16:2,18:7,19:4,20:2 | T06,T04 | высоко | Реальная посадка, SeatWeld/Occupant/jump exit и network authority; не все NPC/moving-seat physics случаи измерены. |

### Tool

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Tool.yaml). inherits: `BackpackItem`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `CanBeDropped: boolean` | нет | E26 | 00:1,20:2 | нет | высоко | Defaults/metadata есть, но activation helper не применяет все эти gates/правила Tool. |
| P `Enabled: boolean` | нет | E26 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | нет | высоко | Defaults/metadata есть, но activation helper не применяет все эти gates/правила Tool. |
| P `Grip: CFrame` | частично | E27 | 00:1,01:7,08:2,09:1,13:6,20:2 | нет | высоко | Собственная установка Handle позы; не полноценный RightGrip/Motor6D animation pipeline. |
| P `GripForward: Vector3` [Hidden, NotReplicated] | частично | E27 | 05:1,10:1,11:1,13:39,16:5,17:1,18:7,19:1 | нет | высоко | Собственная установка Handle позы; не полноценный RightGrip/Motor6D animation pipeline. |
| P `GripPos: Vector3` [Hidden, NotReplicated] | частично | E27 | 05:1,13:33,16:5,18:3 | нет | высоко | Собственная установка Handle позы; не полноценный RightGrip/Motor6D animation pipeline. |
| P `GripRight: Vector3` [Hidden, NotReplicated] | нет | E02 | 05:1,10:1,11:1,13:38,16:5,17:1,18:7,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `GripUp: Vector3` [Hidden, NotReplicated] | частично | E27 | 05:1,10:1,11:1,13:38,16:5,17:1,18:7,19:1 | нет | высоко | Собственная установка Handle позы; не полноценный RightGrip/Motor6D animation pipeline. |
| P `ManualActivationOnly: boolean` | нет | E26 | 01:2,07:1,08:1,09:1,12:1,20:1 | нет | высоко | Defaults/metadata есть, но activation helper не применяет все эти gates/правила Tool. |
| P `RequiresHandle: boolean` | нет | E26 | 09:1,16:21 | нет | высоко | Defaults/metadata есть, но activation helper не применяет все эти gates/правила Tool. |
| P `ToolTip: string` | частично | E28 | 01:1,08:2,09:1 | T05 | высоко | Inventory UI читает tooltip; desktop/mobile parity и все live property обновления не доказаны. |
| M `Activate() → ()` | нет | E26 | 00:2,01:7,07:1,08:2,09:16,12:1,16:3,20:1 | нет | высоко | Native inventory helper есть, публичных Tool:Activate/Deactivate методов нет. |
| M `Deactivate() → ()` | нет | E26 | 01:3 | нет | высоко | Native inventory helper есть, публичных Tool:Activate/Deactivate методов нет. |
| E `Activated()` | частично | E26 | 00:47,01:83,02:2,06:1,08:16,09:55,10:13,11:13,13:59,14:3,16:15,17:3,18:15,19:4 | T05 | высоко | События inventory маршрута; не весь Enabled/RequiresHandle/drop/deactivation контракт. |
| E `Deactivated()` | нет | E02 | 01:4,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Equipped(mouse:Mouse)` | частично | E26 | 00:19,01:20,05:2,08:14,09:54,10:8,11:8,12:15,13:60,14:10,16:15,17:4,18:27,19:4,20:25 | T05 | высоко | События inventory маршрута; не весь Enabled/RequiresHandle/drop/deactivation контракт. |
| E `Unequipped()` | частично | E26 | 00:16,01:19,05:2,08:13,09:20,10:6,11:6,13:42,14:5,16:8,18:15,19:2,20:2 | T05 | высоко | События inventory маршрута; не весь Enabled/RequiresHandle/drop/deactivation контракт. |

### Accessory

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Accessory.yaml). inherits: `Accoutrement`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccessoryType: AccessoryType` | нет | E02 | 00:3,02:1,08:1,09:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### TrussPart

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/TrussPart.yaml). inherits: `BasePart`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Style: Style` [NotReplicated] | нет | E02 | 00:166,01:155,08:1,09:6,12:26,18:1,20:18 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### SpawnLocation

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/SpawnLocation.yaml). inherits: `Part`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AllowTeamChangeOnTouch: boolean` | нет | E29 | — | нет | средне | Нет spawn ForceField duration и team-change-on-touch маршрута в этой реализации. |
| P `Duration: int` | нет | E29 | 00:3,01:2,02:1,09:6 | нет | высоко | Нет spawn ForceField duration и team-change-on-touch маршрута в этой реализации. |
| P `Enabled: boolean` | частично | E29 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | нет | высоко | Выбор team/neutral spawn и RespawnLocation; без доказанного Roblox spawn распределения/lifecycle. |
| P `Neutral: boolean` | частично | E29 | 00:5,01:3,10:3,11:3,13:5,14:1,17:2,18:1 | нет | высоко | Выбор team/neutral spawn и RespawnLocation; без доказанного Roblox spawn распределения/lifecycle. |
| P `TeamColor: BrickColor` | частично | E29 | 00:14,01:7,03:1,04:1,08:1,09:2,10:9,11:9,13:5,14:1,17:7,18:4,19:4 | нет | высоко | Выбор team/neutral spawn и RespawnLocation; без доказанного Roblox spawn распределения/lifecycle. |

### ForceField

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ForceField.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Visible: boolean` | нет | E30 | 00:322,01:34,02:17,05:1,06:6,07:7,08:60,09:95,10:8,11:8,12:74,13:32,14:5,16:9,17:1,18:10,19:16,20:71 | нет | высоко | Иерархическая защита Humanoid есть, но Visible не создаёт штатный ForceField эффект. |

### Player

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Player.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccountAge: int` [ReadOnly, NotReplicated] | нет | E02 | 00:3,01:3,17:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AgeChecked: AgeCheckStatus` [write:RobloxEngineSecurity] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AutoJumpEnabled: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMaxZoomDistance: float` | нет | E02 | 01:2,06:1,07:2,08:2,09:2,12:1,13:2,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMinZoomDistance: float` | нет | E02 | 01:2,02:1,06:1,07:2,08:2,09:2,12:5,13:7,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMode: CameraMode` | нет | E02 | 01:2,06:2,07:2,08:2,09:2,12:10,20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CanLoadCharacterAppearance: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Character: Model` | частично | E31 | 00:62,01:94,02:16,03:17,04:17,05:1,06:6,07:17,08:63,09:87,10:19,11:19,12:35,13:628,14:11,15:3,16:24,17:7,18:68,19:80,20:60 | T01,T03 | критично | Привязка/CharacterAdded работают; setter/новая модель/CharacterRemoving/номер жизни ещё неполны. |
| P `CharacterAppearance: string` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterAppearanceId: int64` | нет | E02 | 00:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DataComplexity: int` [Hidden, ReadOnly, NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DataReady: boolean` [Hidden, ReadOnly, NotReplicated, Deprecated] | нет | E02 | 05:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevCameraOcclusionMode: DevCameraOcclusionMode` | нет | E02 | 00:2,01:3,07:4,08:3,09:3,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevComputerCameraMode: DevComputerCameraMovementMode` | нет | E02 | 01:1,07:1,08:1,09:1,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevComputerMovementMode: DevComputerMovementMode` | нет | E02 | 01:2,07:2,08:2,09:2,12:3,14:1,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevEnableMouseLock: boolean` | нет | E02 | 00:2,01:1,07:1,08:1,09:2,12:1,14:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevTouchCameraMode: DevTouchCameraMovementMode` | нет | E02 | 01:1,07:1,08:1,09:1,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevTouchMovementMode: DevTouchMovementMode` | нет | E02 | 01:2,07:2,08:1,09:1,12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DisplayName: string` | частично | E32 | 00:12,01:2,08:4,09:26,16:1 | нет | высоко | Bobux account identity metadata; UserId может быть string, не Roblox numeric identity. |
| P `FollowUserId: int64` [ReadOnly, NotReplicated] | нет | E02 | 00:1,12:1,13:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FrustumStreaming: FrustumStreamingMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `GameplayPaused: boolean` [write:NotAccessibleSecurity, Hidden] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HasRobloxSubscription: boolean` [write:RobloxEngineSecurity] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HasVerifiedBadge: boolean` | нет | E02 | 00:1,08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HealthDisplayDistance: float` | нет | E02 | 20:8 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LocaleId: string` [Hidden, ReadOnly, NotReplicated] | нет | E02 | 00:1,01:1,08:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MembershipType: MembershipType` [ReadOnly, NotReplicated] | нет | E02 | 00:2,01:1,09:1,18:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NameDisplayDistance: float` | нет | E02 | 20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Neutral: boolean` | частично | E29 | 00:5,01:3,10:3,11:3,13:5,14:1,17:2,18:1 | T07 | высоко | Команды и team spawn selection; неполная история lifecycle и TeamColor тип/enum. |
| P `PartyId: string` [write:RobloxEngineSecurity, Hidden, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ReplicationFocus: Instance` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RespawnLocation: SpawnLocation` | частично | E29 | 01:2 | T07 | высоко | Команды и team spawn selection; неполная история lifecycle и TeamColor тип/enum. |
| P `Team: Team` [NotReplicated] | частично | E29 | 00:24,01:18,09:1,10:3,11:3 | T07 | высоко | Команды и team spawn selection; неполная история lifecycle и TeamColor тип/enum. |
| P `TeamColor: BrickColor` | частично | E29 | 00:14,01:7,03:1,04:1,08:1,09:2,10:9,11:9,13:5,14:1,17:7,18:4,19:4 | T07 | высоко | Команды и team spawn selection; неполная история lifecycle и TeamColor тип/enum. |
| P `User: User` [write:RobloxEngineSecurity] | нет | E02 | 00:2,01:11,16:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `UserId: int64` | частично | E32 | 00:39,01:26,02:4,06:3,08:17,09:73,10:4,11:4,12:1,14:6,16:10,20:3 | нет | высоко | Bobux account identity metadata; UserId может быть string, не Roblox numeric identity. |
| P `userId: int64` [Deprecated] | нет | E02 | 00:6,01:19,05:2,09:2,10:2,11:2,12:4,13:522,16:1,17:1,18:19,19:37,20:10 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `AddReplicationFocus(part:BasePart) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ClearCachedAvatarAppearance() → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ClearCharacterAppearance() → ()` | нет | E02 | 20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `DistanceFromCharacter(point:Vector3) → float` | нет | E02 | 00:1,08:1,10:2,11:2,12:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetCameraState() → CameraState` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetFriendsOnline(maxFriends:int) → Array` [Deprecated] | нет | E02 | 12:3,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetFriendsOnlineAsync(maxFriends:int) → Array` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetFriendsWhoPlayedAsync() → Array` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetJoinData() → Dictionary` | нет | E02 | 08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMouse() → Mouse` | частично | E33 | 00:20,01:15,02:1,07:1,08:23,09:15,10:8,11:8,12:8,13:6,14:2,16:3,20:9 | T08 | высоко | Собственный raycast/события mouse; не все Mouse/InputObject APIs, icon и lock modes. |
| M `GetNetworkPing() → float` | нет | E02 | 00:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRankInGroup(groupId:int64) → int` [Deprecated] | нет | E02 | 00:6,01:6,08:1,09:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRankInGroupAsync(groupId:int64) → int` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRoleInGroup(groupId:int64) → string` [Deprecated] | нет | E02 | 00:2,01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRoleInGroupAsync(groupId:int64) → string` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `HasAppearanceLoaded() → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsBestFriendsWith(userId:User) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsFriendsWith(userId:User) → boolean` [Deprecated] | нет | E02 | 00:4,01:1,02:1,08:1,09:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `isFriendsWith(userId:User) → boolean` [Deprecated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsFriendsWithAsync(userId:User) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsInGroup(groupId:int64) → boolean` [Deprecated] | нет | E02 | 00:5,01:3,02:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsInGroupAsync(groupId:int64) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsVerified(level:VerifiedLevel) → boolean` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Kick(message:string) → ()` | нет | E02 | 00:7,01:7,08:6,09:7,10:2,11:2,13:4,14:2,16:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadBoolean(key:string) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `loadBoolean(key:string) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadCharacter() → ()` [Deprecated] | частично | E34 | 00:4,01:7,09:2,10:2,11:2,13:2,20:3 | T01 | критично | Вызов существующего respawn, возможно повторное использование Godot Node; не полный Roblox LoadCharacter lifecycle. |
| M `LoadCharacterAppearance(assetInstance:Instance) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadCharacterAsync() → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadCharacterWithHumanoidDescription(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadCharacterWithHumanoidDescriptionAsync(humanoidDescription:HumanoidDescription, assetTypeVerification:AssetTypeVerification) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadInstance(key:string) → Instance` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `loadInstance(key:string) → Instance` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadNumber(key:string) → double` [Deprecated] | нет | E02 | 05:2,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `loadNumber(key:string) → double` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `LoadString(key:string) → string` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `loadString(key:string) → string` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Move(walkDirection:Vector3, relativeToCamera:boolean) → ()` | нет | E02 | 00:8,01:2,02:4,07:2,08:3,09:12,12:6,13:1,18:10,20:8 | нет | критично | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `PromptAgeCheck() → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemoveReplicationFocus(part:BasePart) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RequestStreamAroundAsync(position:Vector3, timeOut:double) → ()` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SaveBoolean(key:string, value:boolean) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `saveBoolean(key:string, value:boolean) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SaveInstance(key:string, value:Instance) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `saveInstance(key:string, value:Instance) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SaveNumber(key:string, value:double) → ()` [Deprecated] | нет | E02 | 05:1,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `saveNumber(key:string, value:double) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SaveString(key:string, value:string) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `saveString(key:string, value:string) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `WaitForDataReady() → boolean` [Deprecated] | нет | E02 | 13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `waitForDataReady() → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `CharacterAdded(character:Model)` | частично | E32 | 00:12,01:26,02:5,06:2,07:9,08:22,09:25,10:3,11:3,12:7,13:3,14:4,16:8,18:3,20:10 | T03 | критично | Реальный producer при bind; повторный respawn той же модели и порядок appearance events не доказаны. |
| E `CharacterAppearanceLoaded(character:Model)` | нет | E35 | 00:3,16:1 | нет | высоко | Публичное имя/сигнал не доказывает producer: unbind сейчас отправляет PlayerRemoving, не полный character lifecycle. |
| E `CharacterRemoving(character:Model)` | нет | E35 | 00:5,01:7,07:5,08:9,09:7,13:2 | нет | критично | Публичное имя/сигнал не доказывает producer: unbind сейчас отправляет PlayerRemoving, не полный character lifecycle. |
| E `Chatted(message:string, recipient:Player)` | нет | E02 | 00:3,01:3,03:1,04:1,06:4,07:3,08:2,09:1,12:8,13:1,14:1,16:1,18:5,19:6,20:12 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Idled(time:double)` | нет | E02 | 00:2,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `OnTeleport(teleportState:TeleportState, placeId:int64, spawnName:string)` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Players

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Players.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `BanningEnabled: boolean` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BubbleChat: boolean` [ReadOnly, NotReplicated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterAutoLoads: boolean` [NotReplicated] | нет | E31 | 20:1 | нет | высоко | Metadata не управляет автоматической загрузкой/временем респауна Roblox. |
| P `ClassicChat: boolean` [ReadOnly, NotReplicated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LocalPlayer: Player` [ReadOnly, NotReplicated] | частично | E36 | 00:458,01:105,02:26,03:13,04:13,06:16,07:29,08:135,09:125,10:9,11:9,12:86,13:146,14:18,15:2,16:17,17:4,18:6,19:5,20:88 | T03 | высоко | Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты. |
| P `localPlayer: Player` [Hidden, ReadOnly, NotReplicated, Deprecated] | нет | E02 | 08:1,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MaxPlayers: int` [ReadOnly, NotReplicated] | нет | E02 | 03:1,04:1,18:3,19:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NumPlayers: int` [ReadOnly, NotReplicated, Deprecated] | нет | E02 | 12:2,19:3,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `numPlayers: int` [Hidden, ReadOnly, NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PreferredPlayers: int` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RespawnTime: float` | нет | E31 | 01:2 | нет | высоко | Metadata не управляет автоматической загрузкой/временем респауна Roblox. |
| P `UseStrafingAnimations: boolean` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BanAsync(config:Dictionary) → ()` | нет | E02 | 00:1,08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreateHumanoidModelFromDescription(description:HumanoidDescription, rigType:HumanoidRigType, assetTypeVerification:AssetTypeVerification) → Model` [Deprecated] | нет | E02 | 00:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreateHumanoidModelFromDescriptionAsync(description:HumanoidDescription, rigType:HumanoidRigType, assetTypeVerification:AssetTypeVerification) → Model` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreateHumanoidModelFromUserId(userId:User) → Model` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreateHumanoidModelFromUserIdAsync(userId:User) → Model` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetBanHistoryAsync(userId:User) → BanHistoryPages` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetCharacterAppearanceAsync(userId:User) → Model` [Deprecated] | нет | E02 | 20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetCharacterAppearanceInfoAsync(userId:User) → Dictionary` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetFriendsAsync(userId:User) → FriendPages` | нет | E02 | 00:1,01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetHumanoidDescriptionFromOutfitId(outfitId:int64) → HumanoidDescription` [Deprecated] | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetHumanoidDescriptionFromOutfitIdAsync(outfitId:int64) → HumanoidDescription` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetHumanoidDescriptionFromUserId(userId:User) → HumanoidDescription` [Deprecated] | нет | E02 | 00:1,01:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetHumanoidDescriptionFromUserIdAsync(userId:User) → HumanoidDescription` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetNameFromUserIdAsync(userId:User) → string` | нет | E02 | 00:2,08:1,09:3,12:3,16:1,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPlayerByUserId(userId:User) → Player` | нет | E02 | 00:13,01:2,08:3,09:12,14:2,16:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPlayerFromCharacter(character:Model) → Player` | частично | E36 | 00:22,01:17,02:1,05:1,06:1,07:1,08:6,09:61,10:6,11:6,12:3,13:77,14:4,16:18,17:6,18:19,20:22 | T03 | высоко | Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты. |
| M `GetPlayers() → List<Player>` | частично | E36 | 00:29,01:25,02:3,06:2,07:2,08:16,09:55,10:2,11:2,12:12,13:2,14:7,16:5,18:3,20:22 | T03 | высоко | Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты. |
| M `getPlayers() → List<Player>` [Deprecated] | нет | E02 | 08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetProfileConfigurationFromUserIdAsync(userId:User) → ProfileConfiguration` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetUserIdFromNameAsync(userName:string) → int64` | нет | E02 | 00:4,01:2,08:2,09:3,10:1,11:1,14:1,20:6 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetUserThumbnailAsync(userId:User, thumbnailType:ThumbnailType, thumbnailSize:ThumbnailSize) → Tuple` | нет | E02 | 00:3,01:2,08:3,09:2,14:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `playerFromCharacter(character:Model) → Player` [Deprecated] | нет | E02 | 03:1,04:1,13:9,17:3,18:9,19:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `players() → List<Player>` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnbanAsync(config:Dictionary) → ()` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `PlayerAdded(player:Player)` | частично | E36 | 00:14,01:21,02:2,06:2,07:2,08:11,09:35,10:2,11:2,12:2,13:10,14:6,16:2,18:12,19:6,20:9 | T03 | высоко | Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты. |
| E `PlayerMembershipChanged(player:Player)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `PlayerRemoving(player:Player, reason:PlayerExitReason)` | частично | E36 | 00:6,01:12,02:5,06:1,07:1,08:11,09:51,10:2,11:2,13:2,14:2,16:1,18:1,20:7 | T03 | высоко | Живые wrappers + bind/unbind events; version/lifecycle и все Roblox identity semantics не покрыты. |
| E `UserSubscriptionStatusChanged(user:Player, subscriptionId:string)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### StarterPlayer

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/StarterPlayer.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AllowCustomAnimations: boolean` [write:RobloxScriptSecurity, Hidden] | нет | E02 | 16:22 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AutoJumpEnabled: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMaxZoomDistance: float` | нет | E02 | 01:2,06:1,07:2,08:2,09:2,12:1,13:2,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMinZoomDistance: float` | нет | E02 | 01:2,02:1,06:1,07:2,08:2,09:2,12:5,13:7,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraMode: CameraMode` | нет | E02 | 01:2,06:2,07:2,08:2,09:2,12:10,20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterBreakJointsOnDeath: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterJumpHeight: float` | нет | E02 | 07:3,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterJumpPower: float` | нет | E02 | 00:1,07:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterMaxSlopeAngle: float` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterUseJumpPower: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CharacterWalkSpeed: float` | нет | E02 | 00:1,07:2,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ClassicDeath: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevCameraOcclusionMode: DevCameraOcclusionMode` | нет | E02 | 00:2,01:3,07:4,08:3,09:3,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevComputerCameraMovementMode: DevComputerCameraMovementMode` | нет | E02 | 01:2,07:2,08:2,09:2,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevComputerMovementMode: DevComputerMovementMode` | нет | E02 | 01:2,07:2,08:2,09:2,12:3,14:1,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevTouchCameraMovementMode: DevTouchCameraMovementMode` | нет | E02 | 01:2,07:2,08:2,09:2,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DevTouchMovementMode: DevTouchMovementMode` | нет | E02 | 01:2,07:2,08:1,09:1,12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `EnableDynamicHeads: LoadDynamicHeads` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `EnableMouseLockOption: boolean` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HealthDisplayDistance: float` | нет | E02 | 20:8 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LoadCharacterAppearance: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LoadCharacterLayeredClothing : LoadCharacterLayeredClothing` [NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LuaCharacterController: CharacterControlMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NameDisplayDistance: float` | нет | E02 | 20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `UserEmotesEnabled: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Workspace

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Workspace.yaml). inherits: `WorldRoot`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AirDensity: float` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AirTurbulenceIntensity: float` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AllowThirdPartySales: boolean` [NotReplicated] | нет | E02 | 00:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AvatarUnificationMode: AvatarUnificationMode` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ClientAnimatorThrottling: ClientAnimatorThrottlingMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CurrentCamera: Camera` [NotReplicated] | частично | E37 | 00:30,01:41,02:18,06:3,07:20,08:51,09:70,10:4,11:4,12:18,13:8,14:1,16:6,17:2,18:6,20:22 | нет | высоко | Получается камера активного viewport; setter/все режимы камеры не восстановлены. |
| P `DistributedGameTime: double` [NotReplicated] | нет | E02 | 00:4,01:1,09:1,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `EnableSLIMAvatars: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FallenPartsDestroyHeight: float` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FallHeightEnabled: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FilteringEnabled: boolean` [write:PluginSecurity, Hidden, NotReplicated, Deprecated] | нет | E02 | 13:8,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FluidForces: FluidForces` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `GlobalWind: Vector3` | нет | E02 | 00:3,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Gravity: float` | частично | E38 | 00:6,01:6,09:8,10:2,11:2,14:1,16:1 | T01,T02 | высоко | Live gravity для player/NPC/parts; discrete Godot solver и finite guard, не полный Roblox world solver. |
| P `IKControlConstraintSupport: IKControlConstraintSupport` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ImprovedAnimationConstraint: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ImprovedPhysicsReplication: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `InsertPoint: Vector3` [NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `InterpolationThrottling: InterpolationThrottlingMode` [write:PluginSecurity, Hidden, NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LayeredClothingCacheOptimizations: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LuauTypeCheckMode: LuauTypeCheckMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MeshPartHeadsAndAccessories: MeshPartHeadsAndAccessories` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MeshStreamingAndImprovedLods: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ModelStreamingBehavior: ModelStreamingBehavior` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NextGenerationReplication: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PathfindingUseImprovedSearch: PathfindingUseImprovedSearch` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PhysicsSteppingMethod: PhysicsSteppingMethod` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PlayerCharacterDestroyBehavior: PlayerCharacterDestroyBehavior` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PredictiveStreamingMode: PredictiveStreamingMode` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PrimalPhysicsSolver: PrimalPhysicsSolver` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RejectCharacterDeletions: RejectCharacterDeletions` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RenderingCacheOptimizations: RenderingCacheOptimizationMode` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ReplicateInstanceDestroySetting: ReplicateInstanceDestroySetting` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Retargeting: AnimatorRetargetingMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `SandboxedInstanceMode: SandboxedInstanceMode` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `SignalBehavior: SignalBehavior` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `StreamingEnabled: boolean` | нет | E02 | 00:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `StreamingIntegrityMode: StreamingIntegrityMode` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `StreamingMinRadius: int` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `StreamingTargetRadius: int` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `StreamOutBehavior: StreamOutBehavior` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Terrain: Terrain` [ReadOnly, NotReplicated] | нет | E02 | 00:6,01:7,02:3,08:6,09:6,10:1,11:1,13:5,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TouchesUseCollisionGroups: boolean` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `UseFixedSimulation: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `UseNewLuauTypeSolver: RolloutState` [NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetNumAwakeParts() → int` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPhysicsThrottling() → int` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRealPhysicsFPS() → double` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetServerTimeNow() → double` | нет | E02 | 00:4,08:8,09:66 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `JoinToOutsiders(objects:Instances, jointType:JointCreationMode) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `PGSIsEnabled() → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnjoinFromOutsiders(objects:Instances) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `PersistentLoaded(player:Player)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### PathfindingService

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/PathfindingService.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `EmptyCutoff: float` [NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ComputeRawPathAsync(start:Vector3, finish:Vector3, maxDistance:float) → Path` [Deprecated] | нет | E02 | 12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ComputeSmoothPathAsync(start:Vector3, finish:Vector3, maxDistance:float) → Path` [Deprecated] | нет | E02 | 01:1,07:1,08:1,09:1,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreatePath(agentParameters:Dictionary) → Path` | нет | E02 | 01:1,07:1,08:1,09:2 | нет | критично | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPathAsync(start:Vector3, finish:Vector3) → Path` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### UserInputService

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/UserInputService.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccelerometerEnabled: boolean` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `GamepadEnabled: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:4,01:4,02:2,07:4,08:9,09:3,12:6,13:5,16:1,20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `GyroscopeEnabled: boolean` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `KeyboardEnabled: boolean` [ReadOnly, NotReplicated] | частично | E39 | 00:9,01:4,07:4,08:6,09:5,12:3,13:2,20:5 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| P `ModalEnabled: boolean` [Deprecated] | нет | E02 | 01:1,09:1,12:3,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MouseBehavior: MouseBehavior` | нет | E02 | 00:7,01:6,06:1,07:4,08:5,09:7,12:2,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MouseDeltaSensitivity: float` [NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MouseEnabled: boolean` [ReadOnly, NotReplicated] | частично | E39 | 00:7,01:2,02:2,08:3,09:3 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| P `MouseIcon: ContentId` | нет | E02 | 02:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MouseIconContent: Content` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MouseIconEnabled: boolean` | нет | E02 | 00:6,01:2,02:1,06:2,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `OnScreenKeyboardPosition: Vector2` [ReadOnly, NotReplicated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `OnScreenKeyboardSize: Vector2` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `OnScreenKeyboardVisible: boolean` [ReadOnly, NotReplicated] | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PreferredInput: PreferredInput` [ReadOnly, NotReplicated] | нет | E02 | 09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TouchEnabled: boolean` [ReadOnly, NotReplicated] | частично | E39 | 00:5,01:6,02:2,06:3,07:6,08:47,09:12,12:20,13:10,14:3,16:1,20:17 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| P `UserHeadCFrame: CFrame` [ReadOnly, NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `VREnabled: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:1,01:4,02:4,07:6,08:7,09:6 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CreateVirtualInput() → Object` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GamepadSupports(gamepadNum:UserInputType, gamepadKeyCode:KeyCode) → boolean` | нет | E02 | 12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetConnectedGamepads() → Array` | нет | E02 | 01:3,02:1,07:1,08:1,09:2,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetDeviceAcceleration() → InputObject` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetDeviceGravity() → InputObject` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetDeviceRotation() → Tuple` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetFocusedTextBox() → TextBox` | нет | E02 | 00:12,01:2,02:3,09:6,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetGamepadConnected(gamepadNum:UserInputType) → boolean` | нет | E02 | 01:1,08:1,09:2,12:2,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetGamepadState(gamepadNum:UserInputType) → List<InputObject>` | нет | E02 | 01:1,07:1,08:1,09:2,13:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetImageForKeyCode(keyCode:KeyCode) → ContentId` | нет | E02 | 00:2,08:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetKeysPressed() → List<InputObject>` | нет | E02 | 00:14,06:1,09:7,12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetLastInputType() → UserInputType` | нет | E02 | 01:4,07:2,08:6,09:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMouseButtonsPressed() → List<InputObject>` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMouseDelta() → Vector2` | нет | E02 | 00:1,01:1,07:1,08:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMouseLocation() → Vector2` | частично | E39 | 00:3,02:1,06:1,08:12,09:1 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| M `GetNavigationGamepads() → Array` | нет | E02 | 01:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetStringForKeyCode(keyCode:KeyCode, format:KeyCodeStringFormat) → string` | нет | E02 | 00:3,01:1,08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetSupportedGamepadKeyCodes(gamepadNum:UserInputType) → Array` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetUserCFrame(type:UserCFrame) → CFrame` [Deprecated] | нет | E02 | 01:1,02:2,07:3,08:4,09:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsGamepadButtonDown(gamepadNum:UserInputType, gamepadKeyCode:KeyCode) → boolean` | нет | E02 | 08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsKeyDown(keyCode:KeyCode) → boolean` | частично | E39 | 00:15,01:3,02:7,08:2,09:4 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| M `IsMouseButtonPressed(mouseButton:UserInputType) → boolean` | нет | E02 | 00:1,01:1,02:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsNavigationGamepad(gamepadEnum:UserInputType) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RecenterUserHeadCFrame() → ()` | нет | E02 | 07:2,08:2,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetNavigationGamepad(gamepadEnum:UserInputType, enabled:boolean) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `DeviceAccelerationChanged(acceleration:InputObject)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `DeviceGravityChanged(gravity:InputObject)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `DeviceRotationChanged(rotation:InputObject, cframe:CFrame)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `GamepadConnected(gamepadNum:UserInputType)` | нет | E02 | 01:4,02:1,07:1,08:2,09:3,12:3,20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `GamepadDisconnected(gamepadNum:UserInputType)` | нет | E02 | 01:4,02:1,07:1,08:2,09:3,12:3,20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `InputBegan(input:InputObject, gameProcessedEvent:boolean)` | частично | E39 | 00:38,01:34,02:12,06:6,07:5,08:37,09:26,10:1,11:1,12:25,13:9,14:2,20:27 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| E `InputChanged(input:InputObject, gameProcessedEvent:boolean)` | частично | E39 | 00:11,01:7,02:1,07:2,08:4,09:3,12:3,20:4 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| E `InputEnded(input:InputObject, gameProcessedEvent:boolean)` | частично | E39 | 00:27,01:20,02:8,07:4,08:19,09:12,12:4,13:29,14:1,20:6 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| E `JumpRequest()` | частично | E39 | 00:1,01:1,09:3,14:1 | T08 | высоко | Есть real keyboard/mouse/touch input bridge; не gamepad/sensor/text полный контракт и не реальные Android parity measurements. |
| E `LastInputTypeChanged(lastInputType:UserInputType)` | нет | E02 | 01:2,07:1,08:4,09:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `PointerAction(wheel:float, pan:Vector2, pinch:float, gameProcessedEvent:boolean)` | нет | E02 | 01:2,07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TextBoxFocused(textboxFocused:TextBox)` | нет | E02 | 00:2,01:1,07:1,08:2,09:2,12:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TextBoxFocusReleased(textboxReleased:TextBox)` | нет | E02 | 00:2,01:1,07:1,08:2,09:2,12:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchDrag(dragDirection:SwipeDirection, numberOfTouches:int, gameProcessedEvent:boolean)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchEnded(touch:InputObject, gameProcessedEvent:boolean)` | нет | E02 | 00:3,01:3,07:2,08:6,09:4,12:3,16:2,20:7 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchLongPress(touchPositions:Array, state:UserInputState, gameProcessedEvent:boolean)` | нет | E02 | 08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchMoved(touch:InputObject, gameProcessedEvent:boolean)` | нет | E02 | 00:1,01:1,07:2,08:2,09:3,12:3,20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchPan(touchPositions:Array, totalTranslation:Vector2, velocity:Vector2, state:UserInputState, gameProcessedEvent:boolean)` | нет | E02 | 09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchPinch(touchPositions:Array, scale:float, velocity:float, state:UserInputState, gameProcessedEvent:boolean)` | нет | E02 | 01:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchRotate(touchPositions:Array, rotation:float, velocity:float, state:UserInputState, gameProcessedEvent:boolean)` | нет | E02 | 09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchStarted(touch:InputObject, gameProcessedEvent:boolean)` | нет | E02 | 08:1,09:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchSwipe(swipeDirection:SwipeDirection, numberOfTouches:int, gameProcessedEvent:boolean)` | нет | E02 | 01:2,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchTap(touchPositions:Array, gameProcessedEvent:boolean)` | нет | E02 | 00:2,01:2,07:1,08:7,09:3,12:1,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `TouchTapInWorld(position:Vector2, processedByUI:boolean)` | нет | E02 | 02:1,08:16,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `UserCFrameChanged(type:UserCFrame, value:CFrame)` [Deprecated] | нет | E02 | 07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `WindowFocused()` | нет | E02 | 01:2,07:2,08:2,09:2,12:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `WindowFocusReleased()` | нет | E02 | 01:3,07:1,08:2,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### ContextActionService

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ContextActionService.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| M `BindAction(actionName:string, functionToBind:Function, createTouchButton:boolean, inputTypes:Tuple) → ()` | нет | E39 | 00:10,01:7,07:2,08:3,09:7,12:19,13:2,14:1,20:18 | нет | критично | Service-node создаётся, но action callback/priority/sink/touch button implementation отсутствует. |
| M `BindActionAtPriority(actionName:string, functionToBind:Function, createTouchButton:boolean, priorityLevel:int, inputTypes:Tuple) → ()` | нет | E39 | 00:2,01:9,02:1,07:7,08:8,09:7 | нет | высоко | Service-node создаётся, но action callback/priority/sink/touch button implementation отсутствует. |
| M `BindActionToInputTypes(actionName:string, functionToBind:Function, createTouchButton:boolean, inputTypes:Tuple) → ()` [Deprecated] | нет | E02 | 12:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BindActivate(userInputTypeForActivation:UserInputType, keyCodesForActivation:Tuple) → ()` | нет | E02 | 01:2,02:1,07:2,08:2,09:2,12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetAllBoundActionInfo() → Dictionary` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetBoundActionInfo(actionName:string) → Dictionary` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetButton(actionName:string) → Instance` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetCurrentLocalToolIcon() → string` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetDescription(actionName:string, description:string) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetImage(actionName:string, image:string) → ()` | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetPosition(actionName:string, position:UDim2) → ()` | нет | E02 | 01:2,13:2,14:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetTitle(actionName:string, title:string) → ()` | нет | E02 | 09:3,13:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnbindAction(actionName:string) → ()` | нет | E39 | 00:13,01:10,02:1,07:7,08:9,09:12,12:19,13:2,20:19 | нет | высоко | Service-node создаётся, но action callback/priority/sink/touch button implementation отсутствует. |
| M `UnbindActivate(userInputTypeForActivation:UserInputType, keyCodeForActivation:KeyCode) → ()` | нет | E02 | 01:2,07:2,08:2,09:2,12:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnbindAllActions() → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `LocalToolEquipped(toolEquipped:Instance)` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `LocalToolUnequipped(toolUnequipped:Instance)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### BasePart

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/BasePart.yaml). inherits: `PVInstance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Anchored: boolean` | частично | E02 | 00:40,01:16,02:19,03:1,04:1,05:3,06:2,07:6,08:30,09:59,10:3,11:3,12:5,13:237,14:1,16:19,18:15,19:16,20:22 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `AssemblyAngularVelocity: Vector3` [NotReplicated] | частично | E40 | 00:3,08:1,09:1 | T01,T06 | высоко | Запись преобразуется/передаётся физике. Angular getter не полностью отражает live assembly; R6 proxy не multipart assembly. |
| P `AssemblyCenterOfMass: Vector3` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AssemblyLinearVelocity: Vector3` [NotReplicated] | частично | E40 | 00:4,06:4,08:1,09:2 | T01,T06 | критично | Запись преобразуется/передаётся физике. Angular getter не полностью отражает live assembly; R6 proxy не multipart assembly. |
| P `AssemblyMass: float` [ReadOnly, NotReplicated] | нет | E41 | 00:1 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `AssemblyRootPart: BasePart` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AudioCanCollide: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BackParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BackParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BackSurface: SurfaceType` | нет | E02 | 00:6,05:1,09:4,10:3,11:3,18:3,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BackSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BottomParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BottomParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BottomSurface: SurfaceType` | нет | E02 | 00:12,01:2,02:13,03:1,04:1,05:1,08:8,09:6,10:6,11:6,13:10,16:6,17:2,18:18,19:5,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BottomSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `BrickColor: BrickColor` [NotReplicated] | частично | E02 | 00:16,01:19,02:3,03:9,04:9,05:1,08:4,09:9,10:9,11:9,12:5,13:1189,14:3,15:1,16:4,17:5,18:17,19:38,20:11 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `brickColor: BrickColor` [NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CanCollide: boolean` | частично | E02 | 00:36,01:21,02:20,03:5,04:5,05:2,06:2,07:8,08:133,09:50,10:1,11:1,12:5,13:398,14:4,16:34,17:6,18:50,19:33,20:23 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `CanQuery: boolean` | частично | E02 | 00:8,01:1,02:16,07:1,08:11,09:9 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `CanTouch: boolean` | частично | E02 | 00:8,01:1,02:14,07:1,08:4,09:9 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `CastShadow: boolean` | нет | E02 | 00:5,01:1,07:1,08:4,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CenterOfMass: Vector3` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CFrame: CFrame` | частично | E02 | 00:87,01:183,02:39,03:54,04:54,05:5,06:5,07:26,08:166,09:115,10:5,11:5,12:14,13:679,14:7,15:3,16:49,17:4,18:32,19:192,20:107 | T06 | критично | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `CollisionGroup: string` [NotReplicated] | нет | E41 | 00:1,02:1,08:1 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `CollisionGroupId: int` [NotReplicated, Deprecated] | нет | E02 | 01:1,08:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Color: Color3` [NotReplicated] | частично | E02 | 00:78,01:117,02:21,03:1,04:1,06:2,08:28,09:92,10:4,11:4,12:22,13:425,14:3,16:16,18:9,19:6,20:18 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `CurrentPhysicalProperties: PhysicalProperties` [ReadOnly, NotReplicated] | нет | E41 | — | нет | средне | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `CustomPhysicalProperties: PhysicalProperties` | нет | E41 | 13:1 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `Elasticity: float` [Hidden, NotReplicated, Deprecated] | нет | E41 | 02:1,08:1,09:1,10:1,11:1,13:3,17:2,18:3 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `EnableFluidForces: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ExtentsCFrame: CFrame` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ExtentsSize: Vector3` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Friction: float` [Hidden, NotReplicated, Deprecated] | нет | E41 | 02:1,08:1,09:2,10:1,11:1,13:2,17:4,18:4,19:4 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `FrontParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FrontParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FrontSurface: SurfaceType` | нет | E02 | 00:8,05:1,09:4,10:3,11:3,18:3,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FrontSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LeftParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LeftParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LeftSurface: SurfaceType` | нет | E02 | 00:6,05:1,09:4,10:3,11:3,18:3,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LeftSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `LocalTransparencyModifier: float` [Hidden, NotReplicated] | нет | E02 | 01:3,02:1,06:1,07:3,08:3,09:3,12:2,13:2,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Locked: boolean` | нет | E02 | 00:15,03:1,04:1,05:1,08:3,09:8,10:4,11:4,12:6,13:4,18:15,19:4,20:6 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Mass: float` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Massless: boolean` | нет | E41 | 00:5,01:1,07:1,08:6,09:7 | нет | высоко | Хранение imported properties не устанавливает Roblox density/friction/массу/систему collision groups в solver. |
| P `Material: Material` | нет | E02 | 00:20,01:16,02:8,07:1,08:14,09:17,10:2,11:2,13:400,14:3,16:16,18:2,20:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MaterialVariant: string` [NotReplicated] | нет | E02 | 08:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Orientation: Vector3` [Hidden, NotReplicated] | нет | E02 | 00:3,01:15,06:2,08:3,09:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PivotOffset: CFrame` | нет | E02 | 09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Position: Vector3` [Hidden, NotReplicated] | частично | E02 | 00:163,01:118,02:61,03:63,04:63,05:4,06:12,07:19,08:213,09:168,10:13,11:13,12:73,13:707,14:5,15:2,16:37,17:7,18:48,19:74,20:138 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `ReceiveAge: float` [Hidden, ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Reflectance: float` | нет | E02 | 00:9,03:5,04:5,08:2,09:5,10:1,11:1,13:29,16:1,17:2,18:10,19:12 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ResizeableFaces: Faces` [ReadOnly, NotReplicated] | нет | E02 | 00:1,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ResizeIncrement: int` [ReadOnly, NotReplicated] | нет | E02 | 00:1,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RightParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RightParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RightSurface: SurfaceType` | нет | E02 | 00:6,05:1,09:4,10:3,11:3,18:3,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RightSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `RootPriority: int` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Rotation: Vector3` [NotReplicated] | частично | E02 | 00:16,01:7,02:7,07:3,08:20,09:17,12:4,16:4,20:6 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `RotVelocity: Vector3` [Hidden, Deprecated] | частично | E40 | 00:9,01:2,03:27,04:27,05:2,07:1,08:1,09:7,13:1,14:1,16:2,18:7,19:7,20:1 | T01,T06 | высоко | Запись преобразуется/передаётся физике. Angular getter не полностью отражает live assembly; R6 proxy не multipart assembly. |
| P `Size: Vector3` [NotReplicated] | частично | E02 | 00:162,01:100,02:59,03:1,04:1,05:7,06:11,07:14,08:192,09:137,10:7,11:7,12:47,13:106,14:7,16:32,17:8,18:27,19:48,20:58 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `SpecificGravity: float` [ReadOnly, NotReplicated, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TopParamA: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TopParamB: float` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TopSurface: SurfaceType` | нет | E02 | 00:12,01:2,02:13,03:1,04:1,05:1,08:8,09:6,10:5,11:5,13:10,16:6,17:2,18:18,19:5,20:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TopSurfaceInput: InputType` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Transparency: float` | частично | E02 | 00:33,01:101,02:28,03:1,04:1,05:6,07:9,08:152,09:56,10:3,11:3,12:12,13:682,14:4,16:38,17:3,18:59,19:133,20:23 | T06 | высоко | Есть getters/setters и физика/рендер/query hooks; не полный тип/assembly/mesh/материал контракт Roblox. |
| P `Velocity: Vector3` [Hidden, Deprecated] | частично | E40 | 00:66,01:22,03:33,04:33,05:3,07:6,08:6,09:29,10:5,11:5,12:2,13:40,14:4,15:1,16:9,17:4,18:19,19:110,20:6 | T01,T06 | высоко | Запись преобразуется/передаётся физике. Angular getter не полностью отражает live assembly; R6 proxy не multipart assembly. |
| M `AngularAccelerationToTorque(angAcceleration:Vector3, angVelocity:Vector3) → Vector3` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyAngularImpulse(impulse:Vector3) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ApplyImpulse(impulse:Vector3) → ()` | частично | E42 | 09:1 | T06 | высоко | Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox. |
| M `ApplyImpulseAtPosition(impulse:Vector3, position:Vector3) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BindToCollisionSummaries(callback:Function) → RBXScriptConnection` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BreakJoints() → ()` [Deprecated] | частично | E42 | 00:13,01:4,03:7,04:7,05:2,09:5,10:1,11:1,13:4,14:1,16:3,17:2,18:6,19:6 | T06 | высоко | Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox. |
| M `breakJoints() → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CanCollideWith(part:BasePart) → boolean` | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CanSetNetworkOwnership() → Tuple` | нет | E02 | 00:1,01:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetClosestPointOnSurface(position:Vector3) → Vector3` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetConnectedParts(recursive:boolean) → List<BasePart>` | частично | E42 | 00:6,01:5,02:1,07:2,08:2,09:5,12:1,20:1 | T06 | высоко | Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox. |
| M `GetJoints() → Instances` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMass() → float` | частично | E42 | 00:7,01:3,05:1,09:1,13:8,14:2,16:1,18:3,19:23 | T06 | высоко | Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox. |
| M `getMass() → float` [Deprecated] | нет | E02 | 00:1,01:1,03:1,04:1,18:4,19:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetNetworkOwner() → Instance` | нет | E02 | 01:1,09:1,10:1,11:1,13:6 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetNetworkOwnershipAuto() → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetNoCollisionConstraints() → Instances` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRenderCFrame() → CFrame` [Deprecated] | нет | E02 | 02:3,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRootPart() → Instance` [Deprecated] | нет | E02 | 01:1,07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetTouchingParts() → Instances` | нет | E02 | 00:2,01:2,07:3,09:1,16:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetVelocityAtPosition(position:Vector3) → Vector3` | нет | E02 | 08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IntersectAsync(parts:Instances, collisionfidelity:CollisionFidelity, renderFidelity:RenderFidelity) → Instance` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsGrounded() → boolean` | нет | E02 | 06:1,13:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `MakeJoints() → ()` [Deprecated] | частично | E42 | 00:15,03:24,04:24,05:1,09:6,10:3,11:3,13:3,14:1,16:4,18:4,19:4,20:1 | T06 | высоко | Есть собственные physics/assembly routines; Godot mass, weld/hinge и импульсы не откалиброваны по Roblox. |
| M `makeJoints() → ()` [Deprecated] | нет | E02 | 03:27,04:27,15:2,16:2,17:1,18:3,19:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Resize(normalId:NormalId, deltaAmount:int) → boolean` | нет | E02 | 00:1,18:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `resize(normalId:NormalId, deltaAmount:int) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetNetworkOwner(playerInstance:Player) → ()` | нет | E02 | 00:4,01:3,09:5,10:4,11:4,13:95,16:1,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetNetworkOwnershipAuto() → ()` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SubtractAsync(parts:Instances, collisionfidelity:CollisionFidelity, renderFidelity:RenderFidelity) → Instance` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `TorqueToAngularAcceleration(torque:Vector3, angVelocity:Vector3) → Vector3` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnionAsync(parts:Instances, collisionfidelity:CollisionFidelity, renderFidelity:RenderFidelity) → Instance` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `LocalSimulationTouched(part:BasePart)` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `OutfitChanged()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `StoppedTouching(otherPart:BasePart)` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Touched(otherPart:BasePart)` | частично | E43 | 00:235,01:11,02:1,03:53,04:53,05:3,06:2,07:3,08:6,09:11,10:6,11:6,13:865,14:2,15:9,16:34,17:6,18:158,19:174,20:28 | T06 | высоко | Contact/sweep producer и CanTouch; Humanoid parts/очередь/TouchEnded не полная Roblox contact semantics. |
| E `TouchEnded(otherPart:BasePart)` | нет | E44 | 00:3,01:3,07:2,08:6,09:4,12:3,16:2,20:7 | нет | высоко | Есть public signal fallback, но part physics не имеет body-exit producer. |

### Motor6D

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Motor6D.yaml). inherits: `Motor`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ChildName: string` [ReadOnly, NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ParentName: string` [ReadOnly, NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Transform: CFrame` [Hidden, NotReplicated] | частично | E45 | 01:8,02:2,08:4,09:5 | нет | высоко | Frame участвует при refresh joint; не Animator batched Transform/приоритеты/физический персонаж. |

### Attachment

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Attachment.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Axis: Vector3` [NotReplicated] | нет | E02 | 00:7,01:8,09:3,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CFrame: CFrame` | частично | E46 | 00:87,01:183,02:39,03:54,04:54,05:5,06:5,07:26,08:166,09:115,10:5,11:5,12:14,13:679,14:7,15:3,16:49,17:4,18:32,19:192,20:107 | нет | критично | Node3D общий маршрут использует global coordinates; Attachment local-space semantics отличаются. |
| P `Orientation: Vector3` [Hidden, NotReplicated] | нет | E02 | 00:3,01:15,06:2,08:3,09:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Position: Vector3` [Hidden, NotReplicated] | частично | E46 | 00:163,01:118,02:61,03:63,04:63,05:4,06:12,07:19,08:213,09:168,10:13,11:13,12:73,13:707,14:5,15:2,16:37,17:7,18:48,19:74,20:138 | нет | высоко | Node3D общий маршрут использует global coordinates; Attachment local-space semantics отличаются. |
| P `Rotation: Vector3` [Hidden, NotReplicated, Deprecated] | частично | E46 | 00:16,01:7,02:7,07:3,08:20,09:17,12:4,16:4,20:6 | нет | высоко | Node3D общий маршрут использует global coordinates; Attachment local-space semantics отличаются. |
| P `SecondaryAxis: Vector3` [NotReplicated] | нет | E02 | 16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Visible: boolean` | нет | E02 | 00:322,01:34,02:17,05:1,06:6,07:7,08:60,09:95,10:8,11:8,12:74,13:32,14:5,16:9,17:1,18:10,19:16,20:71 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldAxis: Vector3` [NotReplicated] | нет | E02 | 08:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldCFrame: CFrame` [NotReplicated] | нет | E02 | 01:4,08:2,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldOrientation: Vector3` [Hidden, NotReplicated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldPosition: Vector3` [Hidden, NotReplicated] | нет | E02 | 01:7,08:6,09:6,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldRotation: Vector3` [Hidden, ReadOnly, NotReplicated, Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldSecondaryAxis: Vector3` [NotReplicated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetAxis() → Vector3` [Deprecated] | нет | E02 | 01:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetConstraints() → List<Constraint>` | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetSecondaryAxis() → Vector3` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetAxis(axis:Vector3) → ()` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetSecondaryAxis(axis:Vector3) → ()` [Deprecated] | нет | E02 | — | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### ControllerManager

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ControllerManager.yaml). inherits: `Instance`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ActiveController: ControllerBase` | нет | E02 | 02:3,08:1,09:1 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BaseMoveSpeed: float` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BaseTurnSpeed: float` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `ClimbSensor: ControllerSensor` | нет | E02 | 08:1,09:1 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `FacingDirection: Vector3` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `GroundSensor: ControllerSensor` | нет | E02 | 08:1,09:1 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MovingDirection: Vector3` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `RootPart: BasePart` | нет | E02 | 00:2,01:23,02:1,07:10,08:10,09:15 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `UpDirection: Vector3` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### ControllerPartSensor

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ControllerPartSensor.yaml). inherits: `ControllerSensor`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `HitFrame: CFrame` | нет | E02 | — | нет | критично | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `HitNormal: Vector3` | нет | E02 | — | нет | критично | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `LadderSearchHeight: float` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `LadderSearchOffset: float` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `SearchDistance: float` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `SensedMaterial: Material` | нет | E02 | — | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `SensedPart: BasePart` | нет | E02 | 08:1,09:1 | нет | критично | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `SensorMode: SensorMode` | нет | E02 | — | нет | критично | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### GroundController

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/GroundController.yaml). inherits: `ControllerBase`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccelerationTime: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceSpeed: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `DecelerationTime: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `Friction: float` | нет | E02 | 02:1,08:1,09:2,10:1,11:1,13:2,17:4,18:4,19:4 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `FrictionWeight: float` | нет | E02 | 08:1 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `GroundOffset: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `TurnSpeedFactor: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### AirController

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AirController.yaml). inherits: `ControllerBase`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `BalanceMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceSpeed: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MaintainAngularMomentum: boolean` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MaintainLinearMomentum: boolean` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MoveMaxForce: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `TurnMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `TurnSpeedFactor: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### ClimbController

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ClimbController.yaml). inherits: `ControllerBase`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AccelerationTime: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceSpeed: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MoveMaxForce: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### SwimController

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/SwimController.yaml). inherits: `ControllerBase`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `PitchMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `PitchSpeedFactor: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `RollMaxTorque: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `RollSpeedFactor: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### Constraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Constraint.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Active: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:24,01:9,02:4,07:3,08:16,09:14,12:8,18:1,20:11 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Attachment0: Attachment` | нет | E02 | 00:4,01:5,02:2,07:1,08:5,09:11,10:2,11:2,16:3 | нет | критично | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Attachment1: Attachment` | нет | E02 | 00:2,01:7,02:2,07:1,08:7,09:5,10:2,11:2,16:3 | нет | критично | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Color: BrickColor` | нет | E02 | 00:78,01:117,02:21,03:1,04:1,06:2,08:28,09:92,10:4,11:4,12:22,13:425,14:3,16:16,18:9,19:6,20:18 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Enabled: boolean` | нет | E02 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Visible: boolean` | нет | E02 | 00:322,01:34,02:17,05:1,06:6,07:7,08:60,09:95,10:8,11:8,12:74,13:32,14:5,16:9,17:1,18:10,19:16,20:71 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| M `GetDebugAppliedForce(bodyId:int) → Vector3` [Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| M `GetDebugAppliedTorque(bodyId:int) → Vector3` [Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### WeldConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/WeldConstraint.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Active: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:24,01:9,02:4,07:3,08:16,09:14,12:8,18:1,20:11 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Enabled: boolean` [NotReplicated] | частично | E47 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | T06 | высоко | Реальный rigid joint mesh-to-mesh; не constraints всей character assembly и не полный Roblox solver. |
| P `Part0: BasePart` [NotReplicated] | частично | E47 | 00:18,01:11,03:1,04:1,05:2,07:1,08:14,09:25,12:2,13:29,14:2,16:16,17:3,18:14,19:10,20:77 | T06 | критично | Реальный rigid joint mesh-to-mesh; не constraints всей character assembly и не полный Roblox solver. |
| P `Part1: BasePart` [NotReplicated] | частично | E47 | 00:20,01:11,03:28,04:28,05:2,07:1,08:15,09:25,12:2,13:32,14:2,16:16,17:3,18:15,19:10,20:77 | T06 | критично | Реальный rigid joint mesh-to-mesh; не constraints всей character assembly и не полный Roblox solver. |

### NoCollisionConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/NoCollisionConstraint.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Enabled: boolean` | нет | E02 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Part0: BasePart` | нет | E02 | 00:18,01:11,03:1,04:1,05:2,07:1,08:14,09:25,12:2,13:29,14:2,16:16,17:3,18:14,19:10,20:77 | нет | критично | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Part1: BasePart` | нет | E02 | 00:20,01:11,03:28,04:28,05:2,07:1,08:15,09:25,12:2,13:32,14:2,16:16,17:3,18:15,19:10,20:77 | нет | критично | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### Camera

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Camera.yaml). inherits: `PVInstance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `CameraSubject: Instance` | нет | E02 | 00:3,01:9,07:9,08:10,09:14,10:1,11:1,12:10,13:5,17:2,18:1,20:11 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `CameraType: CameraType` | частично | E48 | 00:7,01:5,02:1,06:1,07:2,08:3,09:2,10:1,11:1,12:5,13:6,17:2,18:1,20:6 | T09 | высоко | Scriptable/Custom transform ownership есть; остальные CameraType представлены не полностью и отсутствуют полноценные camera motors. |
| P `CFrame: CFrame` | частично | E48 | 00:87,01:183,02:39,03:54,04:54,05:5,06:5,07:26,08:166,09:115,10:5,11:5,12:14,13:679,14:7,15:3,16:49,17:4,18:32,19:192,20:107 | T09 | критично | Scriptable/Custom transform ownership есть; остальные CameraType представлены не полностью и отсутствуют полноценные camera motors. |
| P `CoordinateFrame: CFrame` [Hidden, NotReplicated, Deprecated] | нет | E02 | 00:2,01:3,07:3,08:3,09:4,12:12,13:2,16:2,18:5,20:15 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DiagonalFieldOfView: float` [NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FieldOfView: float` | нет | E02 | 00:11,01:14,02:8,06:1,07:1,08:6,09:10,10:2,11:2,12:3,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `FieldOfViewMode: FieldOfViewMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Focus: CFrame` | нет | E02 | 00:27,01:11,02:2,07:8,08:8,09:21,12:10,18:3,20:10 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `focus: CFrame` [NotReplicated, Deprecated] | нет | E02 | 01:6 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HeadLocked: boolean` | нет | E02 | 02:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `HeadScale: float` | нет | E02 | 00:4,02:1,07:4,08:4,09:6,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `MaxAxisFieldOfView: float` [NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `NearPlaneZ: float` [ReadOnly, NotReplicated] | нет | E02 | 01:1,07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ViewportSize: Vector2` [ReadOnly, NotReplicated] | нет | E02 | 00:10,01:4,02:3,07:4,08:10,09:11,12:2,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `VRTiltAndRollEnabled: boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetLargestCutoffDistance(ignoreList:Instances) → float` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPanSpeed() → float` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPartsObscuringTarget(castPoints:Array, ignoreList:Instances) → Instances` | нет | E02 | 01:1,07:1,08:1,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRenderCFrame() → CFrame` | нет | E02 | 02:3,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetRoll() → float` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetTiltSpeed() → float` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Interpolate(endPos:CFrame, endFocus:CFrame, duration:float) → ()` [Deprecated] | нет | E02 | 12:1,13:2,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `PanUnits(units:int) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ScreenPointToRay(x:float, y:float, depth:float) → Ray` | частично | E49 | 00:7,01:2,07:1,08:2,09:4,12:1,20:3 | нет | высоко | Godot camera ray преобразуется; screen inset отличается, ViewportPointToRay пока alias ScreenPointToRay. |
| M `SetCameraPanMode(mode:CameraPanMode) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetRoll(rollAngle:float) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `TiltUnits(units:int) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ViewportPointToRay(x:float, y:float, depth:float) → Ray` | частично | E49 | 00:4,01:2,02:1,07:1,08:7,09:4 | нет | высоко | Godot camera ray преобразуется; screen inset отличается, ViewportPointToRay пока alias ScreenPointToRay. |
| M `WorldToScreenPoint(worldPoint:Vector3) → Tuple` | нет | E02 | 00:6,01:1,08:8,09:3,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `WorldToViewportPoint(worldPoint:Vector3) → Tuple` | нет | E02 | 00:4,02:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ZoomToExtents(boundingBoxCFrame:CFrame, boundingBoxSize:Vector3) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `InterpolationFinished()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Path

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Path.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Status: PathStatus` [ReadOnly, NotReplicated] | нет | E02 | 00:6,01:12,02:5,05:2,07:2,08:4,09:10,12:2,16:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CheckOcclusionAsync(start:int) → int` | нет | E02 | 01:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ComputeAsync(start:Vector3, finish:Vector3) → ()` | нет | E02 | 01:2,07:1,08:1,09:2 | нет | критично | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPointCoordinates() → Array` [Deprecated] | нет | E02 | 01:1,07:1,08:1,09:1,12:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetWaypoints() → Array` | нет | E02 | 01:2,07:1,08:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Blocked(blockedWaypointIdx:int)` | нет | E02 | 01:1,07:1,08:1,09:3 | нет | критично | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Unblocked(unblockedWaypointIdx:int)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Accoutrement

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Accoutrement.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AttachmentForward: Vector3` [Hidden, NotReplicated] | нет | E02 | 18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AttachmentPoint: CFrame` | нет | E02 | 00:2,20:12 | нет | высоко | Нет generic Accoutrement attachment motor; cosmetic Bobux avatar mechanism отдельный. |
| P `AttachmentPos: Vector3` [Hidden, NotReplicated] | нет | E02 | 18:4,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AttachmentRight: Vector3` [Hidden, NotReplicated] | нет | E02 | 18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `AttachmentUp: Vector3` [Hidden, NotReplicated] | нет | E02 | 18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### AlignOrientation

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AlignOrientation.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AlignType: AlignType` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CFrame: CFrame` | нет | E02 | 00:87,01:183,02:39,03:54,04:54,05:5,06:5,07:26,08:166,09:115,10:5,11:5,12:14,13:679,14:7,15:3,16:49,17:4,18:32,19:192,20:107 | нет | критично | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LookAtPosition: Vector3` [NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxAngularVelocity: float` | нет | E02 | 08:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxTorque: float` | нет | E02 | 00:2,08:1,09:4,13:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Mode: OrientationAlignmentMode` | нет | E02 | 00:24,01:1,02:3,08:1,09:12,20:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `PrimaryAxis: Vector3` [NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `PrimaryAxisOnly: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ReactionTorqueEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Responsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RigidityEnabled: boolean` | нет | E02 | 00:1,08:1,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `SecondaryAxis: Vector3` [NotReplicated] | нет | E02 | 16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### AlignPosition

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AlignPosition.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ApplyAtCenterOfMass: boolean` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ForceLimitMode: ForceLimitMode` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ForceRelativeTo: ActuatorRelativeTo` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxAxesForce: Vector3` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxForce: float` | нет | E02 | 00:11,07:3,08:1,09:13,10:1,11:1,13:5,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxVelocity: float` | нет | E02 | 00:1,06:4,07:3,08:1,13:8,14:2,16:1,17:1,18:5,19:1,20:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Mode: PositionAlignmentMode` | нет | E02 | 00:24,01:1,02:3,08:1,09:12,20:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Position: Vector3` | нет | E02 | 00:163,01:118,02:61,03:63,04:63,05:4,06:12,07:19,08:213,09:168,10:13,11:13,12:73,13:707,14:5,15:2,16:37,17:7,18:48,19:74,20:138 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ReactionForceEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Responsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RigidityEnabled: boolean` | нет | E02 | 00:1,08:1,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### AngularVelocity

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AngularVelocity.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AngularVelocity: Vector3` | нет | E02 | 00:1,02:2,09:4,13:2,16:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxTorque: float` | нет | E02 | 00:2,08:1,09:4,13:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ReactionTorqueEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RelativeTo: ActuatorRelativeTo` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### AnimationConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/AnimationConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AngularDamping: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularStrength: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `IsKinematic: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LinearDamping: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LinearStrength: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxForce: float` | нет | E02 | 00:11,07:3,08:1,09:13,10:1,11:1,13:5,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxTorque: float` | нет | E02 | 00:2,08:1,09:4,13:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Transform: CFrame` | нет | E02 | 01:8,02:2,08:4,09:5 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### BackpackItem

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/BackpackItem.yaml). inherits: `Model`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `TextureContent: Content` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `TextureId: ContentId` | нет | E02 | 00:15,01:1,08:1,09:7,13:4,16:4,18:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### BallSocketConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/BallSocketConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxFrictionTorque: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Radius: float` | нет | E02 | 00:2,01:1,02:3,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TwistLimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TwistLowerAngle: float` | нет | E02 | 01:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TwistUpperAngle: float` | нет | E02 | 01:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `UpperAngle: float` | нет | E02 | 01:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### ControllerBase

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ControllerBase.yaml). inherits: `Instance`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Active: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:24,01:9,02:4,07:3,08:16,09:14,12:8,18:1,20:11 | нет | высоко | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `BalanceRigidityEnabled: boolean` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| P `MoveSpeedFactor: float` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### ControllerSensor

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ControllerSensor.yaml). inherits: `SensorBase`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |

### CylindricalConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/CylindricalConstraint.yaml). inherits: `SlidingBallConstraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `AngularActuatorType: ActuatorType` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularLimitsEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularResponsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularRestitution: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularSpeed: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularVelocity: float` | нет | E02 | 00:1,02:2,09:4,13:2,16:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CurrentAngle: float` [ReadOnly, NotReplicated] | нет | E02 | 13:4,18:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `InclinationAngle: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LowerAngle: float` | нет | E02 | 16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxAngularAcceleration: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxTorque: float` | нет | E02 | 02:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RotationAxisVisible: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ServoMaxTorque: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `SoftlockAngularServoUponReachingTarget: boolean` [Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TargetAngle: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `UpperAngle: float` | нет | E02 | 01:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WorldRotationAxis: Vector3` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### FormFactorPart

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/FormFactorPart.yaml). inherits: `BasePart`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `FormFactor: FormFactor` [NotReplicated, Deprecated] | нет | E02 | 00:4,05:1,09:2,12:1,13:7,14:1,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `formFactor: FormFactor` [Hidden, NotReplicated, Deprecated] | нет | E02 | 03:1,04:1,16:2,17:4,18:11,19:7,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### HingeConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/HingeConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ActuatorType: ActuatorType` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularResponsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularSpeed: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `AngularVelocity: float` | нет | E02 | 00:1,02:2,09:4,13:2,16:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CurrentAngle: float` [ReadOnly, NotReplicated] | нет | E02 | 13:4,18:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LowerAngle: float` | нет | E02 | 16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxAcceleration: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxTorque: float` | нет | E02 | 02:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Radius: float` | нет | E02 | 00:2,01:1,02:3,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ServoMaxTorque: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `SoftlockServoUponReachingTarget: boolean` [Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TargetAngle: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `UpperAngle: float` | нет | E02 | 01:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### Instance

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Instance.yaml). inherits: `Object`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Archivable: boolean` | нет | E02 | 00:4,01:10,07:1,08:4,09:9,12:1,16:2,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `archivable: boolean` [Hidden, NotReplicated, Deprecated] | нет | E02 | 16:1,18:8,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Capabilities: SecurityCapabilities` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `IsInSandbox: boolean` [ReadOnly, NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Name: string` | частично | E50 | 00:597,01:245,02:33,03:71,04:71,05:9,06:19,07:23,08:280,09:315,10:21,11:21,12:82,13:961,14:31,15:6,16:96,17:14,18:56,19:63,20:125 | нет | высоко | Name/parenting hooks; Parent=nil и ancestry timing требуют полного контракта. |
| P `Parent: Instance` [NotReplicated] | частично | E50 | 00:1479,01:2042,02:304,03:113,04:113,05:18,06:21,07:37,08:409,09:728,10:32,11:32,12:135,13:3456,14:54,15:15,16:175,17:20,18:262,19:358,20:290 | нет | высоко | Name/parenting hooks; Parent=nil и ancestry timing требуют полного контракта. |
| P `PredictionMode: PredictionMode` [ReadOnly, NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Sandboxed: boolean` [NotReplicated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `AddTag(tag:string) → ()` | нет | E02 | 00:10,01:13,02:1,08:109,09:11,10:1,11:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `children() → Instances` [Deprecated] | нет | E02 | 00:10,01:27,02:9,03:12,04:12,05:1,08:1,09:15,13:29,14:1,17:1,18:30,19:23 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ClearAllChildren() → ()` | частично | E51 | 00:1,01:1,06:1,08:1,09:11,10:5,11:5,12:41,14:1,20:35 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `Clone() → Instance` | частично | E51 | 00:133,01:49,02:19,03:11,04:11,06:1,07:4,08:184,09:147,10:11,11:11,12:62,13:94,14:13,16:57,18:11,19:39,20:86 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `clone() → Instance` [Deprecated] | нет | E02 | 00:8,01:2,02:18,03:58,04:58,05:3,08:12,09:20,10:3,11:3,12:1,13:708,14:2,15:3,17:9,18:54,19:14,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Destroy() → ()` | частично | E51 | 00:321,01:136,02:49,06:10,07:20,08:193,09:215,10:9,11:9,12:27,13:52,14:7,16:92,20:68 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `destroy() → ()` [Deprecated] | нет | E02 | 00:9,01:37,02:15,08:10,09:9,13:24 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindFirstAncestor(name:string) → Instance?` | частично | E51 | 01:184,08:9,09:2,10:1,11:1 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `FindFirstAncestorOfClass(className:string) → Instance?` | частично | E51 | 01:5,07:1,08:18,09:3 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `FindFirstAncestorWhichIsA(className:string) → Instance?` | частично | E51 | 00:32,01:4,07:1,08:6,09:43,10:3,11:3 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `FindFirstChild(name:string, recursive:boolean) → Instance?` | частично | E51 | 00:320,01:119,02:20,03:33,04:33,05:4,06:19,07:20,08:189,09:211,10:18,11:18,12:32,13:600,14:28,16:112,17:11,18:45,19:2,20:88 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `findFirstChild(name:string, recursive:boolean) → Instance` [Deprecated] | нет | E02 | 00:1,01:3,03:53,04:53,05:1,10:1,11:1,12:2,13:1059,14:4,15:12,16:2,17:5,18:127,19:268,20:10 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindFirstChildOfClass(className:string) → Instance?` | частично | E51 | 00:33,01:17,02:7,06:15,07:13,08:22,09:51,14:2,16:27 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `FindFirstChildWhichIsA(className:string, recursive:boolean) → Instance?` | частично | E51 | 00:9,01:24,02:1,07:1,08:72,09:27,10:13,11:13 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `FindFirstDescendant(name:string) → Instance?` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetActor() → Actor?` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetAttribute(attribute:string) → Variant` | частично | E52 | 00:41,01:10,02:6,07:7,08:192,09:147,16:3 | T01,T02 | высоко | Metadata attributes/signals; не все allowed types/serialization/replication/read-only constraints Roblox. |
| M `GetAttributeChangedSignal(attribute:string) → RBXScriptSignal` | частично | E52 | 00:12,01:7,02:2,08:22,09:26 | T01,T02 | высоко | Metadata attributes/signals; не все allowed types/serialization/replication/read-only constraints Roblox. |
| M `GetAttributes() → Dictionary` | частично | E52 | 08:1,09:2 | T01,T02 | высоко | Metadata attributes/signals; не все allowed types/serialization/replication/read-only constraints Roblox. |
| M `GetChildren() → Instances` | частично | E51 | 00:244,01:98,02:10,03:16,04:16,05:7,06:9,07:13,08:194,09:132,10:11,11:11,12:60,13:488,14:16,16:81,17:4,18:24,19:67,20:163 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `getChildren() → Instances` [Deprecated] | нет | E02 | 01:10,08:1,18:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetDescendants() → Instances` | частично | E51 | 00:32,01:42,02:5,06:6,07:5,08:48,09:67,10:8,11:8,14:1 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `GetFullName() → string` | частично | E51 | 00:4,01:27,08:8,09:12,12:1,20:6 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `GetStyled(name:string, selector:string?) → Variant` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetStyledPropertyChangedSignal(property:string) → RBXScriptSignal` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetTags() → Array` | нет | E02 | 01:4,02:2,09:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `HasTag(tag:string) → boolean` | нет | E02 | 00:5,01:17,08:12,09:9,10:2,11:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsAncestorOf(descendant:Instance) → boolean` | частично | E51 | 00:4,02:1,08:2,13:3 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `IsDescendantOf(ancestor:Instance) → boolean` | частично | E51 | 00:9,01:28,02:2,06:1,07:5,08:33,09:21,12:1,13:2,16:2,20:6 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| M `isDescendantOf(ancestor:Instance) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsPropertyModified(property:string) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `QueryDescendants(selector:string) → Instances` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Remove() → ()` [Deprecated] | нет | E02 | 00:17,01:6,08:3,09:13,13:4,14:3,18:23,19:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `remove() → ()` [Deprecated] | нет | E02 | 00:28,01:53,02:13,03:53,04:53,05:6,07:2,08:40,09:64,10:2,11:2,12:16,13:1095,14:2,15:3,16:9,17:8,18:18,19:15,20:24 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemoveTag(tag:string) → ()` | нет | E02 | 00:4,01:9,02:1,08:3,09:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ResetPropertyToDefault(property:string) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetAttribute(attribute:string, value:Variant) → ()` | частично | E52 | 00:40,01:13,02:6,07:1,08:148,09:106,16:1 | T01,T02 | высоко | Metadata attributes/signals; не все allowed types/serialization/replication/read-only constraints Roblox. |
| M `WaitForChild(childName:string, timeOut:double) → Instance` | частично | E51 | 00:538,01:575,02:111,06:23,07:35,08:254,09:351,10:13,11:13,12:21,13:273,14:19,16:58,17:2,20:36 | нет | высоко | Реальное Instance дерево; class inheritance, destruction/event timing, clone references и WaitForChild scheduler не полностью эквивалентны. |
| E `AncestryChanged(child:Instance, parent:Instance)` | частично | E53 | 00:33,01:19,02:1,07:1,08:10,09:17,10:2,11:2,12:1,14:1,18:1 | нет | высоко | Есть native node event bridge; полные Roblox ancestor/order/timing/generic Changed контракты не доказаны. |
| E `AttributeChanged(attribute:string)` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `ChildAdded(child:Instance)` | частично | E53 | 00:16,01:26,02:1,03:14,04:14,05:5,06:5,07:10,08:18,09:23,10:3,11:3,12:11,13:10,14:9,15:2,16:27,17:3,18:11,19:9,20:18 | нет | высоко | Есть native node event bridge; полные Roblox ancestor/order/timing/generic Changed контракты не доказаны. |
| E `childAdded(child:Instance)` [Deprecated] | нет | E02 | 00:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `ChildRemoved(child:Instance)` | частично | E53 | 00:8,01:14,02:1,06:4,07:7,08:12,09:13,12:3,13:5,14:2,16:25,17:2,18:3,19:5,20:4 | нет | высоко | Есть native node event bridge; полные Roblox ancestor/order/timing/generic Changed контракты не доказаны. |
| E `DescendantAdded(descendant:Instance)` | нет | E02 | 00:7,01:11,02:1,06:2,07:1,08:4,09:6,10:1,11:1,12:1,16:1,20:2 | нет | высоко | Сигналы доступны через generic event fallback; рекурсивный Roblox producer не подтверждён. |
| E `DescendantRemoving(descendant:Instance)` | нет | E02 | 00:5,01:8,07:1,08:1,09:5,12:1,13:1,14:2,20:1 | нет | высоко | Сигналы доступны через generic event fallback; рекурсивный Roblox producer не подтверждён. |
| E `Destroying()` | частично | E53 | 00:8,08:112,09:6 | нет | высоко | Есть native node event bridge; полные Roblox ancestor/order/timing/generic Changed контракты не доказаны. |
| E `StyledPropertiesChanged()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### JointInstance

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/JointInstance.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Active: boolean` [ReadOnly, NotReplicated] | нет | E02 | 00:24,01:9,02:4,07:3,08:16,09:14,12:8,18:1,20:11 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `C0: CFrame` | частично | E47 | 00:10,01:9,02:1,03:1,04:1,05:5,07:1,08:5,09:4,12:2,13:22,14:2,16:7,18:13,19:9,20:78 | T06 | высоко | Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives. |
| P `C1: CFrame` | частично | E47 | 00:7,01:11,05:6,07:1,08:4,09:5,12:1,13:21,16:5,17:2,18:8,19:7,20:76 | T06 | высоко | Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives. |
| P `Enabled: boolean` | частично | E47 | 00:249,01:45,02:25,06:3,07:3,08:118,09:68,10:15,11:15,12:1,13:499,14:8,16:64,17:2,18:14,19:2,20:19 | T06 | высоко | Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives. |
| P `Part0: BasePart` | частично | E47 | 00:18,01:11,03:1,04:1,05:2,07:1,08:14,09:25,12:2,13:29,14:2,16:16,17:3,18:14,19:10,20:77 | T06 | критично | Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives. |
| P `Part1: BasePart` | частично | E47 | 00:20,01:11,03:28,04:28,05:2,07:1,08:15,09:25,12:2,13:32,14:2,16:16,17:3,18:15,19:10,20:77 | T06 | критично | Ссылки/frames создают Generic6DOF joint для meshes; не multipart character rig/полные limits/drives. |
| P `part1: BasePart` [Hidden, NotReplicated, Deprecated] | нет | E02 | 08:1,13:2,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### LineForce

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/LineForce.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ApplyAtCenterOfMass: boolean` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `InverseSquareLaw: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Magnitude: float` | нет | E02 | 00:24,01:27,02:13,06:7,07:12,08:53,09:47,12:2,14:1,16:2,18:5,20:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxForce: float` | нет | E02 | 00:11,07:3,08:1,09:13,10:1,11:1,13:5,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ReactionForceEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### LinearVelocity

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/LinearVelocity.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ForceLimitMode: ForceLimitMode` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ForceLimitsEnabled: boolean` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LineDirection: Vector3` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LineVelocity: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxAxesForce: Vector3` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxForce: float` | нет | E02 | 00:11,07:3,08:1,09:13,10:1,11:1,13:5,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxPlanarAxesForce: Vector2` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `PlaneVelocity: Vector2` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `PrimaryTangentAxis: Vector3` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ReactionForceEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RelativeTo: ActuatorRelativeTo` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `SecondaryTangentAxis: Vector3` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `VectorVelocity: Vector3` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `VelocityConstraintMode: VelocityConstraintMode` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### Model

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Model.yaml). inherits: `PVInstance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `LevelOfDetail: ModelLevelOfDetail` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `ModelStreamingMode: ModelStreamingMode` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `PrimaryPart: BasePart` | частично | E54 | 00:43,01:16,07:2,08:33,09:47,10:1,11:1,12:1,13:25,14:3,15:2,16:25,17:2,20:1 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| P `Scale: float` [NotReplicated, NotScriptable] | нет | E02 | 00:41,01:36,02:5,05:1,08:14,09:34,12:21,13:42,14:1,16:7,18:8,19:2,20:22 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `WorldPivot: CFrame` [NotReplicated] | частично | E54 | 00:8 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `AddPersistentPlayer(playerInstance:Player) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BreakJoints() → ()` [Deprecated] | частично | E54 | 00:13,01:4,03:7,04:7,05:2,09:5,10:1,11:1,13:4,14:1,16:3,17:2,18:6,19:6 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `breakJoints() → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetBoundingBox() → Tuple` | нет | E02 | 00:7,01:2,08:3,09:5 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetExtentsSize() → Vector3` | нет | E02 | 01:2,07:2,08:2,09:17,12:2,20:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetModelCFrame() → CFrame` [Deprecated] | частично | E54 | 00:9,01:1,07:1,08:1,09:6,12:2,20:2 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `GetModelSize() → Vector3` [Deprecated] | частично | E54 | 00:4,09:3 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `GetPersistentPlayers() → List<Player>` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPrimaryPartCFrame() → CFrame` [Deprecated] | нет | E02 | 00:1,01:3,07:1,08:25,09:3,14:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetScale() → float` | нет | E02 | 01:1,06:4,07:3,08:3,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `MakeJoints() → ()` [Deprecated] | частично | E54 | 00:15,03:24,04:24,05:1,09:6,10:3,11:3,13:3,14:1,16:4,18:4,19:4,20:1 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `makeJoints() → ()` [Deprecated] | нет | E02 | 03:27,04:27,15:2,16:2,17:1,18:3,19:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `move(location:Vector3) → ()` [Deprecated] | нет | E02 | 00:8,02:1,08:5,09:2,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `MoveTo(position:Vector3) → ()` | частично | E54 | 00:3,01:1,02:1,03:1,04:1,05:1,07:1,08:22,09:5,12:1,13:523,14:1,16:13,18:5,19:4,20:1 | T06 | критично | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `moveTo(location:Vector3) → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RemovePersistentPlayer(playerInstance:Player) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ResetOrientationToIdentity() → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `ScaleTo(newScaleFactor:float) → ()` | нет | E02 | 00:1,08:112,09:4 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetIdentityOrientation() → ()` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `SetPrimaryPartCFrame(cframe:CFrame) → ()` [Deprecated] | частично | E54 | 00:26,01:3,08:44,09:2,13:28,14:4,16:23,20:1 | T06 | высоко | Собственные model transform/reference/physics adapters; весь Roblox Model контракт не установлен. |
| M `TranslateBy(delta:Vector3) → ()` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Motor

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Motor.yaml). inherits: `JointInstance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `CurrentAngle: float` [NotReplicated] | нет | E02 | 13:4,18:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `DesiredAngle: float` | нет | E47 | 00:1,13:8,14:2,17:1,18:5 | нет | высоко | Joint refresh не применяет Motor drive/DesiredAngle/MaxVelocity; отдельные Bobux vehicle motors не полный Motor API. |
| P `MaxVelocity: float` | нет | E47 | 00:1,06:4,07:3,08:1,13:8,14:2,16:1,17:1,18:5,19:1,20:1 | нет | высоко | Joint refresh не применяет Motor drive/DesiredAngle/MaxVelocity; отдельные Bobux vehicle motors не полный Motor API. |
| M `SetDesiredAngle(value:float) → ()` | нет | E02 | 06:4,07:3,08:1,16:1,20:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### Object

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Object.yaml). inherits: `—`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ClassName: string` [ReadOnly, NotReplicated] | частично | E55 | 00:37,01:362,02:10,06:1,08:8,09:36,13:2,14:2,16:1,20:7 | нет | высоко | Из roblox_class metadata; не независимая immutable schema/type model. |
| P `className: string` [ReadOnly, NotReplicated, Deprecated] | нет | E02 | 01:2,03:19,04:19,05:6,06:4,07:3,08:1,13:29,14:4,16:23,17:7,18:26,19:54,20:62 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPropertyChangedSignal(property:string) → RBXScriptSignal` | нет | E02 | 00:49,01:46,02:22,07:11,08:55,09:51,10:8,11:8,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsA(className:string) → boolean` | частично | E56 | 00:263,01:131,02:20,06:15,07:23,08:204,09:172,10:14,11:14,12:38,13:41,14:10,16:67,18:3,20:67 | нет | высоко | Классы сопоставляются ограниченными списками, не всей official inheritance database. |
| M `isA(className:string) → boolean` [Deprecated] | нет | E02 | 01:2,07:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| E `Changed(property:string)` | нет | E02 | 00:182,01:32,02:9,03:12,04:12,05:2,06:7,07:5,08:114,09:106,10:1,11:1,12:16,13:977,14:14,15:1,16:27,17:5,18:7,19:8,20:19 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

### PVInstance

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/PVInstance.yaml). inherits: `Instance`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Origin: CFrame` [NotReplicated, NotScriptable] | нет | E02 | 00:9,01:7,02:5,07:2,08:13,09:8,12:1,20:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| P `Pivot Offset: CFrame` [NotReplicated, NotScriptable] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPivot() → CFrame` | частично | E57 | 00:9,02:1,08:45,09:30,14:2 | T10 | высоко | Node3D/Model transform routines; PrimaryPart/pivot и physics assemblies имеют ограничения. |
| M `PivotTo(targetCFrame:CFrame) → ()` | частично | E57 | 00:2,01:1,02:1,08:41,09:31,14:2 | T10 | высоко | Node3D/Model transform routines; PrimaryPart/pivot и physics assemblies имеют ограничения. |

### Part

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Part.yaml). inherits: `FormFactorPart`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Shape: PartType` [NotReplicated] | частично | E58 | 00:10,01:4,02:5,03:1,04:1,05:1,08:10,09:10,10:4,11:4,13:3,17:4,18:9,19:2,20:3 | нет | высоко | Box/Sphere/Cylinder mesh adapter; геометрия/масса/shape properties Roblox не полностью доказаны. |

### Plane

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Plane.yaml). inherits: `PlaneConstraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |

### PlaneConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/PlaneConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |

### PrismaticConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/PrismaticConstraint.yaml). inherits: `SlidingBallConstraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |

### RigidConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/RigidConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| Собственных публичных членов нет | см. inherits | — | — | — | — | Общий Instance API описан отдельно. |

### RodConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/RodConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `CurrentDistance: float` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Length: float` | нет | E02 | 00:2,01:6,06:2,08:1,09:7,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitAngle0: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitAngle1: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Thickness: float` | нет | E02 | 00:3,01:2,02:1,06:1,08:8,09:6 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### RopeConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/RopeConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `CurrentDistance: float` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Length: float` | нет | E02 | 00:2,01:6,06:2,08:1,09:7,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Thickness: float` | нет | E02 | 00:3,01:2,02:1,06:1,08:8,09:6 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WinchEnabled: boolean` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WinchForce: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WinchResponsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WinchSpeed: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `WinchTarget: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### SensorBase

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/SensorBase.yaml). inherits: `Instance`. Профиль: CCL отдельно от классического Humanoid.

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `UpdateType: SensorUpdateType` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| M `Sense() → ()` [Deprecated] | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |
| E `OnSensorOutputChanged()` | нет | E02 | — | нет | средне | CCL отдельный профиль: ControllerManager/Sensor/Controller physics pipeline отсутствует. |

### SlidingBallConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/SlidingBallConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ActuatorType: ActuatorType` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CurrentPosition: float` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LinearResponsiveness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LowerLimit: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxAcceleration: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MotorMaxForce: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `ServoMaxForce: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Size: float` | нет | E02 | 00:162,01:100,02:59,03:1,04:1,05:7,06:11,07:14,08:192,09:137,10:7,11:7,12:47,13:106,14:7,16:32,17:8,18:27,19:48,20:58 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `SoftlockServoUponReachingTarget: boolean` [Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Speed: float` | нет | E02 | 00:2,01:13,07:1,08:3,09:5,13:3,14:2,18:1,20:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `TargetPosition: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `UpperLimit: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Velocity: float` | нет | E02 | 00:66,01:22,03:33,04:33,05:3,07:6,08:6,09:29,10:5,11:5,12:2,13:40,14:4,15:1,16:9,17:4,18:19,19:110,20:6 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### SpringConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/SpringConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Coils: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CurrentLength: float` [ReadOnly, NotReplicated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Damping: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `FreeLength: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxForce: float` | нет | E02 | 00:11,07:3,08:1,09:13,10:1,11:1,13:5,16:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxLength: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MinLength: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Radius: float` | нет | E02 | 00:2,01:1,02:3,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Stiffness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Thickness: float` | нет | E02 | 00:3,01:2,02:1,06:1,08:8,09:6 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### Torque

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/Torque.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `RelativeTo: ActuatorRelativeTo` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Torque: Vector3` | нет | E02 | 00:5,09:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### TorsionSpringConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/TorsionSpringConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `Coils: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `CurrentAngle: float` [ReadOnly, NotReplicated] | нет | E02 | 13:4,18:2 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Damping: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitEnabled: boolean` [Hidden, Deprecated] | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxAngle: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxTorque: float` | нет | E02 | 00:2,08:1,09:4,13:2,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Radius: float` | нет | E02 | 00:2,01:1,02:3,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Stiffness: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### UniversalConstraint

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/UniversalConstraint.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `LimitsEnabled: boolean` | нет | E02 | 01:2,07:1,09:1,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `MaxAngle: float` | нет | E02 | — | нет | средне | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Radius: float` | нет | E02 | 00:2,01:1,02:3,09:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Restitution: float` | нет | E02 | 01:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### VectorForce

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/VectorForce.yaml). inherits: `Constraint`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| P `ApplyAtCenterOfMass: boolean` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `Force: Vector3` | нет | E02 | 00:12,01:1,09:16,16:3 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |
| P `RelativeTo: ActuatorRelativeTo` | нет | E02 | 00:1 | нет | высоко | Нет solver adapter этого constraint/force API; metadata и похожие имена в JOINT_CLASSES не создают нужную физику. |

### WorldRoot

[Официальный YAML](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/WorldRoot.yaml). inherits: `Model`. Профиль: общий/классический (R15 не подразумевается).

| API / тип | Bobux | Evidence | Карты: кандидаты | Автотест | Важность | Ограничение |
|---|---|---|---|---|---|---|
| M `ArePartsTouchingOthers(partList:Instances, overlapIgnored:float) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Blockcast(cframe:CFrame, size:Vector3, direction:Vector3, params:RaycastParams) → RaycastResult?` | нет | E02 | 02:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `BulkMoveTo(partList:Instances, cframeList:Array, eventMode:BulkMoveMode) → ()` | частично | E59 | 02:2,08:6,09:5 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `CollisionGroupsAreCollidable(name1:string, name2:string) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `CollisionGroupSetCollidable(name1:string, name2:string, collidable:boolean) → ()` | нет | E02 | 00:1,01:1,14:1,16:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPartOnRay(ray:Ray, ignoreDescendantsInstance:Instance, terrainCellsAreCubes:boolean, ignoreWater:boolean) → Tuple` [Deprecated] | частично | E59 | 00:2,01:8,05:1,08:1,12:1,20:5 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `findPartOnRay(ray:Ray, ignoreDescendantsInstance:Instance, terrainCellsAreCubes:boolean, ignoreWater:boolean) → Tuple` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPartOnRayWithIgnoreList(ray:Ray, ignoreDescendantsTable:Instances, terrainCellsAreCubes:boolean, ignoreWater:boolean) → Tuple` [Deprecated] | частично | E59 | 00:8,01:9,07:6,08:6,09:11,12:3,14:1,16:1,20:5 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `FindPartOnRayWithWhitelist(ray:Ray, whitelistDescendantsTable:Instances, ignoreWater:boolean) → Tuple` [Deprecated] | нет | E02 | 01:3,07:2,08:2,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPartsInRegion3(region:Region3, ignoreDescendantsInstance:Instance, maxParts:int) → List<BasePart>` [Deprecated] | частично | E59 | 01:1,05:1,09:9,12:1,20:2 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `findPartsInRegion3(region:Region3, ignoreDescendantsInstance:Instance, maxParts:int) → List<BasePart>` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPartsInRegion3WithIgnoreList(region:Region3, ignoreDescendantsTable:Instances, maxParts:int) → List<BasePart>` [Deprecated] | нет | E02 | 01:1,09:2 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `FindPartsInRegion3WithWhiteList(region:Region3, whitelistDescendantsTable:Instances, maxParts:int) → List<BasePart>` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetMaxCollisionGroups() → int` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `GetPartBoundsInBox(cframe:CFrame, size:Vector3, overlapParams:OverlapParams) → List<BasePart>` | частично | E59 | 00:5,02:1,08:3,09:17 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `GetPartBoundsInRadius(position:Vector3, radius:float, overlapParams:OverlapParams) → List<BasePart>` | частично | E59 | 08:1 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `GetPartsInPart(part:BasePart, overlapParams:OverlapParams) → List<BasePart>` | нет | E60 | 08:2 | нет | высоко | GetPartBoundsInBox не реализует exact GetPartsInPart; публичного метода нет. |
| M `GetRegisteredCollisionGroups() → Array` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsCollisionGroupRegistered(name:string) → boolean` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsRegion3Empty(region:Region3, ignoreDescendentsInstance:Instance) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `IsRegion3EmptyWithIgnoreList(region:Region3, ignoreDescendentsTable:Instances) → boolean` [Deprecated] | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Raycast(origin:Vector3, direction:Vector3, raycastParams:RaycastParams) → RaycastResult?` | частично | E59 | 00:2,01:6,02:2,06:2,07:1,08:30,09:13,12:1,20:1 | T11,T12 | высоко | Есть реальные spatial queries/poses. Bounding-box/filters/CanQuery/result Material тип и terrain отличия требуют полной матрицы. |
| M `RegisterCollisionGroup(name:string) → ()` | нет | E02 | 00:1 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `RenameCollisionGroup(from:string, to:string) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Shapecast(part:BasePart, direction:Vector3, params:RaycastParams, cframeOverride:CFrame?, sizeOverride:Vector3?) → RaycastResult?` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `Spherecast(position:Vector3, radius:float, direction:Vector3, params:RaycastParams) → RaycastResult?` | нет | E02 | 08:3 | нет | высоко | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |
| M `UnregisterCollisionGroup(name:string) → ()` | нет | E02 | — | нет | средне | Dedicated public API/producer не найден при чтении wrapper/runtime. Generic metadata/Node fallback не функциональная поддержка. |

## Воспроизводимость

`python tools/character_parity/inventory_character_api.py` читает pinned schema и без запуска Luau/игры обновляет static corpus candidates. `--refresh-docs` явно обновляет официальный snapshot. `python tools/character_parity/render_api_matrix.py` строит эту таблицу и JSON из ручного route registry; после production изменений registry следует рецензировать.

Артефакты: [official schema](../tests/roblox_humanoid/phase_a/creator_docs_api.json), [typed audit decisions и source hashes](../tests/roblox_humanoid/phase_a/api_matrix.json), [corpus/Source hashes](../tests/roblox_humanoid/phase_a/map_api_candidates.json), [enum regex candidates](../tests/roblox_humanoid/phase_a/map_enum_candidates.json). Все regex ограничения записаны в артефактах. Factual API перечисления не заменяют обязательные собственные измерения/holdout/видео и фазовые регрессии.
