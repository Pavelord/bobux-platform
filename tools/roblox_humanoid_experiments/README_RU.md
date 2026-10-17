# Независимый тест настоящего Roblox Humanoid

Открой `HumanoidBlackBox.rbxlx` в Roblox Studio через **Ctrl+O**, затем **F5 (Play)**. Это отдельное место: основная игра Bobux не изменяется. Не нажимай клавиши движения во время автоматического опыта. Обычно полный запуск занимает около двух минут; при таймаутах дольше. Успешный запуск заканчивается строкой `HUMANOID_EXPERIMENT_DONE … failures=0`; отдельный опыт может честно завершиться `failed` или `unmeasured`.

Место содержит Baseplate, ServerScriptService/Script и StarterPlayerScripts/LocalScript. Сервер создаёт чистый R6 через публичный `Players:CreateHumanoidModelFromDescriptionAsync` с пустым HumanoidDescription, TrussPart и настоящий бассейн Terrain Water. Клиент автоматически выполняет прыжки в обоих режимах UseJumpPower при нескольких Gravity, десять падений с пяти высот и несколько проходов по лестнице/воде. Climbing/Swimming включаются естественным контактом; принудительная смена этих состояний не используется. `Humanoid:Move(direction, false)` получает мировое направление и вызывается после стандартного управления, поэтому положение камеры не меняет тестовый ввод.

Размеры R6, CanCollide и свойства Humanoid снимаются до изменений теста и после приземления. Значения HumanoidStateType берутся через `GetEnumItems`, а не из таблицы вложенного задания. Поэтому противоречия задания с настоящим API остаются видны в результатах.

Прыжок запрашивается внутри PreSimulation через публичный `Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)`. Скорость не назначается вручную. Стандартный Roblox-inserted PlayerModule отключён через его экспортированный `GetControls():Disable()`, чтобы он не сбрасывал тестовый запрос своим вводом. Есть точные **наблюдения** непосредственно до и после запроса, первое PostSimulation с реальным `dt_sim_s`, максимальная наблюдённая скорость и высота. Внутренний момент импульса между публичными callback не наблюдаем: `first_post_vy` не называется точной стартовой скоростью. `ballistic_back_extrapolated_vy` — явно помеченная инженерная оценка, она не используется как доказанное число. Нет произвольного ожидания 0,05 с, выдаваемого за стартовую скорость.

В Output печатаются только короткие основные события и результаты, не длиннее 800 символов: нативный Studio log может обрезать даже небольшую строку. Все исходные записи, включая покадровые, сохраняются в `ReplicatedStorage.HumanoidExperimentTelemetry.chunk_0001…` как StringValue. Чтобы увидеть полный сырой журнал в Output, **до остановки Play** выбери клиентскую Command Bar и выполни:

```lua
local a=game:GetService("ReplicatedStorage"):WaitForChild("HumanoidExperimentTelemetry"):GetChildren(); table.sort(a,function(x,y)return x.Name<y.Name end); for _,v in ipairs(a) do if v:IsA("StringValue") then print(v.Value) end end
```

Для надёжного извлечения из нативного файла журнала печатай каждый chunk порциями не длиннее 400 символов, экранируя их через `HttpService:JSONEncode`, и затем соедини декодированные порции в исходный текст. Печать огромного StringValue одной строкой пригодна для Output UI, но нативный файл может его обрезать. Парсер игнорирует обычные сообщения Studio, объединяет повторные записи по run_id/seq (полная запись заменяет короткую) и выбирает последний запуск:

```powershell
python C:\robloxclone\tools\roblox_humanoid_experiments\parse_output.py C:\path\studio.log --output C:\path\humanoid.empirical.json --csv C:\path\humanoid.frames.csv
```

Без сырого журнала остаются реальные результаты опытов и snapshots, но полный frame CSV отсутствует — парсер указывает это явно. Без `run_begin` он отказывается создавать эмпирический файл. Незавершённый запуск помечается `incomplete`. Таймаут лестницы/воды означает отсутствие измеренного множителя; ноль или ожидаемое число вместо него не подставляются.

`build_place.py` пересобирает XML из соседних `.luau`. `parse_output.py` формирует структурированный JSON: `measurements.jumps`, `measurements.landed_by_drop_height`, `measurements.locomotion`, а также исходные `cases`, `humanoid_defaults`, `r6_parts`, `state_enum`, `camera_properties` и `failures`. Числа можно переносить в отчёт Bobux только после настоящего запуска Studio. Тесты самого парсера используют синтетические записи и не являются эмпирикой Roblox.

Источники публичного API: [Humanoid](https://create.roblox.com/docs/reference/engine/classes/Humanoid), [Players](https://create.roblox.com/docs/reference/engine/classes/Players), [HumanoidStateType](https://create.roblox.com/docs/reference/engine/enums/HumanoidStateType), [RunService](https://create.roblox.com/docs/reference/engine/classes/RunService), [Terrain](https://create.roblox.com/docs/reference/engine/classes/Terrain). Никакие утечки, декомпиляция, бинарные патчи, executor API или сторонние закрытые модули не используются.
