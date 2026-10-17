# Следующее покрытие Enum для character API

Дата проверки: 15 октября 2026. Статус: **PLAN / NOT_IMPLEMENTED**. Прочитаны только существующие локальные исходники и evidence; Studio, Godot и сеть для этой проверки не запускались. Этот план не меняет предыдущие результаты и не закрывает A3.

## Что уже действительно сохранено

| Evidence | Содержимое | Граница вывода |
|---|---|---|
| `tests/roblox_humanoid/phase_a/2026-10-14-studio-run02.raw.log`, run `56d7b7d5-beac-4f26-ba3e-d771a14ece51`, `a3_enum_probe`, seq 2 | Шесть полных списков: HumanoidStateType 17, AnimationPriority 7, CameraType 8, Material 45, SensorMode 4, SensorUpdateType 2 — всего 83 canonical items | Полного namespace здесь нет |
| `tests/roblox_humanoid/phase_a/2026-10-14-studio-enum-coercion-run01.raw.json`, run `c475020d-1687-4cb5-9b53-2ecbe4d5a2f7`, `root_GetEnums`, seq 242 | **648 уникальных имён** типов, в alphabetical sequence; для каждой записи сохранены только `tostring` и `type="Enum"` | Это полный список имён данного запуска Studio, **не списки items всех 648 типов** |
| Тот же coercion corpus, шесть `enum_identity_*` | HumanoidStateType, AnimationPriority, CameraType, Material, SensorMode, RaycastFilterType | Вместе с первым probe имеется семь полных доменов, **85 canonical items**; Raycast aliases не дополнительные canonical items |
| Тот же corpus, 32 `Humanoid_RigType_*` строки | Property setter conversion/getter для fresh и independent anchored fixture; canonical control использует R6 | Можно повторно использовать conversion evidence. Нельзя выводить из него изменение физического R6/R15 rig |
| Первый corpus, `a2_native_getters` | RigType R6=0 и R15=1; CameraMode Classic=0 у Player/StarterPlayer | Наблюдения отдельных getters не заменяют полный namespace/coercion probe |

Имена HumanoidRigType, CameraMode и CoreGuiType уже присутствуют в сохранённых 648 именах на позициях 279, 113 и 157 соответственно. В текущем `roblox_enum_registry.gd::DEFINITIONS` этих трёх доменов нет: зарегистрированы семь доменов/85 items. Следовательно, нельзя заменять реальный subset искусственными 648 пустыми Enum objects и объявлять namespace завершённым.

SHA256 первого raw: `36226a4f7dde505e224e5fbccefb26c8584ffd4ef752a02f9d5e9a771243237b`. Его `-verified.raw.log` имеет тот же hash. SHA256 coercion raw JSON: `bf6f00d2dd18a509353347852a76aec14ae5778e81e23eb2773923961e154e19`.

## Зафиксированные официальные значения

Источник — уже сохранённый `tests/roblox_humanoid/phase_a/creator_docs_api.json`, commit Roblox/creator-docs **`031b2f91d3d47274c255f3ed5691c29f792c181d`**, fetched UTC `2026-10-14T15:50:54.075853+00:00`. SHA256 этого JSON: `82d9ba4b397c95077ae4a8389f0c13f359ed3b877df4514e0c43653cfccca088`. Ниже DOCUMENTED из этого snapshot; полный item-order/identity/coercion этих трёх namespace-доменов ещё не объявляется MEASURED.

| Домен | Name → Value | Текущее legacy-поведение |
|---|---|---|
| HumanoidRigType | R6 → 0; R15 → 1 | Числовой namespace совпадает по значениям; Humanoid getter возвращает scalar ID, metadata может хранить строку R6/R15 |
| CameraMode | Classic → 0; LockFirstPerson → 1 | В legacy namespace отсутствует. Нельзя путать с CameraType, где Custom=5/Scriptable=6 |
| CoreGuiType | PlayerList → 0; Health → 1; Backpack → 2; Chat → 3; All → 4; EmotesMenu → 5; SelfView → 6; Captures → 7; AvatarSwitcher → 8; ExperienceShop → 9 | Первые четыре совпадают. Legacy: EmotesMenu=4, SelfView=5, Captures=6, **All=7**; последние два отсутствуют |

Pinned YAML и сохранённые SHA256:

- [HumanoidRigType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/HumanoidRigType.yaml): `95743029fee8e021dec1ebd1b656d72ec143d585810faab78ce9ead2e9116c12`.
- [CameraMode](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/CameraMode.yaml): `a59d41d176fc8273d4e9ff0b892ba04388c5dc2faf65295b953751aff7072067`.
- [CoreGuiType](https://raw.githubusercontent.com/Roblox/creator-docs/031b2f91d3d47274c255f3ed5691c29f792c181d/content/en-us/reference/engine/enums/CoreGuiType.yaml): `0514e7dc7a2ee0cbd073fd1e15eaee57617b4443c6d38e363a29325db2d8804a`.

## Минимальное следующее измерение

1. В отдельном собственном CommandBar probe прочитать только три `Enum.<Domain>:GetEnumItems()` без изменения мира. Сохранить полный порядок, Name/Value/EnumType, typeof/type/tostring, повторную identity/table-key lookup и FromName/FromValue. Чтение неизвестного member, readonly и extracted receiver проверить теми же ограниченными pcall случаями, что существующий kernel. Raw, размер, packet sequence, SHA256, run_id, UTC и Studio version обязательны; не подставлять DOCUMENTED как native expected result.
2. Отдельно измерять class-specific входы. Для RigType переиспользовать 32 имеющихся conversion-строки и добавить недостающий R15 control на собственном unparented Humanoid. Не трогать Player.Character и не выдавать успешную запись RigType за создание R15 тела.
3. CameraMode setters/getters исследовать на собственном disposable Player, если такая factory разрешена в выбранном контексте; отказ factory — BLOCKED этого пути. StarterPlayer singleton и реальную камеру проверять в отдельном собственном месте с известными начальными settings, сохраняя/восстанавливая значения. LockFirstPerson movement/zoom — самостоятельная проверка фазы H; один успешный setter её не закрывает.
4. CoreGui methods запускать в отдельном собственном Play fixture: записать все доступные GetCoreGuiEnabled значения, выполнить component/All matrix и восстановить snapshot в cleanup. Проверять реально наблюдаемые component flags после All, а не только pcall. Native ошибки контекста/платформы сохранять как OBSERVED ошибки или BLOCKED недоступного fixture, не имитировать успех. Полный официальный class schema StarterGui пока не включён в `creator_docs_api.json`; его следует отдельно сохранить на том же commit перед реализацией service behavior.

Для шагов 2–4 нужны canonical item, numeric ID, canonical name, full Enum string, numeric string, wrong-domain item с тем же Value, fraction, nil/missing/extra args, bool и invalid input. Общий EnumItem kernel не доказывает одинаковую coercion у разных properties/methods. Отсроченные callbacks требуют явно ограниченного observation window. Физические thresholds здесь не калибруются.

## Безопасная последовательность реализации после измерений

1. Добавить **только определения** трёх доменов в opt-in registry и isolated tests, не меняя legacy proxy/default profile. Покрытый subset станет 10 доменов/99 canonical items, если native подтвердит все 14 новых pairs. `GetEnums` продолжает честно возвращать реализованный subset. Совпадение с YAML — STATIC_MATCH; порядок и runtime behavior — отдельные native/VM assertions.
2. Расширять VM boundary по одному consumer: Humanoid.RigType; затем Player/StarterPlayer.CameraMode; затем StarterGui CoreGui methods. Распознавать class и property/method domain; metadata, shared BobuxInstance и motor сохраняют профиль-независимые scalars/semantic identifiers. Профиль остаётся свойством VM, а не Node/shared wrapper. Для каждого consumer проверить две VM на общем объекте в обоих порядках запуска, getter/setter/events/require/task/GC/teardown и сохранение legacy результата.
3. **CoreGuiType нельзя просто перенумеровать в общем backend.** Число 4 означает legacy EmotesMenu, но parity All; число 7 означает legacy All, но parity Captures. Сегодня `Set/GetCoreGuiEnabled` кладут/читают `str(core_type)` в metadata dictionary и не реализуют All semantics. Перед включением parity consumer нужен typed domain-aware translation на VM boundary и единый semantic backend. Любая миграция существующих numeric keys должна иметь отдельный тест; без неё держать consumer PARTIAL, а legacy behavior неизменным.
4. Никакой автоматической отправки новых Enum objects по сети. Сначала сохранить текущий fail-closed transport guard; tagged codec/domain/value и явная version negotiation — отдельная проверяемая работа, затем old/new peer matrix.
5. Полные 648 доменов — отдельный namespace-data этап: собственный public `GetEnums` → `GetEnumItems` snapshot всех доступных типов с per-domain errors/counts/hash и сверкой pinned schema. Не следует считать такой snapshot реализацией всех связанных engine APIs. Этот этап не требует экспорта Source, native assets или keyframes.

## Условия принятия следующего increment

Новое evidence immutable и строго декодируется; legacy numeric IDs/default не изменены; три новых domain pairs сверены с pinned source и native data; оба VM creation orders проходят предметные assertions. Каждый class-specific consumer имеет собственный measured input/output regression. Изменение namespace не объявляет готовыми R15 physics, camera behavior, HUD, сетевую совместимость или фазу A целиком. До фактических запусков статусы native/VM acceptance остаются **NOT_RUN**.
