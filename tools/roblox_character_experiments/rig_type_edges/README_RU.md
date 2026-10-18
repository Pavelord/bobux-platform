# A3: отдельное наблюдение Humanoid.RigType

Статус на 18 октября 2026: **NATIVE_OBSERVED / BOBUX_NOT_IMPLEMENTED**. После review исходники заморожены в `frozen_v1/`. Пять независимых Play на Studio `0.743.0.7431133` дали 720 целостных scalar cases; различий измеренных исходов между повторами не обнаружено. Raw-архивы, транспортные и строгие отчёты находятся в `tests/roblox_humanoid/phase_a/rig_type_edges_v1_20261017/`. Это не native/Bobux parity PASS и не физическое преобразование rig. Подробности: [наблюдения](../../../docs/ROBLOX_RIG_TYPE_OBSERVED_RU.md).

Это server-only scalar probe. Он использует только новые собственные `Instance.new("Humanoid")`: либо без Parent, либо непосредственно под Workspace. Нет Model, частей тела, R15 skeleton, HumanoidDescription, смены Player.Character, Avatar settings, HTTP или оригинальных Source/assets/keyframes. Наблюдаемое поведение bare Humanoid не переносится автоматически на живого Player или физическую перестройку персонажа.

План содержит пять независимых Play-файлов: 1–3 train, 4–5 holdout. В каждом ровно 144 case: два контекста × две проверяемые baseline R6/R15 × два target R6/R15 × 18 input variants. Каждый case создаёт новый disposable Humanoid. Эти 144 объекта внутри Play остаются **одной** Play-сессией, а не 144 независимыми повторениями. Порядок case задаётся до наблюдений: seed 20261016, описанный в builder LCG32/Fisher–Yates, одна и та же фиксированная перестановка для всех пяти Play.

Input variants: matching EnumItem, число, bare Name, numeric string, target.Value+0.5, отдельный -0.5, другой enum domain, полная Enum string, nil, false, true, пустая table, -1, 999999, несуществующее имя, NaN, +Inf и -Inf. Target определяет построение input; итоговое значение не предполагается заранее. Например, -0.5 записывается одинаково при обоих target labels, а его преобразование определяет только native результат.

Перед созданием каждого Humanoid в case_begin записывается, что свежий RigType — наблюдение, а R6 не является asserted fixture input. Getter читается до parenting и в выбранном контексте. Затем отдельный matching EnumItem устанавливает baseline. Сохраняются pcall/error, непосредственный getter, одна реальная settle Heartbeat и повторный getter. Точное совпадение domain/name/value baseline требуется для управляемого опыта. При невозможности подготовить baseline case получает BLOCKED, target setter не вызывается; скрытого retry или custom rig fallback нет.

После baseline settle подключаются оба native сигнала: GetPropertyChangedSignal("RigType") и Changed. До target setter, сразу после него и после каждой из двух реальных Heartbeat записываются getter и счётчики. Каждый пришедший callback сохраняет signal, arguments, getter, phase, время os.clock, индекс Heartbeat и сумму фактических callback dt. Setter имеет собственные отметки до/после pcall, отдельно от стоимости JSON-записи. Нет предполагаемых event counts, гарантии синхронности или утверждения, что после двух Heartbeat уже невозможен поздний callback. События baseline до подключения не измеряются и не выдаются за target events.

False остаётся boolean false. Nil и nonfinite numbers записываются только tagged objects, NaN/Inf не попадают в JSON как числа. Таблицы не обходятся рекурсивно. Ошибка target setter — наблюдаемый native outcome, а не автоматически ошибка стенда. Неопределённый обязательный getter, превышение event cap, ошибка baseline или watchdog сохраняют BLOCKED. При вариативности результатов пяти Play потребуется отдельное заранее зарегистрированное расширение ≥10 Play; holdout не используется для подбора.

Локальные source/semantic проверки:

```powershell
python -m unittest discover -s tools/roblox_character_experiments/rig_type_edges -p test_fixture.py -v
```

Они проверяют матрицу, XML в памяти, отсутствие custom rigs и доступа к stock Source/assets, компиляцию трёх собственных Luau файлов и 20 утверждений serializer/baseline-tag helper в официальном локальном Luau CLI. Последние используют только собственные структуры данных; они не симулируют Roblox coercion.

После review root отдельно разрешает замораживание в **новый** каталог. Builder без `--freeze-reviewed` не создаёт файлов и никогда не перезаписывает существующий output. Команду freeze до review не выполнять. Registration фиксирует все cases, split, input descriptions, timing/window policy, source/builder/test hashes, pinned creator-docs snapshot и SHA256 неизменённых общих exporter/parser. Пять XML содержат собственные config/registration и только два исполняемых исходника; serializer test в place не устанавливается.

При реальном запуске root использует Server Command Bar. После CHARACTER_EXPERIMENT_DONE готовая собственная папка CharacterExperimentTelemetry экспортируется неизменённым `tools/roblox_character_experiments/export_zstd.commandbar.luau`, затем проверяется неизменённым `parse_compressed_output.py`. Каждый Play имеет новый run GUID и отдельный output stem. Generic climbing baseline_summary этого parser для данного режима **не является RigType-анализом**. Нужен отдельный строгий анализ raw getter/coercion/event rows с сохранением всех пяти независимых сессий. Не объединять Studio versions и не исправлять frozen inputs после capture.
