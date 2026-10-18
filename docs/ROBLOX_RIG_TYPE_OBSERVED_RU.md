# Humanoid.RigType: измеренные scalar контракты

На 18 октября 2026 завершены **пять независимых Play / 720 cases** в официальной Roblox Studio `0.743.0.7431133`. Статус данных — **OBSERVED**, реализация нового consumer Bobux — **NOT_IMPLEMENTED_NOT_CALIBRATED**. Общая фаза A остаётся PARTIAL.

Это только свежие собственные `Humanoid`, без Parent либо непосредственно под Workspace. В стенде нет Model, частей тела, skeleton, Player.Character, HumanoidDescription, оригинальных Source, ассетов или анимационных ключей. Запись RigType здесь не доказывает перестройку физического персонажа или работу R15.

## План и целостность

План заморожен до первого Play: два контекста × baseline R6/R15 × target R6/R15 × 18 input variants = 144 cases. Каждый case получает новый Humanoid, установленную matching EnumItem baseline и одну settle Heartbeat. Затем измеряются setter, getter и оба property signals до записи, сразу после неё и после двух реальных Heartbeat. 144 объекта внутри одного Play остаются одним независимым повтором. Play 1–3 — train, 4–5 — holdout; порядок заранее фиксирован, fitting не выполнялся.

- [Registration и пять неизменяемых XML](../tools/roblox_character_experiments/rig_type_edges/frozen_v1/registration.json), registration SHA-256 `373875440df6200fef789a08d140899317a88cc96059d04f94106cf9ccd05f09`.
- [Архивы и отчёты](../tests/roblox_humanoid/phase_a/rig_type_edges_v1_20261017/README_RU.md). Первые четыре Play выполнены 17 октября UTC, пятый — 18 октября UTC; версия Studio одинакова.
- [Строгий analyzer](../tools/character_parity/analyze_rig_type_edges.py), SHA-256 `750bd6af4b6d7c06c69e844eee628816a7c9cd4f3153d774e018b57cc6e54a89`. Он прошёл 18 synthetic tests до чтения native данных. Они проверяют целостность, но не симулируют Roblox coercion.

Все пять транспортных экспортов проверены по SHA-256, размеру, количеству и непрерывности записей. Строгий разбор подтвердил по 144 полных case, точные baseline, четыре observation points, input tags, ссылки на события, реальные clocks и счётчики. Пять уникальных run/session/raw identities проверены отдельно. В итоговом aggregate нет input issues или различий измеренных исходов между повторами; 720 cases не выдаются за 720 независимых Play.

## Что наблюдалось

| Вход | Результат в испытанной матрице |
|---|---|
| Matching `Enum.HumanoidRigType`, числа 0/1, bare strings `R6`/`R15`, numeric strings `0`/`1` | Setter успешен, getter соответствует выбранному значению |
| 0.5 / 1.5 | Getter соответственно R6 / R15 |
| -0.5 | Getter R6 при обоих target labels |
| Чужой EnumItem, полная строка `Enum.HumanoidRigType.R6/R15`, nil, оба boolean, table, -1, 999999, неизвестное имя, NaN, ±Inf | Setter отклонён; baseline остаётся прежней |
| Успешная запись того же значения | В измеренном окне нет property callbacks |
| Успешная смена значения | В измеренном окне по одному `Changed("RigType")` и `GetPropertyChangedSignal("RigType")`, в таком порядке; callbacks наблюдались во время setter call |

Это наблюдения ограниченной матрицы, а не универсальное правило приведения для всех Enum-свойств. Окно из двух Heartbeat не исключает более поздних callbacks. Смена skeleton, живой Player, NPC motor, сетевой codec и Android этими данными не проверяются. Если новая версия или отдельная заранее зарегистрированная серия покажет вариативность, потребуется отдельное расширение минимум до десяти независимых Play.

## Следующая реализация

Нужен class-specific RigType adapter на всех Luau entry paths с VM-local EnumItem getter и общим scalar backend. Необходимо устранить постоянную перезапись player metadata в R6 и проверить настоящее событие изменения без лишних callbacks при равной записи. Нельзя скрывать значение в VM-local override или обещать физический R15 на основании scalar setter. После этого нужны настоящие player/NPC regression fixtures, оба порядка enum-профилей, scheduler/require и сетевые проверки. Ordinary-Part climbing остаётся отдельной незакрытой фазой C.
