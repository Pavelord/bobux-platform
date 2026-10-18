# RigType scalar: пять независимых native Play

**OBSERVED / BOBUX_NOT_IMPLEMENTED_NOT_CALIBRATED**. Собственные стенды, bare Humanoid и телеметрия; оригинальные Roblox Source, ассеты и ключевые кадры отсутствуют. [Описание и ограничения](../../../../docs/ROBLOX_RIG_TYPE_OBSERVED_RU.md).

Пять Play на Studio `0.743.0.7431133`, 144 cases в каждом, всего 720. Play 1–3 — train, 4–5 — holdout. Первые четыре выполнены 17 октября UTC, пятый — 18 октября UTC. Папка названа по дате замораживания плана. Все raw records, setter outcomes, getters и callbacks сохранены; различий измеренных исходов между пятью повторами не обнаружено. Здесь нет Bobux parity PASS, физической перестройки rig или проверки живого Player.

`playN.raw.log.zstd` — один Zstd frame с byte-exact собственным raw log; `playN.archive.json` фиксирует SHA-256 и размеры архива/raw. `playN.transport.json` сохраняет VERIFIED исходного EncodingService-экспорта. `playN.analysis.json` — строгий отдельный разбор, `five-plays.aggregate.json` — повторно проверенное объединение пяти независимых identity. `analyzer-review.json` фиксирует SHA анализатора и 18 synthetic tests до чтения native данных. `manifest.json` содержит hashes файлов данных и отчётов.

Frozen inputs находятся в [frozen_v1](../../../../tools/roblox_character_experiments/rig_type_edges/frozen_v1/registration.json). Исходные отчёты сохраняют реальные абсолютные пути машины измерения и не переписываются ради другого checkout. Для воспроизведения создайте новые отчёты в новой рабочей папке:

```powershell
$data = 'tests/roblox_humanoid/phase_a/rig_type_edges_v1_20261017'
$plan = 'tools/roblox_character_experiments/rig_type_edges/frozen_v1/registration.json'
$work = '.codex-tmp/rig-type-review-new'
if (Test-Path -LiteralPath $work) { throw 'Choose a new review folder' }
New-Item -ItemType Directory -Path $work | Out-Null
$reports = @()
foreach ($i in 1..5) {
    python tools/character_parity/native_evidence_archive.py unpack "$data/play$i.raw.log.zstd" --manifest "$data/play$i.archive.json" --output "$work/play$i.raw.log"
    if ($LASTEXITCODE -ne 0) { throw 'Raw integrity failed' }
    python tools/character_parity/analyze_rig_type_edges.py analyze "$work/play$i.raw.log" --observed "$data/play$i.transport.json" --registration $plan --output "$work/play$i.analysis.json"
    if ($LASTEXITCODE -ne 0) { throw 'Strict analysis blocked' }
    $reports += "$work/play$i.analysis.json"
}
python tools/character_parity/analyze_rig_type_edges.py aggregate --analyses @reports --registration $plan --output "$work/five-plays.aggregate.json"
if ($LASTEXITCODE -ne 0) { throw 'Independent Play coverage blocked' }
python -m unittest discover -s tools/character_parity -p test_analyze_rig_type_edges.py -v
```

Скрипты отказываются перезаписывать существующее evidence. Нужен Python с `zstandard`; никаких Roblox/Godot процессов этот повторный анализ не запускает. Числа времени сохраняются как наблюдения, без подбора фиксированного FPS. Окно двух Heartbeat не исключает более поздние callbacks. При вариативности нужна отдельная заранее зарегистрированная серия минимум из десяти независимых Play.
