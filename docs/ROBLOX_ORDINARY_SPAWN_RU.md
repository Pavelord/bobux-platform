# A2: обычная загрузка персонажа и наследование StarterPlayer

Срез на **16 октября 2026**. Это native-наблюдения официального Studio **0.743.0.7431133**, fixture **`2026-10-15-a2-ordinary-native-v2`**. **Bobux parity: NOT_IMPLEMENTED_NOT_CALIBRATED.** Наблюдения getters не доказывают совпадение физики, timing callbacks или поведения камеры Bobux.

## Покрытие и границы

| Путь / профиль | Независимые Play / joins | Статус этого среза |
|---|---:|---|
| Обычный `LoadCharacterAsync`, фактический R15, default | 5/5: Play 1–3 train, 4–5 holdout | **OBSERVED**, 50 генераций Character; 25 до и 25 после изменения StarterPlayer |
| Тот же путь, фактический R15, altered | 5/5: Play 1–3 train, 4–5 holdout | **OBSERVED**, 50 генераций Character; 25 до и 25 после изменения StarterPlayer |
| Обычный native R6, default / altered | 0/5 и 0/5 | **NOT_RUN**, R15 не подставляется вместо R6 |
| `LoadCharacterWithHumanoidDescriptionAsync` | 0 | **NOT_RUN**; отдельный продолженный стенд ещё не выполнен |

Один Play содержит **один initial join**, пять первоначальных native loads и пять loads после мутации StarterPlayer. Это десять генераций, включая девять respawns, а не десять независимых joins. Приняты **10 разных session IDs/run IDs**: пять default и пять altered, всего 100 генераций и 90 respawns. Train/holdout объявлены до captures; fitting и подбор допусков по этим данным не выполнялись. Обе группы R15 завершены как наблюдения этого пути; A2 целиком остаётся **PARTIAL**.

[Coverage aggregate](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-coverage-r15-both-profiles.json) подтверждает две OBSERVED группы R15, 10/20 предусмотренных independent joins, обе группы R6 NOT_RUN и `full_A2_complete=false`. Общий `BLOCKED_INCOMPLETE` относится к отсутствующим путям/группам; он не превращает успешные R15 captures в native failures.

## Условия измерения

Заморожены [registration.json](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/registration.json) и [places_manifest.json](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/places_manifest.json). Registration SHA256: `b2f02492b81644565aed45b7d4fb6798318457b7d995a12197807e132a7dd273`. Анализатор `tools/character_parity/analyze_ordinary_spawn.py` SHA256: `7d495e79f439fd70bdd471af49e2c82017536d41130206fde480c337a7e2dfc1`.

Repo-owned byte-exact копии 20 первоначальных XML places и обоих registration/manifest файлов находятся в [ordinary_spawn/frozen_v2](../tools/roblox_character_experiments/ordinary_spawn/frozen_v2/). Для запуска используется новая рабочая копия XML; frozen оригиналы не пересохраняются. Исторический preregistration SOURCE_READY статус внутри этих файлов сохраняется и не заменяет статусы фактически полученных captures.

В месте **до join** заданы LoadCharacterAppearance=false, LuaCharacterController=Legacy и Players.CharacterAutoLoads=false. Default-профиль оставляет девять исследуемых inheritance fields неуказанными в XML; числа в таблицах ниже — наблюдавшиеся native getters, а не заполненные предположениями defaults. Altered задаёт девять значений до join. Загрузка вызывается публичным `Player:LoadCharacterAsync()` после установки probes. Это управляемая загрузка обычного native Character; время автоматического spawn не исследовано.

StarterCharacter, StarterHumanoid, custom Character и присваивания Player.Character/RigType не используются. Фактический RigType читается с Humanoid; расхождение с coverage label блокирует case. Сохранены пять точек на каждой генерации **на сервере и клиенте отдельно**: CharacterAdded immediate, первый PostSimulation, +0.25, +1 и +3 wall seconds. Истинное раннее отсутствие Humanoid/HRP допустимо; готовность и живой Character обязательны к +3s. Client/server `os.clock` имеют разные начала, поэтому их wall timestamps не задают общую временную шкалу.

Raw экспортирован через существующий Zstd/Base64/SHA256 transport, проверен на полноту и совпадение bytes/hash. Анализатор проверяет регистрацию, paired server stream, actual rig, generations/current Character, пять точек, native enum/boolean types, нижние границы delayed ages и live mutation window. Изменение только StarterPlayer проверяется как вход эксперимента; наследуемые результаты не подгоняются к ожидаемому числу. Stock scripts остаются установленными; их Source, native assets и animation keyframes не экспортируются. AvatarJointUpgrade/ClassicDeath остаются **NOT_OBSERVABLE**.

## R15/default: пять независимых joins

На **всех 25 первоначальных и 25 последующих генерациях**, на +3s с обеих сторон, получены следующие значения. `true` и `false` — реальные boolean, не результаты truthiness/подстановки.

| StarterPlayer input → Humanoid property | Генерации 1–5 каждого Play | StarterPlayer после мутации | Новые Humanoid, генерации 6–10 |
|---|---:|---:|---:|
| CharacterWalkSpeed → WalkSpeed | 16 | 31 | 31 |
| CharacterJumpPower → JumpPower | 50 | 44 | 44 |
| CharacterJumpHeight → JumpHeight | 7.199999809265137 | 5.5 | 5.5 |
| CharacterUseJumpPower → UseJumpPower | true | true | true |
| CharacterMaxSlopeAngle → MaxSlopeAngle | 89 | 55 | 55 |
| CharacterBreakJointsOnDeath → BreakJointsOnDeath | true | true | true |

HipHeight=2, Health=100, MaxHealth=100, AutoRotate=true, RequiresNeck=true и фактический RigType=R15/Value=1 сохраняются во всех этих +3s observations. Неизменившиеся boolean поля default-профиля сами по себе не проверяют поведение при false. Из этих getters также не выводятся фактическая скорость движения, высота траектории прыжка либо допустимый уклон физического контакта.

**Живой Character пятой генерации не получает новые значения сразу при изменении StarterPlayer.** Серверные before/after snapshots подтверждают тот же current Character поколения 5, живой Humanoid/HRP и отсутствие изменений в измеряемых Player/Humanoid dictionaries. Только последующие native loads показывают новые WalkSpeed/JumpPower/JumpHeight/MaxSlopeAngle.

Отдельно наблюдалась камера Player:

| Объект / момент | CameraMinZoomDistance | CameraMaxZoomDistance | AutoJumpEnabled |
|---|---:|---:|---|
| StarterPlayer перед join | 0.5 | 400 | true |
| Player на +3s первоначальных генераций | 0.5 | 400 | true |
| StarterPlayer после мутации | 1 | 90 | true |
| Тот же Player после мутации и на +3s новых генераций | **0.5** | **400** | true |

Player.CameraMode=Classic/Value=0. CameraMode в этом эксперименте не меняется; наследование LockFirstPerson не измерено. Default-группа показывает раздельную жизнь изменённого StarterPlayer и уже существующего Player. Для различения prejoin boolean/camera inputs существенен altered-профиль ниже.

## R15/altered: пять независимых joins

Пять actual captures имеют по десять OBSERVED generations, разные run IDs и тот же frozen fixture/analyzer. Сверены все **50 altered генераций в обоих realms** по raw +3s rows, а не только filename/итоговый статус. До join StarterPlayer содержит WalkSpeed=23, JumpPower=61, JumpHeight=9, UseJumpPower=false, MaxSlopeAngle=37, BreakJointsOnDeath=false, AutoJumpEnabled=false, camera limits=2…60. После пятой генерации каждого Play сервер меняет только StarterPlayer на тот же заранее объявленный набор 31/44/5.5/true/55/true/true и 1…90.

| Getter на +3s | Generations 1–5: 25 наблюдений на каждый realm | Generations 6–10: 25 наблюдений на каждый realm |
|---|---|---|
| Humanoid WalkSpeed / JumpPower / JumpHeight | 23 / 61 / 9 | 31 / 44 / 5.5 |
| Humanoid UseJumpPower / MaxSlopeAngle / BreakJointsOnDeath | false / 37 / false | true / 55 / true |
| Player CameraMin / CameraMax / AutoJumpEnabled | **2 / 60 / false** | **2 / 60 / false** |

Во всех пяти Play живой Character поколения 5 и Player в server before/after mutation window не изменили измеряемые dictionaries. Изменения StarterPlayer отразились на свойствах будущих Humanoid, но не обновили уже существующий Player camera snapshot. HipHeight=2, Health=100, MaxHealth=100, AutoRotate=true, RequiresNeck=true и actual RigType=R15 сохраняются во всех 50 altered final observations с обеих сторон.

**Начальное событие join нельзя считать барьером готовности Player properties.** Во всех пяти altered server PlayerAdded probes ещё записаны AutoJumpEnabled=true и camera=0.5…400. Client probe при attachment уже видит false и 2…60; server CharacterAdded_immediate также видит false и 2…60. Между этими наблюдениями нет общей client/server временной шкалы. Не установлен точный момент или producer применения Player defaults; вывод «копировать всё непосредственно в PlayerAdded callback» этими данными не доказан.

**Humanoid.AutoJumpEnabled различается по сторонам.** На +3s у всех **50 altered client Humanoid — false**, а у всех **50 server Humanoid — true**. Это остаётся так и после смены StarterPlayer.AutoJumpEnabled на true, при сохранении Player.AutoJumpEnabled=false. Клиентское значение согласуется с сохранённым Player flag, но причинный механизм/вклад standard controls отдельно не измерен. Не следует заменять этот результат общим правилом «каждый Humanoid копирует текущий StarterPlayer.AutoJumpEnabled».

В первом client CharacterAdded_immediate Humanoid ещё отсутствует во всех пяти altered Play. В первом PostSimulation он отсутствует только у Play 1; у Play 2–5 уже присутствует. К +0.25s он наблюдается во всех пяти первых генерациях. Это ранняя асинхронная готовность native модели, а не причина создавать запасной custom Character; фиксированное число кадров до готовности из данных не выводится.

## Lifecycle и evidence

В каждом из десяти принятых Play обе стороны наблюдают 10 CharacterAdded и 9 CharacterRemoving, с согласованными generations 1…10. CharacterAppearanceLoaded не наблюдается при явно отключённом LoadCharacterAppearance; отсутствие сохранено как observation/warning, а не автоматически объявлено багом. События с обеих сторон не объединяются в искусственно синхронизированный порядок.

Все файлы лежат в `tests/roblox_humanoid/phase_a/ordinary_spawn_v2/`. Для default Play 1/2 используются только reviewed2 analyses; для Play 3–5 — reviewed-final; для altered Play 1–5 — перечисленные `.analysis.json`. Предыдущие analyses и source-review исправления не переписывают raw.

| Сессия | Split | Run ID | Trusted analysis |
|---|---|---|---|
| R15/default Play 1 | train | `9faa1be0-5e44-4410-8857-336e2b3faf0a` | [reviewed2](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-15-r15-default-play1.analysis-reviewed2.json) |
| R15/default Play 2 | train | `571fa094-609a-44eb-9605-813733c73d06` | [reviewed2](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-15-r15-default-play2.analysis-reviewed2.json) |
| R15/default Play 3 | train | `2b5ce90a-8592-4900-84d8-a109f68b4273` | [reviewed-final](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-15-r15-default-play3.analysis-reviewed-final.json) |
| R15/default Play 4 | holdout | `bed82350-fda3-410e-bfa6-03fbbaa81a6d` | [reviewed-final](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-15-r15-default-play4.analysis-reviewed-final.json) |
| R15/default Play 5 | holdout | `94279bc4-9c31-4d98-85a0-2f29afcfc1e7` | [reviewed-final](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-15-r15-default-play5.analysis-reviewed-final.json) |
| R15/altered Play 1 | train | `72479e8c-a9b4-4f6a-823d-e07cfa523c54` | [analysis](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-r15-altered-play1.analysis.json) |
| R15/altered Play 2 | train | `2c889ee1-6381-4322-9a4c-84efd9ed834b` | [analysis](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-r15-altered-play2.analysis.json) |
| R15/altered Play 3 | train | `14f205ab-6f02-4f5d-94c8-188e2e242cc5` | [analysis](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-r15-altered-play3.analysis.json) |
| R15/altered Play 4 | holdout | `a53a37a7-0eec-43aa-9201-992e017df0cd` | [analysis](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-r15-altered-play4.analysis.json) |
| R15/altered Play 5 | holdout | `bdff1d90-55fa-41d0-83dd-19ddfe0cdc46` | [analysis](../tests/roblox_humanoid/phase_a/ordinary_spawn_v2/2026-10-16-r15-altered-play5.analysis.json) |

Raw SHA256 (имя raw соответствует тому же Play, окончание `.raw.log`):

| Capture | Raw SHA256 |
|---|---|
| default Play 1 | `ab5cb2659e56865062e80f3f7b37ed715d6b62272a0325ec20f8736d0497de06` |
| default Play 2 | `b653f05229577be95d34e3c7fe33dd0b6535a7c1e2ef0b441f25066eb481cbe3` |
| default Play 3 | `91ab1363b2c9f546d574289e0c2c4b51ddc06c9667cc88698b6e2f3e6b36ea82` |
| default Play 4 | `511d3811faa82c1b242cb2cef67e0325ffd096b72b9faa77865cafb117a56702` |
| default Play 5 | `37639d798d1527a9217fa049e5c67e14afccf52c0b492e4c4b6487efad9d42d1` |
| altered Play 1 | `f5b7aad6d289baa73841fd4bf18f3d4e0e2ca9ca63245894a0f9b04044e7f86e` |
| altered Play 2 | `206d1b3527cdf680a2bb5c66634efea508d6b23fd109cc8792bbbd46e857813d` |
| altered Play 3 | `574d8a08b8819a310931bc52287875cc69a32634716cf2079234185097d9670f` |
| altered Play 4 | `23ff56a85f90c24590a5f37875eeb9471912f176e02a2a63b2ff009d6208bcb7` |
| altered Play 5 | `4448cd8a4fa99ba596c1a8a2495d67a18688095f390138a03c23e11c3d648792` |

## Текущие consumer gaps Bobux: только source inventory

Проверены перечисленные production пути без правок/запуска Godot. Наличие direct Humanoid setter не означает наследования StarterPlayer и не является новым parity PASS.

| Путь | Что есть сейчас | Незавершённое поведение |
|---|---|---|
| `autoload/lua_script_engine.gd:6625` `_ensure_local_player_nodes` | Создаёт Player, GUI, Backpack, PlayerScripts; `:6659` копирует StarterPlayerScripts | Join-time scalar Player snapshot из StarterPlayer не найден |
| `autoload/lua_script_engine.gd:6663` local bind, `:6706` network bind | Привязывают существующий Character и копируют StarterCharacterScripts; network join копирует PlayerScripts `:6731` | Маппинга CharacterWalkSpeed/JumpPower/JumpHeight/UseJumpPower/MaxSlopeAngle/BreakJointsOnDeath в новый Humanoid нет |
| `autoload/lua_script_engine.gd:1747` generic setter | Сохраняет generic properties/metadata | Запись Character* полей StarterPlayer сама по себе не вызывает character initialization |
| `scripts/player/player.gd:475` physics configuration, `:3535` Humanoid API node | Берёт WalkSpeed/JumpPower из HumanoidConfig, заполняет proxy metadata; `:3555` выставляет R6 | Не получает эти defaults из текущего StarterPlayer при native-like new-character boundary; это отдельный существующий R6 runtime, не реализация native R15 |
| `autoload/lua_script_engine.gd:1563`, `:1573`; `scripts/player/player.gd:3796`, `:3805` | Direct Humanoid WalkSpeed/JumpPower меняют logical scalar/body и передают typed command | Это путь прямой записи Humanoid, не Starter inheritance |
| `autoload/lua_script_engine.gd:1583`, `:866`; `scripts/player/player.gd:3819` | Direct JumpHeight/UseJumpPower хранятся; jump calculation читает их | Вход от StarterPlayer при новой генерации отсутствует |
| `autoload/lua_script_engine.gd:1597`; `scripts/player/player.gd:4041` | BreakJointsOnDeath хранится/forward; death visuals читают flag | CharacterBreakJointsOnDeath не наследуется автоматически |
| `autoload/lua_script_engine.gd:1589`, `:868`; `autoload/imported_place_network.gd:803`; `scripts/player/player.gd:4826` | MaxSlopeAngle сохраняется в Humanoid metadata | Forward whitelist и network command whitelist не включают slope; body floor_max_angle берётся из статического config |
| `autoload/lua_script_engine.gd:1597`; `scripts/player/player.gd:3811` | AutoJumpEnabled имеет metadata/forward маршрут | Активный auto-jump consumer в player code не найден; наблюдаемое native client/server различие нельзя подменять единым scalar copy |
| `scripts/player/player.gd:1753` | Camera distance clamp задаётся локальным диапазоном 0…20 | Чтения Player.CameraMinZoomDistance/CameraMaxZoomDistance для реального zoom не найдено |
| `autoload/lua_script_engine.gd:2637` LoadCharacter; `scripts/player/player.gd:4094`; `autoload/lua_script_engine.gd:7497` | Вызывает force_respawn существующего bound Character; LoadCharacter и поздний restore оба могут отправить CharacterAdded | Не создаёт новую native-like identity/generation и не перечитывает Starter defaults; нельзя считать эти события независимыми joins |

Эти gaps **не исправлены данным документом**. При реализации необходимо сохранить измеренное различие Player snapshot и будущего Humanoid, отдельно проверить R6 и description path; producer/точный timing Player initialization пока не установлен. Этот срез не задаёт новые правила сетевой авторитетности, приоритет map movement settings либо политику автоматической миграции старых режимов.
