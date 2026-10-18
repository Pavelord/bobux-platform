# Нативное лазание по обычным Parts: предварительное исследование

Проверка Bobux от 18 октября 2026: действующий `ClimbSensor` по-прежнему отсекает обычный Part после raycast и принимает TrussPart; перенос распознавания геометрии обычных лестниц ещё не выполнен. Существующий Truss sensor validator прошёл проверки двух масштабов, перевёрнутого Truss и четырёх сторон. Устаревший `validate_player_climbing.gd` вызывал удалённый `_probe_climbable_surface` и зависал после script error. Он исправлен: использует текущий sensor и настоящий physics loop игрока через существующий trace-input seam, проверяет автоматический захват, подъём, состояние Climbing и отделение прыжком; добавлен watchdog. Локально все четыре функциональных условия дали true. Оба validator включены в CI. Это регрессия существующего Truss-контроллера, без нового ordinary-Part поведения или parity PASS; player/controller source не изменён.

Статус работы: **IN_PROGRESS**. Это наблюдения официального Roblox Studio, а не завершение фазы C и не подтверждение совместимости Bobux. Производственный мотор, карты и importer этими действиями не изменялись.

В испытанной конфигурации R6 классический Humanoid самостоятельно входил в `Climbing` на лестнице, собранной из обычных `Part`. У гладкого высокого блока, тонкого вертикального `Part` и одиночного уступа при том же движении вперёд этого не произошло. Поэтому нельзя реализовать совместимость ни правилом «обычные Parts никогда не поддерживают лазание», ни правилом «любая вертикальная поверхность является лестницей».

## Доказательства и воспроизводимость

### Завершённый повтор run02 — 15 октября

Studio `0.743.0.7431133`, run `2b50dc06-d10c-417f-b0aa-084a589ac02d`: **45/45 валидных окон**, без смерти/reset timeout. Сырые данные, сравнение с preregistration, таблицы и ограничения разобраны в отдельном разделе run02 ниже. Обе версии Studio сохраняются отдельными наборами; параметры Bobux не подбирались.

[Собственная запись run02](C:/robloxclone/.codex-tmp/character_parity/native/climb-run02-native.mp4): 368,33 s, 1280×672, около 29,73 fps; начало UTC `2026-10-15T10:58:21.6450298Z`, SHA-256 `e967158c22e425a095af7f4bac6a5c7f6f5b3669326151ff4c4303641b39a2a4`. [Пять клипов и manifest](C:/robloxclone/.codex-tmp/character_parity/native/climb-run02-evidence/manifest.json) используют приблизительный offset 23,3 s с неопределённостью минимум 1 s. Все пять still просмотрены: препятствия и персонаж видны. Парного Bobux-видео пока нет; это не пять сравнений со статусом PASS.

При открытии Studio сообщила об автоматической миграции Compatibility→Voxel Lighting. Замороженный входной файл сохранён как `CharacterClimb_run02.prerun.rbxlx`, SHA-256 `7ee9755e841f79c0c982d192f5b0b715bdc99ae2afb39ac6e36bf0bb99f7e426`; исходный generated fixture имеет тот же hash. После эксперимента локальная рабочая копия сохранена с миграцией, её SHA-256 `e8cc7de07d0cfa446f16f931662abf6c3268e703e1a2e4a5ccdb2294cb0b6300`. Она не подменяет входной fixture. Мотор Bobux не калибровался и фаза C остаётся IN_PROGRESS.

### Исторический run01 — 14 октября

- Официальный Studio: `0.742.0.7421053`, запуск `d21f12ca-b480-4585-b6b0-8f0ce98732a0`, UTC `2026-10-14T21:07:42Z`.
- Неизменяемые исходные наблюдения: [raw log](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.raw.log), **50 666 174 байта**, **36 674 записи**. SHA-256: `ec3c3102bf06d6e87cd52777412c4f0efbfd5d163be75f205ed55596ee29302a`.
- Первичный [observed report](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.observed.json) сохранён без исправления его исторических статусов.
- Отдельный [производный анализ](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.derived.json) содержит геометрию собственного стенда, вход, состояния, скорости и выходы диагностических сенсоров. Он не содержит скопированных поз/ключевых кадров анимаций.
- Инструмент: [analyze_native_climbing.py](C:/robloxclone/tools/character_parity/analyze_native_climbing.py). SHA/count сверяются с первичным observed report, последовательность `seq` проверяется. Проверка целостности: **PASS**.
- Семь проверок анализатора: **PASS**. Они защищают от принятия reset timeout за отрицательный результат лазания, смешивания reset-state events с измеряемым окном, двойного подсчёта Pre/Post callbacks и включения смерти в калибровку.

Повторный запуск анализа:

```powershell
python tools/character_parity/analyze_native_climbing.py tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.raw.log --observed tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.observed.json --output tests/roblox_humanoid/phase_c/2026-10-14-studio-climb-run01.derived.json
python -m unittest discover -s tools/character_parity -p test_analyze_native_climbing.py -v
```

Источником конфигурации run01 служит `matrix` внутри его raw manifest. Текущие файлы стенда уже могут относиться к run02. Хеш `measure.client.luau` именно run01: `ef8f238ffd0f4e336d95e004e216f34aca715e47e96761412781470d9eca4268`; значения следующего стенда нельзя подменять в этом отчёте.

## Run01: условия собственного эксперимента

R6 создан официальным API из пустого `HumanoidDescription`, выбран профиль `StarterPlayer.LuaCharacterController=Legacy`. `Gravity` — фактически `196.1999969482422 studs/s²`, `HipHeight=0`, `JumpPower=50`, `AutoRotate=true`, `MaxSlopeAngle=89`, `Climbing` разрешён. По пять повторов условия выполнялись с одним персонажем и reset между ними; это не пять независимых respawn.

Стандартный `Animate` оставлен включённым. Ввод заменён публичным `PlayerModule:GetControls():Disable()` и `Humanoid:Move(Vector3.new(0,0,-1), false)`. Камера `Scriptable` служит только наблюдению. В измеряемом окне `ChangeState(Climbing)` не вызывается, `Jump` не запрашивается. Унаследованный `AutoJumpEnabled` не изменялся; результаты не описывают все возможные виды ввода.

Одно окно длится около шести секунд simulation time. Сохранены PreSimulation, PostSimulation, события состояния, render callbacks и диагностические данные. Для итоговых подсчётов выбраны только PostSimulation; реальные solver substeps и скрытые контакты имеют статус **NOT_OBSERVABLE**. У валидных окон максимальный наблюдаемый callback `dt` равен 0,016667 или 0,020833 секунды, поэтому это не предположение о постоянных внутренних 60 Hz.

Геометрия создана нами, без скриптов внутри объектов. Все перечисленные части anchored, `CanCollide/CanQuery/CanTouch=true`, материал Plastic, пользовательские PhysicalProperties отсутствуют.

| Условие | Собственная геометрия, studs |
|---|---|
| `smooth_tall_block` | Part 12×32×8, центр (-60,16,0) |
| `thin_part` | Part 10×32×0,4, центр (-30,16,0) |
| `regular_parts_ladder` | 22 обычных Part 8×0,5×1, центры (0, 0,5+1,5i, 0), i=0…21 |
| `single_ledge` | Part 12×4×8, центр (30,2,0) |
| `truss` | Только положительный контроль: TrussPart 2×32×2, центр (60,16,0) |

Разбиение задано до наблюдений: r1–r3 — train, r4–r5 — holdout. Ни train, ни holdout этого анализа не использовались для подбора параметров Bobux. Ниже сравниваются распределения фактов, а не заранее навязанный ожидаемый результат.

## Run01: результаты с отделением повреждённого окна

Запланировано 45 условий-повторов. Началось 31 измеряемое окно, **30 валидны**, одно содержит смерть персонажа, ещё 14 не начались из-за reset timeout. Для анализа это **30 OBSERVED / 15 BLOCKED**. Это не 30 проверок Bobux со статусом PASS.

| Геометрия | WalkSpeed | Валидны / план | Climbing: train | Climbing: holdout | Медиана Vy по trial, studs/s | Максимальный подъём root по trial, min…max, studs |
|---|---:|---:|---:|---:|---:|---:|
| Гладкий блок | 16 | 5/5 | 0/3 | 0/2 | — | 0,000083…0,000134 |
| Тонкий Part | 16 | 5/5 | 0/3 | 0/2 | — | 0,000117…0,000192 |
| Лестница из Parts | 16 | 5/5 | 3/3 | 2/2 | 11,1999998 | 32,234704…32,235152 |
| Одиночный уступ | 16 | 5/5 | 0/3 | 0/2 | — | 0,000117…0,000138 |
| Truss-контроль | 16 | 5/5 | 3/3 | 2/2 | 11,1999998 | 31,999964…32,040710 |
| Лестница из Parts | 8 | 5/5 | 3/3 | 2/2 | 5,5999999 | 30,845308…30,938652 |
| Лестница из Parts | 32 | 0/5 | BLOCKED | BLOCKED | — | — |
| Truss-контроль | 8 | 0/5 | BLOCKED | BLOCKED | — | — |
| Truss-контроль | 32 | 0/5 | BLOCKED | BLOCKED | — | — |

Медиана вычислена сначала внутри trial по PostSimulation samples, затем между trials. Строка с пятью повторениями не становится статистически независимой от количества её callbacks. Начальные переходные скорости сохраняются; отдельное «устойчивое» окно задним числом не подбиралось.

У лестницы из Parts при WalkSpeed 16 первое наблюдаемое `Climbing` появилось через 0,300000…0,316667 simulation seconds от начала окна; суммарные `dt` callbacks с этим состоянием — 2,783333…2,787500 s. При WalkSpeed 8: задержка 0,512500…0,516667 s, сумма 5,500000…5,516667 s. После верхнего выхода состояния менялись естественно. Максимальный подъём root включает весь trial, а не только Climbing; это не высота тела и не скрытый порог выхода.

В повреждённом `r6_regular_parts_ladder_ws32_r1` первичный fixture записал `OBSERVED`, хотя внутри окна зарегистрированы `Freefall→Dead`, **22 PostSimulation samples в Dead**, последняя позиция root `(0,133546, -509,389771, -123,678169)`. Это явный дефект проверки жизненного цикла стенда. В производном файле `raw_result_status=OBSERVED` сохранён, отдельно выставлен `analysis_status=BLOCKED`; окно исключено из всех валидных распределений. Из него нельзя принять 22,4 studs/s как подтверждённую калибровку WalkSpeed 32.

Следующие 14 случаев содержат `timeout 6s: quiet standing after reset`, не имеют `case_begin`/`case_result` измеряемого окна и не являются свидетельством отсутствия Climbing. Причина падения согласуется с ограниченной площадкой run01 и продолжающимся движением после выхода наверх; доказаны смерть и уход за край в raw, а скрытая внутренняя причина моторного решения не наблюдаема. Исправленный стенд run02 с большей площадкой и проверкой жизни имеет отдельный preregistered manifest; его результаты должны быть отдельным набором, а не заменой run01.

## Run01: Ladder/ClassicLadder и фактический Humanoid

Официальная документация различает современный `SensorMode.Ladder` и legacy `ClassicLadder`. Это алгоритмы поиска геометрии сенсором, а не сами состояния Humanoid. [Roblox creator-docs, SensorMode, закреплённый commit](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/SensorMode.yaml).

`ControllerPartSensor` отдаёт `SensedPart`, `HitFrame`, `HitNormal` и материал. Параметры области поиска влияют на его запрос; их нельзя автоматически считать скрытыми параметрами Humanoid. [Roblox creator-docs, ControllerPartSensor](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/classes/ControllerPartSensor.yaml).

В стенде оба сенсора прикреплены к root, `UpdateType=OnRead`, `SearchDistance=3`, `LadderSearchHeight=6`, **LadderSearchOffset=0**. Последний параметр отличается от наблюдаемого исходного 5; вся заданная конфигурация явно помечена `ENGINE_APPROXIMATION fixture settings`. `ControllerManager` и потребитель сил не создаются. Сенсоры только читаются и не заставляют Humanoid лезть.

У всех **10 806 валидных PostSimulation observations** четыре публичных поля (`SensedPart`, `SensedMaterial`, `HitNormal`, `HitFrame`) совпали между Ladder и ClassicLadder. Это ограниченное наблюдение на данных геометриях/настройках. Оно не доказывает идентичность алгоритмов при других расстояниях, углах, интервалах между перекладинами или форме персонажа.

Для каждого из двух режимов сенсора получилось:

| Публичный SensedPart | Реальное состояние Humanoid | Валидных PostSimulation observations |
|---|---|---:|
| Есть | Climbing | 3 232 |
| Есть | Другое | 216 |
| nil | Climbing | 105 |
| nil | Другое | 7 253 |

Один read сенсора и состояние в том же callback не эквивалентны: есть как находки без Climbing, так и Climbing с nil. В первой лестничной попытке при WalkSpeed 16 сенсор обнаружил часть через 0,133333 s, фактический Climbing наблюдался через 0,300000 s. У Truss-контроля — 0,016667 и 0,266667 s. Это порядок наблюдений, а не измеренная причинная задержка внутреннего сенсора Humanoid.

## Run01: что пока нельзя объявить реализованным

**BLOCKED**: скорость 32 и Truss 8/32 до нового прогона. **SKIP**: сравнение с Bobux, NPC, R15, сетевой владелец/late join/respawn, отключённое состояние, движение вбок/назад, запрос прыжка, варианты угла и интервала перекладин — в run01 не испытаны. Скрытые пороги, solver contacts и механизм «руки за уступ» — **NOT_OBSERVABLE**. Отсутствие Climbing у одного уступа при прямом подходе не доказывает отсутствия любого нативного перехода на уступ при ином размере, угле или вводе.

Нативное видео относится к собственному окну Studio. Пока нет сопоставленного Bobux-видео, оно не закрывает требование пяти видеосравнений. Root/CFrame и pose traces не используются для копирования стандартных анимаций: движения Bobux должны создаваться самостоятельно, а траектории сравниваться валидатором.

## Run01: пять фрагментов нативного наблюдения

Исходная запись: [climb-run01-native.mp4](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-native.mp4), 379,73 s, 1280×672, 30 fps; начало UTC `2026-10-14T21:07:30.6146127Z`. SHA-256: `86bc8a89b228827d7533cbdcb2d70a953fa3b52e5b639a849a1f8b22fe62e550`.

Созданы пять клипов по 8 s и пять still. Все still просмотрены: видна соответствующая геометрия и персонаж; для лестницы и Truss взят ранний момент подъёма, поскольку выше неподвижная камера обрезает персонажа краем viewport. Длинная исходная запись сохраняет полный наблюдаемый ход попытки, включая поздний выход из кадра.

| Геометрия / WS16 r1 | Native-only clip | Still | Начало clip в записи, s |
|---|---|---|---:|
| Гладкий блок | [Видео](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/smooth_tall_block.mp4) | [Кадр](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/smooth_tall_block.png) | 12,832 |
| Тонкий Part | [Видео](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/thin_part.mp4) | [Кадр](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/thin_part.png) | 44,465 |
| Лестница из Parts | [Видео](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/regular_parts_ladder.mp4) | [Кадр](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/regular_parts_ladder.png) | 76,146 |
| Одиночный уступ | [Видео](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/single_ledge.mp4) | [Кадр](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/single_ledge.png) | 107,812 |
| Truss-контроль | [Видео](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/truss.mp4) | [Кадр](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/truss.png) | 139,494 |

[Manifest клипов](C:/robloxclone/.codex-tmp/character_parity/native/climb-run01-evidence/manifest.json) сохраняет SHA исходного видео, raw данных и каждого результата. [Инструмент извлечения](C:/robloxclone/tools/character_parity/extract_native_climb_evidence.py) использует только эту собственную запись, без графического управления приложениями.

Привязка видео к `wall_s` **приблизительная**: использован offset 11,8 s, native `ToIsoDate` имеет точность одной секунды, общего кадросинхронного маркера нет. Неопределённость составляет минимум одну секунду. По этим клипам нельзя измерять frame-perfect задержку, анимационную фазу или ставить PASS сравнению Bobux. Метки: `NATIVE_ONLY_APPROXIMATE_ALIGNMENT`, Bobux video comparison **SKIP**.

Безопасный run02 завершён и разобран отдельно ниже. Для следующей части фазы C требуется зарегистрировать отдельную матрицу углов, толщины и шага перекладин, верхнего выхода и отключённого Climbing. При неоднозначных результатах нужен заранее зарегистрированный набор ≥10 повторов. Только после этого можно выводить обоснованные границы применения общего character motor и проверять их на holdout. В этом отчёте ни одного физического параметра Bobux не подбирали.

## Run02: отдельный безопасный повтор на Studio 0.743

Запуск `2b50dc06-d10c-417f-b0aa-084a589ac02d`, UTC **2026-10-15T10:58:44Z**, выполнен уже на официальной Studio **0.743.0.7431133**. Исходный [raw log](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-15-studio-climb-run02.raw.log) содержит **53 278 записей / 75 283 757 байт**, SHA-256 `2e52e496a1b363d5fcc7807452d3ac0cfbe9fb5947179d93654d7ef55126fafd`. [Первичный observed report](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-15-studio-climb-run02.observed.json) подтверждает byte-exact compressed transport; [отдельный derived analysis](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-15-studio-climb-run02.derived.json) получен тем же анализатором, без подбора параметров Bobux. SHA, число записей, один run ID, непрерывная seq и completion проверены: **integrity PASS**.

Матрица внутри raw **полностью равна** preregistered `tests/roblox_humanoid/phase_a/climb_run02.splits.json`, включая cases, geometry, reset policy, settings и восемь source hashes. SHA prereg-файла `a1b02b4b1053613e0a001fb377af6c39a4ca938af7a25921764c3fa786762763`. Все восемь текущих собственных source-файлов также совпали с embedded hashes; `measure.client.luau` — `144dbb0c2d47c1de4cf5ffad3e89022a9effa10e318d946c21f6b8eb850b39d1`, `setup.server.luau` — `23107af006cebc7065e8e68e9c14182e36560d867b010d3a63395a90c743a405`. [Независимый prereg/geometry review](C:/robloxclone/tests/roblox_humanoid/phase_c/2026-10-15-studio-climb-run02.prereg_review.json) проверяет все 45 case_begin: геометрия и обязательные свойства соответствуют плану; максимальное отклонение размера/позиции от decimal plan — `5,96×10⁻⁹ studs` при review tolerance `10⁻⁶`.

Run02 увеличил **только support baseplate**: с `220×1×100` до `512×1×512`, центр `(0,-0,5,0)`. Пять obstacle geometries сохранены. Reset останавливает Move, обнуляет линейную/угловую скорости и допускает до двух native reload при испорченной жизни только до измеряемого окна; measured case не повторяется ради получения нужного результата. Freefall может принудительно задаваться при preprocessing, Climbing не задаётся. Все 45 окон фактически прошли с **одним Character generation=1**, без reload или смерти. Это повторные trials одного персонажа, а не независимые respawn.

Классический R6/Legacy профиль, scripted world-space Move вперёд, не запрошенный Jump, сохранённый stock Animate и диагностические OnRead sensors остаются условиями опыта. Gravity фактически `196,1999969482422 studs/s²`. Длительность окна — около шести simulation seconds. Записаны 32 418 Pre/Post callbacks; в результатах использованы только **16 209 PostSimulation callbacks**. Максимальный наблюдаемый `dt_sim` — `0,020833333954 s`; это не измерение внутренних solver substeps.

**45 окон начались и завершились; 45 OBSERVED / 0 BLOCKED, 0 lifecycle-contaminated, 0 не начавшихся.** Train r1–r3 — 27 trials, holdout r4–r5 — 18 trials. Никакого tuning по train или holdout не выполнялось. OBSERVED здесь означает валидное native наблюдение, а не PASS Bobux.

| Геометрия | WalkSpeed | Валидны / план | Climbing train | Climbing holdout | Медиана trial Vy, studs/s | Медиана максимального подъёма root, studs | Подъём root min…max, studs |
|---|---:|---:|---:|---:|---:|---:|---:|
| Гладкий блок | 16 | 5/5 | 0/3 | 0/2 | — | 0,000117 | 0…0,000117 |
| Тонкий Part | 16 | 5/5 | 0/3 | 0/2 | — | 0,000200 | 0,000117…0,000201 |
| Лестница из Parts | 16 | 5/5 | 3/3 | 2/2 | 11,1999998 | 32,228442 | 32,226118…32,234950 |
| Одиночный уступ | 16 | 5/5 | 0/3 | 0/2 | — | 0,000769 | 0,000035…0,002342 |
| Truss-контроль | 16 | 5/5 | 3/3 | 2/2 | 11,1999998 | 31,999986 | 31,999978…32,046512 |
| Лестница из Parts | 8 | 5/5 | 3/3 | 2/2 | 5,5999999 | 30,845308 | 30,799750…30,855727 |
| Лестница из Parts | 32 | 5/5 | 3/3 | 2/2 | 22,3999996 | 32,334498 | 32,333804…32,564925 |
| Truss-контроль | 8 | 5/5 | 3/3 | 2/2 | 5,5999999 | 31,345769 | 31,252475…31,439090 |
| Truss-контроль | 32 | 5/5 | 3/3 | 2/2 | 22,3999996 | 32,882577 | 31,996614…33,146550 |

Как и в run01, сначала берётся медиана Vy среди Climbing PostSimulation samples внутри каждого trial, затем медиана пяти trials. Измеренное отношение этой медианы к WalkSpeed равно примерно `0,7` при трёх испытанных скоростях на двух положительных geometries. Это ограниченный факт этих условий; скрытый коэффициент движка, переходные кадры и все виды лазания этим не доказаны.

| Геометрия | WalkSpeed | Медиана задержки первого Climbing, s | Задержка min…max, s | Медиана суммы callback dt в Climbing, s |
|---|---:|---:|---:|---:|
| Лестница из Parts | 8 | 0,520833 | 0,516667…0,554167 | 5,500000 |
| Лестница из Parts | 16 | 0,316667 | 0,312500…0,316667 | 2,783333 |
| Лестница из Parts | 32 | 0,216667 | 0,195833…0,216667 | 1,383333 |
| Truss-контроль | 8 | 0,416667 | 0,412500…0,445833 | 5,600000 |
| Truss-контроль | 16 | 0,262500 | 0,233333…0,266667 | 2,833333 |
| Truss-контроль | 32 | 0,166667 | 0,150000…0,166667 | 1,416667 |

Ladder и ClassicLadder дали одинаковые публичные query values во всех 16 209 сопоставимых Post callbacks при SearchDistance=3, LadderSearchHeight=6, LadderSearchOffset=0. Всего для каждого mode: 5680 sensor-hit samples с Climbing, **174 sensor-nil samples с Climbing**, **425 sensor-hit samples без Climbing**, 9930 nil без Climbing. Значит, совпадение двух диагностических sensors не означает, что их SensedPart непосредственно равен скрытому критерию состояния Humanoid. ControllerManager/force consumer отсутствуют; sensor settings остаются ENGINE_APPROXIMATION собственного стенда.

Новый запуск устранил прежнюю смерть/reset timeout и дополнил недоступные в run01 скоростные условия. Он **не доказывает причину различий версий**: одновременно изменились Studio 0.742→0.743 и support geometry. Данные run01/run02 не объединяются в десять якобы одинаковых повторов. Вариативность подъёма после верхнего выхода остаётся существенной: размах Truss/WS32 около **1,15 studs**, Parts/WS32 около **0,231 studs**. По preregistered noise policy для калибровки неоднозначной траектории/выхода требуется отдельно зарегистрированное расширение ≥10 повторов; одинаковая медиана скорости и пять валидных окон эту оговорку не закрывают.

Фаза C остаётся **IN_PROGRESS / NOT_IMPLEMENTED_NOT_CALIBRATED**. Root сохранил отдельную запись run02 и пять native-only клипов, перечисленные выше; все пять still просмотрены. Парное видео Bobux/native comparison всё ещё SKIP. Новая геометрическая матрица, R15, NPC, network/respawn, непрерывный top exit и функциональная регрессия Bobux остаются отдельными воротами. Никаких физических параметров Bobux по run02 не подбирали.
