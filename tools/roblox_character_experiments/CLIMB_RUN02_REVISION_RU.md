# Предрегистрация Climb run02

14 октября 2026. Native replay ещё не выполнен. Предыдущий run
`d21f12ca-b480-4585-b6b0-8f0ce98732a0` сохраняется отдельно как BLOCKED.
Его телеметрия и видео не перезаписываются и не объявляются 45 успешными повторениями.

Исправлен измерительный стенд, основные исходники Bobux не менялись:

- Опорная Baseplate расширена с `(220,1,100)` до `(512,1,512)` при прежнем
  положении `(0,-.5,0)`. Это изменение геометрии стенда явно записано в
  `support_geometry`, `previous_support_geometry` и `support_geometry_changed`.
  Пять препятствий, их Parts/Truss и все 45 случаев/сplits/WS/6s окна неизменны.
  Указание WS32×6s=192stud используется только для размера свободной площадки,
  не как ожидаемая измеренная траектория Humanoid.
- Перед каждым случаем проверяются текущий Player.Character, его Parent,
  живой Humanoid/Health/State и принадлежность HRP к Character/Workspace.
  При потере жизни выполняется штатный RPC load R6, затем заново привязываются
  собственные diagnostic sensors и callbacks. Максимум два восстановления до
  измерения: перед reset и при потере жизни во время первого reset.
- RPC загрузки ограничен 20 wall-seconds; settle ограничен 6s. Старые ссылки,
  state connections и собственные sensors освобождаются при смене generation.
- Перед teleport очищается Move и отправляется нулевой Humanoid:Move.
  Linear/angular velocities сбрасываются во время anchored reset. Единственный
  принудительный state — Freefall до измерения; Climbing никогда не задаётся.
- Смерть/удаление во время измеренного окна даёт BLOCKED с частичной телеметрией.
  Такой measured case не повторяется автоматически и не превращается в PASS.
  Восстановление для следующего случая не стирает предыдущую ошибку.

Отдельный файл `CharacterClimbBaseline_run02.rbxlx` содержит точную новую матрицу
из `tests/roblox_humanoid/phase_a/climb_run02.splits.json`; исходные run01 `.rbxlx`
и `splits.json` не пересозданы. Версия `2026-10-14-climb-a2-life-safe`.

Проверки перед capture: официальный Luau0.742 compiler, equality embedded matrix
и registration, SHA loaded measurement, прежние obstacle/cases/splits и покрытие
опорной площадкой максимального командного пути. Это **статическая проверка
стенда**, не доказательство 45 валидных native повторений; его даст новый capture.
