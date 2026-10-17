# ROBLOX_ANIMATE_CONFIG — предварительный measured inventory

Studio `0.742.0.7421053`, run `56d7b7d5-beac-4f26-ba3e-d771a14ece51`, 14 октября 2026. **OBSERVED_METADATA_PROVISIONAL**, Phase A4 не закрыта.

Чтение публичных стандартных скриптов выполнено внутри официальной Studio Command Bar. В репозитории сохранены только идентификаторы, числовые/boolean кандидаты и длина Source. Текст функций, Source snippets, animation assets и keyframes не перенесены.

Метаданные: 62 rows, {'OBSERVED': 62}. Текущий R15 Animate дублирует cached R15; это не третий независимый script implementation.

**BLOCKED semantic constants:** regexp исходного probe извлекает начальное число выражения, а не результат. Например значение 2 у TAU может быть префиксом 2×π; значение 1 у REGEN_RATE нельзя считать 1/сек. Имена разных scopes могут перезаписываться. Эти факты сохранены как lexical candidates, не применяются к конфигурации и не получают статус проверенных STANDARD_SCRIPT constants.

| Script inventory | Source length | Числовые/boolean кандидаты |
|---|---|---|
| CharacterSounds: Players.pavelord332.PlayerScripts.RbxCharacterSounds | 13029 | [] |
| CharacterSounds: Players.pavelord332.PlayerScripts.RbxCharacterSounds.AtomicBinding | 7469 | {"manifestSizeTarget": 1, "manifestSize": 0} |
| Animate_R15: ReplicatedStorage.CharacterExperimentStockMetadataCache.R15.Animate | 28802 | {"lastTick": 0, "scale": 10, "allowCustomAnimations": true, "toolAnimTime": 0, "timeWarp": 1, "currentAnimSpeed": 1, "jumpAnimTime": 0, "jumpAnimDuration": 0.31, "EMOTE_TRANSITION_TIME": 0.1, "smallButNotZero": 0.0001, "toolTransitionTime": 0.1, "currentlyPlayingEmote": false, "setAngles": false, "normalizedRunSpeed": 1, "normalizedWalkSpeed": 0.5, "newWeight": 1, "climbFudge": 0, "amplitude": 1, "fallTransitionTime": 0.2, "HumanoidHipHeight": 2, "idx": 1, "frequency": 1} |
| Animate_R6: ReplicatedStorage.CharacterExperimentStockMetadataCache.R6.Animate | 15630 | {"idx": 1, "setAngles": false, "climbFudge": 0, "frequency": 1, "amplitude": 1, "lastTick": 0, "toolAnimTime": 0, "toolTransitionTime": 0.1, "currentAnimSpeed": 1, "jumpAnimTime": 0, "jumpAnimDuration": 0.3, "fallTransitionTime": 0.3, "EMOTE_TRANSITION_TIME": 0.1, "jumpMaxLimbVelocity": 0.75} |
| Health: Workspace.pavelord332.Health | 703 | {"REGEN_RATE": 1, "REGEN_STEP": 1} |

Ключи jumpAnimDuration, fallTransitionTime, toolTransitionTime, EMOTE_TRANSITION_TIME, normalizedWalkSpeed и normalizedRunSpeed приведены в таблице только при наличии в этой capture. Даже полный RHS literal требует отдельной проверки его назначения; static initializer не доказывает переходы и скорости анимаций.

R6 identifiers включают LoadAnimation, AdjustSpeed, SetDesiredAngle; R15 дополнительно AdjustWeight, GetVelocityAtPosition и GetPropertyChangedSignal. Оба упоминают Priority Core/Idle/Action. Sound script упоминает StateChanged и11 Humanoid states. Такая lexical inventory не доказывает вызов, его условия, sound volume/playback settings или полноценный Animator.

PlayerModule: отдельно Camera и Controls. В derived JSON сохранён полный набор dependencies/methods/signals для каждого row, включая BaseCamera, ClassicCamera, ZoomController, Popper, Keyboard, Gamepad, DynamicThumbstick, TouchJump, ClickToMove. Инициализационные переменные не являются настройками физического мотора.

Сырые animation observations содержат timing/weight/priority aggregates: R6 snapshots имеют6 Motor6D; R15 snapshots0 и дополнительные Length0 tracks. Это BLOCKED для утверждений о полном R15 skeleton/загрузке, а не доказательство отсутствия skeleton у Roblox.

Следующий шаг: strict metadata recapture, независимый обычный spawn, затем собственные анимационные аналоги без переноса оригинальных keyframes. Текущие настройки Bobux не изменены.

Факты и provenance: `tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.analysis.json`; оригинальный metadata SHA-256 `1c3e72b390ef4a119614b2ff0d9a5609d5957cdf5b0b77504d63d39b81e82872`.
