# Humanoid: проверенный публичный контракт Roblox

Проверено 13 октября 2026 года. Это справочник API и аудит исходников Bobux; результаты отдельного запуска реальной Studio помечены явно. Числа, для которых нет источника или реального Output, не считаются эмпирикой. Использованы Creator Hub и опубликованный Roblox репозиторий документации; утёкший код и декомпиляция клиента не использовались.

## Свойства и документированные значения

| Параметр | Подтверждено | Источник |
| --- | --- | --- |
| Health | 100 при создании стандартного персонажа | [Официальный учебник Detect hits](https://create.roblox.com/docs/tutorials/curriculums/gameplay-scripting/detect-hits) |
| WalkSpeed | 16 stud/s | [StarterPlayer.CharacterWalkSpeed](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer#CharacterWalkSpeed) |
| JumpPower | 50, диапазон 0–1000 | [StarterPlayer.CharacterJumpPower](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer#CharacterJumpPower) |
| JumpHeight | 7.2 stud | [StarterPlayer.CharacterJumpHeight](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer#CharacterJumpHeight) |
| UseJumpPower | **true** | [StarterPlayer.CharacterUseJumpPower](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer#CharacterUseJumpPower) |
| MaxSlopeAngle | 89°, диапазон 0–89° | [StarterPlayer.CharacterMaxSlopeAngle](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer#CharacterMaxSlopeAngle) |
| BreakJointsOnDeath | true | [Humanoid](https://create.roblox.com/docs/reference/engine/classes/Humanoid#BreakJointsOnDeath) |
| RequiresNeck | true | [Humanoid](https://create.roblox.com/docs/reference/engine/classes/Humanoid#RequiresNeck) |
| Workspace.Gravity | 196.2 stud/s² | [Workspace](https://create.roblox.com/docs/reference/engine/classes/Workspace#Gravity) |
| Camera.FieldOfView | 70°, вертикальный; диапазон 1–120° | [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera#FieldOfView) |

Значения нового Player.Character могут переопределяться настройками StarterPlayer, StarterHumanoid и самого режима. JumpPower не объявлен Deprecated; утверждение «только устаревший способ» неверно. AutoJumpEnabled связан с Player/StarterPlayer и сенсорным вводом. Просмотренный текст API не даёт полной таблицы defaults.

Дополнительные defaults **измерены в установленной Studio 0.742.0.7421053**, отдельно от документации: MaxHealth=100, AutoRotate=true, AutoJumpEnabled=true, HipHeight=0, Sit=false, PlatformStand=false. Они совпали у `Instance.new('Humanoid')` до parenting и у R6 из пустого HumanoidDescription до изменений теста. Доказательство: [.codex-tmp/roblox_humanoid_experiments/studio_run_01.empirical.json](../.codex-tmp/roblox_humanoid_experiments/studio_run_01.empirical.json), секция humanoid_defaults; run_id `c65b0462-dc68-4cd6-97fb-e76bee2a2c17`. Это не универсальные defaults всех режимов и версий Studio.

## События: точные аргументы

| Событие | Аргументы |
| --- | --- |
| HealthChanged | health: number |
| Died | нет |
| StateChanged | old: HumanoidStateType, new: HumanoidStateType |
| StateEnabledChanged | state: HumanoidStateType, isEnabled: boolean |
| Jumping / FreeFalling / FallingDown / GettingUp | active: boolean |
| PlatformStanding / Ragdoll / Strafing | active: boolean |
| Running / Climbing / Swimming | speed: number |
| Seated | active: boolean, currentSeatPart: BasePart |
| MoveToFinished | reached: boolean |
| Touched | touchingPart: BasePart, humanoidPart: BasePart |

Контракт подтверждён [Humanoid API](https://create.roblox.com/docs/reference/engine/classes/Humanoid) и [его официальным YAML](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Humanoid.yaml). `HealthChanged(old, new)` и `GettingUp(speed)` из задания несовместимы. Boolean-события сообщают вход/выход; `Jumping(false)` не означает приземление. Скорости: Climbing = WalkSpeed × 0.7; Swimming = WalkSpeed × 0.875. При WalkSpeed=16 цели равны 11.2 и 14 stud/s; это документация, не замеры ускорения.

`StateEnabledChanged` срабатывает **при каждом SetStateEnabled**, включая повтор того же значения. Это подтверждено свежим Humanoid в реальной Studio 0.742.0.7421053: false,false,true,true → четыре callback, каждый с двумя аргументами EnumItem/boolean. Источник: [.codex-tmp/roblox_humanoid_experiments/studio_run_02.empirical.json](../.codex-tmp/roblox_humanoid_experiments/studio_run_02.empirical.json). В Bobux повторное значение не перезаписывает metadata, но публичное событие доставляется.

## HumanoidStateType

| Имя Roblox | Value |
| --- | ---: |
| FallingDown | 0 |
| Ragdoll | 1 |
| GettingUp | 2 |
| Jumping | 3 |
| Swimming | 4 |
| Freefall | 5 |
| Flying | 6 |
| Landed | 7 |
| Running | 8 |
| RunningNoPhysics | 10 |
| StrafingNoPhysics | 11 |
| Climbing | 12 |
| Seated | 13 |
| PlatformStanding | 14 |
| Dead | 15 |
| Physics | 16 |
| None | 18 |

Источник: [официальный enum](https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType), [YAML Roblox](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/HumanoidStateType.yaml). Пропуски 9 и 17 сохраняются. Ragdoll и RunningNoPhysics описаны как deprecated. Standing и LedgeGrab отсутствуют. StrafingNoPhysics — не обычное движение боком. Physics не создаёт собственные силы и автоматические переходы; None — служебная заглушка. Jumping и Landed короткие; численная длительность не указана. Freefall не задаёт знак вертикальной скорости.

## R6, голова и масштаб

[Character appearance](https://create.roblox.com/docs/characters/appearance) описывает структуру аватара, но не подтверждает таблицу размеров и offsets из вложения. R6 — шесть видимых частей и HumanoidRootPart; нельзя из этого выводить форму головы BoxMesh или CylinderMesh. Part.Size, физическая оболочка и геометрия SpecialMesh — разные данные. Для классической округлой головы Bobux сохраняем существующий mesh; SpecialMesh.Scale, MeshType и Motor6D.C0/C1 остаются отдельной геометрической проверкой.

В реальной Studio 0.742.0.7421053 у свежего `Players:CreateHumanoidModelFromDescriptionAsync(empty HumanoidDescription, R6)` измерены Head.Size=(2,1,1), HRP.Size=(2,2,1), Torso.Size=(2,2,1), руки и ноги=(1,2,1). До анимации offsets совпали с вложением: Head=(0,1.5,0), руки=(±1.5,0,0), ноги=(±0.5,-2,0). Head/Torso CanCollide=true, HRP/конечности=false. Источник: тот же studio_run_01.empirical.json, r6_parts с label `before harness mutations`. Head.Size=(1,1,1) исходного Bobux config не совпадал с этим **Part**, но исправление API Size не разрешает растянуть округлый визуальный mesh или аксессуары.

[Humanoid.EvaluateStateMachine](https://create.roblox.com/docs/reference/engine/classes/Humanoid#EvaluateStateMachine) описывает стандартные коллизии: включены у Torso и Head. Поэтому тезис «HumanoidRootPart обязательно имеет коллизию» не принимается. Реальную коллизию рига после spawn и после входа в Physics надо измерять отдельно.

[Roblox units](https://create.roblox.com/docs/physics/units) задаёт рекомендуемое физическое соответствие **1 stud = 0.28 м**. Внутренне Roblox не конвертирует studs в метры. Это не основание менять масштаб существующих карт Bobux: наш коэффициент Godot-units/stud остаётся коэффициентом импорта, а не заявлением о метрах. Позиции, скорости, гравитация и размеры должны проходить через один и тот же коэффициент.

## Камера и PlayerModule

[StarterPlayerScripts](https://create.roblox.com/docs/reference/engine/classes/StarterPlayerScripts) документирует замену default CameraScript/ControlScript. [StarterPlayer](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer) задаёт параметры Player.CameraMinZoomDistance/CameraMaxZoomDistance; в просмотренном тексте численные defaults не указаны. FOV=70 уже подтверждён отдельным Camera API, он не обязан быть константой PlayerModule.

Проверка живой пустой локальной сцены Studio 0.742.0.7421053 дала Player.CameraMinZoomDistance=0.5, CameraMaxZoomDistance=400, CameraMode=Classic, Camera.CameraType=Custom и FOV=70. Это снятые свойства конкретного места, а не прочитанные константы PlayerModule и не доказательство «max всегда400». Число128 и shoulder offset не используются как проверенные значения. Доказательство: studio_run_01.empirical.json и исходный studio_run_01.log.

[CameraType](https://create.roblox.com/docs/reference/engine/enums/CameraType) и CameraMode/DevComputerCameraMovementMode — разные enum. Classic/Follow/Orbital нельзя свести к единственному CameraType. Для Scriptable стандартный контроллер должен прекратить менять позу камеры; CameraSubject и Humanoid.CameraOffset сохраняют отдельный смысл. [Публичный Roblox/Core-Scripts](https://github.com/Roblox/Core-Scripts) — официальный исторический архив, закрытый для изменений в 2020 году; он не подтверждает нынешние численные defaults. Стороннее зеркало PlayerModule не использовалось как первичный источник и не копировалось в Bobux.

## Аудит исходников Bobux до исправлений этой задачи

Наблюдения ниже относятся к локальному коду до правок 13 октября, а не к внутреннему устройству Roblox.

| Место | Дефект или ограничение | Практическое следствие |
| --- | --- | --- |
| autoload/lua_script_engine.gd: enum table | Только 8 HumanoidStateType; RunningNoPhysics строка преобразуется в Running=8 | Скрипты не видят полный enum и отличающееся состояние 10 |
| LuaScriptEngine.notify_humanoid_state_changed | Только Jumping и FreeFalling | Не доставляет общие Boolean-переходы FallingDown/GettingUp/PlatformStanding/Ragdoll/Seated |
| BobuxInstance._get_impl | Move возвращается как событие даже у Humanoid; Swimming не включён в список событий | Humanoid:Move и подписка Swimming несовместимы |
| scripts/player/player.gd | request_humanoid_state обрабатывает только Jumping/Freefall; Freefall обрезает velocity.y | Режимы, включающие Physics/PlatformStanding/Dead, теряют управление состояниями |
| player swimming | Фиксированный Swimming.Speed=15 | Изменение WalkSpeed не меняет документированную скорость плавания |
| addons/roblox_runtime/roblox_humanoid_motor.gd | Отдельный NPC motor: gravity=98.1×scale, прыжок только JumpPower | Игрок и NPC расходятся; Workspace.Gravity/JumpHeight не действуют |
| NPC motor | Только StateChanged, без Landed и событий движения | Animate и ожидания событий могут зависнуть |
| humanoid_config.tres | R6 размеры помечены documented, а part_dump.csv отсутствует | Нельзя заявлять измеренное совпадение рига |

Уже корректны HealthChanged(health), дробное здоровье, базовые IDs и UseJumpPower=true. Не следует заменять их ошибочными вариантами из вложения. API-совместимость должна проверяться отдельно от похожести движения.

## Что пока неизвестно

В первом Studio run измерены Landed на десяти падениях с высот 5/10/20/40/80 stud: медиана около 33.33 ms симуляции, диапазон 29.17–45.83 ms. Это результаты только указанной версии и fixture, не константа всех Roblox Humanoid. Climbing при WalkSpeed16 дал 11.2 stud/s в трёх повторах. Измеренное плавание по поверхности Terrain Water дало примерно 12.919 stud/s (0.8074×WalkSpeed), поэтому документационную цель 0.875 и эту фактическую скорость нельзя выдавать за одно и то же. Все первые jump cases завершились timeout из-за методики запроса прыжка; их нельзя считать измерением отсутствия прыжков в Roblox. Исправленный прогон и окончательная калибровка описываются отдельно в ROBLOX_HUMANOID_EMPIRICAL_RU.md.

Повторный реальный studio_run_02 завершил все 35 сценариев, без failures и parser issues; первоначальные jump timeout не остаются ограничением этого повторного прогона. Численные результаты и сравнение Godot вынесены в отдельный эмпирический документ, чтобы не смешивать данные разных запусков и менять источник задним числом.

Не измерены этой проверкой: точные solver-пороги Jumping→Freefall, ускорение/торможение, climb detection, плавучесть, внутренний collision shape рига и touch auto-jump. Константа shoulder offset (1.75,0,0) позднее прочитана из публичного MouseLockController той же Studio-сессии; фактический переход камеры при включении Shift Lock отдельно не калибровался. `sqrt(2*g*h)` остаётся инженерной баллистической моделью Bobux, не подтверждённой точной формулой Roblox Humanoid.

Fall damage и ledge grab — расширения режима/движка, не члены публичного Humanoid API. Отсутствие API не доказывает все внутренние механики платформы, поэтому не приписываем Roblox undocumented поведение. Имеющиеся Bobux parkour-механики не должны включаться через выдуманные значения официального enum.

Правильный следующий шаг: чистый R6 в Studio, запись engine version/rig/settings, несколько повторов и timestamps на Heartbeat/PreSimulation, затем сравнение одинаковых сценариев Godot. Эксперимент из вложения, который ждёт 0.05 с и прыгает несколько раз без ожидания Landed, не измеряет начальную скорость: за это время уже действует гравитация, а очередной прыжок может начаться в воздухе.

## Реализовано и проверено в этой подзадаче

В autoload/lua_script_engine.gd добавлены полная таблица HumanoidStateType, [HumanoidRigType](https://create.roblox.com/docs/reference/engine/enums/HumanoidRigType) R6=0/R15=1, RootPart/MoveDirection и недостающие события. Boolean-переходы общие для игрока и NPC; аргументы Seated/HealthChanged/Died проверяются реальным Luau. Move различает мировую и камерную системы координат. MoveTo принимает Part и отслеживает исходную локальную точку при перемещении/повороте цели. GetState больше не подменяет RunningNoPhysics=10 значением8.

NPC motor теперь использует тот же state_machine.gd, живую Workspace.Gravity и существующий stud scale; поддерживает UseJumpPower/JumpHeight, Landed и Physics с сохранением горизонтального импульса. Отрицательный TakeDamage лечит; защита проверяет класс ForceField, включая переименованные объекты у HRP и предков, но исключает Workspace. Dead блокирует восстановление Health простым присваиванием. [Источник TakeDamage](https://create.roblox.com/docs/reference/engine/classes/Humanoid#TakeDamage).

Новая проверка tools/validate_humanoid_npc_contract.gd проходит 16 внешних проверок и вложенные Luau assert: IDs, enabled states, число/типы аргументов, вход/выход Seated, движение при разных yaw и наклоне камеры, вращающаяся цель MoveTo, отрицательный урон и ForceField, дробное и бесконечное здоровье, единственный Died, гравитация196.2→40, JumpHeight/JumpPower, растущий импульс в Freefall, шесть физических тиков Physics, фактический контакт пола Freefall→Landed→Running. Итоговый лог: .codex-tmp/humanoid-final-npc.log. Дополнительно прошли validate_halloween_character_contract, validate_lift_runtime_contract, validate_lua_gameplay_primitives и validate_lua_service_compatibility.

Пределы этой реализации: enum остаётся совместимым с текущим Bobux представлением числовых ID, а не полноценными Roblox EnumItem с Name/Value/EnumType. Наличие HumanoidRigType.R15 не означает реализованный R15 rig. NPC сохраняет прежнюю Godot capsule и визуальный скелет: manual Ragdoll/Flying/Swimming/Climbing публикуют состояния, но это не новые physical-bones, автоматическое плавание или climbing sensor NPC. Полная геометрия/анимация/плавучесть NPC требуют отдельной проверки. Не менялись main.gd, studio.gd, importer, map_format и карты; изменения Lua/API/сетевого моста проверены локально, на опубликованный сервер не выкладывались.
