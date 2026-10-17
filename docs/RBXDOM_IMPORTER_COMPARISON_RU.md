# Сверка V2-импортёра с rbx-dom

## Зачем нужен второй парсер

Старая Studio-команда импорта остаётся основным путём. Новый парсер Bobux V2 запускается отдельно и пока нужен для контролируемых экспериментов. Для проверки формата добавлен независимый oracle на официальных crates `rojo-rbx/rbx-dom`: `rbx_binary 3.0.1`, `rbx_xml 3.0.0`, `rbx_dom_weak 4.2.0`.

Oracle сериализует дерево объектов и типизированные свойства в сжатый NDJSON. Python-сверка сопоставляет экземпляры по пути классов/имён в иерархии, разрешает ссылки до экземпляров и сравнивает значения после явно перечисленных преобразований. Если путь меняется из-за перестановки одинаковых дочерних объектов, сверка пробует уникальный непустой `UniqueId`. Это помогает отличать несовпадение порядка от потери экземпляров.

`rbx-dom` читает неизвестные XML-свойства через режим `ReadUnknown`. Формат `Tags` отдельно сравнивается как список строк; документация rbx-dom описывает NUL-разделённое бинарное представление и хранение через SharedString, а changelog `rbx_binary 3.0.0` отдельно отмечает чтение Tags из SharedString. [binary-strings.md](https://github.com/rojo-rbx/rbx-dom/blob/master/docs/binary-strings.md), [rbx_binary changelog](https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_binary/CHANGELOG.md)

## Что сравнение нормализует

- `UniqueId` и `HistoryId`: строковую hex-форму rbx-dom переводит в те же `random/epoch/index`, которые выдаёт Bobux.
- Ссылки: сопоставляет целевой экземпляр, а не внутренний номер referent. `Value` считается ссылкой только у `ObjectValue`, поэтому числовые `IntValue.Value` остаются числами.
- `BinaryString` и `SharedString`: сравниваются SHA-256 исходных декодированных байтов и их длина, включая крупные значения.
- `Tags`, `AttributesSerialize` и `MaterialColors`: теги и атрибуты декодируются, `MaterialColors` переводится в таблицу цветов, исходные бинарные данные остаются доступными как sidecar/непреобразованное свойство.
- Переносы имён из reflection database: например `Color3uint8`/`BrickColor` в `Color`, `TextureId` в `TextureContent`, `Part0Internal` в `Part0`, `CornerRadius` в четыре UDim-свойства, а также старые поля звука, огня и дыма.
- Актуальные V2-алиасы, подтверждённые на пользовательских картах: `Decal`/`Texture` content-поля, `ShirtGraphic.Graphic` в `TextureContent`, `ScreenGui.IgnoreGuiInset` в `ScreenInsets`. Старое поле остаётся рядом с новым. Явный `ScreenInsets` не перезаписывается; для старого bool используются enum ID `false → CoreUISafeInsets (2)` и `true → DeviceSafeInsets (1)`.
- Формы `CFrame`, `Rect`, `UDim`, `UDim2`, `Font`, `Content` и близких типов приводятся к общей структуре. Сравнение чисел допускает относительную и абсолютную погрешность `1e-6`.

Перенос свойств rbx-dom не всегда означает потерю у Bobux: старое имя может быть сохранено намеренно для совместимости. Такие поля остаются в категориях «только Bobux»/«только rbx-dom» либо учитываются отдельной нормализацией, вместо молчаливого удаления исходных значений.

Совпадение сериализованных значений подтверждает чтение и преобразование данных, но не их применение рендерером. V2 сохраняет `ScreenInsets` и актуальные content-поля в манифесте; текущая проверка не подтверждает, что GUI safe-area уже влияет на раскладку или что normal/metalness/roughness карты участвуют в PBR-материале. Эти свойства требуют отдельной runtime-проверки.

## Старые XML-файлы

Три вложенных XML-файла не принимались rbx-dom напрямую: два содержат старые `<External>referent</External>` записи внутри элементов, один содержит неэкранированный `&` в Lua source. Runner повторяет попытку на временной копии только для oracle: удаляет legacy `External` элементы и экранирует ampersand, который не начинает допустимую XML entity. Bobux по-прежнему разбирает исходный файл без этой правки. В отчёте для каждой карты указано, понадобилась ли такая подготовка и сколько элементов/символов было затронуто.

Это разделяет два вопроса: корректен ли Bobux на исходном пользовательском файле и можно ли получить независимое дерево сравнения, если XML устарел или формально некорректен.

## Запуск

Нужны Python и стабильный Rust/Cargo. На Windows Rust устанавливается через официальный rustup, который включает Cargo; например:

```powershell
winget install --id Rustlang.Rustup --exact
```

Если текущий терминал ещё не видит Cargo в `PATH`, runner использует `%USERPROFILE%\.cargo\bin\cargo.exe`. Сборка идёт с `--locked`.

Команда в PowerShell собирает pinned rbx-dom oracle и проходит манифест карт из Downloads:

```powershell
powershell -ExecutionPolicy Bypass -File tools/rbxl_compare/run_suite.ps1
```

Третий форматный проход использует pinned [rbx-native](https://github.com/chteau/rbx-native) и его `rbxdump --roundtrip`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/rbxl_compare/run_rbx_native_roundtrip.ps1
```

Runner отдельно сохраняет результат загрузки исходника, бинарного round-trip и XML round-trip. Если исходный legacy XML не читается, он повторяет попытку на временной нормализованной копии; исходная карта не меняется. `--roundtrip` проверяет парсер вместе с writer-ами rbx-native, но не сравнивает каждое значение с Bobux.

Параметры позволяют задать каталог карт и отчётов; `-ReuseOracle` повторно использует dump только когда SHA-256 исходника совпадает с прежним прогоном. Для точечного сравнения можно вызвать `run_suite.py` с `--only "имя файла.rbxl"`.

Список исходных файлов зафиксирован в `tools/rbxl_compare/attached_maps_2026-10-03.txt`. Успешное чтение обоими парсерами не означает, что скрипты карты уже работают: runtime-поведение, геометрический вид, кэш mesh-текстур и API-совместимость проверяются отдельно.

## Итоги прогона

Финальный прогон выполнен 3 октября 2026 г. по всем 21 файлам манифеста: 17 бинарных и 4 XML. Оба парсера успешно прочитали все исходники. Три старых XML-карты пришлось нормализовать только для rbx-dom: у двух Plane Wars удалено по 22 legacy `<External>` элемента, у 2011 Natural Disasters удалено 2 таких элемента и экранировано 3 неэкранированных `&`. Bobux разбирал оригинальные файлы; oracle получил временные копии.

Результат сверки:

- Все **529 154 из 529 154** экземпляров сопоставлены; ни одного лишнего/потерянного объекта и неоднозначного пути не осталось.
- Все **19 530 664 общих значения свойств совпали** после явных преобразований типов и имён; подтверждённых несовпадающих общих значений — **0**.
- Сравнено **502 257 значений свойства `Tags`**, расхождений — **0**. Счётчик включает пустые списки, если свойство присутствует хотя бы в одном представлении, поэтому это не число объектов с непустыми тегами.
- В V2 создано **57 375 совместимых alias-полей** с сохранением исходных имён: `Decal.Texture → TextureContent` (5 055), `Texture.Texture → TextureContent` (51 774), content-карты `Decal`/`Texture` (507), `ShirtGraphic.Graphic → TextureContent` (8), `ScreenGui.IgnoreGuiInset → ScreenInsets` (31). Эти числа показываются в `property_migrations` по каждой карте.
- Остались **14 611 значений свойств только в Bobux** и **2 380 только в rbx-dom**. Это не число потерянных объектов и не прямое доказательство порчи: сюда входят старые сериализованные имена/поля против мигрированных свойств reflection database и сериализованные значения по умолчанию. Частые группы — `Part.Elasticity/Friction`, старые `Font`/`FontSize` против `FontFace`, `BillboardGui.DistanceStep` и устаревшие GUI/звук/physics-поля. Их нельзя автоматически преобразовать без проверки значения, default и поведения класса.
- Для 15 карт сохранён непреобразованный sidecar `MaterialColorsSerialize`. По 502 257 объектам отдельно отмечено различие представления `AttributesSerialize` (Bobux) и уже декодированных `Attributes` (rbx-dom); сами общие нормализованные значения атрибутов прошли сравнение.

Это подтверждает чтение дерева, ссылок и сравниваемых данных, но **не** означает, что Luau-скрипты карты работают или что графика/физика уже эквивалентны Roblox. Эти части требуют отдельных runtime-, визуальных и API-тестов. Предыдущий отчёт о живом импорте и playtest остаётся в [аудите карт](ROBLOX_MAP_IMPORT_AUDIT_RU.md).

### A2: повторная проверка трёх выбросов

Три карты прогнаны повторно по тем же SHA исходников с повторным использованием уже созданных rbx-dom dumps. У каждой совпало число экземпляров и все общие значения свойств; в `top_value_mismatches` пусто. Цифры `Bobux only / rbx-dom only` ниже относятся к наличию значений только в одной схеме, а не к несовпадению общих значений.

| Карта | Экземпляры Bobux / rbx-dom | Только Bobux / только rbx-dom | Главный вклад в разницу полей |
|---|---:|---:|---|
| `Murder Mystery 2.rbxl` | 7 871 / 7 871 | 7 512 / 2 305 | `TextLabel`, `TextButton`, `TextBox`: `Font` и `FontSize` у Bobux против `FontFace` у rbx-dom (4 610 старых значений против 2 305 новых); `Part.Elasticity/Friction` — по 1 330 каждого. |
| `Roblox - Rocket Arena.rbxl` | 1 993 / 1 993 | 3 628 / 0 | `Part.Elasticity/Friction` — по 1 783; далее `Decal.Shiny/Specular` — по 20. |
| `Stickmasterluke - The Underground War.rbxl` | 1 440 / 1 440 | 2 627 / 8 | `Part.Elasticity/Friction` — по 1 295; у GUI `Font`/`FontSize` — по 4 на каждом из `TextButton` и `TextLabel`, против 8 `FontFace`. |

Следовательно, эти карты и сейчас составляют заметную часть хвоста. Сами числа не доказывают, что их надо мигрировать: `Elasticity/Friction`, `Font/FontSize`, `Decal.Shiny/Specular` и устаревшие служебные поля требуют отдельной проверки defaults и runtime-семантики.

### A3: round-trip rbx-native по карте и формату

Для каждой строки `rbxdump --roundtrip` сначала загрузил DOM исходника, затем отдельно вызвал binary/XML serializer, повторно прочитал полученные байты и сравнил деревья. Поэтому ошибки `serialize failed` однозначно возникают при записи. Ошибки сравнения после повторного чтения сами по себе не показывают, изменил ли данные writer или повторный reader. Предыдущий общий вывод «виноват writer» для всех 14 карт был слишком сильным и здесь исправлен.

| Карта | Загрузка исходника | Binary round-trip | XML round-trip |
|---|---|---|---|
| `Build a Boat FULLY WORKING…rbxl` | исходник прочитан | сравнение: `UnscaledCofm` равен NaN с обеих сторон; comparator считает NaN неравным самому себе | сериализация: XML writer не кодирует `Unknown` |
| `ACF_-_VANGUARD_2.rbxl` | исходник прочитан | сравнение после re-read: `Backpack.Name` был `Unknown`, в прочитанном результате отсутствует; компонент потери пока не изолирован | сериализация: XML writer не кодирует `Unknown` |
| `Natural Disaster Survival (Subscribe to FrenchBread).rbxlx` | исходник прочитан | сериализация остановлена: `SurfaceGui.CanvasSize` отсутствует у части экземпляров класса | успешно |
| `2017 - Lego's Plane Wars (1).rbxl` | исходник прочитан | сравнение после re-read: `LinkedSource` `Content(None)` → `String("")`; компонент изменения пока не изолирован | успешно |
| `2017 - Lego's Plane Wars.rbxl` | исходник прочитан | сравнение после re-read: `LinkedSource` `Content(None)` → `String("")`; компонент изменения пока не изолирован | успешно |
| `2011 - Natural disasters survival.rbxl` | исходный XML не разобран: malformed entity; retry на временной нормализованной копии прочитан | на retry-копии сравнение после re-read: `LinkedSource` `Content(None)` → `String("")` | на retry-копии успешно |
| `Combat-system-UNCOPYLOCKED.rbxl` | исходник прочитан | сравнение: `UnscaledCofm` равен NaN с обеих сторон | сериализация: XML writer не кодирует `Unknown` |
| `Grw-a-garden-UNCOPYLOCKED.rbxl` | исходник прочитан | сравнение: одинаковые NaN в `UnscaledCofm` | сравнение: одинаковые NaN в `UnscaledCofm` |
| `Steal-A-Brainrot-Modded-Uncopylocked.rbxl` | исходник прочитан | сравнение: одинаковые NaN в `UnscaledCofm` | сериализация: XML writer не кодирует `Unknown` |
| `2015 - Epic Minigames.rbxl` | исходник прочитан | успешно | сериализация: XML writer не кодирует `Unknown` |
| `2018 - Tower_Of_Hell_Full.rbxl` | исходник прочитан | сравнение: одинаковые NaN в `UnscaledCofm` | сравнение: одинаковые NaN в `UnscaledCofm` |
| `NowDoTheHarlemShake - The Normal Elevator.rbxl` | исходник прочитан | сравнение: одинаковые NaN в `UnscaledCofm` | сериализация: XML writer не кодирует `Unknown` |
| `Reignwolf - Escape the facility obby.rbxl` | исходник прочитан | сравнение после re-read: неизвестное значение `Script.Name` отсутствует; компонент потери пока не изолирован | успешно |
| `Nikilis - Murder Mystery 2.rbxl` | исходник прочитан | сравнение: одинаковые NaN в `UnscaledCofm` | сериализация: XML writer не кодирует `Unknown` |

Итого оба round-trip успешны на 7 картах; binary — на 8, XML — на 12. В 7 binary mismatch значение до и после печатается как NaN, поэтому это дефект equality-check в диагностике. У 7 карт XML serializer явно остановился на `Unknown`; два бинарных изменения `Name` и три `LinkedSource` обнаружены только на завершающем сравнении. Чтобы приписать эти пять изменений writer-у или повторному reader-у, надо сохранить промежуточные сериализованные файлы и прочитать их независимым parser-ом.

### Почему `Font` пока не мигрируется в V2

Проверка отдельного XML-набора показала, что rbx-dom переносит `TextLabel.Font` в `FontFace` для enum ID 0–45, но прерывается на новом ID 46. Для `Arial`/`ArialBold` его зафиксированная миграция записывает семейство `Arial.json`, тогда как текущая документация Roblox говорит, что эти удалённые enum-варианты соответствуют семейству Arimo. Значит, oracle полезен как независимая реализация формата, но его старую Font migration нельзя принимать за актуальную семантику движка.

`FontSize` rbx-dom оставляет enum-значением и не создаёт `TextSize`. Roblox документирует `FontSize` как deprecated, а `TextSize` как число в offsets. До runtime-проверки на этой паре свойств V2 сохраняет сериализованные значения и не подменяет их догадкой. См. [Enum.Font](https://create.roblox.com/docs/reference/engine/enums/Font), [Datatype.Font](https://create.roblox.com/docs/reference/engine/datatypes/Font), [TextLabel](https://create.roblox.com/docs/reference/engine/classes/TextLabel) и [Enum.FontSize](https://create.roblox.com/docs/reference/engine/enums/FontSize).

## Следующие этапы

1. Получить актуальные миграции свойств из Roblox reflection/API dump и применить точечно к устаревшим полям. Начать с `Font`/`FontSize`, проверяя каждое преобразование в Godot GUI.
2. Сделать runtime-проверки V2 для GUI safe-area, content-ассетов и PBR-карт. Совпадение дерева данных ещё не доказывает, что эти значения влияют на раскладку и материалы.
3. Затем прогонять импортированные игровые сценарии и Lua API по категориям (персонаж/физика, сеть, GUI, скрипты), сохраняя сбои как воспроизводимые проверки. Именно здесь выяснится, что мешает картам работать после успешного чтения файла.

Старая Studio-команда остаётся текущим рабочим путём; этот план продолжает развитие V2 и сравнительного инструментария отдельно.

Подробная таблица всех карт и машинные отчёты лежат в `.codex-tmp/rbxdom_diff_20261003/summary.md` и `summary.json`, рядом с JSON по каждой карте и сжатым oracle dump. Прогон дополнительно проверен 29 unit-тестами конвертера и comparator.

## Как использовать другие проекты

| Проект | Для чего полезен Bobux | Граница применения |
|---|---|---|
| [rbx-dom](https://github.com/rojo-rbx/rbx-dom) | Независимый reader/writer для бинарных и XML place/model файлов, типизированные Roblox-типы, reflection/migration database; сейчас используется как oracle для диффа. | Не проверяет поведение импортированной игры в Godot. |
| [GodotLuau](https://github.com/Pimpoli/GodotLuau) | Практический Godot-референс для дерева place, сохранения неизвестных классов/свойств, скриптов и runtime API. README заявляет бинарный `.rbxl` импорт, Luau, R6/Humanoid, remotes и теги. Можно сравнивать конкретные классы и игровые сценарии. | README указывает, что `.rbxlx` не поддержан, asset ID сами по себе не загружаются, а API неполон. Проверять заявленные R6-размеры/суставы на тех же аватарах и сценариях, а не считать их Roblox-эквивалентом без теста. Проект MIT. |
| [rbx-native](https://github.com/chteau/rbx-native) | Третий путь для чтения `.rbxl/.rbxlx`, round-trip, mesh и reflection; CLI `rbxdump --roundtrip` и viewer пригодны для воспроизводимых проверок формата и визуального UX. README помечает проект pre-alpha, при этом заявляет round-trip parser tests на реальных файлах. | Runtime и отдельные форматы, например `Terrain.SmoothGrid`, не завершены. Перед включением в автоматическую матрицу проверить актуальный dependency graph и выход на тех же 21 файлах. |
| [RBX-Asset-Extractor](https://github.com/zv8001/RBX-Asset-Extractor) | Источник идей для локального кэш-сканера и отдельного пайплайна мешей: README/changelog описывают версии мешей 1–5, Draco v7, предпросмотр и OBJ-экспорт. | Это исследователь/экспортёр локального кэша, не place parser; локальные cache assets и embedded data в `.rbxl` — разные входы. |
| [Fleasion](https://github.com/fleasion/Fleasion) | Специализированный asset/proxy-инструмент с cache/export, preview, утилитами mesh/R15→R6 и Draco-зависимостью. Полезен для декомпозиции mesh/rig-проверок и asset-форматов. | Не `.rbxl` importer. README описывает локальный HTTPS proxy и изменение Roblox trust bundle; это не часть потока импорта Bobux. Репозиторий ограничивает использование образовательными и личными целями, поэтому код не переносить в Bobux без отдельной проверки лицензии. |

Рекомендуемая архитектура остаётся дифференциальной: Bobux V2, rbx-dom и при необходимости rbx-native читают один и тот же исходный файл; общий отчёт показывает дерево, родителя, ссылки, типы/значения свойств, теги, атрибуты и содержимое скриптов. GodotLuau полезнее подключать отдельно как runtime-референс, а два cache-инструмента — только к asset pipeline.

### Что дополнительно проверено в исходниках GitHub

- **GodotLuau** изучен по текущему `src/importer/`. Его сильные архитектурные идеи — пакетная обработка по фазам, явная проверка созданных объектов, placeholders для классов без реализации и отчёт по пропускам/ошибкам. В Bobux V2 уже есть асинхронные пакеты, preflight и счётчики, но можно отдельно усилить post-import coverage check. Код GodotLuau в Bobux не копировался. README отмечает ограничения: только бинарный `.rbxl`, asset ID сами не загружаются, часть типов пропускается.
- **rbx-native** собран на Windows stable toolchain, pinned commit `cc50d54b1528ac7ffc470ce232a45295ca5972aa`. `rbxdump --roundtrip` прогнан на всех 21 картах: 20 прочитаны из оригиналов, один старый XML потребовал той же узкой временной нормализации; после неё прочитаны все 21. Полный бинарный и XML round-trip прошли 7 карт; отдельно binary прошёл на 8, XML — на 12. Per-map/formат причины приведены выше. Успешная загрузка rbx-native и ошибки round-trip не устанавливают точную виновную сторону в случаях несовпадения после re-read; это диагностический cross-check, не эталонная гарантия.
- **rbx-dom** остаётся единственным внешним oracle, использованным для точного диффа свойств Bobux на всех 21 картах. **rbx-native** добавлен как независимая диагностика загрузки/round-trip. Ни один проект не подключён как зависимость Bobux.

В V2 добавлена проверка покрытия: итоговый отчёт балансирует экземпляры источника между Part-кандидатами, их ошибками/metadata-fallback, объектами за пределами Workspace-фильтра, обработанными metadata-объектами и пропусками. Ошибки создания Part и пропущенные экземпляры теперь добавляют warnings; старый metadata-fallback для Part сохранён. Следующий основной этап — end-to-end runtime совместимость нескольких представительных карт: GUI, физика, ассеты и Luau.

## Источники по типам

- [Документация формата Attributes](https://github.com/rojo-rbx/rbx-dom/blob/master/docs/attributes.md) и [reader rbx-types](https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_types/src/attributes/reader.rs)
- [Декодирование MaterialColors](https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_types/src/material_colors.rs)
- [Устройство UniqueId](https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_types/src/unique_id.rs)
- [ScreenGui.IgnoreGuiInset](https://create.roblox.com/docs/reference/engine/classes/ScreenGui/DisplayOrder) и [значения Enum.ScreenInsets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets)
- [Enum.Font](https://create.roblox.com/docs/reference/engine/enums/Font), [Datatype.Font](https://create.roblox.com/docs/reference/engine/datatypes/Font), [TextLabel](https://create.roblox.com/docs/reference/engine/classes/TextLabel) и [Enum.FontSize](https://create.roblox.com/docs/reference/engine/enums/FontSize)
