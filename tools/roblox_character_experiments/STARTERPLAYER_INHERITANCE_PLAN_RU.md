# Дополнительный A2: штатное наследование StarterPlayer

Дата: 14 октября 2026. Статус **PLANNED, native measurements ещё не выполнены**.
Этот документ не меняет старые сцены, сырые данные или Bobux.

`CharacterPhaseA_run02` использовал свой `StarterCharacter`, созданный официальным
API. Его результат описывает именно этот путь. Отсутствие изменения свойств
Humanoid в этом опыте нельзя обобщать на обычное создание персонажа.

В следующем отдельном стенде нужны два независимых пути:

| Путь | Настройка до Play | Спавн | Назначение |
|---|---|---|---|
| NATIVE_DEFAULT | Нет StarterCharacter и StarterHumanoid; LoadCharacterAppearance=false | Player:LoadCharacterAsync() | Обычный спавн без внешней одежды/аксессуаров |
| NATIVE_DESCRIPTION | Та же настройка | Player:LoadCharacterWithHumanoidDescriptionAsync(пустой собственный HumanoidDescription) | Проверка пути явного описания без подмены Character |

В обоих путях запрещено присваивать `Player.Character`, клонировать заранее
созданный Model в StarterPlayer, менять `Humanoid.RigType` или переносить свойства
StarterPlayer в Humanoid вручную. Стандартные Animate, PlayerModule и звук
сохраняются. Собственная телеметрия не читает и не экспортирует их Source.

Контроллер задан публичным `StarterPlayer.LuaCharacterController=Legacy`.
Настройка рига R6/R15 задаётся через штатные настройки Avatar отдельного тестового
места **до запуска**; записывается доступное значение настройки и фактический
`Humanoid.RigType` на каждом спавне. Название файла `R6` не является доказательством.
Если локальная Studio не позволяет выбрать риг без публикации/доступа к настройкам
опыта, соответствующая комбинация остаётся **BLOCKED**, а не заменяется
StarterCharacter или NPC. Основной опубликованный опыт Bobux не перенастраивается.

Минимальная матрица: 2 рига × 2 пути × 2 профиля × 5 **независимых Play-сессий** =
40 initial-join cases. В каждой сессии дополнительно четыре независимых обычных
respawn того же пути дают 5 разных Character; это отдельная ось данных, не пять
повторных getter чтений одного Humanoid. Train: сессии 1–3, holdout: 4–5; JSON
матрица и SHA-256 probes фиксируются до первого запуска. Никакие пороги движения
по этим данным не калибруются.

Default-профиль сохраняется из свежего локального места. Modified-профиль задаётся
в файле места до Play, чтобы настройки существовали **до появления нового Player**:

| StarterPlayer | Значение fixture | Наблюдение |
|---|---:|---|
| CharacterWalkSpeed | 23 | Humanoid.WalkSpeed |
| CharacterJumpPower | 61 | Humanoid.JumpPower |
| CharacterJumpHeight | 9 | Humanoid.JumpHeight |
| CharacterUseJumpPower | false | Humanoid.UseJumpPower |
| CharacterMaxSlopeAngle | 37 | Humanoid.MaxSlopeAngle |
| AutoJumpEnabled | false | Player и Humanoid.AutoJumpEnabled |
| CameraMinZoomDistance | 2 | Player.CameraMinZoomDistance |
| CameraMaxZoomDistance | 60 | Player.CameraMaxZoomDistance |
| CharacterBreakJointsOnDeath | false | Humanoid.BreakJointsOnDeath, с отдельным указанием rollout ограничений |

Это значения измерительного стенда, не новые настройки Bobux.
`CharacterBreakJointsOnDeath` нельзя объявлять неверно наследованным без учёта
`AvatarJointUpgrade` и `ClassicDeath`: если rollout нельзя прочитать публично,
это **NOT_OBSERVABLE**, не предполагаемое включённое/выключенное состояние.

Для каждого initial join и respawn сохраняются:

- Studio version/date UTC/run ID/session ID/Character generation ID и SHA probes;
- фактическое отсутствие StarterCharacter/StarterHumanoid и состояние профиля;
- StarterPlayer, Player, Humanoid значения раздельно, сервер и клиент раздельно;
- очередность CharacterRemoving/CharacterAdded/CharacterAppearanceLoaded,
  момент появления Humanoid/HRP/Animator/Animate; отсутствие appearance event при
  выключенной загрузке фиксируется отдельно, не автоматически как ошибка;
- immediate, первый PostSimulation, +0.25s, +1s, +3s getter снимки каждого спавна;
- фактический RigType, имя/класс/количество частей и суставов без внешних asset IDs.

Проверка join-vs-respawn проводится отдельными A/B сессиями. После первых пяти
спавнов сервер меняет только StarterPlayer modified-настройки, не Player/Humanoid.
Сначала сохраняется старый живой Character, затем ещё пять штатных respawn.
Изменение этих настроек в уже запущенной сессии нельзя приравнивать к начальному
наследованию нового Player. Особенно это относится к camera и AutoJump настройкам.

Каждый async спавн имеет watchdog 20s, общий предел 300s/сессия. Timeout, неверный
фактический риг, custom-character contamination или отсутствующая телеметрия дают
BLOCKED и сохранение частичного результата. Снимки оставляются OBSERVED до
независимого сравнения с реализацией Bobux. Шумные lifecycle события требуют
отдельного продолжения минимум 10 сессий, зарегистрированного до повторного опыта.

Первичные источники, проверены 14 октября 2026:

- [StarterPlayer, pinned creator-docs](https://github.com/Roblox/creator-docs/blob/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/StarterPlayer.yaml): настройки Player при входе, свойства будущих Humanoid, StarterCharacter/StarterHumanoid и ограничения death rollout.
- [Player, официальный API](https://create.roblox.com/docs/reference/engine/classes/Player): публичные методы LoadCharacterAsync/LoadCharacterWithHumanoidDescriptionAsync и lifecycle сигналы.

