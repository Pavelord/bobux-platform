# Humanoid: измеренные receiver, arity и строки состояний

15 октября 2026, **OBSERVED_NOT_PARITY_COMPLETE**. Собственный probe выполнен в официальной Studio `0.743.0.7431133`, run `481ea197-ed76-4972-b05e-7a875c3fc888`. [Raw](C:/robloxclone/tests/roblox_humanoid/phase_a/2026-10-15-studio-humanoid-edges-run01.raw.json), SHA-256 `22772eaa9965b6711656ab67f231c440c8a9dbcaca57b3e990824af9bdb28b9e`: 91 строка, 96 pcall outcomes (55 true / 41 false), 12 сигналов. [Проверка транспорта](C:/robloxclone/tests/roblox_humanoid/phase_a/2026-10-15-studio-humanoid-edges-run01.observed.json) и [производный анализ](C:/robloxclone/tests/roblox_humanoid/phase_a/2026-10-15-studio-humanoid-edges-run01.analysis.json) отделены от raw.

Создаются свежие unparented Humanoid и один Part для неправильного receiver; Player.Character и сцена не меняются. События записаны немедленно и за два последующих Heartbeat с фактическим dt. Это **один опыт каждого точного input case**, а не пять независимых повторов. Физические эффекты ChangeState в этом стенде **NOT_OBSERVABLE**.

| Вызов | Наблюдение |
|---|---|
| Извлечённый метод с другим Humanoid | Применяется к переданному receiver; не к объекту, от которого извлечён метод |
| Неверный/отсутствующий receiver | `Expected ':' not '.' calling member function …`; проверяется до аргументов |
| `ChangeState()` / `ChangeState(nil)` | Успех, ноль возвращаемых значений; физическое действие не установлено |
| `GetState(…)` | Лишние аргументы игнорируются; свежий unparented Humanoid возвращает EnumItem None (18) |
| `GetStateEnabled()` / nil | Ошибка `Argument 1 missing or nil` |
| `SetStateEnabled` без bool / bool=nil | Ошибка `Argument 2 missing or nil`, в том числе при nil state |
| `SetStateEnabled(nil, false)` | Ошибка `Argument 1 missing or nil` |
| bare `Running`, matching EnumItem, number 8 | Меняют canonical флаг Running; false/true дают событие `(EnumItem Running, bool)` |
| строки `8`, `Enum.HumanoidStateType.Running`, неизвестное имя | Setter успешен с zero returns, getter=true; все 17 canonical flags остаются прежними, событий за окно нет |

Не следует применять к методам правила property setter. В отдельном native наборе `c475020d-1687-4cb5-9b53-2ecbe4d5a2f7` Studio 0.742 CameraType/Material принимают numeric string как enum value, тогда как enabled-state методы выше оставляют его no-op. Полная строка `Enum.CameraType.Scriptable` для property setter отвергается. Наоборот, похожая строка enabled-state метода успешно игнорируется.

Реализация включается только через `RobloxParity.EnumItem`; default NumericEnums сохранён. Реальные VM контракты проверяют typed сигналы, сохранение scalar backend, отсутствие событий/изменений flags для opaque строк и extracted receivers. Новые входы и bool casts вне записанного набора остаются partial. Нельзя выводить поведение физического мотора, Animator, NPC навигации или сетевой совместимости из этих method checks. Текущий статус и snapshots: [ROBLOX_CHARACTER_PARITY_RU.md](ROBLOX_CHARACTER_PARITY_RU.md).
