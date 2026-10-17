# Phase A2: измеренные defaults персонажа

Studio `0.742.0.7421053`, run `56d7b7d5-beac-4f26-ba3e-d771a14ece51`. Статус **OBSERVED**, функциональная совместимость Bobux **NOT_TESTED**.

Проверено 2401 исходных записей, SHA-256 `36226a4f7dde505e224e5fbccefb26c8584ffd4ef752a02f9d5e9a771243237b`. Анализ не меняет raw и не подбирает параметры.

5 fresh Humanoid и по5 независимо созданных official-description моделей R6/R15. Четыре template spawn дают по5 getter samples одного спавна, а не5 независимых спавнов. Это разные категории повторения.

| Поле | Fresh Humanoid | Модель R6 | Модель R15 |
|---|---|---|---|
| WalkSpeed | 16 | 16 | 16 |
| JumpPower | 50 | 50 | 50 |
| JumpHeight | 7.199999809265137 | 7.199999809265137 | 7.199999809265137 |
| UseJumpPower | true | true | true |
| HipHeight | 0 | 0 | 2.192423105239868 |
| MaxSlopeAngle | 89 | 89 | 89 |
| Health | 100 | 100 | 100 |
| MaxHealth | 100 | 100 | 100 |
| AutoRotate | true | true | true |
| AutoJumpEnabled | true | true | true |
| BreakJointsOnDeath | true | true | true |
| RequiresNeck | true | true | true |
| EvaluateStateMachine | true | true | true |
| AutomaticScalingEnabled | true | true | true |
| CameraOffset | [0, 0, 0] | [0, 0, 0] | [0, 0, 0] |
| RigType | Enum.HumanoidRigType.R6 | Enum.HumanoidRigType.R6 | Enum.HumanoidRigType.R15 |
| NameDisplayDistance | 100 | 100 | 100 |
| HealthDisplayDistance | 100 | 100 | 100 |
| DisplayDistanceType | Enum.HumanoidDisplayDistanceType.Viewer | Enum.HumanoidDisplayDistanceType.Viewer | Enum.HumanoidDisplayDistanceType.Viewer |
| NameOcclusion | Enum.NameOcclusion.OccludeAll | Enum.NameOcclusion.OccludeAll | Enum.NameOcclusion.OccludeAll |
| HealthDisplayType | Enum.HumanoidHealthDisplayType.DisplayWhenDamaged | Enum.HumanoidHealthDisplayType.DisplayWhenDamaged | Enum.HumanoidHealthDisplayType.DisplayWhenDamaged |

Во всех пяти fresh экземплярах все17 публичных GetStateEnabled возвращали true, включая None. Это наблюдение getter, оно не доказывает, что каждый state достижим или разрешён для ChangeState.

**BLOCKED: наследование обычного spawn.** Изменённые StarterPlayer values23/61/9/false/37/false наблюдаются на StarterPlayer, но Humanoid из template остаётся16/50/7.199999809265137/true/89/true. Player camera zoom и AutoJump также остались первоначальными. Нельзя на основании этого отключать наследование: template и момент изменения после входа Player смешивают причины. Нужны новые Player и обычный spawn без StarterCharacter.

Bobux: статическое совпадение пяти config values в JSON не означает проверенное поведение. Editor R6 factory хранит HipHeight2 при измеренном R6 HipHeight0; RigType возвращается числом; CameraOffset требует реального camera test; AnimationTrack пока объект учёта. Производственный код здесь не менялся.

R15 модель имеет16 BasePart, measured HipHeight2.192423105239868 относится именно к пустому HumanoidDescription этой Studio, а не к любому R15. Snapshot Motor6D_count0 и треки Length0 требуют проверки skeleton/загрузки до фазы D/G.

Детальные распределения, seq и ссылки на текущие исходники: `tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.analysis.json`.
