# Подготовка выпуска Bobux — 9 октября 2026

Выпуск разрешён пользователем в текущей задаче. Это план и результаты подготовки;
документ не подтверждает, что новая версия уже опубликована.

Подготовка продолжена 10 октября. Standalone launcher build 21 и Setup 0.1.49
собраны; main Windows/Android/Linux и production deploy ожидают завершения
проверок runtime и фикса серверной репликации.

## Согласованные версии

| Компонент | Сейчас на сервере | Следующий выпуск |
| --- | --- | --- |
| Windows игра | 0.1.48, build 53 | 0.1.49, build 54 |
| Android, `com.bobux.game` | 0.1.48-mobile, build 53 | 0.1.49-mobile, build 54 |
| Windows launcher | 0.1.18, build 20 | 0.1.19, build 21 |
| Setup / Linux download manifest | 0.1.47, build 52 | 0.1.49, build 54 |

Build 54 требует обновления клиента: новый server-authority `SpawnVisibility`
добавляет synchronizer ID даже с пустым `SceneReplicationConfig`. Изолированный
тест точного Godot 4.7 подтвердил ошибки `on_spawn_receive` у прежней структуры
клиента, хотя движение и visibility client-owned аватара продолжались.
Клиент и сервер согласованно переведены на протокол `vps-ws-2026-10-10-1`.
Старая версия получает требование обновить Bobux до создания комнаты/загрузки
карты; build 54 проходит полный room handshake. Проверка выполнена реальными
NetworkManager RPC через отдельный WebSocket port 18148, без live аккаунтов.
Команда: `python tools/run_network_protocol_gate.py --godot <Godot console exe>`.
Все три процесса завершились с кодом 0, ошибок Godot в логах нет.
Логи: `.codex-tmp/performance/protocol-gate/`.

Перед сборкой следует повторно прочитать live manifests через
`tools/ci/resolve_release_versions.ps1 -Production -LauncherVersion 0.1.19 -LauncherBuild 21`.
Новая сборка launcher меняет его номер даже при небольших изменениях исходников.
Нельзя повторно использовать номер 20 для другого ZIP.

## Что проверено

- SSH по существующему ключу и известному host key работает. Значения ключей и
  серверных переменных не выводились. VPS использует Godot 4.7 stable и Node 22.23.2.
- APK build 53 из локального release совпадает с SHA-256 в live mobile manifest.
  Сертификат этого APK совпадает с имеющимся release keystore. Новая production
  APK должна сохранить пакет и сертификат, чтобы обновить установленную игру
  с сохранением данных. Диагностический `com.bobux.performance` остаётся отдельным.
- Доступны export templates Windows x86_32, Android и Linux x86_64, Inno Setup 6,
  JBR Android Studio и Android SDK.
- Исправлен упаковщик серверного hotfix: `.dist` с тестовыми APK, промежуточные
  native-файлы, секреты, базы и локальные кэши исключены. Валидатор проверяет
  обязательные Linux Luau debug/release библиотеки, API, сервер и release helpers.
  Пять тестов проверяют содержимое архива, в том числе реальный набор tar filters.
- Добавлена подготовка серверной транзакции: staged Godot import, Luau smoke и
  API tests выполняются до остановки live процессов. Сохраняются предыдущие
  изменяемые runtime-файлы, API с зависимостями и стабильные downloads/manifests.
  Ошибка после начала обновления запускает откат. Три Linux regression tests
  проверили возврат исходников/пакетов, удаление новых модулей и сохранение
  аккаунтов, SQLite/WAL, storage и `.env`; зависимости с относительными symlinks
  сохраняются. Сгенерированный Bash прошёл `bash -n`.
- Добавлена проверка семи native inputs до/после экспортов, архитектуры DLL/ELF,
  точного размера и SHA-256 упакованного Luau в Windows ZIP, обоих Android ABI,
  Linux tar и серверном archive. Диагностическая APK, захватившая нулевой SO во
  время линковки, отвергнута валидатором и не используется для выпуска.
- Устранено накопление временных AppImage extraction: новый smoke извлекает
  AppImage внутрь временного каталога, который очищается после транзакции.
- Повторная независимая проверка 10 октября: 5 archive tests и 2 native tests
  прошли; rollback — все 3 tests на Linux (Windows: 2 прошли, symlink test
  пропущен из-за разрешений хоста). Все 7 native inputs совпадают с финальным
  snapshot. Standalone launcher/Setup сохраняют приведённые ниже SHA-256.
- Исключены точные имена локальных документов/QA-каталогов и `export_templates`;
  runtime-библиотеки и игровые ресурсы сохраняются. Release PS1 отвергает
  диагностический main scene / Android preset, обновляет versioned APK alias
  при повторной упаковке и явно читает UTF-8 при изменении номеров версий,
  чтобы PowerShell 5 не искажал русский текст в конфигурациях.

## Готовые независимые артефакты

Launcher parse/load/install contract прошли проверку. Исходники launcher не
менялись после его экспорта, EXE имеет file version `0.1.19.0`.

| Артефакт | Размер | SHA-256 |
| --- | ---: | --- |
| `dist/BobuxLauncher-Windows.zip`, build 21 | 41,439,279 bytes | `288DFA8D6FB87F6F38761666440C51A93F7DF3C0CD347A1FB749C685AC417D43` |
| `dist/release/BobuxSetup.exe`, 0.1.49 | 29,692,112 bytes | `612CBD7474B10225C8C64736703E96E61900E875D3E4EF333C14704C5116797E` |

Полный release pipeline может пересобрать launcher/Setup. В окончательные
manifests входят хэши финальных файлов после общей сборки.

## Место на VPS

До подготовки было занято 97% диска, свободно около 1.2 GB. С согласованием
ведущего агента удалены только десять явно перечисленных старых каталогов
`/tmp/appimage_extracted_*` и `/tmp/bobux-linux-smoke.*`. Для каждого проверены
абсолютный resolved path внутри `/tmp`, возраст и отсутствие открытых файлов
через `lsof +D`. Освобождено 5.59 GB, сразу после проверки свободно 6.84 GB.
Production downloads, прежние release backups, аккаунты и пользовательские
сессии не удалялись. Аудит: `.codex-tmp/performance/release-cleanup-result.json`.

## Финальная сборка после проверки runtime

Не запускать экспорт одновременно с изменениями runtime, native библиотек или
диагностическим export helper: упаковка должна взять одну согласованную версию.
Убедиться, что новый native watchdog собран для Windows release x86_32 и x86_64,
Android release ARM64/ARM32 и Linux debug/release x86_64.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy_bobux_release.ps1 `
  -Version 0.1.49 -Build 54 -MobileVersion 0.1.49-mobile -MobileBuild 54 `
  -LauncherVersion 0.1.19 -LauncherBuild 21 -WindowsArchitecture x86_32 `
  -ReleaseNotes "Faster loading, Luau runtime and multiplayer performance improvements." `
  -SkipUpload
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_desktop_downloads.ps1 `
  -Version 0.1.49 -Build 54
```

Pipeline обновляет `project.godot`, `export_presets.cfg`, launcher configs и
константы, `game/launcher/latest.json` и `mobile/latest.json` вместе с артефактами.
Нельзя вручную обновлять только manifest. `game/` — связанный Git repository;
pipeline пишет его release metadata, остальной код этого repository не меняется.
Старые версии по умолчанию в release PS1 не использовать.

После проверки Windows package, production APK на подключённом Android и
полного набора runtime regression checks ведущий агент запускает существующий
`tools/deploy_bobux_release_paramiko.py` с явными номерами версий и существующими
key/known_hosts путями. Он сохраняет защищённую серверную `.env` и live данные.
Копия для отката остаётся в `/opt/bobux-release-rollback-54-<UTC timestamp>`.

## После публикации

Проверить `tools/verify_bobux_server.ps1`, совпадение versions, sizes и SHA-256
Windows/Android/Setup/Linux, no-store на manifests, доступность WebSocket и
реальный вход/выход в четыре тестовых режима. Особенно проверить серверный
цикл бедствий NDS и скрипты «Нормального лифта». Убедиться, что авторские данные
режимов не изменились. Статус опубликованного выпуска фиксируется в итоговом
отчёте после этих проверок.
