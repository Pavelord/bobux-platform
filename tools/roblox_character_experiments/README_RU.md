# Независимые Character-эксперименты Roblox Studio

Создано 14 октября 2026. Это измерительные стенды, не реализация и не калибровка Bobux.
Старые доказательства от 13 октября не изменяются. В репозиторий записаны только наши
скрипты и геометрия; исходники/ключевые кадры/модели/звуки Roblox не экспортируются.

`python tools/roblox_character_experiments/build_place.py` создаёт две отдельные сцены.
Если доступен локальный официальный Luau CLI `.compiler/luau-compile.exe`, builder
сначала компилирует все наши probes. Проверено CLI0.742 из официального
[luau-lang/luau release](https://github.com/luau-lang/luau/releases/tag/0.742).
Игнорируемая `.compiler` содержит только инструмент проверки и не является
частью Bobux runtime. Матрица содержит SHA-256 каждого нашего `.luau` fixture.

- `CharacterPhaseA.rbxlx`: A2 — 5 свежих Humanoid, 5 R6 и 5 R15 через официальный
  `Players:CreateHumanoidModelFromDescriptionAsync` с пустым HumanoidDescription;
  затем четыре штатных `LoadCharacterAsync` со StarterCharacter, созданным этим API:
  R6/R15, default/modified StarterPlayer. В каждом штатном спавне записаны пять
  повторных getter observations. Это не пять независимых спавнов — тип повторения
  явно указан в данных. Изменение StarterPlayer после входа игрока может отличаться
  от применения к новому Player: фиксируются одновременно значения StarterPlayer,
  Player и Humanoid, ничего вручную не переносится в Humanoid.
- `CharacterClimbBaseline.rbxlx`: только классический R6 Humanoid, 45 заранее
  записанных сценариев. Пять геометрий по 5 повторов при WS16, regular-Parts ladder
  и Truss дополнительно по 5 при WS8 и WS32. Gravity196.2. Это предварительный
  минимум Phase C, не полный поиск порогов, R15/CCL/FPS/нагрузки ещё не проверяются.

`tests/roblox_humanoid/phase_a/splits.json` фиксирует точную геометрию, сценарии,
train r1–r3 и holdout r4–r5, допуски и политику шумных событий до просмотра данных.
Геометрия лестницы — обычные гладкие Parts размером `(8,.5,1)` с шагом1.5stud;
скриптов/Truss внутри неё нет. Остальные контроли: высокий гладкий блок,
тонкий Part, одиночный выступ и настоящий TrussPart.

## Запуск

Открыть соответствующий `.rbxlx` в официальной Studio и нажать Play. Сценарий
проходит сам; мышь/WASD не нужны. Phase A обычно 1–2мин с учётом загрузки ресурсов,
Climb baseline около 5–7мин. Жёсткий общий предел540wall-seconds сохраняет частичные
данные и выдаёт BLOCKED. Каждый reset имеет6s предел; отсутствие стандартного
Animate/PlayerModule или Truss positive control также BLOCKED.

Профиль явно `StarterPlayer.LuaCharacterController=Legacy`; ControllerManager
не создаётся, CCL в результаты не смешивается. Штатные Animate и звуки остаются
установленными, их фактический inventory записывается. Ввод отключается только
публичным `PlayerModule:GetControls():Disable()`, затем используется `Humanoid:Move`
в world-space. Камера Scriptable используется для наблюдения и это вмешательство
явно записано. Принудительный Freefall происходит только до measured reset window;
Climbing никогда не задаётся вручную, Jump не запрашивается.

Два независимых ControllerPartSensor на HRP читаются с `UpdateType=OnRead`:
Ladder и ClassicLadder. Их исходные defaults записаны до конфигурирования.
SearchDistance3/LadderSearchHeight6/LadderSearchOffset0 — **fixture settings**,
не восстановленные внутренние пороги Humanoid. Выходы никак не управляют мотором.
Не создаётся ControllerManager, нет force consumers. Manual/Sense не используются.

Pre/Post записывают реальные dt, сумму PreSimulation dt, wall-clock, положение,
CFrame, линейную/угловую скорость, MoveDirection, state, FloorMaterial и outputs
датчиков. Motor6D C0/C1 записаны до каждого сценария; Transform, части и timing/
weight/priority AnimationTrack — каждый четвёртый callback (~15Hz при60fps).
Render dt и Camera3D CFrame записаны отдельно. Внутренние solver substeps и скрытые
Humanoid contacts помечены NOT_OBSERVABLE; их не выводят из предположений.

Для визуального доказательства дополнительно записать настоящее видео/кадры
окна Play внешним инструментом. Телеметрия pose/camera не заменяет видеозапись.

## Экспорт и проверка

Дождаться `CHARACTER_EXPERIMENT_DONE`. **Не нажимать Stop до экспорта.** В клиентской
Command Bar исполнить содержимое `export.commandbar.luau`; оно экспортирует только
нашу телеметрию кусками400символов, обходя ограничение native log на длину строки.

Обычный LocalScript не может читать Source. A4 autonomous inventory честно
помечает Source BLOCKED. Для разрешённого чтения публичных штатных скриптов из
официальной Studio выполнить в Command Bar:

```luau
require(game.ReplicatedStorage.StandardScriptMetadataProbe).capture()
```

Вывод — **только** идентификаторы зависимостей/API/событий, числовые/boolean
константы и длина Source. Никаких Source snippets, функции/текст оригинальных
скриптов не сохраняются. Animate R6/R15 клонируются только в оперативной памяти
этой временной Play-сессии, чтобы probe мог прочитать их после смены персонажа.

Важно: schema1 metadata run02 от14октября извлекала числовой **префикс** RHS,
поэтому сохранённые числа нельзя считать результатом выражения или применять
как настройки. Например `1/100` давало кандидат1. Этот raw не исправляется задним
числом. Schema2 `standalone_single_line_literals_v2` принимает только полный
single-line decimal/scientific/boolean RHS; comments и string contents исключены,
повторяющиеся local names помечены scope-ambiguous и не экспортируются как values.
Даже exact local initializer не доказывает runtime behavior или физический порог.
Зависимости/API/signal identifiers также остаются lexical inventory.

Наша отдельная CLI-проверка (все fixture strings написаны нами):

```powershell
tools/roblox_character_experiments/.compiler/luau.exe tools/roblox_character_experiments/test_metadata_literals.luau
python tools/character_parity/analyze_phase_a.py
python -m unittest discover -s tools/character_parity -p test_analyze_phase_a.py
```

Сохранить только строки наших export markers из native Studio log. Parser также
может принимать полный native log, но игнорирует всю постороннюю информацию:

```powershell
python tools/roblox_character_experiments/parse_output.py <log> --output tests/roblox_humanoid/phase_a/<date-runid>
python tools/roblox_character_experiments/parse_output.py <metadata-log> --metadata-only --output tests/roblox_humanoid/phase_a/<date-runid>
python -m unittest discover -s tools/roblox_character_experiments -p test_parse_output.py
```

Parser сохраняет `.raw.log`, `.frames.csv`, `.observed.json` с SHA-256 raw.
Отсутствующие segments, неверный byte count, mixed run IDs, seq gaps или отсутствие
финального marker приводят к BLOCKED, а не к PASS. Итоги real-world geometry
обозначаются OBSERVED: без Bobux comparison никакого parity PASS не существует.
При смешанных дискретных outcomes по пяти повторам калибровка BLOCKED до отдельного
пререгистрированного продолжения минимум10повторов. Holdout не используется для
подбора параметров. Допуски для short states сравниваются как шаги/распределения,
не универсальным процентом.

## Первичные источники

- [ControllerPartSensor](https://create.roblox.com/docs/reference/engine/classes/ControllerPartSensor): public sensed part/hit outputs, ladder modes.
- [SensorMode](https://create.roblox.com/docs/reference/engine/enums/SensorMode): Ladder modern piercing, ClassicLadder legacy detection.
- [SensorBase YAML Roblox/creator-docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/SensorBase.yaml): OnRead re-evaluates stale outputs on read; Manual does not recompute; Sense deprecated.
- [StarterPlayer](https://create.roblox.com/docs/reference/engine/classes/StarterPlayer): custom StarterCharacter and per-character settings.
- [Player](https://create.roblox.com/docs/reference/engine/classes/Player): native LoadCharacterAsync lifecycle.
- [Players](https://create.roblox.com/docs/reference/engine/classes/Players): official blank-description R6/R15 model creation.
- [CharacterControlMode](https://create.roblox.com/docs/reference/engine/enums/CharacterControlMode): Legacy separate from LuaCharacterController.

Никакие исходники основной игры и карты этот стенд не изменяет. Все новые файлы
лежат только в `tools/roblox_character_experiments` и `tests/roblox_humanoid/phase_a`.
