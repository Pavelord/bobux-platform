# Roblox Character Parity: текущие доказательства и ворота

Снимок от **18 октября 2026**. Общий статус: **IN_PROGRESS**. Это предварительный отчёт, а не заявление о завершении фаз A–J или готовности к выпуску. Архитектурный план: [ROBLOX_CHARACTER_ARCHITECTURE_RU.md](ROBLOX_CHARACTER_ARCHITECTURE_RU.md). Официальные измерения отделены от реализации Bobux и от функциональных PASS.

## Сохранённая исходная база

До новых изменений сохранены 46 исходников, Git status/index и исходные hashes в `.codex-tmp/character_parity/baseline_2026-10-14/`. Проверка `python tools/character_parity/verify_baseline.py .codex-tmp/character_parity/baseline_2026-10-14`, повторённая при этом независимом review, дала **PASS**: все 46 файлов совпадали со снимком, три защищённых файла не изменены, нового `map_format.gd` в проверяемых каталогах нет. Это результат до следующего production slice; после него проверка требует точного списка разрешённых изменений.

Защищённые пути: `scripts/place_editor/studio.gd`, `scripts/main/main.gd`, `addons/rbxl_importer/rbxl_runtime_importer.gd`; любой файл с именем `map_format.gd` также защищён. Модель Bobux, голова, аксессуары, исходники карт и importer V2 не заменяются в рамках подготовки.

Историческое измерение `tests/roblox_humanoid/2026-10-13.empirical.json` осталось неизменным: SHA-256 `68bda7a419a92db53831b06ea739714cf8f617d9dd3cb2991429cd5e7931d5f4`. Историческая калибровка — **48 PASS / 5 FAIL / 18 SKIP / 0 BLOCKED**. Пять FAIL относятся к длительности Landed; 18 SKIP не дают доказательства начального импульса. Эти результаты, допуски и данные не переписываются. Сохранённая копия калибровки: `.codex-tmp/character_parity/baseline_2026-10-14/calibration-baseline.json`; разбор: [ROBLOX_HUMANOID_EMPIRICAL_RU.md](ROBLOX_HUMANOID_EMPIRICAL_RU.md).

Базовые локальные player/NPC контракты ранее в этой фазе запущены с результатом 40 PASS и 16 PASS; логи находятся в указанном baseline-каталоге. Это ограниченные контракты, а не полное соответствие Roblox.

## Фаза A

| Подзадача | Текущий статус | Доказательство и оставшиеся условия |
|---|---|---|
| A1 — исходная API/corpus-инвентаризация | DONE для исходного аудита | [Матрица](ROBLOX_CHARACTER_API_MATRIX_RU.md), `tests/roblox_humanoid/phase_a/api_matrix.json`: 69 классов в schema, 1045 собственных публичных членов; 188 частично, 857 нет, 0 полностью. Это оценки реальных маршрутов исходной базы, не результат новых runtime assertions. Typed usage всех карт ещё не доказан |
| A2 — native defaults R6/R15/StarterPlayer | PARTIAL | Новый ordinary-spawn v2, Studio `0.743.0.7431133`: пять независимых R15/default и пять R15/altered joins, 100 генераций и 1000 обязательных снимков client/server; обе группы OBSERVED, без fit/Bobux parity claim. [Наблюдения и consumer gaps](ROBLOX_ORDINARY_SPAWN_RU.md). Ordinary R6 и новый description-load путь NOT_RUN. Исторический run02 `56d7b7d5-beac-4f26-ba3e-d771a14ece51` / Studio `0.742.0.7421053` с fresh Humanoid, description-created rigs и custom StarterCharacter сохраняется отдельно; его повторные чтения не подменяют независимые ordinary joins |
| A3 — EnumItem | PARTIAL, opt-in VM slice проверен отдельно | Последнее ядро: 69 PASS / 0 FAIL, 10 domains / 99 items. Настоящий Humanoid/shared wrapper/event/Camera fixture: 43 PASS / 0 FAIL в каждом порядке двух VM, включая 94 cyclic safety assertions, 95 method-edge assertions и 594 CameraType assertions. Player 40 PASS и NPC 16 PASS. Полная A3, остальные typed свойства и wire compatibility остаются открыты |
| A4 — стандартные скрипты | PARTIAL | Есть inventory, dependency/API identifiers и ограниченные literal constants. Строгий extractor schema 2 применён к R6; строгого повторения R15 в этом наборе нет. Поведение скрипта не выводится из его констант |
| A5 — provenance/конфигурация | PARTIAL | Категории и правила определены в архитектуре; полный количественный аудит параметров фаз B–J и замена TODO_MEASURE не выполнены |

Corpus-аудит подтвердил SHA всех 21 оригинальных файлов, 20 уникальных содержимых. Доступны 14203 Source-поля, 14145 непустых. В сохранённом JSON карты №18 двенадцать script instances не имеют Source-поля: их usage **BLOCKED**. Regex-кандидаты не доказывают тип receiver или отсутствие динамических обращений. Числовые CameraType 4/5 в карте №17 требуют сохранения legacy-профиля. Подробности и ограничения находятся в A1-матрице.

Native A2/A3 данные: `tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.raw.log`, SHA-256 `36226a4f7dde505e224e5fbccefb26c8584ffd4ef752a02f9d5e9a771243237b`; разбор `2026-10-14-studio-run02.analysis.json`. Статус наблюдений **OBSERVED_NOT_PARITY_PASS**. Файл с суффиксом `-verified` представляет повторную проверку экспорта того же run, а не независимое повторение эксперимента.

## Точная область текущего Enum registry

Registry теперь реализует **10 enum domains / 99 canonical items**: HumanoidStateType 17, HumanoidRigType 2, CameraType 8, CameraMode 2, CoreGuiType 10, AnimationPriority 7, Material 45, SensorMode 4, SensorUpdateType 2, RaycastFilterType 2. RaycastFilterType.Blacklist/Whitelist — два alias к Exclude/Include; они не добавляют canonical items в GetEnumItems. Старый snapshot r03 содержал семь доменов / 85 items и остаётся историческим результатом.

Статическая проверка `tools/character_parity/review_enum_schema.py` сверяет эти пары с pinned creator-docs commit `031b2f91d3d47274c255f3ed5691c29f792c181d` и supplement того же commit. Последний результат — **10 STATIC_MATCH / 99 pairs**, без недостающих/лишних canonical пар или дубликатов в реализованных доменах. Снимок: `tests/roblox_humanoid/phase_a/enumitem_prototype_schema_review.json`. Новый native capture `664b4f14-6de7-42a1-95b3-2e80065d19ec` независимо сохраняет фактический порядок и identity всех 99 items, SHA-256 `9b3a8f4aabc02ad0fc2be5ddb040385d2bf03ec7c367a1897be67ea0ac1e0315`.

В Studio 0.742 `Enum:GetEnums()` вернул **648 типов**, их имена сохранены целиком; items записаны только для выбранных доменов. В Studio 0.743 новый probe вернул **651 тип**, сохранив count и полные items только десяти выбранных доменов. Текущее ядро покрывает **10 из 651**, остальные **641** не реализованы. Это счёт доменов, не процент функциональной совместимости. Локальный GetEnums возвращает покрытое подмножество, а не полный native namespace.

Измерения coercion: `2026-10-14-studio-enum-coercion-run01.raw.json`, 543 записи, run `c475020d-1687-4cb5-9b53-2ecbe4d5a2f7`, SHA-256 `bf6f00d2dd18a509353347852a76aec14ae5778e81e23eb2773923961e154e19`. Дополнительные шесть наблюдений: `2026-10-14-studio-enum-extra-run01.raw.json`, run `06e5b50d-dbad-4187-bf85-12d34a204bc8`, SHA-256 `bf0cfd177f200ded653b4423d5acdbd99e346aa24cd582599c9bc4f9c1f56306`.

Отчёт `tests/roblox_humanoid/phase_a/enumitem-prototype-native-r03.report.json` содержит **54 PASS / 0 FAIL**, Godot `4.7.stable.official.5b4e0cb0f`, Luau `0.719`, Windows. Независимая проверка подтвердила все пять записанных source hashes, три native reference hashes и runtime log SHA-256 `46a6df5cd013d667d6f7f285e3af419d9fabee016e740d18d2176a3991a7d2ed`; лог заканчивается `PASS=54 FAIL=0`. Сам Godot при review повторно не запускался. Native наблюдения получены в Studio с другим номером версии; это явно разные среды. Android этим validator не проверялся.

В историческом r03 54 — число aggregate checks, не число raw native rows: 20 checks помечены MEASURED, остальные 34 проверяют kernel/isolation/lifetime как ENGINE_APPROXIMATION. Они покрывают readonly/identity/lookup, измеренное подмножество enum semantics, две изолированные VM, настоящий GC и owner lease/teardown. Fixtures со словом `strict input policy` проверяют собственную политику kernel и **не являются** native class-specific coercion. Числовая внутренняя metadata и fixture store также не доказывают работу настоящего Humanoid.

План opt-in slice описан в [enum_vm_boundary_plan.md](enum_vm_boundary_plan.md), реализация и её ограничения — в [ENUM_VM_BOUNDARY_IMPLEMENTATION_RU.md](ENUM_VM_BOUNDARY_IMPLEMENTATION_RU.md). `ExistingNumericEnums` остаётся default. Fresh native Humanoid.GetState()=None — отдельный lifecycle/default gap, который нельзя скрыть одним typed return.

### Отдельный production VM slice

Последний набор — `tests/roblox_humanoid/phase_a/enum_vm_boundary_camera_20261015/manifest.json`: **43 PASS / 0 FAIL в каждом порядке VM**. CameraType проверяется на настоящей CurrentCamera и свежем Camera3D: 32 native input cases повторены по четырём entry paths; 594 assertions проверяют typed getter, scalar metadata, strict setter, отказ cyclic input без мутации и реальные SpringArm side effects Scriptable/Custom. Отдельный scheduled require/task fixture проверяет обычные authored assignments и явный `__bobux_set`; текущий rewriter не переписывает CameraType, этот маршрут не добавлялся ради теста. Native movement algorithms всех восьми типов и Changed ordering не измерены. Полный последовательный runner `20261015T210440Z-1d6efc` прошёл все 12 групп, включая player/NPC, Luau scheduler/callback guard/property cache и protected baseline. После уточнения report labels два VM повторены в `20261015T210707Z-61c88a`; production source не менялся.

Последний сохранённый набор перед CameraType slice — `tests/roblox_humanoid/phase_a/enum_vm_boundary_namespaces_20261015/manifest.json`: **38 PASS / 0 FAIL в каждом порядке VM**, включая **94 cyclic safety assertions** и **95 native method-edge assertions**. Registry в нём содержит 10 domains / 99 items. Извлечённые Humanoid методы используют настоящий переданный receiver; opaque enabled-state строки принимаются без изменений canonical flags и без событий. Числовой профиль и scalar backend сохраняются.

Отдельное ядро r04 имеет **69 PASS / 0 FAIL**: `tests/roblox_humanoid/phase_a/enumitem-prototype-native-r04.report.json` включает exact source/runtime/native/schema hashes и историю предыдущего 68 PASS / 1 FAIL. Этот FAIL был оставшимся ожиданием namespace count 7 после расширения до 10; он не был расхождением native item values/order. Сохранены также неудачные VM labels для mixed userdata/table comparisons: Luau отклоняет их до метаметода. Исправления ожиданий не меняли raw данных, физических допусков или реализации ради PASS.


Сохранённый набор `tests/roblox_humanoid/phase_a/enum_vm_boundary_20261015/manifest.json` фиксирует **34 PASS / 0 FAIL parity-first**, **34 PASS / 0 FAIL legacy-first**, **40 PASS player**, **16 PASS NPC** на Godot 4.7 / Luau 0.719. Независимый read-only review подтвердил hashes пяти sources, четырёх результатов, исходного dirty snapshot и всех перечисленных development failures. Эти данные относятся к engine SHA-256 `1c964d1b1335328c76fa6f344a8eeea5f44a33384bb0fd043fed230fe59095e0` и boundary SHA-256 `335482af71b15209fe2cfd94376cc4f4709824ce42aa3c67840f2508f2b7dcdc`. Изменения после этих hashes требуют новых результатов; старый manifest не переписывается.

В fixture используются настоящий `player.tscn`/Humanoid, общие cached BobuxInstance/BobuxEvent, отдельные реальные VM, module cache, task/coroutine/yield, canonical ChangeState/SetStateEnabled и zero returns, typed Connect/Once/Wait/extracted/lowercase wait, trailing nil, deferred profile, Stop/GC. Добавлены оба порядка создания VM, настоящий вложенный callback B→A→B и последующая эмиссия после Disconnect. Первая находка review — накопление strong connections — исправлена: owner хранит WeakRef с периодическим pruning; после 256 Once callbacks осталось 19 slots. Shared userdata подтверждён `rawequal`; generic BobuxEvent `==` остаётся отдельным OPEN дефектом native object equality.

Последующий review обнаружил дополнительные cyclic-table пути: operators/error formatting, Enum methods, missing-bool SetStateEnabled, enum keys/writes/calls и передача Enum/Enums namespace в RemoteEvent. Lua-side guards закрыты и проверены 94 assertions: циклические данные не передаются native conversion. Неподтверждённые операции Enum/Enums дают явный partial error; wire codec остаётся OPEN. Эти новые результаты отделены от старых 34 PASS source hashes.

## A4: два разных набора metadata

| Набор | Scope | Ограничение |
|---|---|---|
| `2026-10-14-studio-run02.metadata.json` | Schema 1, 62 OBSERVED rows; cache R6/R15 Animate и текущий R15 Animate. SHA-256 `1c3e72b390ef4a119614b2ff0d9a5609d5957cdf5b0b77504d63d39b81e82872` | Старый extractor; его literals не получают задним числом строгую гарантию schema 2 |
| `2026-10-14-studio-climb-run01-strict-a4.metadata.json` | Schema 2, extractor `standalone_single_line_literals_v2`, 61 OBSERVED rows, R6. SHA-256 `336e90888369b6cd53a87323b05e03dda0fbe6a7f8d86e96d578a63628300b14` | Только standalone local numeric/bool literal initializers; оба Animate rows относятся к R6 (cache и текущий character), по 13 literals. R15 строгим extractor ещё не подтверждён |

Количество rows включает дубли разных расположений; это не количество уникальных систем или независимых повторов. Данные являются Source-derived metadata из официальной Studio: Source, тела функций, исходные анимационные ключи и ассеты Roblox в Bobux не экспортированы. Статические identifier sets не доказывают runtime вызовы или значения выражений.

## Следующие ворота A3

Отдельно завершена native scalar матрица `Humanoid.RigType`: пять независимых Play Studio `0.743.0.7431133`, 720 cases, train 1–3 / holdout 4–5, VERIFIED transport и строгая проверка 144 cases каждого запуска. Измеренные setter/getter/event исходы совпали между пятью повторами. Реализация нового RigType consumer в Bobux этим не выполнена; физическая смена skeleton и живой Player не испытывались. [Наблюдения, архивы и ограничения](ROBLOX_RIG_TYPE_OBSERVED_RU.md).

Настоящий `LuaScriptEngine.start_script` fixture с Humanoid, Camera3D, общими cached wrappers/events и двумя VM имеет 43 PASS в обоих порядках. Полное пространство native input/bool casts/physical ChangeState остаётся вне этого результата. CameraType consumer закрыт только в указанной области; наличие enum namespace не доказывает работу Material, RigType или FloorMaterial consumers.

Профиль должен проверяться до очереди/выделения runtime ID и принадлежать VM, включая deferred start и retained state. Пустой/null/неизвестный профиль не превращается в numeric default. При общем wrapper он не может храниться в Node metadata или global current profile. Callback конвертируется ровно один раз; bool и trailing nil сохраняются; Once срабатывает один раз, Disconnect/Stop очищают реальные callables. Все эти assertions должны иметь явные PASS/FAIL, а не выводиться из формы кода.

Native coercion методов и setters различается. Нельзя обобщать strict kernel `int()` на number/string/EnumItem другого домена, NaN/Inf, fractions или Lua truthiness. Receiver/arity и три opaque enabled-state строки уже имеют отдельные raw наблюдения 0.743 и проверенную реализацию; остальные bool casts и noncanonical physical ChangeState остаются OPEN. RemoteEvent/RemoteFunction enum codec и version negotiation ещё открыты; opt-in slice не разрешает переключать опубликованный сервер на новый default.

После production slice нужны fresh player/NPC и существующие network/replication regressions. Перед rollout обязательны все заявленные старый/новый client/server combinations, либо явный отказ версии и согласованный порядок обновления. Localhost с одинаковыми исходниками не доказывает обратную совместимость.

## Фазы B–J

| Фаза | Статус текущей задачи | Незакрытые условия |
|---|---|---|
| B — R6 физика/состояния | NOT_COMPLETE | Полная пререгистрированная матрица, независимые повторы, отдельный holdout, силы/платформы и Landed FAIL. Исторические данные остаются отдельной калибровкой |
| C — ordinary Parts climbing | RESEARCH_IN_PROGRESS, NOT_COMPLETE | Предварительный native стенд и raw research не заменяют парное сравнение Bobux, ≥5 видео, player/NPC/network/respawn и непрерывный top exit. Ladder/ClassicLadder sensor не доказывает Humanoid Climbing |
| D — R15 | NOT_COMPLETE | Геометрия, масштабирование, общий мотор и собственный rig/анимации |
| E — Truss/water/seats/MoveTo | NOT_COMPLETE | Полная функциональная/сетевая матрица, Terrain Water и edge cases |
| F — здоровье/смерть/lifecycle/constraints | NOT_COMPLETE | Поколение жизни, cleanup ссылок/событий, реальные физические constraints; preexisting native userdata pointer-cache risk ещё не исследован lifecycle-тестом |
| G — Animator | NOT_COMPLETE | Реальный собственный joint playback, fade/blend/priorities/markers/loops, замена анимаций картой |
| H — камера/ввод/Android | NOT_COMPLETE | Измеренные camera/input контракты и проверки на физическом Android |
| I — внешний вид/UI/звук | NOT_COMPLETE | Собственные ассеты и количественные distance/visibility/sound правила |
| J — NPC/pathfinding | NOT_COMPLETE | Общие политики player/NPC, реальные маршруты/невозможные цели, измерение нагрузки |

Нет измерений, позволяющих обещать производительность 20 игроков / 100 NPC на всех устройствах. Новые phase gates закрываются только своим raw dataset, реализацией, validator и отчётом. Отсутствие наблюдения обозначается NOT_OBSERVABLE, отсутствие необходимого материала — BLOCKED; ни одно из них не заменяется вымышленным PASS.

Studio 0.743 native climbing run02 завершён отдельно: **45/45 валидных окон**, 53 278 записей / 75 283 757 байт, SHA-256 `2e52e496a1b363d5fcc7807452d3ac0cfbe9fb5947179d93654d7ef55126fafd`. Полная матрица и восемь source hashes совпали с preregistration; train/holdout не менялись, fit не выполнялся. Сохранены отдельное видео и пять native-only клипов. Данные не объединяются с run01 Studio 0.742: изменились версия и support baseplate. Детали и ограничения: [ROBLOX_NATIVE_PART_CLIMBING_RU.md](ROBLOX_NATIVE_PART_CLIMBING_RU.md).

Read-only аудит свойств выявил отдельные backend gaps: Material generic setter меняет metadata без renderer/physics update; FloorMaterial может содержать неканонический `Climbable` и не защищён как readonly. Их нельзя объявлять поддержанными из-за наличия Enum.Material. Узкий CameraType boundary проверен отдельно; алгоритмы камеры и Material backend этой правкой не подменяются.
