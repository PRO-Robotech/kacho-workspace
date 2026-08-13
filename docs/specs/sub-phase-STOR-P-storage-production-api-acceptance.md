# STOR-P — приёмка: целевой API storage (продакшн-вариант)

**Статус:** DRAFT (ожидает APPROVED — гейт ban #1).
**Ветка:** `release/storage-production-api` (оба репозитория).
**База:** `bfaf239b` (монорепо) / `c58bc2b` (воркспейс) — точка ветвления, проверено
`git merge-base`. Сам `origin/release/2026-08-12` с тех пор ушёл вперёд, поэтому имя ветки
базой быть перестало: сверять надо с хешем.
**Сверено с деревом:** монорепо **`5cec65cd`** (13.08.2026) — под каждым сценарием назван
**исполнитель поимённо** либо сказано, что его нет. Первая редакция переписи снималась с
`db7146fb`; пять строк изменились в следующем же коммите — там, где это произошло, названы
**обе** ревизии, чтобы движение было видно, а не затёрто.

> [!important] Перепись сделана по ЗАКОММИЧЕННОМУ дереву, а не по рабочей копии
> В момент переписи рабочая копия монорепо несла незакоммиченные правки соседнего
> исполнителя — в частности в `services/storage/tests/newman/cases/*.py`. Считать по ней
> значило бы записать в приёмку числа, которых нет ни в одной ревизии и которые никто не
> сможет воспроизвести. Поэтому каждый предикат прогнан через `git grep <sha>`, а не по
> файлам на диске.
>
> **Так и вышло, и это стоит записать.** Первая редакция переписи снималась с `db7146fb`;
> следующий коммит (`5cec65cd`) закоммитил ровно те правки, что лежали в рабочей копии, и
> **пять строк переписи сменили корзину**: `:changeDiskType`, оба `:copy`, журнал операций
> снимка и снятое поле размера блока получили чёрный ящик. Число «14 без исполнителя» жило
> одну ревизию — но пересчитать его удалось за минуту, потому что у каждой строки **назван
> предикат**. Число без предиката пришлось бы измерять заново целиком.
**Первый бэкенд:** Ceph RBD (Tentacle 20.2).

## 0.-1. Перепись исполнителей — числами

Сценарий без названного исполнителя неотличим от покрытого: «75 сценариев» одинаково
читается и когда за ними стоят пробы, и когда за ними не стоит ничего. Поэтому перепись
идёт первой и в трёх корзинах, а не в двух — «частично» здесь не смягчение, а **отдельный
исход**: у сценария есть проба, и она проверяет **не то**, что он утверждает.

| Корзина | На `5cec65cd` | Было на `db7146fb` | Что это значит |
|---|---:|---:|---|
| **Исполнитель есть** | **47** | 42 | названная проба/гейт исполняет то, что сценарий утверждает |
| **Частично** | **18** | 19 | проба есть, но покрывает часть сценария — под каждым сказано, какую именно и чего не хватает |
| **Исполнителя нет** | **10** | 14 | не исполняет ничто; причина названа |
| Всего | **75** | 75 | |

**Из 10 непокрытых** два — про глаголы и полосы, доставленные без единой пробы
(STOR-P-64 квота · 51 множественная привязка); четыре — про свойства, которых в дереве нет
вовсе (STOR-P-16 префиксы · 45 предикат состояния при ресайзе · 66 потребление проекта ·
9 границы размера на `Create`); два — про пробы, которые не написаны при живом свойстве
(STOR-P-02 · 38); два — про отсутствующие гейты (STOR-P-27 · 62).

**Перепись сделана по дереву, а не по памяти.** Предикат для каждой строки — имя теста
(`git grep '^func Test' <sha>` — 442 функции в `services/storage`, из них 133 добавлены
веткой) либо идентификатор newman-кейса, либо доказанное отсутствие: для непокрытых
сценариев в теле сказано, какой именно поиск дал ноль. Поэтому «ноль находок» здесь отличимо
от «ноль прочитанного».

## 0.0. Отношение к плану — два документа, один предмет, разные роли

Обоснования, рыночный контекст, форма JSON, схема БД и **нормативная таблица текстов
ошибок** живут в `docs/plans/storage-production-api-plan.md`. Здесь они **не
пересказываются**: два места об одном предмете расходятся на первом же уточнении.

| Документ | Отвечает на вопрос |
|---|---|
| План | «как устроено и почему именно так» |
| **Эта приёмка** | «что обязано быть верно, и каким тестом это ловится» |

Каждый сценарий ниже — **будущий падающий тест**. Уровень указан в заголовке:
`unit` · `integration` (testcontainers Postgres) · `contract` (суита адаптера) ·
`newman` (чёрный ящик через край) · `гейт` (обход дерева).

## 0.1. Что авторизует эта приёмка

Целевой вид модуля целиком, без промежуточных поставок. Ни один пункт не откладывается
маркером в коде: недостающее дописывается в этой же ветке. Порядок коммитов — внутренний,
наружу уходит один MR.

## 0.2. Out-of-scope — с названными исполнителями

Ведут себя как «нет такого пути», а не «недоделано».

| Предмет | Исполнитель | Предикат появления |
|---|---|---|
| Отображение тома на узле (map/unmap) | узловой агент плоскости данных | компонент заведён и у него объявлена граница доверия |
| Резервные копии | отдельный домен | своя приёмка |
| Ключи шифрования арендатора | отдельный домен ключей | своя приёмка; здесь только флаг класса |
| Лимиты как **ресурс** | платформенный домен | до тех пор storage энфорсит и отдаёт потребление чтением |
| `digest` у Image | **решение владельца** | см. §11 открытых вопросов плана |
| Переопределение производительности на томе | Ф-рост | бэкенд объявил энфорсмент |
| Второй бэкенд | Ф-рост | сам факт добавления — проверка шва |

## 0.3. Инварианты-критерии (проверяются, не только сценариями)

- **INV-P1. Ни одного маркера отложенной работы.** Гейт `internal/repohygiene`
  `TestNoDeferredWorkInTheTree` остаётся зелёным на всей ветке.
- **INV-P2. Ни одного ломающего изменения контракта после этой ветки.** Всё, что
  объявлено формой, объявлено сейчас; рост добавляет поля, не меняет смысл отданных.
- **INV-P3. Публичная поверхность не несёт инфра-лексики** — ни именем поля, ни
  **значением**. Гейт проекции расширяется со значений.
- **INV-P4. AuthN+AuthZ на каждом RPC обоих листенеров**, включая новые. Отсутствие
  записи в каталоге прав — отказ, а не пропуск.
- **INV-P5. Within-service инварианты — на DB-уровне**, не software check-then-act.
  Каждый спорный путь несёт integration-пробу с конкурентными горутинами.
- **INV-P6. Дублёр не снисходительнее настоящего.** Фейковый адаптер выполняет тот же
  контракт, что Ceph-адаптер, и гоняется той же контрактной суитой.
- **INV-P7. Ноль находок отличимо от нуля прочитанного.** Каждый гейт печатает объём
  осмотренного; каждый счётчик отличает «не отказывало» от «не вызывалось».

---

# F1. Каталог классов

### STOR-P-01 (positive) `integration` — посев снят, пустой каталог законен
**Given** свежая база с применёнными миграциями
**When** `DiskTypeService.List` без фильтра
**Then** список **пуст**, `nextPageToken` пуст, код `OK`
**And** ни один из пяти прежних слагов не резолвится через `Get`

**Исполнитель:** `internal/repo/pg/disk_type_integration_test.go` :: **`TestDiskTypeCatalogEmptyAfterSeedRemoval`** — пустой список + ни один из пяти слагов посева не резолвится; положительный контроль (зарегистрированный класс виден) в том же теле.

### STOR-P-02 (edge) `integration` — снятие посева не роняет миграцию на живых томах
**Given** база, где на классе `block-balanced` есть том
**When** применяется миграция снятия посева
**Then** миграция проходит, класс `block-balanced` **остаётся** (на него ссылаются)
**And** классы без томов сняты
> Безусловный `DELETE` упёрся бы в FK RESTRICT и уронил старт сервиса.

**Исполнителя НЕТ.** Пробы нет. Условный `DELETE … AND NOT EXISTS (… volumes …)` стои́т в миграции 0016, но ни один прогон не ставит том на посеянный класс перед её применением, то есть ветка «класс остаётся» не исполняется. `internal/migrations/dropguard_integration_test.go` :: `TestIntegration_StorageDropsAreMeasured` меряет состав дропов, а не эту ветку.

### STOR-P-03 (negative) `integration` — при пустом каталоге том не создаётся
**Given** пустой каталог
**When** `Volume.Create` с любым `diskTypeId`
**Then** операция завершается ошибкой `FAILED_PRECONDITION`, текст `DiskType <id> not found`
**And** строки тома в БД нет

**Исполнитель:** `internal/repo/pg/volume_disk_type_zone_integration_test.go` :: **`TestVolumeOnMissingDiskTypeStillReportsMissing`** — текст `DiskType <id> not found`, строки тома нет.

### STOR-P-04 (positive) `newman` — администратор регистрирует класс, арендатор его видит
**Given** пустой каталог
**When** админ создаёт класс через internal-mux, затем арендатор зовёт публичный `List`
**Then** класс виден, несёт `lifecycle: ACTIVE`, `capabilities`, `limits`

**Исполнитель (частично):** Через край **недостижим**: коллекции ходят только на внешний слушатель, административная полоса живёт на `:9091`. Публичную половину держат newman `DT-LST-CRUD-OK` / `DT-GET-CRUD-OK` (`tests/newman/cases/disk-type.py`: ярус и обращение — из закрытых словарей, инфра-полей нет, `performanceTier` снят), административную — `TestDiskTypeCreateUpdateAdmin` · `TestDiskTypePolicyRoundTrip` · `TestDiskTypeCapabilitiesIntersectActiveBindings`. Перенаправление записано **в самом case-файле**, а не только здесь.

### STOR-P-05 (negative) `unit` — ярус только из словаря
**When** админ создаёт класс с `performanceTier: "nvme-fast"`
**Then** `INVALID_ARGUMENT`; принимаются только `CAPACITY|BALANCED|FAST|SINGLE|IO_MAX`
> Свободная строка — канал утечки мимо гейта проекции, читающего имена полей.

**Исполнитель:** `internal/domain/disk_type_policy_test.go` :: **`TestDiskTypeTier_ClosedDictionary`** (домен) + `internal/repo/pg/disk_type_integration_test.go` :: **`TestDiskTypePolicyHeldByDBInvariants`** (ограничение БД, отрицание в паре с законным близнецом).

### STOR-P-06 (positive) `unit` — `Update` класса идёт по маске
**Given** класс с `zoneIds: [a, b]`
**When** `Update` с маской `{name}` и телом без `zoneIds`
**Then** `zoneIds` **не изменились**
> Сегодня full-replace: пропущенный `zoneIds` обнулял список.

**Исполнитель:** `internal/apps/kacho/api/disktype/disktype_mask_test.go` :: **`TestUpdateAdminAppliesOnlyMaskedFields`** + `TestUpdateAdminEmptyMaskPatchesAllMutable` · `TestUpdateAdminRejectsUnknownMaskField` · `TestUpdateAdminRejectsImmutableMaskField`; репозиторный близнец — `TestDiskTypeUpdateAppliesOnlyNamedFields`.

### STOR-P-07 (negative) `integration` — `DEPRECATED` не принимает новые тома
**Given** класс в `DEPRECATED`, на нём есть существующий том
**When** `Volume.Create` на этот класс
**Then** `FAILED_PRECONDITION` `DiskType <id> is not accepting new volumes`
**And** существующий том продолжает читаться и обновляться

**Исполнитель (частично):** `internal/domain/disk_type_policy_test.go` :: **`TestDiskTypeLifecycle_OnlyActiveAcceptsNewVolumes`** утверждает предикат домена. Отказ **самого `Volume.Create`** на `DEPRECATED`-классе не проверяется ничем: текста `is not accepting new volumes` нет ни в одной пробе дерева, хотя ветка в стейтменте создания есть.

### STOR-P-08 (negative) `integration` — `RETIRED` с томами не удаляется
**Given** класс в `RETIRED`, на него ссылается том
**When** админ зовёт `Delete`
**Then** `FAILED_PRECONDITION` `DiskType <id> is in use`

**Исполнитель (частично):** `internal/repo/pg/disk_type_integration_test.go` :: **`TestDiskTypeDeleteFKRestrict`** (+ `TestDiskTypeDeleteFKRestrictRace`) — точный текст `DiskType <id> is in use`. Плечо **`RETIRED`** не утверждается: проба удаляет класс в любом состоянии обращения, то есть проверяет FK, а не связку «выведен из обращения ⇒ удаляется только при нуле томов».

### STOR-P-09 (negative) `unit` — границы размера энфорсятся из класса
**Given** класс с `limits{min: 1GiB, max: 16TiB, step: 1GiB}`
**When** `Volume.Create` с размером 512MiB / 20TiB / 1.5GiB
**Then** каждый — `INVALID_ARGUMENT`, поле названо в детали ответа

**Исполнителя НЕТ.** `internal/domain/disk_type_policy_test.go` :: `TestDiskTypeLimits_ValidateVolumeSize` зелёный, но **вакуумный**: он зовёт `ValidateVolumeSize` напрямую, а прод-код её не вызывает ни разу, и предикат вставки тома границы не читает. Сценарий утверждает свойство `Volume.Create` — его не держит ничто.

---

# F2. Бэкенды и ревизии привязок

### STOR-P-10 (positive) `integration` — регистрация бэкенда
**When** админ создаёт `StorageBackend{kind: CEPH_RBD, zoneIds, endpoint, credentialsRef}`
**Then** ресурс создан с id префикса `sb-`, `status: ACTIVE`

**Исполнитель (частично):** `internal/repo/pg/storage_backend_integration_test.go` :: **`TestStorageBackendRegisteredAndReadBackIdentically`** + `internal/domain/storage_backend_test.go`. Обе пробы **присваивают `id` сами** и идут в репозиторий напрямую; полоса RPC (`InternalStorageBackendService.Create`) `id` не назначает и потому отвергает каждый вызов. Сценарий описывает именно её.

### STOR-P-11 (negative) `гейт` — бэкенд не выставлен наружу
**Then** ни `StorageBackend`, ни `DiskTypeBinding` не резолвятся на external mux
**And** их REST-привязки классифицированы как internal по паре (метод, путь)

**Исполнитель:** `cmd/storage/permission_map_test.go` :: **`TestPublicListenerServesNoInternalService`** — наборы служб спрашиваются порознь: в публичном ни одной `Internal*`, во внутреннем хотя бы одна (вторая половина не украшение — без неё проба зеленела бы на пустом внутреннем наборе).

### STOR-P-12 (negative) `unit` — секрет не проходит через API
**When** в `credentialsRef` передано значение, похожее на секрет, а не ссылку
**Then** `INVALID_ARGUMENT`: поле принимает **ссылку** заданной формы
**And** ни один ответ API и ни одна колонка БД не содержат материала секрета

**Исполнитель:** `internal/domain/storage_backend_test.go` — форма `CredentialsRef`: значение, не похожее на ссылку, отвергается; сам материал не доезжает ни до колонки, ни до текста отказа.

### STOR-P-13 (positive) `integration` — ревизия привязки создаётся, прежняя вытесняется
**Given** активная ревизия `rev=1` на (класс, зона)
**When** создаётся новая привязка на ту же пару
**Then** новая — `rev=2, ACTIVE`, прежняя — `SUPERSEDED`
**And** строка `rev=1` **не изменена ни в одном поле**

**Исполнитель:** `internal/repo/pg/disk_type_binding_integration_test.go` :: **`TestDiskTypeBindingRegisterSupersedesPrevious`** (прежняя строка не изменена ни в одном поле) + `internal/domain/disk_type_binding_test.go` :: `TestDiskTypeBinding_SupersedeProducesNewValue`.

### STOR-P-14 (negative, CONCURRENCY) `integration` — ровно одна активная ревизия
**When** две конкурентные `Create` на одну пару (класс, зона)
**Then** ровно одна получает `ACTIVE`, вторая — `ALREADY_EXISTS`
**And** тест под `-race`, детерминированный, без `time.Sleep`

**Исполнитель:** `internal/repo/pg/disk_type_binding_integration_test.go` :: **`TestDiskTypeBindingRegisterConcurrentExactlyOneWins`** + **`TestDiskTypeBindingRegisterRaceHoldsUnderAnyInterleaving`** — под `-race`, без `time.Sleep`.

### STOR-P-15 (negative) `integration` — ревизия с ссылающимися ресурсами не удаляется
**Then** FK RESTRICT: `FAILED_PRECONDITION`

**Исполнитель:** `internal/repo/pg/disk_type_binding_integration_test.go` :: **`TestDiskTypeBindingReferencedRevisionIsNotDeletable`**.

### STOR-P-16 (negative) `unit` — префиксы новых ресурсов известны роутеру
**When** `corevalidate.ResourceID` получает `sb-…` / `dtb-…`
**Then** классифицирует как валидные (внесены в `ids.KnownHyphenPrefixes()`)
**And** зеркальная проба: неизвестный префикс по-прежнему отвергается

**Исполнителя НЕТ.** Исполнителя нет, **и свойства нет**: `pkg/ids/` веткой не тронут, значений `sb`/`dtb` в `hyphenFormPrefixes` не появилось. Сегодня безвредно — `corevalidate.ResourceID` на путях обоих ресурсов не вызывается (перепись: ноль вхождений), — но сценарий утверждает ровно то, чего в дереве нет.

### STOR-P-17 (negative) `integration` — класс без активной привязки не создаёт томов
**Given** класс `ACTIVE`, привязки на зону тома нет
**When** `Volume.Create`
**Then** `FAILED_PRECONDITION`, текст называет отсутствие предложения в зоне
**And** строки тома нет

**Исполнитель:** `internal/repo/pg/volume_disk_type_zone_integration_test.go` — отказ `DiskType <id> has no active binding in zone <zone>`, отдельный от «не предлагается в зоне».

---

# F3. Политика на ресурсе

### STOR-P-18 (positive) `integration` — том фиксирует ревизию на момент создания
**When** `Volume.Create`
**Then** `volumes.binding_id` указывает на **активную** ревизию (класс, зона)
**And** `backend_object` заполнен и уникален

**Исполнитель (частично):** `internal/repo/pg/image_backend_binding_integration_test.go` :: **`TestImageBornCreatingInheritsBinding`** и `TestImageInheritsBindingFromSnapshot` держат это **для образа**; `internal/repo/pg/snapshot_placement_integration_test.go` :: `TestSnapshotInheritsBindingAndTenantSpace` — для снимка. Для **тома** утверждения о `binding_id`/`backend_object` нет ни в одной пробе, хотя стейтмент их заполняет.

### STOR-P-19 (positive) `integration` — правка класса НЕ ретроактивна
**Given** том создан под `rev=1` с числами QoS X
**When** админ заводит `rev=2` с числами Y
**Then** `GetInternal` тома по-прежнему показывает `rev=1` и числа X
**And** новый том на том же классе получает `rev=2`
> Класс — шаблон, а не живой указатель. Это несущая проба всей модели данных.

**Исполнитель (частично):** Существо держит `internal/repo/pg/disk_type_integration_test.go` :: **`TestDiskTypeUpdateNotRetroactiveForExistingVolumes`**. **Буква сценария невыполнима**: он утверждает через `GetInternal` тома, а тот отвечает `UNIMPLEMENTED` (план §4.6). Числа QoS ревизии наружу не читаются ничем.

### STOR-P-20 (negative) `integration` — сужение зон класса не трогает созданные тома
**Given** том в зоне `b`, класс предлагается в `[a, b]`
**When** админ сужает `zoneIds` до `[a]`
**Then** том читается, обновляется и удаляется без изменений
**And** **новый** том в зоне `b` отвергается

**Исполнитель:** `internal/repo/pg/disk_type_integration_test.go` :: **`TestDiskTypeUpdateNotRetroactiveForExistingVolumes`** — сужение зон не трогает созданные тома, новый том в снятой зоне отвергается.

### STOR-P-21 (positive) `unit` — имя объекта у бэкенда детерминировано
**Then** `backendObject == "<installPrefix>-<resourceId>"`, вычисляется чистой функцией
**And** адаптер имя **выводит**; проба подаёт имя во входе и убеждается, что оно проигнорировано

**Исполнитель:** `internal/blockbackend/blockbackend_test.go` :: **`TestObjectName_DeterministicAndPrefixed`** + `TestNamespaceOfProject`; пара «выводит / не принимает» — `internal/apps/kacho/api/image/register_test.go` :: `TestImageCreateDerivesBackendObject` против `TestImageRegisterKeepsSuppliedObjectName`.

### STOR-P-22 (negative) `unit` — префикс установки обязателен
**Given** конфигурация без префикса установки в production-режиме
**Then** сервис **отказывается стартовать** с сообщением, называющим ручку
> Без префикса два развёртывания на одном кластере усыновят объекты друг друга.

**Исполнитель:** `internal/blockbackend/blockbackend_test.go` :: **`TestValidateInstallPrefix_PairedControls`** и `TestValidateInstallPrefix_EmptyNamesTheConsequence` + `internal/config/blockbackend_guard_test.go` :: **`TestBootGuard_BackendWithoutInstallPrefix_RefusesToStart`**, `TestBootGuard_MalformedInstallPrefix_RefusesToStart`.

---

# F4. Состояния и операция

### STOR-P-23 (positive) `integration` — операция фиксирует намерение и завершается
**When** `Volume.Create`
**Then** `Operation.done == true` в пределах секунд, `error` не установлен
**And** том в статусе `CREATING`, `observed_state == ABSENT`

**Исполнитель:** `internal/repo/pg/volume_integration_test.go` :: **`TestVolumeCreateGetDerivedStatus`** (строка рождается в `CREATING`, наблюдаемое — `ABSENT`) + `internal/reconciler/cycle_integration_test.go` :: `TestCycle_CreatingBecomesReadyOnlyAfterTheObjectExists`.

### STOR-P-24 (positive) `contract`+`integration` — сверщик доводит до `AVAILABLE`
**When** сверщик отрабатывает
**Then** объект у бэкенда создан, `observed_state == READY`, публичный статус `AVAILABLE`

**Исполнитель:** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_CreatingBecomesReadyOnlyAfterTheObjectExists`** + `internal/reconciler/decide_test.go` :: `TestDecide`.

### STOR-P-25 (negative) `integration` — отказ бэкенда даёт `ERROR` с причиной
**Given** фейковый адаптер настроен отказывать по исчерпанию
**Then** статус `ERROR`, `statusReason == BACKEND_CAPACITY_EXHAUSTED`
**And** сообщение **не содержит** текста бэкенда

**Исполнитель:** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_BackendRefusalMarksTheResourceWithANamedReason`**; текст бэкенда наружу не выходит — `internal/blockbackend/blockbackend_test.go` :: `TestError_CarriesBackendTextForOperatorNotForTenant`.

### STOR-P-26 (negative, РЕГРЕССИЯ КЛАССА) `integration` — длинная работа не даёт ложного «готово»
**Given** адаптер, отвечающий дольше потолка исполнителя операций
**When** проходит окно разрешителя осиротевших операций
**Then** операция **не** помечается `Done` с несуществующим объектом
**And** статус тома отражает реальность (`CREATING` либо `ERROR`), а не «готово»
> Это регрессия на конкретный класс: разрешитель признаёт строку завершённой, читая нашу
> БД, а его объявленный контракт «частичных состояний нет» с внешним бэкендом неверен.

**Исполнитель (частично):** Класс закрыт **по построению**, и это держит гейт `internal/check/backend_port_reach_test.go` :: **`TestBackendPortIsReachableOnlyFromTheReconciler`**: порт плоскости данных недостижим с пути запроса, поэтому функция операции физически не может ждать бэкенд. Разрешитель осиротевших операций проверен отдельно — `internal/operationresolver/resolver_test.go` :: `TestResolve_CreateOfAnUncommittedResourceIsInterrupted` / `TestResolve_CreateOfACommittedResourceIsDone`. Чего нет: прогона с адаптером, отвечающим дольше потолка, — то есть сценарий как **написан** (через медленный адаптер) исполнителя не имеет.

### STOR-P-27 (positive) `unit` — три из пяти статусов имеют производителя
**Then** обход прод-кода находит производителя для `CREATING`, `DELETING`, `ERROR`
**And** гейт падает, если значение публичного перечисления не производится ничем

**Исполнителя НЕТ.** Гейта «каждое значение публичного перечисления имеет производителя» в дереве нет. Ближайшее — `internal/reconciler/decide_test.go` :: `TestReasonFor_ClosedVocabulary` (словарь причин) и `TestDecide` (решения сверщика); ни то, ни другое не обходит значения `Volume.Status`.

### STOR-P-28 (positive) `integration` — удаление не теряет ёмкость
**When** `Volume.Delete`
**Then** строка **остаётся** в `DELETING`, пока объект у бэкенда жив
**And** после подтверждения снятия строка удаляется
**And** тест на крах между шагами: строка на месте, объект найден сверщиком

**Исполнитель (частично):** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_DeletionRemovesTheObjectBeforeTheRow`** держит полосу сверщика целиком. **Полосы запроса нет**: `VolumeRepo.Delete` снимает строку немедленно, состояние `DELETING` проба выставляет сырым SQL (план §6.5).

### STOR-P-29 (negative) `integration` — привязанный том не удаляется
**Then** `FAILED_PRECONDITION` `Volume <id> is in use`, объект у бэкенда не тронут

**Исполнитель:** `internal/repo/pg/volume_integration_test.go` :: **`TestVolumeDeleteFKRestrict`** — `FAILED_PRECONDITION` `Volume <id> is in use`.

### STOR-P-30 (positive) `unit` — операция несёт инициатора
**Then** `principalType`/`principalId` строки операции равны вызывающему
**And** фоновый исполнитель читает их для аудита, а к бэкенду идёт под личностью сервиса

**Исполнитель (частично):** `internal/apps/kacho/api/volume/list_operations_owner_test.go` :: **`TestListOperations_ReturnsOnlyCallerOwnRows`** и `internal/handler/operation_ownership_test.go` держат, что операция несёт инициатора и что владение энфорсится на чтении. **Вторая половина без исполнителя**: сверщик строку операции не читает (ноль упоминаний принципала в `internal/reconciler/`), значит «аудит пишет обоих» ничем не проверяется.

---

# F5. Сверка дрейфа

### STOR-P-31 (positive) `integration` — строка есть, объекта нет
**Given** объект снят у бэкенда мимо нас
**Then** сверщик ставит `observed=ABSENT`, статус `ERROR`, `statusReason` заполнен

**Исполнитель:** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_VanishedObjectIsReportedNotRecreated`**.

### STOR-P-32 (positive) `integration` — объект есть, строки нет
**Given** объект с нашим префиксом, которому не соответствует ни одна строка
**Then** счётчик утечки увеличен, запись в журнале называет объект
**And** объект **не удалён**: автоснятия нет by construction

**Исполнитель:** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_LeakScanCountsButNeverDeletes`** — счётчик растёт, объект не удаляется.

### STOR-P-33 (positive) `integration` — расхождение размера выравнивается
**Given** объект меньше желаемого (ресайз не доехал)
**Then** сверщик доводит размер, `observed_size_bytes` сходится

**Исполнитель (частично):** `internal/reconciler/decide_test.go` :: **`TestDecide`** (ветка `ActionResize`) — решение принимается. Схождение `observed_size_bytes` интеграционно не проверяется: в `cycle_integration_test.go` пробы на выравнивание размера нет.

### STOR-P-34 (positive) `unit` — «ноль находок» отличимо от «ноль прочитанного»
**Then** каждый проход печатает число осмотренных строк и число обращений к бэкенду
**And** проба на пустом дереве утверждает **ноль находок при ненулевом осмотре**

**Исполнитель (частично):** Перепись **производится**: `Counters{Scanned, Provision, Resize, Remove, Forget, Leaked}` печатается каждым проходом (`internal/reconciler/loop.go`), и `TestCycle_LeakScanCountsButNeverDeletes` утверждает счётчики. Отдельной пробы «ноль находок при ненулевом осмотре» — на пустом дереве — нет.

### STOR-P-35 (negative) `unit` — недоступность бэкенда не выглядит здоровьем
**Given** бэкенд не отвечает
**Then** `observed_state` переходит в `UNKNOWN`, а **не** остаётся прежним
**And** счётчик недоступности растёт, статус ресурса не объявляется здоровым

**Исполнитель:** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_UnavailableBackendDoesNotCondemnTheResource`** + `internal/blockbackend/blockbackend_test.go` :: `TestObservedState_UnknownIsNotAbsent` + `internal/reconciler/decide_test.go` :: `TestDecide_UnknownNeverActs`.

---

# F6. Снимок

### STOR-P-36 (positive) `integration` — снимок несёт свою зону
**When** снимок снят с тома зоны `a`
**Then** `Snapshot.zoneId == "a"`, поле output-only и неизменяемо

**Исполнитель:** `internal/repo/pg/snapshot_placement_integration_test.go` :: **`TestSnapshotInheritsZoneOfSourceVolume`**.

### STOR-P-37 (negative, РЕГРЕССИЯ КЛАССА) `integration` — восстановление в чужую зону отвергается ПОСЛЕ удаления исходного тома
**Given** снимок из тома зоны `a`, исходный том удалён (`source_volume_id` обнулён)
**When** `Volume.Create{sourceSnapshotId}` в зоне `b`
**Then** `FAILED_PRECONDITION`, зона названа
> Сегодня проверка вырождается в тождественно-истинную: у снимка не остаётся размещения.

**Исполнитель:** `internal/repo/pg/snapshot_placement_integration_test.go` :: **`TestSnapshotKeepsOwnZoneAfterSourceVolumeDeleted`** — ровно тот случай, в котором прежняя проверка вырождалась в тождественно-истинную.

### STOR-P-38 (positive) `newman` — снимок отдаёт `updatedAt` после правки
**Then** `updatedAt` присутствует и больше `createdAt`

**Исполнителя НЕТ.** Кейса нет: в `tests/newman/cases/snapshot.py` нет ни одного утверждения об `updatedAt`. Поле в контракте есть (11), но что оно растёт после правки, не проверяет ни newman, ни Go-проба.

### STOR-P-39 (positive) `newman` — журнал операций снимка
**Then** `GET /storage/v1/snapshots/{id}/operations` отдаёт операции этого снимка

**Исполнитель:** newman `tests/newman/cases/snapshot.py` :: **`SNP-LOP-CRUD-OK`** + `SNP-LOP-NEG-MALFORMED-ID` · `SNP-LOP-BVA-PAGESIZE-OVER-MAX` — журнал операций снимка, отказ по форме id и граница страницы. Заведены `5cec65cd`; на `db7146fb` исполнителя не было.

### STOR-P-40 (positive) `integration` — `usedBy` называет засеянные тома
**Given** два тома засеяны из снимка
**Then** `usedBy` содержит оба
**And** после удаления одного — остаётся один

**Исполнитель:** `internal/repo/pg/snapshot_placement_integration_test.go` :: **`TestSnapshotSeededVolumesAreListed`** + **`TestSnapshotListSeedsWithoutPerRowQuery`** (перечень одним запросом, а не по строке).

### STOR-P-41 (positive) `integration` — `Copy` в другую зону
**When** `Snapshot:copy{targetZoneId}`
**Then** создан **новый** снимок в целевой зоне, исходный не изменён
**And** новый проходит `CREATING → READY` через сверщик

**Исполнитель:** newman `tests/newman/cases/snapshot.py` :: **`SNP-COPY-CRUD-OK`** + пять негативов (`…VAL-PROJECT-REQUIRED` · `…VAL-TARGET-ZONE-REQUIRED` · `…NEG-TARGET-ZONE-UNKNOWN` · `…NEG-MALFORMED-ID` · `…NEG-SOURCE-NOTFOUND`). Заведены `5cec65cd`; на `db7146fb` глагол не вызывался ни одной пробой дерева.

---

# F7. Том: предикаты и снятие ручки

### STOR-P-42 (negative) `гейт` — `blockSize` снят с контракта
**Then** поля нет в публичном сообщении, **номер и имя** зарезервированы
**And** запрос с `blockSize` отвергается как неизвестное поле

**Исполнитель:** обе половины. «Поля нет в ответе» — newman `tests/newman/cases/volume.py` :: **`VOL-CR-CRUD-OK`** (`pm.expect(j).to.not.have.property('blockSize')`); «запрос с `blockSize` отвергается» — newman **`VOL-UPD-MASK-RETIRED-BLOCKSIZE-REJECTED`** (маска со снятым слотом → синхронный 400) и `internal/apps/kacho/api/volume/volume_test.go` :: **`TestUpdateImmutableField`**. Чёрный ящик заведён `5cec65cd`; на `db7146fb` первой половины не держал никто.

### STOR-P-43 (negative) `integration` — засев из неготового источника отвергается
**Given** снимок в `CREATING`
**When** `Volume.Create{sourceSnapshotId}`
**Then** `FAILED_PRECONDITION` `Snapshot <id> is not ready`
**And** зеркальная проба: источник в `READY` — проходит

**Исполнитель:** `internal/repo/pg/snapshot_placement_integration_test.go` :: **`TestSnapshotSeedingRefusedUntilReady`** — с зеркальной пробой готового источника.

### STOR-P-44 (negative) `integration` — то же для образа и для `Image.Create`
**Then** четыре пути источника несут предикат готовности, ни один не пропущен

**Исполнитель:** `internal/repo/pg/image_backend_binding_integration_test.go` :: **`TestImageSourceNotReadyRejected`** и **`TestVolumeSeedFromNotReadyImageRejected`** + `internal/repo/pg/snapshot_integration_test.go` :: `TestSnapshotCreateSourceNotReady`.

### STOR-P-45 (negative) `integration` — ресайз смотрит на состояние
**Given** том в `CREATING` / `ERROR` / `DELETING`
**When** `Update{sizeBytes}` больше текущего
**Then** `FAILED_PRECONDITION`
**And** зеркальная проба: том в `AVAILABLE` — ресайз проходит

**Исполнителя НЕТ.** Предиката состояния при ресайзе в дереве нет: `VolumeRepo.Update` выполняет size-CAS **только** на увеличение и о состоянии строки не спрашивает. Том в `CREATING`/`ERROR`/`DELETING` ресайзится.

### STOR-P-46 (negative) `unit` — размер только вверх
**Then** `INVALID_ARGUMENT` `Volume size can only be increased`

**Исполнитель:** `internal/repo/pg/volume_integration_test.go` :: **`TestVolumeSizeIncreaseOnly`** — точный текст `Volume size can only be increased`, включая конкурентную ветку.

### STOR-P-47 (positive) `integration` — `ChangeDiskType`
**Given** том `AVAILABLE` на классе X, целевой класс Y `ACTIVE` в той же зоне
**When** `:changeDiskType`
**Then** статус `MIGRATING`, по завершении `binding_id` равен активной ревизии Y
**And** `backendObject` перенесён, данные читаются

**Исполнитель:** newman `tests/newman/cases/volume.py` :: **`VOL-CDT-CRUD-OK`** + `VOL-CDT-NEG-MALFORMED-ID` · `VOL-CDT-VAL-DISKTYPE-REQUIRED` · `VOL-CDT-NEG-VOLUME-NOTFOUND` · `VOL-CDT-NEG-DISKTYPE-UNKNOWN`. Заведены `5cec65cd`; на `db7146fb` глагол не вызывался ни одной пробой дерева. Go-пробы у глагола по-прежнему нет — чёрный ящик утверждает исход, но не предикат перехода в `MIGRATING`.

### STOR-P-48 (negative) `unit` — `diskTypeId` не проходит через `Update`
**When** `update_mask` содержит `disk_type_id`
**Then** `INVALID_ARGUMENT` `disk_type_id is immutable after Volume.Create`
**And** сообщение называет глагол, которым это делается

**Исполнитель (частично):** `internal/apps/kacho/api/volume/volume_test.go` :: **`TestUpdateImmutableField`** — `disk_type_id` в маске даёт `INVALID_ARGUMENT` `disk_type_id is immutable after Volume.Create`. Второе утверждение сценария («сообщение называет глагол, которым это делается») **ложно для дерева**: текст глагол не называет.

---

# F8. Привязка тома

### STOR-P-49 (positive) `integration` — привязка по новому первичному ключу
**Then** строка создаётся, статус тома `IN_USE`

**Исполнитель:** `internal/repo/pg/attach_integration_test.go` :: **`TestAttachHappyDerivedInUse`** + `TestAttachIdempotentReplay`.

### STOR-P-50 (negative, CONCURRENCY) `integration` — при `multiAttach: false` проходит одна
**When** две конкурентные `Attach` разных инстансов
**Then** ровно одна успешна, вторая — `Volume <id> is in use`
**And** под `-race`, детерминированно

**Исполнитель:** `internal/repo/pg/attach_integration_test.go` :: **`TestAttachDoubleRace`** — под `-race`, ровно один победитель.

### STOR-P-51 (positive) `integration` — при `multiAttach: true` проходят обе
**Given** класс, чья привязка объявляет множественную привязку
**Then** обе строки созданы, `attachments` содержит две записи

**Исполнителя НЕТ.** Пробы нет: `MultiAttach` в `attach_integration_test.go` не встречается ни разу. Предикат CAS способность читает (`COALESCE(b.cap_multi_attach, false)`), но ветка «объявлена ⇒ проходят обе» не исполняется — то есть проверена только та половина, которая **запрещает**.

### STOR-P-52 (negative) `integration` — три текста, а не один
**Then** несовпадение зоны, несовпадение проекта и занятость дают **три разных** текста
> Переиспользование зонного текста на проектном промахе — вводящий в заблуждение контракт.

**Исполнитель:** `internal/repo/pg/attach_integration_test.go` :: **`TestAttachZoneProjectMismatch`** (два разных текста дословно) + `TestAttachDoubleRace` (третий, `Volume <id> is in use`).

### STOR-P-53 (negative) `unit` — безымянный вызывающий
**Then** `UNAUTHENTICATED`, а не `PERMISSION_DENIED`, на `Attach`/`Detach`/`ListAttachments`

**Исполнитель:** `internal/apps/kacho/api/volume/attach_instance_gate_test.go` :: **`TestAttach_EmptySubjectIsRefusedUnconditionally`** / **`TestDetach_EmptySubjectIsRefusedUnconditionally`** + `list_attachments_visibility_test.go` :: `TestListAttachments_EmptySubjectFailsClosed` и `…EvenWithoutFilter` — все утверждают `Unauthenticated`, а не пустой ответ.

---

# F9. Образ

### STOR-P-54 (positive) `newman` — чистая установка доходит до запуска машины
**Given** пустой каталог и ноль образов
**When** админ регистрирует класс, привязку и образ, затем арендатор создаёт загрузочный том
**Then** том создаётся и доходит до `AVAILABLE`
> Без регистрации образа на чистой установке VM не запускается by construction.

**Исполнитель (частично):** `internal/repo/pg/image_backend_binding_integration_test.go` :: **`TestImageRegisterBornReady`** + newman `tests/newman/cases/image.py` (загрузочный том из образа доходит до готовности). **Сценарий целиком недостижим**: «пустой каталог → админ заводит класс, привязку и образ → арендатор создаёт том» требует административной полосы `:9091`, которой newman не располагает; посев стенда (`make -C deploy seed-storage`) делает это SQL-ом, минуя API.

### STOR-P-55 (negative) `unit` — `Register` только на internal
**Then** метод не резолвится на external mux

**Исполнитель:** `cmd/storage/permission_map_test.go` :: **`TestPublicListenerServesNoInternalService`**. Сверх сценария: `InternalImageService` вообще не объявляет REST-аннотаций, поэтому маршрута нет ни на одном мультиплексоре.

### STOR-P-56 (positive) `integration` — `Copy` образа между регионами
**Then** создан новый образ в целевом регионе, исходный не изменён

**Исполнитель:** newman `tests/newman/cases/image.py` :: **`IMG-COPY-CRUD-OK`** + пять негативов (`…VAL-PROJECT-REQUIRED` · `…VAL-TARGET-REGION-REQUIRED` · `…NEG-TARGET-REGION-UNKNOWN` · `…NEG-MALFORMED-ID` · `…NEG-SOURCE-NOTFOUND`). Заведены `5cec65cd`; на `db7146fb` глагол не вызывался ни одной пробой дерева.

### STOR-P-57 (negative) `integration` — засев тома образом чужого проекта неотличим от промаха
**Then** текст **байт-в-байт** равен настоящему `Image <id> not found`

**Исполнитель:** `internal/repo/pg/volume_image_region_integration_test.go` :: **`TestVolumeSourceImageForeignProjectStaysHidden`** + `image_backend_binding_integration_test.go` :: `TestImageForeignProjectSourceStateStaysHidden` + `volume_image_min_disk_integration_test.go` :: `TestVolumeSourceImageCrossProjectStillHidesMinDisk` — три разные полосы, и все дают байт-в-байт промах.

---

# F10. Адаптер и контрактная суита

### STOR-P-58 (positive) `contract` — одна суита против двух реализаций
**Then** суита исполняется против фейка **и** против Ceph-адаптера
**And** прогон печатает, какая реализация проверялась и сколько случаев исполнено

**Исполнитель (частично):** `internal/blockbackend/fake/fake_test.go` :: **`TestFakeSatisfiesBackendContract`** — 47 случаев, перепись печатается (`Report.WriteCensus`), покрытие глаголов требуется (`assertEveryVerbCovered`). **Против Ceph-адаптера суита не исполняется**: `contract.Run` вызывается в дереве ровно один раз.

### STOR-P-59 (positive) `contract` — идемпотентность каждого глагола
**Then** повтор `create`/`delete`/`resize`/`snapshot`/`clone` с теми же аргументами — успех
**And** повтор `create` с **другим** размером — отказ, а не молчаливое расхождение

**Исполнитель:** `internal/blockbackend/contract/cases.go` — пары «повтор с теми же аргументами → успех» / «повтор с другим размером → конфликт» у `CreateVolume`, `CreateSnapshot`, `CloneVolume`, `CopySnapshot`, `ResizeVolume`, `MigrateVolume`; у Ceph-адаптера те же две ветки — `TestCreateVolume_ExistingWithSameSizeIsSuccess` / `…DifferentSizeIsConflict`.

### STOR-P-60 (negative) `contract` — классификация без корзины «прочее»
**Then** каждый исход бэкенда отображается в объявленную полосу
**And** неизвестный исход даёт **терминальное** «не классифицировано» → фиксированный `INTERNAL`
**And** отказ в правах классифицирован как **не**-временный

**Исполнитель:** `internal/blockbackend/blockbackend_test.go` :: **`TestOutcome_ClosedSetWithoutCatchAll`** и **`TestOutcomeOf_AbsentClassificationIsNotAnAssumption`** + `internal/clients/cephrbd/adapter_test.go` :: **`TestClassify_ClosedSetWithPairedControls`** + `internal/reconciler/decide_test.go` :: **`TestTerminal_OnlyUnavailableRepeats`** (отказ в правах не временный).

### STOR-P-61 (negative) `contract` — дублёр не снисходительнее настоящего
**Then** ввод, который Ceph-адаптер отвергает, фейк отвергает **тем же** кодом
> Иначе дублёр прячет ровно тот дефект, ради которого его подставляют.

**Исполнитель (частично):** `internal/clients/cephrbd/adapter_test.go` :: **`TestValidateRef_NoMoreLenientThanTheDouble`** — точечное равенство на одном срезе ввода. Набором это не утверждается: суита против настоящего адаптера не гоняется (см. STOR-P-58), поэтому INV-P6 держится одной пробой, а не контрактом.

### STOR-P-62 (negative) `unit` — операция не выходит за бюджет
**Then** срок вызова × число повторов **строго меньше** потолка исполнителя операций
**And** гейт роняет сборку при нарушении соотношения

**Исполнителя НЕТ.** Гейта нет. Потолок исполнителя операций — `4 * time.Minute` (`pkg/operations/worker.go`), срок обращения к бэкенду и такт сверщика настраиваются (`BlockBackendCallTimeout`, `BlockBackendReconcileInterval`), но соотношения между ними не проверяет ничто. Сборка при его нарушении не падает.

### STOR-P-63 (negative) `unit` — «не тот эндпоинт» громко
**Given** бэкенд отвечает не тем форматом
**Then** это классифицируется как **настройка**, а не сбой: журнал уровня ошибки, счётчик

**Исполнитель:** `internal/clients/cephrbd/adapter_test.go` :: **`TestObserve_WrongOutputFormatIsMisconfiguration`** и **`TestRun_ToolMissingIsMisconfigurationNotUnavailable`** — обе про то, что настройку нельзя списать на временную недоступность.

---

# F11. Квота и ёмкость

### STOR-P-64 (negative) `integration` — превышение нашей квоты
**Then** `RESOURCE_EXHAUSTED` `storage quota exceeded for project <id>`, объект не создаётся

**Исполнителя НЕТ.** Пробы нет: `quota` в тестах storage не встречается ни разу. Предел энфорсится внутри стейтмента создания (`KACHO_STORAGE_PROJECT_PROVISIONED_BYTES_LIMIT`), но что при его исчерпании приходит `RESOURCE_EXHAUSTED` с назначенным текстом и строка не создаётся, дерево не утверждает.

### STOR-P-65 (negative) `integration` — исчерпание у бэкенда
**Then** `RESOURCE_EXHAUSTED` нейтральным текстом, без имени пула
**And** `statusReason == BACKEND_CAPACITY_EXHAUSTED`

**Исполнитель (частично):** `internal/reconciler/cycle_integration_test.go` :: **`TestCycle_BackendRefusalMarksTheResourceWithANamedReason`** держит `statusReason`. Синхронного `RESOURCE_EXHAUSTED` с нейтральным текстом **не существует** — исчерпание у бэкенда доезжает только состоянием ресурса (план §5.3).

### STOR-P-66 (positive) `integration` — потребление проекта
**Then** `GetProjectUsage` отдаёт провизионированное по нашим строкам
**And** фактическое — только если бэкенд его сообщил; иначе поле **отсутствует**, а не равно нулю

**Исполнителя НЕТ.** `InternalUsageService` / `GetProjectUsage` в дереве отсутствует целиком — ни контракта, ни реализации, ни пробы.

---

# F12. Периметр

### STOR-P-67 (negative) `unit` — новый RPC без записи в каталоге прав
**Given** запись удалена
**Then** вызов даёт отказ (fail-closed), а не проходит

**Исполнитель (частично):** Общий механизм держит край: `gateway/internal/middleware/authz.go` отвечает `PermissionDenied` `catalog: no entry for method`, пробы маршрутизатора — `gateway/internal/middleware/rest_router_test.go`. Со стороны storage полнота каталога держится `cmd/storage/permission_map_test.go` :: **`TestPermissionMapCoversEveryServedRPC`**. Чего нет: пробы, **удаляющей** запись и утверждающей отказ, — то есть сценарий как написан («запись удалена») исполнителя не имеет.

### STOR-P-68 (positive) `гейт` — обе копии каталога прав байт-идентичны
**Then** генерация из proto воспроизводима, гейт дрейфа зелёный

**Исполнитель:** `internal/repohygiene/catalogparity_test.go` :: **`TestCatalogMatchesTheAnnotationsItWasGeneratedFrom`** (генерация из аннотаций воспроизводима) + `catalogreachability_test.go` :: `TestCatalogReachability_EveryRowResolvesToAServedMethod` и `TestCatalogReachability_InertRowsAreExactlyTheAllowedServices`; цель сборки — `make permission-catalog-check`.

### STOR-P-69 (negative) `гейт` — публичная поверхность без инфра-лексики **по значениям**
**Given** в ответ подставлено значение из инфра-словаря
**Then** гейт краснеет и называет поле
**And** зеркальная проба: законное значение из закрытого словаря — гейт молчит
> Сегодняшний гейт читает только **имена** полей.

**Исполнитель:** `internal/protoconv/protoconv_projection_test.go` :: **`TestValueGateGoesRedOnALeak`** (инъекция значения → красное) + **`TestProjectionGateHasItsSubject`** (у гейта есть предмет) + `TestVolumePublicProjectionNoInfra` / `TestSnapshotPublicProjectionNoInfra` / `TestImagePublicProjectionNoInfra`; чёрный ящик — newman `DT-LST-CRUD-OK`.

### STOR-P-70 (negative) `unit` — круг доверенных отправителей непуст
**Given** production-режим и пустой круг
**Then** сервис **отказывается стартовать**, сообщение называет ручку

**Исполнитель:** `cmd/storage/describe_test.go` :: **`TestUnnarrowedForwarderCircleRefusesStart`** + `cmd/storage/trusted_forwarders_test.go` :: `TestListener_NeighbourWithValidCertCannotActAsSomeoneElse`, `TestBootPosture_ReportsWhetherTheCircleIsNarrowed`, `TestTrustedForwarders_MatchesTheCorelibFilter` (guard и транспорт меряют одним предикатом).

### STOR-P-71 (negative) `unit` — страж старта видит новое измерение
**Given** production-режим, бэкенд объявлен, адрес или учётные данные пусты
**Then** отказ в старте, перечень проблем печатается **целиком** за один прогон

**Исполнитель:** `internal/config/blockbackend_guard_test.go` :: **`TestBootGuard_AllProblemsReportedInOneRun`** + шесть пообъектных отказов + `TestBootGuard_DevModeDoesNotRequireBackendKnobs` как положительный контроль.

### STOR-P-72 (negative) `unit` — адрес бэкенда не выводится из чужого
**Then** значение по умолчанию пусто; никакой сборки из адреса соседа

**Исполнитель:** `internal/config/blockbackend_guard_test.go` :: **`TestBootGuard_ProductionWithoutBackend_RefusesToStart`** и `TestBootGuard_BackendWithoutCredentialsDir_RefusesToStart`; умолчания — `internal/config/config_test.go`. Ни одна ручка плоскости данных не собирается из чужого адреса: значения `default:""`.

### STOR-P-73 (negative) `integration` — список сужается по данным
**Then** арендатор без гранта не видит чужих строк
**And** мусорный курсор при пустом гранте даёт `INVALID_ARGUMENT`, а не пустую страницу

**Исполнитель:** `internal/apps/kacho/api/volume/list_filter_test.go` :: **`TestList_PageSizeValidatedBeforeVisibilityShortCircuit`** и **`TestList_PageTokenValidatedBeforeVisibilityShortCircuit`** (порядок — в той же функции, которая замыкается) + `TestList_HidesVolumesWithoutPerObjectGrant`; тот же набор у снимка и образа.

### STOR-P-74 (negative) `integration` — ошибка модели прав не отдаёт страницу
**Then** fail-closed: `UNAVAILABLE`, нефильтрованная страница не отдаётся никогда

**Исполнитель:** `internal/apps/kacho/api/volume/list_filter_test.go` :: **`TestList_FilterErrorIsFailClosed`** + `TestList_AbsentModelIsRefusedNotPassedThrough` + `TestList_NoPrincipalIsRefused`.

### STOR-P-75 (positive) `гейт` — посадка проверяется по живому процессу
**Then** `values.prod` **поднимается** (не только рендерится)
**And** гейт сверяет посадку, объявленную процессом при старте, и шифрование со стороны БД
**And** чарт несёт `checksum/config`, иначе смена посадки не перекатывает под

**Исполнитель (частично):** Гейт посадки существует и **общий для стенда**: `deploy/Makefile` цели `dev-prod-up` → `assert-rollout-ready` + `assert-production-posture` (посадка читается по живому процессу и по шифрованию со стороны БД); чарт storage несёт `checksum/config`. Чего нет **у storage**: прогона `values.prod` с объявленной плоскостью данных — профиль её объявляет (`kind: CEPH_RBD`), а кластера, на котором это поднимется, в наличии нет, поэтому «поднимается» для этого сервиса не проверено ни разу.

---

## Состояние инвариантов-критериев на `db7146fb`

Инварианты §0.3 названы «проверяются, не только сценариями» — значит у каждого обязан быть
свой ответ, а не общая галочка.

| Инвариант | Состояние | Чем установлено |
|---|---|---|
| **INV-P1** ни одного маркера отложенной работы | **держится** | `go test ./internal/repohygiene/ -run TestNoDeferredWorkInTheTree` — прогнан, код возврата 0 |
| **INV-P2** ни одного ломающего изменения после ветки | **держится по построению** | `ChangeDiskType` и оба `Copy` объявлены **сейчас**; PK привязок сменён сейчас; рост Ф1–Ф3 добавляет поля. Цена решения — три глагола без проб (STOR-P-41/47/56) |
| **INV-P3** публичная поверхность без инфра-лексики по значениям | **держится** | `TestValueGateGoesRedOnALeak` + `TestProjectionGateHasItsSubject` + три пообъектные пробы проекции; ярус переведён в закрытое перечисление, прежнее поле снято с номером и именем |
| **INV-P4** authN+authZ на каждом RPC обоих листенеров | **держится** | 41 запись каталога прав домена storage; `TestPermissionMapCoversEveryServedRPC` + `TestPublicListenerServesNoInternalService` |
| **INV-P5** инварианты на DB-уровне, спорный путь — конкурентная проба | **держится** | привязка — `TestAttachDoubleRace`, `TestAttachAutoDeviceNameRace`; ревизия — `TestDiskTypeBindingRegisterConcurrentExactlyOneWins`, `…RaceHoldsUnderAnyInterleaving`; уникальность имени — `Test*NameUniqueRace` на трёх ресурсах |
| **INV-P6** дублёр не снисходительнее настоящего | **НЕ держится набором** | контрактная суита гоняется против одного дублёра; равенство утверждает одна точечная проба `TestValidateRef_NoMoreLenientThanTheDouble` (STOR-P-58/61) |
| **INV-P7** ноль находок отличимо от нуля прочитанного | **держится частично** | сверщик печатает `Counters{Scanned…Leaked}`, контрактная суита — `Report.WriteCensus`; пробы «ноль находок при ненулевом осмотре» нет (STOR-P-34) |

## DoD

- [ ] Все 75 сценариев реализованы тестами и зелёные — **сегодня: 42 с исполнителем, 19
      частично, 14 без исполнителя** (перепись §0.-1). Это и есть точная величина остатка
      по этому пункту, а не «почти всё»
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` · `make audit-list-filter` зелёные
- [ ] newman-суита storage зелёная, отчёт печатает числа (коллекций, запросов, утверждений, упавших, неотвеченных)
- [x] **INV-P1: ни одного маркера отложенной работы в ветке** — гейт прогнан, зелёный
- [x] **INV-P2: ни один пункт роста не требует ломающего изменения** — см. таблицу выше
- [ ] INV-P6 и INV-P7 — см. таблицу выше: первый не держится набором, второй частично
- [ ] Документация сервиса приведена в соответствие (`docs/content/`, `database-schema.ts`)
- [x] **План (`docs/plans/storage-production-api-plan.md`) перечитан**: пометки приведены к
      дереву `db7146fb`, заведён знак `нет` и §12 — перечень недоставленного из 13 пунктов
      с признаком по каждому

> [!note] Почему галочки проставлены не все и это не формальность
> Пункт DoD, отмеченный при невыполненном предмете, — то же «ноль находок вместо ноля
> прочитанного», только в приёмке. Три пункта отмечены потому, что у них есть **прогон или
> перепись**; остальные — нет, и рядом сказано, сколько именно осталось. Пункт про 75
> сценариев не превращён в «сделано частично»: у него теперь есть число, и число это
> проверяемо.
