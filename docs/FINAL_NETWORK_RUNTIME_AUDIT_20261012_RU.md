# Проверка входа и Luau перед Halloween update

Проверено в текущем Godot 4.7 checkout, без публикации из этой проверки и без изменения файлов режимов. Финальная сборка и развёртывание проверяются отдельно.

## Исправления жизненного цикла

- `LuaScriptEngine.stop_script` удаляет ещё не скомпилированный Script из очереди по зарезервированному ID или контексту. Раньше завершение фоновой подготовки могло запустить уже остановленный Script. Контекст в регрессии остаётся живым, поэтому тест ловит именно поздний запуск, а не только удаление сцены.
- Подтверждение комнаты сохраняет номер подключения и точный MultiplayerPeer. После асинхронной загрузки старый запрос не закрывает новый peer, не подтверждает чужую комнату и не запускает её таймер авторизации.
- `MapManager.load_map` принимает необязательный callback актуальности. Проверки после загрузки файлов/ассетов предотвращают позднюю запись GameState от отменённого входа. Независимые предзагрузки без callback продолжают работать.
- Тестовый сервер редактора очищает служебные переменные окружения и прочитанные credentials только в своей памяти. Родительские файлы аккаунта не удаляются. Он слушает loopback, не использует production registry/heartbeat bootstrap; его комната получает отдельный `editor:` ID.
- Debug endpoint проверяет точный host/port URL authority; адрес с `127.0.0.1:123@public.example` не принимается за loopback. Release-сборка не включает этот debug switch.

## Результаты

| Проверка | Результат |
| --- | --- |
| Реальная WebSocket RPC protocol gate | Старый `vps-ws-2026-10-10-1` отклонён до map sync; текущий `vps-ws-2026-10-10-2` принят |
| F5 Classic, текущий авторитетный дочерний сервер | Контролируемый аватар, выход и остановка только собственного child process |
| F5 Долина семи ветров | 4269 блоков, manifest 6, replica ready, аватар доступен, клиентских Luau failures 0 |
| F5 Natural Disaster Survival | 867 блоков, manifest 18, replica ready, аватар доступен, клиентских Luau failures 0 |
| Child boundary | Loopback, protocol -2, Luau 0.719, сохранённых service/account credentials нет |
| Отменённый map join | Новый peer/room/map сохранены, старый timeout не запущен, независимая предзагрузка успешна |
| Deferred Script lifecycle | Все проверки, включая индивидуальную отмену worker reservation, успешны |
| Luau task fairness | 24 задачи завершены, failures 0 |
| Luau recursive scheduling/Instance identity | Успешно, failures 0 |
| Luau task error isolation | Преднамеренная бесконечная задача прервана watchdog; остальные 12 задач завершились |
| Humanoid/пространственный контракт | Дробный урон, события Health/MaxHealth, ненулевой origin комнаты, Scriptable/Custom камера успешны |
| Network poll lifecycle | Закрытый ENet не опрашивается; подключающийся WebSocket продолжает опрашиваться |

Преднамеренная watchdog-ошибка в `validate_luau_task_isolation` является условием успешного теста; это не ошибка режима. Остальные перечисленные журналы не содержат `ERROR:`/`SCRIPT ERROR:`.

Исходные JSON карт в изолированных cache-only данных имеют SHA-256:

- Valley: `0edbf745eaaeb1091349e717dc47899541da3beb46230584d6be6450ce723d75`.
- NDS: `c6e37cb0be066fde61114884e6e39d2f1532caed2a3906265b2d5de7e7a1a9f6`.

Эти join checks не являются измерением Android FPS, холодной загрузки или полного цикла всех бедствий. Графические и экспортные тесты выполняются отдельно.

## Повторить

```powershell
C:\Python314\python.exe tools/run_network_protocol_gate.py --godot .codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe
C:\Python314\python.exe tools/run_pc_performance.py --prepare-only --maps valley,nds --tag final-editor-maps --client-appdata .codex-tmp/performance/final-editor-maps
$env:APPDATA = 'C:\robloxclone\.codex-tmp\performance\final-editor-maps'
& '.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tools/validate_editor_test_server.gd -- --bobux-editor-test-client --map=akx0oto939gi501_dolina_semi_vetrov
& '.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tools/validate_editor_test_server.gd -- --bobux-editor-test-client '--map=z9ovqynlv860sgw_narural disaster survival - bobux edition'
& '.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tools/validate_map_join_cancellation.gd
& '.codex-tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tools/validate_deferred_runtime_lifecycle.gd
```

Журналы: `.codex-tmp/performance/final-*.log`, `.codex-tmp/performance/protocol-gate/*.log`; скрытые server logs — `final-editor-*/Godot/app_userdata/Bobux/editor_test/*.log`. Для exportrelease отсутствует feature `editor`; debug endpoint разрешён только debug-сборке и только loopback. Production protocol gate, duplicate-session и capacity checks не отключались.
