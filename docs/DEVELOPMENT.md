# Окружение разработчика

Все команды выполняются из корня вашей копии Bobux, если явно не указана другая папка. Примеры для Windows PowerShell не зависят от буквы диска.

Локальная организация проекта на 17 октября 2026: основная копия остаётся в `C:\robloxclone`, резервная — `D:\robloxclone`. Тяжёлые build/toolchain-артефакты вынесены в `D:\Bobux_Artifacts\2026-10-17`. Для нового clone эти пути не требуются. Если инструмент был вынесен, укажите его реальный путь или установите нужную зависимость заново; не копируйте весь архив в Git.

## Зависимости

| Компонент | Для чего нужен |
| --- | --- |
| Git и Git LFS | Исходники и крупные модели / миры |
| Godot 4.7 stable | Основной проект, выделенный сервер и лаунчер |
| Экспортные шаблоны той же версии Godot | Сборки клиента и лаунчера |
| Node.js 22.13+ и npm | API; используется встроенный `node:sqlite` |
| Python 3.12+ | Конвертер миров и измерительные инструменты |
| Android SDK, JDK и настройки Android export в Godot | Экспорт и запуск на Android |
| C++ toolchain и SCons | Только для пересборки нативного Luau bridge |

Вспомогательные Python-модули для сжатых миров и evidence-проверок:

```powershell
python -m pip install lz4 zstandard
```

Нативные библиотеки выбираются по `addons/luaAPI/luaAPI.gdextension`. Проверьте, что библиотека для вашей платформы и архитектуры получена полностью. Текущий Bobux bridge основан на Luau 0.719; его pinned dependencies и команда C++-сборки описаны в [native/luau_bridge/README.md](../native/luau_bridge/README.md). Наличие legacy mapping другой платформы не означает, что её runtime уже проверен как Luau.

## Запуск клиента

Откройте корневой `project.godot` в Godot 4.7. Проект использует Compatibility renderer и запускает `scenes/login/login.tscn`. Первый импорт после клонирования или удаления `.godot/` может занять время.

В репозитории есть Windows helper с закреплёнными checksums Godot:

```powershell
./tools/ci/install_godot.ps1 -SkipTemplates
& $env:GODOT_BIN --editor --path .
```

Без `-SkipTemplates` helper также устанавливает нужные ему export templates. При использовании другого установленного Godot задайте путь к его console executable самостоятельно:

```powershell
$env:GODOT_BIN = 'D:\Tools\Godot\Godot_v4.7-stable_win64_console.exe'
& $env:GODOT_BIN --editor --path .
```

`launcher/project.godot` — отдельный проект. Он запускается через:

```powershell
& $env:GODOT_BIN --editor --path ./launcher
```

Репозиторий `game`, указанный в `.gitmodules`, содержит отдельно версионируемые release-материалы; `exiting_game` — исторический submodule. Не требуется рекурсивно загружать исторический проект для редактирования основного клиента. CI отдельно получает `game/launcher` для проверок, которым нужен launcher manifest.

## Локальная серверная часть

Текущий backend состоит из Express API, PocketBase и локальных файловых / SQLite-хранилищ. `services/bobux_api/server.js` слушает loopback-интерфейс, порт задаётся переменной `PORT` (по умолчанию 3000). API получает настройки из окружения; пример в корневом `.env.example` сам по себе не загружается Node.js автоматически.

Установить зависимости и выполнить API-проверки:

```powershell
Push-Location services/bobux_api
npm ci
npm run check
npm test
Pop-Location
```

Тесты импорта вызывают Python. Для запуска собственного API настройте `POCKETBASE_URL`, `STORAGE_DIR`, `PUBLIC_BASE_URL` и необходимые server-only credentials в окружении, затем выполните `npm start` из `services/bobux_api`. Пользовательская база, серверное хранилище и ключи не входят в Git. Schema и production-конфигурация требуют отдельной настройки; запуск процесса не создаёт готовую копию действующего сервиса.

Для клиента адреса API находятся в секции `[cloud]` корневого `project.godot`, WebSocket endpoint — в `[application]`. Для выделенного сервера используются `BOBUX_API_URL`, `PUBLIC_SERVER_WS_URL`, `GODOT_SERVER_PORT` и server-only credentials, читаемые `server/server_main.gd`. Изолированные проверки выполняйте со своими endpoints: не направляйте тестовую запись данных в действующий сервис.

## Проверки

Простая проверка импорта проекта:

```powershell
& $env:GODOT_BIN --headless --editor --quit --path .
```

Проверка конкретного runtime-контракта:

```powershell
& $env:GODOT_BIN --headless --path . --script res://tools/validate_lua_runtime_regressions.gd
```

Python-проверки character parity без запуска Godot:

```powershell
python tools/character_parity/run_checks.py --offline
```

После закрытия Roblox Studio — последовательный набор Python и Godot:

```powershell
python tools/character_parity/run_checks.py --godot "$env:GODOT_BIN"
```

Runner сохраняет отдельные логи и `report.json` в новой папке `.codex-tmp/character_parity/suites/`. Он не закрывает чужие процессы и не заменяет Android, визуальное сравнение, старый / новый сетевой протокол или нагрузочное испытание. Дополнительные параметры и правила baseline — в [tools/character_parity/README.md](../tools/character_parity/README.md).

Workflow [Bobux Validate](../.github/workflows/validate.yml) содержит текущий список CI-проверок клиента, лаунчера, API и сети. Проверки на физическом телефоне и сценарии конкретного режима выполняются отдельно.

## Экспорт

В `export_presets.cfg` есть presets `Windows Desktop`, `Android` и `Linux`. Их параметры и native libraries должны соответствовать целевой архитектуре. В частности, текущий Windows release preset настроен на x86_32; редактор и его debug extension могут быть x86_64.

Для будущих локальных сборок используйте `tools/build_local.ps1`. При наличии диска D он выбирает `D:\Bobux_Artifacts\local`, иначе — `.dist/local` внутри проекта. Каждая сборка получает новую папку с UTC timestamp и GUID, готовый файл и `export.log`. Скрипт не меняет presets, не запускает готовую игру и ничего не публикует. Архив старых сборок от 17 октября находится отдельно в `D:\Bobux_Artifacts\2026-10-17`.

Сначала проверьте план без запуска Godot и создания файлов:

```powershell
./tools/build_local.ps1 -Preset 'Windows Desktop' -DryRun
./tools/build_local.ps1 -Preset Android -DryRun
./tools/build_local.ps1 -Project Launcher -DryRun
```

После установки шаблонов и настройки SDK / подписи можно выполнить экспорт:

```powershell
./tools/build_local.ps1 -Preset 'Windows Desktop' -ArtifactRoot 'D:\Bobux_Artifacts\local'
./tools/build_local.ps1 -Preset Android -GodotBin "$env:GODOT_BIN"
```

Приоритет пути артефактов: `-ArtifactRoot`, затем переменная `BOBUX_ARTIFACT_ROOT`, затем default. Для редактора: `-GodotBin`, затем `GODOT_BIN`, затем локальный `.codex-tools/godot-4.7/..._console.exe`. `-Project Game` поддерживает presets `Windows Desktop`, `Android`, `Linux`; `-Project Launcher` — только `Windows Desktop`. Пути с junction/symlink в цепочке назначения отклоняются. Внутренний кэш Godot остаётся рядом с проектом; перенос выходного файла не переносит `.godot/`.

CI и release packagers продолжают использовать свои прежние пути и команды; этот wrapper предназначен для локального экспорта.

Подпись Android хранится локально, без keystore и паролей в Git. Успешный экспорт не публикует обновление: загрузка сборок, manifest и развёртывание API / игровых серверов относятся к отдельному выпуску. Скрипты `deploy_vps.ps1` и `tools/mobile/deploy_mobile_release.ps1` изменяют внешнюю среду; для обычной разработки их запуск не нужен.

## Материалы и лицензирование

Сохраняйте сторонние notices и проверяйте права на новые ассеты. Общая лицензия на Bobux пока не определена в корне репозитория; лицензия одного addon не распространяется автоматически на основной код, брендинг и пользовательские миры. Правила вклада и воспроизводимости измерений — в [CONTRIBUTING.md](../CONTRIBUTING.md).
