# Sub-phase XC-1 (машинно-читаемый признак отказа — `google.rpc.ErrorInfo.reason`) — Acceptance

> **Статус:** DRAFT
> **Дата:** 2026-07-27
> **Ревьюер:** `acceptance-reviewer` (единственный approve-gate, ban #1)
> **Эпик/тикет:** KAC-XC-1 (cross-cutting, redesign-2026; снимает `[PHASE-0-GATED]` reason-token из GEO-1 / VPC-1 / COMP-1 / STOR-1 / REG-1 / NLB-1 / IAM-1)
> **Монорепо:** `project/kacho` (`github.com/PRO-Robotech/kacho`), база сверки — `redesign/integration` @ `2e54f0e`
> **Круг ревью:** 4 (круги 1-3 — `CHANGES_REQUESTED`; их правки аннотированы по месту цитатами
> «Исправление круга N»). Все числа §2 пересчитаны **и на `2e54f0e`, и на голове `b892cd8`** —
> команды пересчёта приведены рядом с каждым числом, чтобы ревьюер не сверял на глаз.
> Ветки `redesign/integration` и `base/redesign` указывают на **один и тот же** коммит `b892cd8`
> (`git rev-parse --short redesign/integration base/redesign`), поэтому «база сверки» однозначна.
>
> **Что изменил круг 4 (пять требований ревьюера, каждое закрыто проверкой по коду):**
> (1) **у каждого открытого пункта есть исход.** §9 открывается **реестром исходов**: пункт →
> **номер заведённой задачи** (**#75**, **#76**, **#80**, **#81**) либо прямая пометка «требует
> отдельной задачи — номера в списке нет» → критерий закрытия одной фразой. Вымышленных номеров нет.
> Ключевая пересадка: **O-8/XC-5 — это не новая под-фаза, а часть уже заведённой #75**
> (STOR-AUTHZ-2), потому что чинится ровно тем же переводом каталога storage на `v_get`/Design-B.
> (2) **перепроверен каждый механизм защиты** (§2.8 — таблица «утверждение → команда → наблюдённый
> вывод»). Два утверждения оказались **неверны** и переписаны под действующий механизм:
> наблюдаемость (D9: storage **объявляет** `/metrics`, а раздаёт **только** `/healthz` — #76в) и
> `domain` шлюза (**четыре** сайта, включая две REST-JSON-ветки, а не один). Остальные
> (hide-existence-таблица, направление дрейф-гейта, 22 достижимых типа, пять паритетных и пять
> непаритетных сайтов, BOLA-guard, гейт `AttachDisk`) — подтверждены дословно.
> (3) **критерии наблюдаемы**: назван прогон, набор и «сколько из скольки»; вердикт newman читается
> из `out/<stem>.json` → `.run.stats.assertions.failed`, а не из строки «GREEN».
> (4) **команды гейтов исполнены из корня, а не процитированы.** `permission-catalog-check` /
> `rest-route-table-check` в дереве workspace падают без `GOWORK=off`; `audit-list-filter` у
> **registry — echo-заглушка** (цель есть, скрипта нет, всегда `0`), а CI перебирает **4** сервиса.
> Названы артефакты, которые наблюдают на самом деле.
> (5) **id сценариев не образуют третьего пространства имён.** §7.4 переписан: каждый `XC-1-NN`
> обязан назвать **якорь** — либо уже принятый id владельца, с которого он снимает
> `[PHASE-0-GATED]` (`GEO-1-34/35`, `VPC-1-03/04/05/35/41`, `NLB-1-11`, `REG-1-16/31/34`,
> `STOR-1-05/11`, `COMP-1-22`), либо существующий тест/кейс, который он расширяет. Id без якоря —
> не сценарий XC-1.
> **Порядок работы (слои монорепо):** `pkg/` (corelib) → `services/<owner>` → `services/<consumer>` → `gateway/` → `deploy/` → `docs/` + vault
> **Формат:** Given-When-Then (только markdown — без кода)
> **Нормативка (не дублируется в тело — ссылки):**
> - `.claude/rules/api-conventions.md` — **by-lane code-split + таблица reason-token** (нормативно, §Error-format), error-тон, async `Operation`.
> - `.claude/rules/security.md` — hardening-инварианты **#1** (INTERNAL без leak), **#5** (комментарий = ловушка), **#6** (hide-existence byte-identical), **#7** (format-validate до authz); §публичные артефакты.
> - `.claude/rules/data-integrity.md` — cross-domain peer-validate fail-closed, «межсервисное намерение — контракт принимающей стороны».
> - `.claude/rules/testing.md` — TDD RED-до-кода, regression **на уровне обсервабла**, integration + newman в том же PR.
> - `.claude/rules/architecture.md` — dependency rule, LEAN, doc-truthfulness.
> - `00-kacho-core.md` — ban #11 (без тех-долга), **ban #14** (production-grade, никогда MVP), ban #12 (TDD).

---

## 1. Обзор и цель

`api-conventions.md` §Error-format предписывает: **клиент машинно различает полосы отказа по
`reason`-токену в `google.rpc.Status.details` (`google.rpc.ErrorInfo.reason`), а НЕ разбором прозы
сообщения.** Проза объявлена стабильной, но непарсибельной.

**Токена нет ни в одном прод-файле ни одного из семи сервисов.** Под-фаза XC-1 закрывает разрыв:
вводит единственный corelib-помощник, закрытый словарь из пяти токенов, `domain` + `metadata`
(`resource_type` — из нового единого набора `pkg/restype`, D4), и раскатывает их по всей поверхности
резолва идентификаторов — **аддитивно**: код ответа и текст сообщения остаются байт-в-байт прежними,
токен **добавляется** в `details`.

Аддитивность имеет **ровно одно поимённое исключение из шести позиций** (D6): пять peer-сайтов, где
«нет доступа» и «нет объекта» сегодня различимы наблюдателем, плюс текст ветки недоступности на
семи файлах vpc, куда интерполируется сырая ошибка соседа. Это не смягчение принципа, а его
условие: сценарий XC-1-16 **утверждает** неразличимость, а по коду (§2.7) она держится лишь на
половине сайтов — утверждать её поверх живого оракула значило бы ввести «проверку с формой без
содержания». Исключение закрыто списком, проверяется по именам сайтов и не растёт.

Цель формулируется от клиента: **после XC-1 у клиента (UI, SDK, оркестратор, e2e) есть решающая
процедура над отказом, не зависящая ни от текста, ни от сервиса, ни от формы доставки** (синхронный
ответ или `Operation.result.error`). До XC-1 такой процедуры нет — и, как показано в §2.4, её нельзя
построить даже по коду ответа, потому что одна и та же полоса возвращает **три разных кода** в
разных сервисах.

---

## 2. Проверка проблемы по коду (ground-truth, `2e54f0e`)

Проверено grep/чтением исходников, а не по существующим докам (доки успели устареть — см. §2.6).

### 2.1 Токена нет

- `grep -rn "ErrorInfo" --include=*.go` по всему дереву → **10 попаданий, все в `gateway/`**:
  `gateway/internal/middleware/permission_denied_response.go` (`AUTHZ_DENIED`, `AUTHN_REQUIRED`) и
  один тест. В `services/**` — **ноль**.
- `grep -rn "RESOURCE_NOT_FOUND\|PEER_RESOURCE_MISSING\|PEER_RESOURCE_STATE\|PEER_UNAVAILABLE\|INVALID_RESOURCE_ID"`
  → **7 попаданий, все в комментариях/названиях тестов** (`services/registry/internal/clients/geo/region_client.go:90`,
  `services/registry/internal/apps/kacho/api/registry/create.go:71,166,167` и три теста). Ни одного
  места, где токен попадал бы на wire.
- `pkg/errors/errors.go` (97 строк) умеет `BadRequest.FieldViolation`, `ResourceInfo`,
  `LocalizedMessage` — **`ErrorInfo` не поддерживает вовсе**.
- `pkg/validate/validate.go:473` — `ResourceID` возвращает голый
  `status.Errorf(codes.InvalidArgument, "invalid %s id '%s'", …)` без деталей.

Итого: заявление задачи подтверждено. Дополнительно подтверждено собственной записью проекта —
`docs/plans/kacho-redesign-2026/integration-status.md` §Cross-cutting deferred.

### 2.2 Транспорт для деталей уже есть — доработки не требуют ни схемы, ни proto

| Путь | Факт (файл) | Вывод |
|---|---|---|
| gRPC sync | `status.WithDetails` уже используется (`pkg/errors/errors.go:48`) | готово |
| REST sync | mux собирается **без** `runtime.WithErrorHandler` (`gateway/internal/restmux/mux.go:328-337`) ⇒ работает `DefaultHTTPErrorHandler`, который маршалит **весь** `s.Proto()`, включая `details`, через `runtime.JSONPb` | готово |
| async `Operation` | `proto/kacho/cloud/operation/operation.proto:55` — `google.rpc.Status error = 8` (несёт `details`) | готово |
| async persist | `pkg/operations/repo.go:154,182-195` — `marshalStatus` кладёт `proto.Marshal(Status)` в колонку `error_details BYTEA` (`pkg/migrations/common/0001_operations.sql:18`), `scanOperation` (`repo.go:624-628`) восстанавливает `op.Error.Details` | готово |
| async capture | `pkg/operations/worker.go:509,649` — `status.FromError(err)` сохраняет детали, если ошибка уже `*status.Status`; не-status/panic заменяется фиксированным INTERNAL | готово |

**Следствие:** XC-1 — изменение *только* прикладного слоя. Ни новой миграции, ни правки
`operation.proto`, ни `buf breaking`. Это ключевая причина, по которой под-фаза дешёвая и безопасная.

### 2.3 Точек эмиссии много, единого места нет

`status.Error*` в `services/**` (без тестов) — **906**: compute 146, geo 17, iam 255, nlb 161,
registry 27, storage 29, vpc 271.

> Круг 1 приводил 910 (iam 256, nlb 162, vpc 273) — **числа были неверны, исправлено по коду**.
> Пересчёт (идентичен на `2e54f0e` и на `b892cd8`):
> `git grep -hoE "status\.Error(f)?\(" <ref> -- "services/**/*.go" ":(exclude)services/**/*_test.go" | wc -l` → `906`.

Из них полосу резолва идентификатора образует небольшое подмножество, но **эмиттеры формата id уже
расползлись на шесть независимых реализаций**:

| Реализация | Где | Форма |
|---|---|---|
| `pkg/validate.ResourceID` | compute **15**, vpc **51**, nlb **7**, registry **2** | `error`, построенная `status.Errorf` в **точке эмиссии** (`pkg/validate/validate.go:473`) |
| `iam/internal/apps/kacho/shared.ValidateResourceID` | `services/iam/internal/apps/kacho/shared/ids.go:31` | `error`, построенная `status.Errorf` в **точке эмиссии** |
| `geo/internal/domain.ValidateID` | объявлена в `services/geo/internal/domain/geo.go:45`; вызовы — в **другом пакете**: `services/geo/internal/apps/kacho/api/region/region.go:119,127,148,190,261` и `…/api/zone/zone.go:123,131,152,198,276` | доменная ошибка → маппер |
| `vpc/internal/repo/helpers/unique.go:185` | vpc repo | `fmt.Errorf("%w: invalid %s id '%s'", ErrInvalidArg, …)` |
| `nlb/internal/repo/kacho/pg/errors.go:104` | nlb repo | то же |
| `storage/internal/service/image/image.go:156` | storage | то же |

> Круг 1 приводил `pkg/validate.ResourceID`: compute 17, vpc 59, nlb 9 — **неверно, исправлено по коду**
> (`git grep -n "corevalidate\.ResourceID(" <ref> -- "services/<svc>/**/*.go" | grep -v _test.go | wc -l`
> → 15 / 51 / 7 / 2 на обоих ref'ах). Круг 1 также указывал `region.go:119,127,148,190` как файл
> объявления `domain.ValidateID` — **файла `services/geo/internal/domain/region.go` в дереве нет**;
> смешаны пакет объявления (`internal/domain/geo.go`) и файл вызова (`internal/apps/kacho/api/region/region.go`).
> Структурный вывод от этого не меняется, но §2 позиционируется как сверенная по коду, поэтому цитата
> приведена к реальности.

geo / iam / storage **не вызывают** `pkg/validate.ResourceID` вообще (0 / 0 / 0). Значит «повесить
токен в corelib-валидаторе» покрывает лишь 4 сервиса из 7 — расползание уже случилось, и XC-1 обязан
его свести, иначе полоса будет частичной (см. D2).

> **Исправление круга 2 (фактическое замечание №3).** Круг 2 писал в этой таблице «возвращает
> `*status.Status`» про обе реализации — **неверно**: обе возвращают `error`, построенную
> `status.Errorf` (`pkg/validate/validate.go:473`; `services/iam/internal/apps/kacho/shared/ids.go:31`).
> Структурное различие, на которое опирается D3, от этого **не меняется** и даже становится точнее:
> значимо не то, какой Go-тип возвращается, а **где собран статус** — в точке эмиссии (эти две
> реализации) или позже в маппере, уже потерявшем знание о ресурсе (три sentinel-реализации ниже).
> Именно поэтому D3 требует **двух** выходов помощника, а не одного.

**Отдельный структурный факт:** три из шести реализаций возвращают **sentinel-обёрнутую ошибку**, а
`*status.Status` собирается позже в маппере (`serviceerr.MapRepoErr`, `compute/service/maperr.go`,
`nlb/api/shared/errmap.go`, `registry/api/registry/mapping.go`). Детали `*status.Status` **не
переживают** `fmt.Errorf("%w: …")` — маппер строит статус заново и о ресурсе ничего не знает
(`MapRepoErr(err error) error` — единственный аргумент). Отсюда требование к помощнику: не только
конструктор статуса, но и **типизированный носитель**, который проходит сквозь sentinel-слои и
читается маппером (D3).

### 2.4 Главный аргумент: код ответа сегодня НЕ является дискриминатором полосы

Сверка по коду, одна и та же полоса — **peer-validate miss** (чужой id не резолвится у владельца):

| # | Consumer | Чужой ресурс | Владелец | Код сейчас (файл:строка) | Канон | Файлов |
|---|---|---|---|---|---|---|
| 1 | compute | `Subnet` | vpc | `FAILED_PRECONDITION` (`service/instance.go:1043-1047`, `mapSubnetRefErr`) | ✅ совпадает | — |
| 2 | registry | `region` | geo | `FAILED_PRECONDITION` (`api/registry/create.go:171`) | ✅ совпадает | — |
| 3 | compute | `Zone` | geo | **`INVALID_ARGUMENT`** (`service/maperr.go:93,96`) | ✗ | 1 |
| 4 | compute | `Project` | iam | **`NOT_FOUND`** (`service/project_check.go:34`) | ✗ | 1 |
| 5 | compute | `Volume` | **storage** | **`NOT_FOUND`** (`clients/storage_client.go:205-207` — код владельца пробрасывается дословно) | ✗ | 1 |
| 6 | vpc | `Project` | iam | **`NOT_FOUND`** × **7** (`api/{address:449,gateway:122,network:221,networkinterface:155,routetable:161,securitygroup:179,subnet:205}/create.go`) | ✗ | 7 |
| 7 | nlb | `Instance` | compute | **`INVALID_ARGUMENT`** (`clients/compute/instance_client.go:151,153` → `domain.ErrInvalidArg`) | ✗ | 1 |
| 8 | nlb | `Region` | geo | **`INVALID_ARGUMENT`** (`clients/geo/region_client.go:129,132`) | ✗ | 1 |
| 9 | nlb | `Project` | iam | **`NOT_FOUND`** (`clients/iam/project_client.go:139-140` → `domain.ErrNotFound`) | ✗ | 1 |
| 10 | registry | `project` | iam | **`INVALID_ARGUMENT`** (`api/registry/create.go:156`) | ✗ | 1 |

**Кардинальность (нормативна — от неё зависит стартовый состав храповика §7.3):** строк — **10**;
совпадают с каноном — **2** (№1, №2); off-lane — **8 полос**, которым соответствуют **14 файлов**
(№6 — семь файлов, остальные семь полос — по одному). Оба числа приводятся явно, потому что храповик
считается **по файлам** (решение Q3, §10), а «список не растёт» (XC-1-40) проверяется по файловым
строкам.

> **Исправление круга 1 (блокирующее №3 и №4).** В круге 1 таблица содержала девять строк, из них
> семь `✗`, а §7.3 и O-1 при этом говорили «восемь сайтов» — расхождение. Причина расхождения — не
> арифметика: **отсутствовало ребро `compute → storage`** (строка №5). Оно объявлено несущим в
> `polyrepo.md`, живо в коде (`services/compute/internal/clients/storage_client.go`, per-call deadline
> 5 c, `auth.PropagateOutgoing`, wired в composition root), достижимо с публичного края
> (`POST /compute/v1/instances/{instance_id}:attachDisk`) и off-lane по коду. Оно же перечислено в
> собственном DoD S4 этого документа — то есть документ противоречил сам себе. После внесения строки
> off-lane-полос ровно **восемь**, и число в §7.3/O-1 сходится с таблицей не по совпадению, а по счёту.

**Одна полоса — три разных кода (`INVALID_ARGUMENT`, `NOT_FOUND`, `FAILED_PRECONDITION`) в шести
сервисах.** Клиент физически не может ключеваться на код: `404` на `Network.Create` означает и «моей
сети нет» (vpc, своя полоса), и «чужого проекта нет» (vpc→iam, чужая полоса) — разная реакция
(проверь свой id vs. проверь права/область vs. повтори позже), одинаковый код.

**Отдельно про строку №5 (`compute → storage`).** `mapStorageErr`
(`services/compute/internal/clients/storage_client.go:196-212`) пробрасывает **код и сообщение
владельца дословно** для набора `{InvalidArgument, FailedPrecondition, NotFound, AlreadyExists,
PermissionDenied}`. Для полосы это значит две вещи сразу: (а) peer-miss выходит наружу как `NOT_FOUND`
вместо канонического `FAILED_PRECONDITION` — обычный off-lane, строка храповика; (б) в тот же
whitelist попал `PermissionDenied`, и он выходит наружу как `PERMISSION_DENIED` — полоса, которой
пятитокенный словарь **не выражает вовсе**. Второе — не off-lane, а дефект безопасности; он разбирается
в §2.7 и закрывается D12, а не откладывается в XC-2.

Это переворачивает приоритет: токен — **не украшение поверх работающего разделения**, а
единственное, что делает разделение выразимым, не ломая коды. Из этого прямо следует D6.

### 2.5 Риск, который XC-1 обязан снять на своём же пути: токен как existence-oracle

`gateway/internal/middleware/permission_denied_response.go:113-124` (`buildGRPCNotFoundStatus` с
godoc), `:168-208` (`notFoundMessage` с godoc): 404 отдаётся **без единой детали**, а текст берётся
из таблицы `hideExistenceNotFoundFormats` (`:153-185` — **21 запись**: iam 6, compute 4, vpc 7,
nlb 3, registry 1; круг 1 говорил «24 типа» — **число было неверно, исправлено по коду**),
скопированной **дословно** из repo-слоёв владельцев — ровно чтобы «нет доступа» было
байт-неотличимо от «не существует» (hardening-инвариант #6). Таблица защищена дрейф-гейтом
`TestHideExistenceMap_CoversCatalogReachableTypes`.

> **Исправление круга 2 (фактическое замечание №4, якоря строк).** Круг 2 указывал `:115-135` для
> `buildGRPCNotFoundStatus` — функция вместе с godoc занимает **113-124**; и `:98-101` для пропуска
> `deny_reasons` — комментарий занимает **99-100**. Приведено к дереву.

**Направление гейта — только «достижим ⇒ отображён» (нормативно, из него следует блокирующий вывод
§2.7).** `TestHideExistenceMap_CoversCatalogReachableTypes`
(`permission_denied_notfound_oracle_test.go:139-186`) выводит из **встроенного** каталога множество
типов, для которых `CatalogEntry.HidesExistenceOnDeny(FQN)` истинна, и падает, если тип не отображён
в таблице (или не объявлен в `hideExistenceNoBackendTypes`). Обратное направление — «строка есть,
тип недостижим» — гейтом **не проверяется вовсе**. Сегодня достижимых типов **22**, отображённых —
**21**, плюс один объявлен как «нет реализации владельца» (`compute_instance_group`). Ни одного
storage-типа среди достижимых **нет** — и это ровно причина, по которой строка шлюза для storage
была бы мёртвым кодом (см. §2.7 и DoD S3).

Если владелец начнёт класть `ErrorInfo` в настоящий miss, а gateway на deny — нет, то **наличие
детали само становится оракулом**. Прямое следствие: паритет деталей — обязательная часть XC-1, а
не «потом» (D8). Проверено, что hide-existence применяется и к мутациям
(`authz_registry_mutation_hide_existence_test.go` — `RegistryService.Update/Delete`).

Дополнительный факт, влияющий на форму: miss может приходить **синхронно**, а не только в
`op.error`. `services/vpc/internal/apps/kacho/api/subnet/create.go:129-136` — pre-flight
`rd.Networks().Get` в **request-path**, `NOT_FOUND "Network %s not found"` (`:133`) возвращается
синхронно; там же (комментарий `:117-122`) `Project` намеренно проверяется **асинхронно** — его
`NOT_FOUND` живёт в `doCreate` (`:200-205`) и приходит в `op.error`. Значит один RPC отдаёт две
полосы двумя разными формами доставки — токен обязан быть идентичным в обеих (сценарий XC-1-12).

### 2.6 Дрейф существующих документов (доки устарели — исправляется в DoD)

- **Девять** acceptance-доков (не семь — круг 1 ошибся; пересчёт
  `grep -rln "PHASE-0-GATED" docs/specs/` даёт 10 файлов, минус сам XC-1) ссылаются на reason-token как
  `[PHASE-0-GATED]`: `sub-phase-GEO-1-region-zone-redesign`, `sub-phase-VPC-1-network-subnet`,
  `sub-phase-COMP-1-instance-machinetype`, `sub-phase-STOR-1-volume-image`,
  `sub-phase-IAM-1-tenancy-authz-core`, `sub-phase-NLB-1-lb-listener-targetgroup`,
  `sub-phase-NLB-1b-loadbalancer-listener-core`, `sub-phase-REG-1-namespace-repository`,
  `sub-phase-REG-1-registry-repository`. Они называют **ад-хок
  токены под ресурс**: `REGION_NOT_FOUND` (GEO-1-34/35, REG-1, NLB-1), `NETWORK_NOT_FOUND` (VPC-1-41),
  `NAMESPACE_NOT_FOUND` (REG-1), `PROJECT_NOT_FOUND` (NLB-1). Приземлившаяся конвенция фиксирует
  **закрытый набор из пяти** токенов полосы; специфика ресурса уходит в `metadata.resource_type`.
  Эти строки — устаревшие, XC-1 их перенаправляет (см. DoD, пункт «сверка доков»).
- Те же доки называют токены, которые **не являются полосой вовсе**: `ZONE_NOT_OPEN`,
  `CAPACITY_UNAVAILABLE` (GEO-1-05), `NAMESPACE_NAME_IS_GLOBAL` (REG-1-16), `ROLE_DOES_NOT_COVER_TYPE`
  (IAM-1-24/25). Это доменные предусловия — **другая ось**, явный Out-of-scope (§9, O-2).
- `api-conventions.md` утверждает, что consumer «на geo-miss маппит в `PEER_RESOURCE_MISSING`/
  `FAILED_PRECONDITION`». По коду (§2.4) это **не так** у compute и nlb. Конвенция описывает цель, а
  не реальность — расхождение фиксируется явно (D6, ratchet §7.3), а не замалчивается.
- Gateway использует `domain = "kacho.cloud.iam.v1"` (proto-пакет), конвенция предписывает
  `<service>.kacho.cloud`. Расхождение реально и живёт на **четырёх** сайтах одного файла
  `gateway/internal/middleware/permission_denied_response.go`: `:93` (`AUTHZ_DENIED`, gRPC),
  `:242` (`AUTHN_REQUIRED`, gRPC) и **две REST-JSON-ветки** `:273` / `:320`, где та же строка
  собирается литералом в map, а не берётся из константы.
  > **Исправление круга 4 (фактическая ошибка круга 3).** Круг 3 писал про эту строку в
  > единственном числе («его `domain` нормализуется»), что превращало S5 в однострочную правку и
  > **гарантированно оставляло бы REST-проекцию расходящейся с gRPC** — ровно тот класс, который
  > XC-1-22/23 обязан ловить (символ-в-символ между проекциями). Пересчёт:
  > `git grep -c '"kacho.cloud.iam.v1"' -- gateway/internal/middleware/permission_denied_response.go`
  > → **4**. Вывод «нормализуется в S5» не меняется, объём — меняется: четыре сайта + вынос в
  > единственную константу, иначе пятый сайт разъедется снова.
  Проверено отдельно, что **ни один тест и ни один newman-кейс на значение `domain` не опирается**:
  `git grep -rn '"kacho.cloud.iam.v1"' -- 'gateway/**/*_test.go' 'services/*/tests/newman/**'` даёт
  только FQN-литералы методов (`…AccountService/Create`) и proto-пакеты в фикстурах генератора, ни
  одного assert'а поля `domain`; newman-хелпер `services/iam/tests/newman/scripts/gen.py:199-200,
  252-253` утверждает **наличие** `ErrorInfo` и его `reason`/`metadata`, но не `domain`. Поэтому
  нормализация в S5 — безопасна (D5).

### 2.7 Паритет deny↔miss на peer-границе: пять сайтов держат, пять — нет

Круг 1 утверждал в XC-1-16 свойство безопасности («владелец ответил `PERMISSION_DENIED` → наружу
`PEER_RESOURCE_MISSING`, как и на настоящий промах; authz-факт владельца наружу не течёт») **как
общее**, опираясь на один процитированный сайт. Свойство проверено на **всех** peer-клиентах дерева.
Оно держится на пяти сайтах из десяти. На остальных пяти «нет доступа» и «нет объекта» **различимы
наблюдателем** — то есть XC-1-16, как он был написан, декларировал бы защиту поверх живого оракула.
Это ровно класс «проверка с формой без содержания», и он закрывается здесь, а не «отмечается».

| Consumer → владелец | miss (нет объекта) | deny (`PERMISSION_DENIED` от владельца) | различимо? |
|---|---|---|---|
| compute → vpc `Subnet` (`clients/vpc_subnet_client.go:66-69` → `service/instance.go:1045`) | `FAILED_PRECONDITION` | `FAILED_PRECONDITION`, тот же текст | ✅ нет |
| registry → geo `region` (`clients/geo/region_client.go:88-91`) | `FAILED_PRECONDITION` | `FAILED_PRECONDITION`, тот же текст | ✅ нет |
| registry → iam `project` (`clients/iam/iam_client.go:89`) | `INVALID_ARGUMENT` | `INVALID_ARGUMENT`, тот же текст | ✅ нет |
| nlb → compute `Instance` (`clients/compute/instance_client.go:150-153`) | `INVALID_ARGUMENT` | `INVALID_ARGUMENT`, тот же текст | ✅ нет |
| nlb → geo `Region` (`clients/geo/region_client.go:127-132`) | `INVALID_ARGUMENT` | `INVALID_ARGUMENT`, тот же текст | ✅ нет |
| **compute → storage `Volume`** (`clients/storage_client.go:205-207`) | `NOT_FOUND` | **`PERMISSION_DENIED` + сообщение владельца дословно** | ❌ **ДА** |
| **nlb → iam `Project`** (`clients/iam/project_client.go:139-146`) | `NOT_FOUND` (404) | **`FAILED_PRECONDITION` (400)**, текст тот же | ❌ **ДА** |
| **vpc → iam `Project`** (`clients/iam_client.go:53-58`) | `NOT_FOUND` (404) | **`UNAVAILABLE` (503) + сырой peer-текст** (`api/*/create.go` → `status.Errorf(codes.Unavailable, "project check: %v", err)`) | ❌ **ДА** |
| **compute → iam `Project`** (`clients/iam_client.go:120` → `service/project_check.go:31,34`) | `NOT_FOUND` (404) | **`UNAVAILABLE` (503)** | ❌ **ДА** |
| **compute → geo `Zone`** (`clients/geo_client.go:75-78` → `service/maperr.go:93,101`) | `INVALID_ARGUMENT` (400) | **`UNAVAILABLE` (503)** | ❌ **ДА** |

**Механика расхождения одна и та же на всех пяти:** клиент-адаптер сводит в «ссылка не резолвится»
**только** `NotFound` (иногда + `InvalidArgument`), а `PermissionDenied` проваливается в
`default`-ветку и уезжает либо как транспортная недоступность, либо (compute→storage) дословно.
Пять сайтов, которые держат паритет, отличаются ровно одной строкой — `PermissionDenied` включён в
тот же `case`, что `NotFound`.

**Три следствия, каждое самостоятельное:**

1. **Existence-oracle.** Наблюдатель отличает «объект есть, но не мой» от «объекта нет». Практически
   достижимо **с публичного края** на `compute → storage`: `AttachDisk` авторизуется шлюзом по
   **инстансу** (`proto/kacho/cloud/compute/v1/instance_service.proto:197-202` — permission
   `compute.instance_disks.attachDisk`, `required_relation = v_update`, scope на `instance_id`), а
   `volume_id` шлюзом **не** скоупится — единственный гейт по тому обращается на стороне storage
   (`proto/kacho/cloud/storage/v1/internal_volume_service.proto:33-38` — `required_relation = editor`,
   `scope_extractor {object_type: storage_volume, from_request_field: volume_id}`), и его
   `PERMISSION_DENIED` compute пробрасывает наружу дословно
   (`clients/storage_client.go:205-207`). Значит владелец инстанса перебором `volumeId` отличает
   `403` (том есть, не мой) от `404` (тома нет) **внутри одного и того же RPC**.

   > **Блокирующее исправление круга 2 (заявлена защита, которой нет).** Круг 2 писал здесь и в
   > XC-1-43, что «прямой `Volume.Get` того же тома шлюз прячет под `404`
   > (`hideExistenceNotFoundFormats`)», и выводил отсюда, что оракул — это **обход** купленного
   > скрытия через чужой RPC. **По коду это ложно, проверено тремя независимыми фактами:**
   > (а) в `gateway/internal/middleware/permission_denied_response.go:153-185` **нет ни одной**
   > storage-строки — 21 запись покрывает только iam/compute/vpc/nlb/registry;
   > (б) в `gateway/internal/middleware/embed/permission_catalog.json` у
   > `kacho.cloud.storage.v1.VolumeService/Get` стоит `required_relation: "viewer"` (не `v_get`) и
   > отсутствует `hide_existence`, поэтому `CatalogEntry.HidesExistenceOnDeny`
   > (`permission_catalog.go:149-153`: явный флаг **ИЛИ** `/Get` + `v_get` + конкретный scope)
   > возвращает **false**; то же у `SnapshotService/Get` и `ImageService/Get`;
   > (в) множество достижимых типов, выводимое дрейф-гейтом, содержит **22** типа и **ни одного**
   > storage.
   > **Реальность:** denied прямой `GET /storage/v1/volumes/{id}` отдаёт `403 PERMISSION_DENIED`, а
   > настоящий промах — `404 "Volume <id> not found"`
   > (`services/storage/internal/repo/pg/errmap.go:62`). То есть **прямой путь сам является
   > оракулом**, а не эталоном скрытия. Отсюда два раздельных вывода, и их нельзя смешивать:
   > - **внутри XC-1** формулировка паритета для `AttachDisk` — «deny ≡ miss **внутри самого
   >   AttachDisk**» (сравниваются два ответа одного и того же RPC), **без** какой-либо ссылки на
   >   прямой `Volume.Get` как на эталон. Это исполнимо и до, и после исправления прямого пути,
   >   потому что не зависит от него. Переписано в XC-1-43;
   > - **исход прямого пути** — он не «отмечен», а вынесен в **уже заведённую задачу #75** (STOR-AUTHZ-2; «XC-5» — имя среза внутри неё) с
   >   критерием приёмки (§9, O-8). Причина выноса не в объёме, а в радиусе: `required_relation`
   >   живёт в **proto-аннотации** (`proto/kacho/cloud/storage/v1/volume_service.proto:26`), из
   >   которой каталог **генерируется** (`gateway/Makefile:49` `gen-permission-catalog.sh`), поэтому
   >   исправление меняет наблюдаемый код ответа `403 → 404` на публичной поверхности трёх
   >   ресурсов, требует byte-identical регенерации **обеих** встроенных копий каталога (iam-seed и
   >   middleware шлюза, гейт `permission-catalog-check`) и переразметки storage-суиты, где сегодня
   >   **51** строка упоминает `403`
   >   (`grep -rn 403 services/storage/tests/newman/cases/*.py | wc -l`). Это тот же набор строк
   >   каталога, который правит уже открытая
   >   задача **#75** STOR-AUTHZ-2 (`viewer` → Design-B), поэтому срез исполняется внутри неё, а не
   >   параллельно ей.
   >
   > **Что XC-1 при этом всё-таки закрывает на storage-ребре:** `PERMISSION_DENIED` перестаёт
   > пересекать границу сервиса (D12, правило 2) — то есть перебор `volumeId` через **compute**
   > больше не различает две ситуации, даже пока прямой storage-путь их различает. Оракул сужается
   > с двух поверхностей до одной и получает названный срок закрытия.

   На четырёх project/zone-полосах достижимость **уже, но не нулевая**: обычно шлюз отвергает запрос
   по project-scope раньше, чем consumer дойдёт до peer-вызова; не отвергает — на internal-листенере
   `:9091` (шлюза перед ним нет) и на путях, где грант позволяет `v_create` в consumer-домене без
   `v_get` на сам проект. По `compute → geo Zone` deny сегодня почти недостижим по другой причине —
   read-RPC geo объявлены project-scope EXEMPT (`security.md`, задокументированное исключение); это
   **латентная**, а не отсутствующая дыра: она становится достижимой в тот день, когда исключение
   сузят. Латентность — довод чинить сейчас, а не довод отложить.
2. **Ложная retryability.** `UNAVAILABLE` на отказ по правам говорит клиенту «повтори позже» про
   условие, которое повтором не изменится. Клиент с бэкоффом будет долбить владельца до исчерпания
   бюджета — стоимость на стороне iam/geo, ноль шансов на успех.
3. **Комментарий, описывающий несуществующий механизм защиты** (`security.md` инвариант #5 —
   прямо запрещённый класс). `services/nlb/internal/clients/iam/project_client.go:142-144`:
   «Не лик'аем разницу: tenant видит "не существует" и для NotFound, и для denied (existence-hiding…)»
   — и **следующей же строкой** объясняет, что код намеренно разный ради удобства handler-слоя.
   То есть утверждение о неразличимости верно только для текста и опровергается кодом ответа,
   который тенант видит как `400` против `404`. Тот же комментарий-обещание продублирован в
   godoc порта (`:41-48`). Внутреннее удобство слоя вынесено на публичную поверхность.
   Симметрично `services/vpc/internal/clients/iam_client.go:56-61`: комментарий подробно объясняет,
   что `InvalidArgument` **нельзя** пробрасывать ошибкой, иначе наружу уедет `"project check: rpc
   error: code = Inval…"`; `PermissionDenied` под то же рассуждение подпадает полностью, но в
   `case` не включён — и наружу уезжает ровно тот текст, которого комментарий велит избегать
   (это одновременно и hardening-инвариант **#1**: сырой peer-текст в сообщении).

**Что из этого делает XC-1** — D12. Коротко: пять сайтов приводятся к паритету (deny сводится в ту же
ветку, что miss, **того же** сайта), пять паритетных остаются нетронутыми, а `PERMISSION_DENIED`
как сквозной код на peer-границе запрещается отдельным правилом. Полоса `PERMISSION_DENIED` в
пятитокенный словарь **не добавляется** — словарь закрыт (D2); она **устраняется** как полоса.

### 2.8 Перепроверка механизмов защиты (круг 4): утверждение → команда → наблюдённый вывод

Прошлые круги **дважды** описали механизм, которого в коде нет (круг 2 — «прямой `Volume.Get`
прячет существование»; круг 3 — «`domain` шлюза живёт в одном месте»). Поэтому каждое утверждение
XC-1 о **существующей защите** прогнано командой, а не сверено по памяти. Прогон — рабочий каталог
`project/kacho` (моно-репо), голова `b892cd8`.

| # | Утверждение документа | Команда | Наблюдено | Вердикт |
|---|---|---|---|---|
| 1 | hide-existence-таблица шлюза — **21** запись, **ни одной** storage | `sed -n '153,185p' gateway/internal/middleware/permission_denied_response.go` | 21 ключ: iam 6, compute 4, vpc 7, nlb 3, registry 1 | ✅ верно |
| 2 | `HidesExistenceOnDeny` = явный флаг **ИЛИ** (`/Get` + `v_get` + конкретный scope) | `permission_catalog.go:149-153` + `authz_util.go:36-46` (`isConcreteResourceScope`) | дословно так; «конкретный» = `from_request_field ∉ {"", "*", "subject", "resource"}` и пустой `object_type_from_request_field` | ✅ верно |
| 3 | достижимых типов — **22**, отображён **21**, один объявлен no-backend | производный набор из `embed/permission_catalog.json` (357 записей) по правилу п.2 | 22 типа; 21 = ключи таблицы; 22-й — `compute_instance_group` (`hideExistenceNoBackendTypes`, `permission_denied_notfound_oracle_test.go:62-67`) | ✅ верно |
| 4 | дрейф-гейт проверяет **только** «достижим ⇒ отображён» | `permission_denied_notfound_oracle_test.go:139-186` | два прохода по `reachable`: (а) отображён-или-no-backend, (б) присутствует в таблице ожиданий. Обратного прохода «строка ⇒ достижим» нет | ✅ верно (обратное направление отсутствует) |
| 5 | storage-read скрытия **не покупает** | те же 357 записей: `{Volume,Snapshot,Image}Service/Get` | у всех трёх `required_relation: "viewer"`, `hide_existence` отсутствует ⇒ п.2 ложна ⇒ ни один storage-тип не достижим | ✅ верно (оракул живой — #75) |
| 6 | 404 шлюза не несёт **ни одной** детали | `permission_denied_response.go:113-124` (`buildGRPCNotFoundStatus`) | `status.New(codes.NotFound, notFoundMessage(desc))` — деталей нет by construction | ✅ верно |
| 7 | `deny_reasons` намеренно опущены | `permission_denied_response.go:99-100` | комментарий + отсутствие ключа в `metadata` | ✅ верно |
| 8 | **пять** peer-сайтов держат паритет deny↔miss | чтение пяти файлов §2.7 | `compute/clients/vpc_subnet_client.go:66-69`, `registry/clients/geo/region_client.go:88-91`, `registry/clients/iam/iam_client.go:89`, `nlb/clients/compute/instance_client.go:150-153`, `nlb/clients/geo/region_client.go:127-132` — `PermissionDenied` в одном `case` с `NotFound` | ✅ верно |
| 9 | **пять** сайтов паритет не держат | чтение пяти файлов §2.7 | `compute/clients/storage_client.go:205-206` (`PermissionDenied` в whitelist проброса); `nlb/clients/iam/project_client.go:139,141` (miss→`ErrNotFound`, deny→`ErrFailedPrecondition`); `vpc/clients/iam_client.go:55` и `compute/clients/iam_client.go:120` (свёрнуты только `NotFound`+`InvalidArgument`); `compute/clients/geo_client.go:75-78` (свёрнут только `NotFound`) | ✅ верно |
| 10 | текст ветки недоступности vpc интерполирует ошибку peer'а | `git grep -n 'project check: %v' -- 'services/vpc/internal/apps/kacho/api/*/create.go'` | **7** файлов: `subnet:202`, `address:446`, `network:218`, `securitygroup:176`, `routetable:158`, `gateway:119`, `networkinterface:152` | ✅ верно |
| 11 | у compute та же ветка **уже** opaque (образец для vpc) | `services/compute/internal/service/project_check.go:31` | `Unavailable "project check: upstream project service unavailable"` | ✅ верно |
| 12 | BOLA-guard отдаёт тот же текст, что промах | `services/vpc/internal/apps/kacho/api/subnet/create.go` | **два** guard'а: sync `:141-144` и **async-backstop** после `GetForShare` (`:230`+) — оба `NOT_FOUND "Network %s not found"` | ✅ верно, но guard'а **два** (XC-1-11 дополнен) |
| 13 | `AttachDisk` скоупится по инстансу, `volumeId` гейтит storage | `instance_service.proto:197-202`; `internal_volume_service.proto:33-38`; `services/storage/internal/check/permission_map.go:128` | шлюз: `v_update` @ `compute_instance`/`instance_id`; storage **в процессе**: `editor` @ `storage_volume`/`volume_id` — карта сервиса зеркалит каталог на этом RPC | ✅ верно (гейт реальный, а не только в proto) |
| 14 | транспорт деталей готов: REST-хендлер по умолчанию, async-колонка | `git grep -rn WithErrorHandler -- gateway/` (пусто); `pkg/operations/repo.go:154,183`, `:624-628`; `pkg/migrations/common/0001_operations.sql:18` | `WithErrorHandler` не зарегистрирован ⇒ работает `DefaultHTTPErrorHandler`; `error_details BYTEA` пишется/читается | ✅ верно |
| 15 | наблюдаемость: пакет метрик есть в 5 сервисах | `ls services/*/internal/observability/` | есть у compute, geo, iam, nlb, vpc; **нет** у registry и storage | ⚠️ верно частично — см. п.16 |
| 16 | **«два новых пакета» — неполное описание** | `services/storage/internal/config/config.go:44-46` + `services/storage/cmd/storage/serve.go:326-349` | storage **объявляет** listener «`/healthz`, `/metrics`» и слушает `:9095`, но `mux` регистрирует **только** `GET /healthz` — `/metrics` не раздаётся вовсе; у registry нет ни пакета, ни диагностического listener'а | ❌ **утверждение исправлено** (D9), исход — **#76(в)** |
| 17 | `domain` шлюза — один сайт | `git grep -c '"kacho.cloud.iam.v1"' -- gateway/internal/middleware/permission_denied_response.go` | **4** (`:93`, `:242`, `:273`, `:320`) | ❌ **утверждение исправлено** (§2.6, D5) |

Пункты 16 и 17 — единственные, где круг 4 нашёл описание, расходящееся с кодом; оба переписаны под
**действующий** механизм, а не смягчены. Пункты 1-14 воспроизводимы указанными командами.

---

## 3. Решения и обоснование

### D1. Дом помощника — `pkg/errors` (расширение существующего пакета), не новый

**Решение.** Словарь полос, конструкторы и носитель живут в **`pkg/errors`**.

**Почему.** (а) `pkg/validate` уже импортирует `pkg/errors` (`validate.go:32`), а `INVALID_RESOURCE_ID`
обязан родиться именно в `ResourceID` — общий пакет ниже по графу даёт это без нового ребра импорта и
без риска цикла. (б) `pkg/errors` уже есть и уже про «gRPC-статус с деталями» — заводить второй пакет
той же природы значит ровно то расползание, которое под-фаза устраняет (LEAN). (в) Единственная
альтернатива — per-service дубли — отвергается: §2.3 показывает, что расползание уже произошло на
шести реализациях формата id и стоит одной полосы.

**Границы (Clean Architecture).** Пакет остаётся зависимым только от stdlib + `grpc`/`genproto` —
как сейчас; `domain`/use-case его используют, но он не тянет ни pgx, ни proto-стабы сервисов.

### D2. Пять токенов — закрытый словарь; отсутствие токена значимо

Точное соответствие полосам (нормативная таблица `api-conventions.md`, воспроизводится здесь как
контракт под-фазы, а не как копия правила):

| Токен | Полоса | Смысл для клиента | Канонический код |
|---|---|---|---|
| `INVALID_RESOURCE_ID` | sync-format, **свой** id | «испорченный идентификатор» — терминально, чинится вызывающим | `INVALID_ARGUMENT` |
| `RESOURCE_NOT_FOUND` | direct-read, **свой** ресурс | «своего промаха» — объекта нет в моей БД (или он мне не виден — неотличимо by design) | `NOT_FOUND` |
| `PEER_RESOURCE_MISSING` | peer-validate | «чужой промах» — ссылка не резолвится у владельца | `FAILED_PRECONDITION` |
| `PEER_RESOURCE_STATE` | peer-validate | «чужое состояние» — ресурс есть, состояние не позволяет | `FAILED_PRECONDITION` |
| `PEER_UNAVAILABLE` | peer-validate | «недоступность владельца» — retryable, fail-closed на мутации | `UNAVAILABLE` |

**Словарь закрыт.** Шестой токен не добавляется реализацией — только правкой
`api-conventions.md` (governance). Гейт §7.2 роняет сборку на неизвестном токене.

**Отсутствие токена — тоже контракт.** Токен появляется **только** на полосах резолва
идентификатора. Он **не появляется** на: успешном ответе; `ALREADY_EXISTS`; `ABORTED`;
`INTERNAL`; валидации значения поля (CIDR, `page_size`, `page_token`, `filter`, длина имени);
доменных предусловиях (`"network is not empty"`, immutable-поле); отказе в правах (это
`AUTHZ_DENIED` шлюза — другой namespace). Клиент вправе читать «детали есть, но ErrorInfo нет» как
«это не полоса идентификатора».

### D3. Форма помощника: конструктор + носитель (иначе полоса теряется в sentinel-слоях)

Два выхода, потому что в дереве живут две топологии эмиссии (§2.3):

1. **Конструктор терминального статуса** — там, где полоса известна в точке эмиссии и статус
   строится сразу (`pkg/validate.ResourceID`, iam `shared/ids.go`, use-case-уровень vpc/compute,
   peer-клиенты). Конструктор владеет **и кодом, и токеном** — их нельзя рассогласовать по
   построению.
2. **Носитель полосы** — типизированная ошибка, оборачивающая существующий sentinel (Go 1.25,
   `go.mod:3` — множественный `%w` доступен), которую маппер извлекает через `errors.As` и
   превращает в статус вместе с деталью. Нужен для `serviceerr.MapRepoErr` / `maperr.go` /
   `errmap.go`, где статус строится **позже и в другом слое**, чем известен ресурс.

**Почему не «интерцептор, который дорисует токен по коду».** Полоса не выводится из кода (§2.4:
три кода на одну полосу) и не выводится из текста (текст объявлен непарсибельным — парсить его в
интерцепторе значило бы узаконить ровно то, что конвенция запрещает). Интерцептор физически не
знает, свой это id или чужой. Отвергнуто.

**Почему пара (код, токен) неразрывна в конструкторе.** Иначе через полгода появится вызов, где
токен и код разошлись, и клиент, доверившийся токену, получит неверный код. Пара — единица
контракта.

### D4. `resource_type` — единый corelib-набор `pkg/restype`, форма `<rest-домен>.<ресурс-в-ед.ч.>`

> Круг 1 объявлял `resource_type` «точечной формой из **уже принятого** cross-owner словаря
> `reference.Referrer.type`». **Проверка по коду это опровергла**, и решение переписано целиком.
> `resource_type` — литерал в каждом сценарии §6, то есть wire-контракт, а не деталь.

**Что в дереве на самом деле (сверено, а не предположено).** «Уже принятого словаря» не существует;
существуют **четыре несовместимые точечные таксономии**, живущие одновременно:

| # | Что | Где | Форма | Пригодность как источник истины |
|---|---|---|---|---|
| 1 | `reference.Referrer.type` | `proto/kacho/cloud/reference/reference.proto:49-54` | **пять примеров в комментарии**: `compute.instance`, `compute.instanceGroup`, `loadbalancer.networkLoadBalancer`, `managed-kubernetes.cluster`, `managed-mysql.cluster` | ✗ это не набор, а комментарий; **три из пяти** называют домены, которых среди семи сервисов Kachō нет (`loadbalancer`, `managed-kubernetes`, `managed-mysql`); ничем не гейтится |
| 1а | единственная Go-реализация №1 | `services/compute/internal/protoconv/protoconv.go:25` — `serviceAccountRefType = "iam.service_account"` | **snake_case** | ✗ форма расходится и с №1, и с №2 — для одного и того же ресурса в дереве уже три написания |
| 2 | ключи закрытой таблицы модели прав | `services/iam/internal/authzmap/fga_types.go:232-290` (28 записей), зеркало — `services/iam/internal/domain/feed_registry.go` | **смешанная**: compute/vpc/iam — ед. ч. (`vpc.subnet`, `iam.serviceAccount`), а loadbalancer/registry/storage — **мн. ч.** (`loadbalancer.networkLoadBalancers`, `registry.registries`, `storage.volumes`) | ✗ домен nlb записан как `loadbalancer` (это proto-пакет `kacho.cloud.loadbalancer.v1`, а не то, что видит тенант); **geo отсутствует целиком** (его read-RPC project-scope EXEMPT), операций нет |
| 2а | `module.resource` из permission-строк proto | генерируется в permission-catalog | машинно-плюрализованная, с дефектами: `vpc.gatewaies`, `compute.instanceses`, `iam.issue_s_a_keies` | ✗ не показывается тенанту ни при каких условиях |
| 3 | план-скан iam-direct | `services/iam/internal/repo/kacho/pg/reconcile_adapter.go:287-325` | ед. ч. (`iam.project`, `iam.serviceAccount`, `iam.accessBinding`) | ✗ покрывает только iam |
| 4 | **тенант-видимый** дискриминатор источника ОС | `services/compute/internal/service/instance.go:44-45`, валидируется на входе (`:926-929`) и отдаётся наружу | **ед. ч.**: `storage.image`, `registry.image` | — уже на публичном wire |

Ключевое наблюдение — строки №2 и №4 вместе: для **одного и того же** ресурса дерево уже несёт
`storage.images` (ключ каталога прав) и `storage.image` (публичное поле `bootSource.type`). То есть
«взять существующий словарь» — не выбор между «новым» и «принятым», а выбор между **четырьмя
взаимно противоречивыми**, из которых наружу тенанту сегодня показывается **единственное число**.

**Решение.** Источник истины — **новый единый Go-набор `pkg/restype`** в corelib. Каноническая
форма: **`<rest-домен>.<ресурс в единственном числе, lowerCamelCase>`**, где `<rest-домен>` — первый
сегмент REST-пути, который тенант уже видит в URL. Их ровно семь, по числу сервисов:
`compute` · `geo` · `iam` · `nlb` · `registry` · `storage` · `vpc`
(проверено по `google.api.http` во всём `proto/**`: `/compute/v1` 86, `/iam/v1` 81, `/vpc/v1` 69,
`/nlb/v1` 23, `/storage/v1` 22, `/registry/v1` 15, `/geo/v1` 12 — **`/loadbalancer/v1` не существует**).
Отсюда: `vpc.subnet`, `geo.region`, `iam.project`, `registry.registry`, `storage.volume`,
**`nlb.networkLoadBalancer`**, `compute.instance`, `<домен>.operation`.

**Каждая запись набора несёт три поля** (не одну строку): `Value` (сам `resource_type`), `Owner`
(сервис-владелец типа) и `CatalogKey` (ключ таблицы прав из №2, либо пусто, если тип моделью прав не
покрыт — geo, operation). Владелец — **поле**, а не результат разбора строки; см. D5.

**Как разрешается коллизия с ключами permission-каталога (№2).** Ключи каталога **не
переименовываются** — они завязаны на FGA-типы, на seed iam, на встроенную копию в middleware шлюза и
на гейт `permission-catalog-check`; их правка — отдельный ломающий контракт, к полосе отказа
отношения не имеющий. Вместо переименования S1 вводит **биекцию** `restype.Value ↔ CatalogKey`
и гейтит её в обе стороны:
- каждый ключ №2 имеет **ровно одну** запись в `pkg/restype` (`loadbalancer.networkLoadBalancers` →
  `nlb.networkLoadBalancer`, `storage.volumes` → `storage.volume`, `registry.registries` →
  `registry.registry`, …) — иначе CI красный;
- каждая запись `pkg/restype` с непустым `CatalogKey` указывает на существующий ключ №2 — иначе CI красный;
- `resource_type` со значением, равным **неканоническому** ключу каталога, — **запрещён к эмиссии**:
  гейт §7.2 роняет сборку. Так внутренний словарь не протекает наружу через заднюю дверь, а дрейф
  между таблицами невозможен by construction.

**Что такое «неканонический ключ» — перечислено поимённо, потому что от этого зависит исполнимость
гейта.** Из **28** ключей `services/iam/internal/authzmap/fga_types.go:232-290` **20 уже записаны в
канонической форме** `<домен>.<ресурс в ед. ч.>` и **совпадают** с целевым `Value` (`compute.instance`,
`compute.disk`, `compute.image`, `compute.snapshot`, `vpc.network`, `vpc.subnet`, `vpc.address`,
`vpc.securityGroup`, `vpc.routeTable`, `vpc.gateway`, `vpc.networkInterface`, `vpc.addressPool`,
`iam.account`, `iam.project`, `iam.user`, `iam.serviceAccount`, `iam.group`, `iam.role`,
`iam.accessBinding`, `iam.condition`). Расходятся ровно **8**:

| Неканонический ключ каталога | Канонический `Value` | Причина расхождения |
|---|---|---|
| `loadbalancer.networkLoadBalancers` | `nlb.networkLoadBalancer` | домен + мн. число |
| `loadbalancer.targetGroups` | `nlb.targetGroup` | домен + мн. число |
| `loadbalancer.listeners` | `nlb.listener` | домен + мн. число |
| `registry.registries` | `registry.registry` | мн. число |
| `registry.repositories` | `registry.repository` | мн. число |
| `storage.volumes` | `storage.volume` | мн. число |
| `storage.snapshots` | `storage.snapshot` | мн. число |
| `storage.images` | `storage.image` | мн. число |

> **Блокирующее исправление круга 2 (гейт был неисполним).** Круг 2 формулировал запрет как «эмиссия
> `resource_type`, равного ключу каталога, роняет сборку». Буквально это запрещало **20 из 28**
> ключей — в том числе `vpc.subnet`, `vpc.network`, `iam.project`, `compute.instance`, то есть
> **wire-литералы собственных сценариев** документа (XC-1-01, XC-1-02, XC-1-07, XC-1-12, XC-1-19).
> Гейт краснел бы на первом же сценарии, который сам же и обязан пройти. Причина ошибки —
> неявное допущение «ключи каталога неканоничны все», опровергаемое чтением `fga_types.go:232-290`.
> **Корректная формулировка:** запрещена эмиссия значения, равного ключу каталога, **для которого
> канонический `Value` отличается** — то есть ровно 8 строк таблицы выше. Проверяемо без разбора
> строк: гейт сравнивает эмитируемый литерал со **столбцом `CatalogKey`** тех записей `pkg/restype`,
> где `CatalogKey != Value`; совпадение → красный. Записи с `CatalogKey == Value` (20 штук) в
> запрещающий набор **не входят by construction**, а не «по исключению».

Записи, не покрытые №2 (`geo.region`, `geo.zone`, `<домен>.operation`), несут пустой `CatalogKey`
и **обязаны** быть перечислены поимённо в наборе — «нет в каталоге прав» перестаёт означать «нет
`resource_type`». Это и есть та дыра, из-за которой каталог нельзя было взять источником истины.

**Почему не FGA-`object_type`** (`vpc_subnet`, `storage_volume`, `compute_instance`). Это
**внутренний закрытый словарь модели прав**, и его утечка наружу уже была инцидентом: gateway
отдавал `"vpc_subnet not found"`, что одновременно и раскрывало внутренний словарь типов, и, будучи
непохожим ни на один backend-текст, само работало оракулом (`security.md` инвариант #6; комментарий
`permission_denied_response.go:195-208`). Повторять это в `metadata` — воспроизводить закрытый
дефект.

**Почему «не плодить таксономию» здесь не аргумент против.** Ban #11/LEAN запрещает **дрейф**, а не
единый набор. Четыре несовместимые таксономии уже существуют — опция «просто взять принятую»
физически недоступна. Выбор стоит между (а) поднять одну из четырёх на публичную поверхность
(любая тянет за собой либо несуществующий домен `loadbalancer`, либо множественное число вопреки
уже отданному наружу `storage.image`, либо отсутствие geo/operation) и (б) один канон + **гейтенные**
биекции к остальным. LEAN достигается гейтом, а не отказом от канона: после S1 дрейф между №2 и
`pkg/restype` роняет CI, чего сегодня нет ни между какой парой из четырёх.

`reference.Referrer.type` при этом **не переписывается в XC-1** (это wire-поле, его форма — вопрос
B1/REG-2). S5 добавляет в `reference.proto` ссылку на `pkg/restype` как на источник истины и заводит
issue на приведение `serviceAccountRefType` (`iam.service_account` → `iam.serviceAccount`) — с
критерием приёмки, см. §9 O-7.

### D5. `domain` = сервис-**эмитент**, `<service>.kacho.cloud`

**Решение.** `ErrorInfo.domain` называет сервис, **сформировавший статус**, в форме
`<service>.kacho.cloud` (`geo.kacho.cloud`, `iam.kacho.cloud`, `vpc.kacho.cloud`,
`compute.kacho.cloud`, `storage.kacho.cloud`, `nlb.kacho.cloud`, `registry.kacho.cloud`).

**Почему эмитент, а не владелец ресурса.** Если consumer, отвергая чужой `zoneId`, поставит
`domain = geo.kacho.cloud`, он начнёт говорить от имени сервиса, который не контролирует; хуже —
станет неотличим от самого geo, и клиент не поймёт, «geo сказал, что зоны нет» или «compute
сказал, что geo сказал».

**Владелец НЕ выводится разбором префикса `resource_type`.** Круг 1 писал «он читается из префикса
(`geo.zone` → geo)» — это была деривация из строки, и она ломалась ровно на том словаре, который
круг 1 объявил источником: attested-префикс nlb там — `loadbalancer`, а `domain` по D5 —
`nlb.kacho.cloud`, то есть разбор давал бы несуществующий сервис. Класс ошибки известен и запрещён
директивой владельца (`data-integrity.md`: «связь берётся только резолвом у владельца, никогда не
выводится из имени» — прецедент `regionFromZone()` в nlb, где строковая деривация молча обращала
проверку в no-op).

**Решение.** Владелец — **поле** `Owner` записи `pkg/restype` (D4), а не результат разбора. Клиент,
которому владелец нужен, получает его из **опубликованного набора**, а не парсит строку. Внутри кода
владелец берётся только чтением поля.

Для канонической формы D4 префикс **совпадает** с `Owner` на каждой записи — но это **проверяемый
инвариант, а не допущение**: S1 несёт гейт `strings.Cut(Value, ".") ⇒ первый сегмент == Owner` по
всему набору, красный при первом же расхождении. Разница принципиальная: сегодня совпадение
обеспечено конструкцией и загейчено, а деривация из строки была бы верна «пока никто не завёл
`loadbalancer.*`».

**Проверяемость D7 (не отмывать чужой токен)** формулируется без разбора префиксов: `domain` в
ответе обязан быть **равен единственной константе домена эмитирующего процесса**
(`errors.Domain`, задаётся в composition root один раз на сервис). Ответ, содержащий деталь с любым
другим `domain`, — нарушение, ловится и сценарием XC-1-18, и статическим гейтом §7.1. Владелец в
этой проверке не участвует вовсе.

**Gateway.** Его собственные `AUTHZ_DENIED`/`AUTHN_REQUIRED` — отдельный namespace (не полоса
идентификатора). В S5 их `domain` нормализуется на `gateway.kacho.cloud` ради когерентности —
**на всех четырёх сайтах** `permission_denied_response.go` (`:93` gRPC-`AUTHZ_DENIED`, `:242`
gRPC-`AUTHN_REQUIRED`, `:273` и `:320` — REST-JSON-ветки, собирающие строку литералом), и все
четыре берут её из **одной** константы. Это безопасно — ни один тест и ни один newman-кейс на
значение `domain` не опирается (проверено командой, §2.6): newman-хелпер утверждает `reason` и
`metadata`, но не `domain`. Правка **только gRPC-ветки** оставила бы REST расходящейся с gRPC и
уронила бы XC-1-22/23 («символ-в-символ») — именно поэтому число сайтов здесь названо явно.

### D6. Аддитивность: XC-1 меняет **только** детали; коды и тексты — ни одного

**Решение.** Токен описывает **полосу вызова**, а не текущий код. Там, где код сегодня off-lane
(§2.4), XC-1 всё равно ставит токен полосы и **не трогает код**. Расхождение «как эмитится» vs
«канон» фиксируется явным списком-храповиком (§7.3), который может только сокращаться.

**Единственное исключение из аддитивности — поимённое, пять сайтов, по причине безопасности.**
Аддитивность защищает **совместимость**, а не дефекты. Пять сайтов §2.7, где «нет доступа» и «нет
объекта» различимы наблюдателем, — не off-lane-коды, а живой existence-oracle; откладывать их в XC-2
значило бы, что XC-1 **утверждает** сценарием XC-1-16 защиту, которой в коде нет (ban #14: production-
grade, не «hardening позже»). Поэтому D12 меняет **ровно** ветку `PermissionDenied` этих пяти сайтов
и **ничего больше**:

| Сайт | miss (не меняется) | deny: было → станет |
|---|---|---|
| compute → storage `Volume` | `NOT_FOUND` | `PERMISSION_DENIED` + текст владельца → `NOT_FOUND` + тот же текст, что miss |
| nlb → iam `Project` | `NOT_FOUND` | `FAILED_PRECONDITION` → `NOT_FOUND` |
| vpc → iam `Project` | `NOT_FOUND` | `UNAVAILABLE` + сырой peer-текст → `NOT_FOUND` |
| compute → iam `Project` | `NOT_FOUND` | `UNAVAILABLE` → `NOT_FOUND` |
| compute → geo `Zone` | `INVALID_ARGUMENT` | `UNAVAILABLE` → `INVALID_ARGUMENT` |

Свойства этого исключения, которые делают его безопасным и проверяемым: (а) **путь промаха —
байт-в-байт прежний** на всех пяти, меняется только путь отказа по правам; (б) целевое значение
берётся не из канона, а из **соседней ветки того же сайта**, поэтому off-lane-статус сайта не
меняется и строка храповика §7.3 остаётся на месте; (в) исход схлопывания — тот же, что уже
работает на пяти паритетных сайтах, то есть новая семантика не изобретается; (г) список закрыт и
перечислен здесь поимённо — гейт §7.1 запрещает шестой сайт с расходящейся deny-веткой.
Аддитивная сверка DoD («ноль расхождений против базы») исключает **только** эти пять deny-веток,
и исключение проверяется по имени сайта, а не по маске.

**Почему так, а не «сначала выправить коды».** (а) Выправление меняет HTTP-статус там, где полоса
перекодируется с `NOT_FOUND` на `FAILED_PRECONDITION`: `404 → 400` (проверено по
`grpc-gateway v2.29.0 runtime/errors.go:44-60`: `InvalidArgument→400`, `FailedPrecondition→400`,
`NotFound→404`). Это ломающее изменение для UI и всех newman-суит — отдельная работа со своим
риском. (б) Порядок «токен → потом коды» **безопаснее обратного**: клиент, уже ключующийся на
токене, переживёт коррекцию кода незаметно; клиент, ключующийся на коде, сломается. Токен — это
именно тот слой совместимости, который делает будущую коррекцию нерушительной.
(в) Для части коррекций HTTP-статус вообще не меняется (`INVALID_ARGUMENT → FAILED_PRECONDITION`:
400 → 400), что даёт дешёвый первый шаг XC-2.

**Это не MVP и не отложенный тех-долг** (ban #14/#11): XC-1 production-complete в своих границах —
полоса выражена, наблюдаема, протестирована и загейчена на всей поверхности; коррекция кодов — не
недоделанная часть XC-1, а **другой контракт** с другим радиусом поражения, и он явно
зафиксирован как XC-2 с механизмом принуждения (храповик не даёт списку расти).

### D7. Токен не отмывается через границу сервиса

Consumer, получив от владельца статус с `RESOURCE_NOT_FOUND`/`domain=<owner>`, **обязан
переставить** свой токен полосы (`PEER_RESOURCE_MISSING`/`PEER_RESOURCE_STATE`/`PEER_UNAVAILABLE`)
и свой `domain`. Проброс чужой детали наружу запрещён.

**Почему.** Иначе клиент получит `domain=geo.kacho.cloud` в ответе от `compute` и решит, что говорил
с geo напрямую; вся полосовая семантика («свой промах» vs «чужой промах») схлопнется. Это ровно тот
класс, что `data-integrity.md` называет «межсервисное намерение — контракт принимающей стороны»:
эмиссия ≠ пригодность на приёмной стороне. Проверяется сценарием XC-1-18 и статическим гейтом.

### D8. Паритет hide-existence — часть XC-1, и он режется **атомарно по типу ресурса**

**Решение.** Для каждого типа, достижимого через `CatalogEntry.HidesExistenceOnDeny`, шлюзовой
404-отказ несёт **ровно ту же** деталь, что и настоящий промах владельца: `RESOURCE_NOT_FOUND`,
`domain` владельца, `metadata{resource_type, resource_id}` — с тем же `resource_id`, что прислал
вызывающий (он его уже знает — не утечка). Ни одной дополнительной детали (никаких deny-reasons —
запрет остаётся, `permission_denied_response.go:98-101`).

**Атомарность среза.** Строка таблицы шлюза и эмиссия у владельца этого типа **приземляются одним
изменением** (одна ветка/PR, один rollout umbrella-чарта). Иначе между двумя мержами наличие детали
разделяет «нет доступа» и «нет объекта» — тот самый оракул, который таблица и существует, чтобы
закрыть.

**Ветка fallback** (тип вне таблицы / wildcard-scope) поведение не меняет: нейтральный `"not found"`
**без** детали — как сегодня. Существующий дрейф-гейт таблицы расширяется так, чтобы «тип достижим,
но `resource_type` не задан» роняло CI (§7.2), поэтому fallback остаётся аварийным, а не рабочим.

**Остаточный риск rolling-update** (шлюз и сервис — разные поды): окно в секунды, когда одна сторона
уже отдаёт деталь, а другая нет. Митигация — атомарный срез + единый `helm upgrade` umbrella.
Документируется, не замалчивается. **Рассмотрена и отвергнута** альтернатива «шлюз нормализует
и настоящий 404 владельца»: она превращает шлюз из гейта в переписыватель ответов ради секундного
окна; при этом байт-паритет уже покрыт таблицей и её гейтом. Если таблица когда-нибудь поплывёт —
нормализатор становится правильным фиксом; пока он scope creep.

### D9. Наблюдаемость — интерфейс в corelib, счётчик в сервисном адаптере

Corelib определяет узкий интерфейс-приёмник (`reason`, `resource_type`) — по образцу уже
приземлившегося `pkg/operations.Recorder`, который сервисные `internal/observability/metrics`
реализуют (`services/geo/internal/observability/metrics/metrics.go:26-45`). Никакого prometheus в
corelib (его там нет и не должно быть — adapter-граница).

> **Исправление круга 2 (фактическое замечание №2).** Круг 2 писал «ровно как уже сделано …,
> который сервисные `internal/observability/metrics` реализуют», подавая раскатку как продолжение
> **сплошного** существующего паттерна. По коду пакет `internal/observability/metrics` существует в
> **5 сервисах из 7** — compute, geo, iam, nlb, vpc; в **registry и storage его НЕТ**. Значит
> «реализация в семи адаптерах» = 5 расширений + **2 новых пакета**, и это объявляется прямо, а не
> прячется за словом «уже».
>
> [!note] Координаты трёх исправлений ниже — состояние НА МОМЕНТ КРУГА, не сегодняшнее
> Круги — история, и их вердикты здесь не переписываются. Но координаты в них читаются как
> живые, а часть уже мертва: диагностическая поверхность storage поднимается профилем
> носителя (`pkg/servicehost.ServeSurface`) по объявлению, а не собственной функцией корня,
> и метрики на ней раздаются. Что осталось верным по существу — сам класс: «порт слушается,
> ручка объявлена, отдавать нечего», и «полоса не сработала ни разу» неотличимо от «полоса не
> подключена». Прежде чем идти по любой координате отсюда — спроси дерево.

> **Исправление круга 4 (механизм описан неверно — «два новых пакета» скрывало худшее).** Круг 3
> оставил формулировку «пакета в дереве нет», из которой следовало бы, что достаточно добавить
> пакет и зарегистрировать его в composition root. По коду у storage **уже есть** диагностический
> listener и он **уже объявлен раздающим `/metrics`**: `services/storage/internal/config/config.go:44-46`
> («адрес cluster-internal diagnostic HTTP-listener'а (`/healthz`, `/metrics`)», `KACHO_STORAGE_METRICS_ADDR`,
> default `:9095`), поднимается в `cmd/storage/serve.go:236`. Но сам `startDiagnosticListener`
> (`serve.go:326-349`) регистрирует в `mux` **ровно один** хендлер — `GET /healthz` — и печатает в
> лог `"paths", "/healthz"`. То есть **порт слушается, ручка объявлена, метрик нет ни одной**:
> любой скрейп `:9095/metrics` получит 404, а «полоса не сработала ни разу» будет неотличима от
> «полоса не подключена» — ровно класс, ради которого D9 и существует. У registry нет ни пакета
> метрик, ни диагностического listener'а вообще (`grep -rn "MetricsAddr\|/metrics"
> services/registry/internal/config services/registry/cmd/registry` — пусто).
>
> **Что из этого следует для XC-1.** (а) Объём S1 — 5 расширений + **1 новый пакет** (registry) +
> **1 новый пакет и починка уже объявленной ручки** (storage). (б) Расхождение «объявлено, но не
> раздаётся» — **не** предмет XC-1: это самостоятельный дефект наблюдаемости storage, у него есть
> заведённая задача **#76(в)** («сбор метрик объявлен, процесс их не отдаёт»); XC-1 обязан лишь не
> объявлять счётчик наблюдаемым там, где скрейпить нечего. (в) Поэтому DoD S1 формулирует критерий
> **через ручку, а не через пакет**: счётчик полосы виден в теле ответа `GET <metricsAddr>/metrics`
> процесса, а не «пакет создан».

Кардинальность ограничена **by construction**: 5 токенов × ~40 `resource_type` × 1 сервис на
процесс. `resource_id` в метку **не попадает никогда** (неограниченная кардинальность).

**Зачем это обязательно.** Класс «ноль доставленных строк за всю жизнь очереди» (`data-integrity.md`)
воспроизводится здесь один-в-один: полоса, которая никогда не срабатывает, неотличима от полосы,
которую забыли подключить. Счётчик + структурное поле лога `error.reason` делают «эта полоса мертва»
наблюдаемым фактом, а не догадкой.

### D10. Производительность — стоимость только на пути отказа, с потолком

- Деталь строится **исключительно** на пути ошибки. На успешном ответе — ни одной аллокации.
- `WithDetails` = один `anypb.New` + marshal; фиксируется бенчмарком и **потолком сериализованной
  детали ≤ 256 байт** (тест). Потолок нужен не ради байтов, а как структурный запрет складывать в
  `metadata` прозу/диагностику.
- `metadata` — **закрытый набор из двух ключей**. Расширение — только governance.
- Один статус на один RPC: запрещено строить деталь в цикле по странице выдачи (List фильтрует,
  а не отвергает поэлементно).
- Async-путь: колонка `error_details` сегодня почти всегда NULL, после XC-1 будет заполнена на
  op-ошибках (~+100 Б на строку ошибки). Строк ошибок на порядки меньше строк операций; влияния на
  индексы нет (колонка не индексируется).

### D11. Валидность на wire (границы, которые ломают деталь молча)

`ErrorInfo.metadata` — `map<string,string>` proto3, где **строка обязана быть валидным UTF-8**.
Испорченный id из запроса может содержать невалидные байты; тогда `proto.Marshal` внутри
`WithDetails` падает, а существующий код повсеместно **игнорирует** эту ошибку
(`pkg/errors/errors.go:48,53` — `if … derr == nil`). Результат — деталь молча исчезает, и клиент,
доверившийся токену, попадает в необъявленную ветку.

**Решение:** помощник **санирует** значения перед укладкой: невалидный UTF-8 заменяется, длина
`resource_id` в metadata обрезается до фиксированного предела. Текст сообщения при этом **не
меняется** (аддитивность, D6). Ветка «деталь не собралась» обязана быть невозможной, а не тихой.

### D12. Паритет deny↔miss на peer-границе — часть XC-1, и `PERMISSION_DENIED` наружу не проходит

**Мотив.** XC-1 обязан утверждать сценарием XC-1-16, что отказ владельца по правам неотличим от
промаха. По §2.7 это верно на пяти сайтах из десяти. Утверждать общее свойство, держащееся на
половине сайтов, — «проверка с формой без содержания»; ослаблять формулировку до «на тех сайтах, где
уже верно» — оставить оракул, достижимый с публичного края (compute→storage). Поэтому паритет
**доводится**, а не декларируется.

**Правило 1 — deny сводится в ветку miss того же сайта.** Peer-клиент обязан классифицировать
`PermissionDenied` от владельца **тем же** исходом, что `NotFound`: одна `case`-ветка, один sentinel,
один текст. Целевые значения — таблица в D6 (берутся из соседней ветки того же сайта, не из канона).
Это ровно то, что уже делают `compute/internal/clients/vpc_subnet_client.go:66-69`,
`registry/internal/clients/geo/region_client.go:88-91`, `registry/internal/clients/iam/iam_client.go:89`,
`nlb/internal/clients/compute/instance_client.go:150-153`, `nlb/internal/clients/geo/region_client.go:127-132`.

**Правило 2 — `PERMISSION_DENIED` владельца не пересекает границу сервиса.** Consumer **никогда** не
форвардит `codes.PermissionDenied` peer'а наружу — ни кодом, ни сообщением. Основание двойное: это
authz-факт **чужого** ресурса (клиент не должен узнать о существовании объекта, к которому доступ ему
не выдан), и это полоса, которой закрытый пятитокенный словарь не выражает. Из whitelist
`services/compute/internal/clients/storage_client.go:205-206` `codes.PermissionDenied` **изымается**;
остальные коды whitelist'а не трогаются. Собственный отказ шлюза по правам не затрагивается — он
живёт в своём namespace (`AUTHZ_DENIED`, O-3).

**Правило 3 — сырой peer-текст не попадает в сообщение.** `status.Errorf(codes.Unavailable,
"project check: %v", err)` (семь файлов vpc, §2.4 строка №6) интерполирует ошибку peer'а в ответ
клиенту — hardening-инвариант **#1**. Ветка недоступности этих сайтов переводится на фиксированный
opaque-текст (образец — `compute/internal/service/project_check.go:31` «project check: upstream
project service unavailable»). Это меняет **текст ветки `UNAVAILABLE`**, и это шестая позиция
в списке исключений аддитивности; ветки `NOT_FOUND` она не касается.

**Правило 4 — комментарий приводится в соответствие коду.** Три комментария, заявляющих паритет,
которого нет (`nlb/internal/clients/iam/project_client.go:41-48` и `:142-144`;
`vpc/internal/clients/iam_client.go:56-61` — рассуждение, покрывающее `PermissionDenied`, но не
включившее его в `case`), переписываются под фактическое поведение **после** фикса. Пока код и
комментарий расходятся, следующий контрибьютор «чинит» код под неверный комментарий (`security.md`
инвариант #5, `architecture.md` doc-truthfulness).

**Где приземляется.** vpc → S3; compute и nlb → S4 (стадия, владеющая consumer'ом). Каждый сайт —
TDD RED→GREEN на **наблюдаемом** уровне: тест утверждает, что ответ на deny **байт-в-байт** равен
ответу на miss (код + текст + сериализованные детали), а не только «код совпал».

**Чего D12 НЕ делает.** Не меняет решение о доступе ни на одном RPC (правá проверяет модель —
`security.md`, директива владельца 2026-07-27); не превращает отказ в успех; не трогает пять
паритетных сайтов; не добавляет шестой токен.

**Смежный, но другой класс — и он не подменяется D12.** «Отказ в правах — терминален, а не
временный» — то же наблюдение, что и у D12, но на **другой** поверхности: в очереди регистраций
storage отказ в правах классифицируется как **временный**, поэтому строка не помечается
отправленной и блокирует свою партицию повторами (`data-integrity.md`, §«Межсервисное намерение —
контракт принимающей стороны»). D12 живёт на **request-path** peer-клиентов и о дренаже ничего не
знает. Исход этой строки — задача **#76(б)**, критерий — в реестре §9.0. XC-1 её **не** чинит и не
объявляет починенной: иначе документ приписал бы себе фикс, которого не делает.

---

## 4. Область: что покрывается — и почему это правильный первый срез

Задача просила оценить, нужно ли покрывать все RPC сразу или существует осмысленный первый срез.

### 4.1 Ось «все RPC» — неверная ось

Пять токенов описывают **исключительно резолв идентификатора**. RPC без единого id-аргумента
(`List` без ссылок, `MachineType.List`, health) полосы не имеют и токена не получают **никогда** —
не «пока», а по определению. Правильная ось — **полоса**, а не RPC. Всего RPC **358**; полосу несёт
подмножество, определяемое наличием id-аргумента (свой или чужой).

> **Разбор замечания круга 1 (ревьюер указал «≈350» как фактическую ошибку — перепроверено, верно
> 358).** Пересчёт, идентичный на `2e54f0e` и `b892cd8`:
> `git grep -hE "^[[:space:]]*rpc[[:space:]]" <ref> -- "proto/**/*.proto" | wc -l` → **358**.
> Контрольные срезы: то же число получается при ограничении областью `proto/kacho`
> (единственное дерево с `rpc`-декларациями — `proto/` содержит лишь `google/`, `kacho/`,
> `buf.*`, `validation.proto`); ни одна из 358 строк не является закомментированной
> (`grep -vE "^\s*//"` не убирает ни одной); 65 блоков `service`, 63 файла. Строки `rpc` внутри
> комментариев в дереве есть (9 штук), но они начинаются с `//` и под шаблон `^\s*rpc\s` не
> попадают, поэтому в 358 не входят. Вероятная причина «≈350» — счёт по `rpc `-подстроке с
> последующим ручным вычитанием комментариев, которые в исходный шаблон и не попадали.
> Число оставлено как было; изменена только его доказательность.

### 4.2 Срез «только мутации» — рассмотрен и отвергнут

Аргумент «клиент различает полосы в основном на мутациях» не выдерживает проверки кодом:

- Именно на **чтении** живёт пара, которую клиент обязан различать, а сегодня не может:
  `INVALID_RESOURCE_ID` («в ссылке опечатка — не повторяй») против `RESOURCE_NOT_FOUND` («объект
  удалён или не твой — обнови список»). Для UI это разные экраны.
- `Get` — единственное место, где живёт hide-existence-паритет (§2.5). Оставить чтение без токена
  значит оставить незакрытым оракул, который сама под-фаза и создаёт.
- Разделение по форме доставки в принципе невозможно: `Subnet.Create` отдаёт одну полосу
  **синхронно**, а другую — в `op.error` (§2.5). «Мутации» не образуют связного множества.
- Стоимость покрытия чтения — та же строка на той же полосе, тем же помощником. Экономии нет.

**Настоящий риск сосредоточен не в «мутациях», а в round-trip деталей через БД операции** —
единственная неопробованная механика. Поэтому она доказывается **первой** (стадия S2), но не сужает
область.

### 4.3 Принятый срез

**XC-1 покрывает полосу целиком: все пять токенов, на всех путях резолва идентификатора, во всех
семи сервисах, на обоих листенерах (:9090 и :9091), в обеих формах доставки.**

Обоснование полноты — прямое следствие D2: решающая процедура клиента есть **дизъюнкция** по
токенам. Частичный словарь оставляет клиенту разбор прозы как запасной путь, а значит не даёт
избавиться от него; выгода появляется только на полном покрытии, и «отсутствие токена» становится
значимым только когда покрытие тотально. Половина словаря — не половина пользы, а ноль.

**Входит дополнительно (круг 2):** приведение к паритету пяти peer-сайтов, где «нет доступа» и «нет
объекта» сегодня различимы наблюдателем (§2.7, D12). Это не расширение оси, а условие
**истинности** утверждений XC-1-16/XC-1-43: XC-1 не вправе декларировать существование защиты,
которой в коде нет.

**Явно НЕ входит** (§9): коррекция off-lane кодов (O-1/XC-2); доменные предусловия как отдельная ось
токенов (O-2/XC-3); токены на пути авторизации (O-3); локализация (O-4); нормализатор ответов на
шлюзе (O-5); асимметрия **формы доставки** deny-vs-miss на async-мутациях (O-6/XC-4); приведение
`reference.Referrer.type` к `pkg/restype` (O-7); **скрытие существования на прямом read-пути storage**
(O-8 → задача **#75** — меняет наблюдаемый код `403 → 404` через proto-аннотацию и генерируемый каталог,
исполняется вместе с STOR-AUTHZ-2); стандартизация newman-харнесса compute/iam/registry/storage
(O-9).

> Граница между «входит» и «не входит» на storage-ребре проведена **по поверхности, а не по
> удобству**: XC-1 закрывает оракул там, где он рождается **пробросом чужого кода через границу
> сервиса** (`AttachDisk`, D12 правило 2 — это и есть предмет полосы), и не трогает оракул, который
> живёт **в собственной модели прав storage** (прямой `Get` — предмет authz-редизайна). Обе
> поверхности названы, обе имеют сценарий (XC-1-43 и XC-1-46) и обе имеют исход.

---

## 5. Декомпозиция на стадии

Порядок продиктован графом зависимостей монорепо и требованием атомарности среза (D8).
`project/kacho` — один `go.mod`, поэтому «порядок сборки» здесь = порядок слоёв и мержей.

| Стадия | Содержание | Почему именно здесь |
|---|---|---|
| **S1** | corelib: словарь, конструкторы, носитель, санитайзер, **`pkg/restype`** (набор `resource_type` + `Owner` + `CatalogKey`, D4), приёмник наблюдаемости; **скелет всех четырёх гейтов** (§7.1-§7.4, включая биекцию к каталогу прав и прослеживаемость сценариев); сведение **шести** реализаций формата id → полоса `INVALID_RESOURCE_ID` целиком | Ничего нельзя написать до словаря и до `pkg/restype` — `resource_type` литерален в каждом сценарии. Полоса формата **не имеет оракульной составляющей** (существование ресурса не запрашивается) ⇒ раскатывается разом, без атомарных срезов. Гейты вводятся **сразу**, а не в конце — иначе S2-S4 успеют разъехаться (и ровно так разъехались перечень и таблица в круге 1) |
| **S2** | **geo + iam** (leaf-владельцы): `RESOURCE_NOT_FOUND` на direct-read; строки шлюза для их типов — **тем же изменением**; доказан round-trip детали через `Operation.error_details` | geo и iam — владельцы `Zone`/`Region`/`Project`/`Account`, которых валидируют все остальные. Их промах — **триггер** чужой полосы у всех consumer'ов; пока его формы нет, conformance consumer'ов нечем закреплять. Плюс они не зовут никого (leaf) — минимальный радиус |
| **S3** | **vpc + storage**: своя `RESOURCE_NOT_FOUND` + чужие `PEER_*` (→ geo, iam); строки шлюза для **7 vpc-типов** (storage-типы недостижимы через `HidesExistenceOnDeny` — строка была бы мёртвой, см. §2.5/§2.7; исход — O-8 → **#75**); **D12 для vpc→iam** (1 сайт / 7 файлов) | Владельцы второго яруса: сами являются целью для compute/nlb и сами consumer'ы для geo/iam. Приземляются после S2, чтобы их peer-полоса тестировалась против уже токен-несущего владельца (D7 проверяем). Паритет deny↔miss чинится там же, где живёт peer-клиент — иначе фикс отрывается от полосы, которую он делает утверждаемой |
| **S4** | **compute + nlb + registry**: своя `RESOURCE_NOT_FOUND` + чужие `PEER_*` (→ geo, iam, vpc, **storage**, compute); строки шлюза для 8 достижимых типов (`compute_*` ×4, `nlb_*` ×3, `registry_registry`); **D12 для compute и nlb** (4 сайта, включая изъятие `PermissionDenied` из whitelist compute→storage) | Самые глубокие consumer'ы: nlb зовёт compute+vpc+geo+iam, compute зовёт vpc+**storage**+geo+iam. Приземляются последними, когда все их владельцы уже эмитируют. Здесь же закрывается оракул §2.7, достижимый с публичного края через **чужой** RPC (XC-1-43), и ставится пин на оракул прямого storage-пути, который закрывает **#75** (XC-1-46) |
| **S5** | Сквозная сверка: нормализация `domain` шлюза; заморозка храповика off-lane; e2e-проекция (REST + gRPC-native); правка `api-conventions.md` (пункт «как-эмитится vs канон»); перенаправление семи acceptance-доков с ад-хок токенов; vault-trail | Финальная когерентность: делается, когда вся поверхность уже эмитирует, иначе документируется намерение, а не реальность (`architecture.md` doc-truthfulness) |

**Каждая стадия production-complete в своих границах:** полный error-handling на затронутых полосах,
authz не ослабляется ни на одном RPC (детали добавляются **после** решения о доступе), инварианты
БД не затрагиваются (изменений схемы нет), наблюдаемость подключена с S1, TDD RED→GREEN на каждой.

---

## 6. Сценарии (Given-When-Then)

Обозначения: `<D>` — `domain` эмитента (`vpc.kacho.cloud` и т.п.); `RT` — `metadata.resource_type`;
`RID` — `metadata.resource_id`. «Деталь» = элемент `google.rpc.Status.details` с
`@type = type.googleapis.com/google.rpc.ErrorInfo`.

### 6.1 Полоса «испорченный идентификатор» — `INVALID_RESOURCE_ID` (S1)

#### Сценарий XC-1-01: malformed свой id на sync-чтении

**ID:** XC-1-01

**Якорь:** **U** `VPC-1-03` (wrong-prefix own-id → sync `INVALID_ARGUMENT` первым стейтментом) · проекции: `STOR-1-05`, `COMP-1-22`

**Given** аутентифицированный принципал с правом на `vpc.subnets.get`

**When** клиент вызывает `SubnetService.Get` (`GET /vpc/v1/subnets/garbage!!`)

**Then** код `INVALID_ARGUMENT`, текст **дословно** `"invalid subnet id 'garbage!!'"` (не изменён)
**And** ровно одна деталь `ErrorInfo` с `reason = "INVALID_RESOURCE_ID"`, `domain = "vpc.kacho.cloud"`
**And** `metadata = {resource_type: "vpc.subnet", resource_id: "garbage!!"}` — ровно два ключа
**And** ответ приходит **до** любого обращения к БД и до peer-вызова (первым стейтментом)

#### Сценарий XC-1-02: malformed свой id на мутации — форма доставки синхронная

**ID:** XC-1-02

**Якорь:** **U** `VPC-1-03` (та же полоса на мутации — `networkId` own-owned)

**When** клиент вызывает `SubnetService.Create` с `networkId = "garbage!!"`

**Then** **синхронный** `INVALID_ARGUMENT "invalid network id 'garbage!!'"`; операция не создаётся
**And** деталь `ErrorInfo{reason: "INVALID_RESOURCE_ID", domain: "vpc.kacho.cloud",
metadata: {resource_type: "vpc.network", resource_id: "garbage!!"}}`

#### Сценарий XC-1-03: полоса формата покрыта во всех шести реализациях

**ID:** XC-1-03

**Якорь:** **U** `COMP-1-22` + `REG-1-31` + `STOR-1-05` (кросс-сервисный сценарий — по строке на принятый id) · **E** существующие malformed-id тесты vpc/nlb/iam/geo

**Given** шесть независимых эмиттеров формата id (`pkg/validate.ResourceID`; iam
`shared.ValidateResourceID`; geo `domain.ValidateID`; vpc `repo/helpers`; nlb `repo/pg/errors`;
storage `service/image`) — см. §2.3

**When** для каждого сервиса из семи вызывается любой RPC с испорченным **своим** id

**Then** во **всех семи** ответ несёт `reason = "INVALID_RESOURCE_ID"` с `domain` этого сервиса
**And** текст остаётся прежним в каждом случае (byte-identical к базе `2e54f0e`)

#### Сценарий XC-1-04 (negative): чужой id формату НЕ проверяется — токена нет

**ID:** XC-1-04

**Якорь:** **U** `VPC-1-05` (foreign id **не** prefix-checked, только peer-validate existence)

**Given** конвенция B4: format-check — только own-owned id; чужой id проверяется существованием у
владельца

**When** `Instance.Create` с `zoneId = "!!!"` (чужой ресурс, владелец geo)

**Then** ответ **не** несёт `INVALID_RESOURCE_ID` — полоса чужая, ответ формируется peer-полосой
(XC-1-13/14/15)

> Задокументированное исключение (`api-conventions.md`): синтаксический gate на чужой ссылке nlb
> (`v4Source/v6Source.subnetId`/`.addressId`). Там `INVALID_RESOURCE_ID` **допустим** и обязателен —
> исключение записано в `services/nlb/docs/architecture/08-known-divergences.md`. Покрывается
> XC-1-05.

#### Сценарий XC-1-05 (edge): записанное исключение nlb — токен есть и он именно формата

**ID:** XC-1-05

**Якорь:** **E** `services/nlb/internal/apps/kacho/api/loadbalancer/foreign_vip_id_lane_test.go` → `TestCreateLB_Foreign{Subnet,Address}ID_Malformed_SyncFormatRejectWithoutPeer` и `…_TerminalEvenWhenOwnerUnavailable` (записанное исключение уже залочено — XC-1 добавляет assert детали)

**Given** nlb VIP-источники прогоняют чужой id через платформенный каталог префиксов (записанное
исключение)

**When** `LoadBalancer.Create` с `v4Source.subnetId = "явно-не-id"`

**Then** терминальный `INVALID_ARGUMENT` с `reason = "INVALID_RESOURCE_ID"`, `domain =
"nlb.kacho.cloud"`, `RT = "vpc.subnet"` — **не** `PEER_UNAVAILABLE` и **не** `RESOURCE_NOT_FOUND`
(смысл исключения: терминальный отказ вместо retryable/ложного промаха)

#### Сценарий XC-1-06 (negative): пустая обязательная ссылка — это не полоса формата

**ID:** XC-1-06

**Якорь:** **E** тот же файл → `TestCreateLB_Foreign{Subnet,Address}ID_Empty_RejectedAsMissingReference` (пустая обязательная ссылка уже отделена от полосы формата)

**Given** проверка формата пустую строку пропускает; required — отдельная ответственность

**When** мутация с обязательным полем-ссылкой, равным `""`

**Then** `INVALID_ARGUMENT "<field>: required"` **без** детали `ErrorInfo` (это валидация формы
запроса, не резолв идентификатора)
**And** ответ **не** содержит `"<res>  not found"` с вырезанным id

### 6.2 Полоса «свой промах» — `RESOURCE_NOT_FOUND` (S2-S4)

#### Сценарий XC-1-07: happy-negative — well-formed отсутствующий свой id на чтении

**ID:** XC-1-07

**Якорь:** **U** `VPC-1-04` (well-formed-но-нет → `NOT_FOUND`, direct-read lane) + `VPC-1-41` (гейтит **только** reason-token detail) · проекция registry — `REG-1-34`

**Given** `net-000000000000000` well-formed и не существует

**When** `NetworkService.Get` (`GET /vpc/v1/networks/net-000000000000000`)

**Then** `NOT_FOUND`, текст `"Network net-000000000000000 not found"` (не изменён)
**And** `ErrorInfo{reason: "RESOURCE_NOT_FOUND", domain: "vpc.kacho.cloud",
metadata: {resource_type: "vpc.network", resource_id: "net-000000000000000"}}`

#### Сценарий XC-1-08: leaf-владелец geo — direct-read промах (снимает `[PHASE-0-GATED]` GEO-1-35)

**ID:** XC-1-08

**Якорь:** **U** `GEO-1-35` (geo-direct read отсутствующего региона) · парная ветка — `GEO-1-34`

**When** `RegionService.Get` (`GET /geo/v1/regions/eu-west1`), регион отсутствует

**Then** `NOT_FOUND "Region eu-west1 not found"` (ungated, не изменён)
**And** `ErrorInfo{reason: "RESOURCE_NOT_FOUND", domain: "geo.kacho.cloud",
metadata: {resource_type: "geo.region", resource_id: "eu-west1"}}`
**And** токен — именно `RESOURCE_NOT_FOUND`, **а не** `REGION_NOT_FOUND` из устаревшей формулировки
GEO-1-34/35 (§2.6): специфика ресурса живёт в `resource_type`

#### Сценарий XC-1-10 (async, edge): не-полосовая ошибка операции деталь не получает

**ID:** XC-1-10

**Якорь:** **C** (worker/corelib: неклассифицированная ошибка операции — предшественника нет)

**Given** worker падает с неклассифицированной ошибкой (или паникой)

**When** клиент поллит операцию до `done`

**Then** `result.error.code == INTERNAL`, текст — фиксированный opaque (без pgx/SQL/хоста)
**And** `result.error.details` **не содержит** `ErrorInfo` (полосы нет; hardening-инвариант #1 не
ослаблен)

#### Сценарий XC-1-11: BOLA-guard отдаёт байт-идентичный промах — включая деталь

**ID:** XC-1-11

**Якорь:** E — `services/vpc/internal/apps/kacho/api/subnet/create.go` (оба guard'а), расширяется
существующий vpc-кейс на cross-project `networkId`

**Given** сеть `net-A` существует, но принадлежит **чужому** проекту. По коду BOLA-guard'а **два**,
и оба отдают тот же `NOT_FOUND "Network %s not found"`, что и промах на `:133`:
sync — `subnet/create.go:141-144` (после pre-flight `rd.Networks().Get`), и **async-backstop** —
после `w.Networks().GetForShare` (`:230`+) внутри writer-TX

**When** `SubnetService.Create` с `networkId = "net-A"` под принципалом другого проекта

**Then** ответ **байт-идентичен** ответу на несуществующий id: тот же код, тот же текст
**And** та же деталь `ErrorInfo{reason: "RESOURCE_NOT_FOUND", …, resource_id: "net-A"}` — по деталям
«существует, но не твоя» неотличимо от «не существует»
**And** **оба** guard'а несут одну и ту же деталь: sync-ветка проверяется вызовом, async-ветка —
удалением/сменой владельца сети между pre-flight и commit (иначе залочен один из двух путей, а
второй молча отдаёт 404 без детали — «форма без содержания» на половине сценария)

> **Дополнение круга 4.** Круг 3 называл один guard (`:137-144`). По коду их два, и async-backstop
> достижим ровно в той гонке, которую описывает XC-1-28, — поэтому он не «тот же код повторно», а
> второй наблюдаемый путь с собственным тестом.

#### Сценарий XC-1-12 (edge): один RPC, две полосы, две формы доставки — токены различны и корректны

**ID:** XC-1-12

**Якорь:** **U** `VPC-1-04` (sync-ветка) + `VPC-1-05` (async-ветка) — один RPC, два принятых id

**Given** `Subnet.Create` резолвит `networkId` **синхронно** (pre-flight, `create.go:129-136`), а
`projectId` — **асинхронно** (в worker)

**When** (а) вызов с отсутствующим `networkId`; (б) вызов с отсутствующим `projectId`

**Then** (а) синхронный ответ с `reason = "RESOURCE_NOT_FOUND"`, `RT = "vpc.network"`
**And** (б) `Operation.result.error` с `reason = "PEER_RESOURCE_MISSING"`, `RT = "iam.project"`,
`domain = "vpc.kacho.cloud"`
**And** решающая процедура клиента одинакова в обоих случаях — она читает деталь, а не форму доставки

### 6.3 Полоса «чужой промах / чужое состояние / недоступность» — `PEER_*` (S3-S4)

#### Сценарий XC-1-09 (async): чужой промах приходит в `Operation.result.error` с сохранёнными деталями

**ID:** XC-1-09

**Якорь:** **U** `VPC-1-05` (async peer-резолв `projectId`)
> **Исправление круга 2 (фактическое замечание №6): сценарий перенесён из §6.2 в §6.3 и токен назван
> явно.** Круг 2 помещал XC-1-09 в полосу «свой промах» (`RESOURCE_NOT_FOUND`), хотя его триггер —
> отсутствующий **`projectId`**, а `Project` принадлежит **iam**, то есть это **peer**-полоса.
> Проверено по коду: проверка проекта у `NetworkService.Create` живёт в
> `services/vpc/internal/apps/kacho/api/network/create.go`, функция `doCreate:216-221` (async
> worker-часть), и отдаёт `NOT_FOUND "Project %s not found"` на `:221`; синхронного precheck'а
> проекта на этом пути **нет** — он снят осознанно как race-prone (`subnet/create.go:117-122`).
> Круг 2 не называл токен, поэтому прямой лжи не было, но формулировка «та же деталь, что вернулась
> бы **синхронно**» опиралась на синхронную ветку, которой в коде не существует. Заменена на
> сверку с **той же полосой у того же consumer'а** — она достижима и синхронно (`Subnet.Create`
> pre-flight по `networkId`), и асинхронно, поэтому сравнение остаётся проверяемым, но больше не
> ссылается на контрфактическую ветку. Токен по D2 — **`PEER_RESOURCE_MISSING`**, как в XC-1-12(б).

**Given** мутация, чей резолв **чужого** идентификатора выполняется в worker-fn: `projectId`
намеренно асинхронен (`subnet/create.go:117-122` объясняет снятие sync-precheck; у
`NetworkService.Create` та же топология — `network/create.go` `doCreate:216-221`)

**When** клиент вызывает `NetworkService.Create` с несуществующим `projectId`, затем поллит
`OperationService.Get(id)` до `done == true`

**Then** `Operation.done == true`, `result.error.code` прежний (`NOT_FOUND` — off-lane, строка
храповика №4 §7.3), `result.error.message` прежний (`"Project <id> not found"`)
**And** `result.error.details` содержит ровно одну деталь
`ErrorInfo{reason: "PEER_RESOURCE_MISSING", domain: "vpc.kacho.cloud",
metadata: {resource_type: "iam.project", resource_id: "<projectId>"}}` — **не**
`RESOURCE_NOT_FOUND` (vpc не делает утверждения о своей БД) и **не** `domain = "iam.kacho.cloud"`
(D7, токен не отмывается)
**And** деталь, **прочитанная клиентом из операции**, побайтово равна детали, которую worker-fn
построил до записи, — сравниваются сериализованные `details` до и после round-trip через
`error_details` (это и есть предмет сценария: неопробованная механика §4.2)
**And** round-trip проверяется чтением операции **новым** соединением после рестарта воркера — то
есть деталь восстанавливается из хранилища, а не из памяти процесса
**And** сравнение **форм доставки** между собой сюда не входит — оно принадлежит XC-1-12, где обе
формы порождает **один и тот же** RPC (иначе сравнивались бы `domain` разных сервисов)

#### Сценарий XC-1-13: чужой ресурс отсутствует у владельца

**ID:** XC-1-13

**Якорь:** **U** `REG-1-16` (несуществующий `regionId` → peer-validate geo)

**Given** регион `eu-west1` не существует в geo

**When** `RegistryService.Create` с `regionId = "eu-west1"`

**Then** код и текст прежние (`FAILED_PRECONDITION`, `"region eu-west1 not found"`)
**And** `ErrorInfo{reason: "PEER_RESOURCE_MISSING", domain: "registry.kacho.cloud",
metadata: {resource_type: "geo.region", resource_id: "eu-west1"}}`

#### Сценарий XC-1-14: чужой ресурс есть, состояние не позволяет

**ID:** XC-1-14

**Якорь:** **E** `services/compute/internal/service/instance_nic_spec_placement_test.go` → `TestInstance_Create_NicSpecSubnetForeignZone_Rejected` / `…SameZone_OK`

**Given** подсеть `sub-…` (владелец vpc) существует и резолвится, но её зона не совпадает с зоной
инстанса (`services/compute/internal/service/instance.go:1031-1034` — placement-coherence на
request-path)

**When** `InstanceService.Create` с NIC-спекой на этой подсети

**Then** код и текст прежние: `FAILED_PRECONDITION`,
`"NetworkInterface subnet is in zone %s, instance zone is %s"`
**And** `ErrorInfo{reason: "PEER_RESOURCE_STATE", domain: "compute.kacho.cloud",
metadata: {resource_type: "vpc.subnet", resource_id: "<subnetId>"}}` — **не**
`PEER_RESOURCE_MISSING` (ресурс найден, не позволяет состояние)
**And** REGIONAL/anycast-ветка того же кода (`instance.go:1025-1027`,
`"… must be in the same region as the instance"`) несёт тот же токен

> Разграничение: `"Volume <id> is not ready"`
> (`services/storage/internal/repo/pg/snapshot_repo.go:193`) — **within-service** (storage владеет
> томами, резолв в своей БД), поэтому это **не** `PEER_RESOURCE_STATE`, а доменное предусловие
> (ось O-2). Полоса определяется линией резолва, а не похожестью формулировки.

#### Сценарий XC-1-15: владелец недоступен — мутация fail-closed, токен retryable

**ID:** XC-1-15

**Якорь:** **U** `REG-1-16` (ветка недоступности) + `STOR-1-11` (geo недоступен → `UNAVAILABLE` fail-closed)

**Given** geo недоступен (peer down / per-call deadline исчерпан)

**When** `RegistryService.Create` с валидным `regionId`

**Then** `UNAVAILABLE`, текст **дословно** прежний — `"region existence check unavailable"`
(`services/registry/internal/apps/kacho/api/registry/create.go:173`), без dial/endpoint-деталей
**And** `ErrorInfo{reason: "PEER_UNAVAILABLE", domain: "registry.kacho.cloud",
metadata: {resource_type: "geo.region", resource_id: "<regionId>"}}`
**And** это **единственный** токен, по которому клиенту предписано повторять запрос

> **Уточнение по коду (круг 1 обобщал сценарий неверно).** «Текст прежний» и «opaque» совпадают
> только там, где текст уже opaque. На семи сайтах vpc это **не так**:
> `services/vpc/internal/apps/kacho/api/{address:446,gateway:119,network:218,networkinterface:152,routetable:158,securitygroup:176,subnet:202}/create.go`
> возвращают `status.Errorf(codes.Unavailable, "project check: %v", err)` — **сырая ошибка peer'а
> интерполируется в сообщение клиенту** (hardening-инвариант #1). Требовать здесь одновременно
> «текст прежний» и «opaque» — противоречие: прежний текст **не** opaque. Разведено сценарием
> XC-1-42: на этих семи сайтах текст ветки `UNAVAILABLE` **меняется** на фиксированный opaque
> (D12, правило 3, шестая позиция в списке исключений аддитивности D6), и это единственное место,
> где XC-1 трогает текст.

#### Сценарий XC-1-16: паритет deny↔miss на пяти сайтах, которые его уже держат (регресс-лок)

**ID:** XC-1-16

**Якорь:** **E** `nlb/internal/clients/{iam,geo,compute}/…_test.go` (8+8+9 тестов), `registry/internal/clients/iam/iam_client_test.go` (5), `compute/internal/clients/storage_client_test.go` (10) · **две дыры**: файлов `compute/internal/clients/vpc_subnet_client_test.go` и `registry/internal/clients/geo/region_client_test.go` в дереве нет — создаются в S4/S3 (§7.4)

**Given** пять peer-сайтов, где `PermissionDenied` и `NotFound` владельца сведены в одну ветку —
`compute/internal/clients/vpc_subnet_client.go:66-69`,
`registry/internal/clients/geo/region_client.go:88-91`,
`registry/internal/clients/iam/iam_client.go:89`,
`nlb/internal/clients/compute/instance_client.go:150-153`,
`nlb/internal/clients/geo/region_client.go:127-132`

**When** для каждого из пяти выполняются два вызова: (а) чужой id, которого у владельца нет;
(б) чужой id, который у владельца есть, но доступ вызывающему не выдан

**Then** ответы (а) и (б) **байт-идентичны**: тот же код, тот же текст, те же сериализованные
`details` (сравнение полного тела, а не только кода)
**And** в обоих — `reason = "PEER_RESOURCE_MISSING"` с `domain` consumer'а и одинаковым
`metadata{resource_type, resource_id}`
**And** ни один ответ не содержит `PERMISSION_DENIED`, отношения FGA, субъекта или `deny_reasons`

> Сценарий ограничен пятью сайтами **намеренно**: на остальных пяти (§2.7) паритета сегодня нет, и
> утверждать его до фикса значило бы декларировать защиту поверх живого оракула. Их приводит к
> паритету XC-1-42, после чего XC-1-16 и XC-1-42 покрывают все десять.

#### Сценарий XC-1-42: пять сайтов без паритета приводятся к паритету (D12, правила 1 и 3)

**ID:** XC-1-42

**Якорь:** **E** те же пять клиентских тестовых файлов, что у XC-1-16 (+ два создаваемых)

**Given** пять сайтов, где сегодня deny и miss различимы наблюдателем (§2.7): compute→storage
`Volume`, nlb→iam `Project`, vpc→iam `Project`, compute→iam `Project`, compute→geo `Zone`

**When** для каждого выполняются два вызова — (а) чужой id, отсутствующий у владельца; (б) чужой id,
существующий у владельца, но недоступный вызывающему по правам

**Then** ответы (а) и (б) **байт-идентичны** — код, текст и сериализованные `details` совпадают
**And** код ответа (а) **не изменился** относительно базы `2e54f0e` ни на одном из пяти
(`NOT_FOUND` на четырёх, `INVALID_ARGUMENT` на compute→geo)
**And** ответ (б) больше **не** несёт `PERMISSION_DENIED` (compute→storage), `FAILED_PRECONDITION`
(nlb→iam) и `UNAVAILABLE` (vpc→iam, compute→iam, compute→geo)
**And** на семи файлах vpc текст ветки `UNAVAILABLE` (реальная недоступность iam) — фиксированный
opaque; ответ **не содержит** подстроки `"rpc error: code ="` ни при каком состоянии peer'а
**And** RED-половина TDD воспроизводится инъекцией: peer отвечает `PermissionDenied` → до фикса тела
ответов (а) и (б) различаются, после — совпадают

#### Сценарий XC-1-43 (negative, безопасность): `PERMISSION_DENIED` владельца не пересекает границу сервиса

**ID:** XC-1-43

**Якорь:** **E** `services/compute/internal/clients/storage_client_test.go` (10 тестов; XC-1 добавляет пару deny/miss)

**Given** `AttachDisk` авторизуется шлюзом по **инстансу**
(`proto/kacho/cloud/compute/v1/instance_service.proto:197-202` — `required_relation = v_update`,
scope на `instance_id`), а `volume_id` шлюзом **не** скоупится: единственный гейт по тому
обращается на стороне storage
(`proto/kacho/cloud/storage/v1/internal_volume_service.proto:33-38` — `required_relation = editor`,
scope на `volume_id`), и его `PERMISSION_DENIED` compute сегодня пробрасывает наружу дословно
(`services/compute/internal/clients/storage_client.go:205-207`)

**When** владелец инстанса вызывает `POST /compute/v1/instances/{instanceId}:attachDisk` с
`volumeId` **чужого существующего** тома, а затем с `volumeId` **несуществующего** тома

**Then** оба ответа **байт-идентичны** — код, текст и сериализованные `details` совпадают; паритет
утверждается **внутри самого `AttachDisk`** (сравниваются два ответа одного RPC), без обращения к
какому-либо другому RPC как к эталону
**And** ни один ответ не несёт кода `PERMISSION_DENIED` и не содержит текста, сформированного storage
**And** оба ответа несут `ErrorInfo{reason: "PEER_RESOURCE_MISSING", domain: "compute.kacho.cloud",
metadata: {resource_type: "storage.volume", resource_id: "<volumeId>"}}` — одинаковый в обоих
**And** ни один RPC не начал отвечать успехом там, где раньше отвечал отказом
**And** RED-половина воспроизводится инъекцией: storage отвечает `PermissionDenied` → до изъятия
`codes.PermissionDenied` из whitelist тела ответов различаются (`403` против `404`), после — совпадают

> **Блокирующее исправление круга 2.** Круг 2 требовал третьим Then, чтобы результат «совпадал с тем,
> что отдаёт прямой `GET /storage/v1/volumes/{volumeId}` на тот же том — обход скрытия существования
> через чужой RPC закрыт». **Утверждение неисполнимо ни до, ни после D12**, потому что прямой путь
> скрытия не даёт: у `kacho.cloud.storage.v1.VolumeService/Get` в каталоге `required_relation:
> "viewer"` и нет `hide_existence` ⇒ `HidesExistenceOnDeny` false ⇒ deny отдаёт `403`, а промах —
> `404 "Volume <id> not found"` (`services/storage/internal/repo/pg/errmap.go:62`). Требовать
> «свести `AttachDisk` к ответу прямого `Get`» значило бы требовать свести его к **протекающей
> паре ответов**. Целевое свойство переформулировано как **внутренний** паритет `AttachDisk` — оно
> самодостаточно, проверяется двумя вызовами одного RPC и не зависит от исхода #75. Исход прямого
> пути — O-8 → **#75**, пин текущего расхождения — XC-1-46.

#### Сценарий XC-1-46 (negative, безопасность): прямой storage-read различает deny и miss — расхождение зафиксировано и адресовано #75

**ID:** XC-1-46

**Якорь:** **E** `services/storage/tests/newman/cases/*.py` (51 строка с `403`) — пин расхождения; исход — **#75**

**Given** по коду прямой read-путь storage скрытия существования **не покупает**:
`kacho.cloud.storage.v1.{Volume,Snapshot,Image}Service/Get` несут `required_relation: "viewer"`
(не `v_get`) и не несут `hide_existence`
(`gateway/internal/middleware/embed/permission_catalog.json`, источник —
`proto/kacho/cloud/storage/v1/volume_service.proto:26`), поэтому `CatalogEntry.HidesExistenceOnDeny`
(`gateway/internal/middleware/permission_catalog.go:149-153`) для них **ложна**, и ни один
storage-тип не входит в 22 достижимых типа дрейф-гейта

**When** вызывающий без прав выполняет `GET /storage/v1/volumes/{id}` на **существующий чужой** том,
а затем на **несуществующий** том

**Then** ответы **различаются**: `403 PERMISSION_DENIED` против
`404 "Volume <id> not found"` (`services/storage/internal/repo/pg/errmap.go:62`) — это **живой
existence-oracle**, и XC-1 его **не закрывает и не заявляет закрытым**
**And** тест написан как **пин расхождения**: ожидаемая пара кодов вынесена в **одну именованную
константу**, помеченную как RED-цель **#75**, поэтому исправление в #75 обязано её перевернуть — а
до тех пор ни один рефакторинг не сдвинет поведение молча
**And** рядом с утверждением стоит ссылка на строку реестра §9.0 (O-8) и на задачу **#75** — «известное
расхождение с названным сроком», а не «так и задумано»
**And** XC-1 **не добавляет** ни одной storage-строки в `hideExistenceNotFoundFormats`: тип
недостижим, а дрейф-гейт проверяет только направление «достижим ⇒ отображён»
(`permission_denied_notfound_oracle_test.go:165-186`), поэтому такая строка была бы **мёртвым
кодом** (ban #11 / LEAN) и создавала бы ложное впечатление закрытой дыры
**And** оракул на **cross-RPC** поверхности (`AttachDisk`) при этом закрыт — XC-1-43; то есть после
XC-1 расхождение живёт ровно на одной поверхности вместо двух, и это проверяется обоими сценариями
сразу

#### Сценарий XC-1-44 (negative): полосы `PERMISSION_DENIED` в словаре нет и появиться не может

**ID:** XC-1-44

**Якорь:** **C** (гейт запрета сквозного `PERMISSION_DENIED`)

**Given** словарь закрыт пятью токенами (D2), а `PERMISSION_DENIED` на peer-границе устранён как
полоса (D12, правило 2)

**When** сканируется вся поверхность обоих листенеров всех семи сервисов

**Then** ни один peer-клиент не форвардит `codes.PermissionDenied` владельца наружу — гейт §7.1
падает с файлом и строкой при первой такой попытке
**And** гейт **доказан инъекцией**: возврат `codes.PermissionDenied` из любого peer-клиента делает CI
красным; изъятие — зелёным
**And** собственный отказ шлюза по правам (`AUTHZ_DENIED`) не затронут — он в своём namespace (O-3)

#### Сценарий XC-1-45: комментарий не заявляет паритета, которого нет (doc-truthfulness)

**ID:** XC-1-45

**Якорь:** **C** (doc-truthfulness трёх комментариев)

**Given** три комментария заявляют существующую защиту, которой в коде нет:
`nlb/internal/clients/iam/project_client.go:41-48` и `:142-144`
(«не лик'аем разницу… existence-hiding» — при разных кодах ответа) и
`vpc/internal/clients/iam_client.go:56-61` (рассуждение про утечку сырого peer-текста, покрывающее
`PermissionDenied`, но не включившее его в `case`)

**When** после фикса D12 проверяется соответствие комментария коду

**Then** каждый из трёх комментариев описывает **фактическое** поведение после фикса
**And** ни один комментарий в затронутых файлах не утверждает паритет/скрытие существования,
не подтверждённое тестом из XC-1-42 или XC-1-16 (`security.md` инвариант #5)
**And** проверка входит в общий DoD-пункт «комментарий не заявляет паритет с соседом без проверки
соседа» и подтверждается ссылкой на конкретный тест рядом с утверждением

#### Сценарий XC-1-17: одна полоса — три разных кода, один токен (регресс-лок §2.4)

**ID:** XC-1-17

**Якорь:** **U** `VPC-1-35` + `NLB-1-11` + `REG-1-16` (три принятых id, три разных кода, один токен) · **E** `compute/internal/service/maperr_test.go` → `TestMapZoneRefErr_*`

**Given** сегодня peer-miss возвращает `INVALID_ARGUMENT` (compute→geo `Zone`),
`NOT_FOUND` (vpc→iam `Project`), `FAILED_PRECONDITION` (registry→geo `region`)

**When** клиент вызывает каждую из трёх мутаций с несуществующей чужой ссылкой

**Then** **коды остаются разными** (XC-1 их не трогает — D6)
**And** во всех трёх случаях `reason == "PEER_RESOURCE_MISSING"` — клиент принимает **одно и то же**
решение, не глядя ни на код, ни на текст
**And** все три сайта перечислены в храповике off-lane (§7.3) как «как-эмитится ≠ канон»

#### Сценарий XC-1-18 (negative): чужой токен не отмывается

**ID:** XC-1-18

**Якорь:** **C** (правило D7 — предшественника нет)

**Given** geo вернул consumer'у статус с `ErrorInfo{reason: "RESOURCE_NOT_FOUND",
domain: "geo.kacho.cloud"}`

**When** consumer (compute) формирует свой ответ клиенту

**Then** ответ содержит **ровно одну** деталь `ErrorInfo` с `domain = "compute.kacho.cloud"` и
`reason = "PEER_RESOURCE_MISSING"`
**And** ответ **не содержит** ни одной детали с `domain`, отличным от `compute.kacho.cloud`
**And** ответ **не содержит** `reason = "RESOURCE_NOT_FOUND"` (это утверждение о своей БД, которого
consumer не делал)

### 6.4 Паритет hide-existence (S2-S4, атомарно по типу)

#### Сценарий XC-1-19: отказ шлюза байт-идентичен настоящему промаху — включая деталь

**ID:** XC-1-19

**Якорь:** **E** `gateway/internal/middleware/permission_denied_notfound_oracle_test.go` → `TestNotFoundMessage_NoFGATokenLeak`

**Given** ресурс `sub-XXXXXXXXXXXXXXXXX` существует, но вызывающему не выдан доступ; шлюз прячет
существование (`HidesExistenceOnDeny`)

**When** клиент вызывает `SubnetService.Get` по этому id

**Then** `404`, текст `"Subnet sub-XXXXXXXXXXXXXXXXX not found"` — как сегодня
**And** деталь `ErrorInfo{reason: "RESOURCE_NOT_FOUND", domain: "vpc.kacho.cloud",
metadata: {resource_type: "vpc.subnet", resource_id: "sub-XXXXXXXXXXXXXXXXX"}}`
**And** сериализованный ответ **байт-идентичен** ответу на несуществующий id того же типа
(сравнение всего тела, а не только кода)
**And** деталь **не содержит** `deny_reasons`, субъекта, действия, отношения FGA, FQN метода

#### Сценарий XC-1-20: паритет держится и на мутации, которую шлюз прячет

**ID:** XC-1-20

**Якорь:** **E** `gateway/internal/middleware/authz_registry_mutation_hide_existence_test.go` → `TestAuthz_GRPC_RegistryMutationDeny_OpaqueHideExistence`

**Given** `RegistryService.Update`/`Delete` помечены hide-existence (проверено:
`authz_registry_mutation_hide_existence_test.go`)

**When** вызывающий без права вызывает `RegistryService.Delete` по существующему чужому реестру

**Then** `404` с текстом `"Registry <id> not found"` и деталью `RESOURCE_NOT_FOUND`,
`RT = "registry.registry"`
**And** ни один из oracle-токенов (`deny_reasons`, `direct relations`, `lacks relation`) не
встречается ни в сообщении, ни в сериализованных деталях

#### Сценарий XC-1-21 (edge): неотображённый тип — поведение не изменилось

**ID:** XC-1-21

**Якорь:** **E** `permission_denied_notfound_oracle_test.go` → `TestNotFoundMessage_UnmappedTypeIsNeutral`

**Given** тип не покрыт таблицей соответствия либо scope-id отсутствует/wildcard

**When** шлюз отказывает с hide-existence

**Then** нейтральный `"not found"` **без** детали `ErrorInfo` — ровно как сегодня
**And** внутренний FGA-`object_type` (`vpc_subnet`, `registry_registry`, …) не появляется **ни в
тексте, ни в `metadata`** — ни при каких обстоятельствах
**And** CI роняется, если такой тип достижим через каталог (§7.2) — ветка остаётся аварийной

### 6.5 Проекции: REST, gRPC, оба листенера

#### Сценарий XC-1-22: REST-клиент получает деталь без специальной настройки

**ID:** XC-1-22

**Якорь:** **C** (REST-проекция детали — предшественника нет)

**When** клиент выполняет любой из негативов выше через `https://<edge>/vpc/v1/...`

**Then** тело — JSON с `code`, `message`, `details[]`
**And** в `details[]` есть объект с `"@type": "type.googleapis.com/google.rpc.ErrorInfo"`,
полями `reason`, `domain`, `metadata`
**And** HTTP-статус не изменился относительно базы `2e54f0e` для того же запроса

#### Сценарий XC-1-23: gRPC-клиент получает ту же деталь

**ID:** XC-1-23

**Якорь:** **C** (gRPC-проекция детали)

**When** тот же запрос выполняется gRPC-клиентом напрямую

**Then** `status.Details()` содержит `*errdetails.ErrorInfo` с теми же `reason`/`domain`/`metadata`
**And** значения совпадают с REST-проекцией символ-в-символ

#### Сценарий XC-1-24: internal-листенер (:9091) паритетен public

**ID:** XC-1-24

**Якорь:** **C** (паритет :9091 — предшественника нет)

**Given** `security.md`: правила public и internal одинаковы; internal не освобождён

**When** admin-RPC на `Internal*Service` (:9091) вызывается с испорченным/отсутствующим id

**Then** деталь `ErrorInfo` присутствует и построена по тем же правилам, что на :9090
**And** `metadata` **не содержит** инфра-чувствительных данных (host/placement/underlay/числовой
инфра-идентификатор) — только `resource_type` + `resource_id`

#### Сценарий XC-1-25: операция как ресурс — своя полоса

**ID:** XC-1-25

**Якорь:** **C** (полоса ресурса `Operation`, решение Q2)

**When** `OperationService.Get` с well-formed отсутствующим id операции

**Then** `NOT_FOUND` с прежним текстом
**And** `ErrorInfo{reason: "RESOURCE_NOT_FOUND", domain: "<svc>.kacho.cloud",
metadata: {resource_type: "<domain>.operation", resource_id: "<id>"}}`

### 6.6 Идемпотентность, стабильность, конкурентность

#### Сценарий XC-1-26 (идемпотентность): повтор даёт побайтово тот же токен

**ID:** XC-1-26

**Якорь:** **C**

**When** один и тот же отказной запрос повторяется трижды

**Then** `reason`, `domain`, `metadata` идентичны во всех трёх ответах
**And** порядок ключей `metadata` не влияет на решение клиента (map), но набор ключей строго один

#### Сценарий XC-1-27 (конкурентность): проигравший CAS не получает полосового токена

**ID:** XC-1-27

**Якорь:** **C**

**Given** две параллельные транзакции борются за attach/allocate; ровно одна выигрывает

**When** проигравшая получает `ALREADY_EXISTS` / `ABORTED` / `FAILED_PRECONDITION` из CAS с 0 строк

**Then** ответ **не содержит** `ErrorInfo` полосы (это исход конкуренции, а не резолв
идентификатора)
**And** победитель получает успех — семантика гонки не изменена

#### Сценарий XC-1-28 (edge, конкурентность): pre-flight прошёл, FK-backstop сработал

**ID:** XC-1-28

**Якорь:** **C** (гонка pre-flight ↔ FK-backstop; интеграционный тест новый, но поведение сверяется с базой `2e54f0e`)

**Given** `Subnet.Create` резолвит родительскую сеть **дважды**: sync pre-flight
(`services/vpc/internal/apps/kacho/api/subnet/create.go:129-136`, `rd.Networks().Get` →
`NOT_FOUND "Network %s not found"`) и повторно внутри writer-TX
(`:230` `w.Networks().GetForShare` + FK-backstop на commit)

**When** родительская сеть удалена **между** pre-flight и INSERT, и мутация доходит до commit,
получая 23503

**Then** `Operation.done == true`, `result.error.code` и `result.error.message` — те же, что маппер
даёт сегодня (сверка с базой `2e54f0e`)
**And** `result.error.details` содержит **ровно одну** деталь `ErrorInfo` — ветка «полоса неизвестна»
на этом пути **недостижима**, и на её недостижимость есть отдельный тест
**And** эта деталь **побайтово равна** детали, которую тот же вызов получил бы на pre-flight-промахе:
`reason = "RESOURCE_NOT_FOUND"`, `domain = "vpc.kacho.cloud"`,
`metadata = {resource_type: "vpc.network", resource_id: "<networkId>"}` — гонка не различима
клиентом от промаха
**And** сценарий проверяется интеграционно на реальном Postgres с конкурирующим удалением родителя
(не моком): без фикса деталь на 23503-пути отсутствует (RED), с фиксом — совпадает с
pre-flight-деталью (GREEN)

> Круг 1 формулировал Then как «**если** полоса известна в этой точке — деталь соответствует…».
> Предикат «полоса известна» нигде не определён, поэтому сценарий не мог быть провален ни при каком
> поведении кода — это утверждение без содержания. Заменено на безусловное: деталь обязана быть,
> обязана быть одна и обязана совпасть с pre-flight-веткой.

### 6.7 Границы и защита от тихой поломки

#### Сценарий XC-1-29 (BVA): испорченный id с невалидным UTF-8

**ID:** XC-1-29

**Якорь:** **C** (санитайзер UTF-8, D11)

**Given** `resource_id` обязан быть валидным UTF-8 (proto3 `map<string,string>`), иначе marshal
детали падает и деталь молча теряется (§D11)

**When** клиент присылает id с невалидными байтами

**Then** деталь **присутствует**, `metadata.resource_id` санирован до валидного UTF-8
**And** текст сообщения не изменён относительно базы
**And** ветка «деталь не собралась» недостижима — на неё есть отдельный тест

#### Сценарий XC-1-30 (BVA): очень длинный испорченный id

**ID:** XC-1-30

**Якорь:** **C** (предел длины, D11)

**When** клиент присылает id длиной 8 КБ

**Then** `metadata.resource_id` обрезан до фиксированного предела
**And** сериализованная деталь ≤ 256 байт
**And** текст сообщения остаётся прежним (аддитивность — обрезка только в `metadata`)

#### Сценарий XC-1-31 (BVA): `resource_id` пуст, когда ссылка выведена сервером

**ID:** XC-1-31

**Якорь:** **C** (id, выведенный сервером)

**Given** полоса сработала на идентификаторе, которого вызывающий **не присылал** (выведен сервером
— например авто-созданная таблица маршрутов)

**When** формируется деталь

**Then** `metadata` несёт `resource_type` и **не несёт** `resource_id`
**And** ни один серверный идентификатор, неизвестный вызывающему, наружу не попадает

#### Сценарий XC-1-32 (negative): `metadata` — закрытый набор ключей

**ID:** XC-1-32

**Якорь:** **C** (закрытый набор ключей `metadata`)

**When** проверяется любой ответ с полосовым токеном на любом из семи сервисов

**Then** `metadata` содержит **только** `resource_type` и (опционально) `resource_id`
**And** отсутствуют: субъект, проект, аккаунт, e-mail, метод/FQN, SQL, имя таблицы, имя хоста,
FGA-отношение, `deny_reasons`

#### Сценарий XC-1-33 (negative): полосовой токен не появляется на не-полосовых отказах

**ID:** XC-1-33

**Якорь:** **C** · смежные расхождения storage вынесены исходами: **#80** (`Snapshot.Create` — синхронной валидации нет вовсе) и **#81(а,б)** (поле сортировки принимается и игнорируется; зоны типа диска ничего не ограничивают) — XC-1 их **не** фиксирует как корректное поведение

**When** вызывается каждое из: `List` с испорченным `pageToken`; `List` с `pageSize = 1001`;
`Create` с пересекающимся CIDR; `Update` с immutable-полем в маске; `Update` с неизвестным полем в
маске; `Delete` непустой сети; создание дубля имени

**Then** коды и тексты — прежние
**And** ни один ответ **не содержит** `ErrorInfo` из полосового словаря

> **Граница «прежнее» ≠ «правильное» (уточнение круга 4).** На трёх storage-поверхностях «прежнее»
> поведение само является дефектом, и XC-1, фиксируя его неизменность, **не** объявляет его
> корректным: (а) `Snapshot.Create` **вообще не валидирует** `description`/`labels` синхронно —
> отказ приезжает в `op.error` и без имени поля, тогда как `Volume`/`Image` валидируют
> синхронно (исход — **#80**; критерий обязан **прямо предписывать синхронную валидацию на
> создании снимка**, а не отсылать «как на Create», потому что для снимка это сегодня «никак»);
> (б) поле порядка сортировки в `List` принимается и **молча игнорируется**, а объявленное
> умолчание не совпадает с фактическим; (в) зоны типа диска не ограничивают ничего (оба — **#81**).
> Ни один сценарий XC-1 не должен превратиться в regression-lock этих трёх состояний: assert'ы
> XC-1-33 утверждают **отсутствие полосового токена**, а не корректность кода/текста/формы доставки
> этих отказов.

#### Сценарий XC-1-34 (порядок): формат проверяется до отсечки по правам на чтении

**ID:** XC-1-34

**Якорь:** **C** (порядок format-validate → authz, `security.md` инв. #7)

**Given** `security.md` инвариант #7 и gotcha `api-conventions.md`: валидация формата — **до**
listauthz empty-grant short-circuit

**When** принципал без единого гранта вызывает `List` с испорченным `pageToken`, а затем `Get` с
испорченным id

**Then** `List` → `INVALID_ARGUMENT` (не `200 []`), `Get` → `INVALID_ARGUMENT` с
`INVALID_RESOURCE_ID`
**And** порядок не изменён введением деталей (деталь строится после решения, а не вместо него)

#### Сценарий XC-1-35 (negative): токен не подменяет и не ослабляет решение о доступе

**ID:** XC-1-35

**Якорь:** **C** (границы со словарём шлюза)

**Given** авторизация принимается моделью прав (каталог + per-object Check)

**When** запрос отвергается по правам не-hide-existence-путём

**Then** ответ — прежний `PERMISSION_DENIED` с существующим `AUTHZ_DENIED` шлюза
**And** полосовой `ErrorInfo` **отсутствует** — словари не пересекаются
**And** ни один RPC не начал отвечать успехом там, где раньше отвечал отказом

### 6.8 Наблюдаемость и стоимость

#### Сценарий XC-1-36: каждая эмиссия наблюдаема

**ID:** XC-1-36

**Якорь:** **C** (наблюдаемость, D9; ограничение объёма — **#76(в)**)

**When** сработала любая полоса

**Then** структурный лог несёт поле `error.reason` и `error.resource_type`
**And** счётчик сервиса инкрементирован по меткам `{reason, resource_type}`
**And** `resource_id` **не** попадает ни в метку метрики, ни в лог как отдельное PII-подобное поле
**And** мёртвая полоса (счётчик 0 за всё время жизни процесса при живом трафике) видна оператору

#### Сценарий XC-1-37 (производительность): успешный путь не платит

**ID:** XC-1-37

**Якорь:** **C** (бенчмарк)

**When** выполняется успешный `Get`/`List`/`Create`

**Then** ни одной аллокации на построение деталей (бенчмарк: 0 alloc на success-path)
**And** на отказном пути стоимость построения детали зафиксирована бенчмарком и не растёт при
повторных прогонах (регресс-порог)
**And** деталь строится **один раз на RPC** — не в цикле по элементам страницы

### 6.9 Гейты дрейфа (проверяются как поведение, а не как наличие файла)

#### Сценарий XC-1-38: новый RPC с id-аргументом без токена роняет CI

**ID:** XC-1-38

**Якорь:** **C** (гейт §7.1)

**Given** статический гейт запрещает конструировать полосовой статус в обход corelib-конструкторов

**When** в любой сервис добавляется RPC, который отвергает id «голым» `status.Errorf` c
`NOT_FOUND`/`FAILED_PRECONDITION`/`UNAVAILABLE`/malformed-`INVALID_ARGUMENT`

**Then** гейт падает с указанием файла и строки
**And** гейт **доказан инъекцией реального дефекта**: воспроизведён такой вызов — гейт красный;
вызов переведён на конструктор — зелёный (без инъекции гейт не принимается)

#### Сценарий XC-1-39: канонический список полос не может устареть молча

**ID:** XC-1-39

**Якорь:** **C** (гейт §7.2)

**Given** канонический перечень «место эмиссии → полоса → токен → `resource_type`» — версионируемый
артефакт (идиома репо: `permission-catalog-check`, `rest-route-table-check`)

**When** добавлена/удалена/переименована точка эмиссии без обновления перечня

**Then** staleness-гейт падает (diff перечня против сканирования дерева)
**And** тот же гейт падает при неизвестном токене (словарь закрыт, D2) и при `resource_type` вне
общего словаря (D4)

#### Сценарий XC-1-40: храповик off-lane может только сокращаться

**ID:** XC-1-40

**Якорь:** **C** (гейт §7.3)

**Given** список сайтов «как-эмитится ≠ канон» (§7.3), зафиксированный по §2.4

**When** появляется новый сайт, где код полосы расходится с каноном

**Then** CI падает — список не может вырасти
**And** удаление строки из списка допускается только вместе с изменением кода на канонический
**And** пустой список означает, что XC-2 завершён

#### Сценарий XC-1-41: таблица шлюза покрывает все скрываемые типы вместе с `resource_type`

**ID:** XC-1-41

**Якорь:** **E** `permission_denied_notfound_oracle_test.go` → `TestHideExistenceMap_CoversCatalogReachableTypes` (гейт существует; XC-1 расширяет его требованием `resource_type`)

**Given** существующий дрейф-гейт таблицы hide-existence выводит множество типов из встроенного
каталога прав

**When** новый ресурс становится object-scoped, но `resource_type` для него не задан

**Then** CI падает — «тип достижим, соответствия нет»
**And** ни один такой тип не уходит в нейтральный fallback незамеченным

---

## 7. Механизмы принуждения (детализация)

### 7.1 Что именно проверяет статический гейт

Живёт в `internal/repohygiene` — уже существующий дом репо-широких гигиенических гейтов (там же
`license_test.go`, `execbit_test.go`, `newmanvars_test.go`). Сканирует `services/**` и `gateway/**`,
находит конструирование статуса с полосовым кодом, и требует, чтобы источником был
corelib-конструктор либо запись в перечне §7.2. Разрешённые исключения перечислены поимённо, а не
паттерном.

### 7.2 Канонический перечень полос

Версионируемый артефакт, сверяемый с деревом. Содержит: сервис, файл, полоса, токен,
`resource_type`, форма доставки (sync/op). Сравнение — как у `permission-catalog-check`:
сгенерировать → сравнить с закоммиченным → падать на расхождении.

### 7.3 Храповик off-lane (перечень §2.4)

**Стартовый состав — 8 полос / 14 файловых строк.** Единица храповика — **файл** (решение Q3),
поэтому нормативна вторая цифра; первая приводится, чтобы обе были сверяемы против §2.4.

| # | Полоса | Файл(ы) | Строк | Эмитируемый код | Канон |
|---|---|---|---|---|---|
| 1 | compute→geo `Zone` | `services/compute/internal/service/maperr.go:93,96` | 1 | `INVALID_ARGUMENT` | `FAILED_PRECONDITION` |
| 2 | compute→iam `Project` | `services/compute/internal/service/project_check.go:34` | 1 | `NOT_FOUND` | `FAILED_PRECONDITION` |
| 3 | **compute→storage `Volume`** | `services/compute/internal/clients/storage_client.go:205-207` | 1 | `NOT_FOUND` | `FAILED_PRECONDITION` |
| 4 | vpc→iam `Project` | `services/vpc/internal/apps/kacho/api/{address,gateway,network,networkinterface,routetable,securitygroup,subnet}/create.go` | **7** | `NOT_FOUND` | `FAILED_PRECONDITION` |
| 5 | nlb→compute `Instance` | `services/nlb/internal/clients/compute/instance_client.go:151,153` | 1 | `INVALID_ARGUMENT` | `FAILED_PRECONDITION` |
| 6 | nlb→geo `Region` | `services/nlb/internal/clients/geo/region_client.go:129,132` | 1 | `INVALID_ARGUMENT` | `FAILED_PRECONDITION` |
| 7 | nlb→iam `Project` | `services/nlb/internal/clients/iam/project_client.go:139-140` | 1 | `NOT_FOUND` | `FAILED_PRECONDITION` |
| 8 | registry→iam `project` | `services/registry/internal/apps/kacho/api/registry/create.go:156` | 1 | `INVALID_ARGUMENT` | `FAILED_PRECONDITION` |
| | **Итого** | | **14** | | |

Строка несёт: сайт, полосу, эмитируемый код, канонический код, ссылку на XC-2-issue. Гейт: список
не растёт; строка удаляется только вместе с приведением кода к канону.

**Три оговорки, без которых храповик был бы неверен:**

1. **Состав сверяется с §2.4 автоматически**, а не переписывается вручную: гейт S1 сравнивает
   14 строк перечня с 14 off-lane-строками таблицы §2.4 и падает на расхождении. Причина —
   именно та ошибка круга 1: перечень и таблица разъехались (девять строк / семь ✗ / «восемь сайтов»),
   и разъехались они потому, что расхождение никто не считал.
2. **Строка №3 добавлена в круге 2** — в круге 1 ребро `compute → storage` отсутствовало в §2.4 и в
   храповике, хотя присутствовало в DoD S4 того же документа. Без него «пустой список означает, что
   XC-2 завершён» (XC-1-40) было бы **ложным утверждением**: список опустел бы при живом off-lane-сайте.
3. **D12 строк не удаляет.** Фикс паритета deny↔miss меняет ветку отказа по правам и не трогает код
   ветки промаха, поэтому off-lane-статус сайтов №1-№4, №7 сохраняется, и их строки остаются до XC-2.
   Это проверяется тестом: после D12 код ответа на **промах** байт-в-байт равен базе `2e54f0e`.

---

### 7.4 Прослеживаемость: сценарий ↔ Go-тест ↔ newman-кейс (двусторонняя, гейтенная)

Круг 1 ввёл 41 идентификатор `XC-1-NN`, не связанный ни с одним тестом и ни с одним кейсом — третье
изолированное пространство имён. Круг 2 довёл их до 45, круг 3 — до **46**. Круг 4 закрывает саму
причину претензии, а не её симптом.

#### Правило якоря (нормативно): `XC-1-NN` — указатель, а не новое пространство имён

**Каждый** из 46 id обязан нести строку `**Якорь:**` (проверено: 46 из 46). Якорь — **один**, кроме
сценариев, кросс-сервисных по построению (XC-1-03, XC-1-12, XC-1-15, XC-1-17): у них якорь —
**набор** принятых id, и в матрице покрытия каждый даёт **свою** строку, иначе «покрыт частично»
было бы неотличимо от «покрыт». Id, который не может назвать ни принятого id, ни существующего
артефакта, — **не сценарий XC-1**: он принадлежит доку своего владельца и заводится там.

- **U — ungate.** Сценарий снимает `[PHASE-0-GATED]` с **уже принятого** id владельца. Тогда
  **первичным ключом прослеживаемости остаётся id владельца** (`# verifies GEO-1-35`,
  `Test…_GEO_1_35_…`), а `XC-1-NN` живёт **только** в этом документе как перекрёстная ссылка. Новое
  имя в тестах/кейсах не заводится — иначе одно и то же утверждение получило бы два ключа, и
  «покрыто ли оно» перестало бы иметь однозначный ответ.
- **E — extend.** Сценарий расширяет **существующий** тест/кейс утверждением о детали. Первичный
  ключ — имя уже существующей функции/кейса; XC-1 добавляет в неё `assert`, а не заводит спутник.
- **C — corelib/gate.** Утверждение о corelib-помощнике, санитайзере или о самом гейте — у него нет
  ресурса-владельца и нет предшественника. **Только** такие сценарии получают собственное имя, в
  **уже принятой** семейной форме `Test…_XC_1_NN_…` (та же, что `TestInstance_COMP_1_33_ZoneReject`,
  `TestIntegration_Instance_COMP_1_30_ConcurrentNameRace`) — это ветка существующей конвенции
  `<SUBPHASE>_<NN>`, а не третье пространство.

**Якоря класса U — принятые id, проверенные по докам в круге 4** (цитаты — из самих доков, не из памяти):

| Якорь (принятый id) | Что он уже утверждает | Сценарии XC-1, ссылающиеся на него |
|---|---|---|
| `VPC-1-03` | wrong-prefix id → sync `INVALID_ARGUMENT "invalid network id '…'"` первым стейтментом | XC-1-01, XC-1-02 |
| `VPC-1-04` | well-formed-но-нет → `NOT_FOUND "Network … not found"` (direct-read lane) | XC-1-07 |
| `VPC-1-05` | foreign `projectId` **не** prefix-checked, только peer-validate existence; код `[PHASE-0-GATED]` | XC-1-04, XC-1-09, XC-1-12(б) |
| `VPC-1-35` | несуществующий `zoneId` → peer-validate geo; **код и токен** gated | XC-1-17 |
| `VPC-1-41` | гейтит **только reason-token detail**, не код (прямо оговорено в доке) | XC-1-07 |
| `GEO-1-34` | Zone.Create с отсутствующим `regionId` → `NOT_FOUND "Region … not found"` + reason (gated) | XC-1-08 (парная ветка) |
| `GEO-1-35` | geo-direct read отсутствующего региона → `NOT_FOUND` + reason (gated) | XC-1-08 |
| `NLB-1-11` | несуществующий `regionId` → peer-validate geo; AS-IS `INVALID_ARGUMENT`, target gated | XC-1-17 |
| `REG-1-16` | явный несуществующий `regionId` → отказ peer-validate geo | XC-1-13, XC-1-15 |
| `REG-1-31` | malformed namespace id → `INVALID_ARGUMENT` первым стейтментом | XC-1-03 |
| `REG-1-34` | Create под несуществующим namespace → `NOT_FOUND` (direct-read lane) | XC-1-07 (проекция registry) |
| `STOR-1-05` | malformed volume id → `INVALID_ARGUMENT`; well-formed-нет → `NOT_FOUND` | XC-1-01, XC-1-03 |
| `STOR-1-11` | неизвестная зона → peer-validate reject; geo недоступен → `UNAVAILABLE` fail-closed | XC-1-15 |
| `COMP-1-22` | malformed instance id → `INVALID_ARGUMENT` first-statement; well-formed-нет → `NOT_FOUND` | XC-1-01, XC-1-03 |

**Якоря класса E — существующие тесты, проверенные наличием в дереве:**

| Существующий артефакт | Сценарий |
|---|---|
| `gateway/…/permission_denied_notfound_oracle_test.go` → `TestNotFoundMessage_NoFGATokenLeak` | XC-1-19 |
| там же → `TestNotFoundMessage_UnmappedTypeIsNeutral` | XC-1-21 |
| там же → `TestHideExistenceMap_CoversCatalogReachableTypes` | XC-1-41 |
| `gateway/…/authz_registry_mutation_hide_existence_test.go` → `TestAuthz_GRPC_RegistryMutationDeny_OpaqueHideExistence` | XC-1-20 |
| `services/compute/internal/service/instance_nic_spec_placement_test.go` → `TestInstance_Create_NicSpecSubnetForeignZone_Rejected` / `…SameZone_OK` | XC-1-14 |
| `services/compute/internal/service/maperr_test.go` → `TestMapZoneRefErr_{NotFound_InvalidArgument, GeoNotFoundStatus_InvalidArgument, GeoDown_Unavailable}` | XC-1-17, XC-1-42 (ветка compute→geo) |
| `services/{nlb/internal/clients/{iam,geo,compute},registry/internal/clients/iam,compute/internal/clients}/…_test.go` (8+9+10+5+10 тестов) | XC-1-16, XC-1-42 |
| `services/nlb/…/loadbalancer/foreign_vip_id_lane_test.go` → `TestCreateLB_Foreign{Subnet,Address}ID_Malformed_SyncFormatRejectWithoutPeer`, `…_TerminalEvenWhenOwnerUnavailable` | XC-1-05 |
| там же → `TestCreateLB_Foreign{Subnet,Address}ID_Empty_RejectedAsMissingReference` | XC-1-06 |
| там же → `TestCreateLB_Foreign{Subnet,Address}ID_WellFormedAbsent_PeerLaneNotOwnNotFound` | XC-1-04 (контроль: чужой id не получает own-полосу) |
| `services/storage/tests/newman/cases/*.py` — **51** строка с `403` | XC-1-46 (пин) |

> **Две дыры класса E названы, а не обойдены:** тестовых файлов
> `services/compute/internal/clients/vpc_subnet_client_test.go` и
> `services/registry/internal/clients/geo/region_client_test.go` в дереве **нет** — то есть два из
> пяти «паритетных» сайтов XC-1-16 сегодня не залочены вообще. Их создание входит в S4 и S3
> соответственно и является **частью** XC-1 (регресс-лок на существующее поведение), а не
> follow-up: сайт, чей паритет утверждается, но ничем не проверяется, — «проверка с формой без
> содержания».

**Что это меняет в нумерации.** Нумерация остаётся **append-only** (id не переиспользуются и не
сдвигаются), но она больше не является пространством имён **тестов**: в имя Go-функции и в
`# verifies` уезжает **якорь**, а `XC-1-NN` — только в этот документ и в отчёт покрытия.
Распределение по классам (читается из строк `**Якорь:**`, 46 из 46):
**U — 11** (01, 02, 03, 04, 07, 08, 09, 12, 13, 15, 17);
**E — 12** (05, 06, 11, 14, 16, 19, 20, 21, 41, 42, 43, 46);
**C — 23** (10, 18, 22…40 без 41, 44, 45).
Класс C — **единственный**, где `XC_1_NN` появляется в имени теста, и ни один из этих сценариев не
дублирует чужой id: у каждого либо нет ресурса-владельца (corelib, санитайзер, проекция), либо нет
предшественника (сам гейт). Итоговое распределение сверяется генерируемой колонкой
`XC-1-COVERAGE.md`; **гейтом является наличие и разрешимость якоря, а не его класс**.
XC-1-09 в круге 3 перенесён между разделами (§6.2 → §6.3) с сохранением номера — именно потому,
что append-only относится к номеру, а не к месту в тексте.

**Идиома 1 — Go-тест несёт id в имени функции.** В дереве это уже принято:
`TestIntegration_Instance_COMP_1_30_ConcurrentNameRace`,
`TestIntegration_Instance_COMP_1_37_DeleteNameRecycle`, `TestInstance_SEC_D_04_…`,
`Test_1_4_31_FailClosedBootGate_…`, `TestInstance_COMP_1_33_ZoneReject`. Конвенция XC-1: имя несёт
**якорь**, а не `XC-1-NN` по умолчанию — `Test…_GEO_1_35_…` для класса U, уже существующее имя для
класса E (в него добавляется `assert`), и **только** для класса C — `Test…_XC_1_NN_<Slug>`. Один
сценарий может иметь несколько тестов (разные сервисы/слои) — все несут один и тот же якорь.

**Идиома 2 — newman-кейс несёт id в аннотации.** В дереве **256** вхождений (`# verifies ` — 249,
`// verifies ` — 7) на голове `b892cd8`; на базе `2e54f0e` — **251** (244 + 7). Напр.
`services/geo/tests/newman/cases/authz-deny.py:29` — `# verifies GEO-1-21`. Конвенция XC-1:
над кейсом стоит `# verifies <якорь>` — **id владельца** для класса U (`# verifies GEO-1-35`),
существующая аннотация для класса E (в кейс добавляется assert детали), и `# verifies XC-1-NN`
**только** для класса C. Case-id с сегментом `XCR` (`SUB-XCR-VAL-MALFORMED`, `NET-XCR-NEG-NOTFOUND`)
заводится **только** там, где кейса ещё нет — то есть тоже преимущественно в классе C; расширение
существующего кейса его case-id **не меняет** (переименование сорвало бы ссылки из индексов суит).

> **Исправление круга 2 (фактическое замечание №1) + разбор расхождения с ревьюером.** Круг 2 писал
> «242 вхождения» — число не воспроизводится ни одним шаблоном; исправлено. Ревьюер круга 2 привёл
> **256** на `b892cd8` (совпало) и **262** на `2e54f0e` — второе **не воспроизводится**: командой
> `git grep -hoE "(#|//) verifies " 2e54f0e | wc -l` получается **251**, и то же значение даёт
> раздельный подсчёт по строкам (`git grep -c "# verifies " 2e54f0e` → 244, `"// verifies "` → 7).
> На `b892cd8` обе методики дают 256, то есть многострочных совпадений в дереве нет и расхождение
> методикой не объясняется. Вывод ревьюера (идиома существует и её достаточно) от этого не меняется;
> в документ внесены **воспроизводимые** числа вместе с командой, чтобы следующий круг сверял
> прогоном, а не памятью.

**Зависимость от суит-инфраструктуры — сведена к нулю намеренно.** Гейт прослеживаемости XC-1
опирается **только** на две вещи, которые есть во всех семи суитах by construction: имя Go-функции и
комментарий `# verifies XC-1-NN` в `.py`-кейсе. Ни `validate-cases.py`, ни `docs/TAXONOMY.md`, ни
`docs/CASES-INDEX.md` для него **не требуются**.

> **Блокирующее исправление круга 2 (DoD опирался на несуществующие артефакты).** Круг 2 требовал
> «case-id по таксономии своей суиты (`docs/TAXONOMY.md` сервиса)» и «`validate-cases.py` зелёный во
> всех 7 суитах». По дереву эти артефакты есть не везде:
>
> | суита | `scripts/validate-cases.py` | `docs/CASES-INDEX.md` | `docs/TAXONOMY.md` |
> |---|---|---|---|
> | compute | **нет** | есть | есть |
> | geo | есть | есть | есть |
> | iam | **нет** | **нет** | **нет** |
> | nlb | есть | есть | есть |
> | registry | есть | есть | **нет** |
> | storage | есть | есть | **нет** |
> | vpc | есть | есть | есть |
>
> Итого: валидатор — в **5** суитах, индекс — в **6**, таксономия — в **4**. Требование «во всех 7»
> было неисполнимо и, что важнее, тянуло в XC-1 работу по стандартизации харнесса, которой не
> владеет ни одна из стадий S1-S5. **Решение:** (а) DoD сужен до суит, где артефакт существует
> (регистрация case-id — в 6 суитах с индексом; `validate-cases.py` — в 5, где он есть); (б)
> сегмент `XCR` и форма case-id заданы **этим документом** и потому применимы во всех семи
> независимо от наличия таксономии; (в) сам пробел не «отмечен», а вынесен в **O-9** с критерием
> приёмки и передан уже идущей работе по стандартизации тестового харнесса семи сервисов — он
> предшествует XC-1 по природе (это харнесс, а не полоса отказа) и блокировать XC-1 не должен.

**Гейт двусторонней полноты** (новый, живёт рядом с прочими в `internal/repohygiene`, идиома
`permission-catalog-check`: сгенерировать → сравнить с закоммиченным → упасть на расхождении).
Источник истины — **этот документ**: гейт парсит из него все строки `**ID:** XC-1-NN` **вместе с их
строкой якоря** (`**Якорь:** U GEO-1-35` / `E <файл>::<TestName>` / `C`) и строит матрицу покрытия
против дерева. Падает в **пяти** случаях:

0. **сценарий без якоря:** у `XC-1-NN` нет строки `**Якорь:**` либо якорь класса U называет id,
   которого нет ни в одном доке `docs/specs/*-acceptance.md`, либо якорь класса E называет
   несуществующий файл/функцию. Это и есть механическая защита от «третьего пространства имён»:
   новый id **невозможно** завести, не привязав его к принятому id или к существующему артефакту;
1. **сценарий → тест:** для якоря нет ни одной Go-функции с соответствующим сегментом в имени
   (`_GEO_1_35_` для U, точное имя для E, `_XC_1_NN_` для C);
2. **сценарий → newman:** для якоря нет ни одного `# verifies <якорь>` (кроме сценариев,
   помеченных в матрице `no-newman:` с письменной причиной — она печатается в отчёте, поэтому
   «тихо не покрыт» невозможно; допустимо только для гейтов CI, у которых нет HTTP-поверхности:
   XC-1-38/39/40/41/44);
3. **тест → сценарий:** имя функции содержит `_XC_1_NN_`, которого нет среди id документа
   (защита от опечатки в номере — иначе тест «покрывает» несуществующий сценарий);
4. **newman → сценарий:** `# verifies XC-1-NN` с номером, которого нет в документе.

**Отчёт покрытия** (`XC-1-COVERAGE.md`, генерируемый, коммитится) — таблица «сценарий → **якорь** →
Go-тесты → newman-кейсы», по строке на каждый из **46** id, с итоговой строкой «U/E/C: n/n/n».
Именно она делает DoD наблюдаемым: «сколько из скольки» читается из артефакта, а не заявляется в
тексте PR.

**Почему id, а не «полоса»:** покрытие по полосам (как было в DoD круга 1) закрывается пятью кейсами
на сервис и оставляет непрослеживаемым, покрыт ли конкретный сценарий — в том числе edge-сценарии,
ради которых они и написаны (XC-1-12 две формы доставки, XC-1-28 гонка, XC-1-31 выведенный сервером
id, XC-1-43 внутренний паритет `AttachDisk`, XC-1-46 пин прямого storage-пути). Полоса остаётся
**дополнительным** измерением отчёта, не заменой.

---

## 8. Definition of Done

Формулировки — наблюдаемые: назван прогон, назван набор, названо «сколько из скольки». Пункт,
который нельзя предъявить артефактом, в DoD не входит.

### Общий (все стадии)

- [ ] **Покрытие сценариев — 46 из 46, и у 46 из 46 разрешимый якорь.** `XC-1-COVERAGE.md` (§7.4)
      не содержит ни одной строки со статусом «нет теста» и ни одной с пустым/неразрешимым якорем
      (класс U — id, реально присутствующий в доке владельца; класс E — существующие файл и
      функция/кейс). Строк со статусом «нет newman» — ровно 5, и это в точности
      XC-1-38/39/40/41/44 (гейты CI, HTTP-поверхности не имеют), каждая с печатаемой причиной.
      Гейт двусторонней полноты зелёный по всем **пяти** направлениям (включая нулевое — «сценарий
      без якоря»), и направление 0 **доказано инъекцией**: сценарий с якорем `U GEO-1-99`
      (несуществующий id) → красный.
- [ ] **TDD**: для каждого из **46** сценариев и каждого из **четырёх** гейтов §7 (§7.1 статический,
      §7.2 канонический перечень, §7.3 храповик, §7.4 прослеживаемость) в отчёте по стадии приведена
      пара RED → GREEN (команда, вывод «FAIL … / ok …»). Заявление о готовности без обеих половин
      не принимается.
      > Круг 2 писал «трёх гейтов §7», хотя §7 определяет четыре и DoD S1 сам перечислял «три +
      > гейт прослеживаемости» — внутреннее расхождение счёта, исправлено на **четыре** во всех
      > пунктах DoD.
- [ ] **Аддитивность доказана прогоном, а не утверждением**: скрипт сверки гоняет корпус негативов
      против базы `2e54f0e` и текущего дерева, сравнивая `(код, текст)` — **0 расхождений** на всех
      негативах, **кроме** ровно шести поимённых позиций списка исключений D6 (пять deny-веток §2.7 +
      текст ветки `UNAVAILABLE` на семи файлах vpc). Список исключений задан **именами сайтов**;
      расхождение по сайту вне списка роняет прогон.
- [ ] **Регрессия утверждает И токен, И код** — на каждом покрытом негативе: `assert code == …`
      **и** `assert reason == …` **и** `assert domain == …` **и** `assert metadata == {…}`. Тест,
      проверяющий только код, считается непокрывающим (`testing.md`: regression на уровне обсервабла).
- [ ] **newman — вердикт из отчёта, а не из строки «GREEN»**: в каждом из 7 сервисов — ≥1 кейс на
      каждую полосу, применимую к этому сервису, читающий `details[]` из тела; ≥1 кейс,
      утверждающий **отсутствие** `ErrorInfo` на не-полосовом отказе. Наблюдаемый критерий:
      `services/<svc>/tests/newman/scripts/run.sh` → для **каждого** ожидаемого stem существует
      `out/<stem>.json` и в нём `.run.stats.assertions.failed == 0` при `out/<stem>.rc == 0`
      (именно так считает `aggregate_verdict`, `run.sh:83-108`; отсутствие отчёта = `MISSING` =
      красный, а не «пропущено»). Базовые объёмы суит на `b892cd8` — compute 10, geo 7, iam 31,
      nlb 10, registry 5, storage 9, vpc 16 case-файлов; XC-1 добавляет к ним кейсы класса C и
      assert'ы деталей в существующие (§7.4), поэтому «сколько из скольки» читается из
      `XC-1-COVERAGE.md` + сводки `aggregate_verdict`, а не из текста PR.
      Каждый кейс несёт `# verifies <якорь>` (единственное требование, исполнимое во всех 7 суитах)
      и — если кейс новый — case-id с сегментом `XCR`. Регистрация в `docs/CASES-INDEX.md` — в
      **6** суитах, где индекс существует (все, кроме iam). `tests/newman/scripts/validate-cases.py`
      зелёный в **5** суитах, где он существует — **geo, nlb, registry, storage, vpc**; в compute и
      iam скрипта нет, и его создание в XC-1 **не входит** (O-9).
      > Круг 2 требовал «`validate-cases.py` зелёный во всех 7 суитах» — неисполнимо: скрипта нет в
      > `services/compute/tests/newman/scripts/` и `services/iam/tests/newman/scripts/`. Приведено
      > к дереву; пробел вынесен в O-9 с критерием приёмки.
- [ ] **Полный прогон, не `-short`**: `GOWORK=off go test ./... -race` из корня `project/kacho`
      (`-short` скрывает testcontainers-интеграции, а round-trip детали через
      `Operation.error_details` и гонка XC-1-28 проверяются только там). Плюс `golangci-lint run`,
      `govulncheck`.
      > **`GOWORK=off` — часть команды, а не совет.** Проверено запуском: без него **любой**
      > `go test` в этом дереве падает **до компиляции** —
      > `directory gateway/internal/middleware is contained in a module that is not one of the
      > workspace modules listed in go.work` → `FAIL [setup failed]`. Причина — `project/go.work`
      > воркспейса, не перечисляющий модуль монорепо (в CI single-repo checkout, go.work нет,
      > поэтому там команда работает как записана). Контроль на образце:
      > `GOWORK=off go test ./gateway/internal/middleware/ -run
      > 'TestHideExistenceMap_CoversCatalogReachableTypes|TestNotFoundMessage' -count=1` → `ok …
      > 0.011s` (без `GOWORK=off` — `FAIL [setup failed]`). Отчёт стадии, приводящий «зелёный»
      > прогон без этого префикса, предъявляет **не выполненную** команду.
- [ ] **Гейты репо — командами, которые ИСПОЛНЯЮТСЯ, и артефактами, которые НАБЛЮДАЮТ**
      (корневого `Makefile` в репо нет; всё — из корня `project/kacho`):
      - `GOWORK=off make -C gateway permission-catalog-check` (`gateway/Makefile:67`) →
        `OK: build/permission_catalog.json (357 entries)` + `permission catalog is complete and both
        copies are in sync.`;
      - `GOWORK=off make -C gateway rest-route-table-check` (`gateway/Makefile:94`) →
        `REST route table is complete and in sync with proto.`;
      - `make -C services/{compute,nlb,storage,vpc} audit-list-filter` → `audit-list-filter: OK`
        (**4** сервиса, ровно набор CI-шага `.github/workflows/ci.yaml:230`);
      - `GOWORK=off go test ./services/storage/tools/ -run TestAuditListFilter -count=1` — **это и
        есть** артефакт, наблюдающий гейт storage внутри `go test` (`tools/audit_list_filter_test.go`,
        `TestAuditListFilter` + `TestAuditListFilter_RealTreePasses`).
      > **Исправление круга 4 (обе команды круга 3 не исполнялись как записано).**
      > (а) **`GOWORK=off` обязателен**, и это не косметика: в дереве workspace существует
      > `project/go.work`, не перечисляющий модули плагинов шлюза, поэтому
      > `make -C gateway permission-catalog-check` **падает** ещё до сравнения —
      > `directory cmd/protoc-gen-kacho-permissions is contained in a module that is not one of the
      > workspace modules listed in go.work`, и `make` возвращает ошибку. В CI go.work нет, поэтому
      > там та же цель зелёная (`ci.yaml:199-201`, `working-directory: gateway`) — расхождение
      > local-vs-CI, из-за которого круг 3 записал команду, ни разу её не запустив.
      > (б) **registry изъят из набора**: цель `audit-list-filter` там объявлена, но её тело —
      > `@echo "audit-list-filter: реализуется вместе с RegistryService.List (rpc-implementer)"`
      > (`services/registry/Makefile:46-47`), скрипта `tools/audit-list-filter.sh` в дереве нет,
      > exit-код всегда `0`. Круг 3 включил registry как «надмножество исполнимых наборов» — по
      > факту это **проверка с формой без содержания**: она зелёная при любом состоянии кода.
      > Фильтрация у registry при этом **есть** (`internal/handler/listauthz.go`, ссылки в
      > `internal/apps/kacho/api/registry/registry.go:88,323`) — то есть заглушка скрывает не дыру в
      > фильтрации, а **отсутствие гейта на неё**. Исход — **#81(в)** («команда гейта не исполняется
      > из корня и не вызывается в CI»); критерий закрытия — §9, реестр исходов.
      > **Исправление круга 2 (тот же класс, что круг 2 исправил у круга 1).** Круг 2 писал «для
      > всех 7 сервисов (как в `.github/workflows/ci.yaml:231-232`)» — **неисполнимо**: цель
      > `audit-list-filter` объявлена в `services/{compute,nlb,registry,storage,vpc}/Makefile` и
      > **отсутствует** в `services/geo/Makefile` и `services/iam/Makefile` (`make` завершится
      > «No rule to make target»). Процитированный CI-шаг при этом перебирает **4** сервиса
      > (`.github/workflows/ci.yaml:230` — `for svc in compute nlb storage vpc`), а его собственное
      > имя (`:226`) гласит «(4 сервиса)». В DoD взят **надмножественный из двух исполнимых**
      > наборов — 5 сервисов с объявленной целью (он строго покрывает CI-шаг); расширение до geo/iam
      > потребовало бы завести цель, а это работа харнесса, не полосы отказа (O-9).
- [ ] Ни одного TODO/FIXME/SKIP в добавленном коде и тестах (ban #11/#13).
- [ ] Комментарии описывают **реальное** поведение (`architecture.md` doc-truthfulness): в
      частности, ни один комментарий не заявляет паритет с соседом без проверки соседа — проверено
      на трёх известных экземплярах (XC-1-45) и не введено новых.

### S1

- [ ] Словарь из пяти токенов; шестой невозможен без правки правила (гейт красный при инъекции
      шестого литерала).
- [ ] Конструкторы владеют парой (код, токен) неразрывно; носитель проходит sentinel-слои
      (`errors.As`) — тест на цепочку `fmt.Errorf("%w: …")` длиной ≥2.
- [ ] Санитайзер UTF-8 + предел длины; ветка «деталь не собралась» недостижима (тест).
- [ ] **`pkg/restype` (D4)**: набор покрывает все типы, встречающиеся в **46** сценариях, плюс
      `<домен>.operation` для 7 доменов. Гейты, все доказаны инъекцией:
      (а) каждый из **28** ключей `services/iam/internal/authzmap/fga_types.go:232-290` имеет ровно
      одну запись `pkg/restype` (биекция в обе стороны); (б) первый сегмент `Value` == поле `Owner`
      на **каждой** записи; (в) эмиссия `resource_type`, равного `CatalogKey` записи, **у которой
      `CatalogKey != Value`**, роняет сборку — это ровно **8** значений
      (`loadbalancer.networkLoadBalancers|targetGroups|listeners`,
      `registry.registries|repositories`, `storage.volumes|snapshots|images`), перечисленных
      таблицей D4; остальные **20** ключей каноничны, совпадают с `Value` и в запрещающий набор
      **не входят by construction** — инъекция обязана показать это в обе стороны: эмиссия
      `storage.volumes` → красный, эмиссия `vpc.subnet` (канонический ключ и одновременно
      wire-литерал XC-1-01/19) → **зелёный**; (г) `Owner` ∈
      {compute, geo, iam, nlb, registry, storage, vpc} — 7 значений, совпадающих с первым сегментом
      REST-пути.
      > Круг 2 формулировал (в) как «равного ключу каталога» без квалификатора — гейт краснел бы на
      > 20 из 28 ключей, включая литералы собственных сценариев. Исправлено по
      > `fga_types.go:232-290`.
- [ ] Приёмник наблюдаемости: интерфейс в corelib + реализация в **семи** сервисных
      `internal/observability/metrics`, из которых **пять существуют** (compute, geo, iam, nlb, vpc)
      и **два создаются в S1** (registry, storage). **Наблюдаемое утверждение — через ручку, а не
      через пакет**: после срабатывания полосы тело `GET <metricsAddr>/metrics` процесса содержит
      серию счётчика с метками `{reason, resource_type}` — 7 процессов из 7 (тест адаптера каждого
      сервиса + один e2e-скрейп на стенде). Формулировка «пакет создан» **не принимается**: у
      storage порт уже слушается и `/metrics` уже объявлен в конфиге, а `mux` регистрирует только
      `/healthz` (`cmd/storage/serve.go:326-349`) — то есть «пакет есть, скрейп 404» является
      достижимым состоянием и было бы ровно «формой без содержания».
      **Ограничение объёма:** XC-1 доводит до раздачи **свою** серию; общий дефект «ручка объявлена,
      процесс её не отдаёт» — задача **#76(в)**, и XC-1 её не подменяет (§9, реестр исходов).
- [ ] Шесть реализаций формата id сведены; `INVALID_RESOURCE_ID` наблюдаем во всех семи сервисах
      (7 из 7 — включая geo/iam/storage, которые `pkg/validate.ResourceID` не вызывают вовсе).
- [ ] **Четыре** гейта (§7.1 статический, §7.2 канонический перечень, §7.3 храповик,
      §7.4 прослеживаемость) существуют и **доказаны инъекцией дефекта**: воспроизведён реальный
      дефект → красный; исправлен → зелёный. Гейт, для которого инъекция не показана, не
      принимается (`checks-with-form-but-no-substance`).
- [ ] **Учёт исходов — по реестру §9, без изобретения номеров.** (а) Пункты, у которых задача
      **уже заведена** (**#75** — прямой read-путь storage; **#76(в)** — объявленная, но не
      раздаваемая ручка метрик; **#80** — синхронная валидация `Snapshot.Create`; **#81(в)** —
      неисполняемый гейт), в S1 **не заводятся заново**: первым коммитом S1 в тело каждой из них
      добавляется комментарий со ссылкой на соответствующую строку §9 и её критерий, а номера
      проставляются в `obsidian/kacho/KAC/KAC-XC-1.md`. (б) Пункты **без** задачи (O-1/XC-2,
      O-2/XC-3, O-6/XC-4, O-7, O-9) — заводятся первым коммитом S1 с критерием приёмки из §9 и
      метками `tech-debt`/`security` + `blocked:` XC-1; их номера проставляются в §9 и KAC-trail тем
      же коммитом. Наблюдаемое утверждение: для **каждой** строки реестра §9 колонка «исход» несёт
      либо существующий номер, либо номер, созданный этим коммитом — пустых клеток ноль, а
      `gh issue view <N>` открывает issue с тем же критерием. Закрытие — только code-артефактом
      (`git-issues.md`, issue-lifecycle discipline).
- [ ] Бенчмарк: 0 alloc на success-path; порог на отказном пути; потолок детали 256 Б.

### S2 (geo + iam)

- [ ] `RESOURCE_NOT_FOUND` на direct-read обоих сервисов, оба листенера.
- [ ] Строки шлюза для `account`, `project`, `iam_user`, `iam_group`, `iam_service_account`,
      `iam_access_binding` — **в том же изменении** (D8).
- [ ] Round-trip детали через `Operation.error_details` доказан на реальном Postgres
      (testcontainers), включая чтение после рестарта воркера.
- [ ] Байт-паритет deny↔miss на всех типах S2 (сравнение полного тела).

### S3 (vpc + storage)

- [ ] Своя полоса + чужие полосы (→ geo, iam): `PEER_RESOURCE_MISSING` и `PEER_UNAVAILABLE`.
- [ ] Строки шлюза для **`vpc_*`** (`vpc_network`, `vpc_subnet`, `vpc_address`, `vpc_route_table`,
      `vpc_security_group`, `vpc_gateway`, `vpc_network_interface` — 7 из 7 достижимых) — в том же
      изменении (D8). **Storage-типов в этом пункте нет.**
      > **Блокирующее исправление круга 2 (аддитивность / мёртвый код).** Круг 2 писал «строки шлюза
      > для `vpc_*` и storage-типов». Строка для storage-типа **не даёт ничего**: типы
      > `storage_volume|snapshot|image` **не достижимы** через `HidesExistenceOnDeny` (у их `/Get`
      > `required_relation: "viewer"`, флага `hide_existence` нет — см. §2.7), а дрейф-гейт
      > `TestHideExistenceMap_CoversCatalogReachableTypes` проверяет **только** направление
      > «достижим ⇒ отображён» (`permission_denied_notfound_oracle_test.go:165-186`), поэтому
      > недостижимая строка не ловится **ничем** и остаётся мёртвой (ban #11 / LEAN) — да ещё и
      > создаёт впечатление закрытой дыры. Чтобы строки заработали, каталог должен пометить
      > storage-RPC как hide-existence, а это смена наблюдаемого кода `403 → 404` на публичной
      > поверхности — её **нет** ни в шести поимённых исключениях аддитивности (D6), ни в скрипте
      > сверки «0 расхождений (код, текст) против базы `2e54f0e`». **Решение принято явно: пункт
      > снят из XC-1**, седьмым исключением аддитивности он **не объявляется**, а исход прямого
      > storage-пути закреплён за **#75** (§9.0, O-8) с критерием приёмки; текущее расхождение
      > зафиксировано пином XC-1-46.
- [ ] Правило «не отмывать» проверено интеграционно: vpc→iam промах не выносит `domain=iam…`.
- [ ] **D12 для vpc (1 сайт, 7 файлов)**: `vpc → iam Project` — deny сведён в ветку miss
      (`NOT_FOUND`), текст ветки `UNAVAILABLE` переведён на фиксированный opaque; ответ не содержит
      подстроки `"rpc error: code ="` ни при каком состоянии iam. XC-1-42 зелёный по vpc-части;
      комментарий `services/vpc/internal/clients/iam_client.go:56-61` приведён к коду (XC-1-45).

### S4 (compute + nlb + registry)

- [ ] Своя полоса + все чужие рёбра: compute→{geo, iam, vpc, storage}; nlb→{geo, iam, vpc, compute};
      registry→{geo, iam}.
- [ ] `PEER_RESOURCE_STATE` приземляется здесь (compute→vpc placement-coherence, XC-1-14) — это
      единственная полоса, чей носитель живёт в S4; до S4 она не эмитируется нигде и это отражено
      в каноническом перечне §7.2 (полоса не считается покрытой, пока не покрыта).
- [ ] Строки шлюза для достижимых типов S4: `compute_disk`, `compute_image`, `compute_instance`,
      `compute_snapshot`, `nlb_network_load_balancer`, `nlb_listener`, `nlb_target_group`,
      `registry_registry` (8 из 8 достижимых по каталогу) — в том же изменении.
- [ ] Записанное исключение nlb (XC-1-05) даёт именно `INVALID_RESOURCE_ID`.
- [ ] **D12 для compute и nlb (4 сайта из 5)**: `compute→storage Volume`, `compute→iam Project`,
      `compute→geo Zone`, `nlb→iam Project` — deny байт-в-байт равен miss (XC-1-42 зелёный по
      этим четырём); `codes.PermissionDenied` изъят из whitelist
      `services/compute/internal/clients/storage_client.go:205-206`; **XC-1-43 зелёный, и его
      утверждение — внутренний паритет `AttachDisk`** (два вызова одного RPC), **без** сверки с
      прямым `GET /storage/v1/volumes/{id}`: тот путь скрытия не покупает и сам протекает (§2.7,
      пин XC-1-46, исход — O-8 → **#75**). Комментарии
      `services/nlb/internal/clients/iam/project_client.go:41-48,142-144` приведены к коду (XC-1-45).
- [ ] **XC-1-46 зелёный**: пин прямого storage-пути на месте, ожидаемая пара кодов вынесена в
      именованную константу-RED-цель **#75**, ссылка на задачу #75 стоит рядом с утверждением, и в
      `hideExistenceNotFoundFormats` **не добавлено** ни одной storage-строки (проверяется тем же
      тестом: `grep`-утверждение об отсутствии ключей с префиксом `storage_` в таблице).
- [ ] Ребро `compute → storage` покрыто как полноправная peer-полоса: `RT = "storage.volume"`,
      `domain = "compute.kacho.cloud"`, строка храповика №3 на месте (код промаха не изменён).

### S5 (сквозная сверка)

- [ ] `domain` шлюза нормализован (`gateway.kacho.cloud`); словари не пересекаются.
- [ ] Храповик off-lane заморожен ровно на составе §7.3 — **8 полос / 14 файловых строк**; гейт
      сверки перечня с таблицей §2.4 зелёный; каждая из 14 строк несёт XC-2-issue с номером.
- [ ] `api-conventions.md` дополнен пунктом «как-эмитится vs канон» + ссылкой на храповик
      (иначе правило описывает несуществующую реальность — `security.md` инвариант #5).
- [ ] **Девять** acceptance-доков (поимённый список — §2.6) перенаправлены с ад-хок токенов
      (`REGION_NOT_FOUND`, `NETWORK_NOT_FOUND`, `NAMESPACE_NOT_FOUND`, `PROJECT_NOT_FOUND`) на
      пятитокенный словарь + `resource_type`; метки `[PHASE-0-GATED]` на reason-token сняты во всех
      девяти. Проверка: `grep -rl "PHASE-0-GATED" docs/specs/` не возвращает ни одного файла,
      где метка стоит на reason-token (метки на других осях остаются).
      > **Снимается ровно половина гейта — токен, не код.** У части принятых сценариев
      > (`GEO-1-34`, `VPC-1-35`, `NLB-1-11`, `REG-1-16`) одна и та же метка `[PHASE-0-GATED]` держит
      > **две** вещи: reason-token **и** by-lane-код (`AS-IS INVALID_ARGUMENT`/`NOT_FOUND` → target
      > `FAILED_PRECONDITION`). XC-1 аддитивен (D6) и снимает **только** токен; кодовая половина
      > остаётся под гейтом и переезжает на храповик §7.3 (исход — XC-2, реестр §9.0). Поэтому S5
      > правит формулировку метки на «`[GATED: код — XC-2]`», а не удаляет её целиком: сплошное
      > удаление объявило бы приземлившимся изменение кода, которого XC-1 не делает, и следующий
      > контрибьютор «починил» бы код под неверную запись (`security.md` инв. #5). У `VPC-1-41`
      > метка гейтит **только** токен — там она снимается целиком.
- [ ] `reference.proto` несёт ссылку на `pkg/restype` как на источник истины значений `type`
      (D4); заведён issue O-7 на приведение `serviceAccountRefType` с критерием приёмки.
- [ ] e2e: REST и gRPC-native проекции совпадают символ-в-символ (XC-1-22/23).
- [ ] vault-trail: `KAC/KAC-XC-1.md`; обновлены `packages/kacho-corelib-errors.md`,
      `packages/kacho-corelib-validate.md`, затронутые `edges/*` (полоса ошибок — часть контракта
      ребра); при отсутствии — созданы узкие записки 1-3 КБ.

---

## 9. Out-of-scope (с обоснованием)

### 9.0 Реестр исходов — у каждого открытого пункта есть номер и критерий

Правило: **ни один пункт не остаётся без исхода.** «Осознанно не сделано», «зафиксировано»,
«расхождение» — все три формулировки одинаково обязаны нести (а) номер **уже заведённой** задачи
либо явную пометку «задачи ещё нет — завести», и (б) критерий закрытия **одной фразой**.
Номера, которых нет в трекере, здесь **не выдумываются**: пометка «нет номера» — сама по себе
исход (обязательство завести первым коммитом S1, DoD S1).

| Пункт документа | Что открыто | Исход | Критерий закрытия (одной фразой) |
|---|---|---|---|
| **O-8** (§2.7 п.1, XC-1-46) | прямой `GET /storage/v1/{volumes,snapshots,images}/{id}` различает «нет доступа» (`403`) и «нет объекта» (`404`) — живой existence-oracle | **#75** (STOR-AUTHZ-2) — **не новая под-фаза**: чинится тем же переводом каталога storage на `v_get`/Design-B, которым владеет #75 | внутрисервисная карта прав зеркалит каталог (проверено во всех семи сервисах), и на трёх storage-read-RPC ответ на deny **байт-идентичен** ответу на miss |
| **D9 / DoD S1** (наблюдаемость) | storage объявляет `/metrics` (`config.go:44-46`), а `mux` регистрирует только `/healthz` (`serve.go:326-349`) — скрейпить нечего | **#76(в)** | `GET :9095/metrics` живого процесса storage возвращает непустой ответ со счётчиками, а не 404 |
| **§2.4 / §7.3** (храповик off-lane) | 8 полос / 14 файловых строк эмитируют не-канонический код | **задачи нет — завести (XC-2)** | перечень §7.3 пуст, и ни одна peer-полоса не отвечает кодом, отличным от канона таблицы D2 |
| **O-2** (доменные предусловия) | `ZONE_NOT_OPEN`, `CAPACITY_UNAVAILABLE`, `NAMESPACE_NAME_IS_GLOBAL`, `ROLE_DOES_NOT_COVER_TYPE` — вторая ось токенов, не покрыта | **задачи нет — завести (XC-3)** | у второй оси есть собственное пространство имён, правило версионирования и политика раскрытия, а её токены не пересекаются с пятитокенным словарём полосы |
| **O-6** (форма доставки) | у async-мутаций deny приходит sync-`404`, а miss — `200 + op.error`: различимы формой | **задачи нет — завести (XC-4)** | для каждой мутации с `HidesExistenceOnDeny` и async-резолвом deny и miss неразличимы **по форме доставки**, что проверяется newman-кейсом на каждую такую мутацию |
| **O-7** (`serviceAccountRefType`) | `iam.service_account` (snake_case) — форма, не совпадающая ни с одной другой в дереве | **задачи нет — завести** | `reference.Referrer.type` во всех эмитирующих сайтах принимает значения только из `pkg/restype`, а гейт роняет сборку на литерале вне набора |
| **O-9** (харнесс newman) | `validate-cases.py` нет в compute/iam; `CASES-INDEX.md` нет в iam; `TAXONOMY.md` нет в iam/registry/storage | **задачи нет — завести** (принадлежит уже идущему потоку стандартизации харнесса семи сервисов, не XC-1) | три артефакта существуют во всех 7 суитах, `validate-cases.py` зелёный 7 из 7 и **краснеет при инъекции** дублирующегося case-id |
| **DoD (гейты)** | цель `audit-list-filter` у registry — echo-заглушка (скрипта нет, exit всегда 0), CI перебирает 4 сервиса из 5 объявленных | **#81(в)** | цель registry исполняет реальную проверку, вызывается CI, и **краснеет при инъекции** снятого listauthz-фильтра |
| **XC-1-33 / D2** (не-полосовые отказы) | у `Snapshot.Create` валидация `description`/`labels` **вообще не выполняется синхронно** — отказ приходит в `op.error` и без имени поля, в отличие от `Volume`/`Image` | **#80** | `Snapshot.Create` **синхронно** отвергает невалидные `description`/`labels` с `INVALID_ARGUMENT` и именем поля — критерий предписывает синхронную валидацию **на создании снимка** прямо, а не отсылкой «как на Create» (для снимка это сегодня «никак») |
| **XC-1-33** (List-негативы) | у storage поле порядка сортировки принимается и молча игнорируется, объявленное умолчание неверно; зоны типа диска ничего не ограничивают | **#81(а,б)** | принятое поле либо действует, либо отвергается `INVALID_ARGUMENT`; объявленное умолчание совпадает с фактическим; зоны типа диска ограничивают размещение |
| **D12 / §«межсервисное намерение»** | дренаж storage классифицирует отказ в правах как **временный** — строка не помечается отправленной и блокирует свою партицию | **#76(б)** | отказ в правах классифицирован терминально, и очередь регистраций storage не имеет партиции, заблокированной повторами |
| **§2.6** (доки владельцев) | 9 acceptance-доков ссылаются на ад-хок токены под ресурс; `api-conventions.md` описывает цель, а не реальность | **входит в XC-1**, стадия S5 | ни в одном доке метка `[PHASE-0-GATED]` не стоит на reason-token, а `api-conventions.md` несёт пункт «как-эмитится vs канон» со ссылкой на храповик |
| **§2.7 / D12** (паритет peer) | 5 сайтов из 10 различают deny и miss наблюдателем | **входит в XC-1**, стадии S3/S4 | XC-1-42 зелёный на всех пяти: тела ответов на deny и на miss байт-идентичны |
| **§7.4** (две дыры регресс-лока) | нет тестовых файлов `compute/internal/clients/vpc_subnet_client_test.go` и `registry/internal/clients/geo/region_client_test.go` — два «паритетных» сайта не залочены ничем | **входит в XC-1**, стадии S4/S3 | оба файла существуют и падают при инъекции `PermissionDenied`, расходящегося с `NotFound` |
| **D4 / D5** (`CatalogEntry`) | поля `resource_type` и `domain` объявлены в `CatalogEntry` (`permission_catalog.go:70-76`), но **пусты во всех 357** записях каталога — мёртвая пара, одноимённая с ключами `metadata` XC-1 | **задачи нет — завести** (LEAN, ban #11; читаемостная ловушка: одноимённые поля с разным смыслом — `networks` против `vpc.network`) | поля либо заполняются генератором и используются, либо удалены из структуры и из генератора; одноимённость с `metadata`-ключами XC-1 снята комментарием или переименованием |
| **O-3, O-4, O-5** | границы области (authz-токены, локализация, нормализатор шлюза) | **долгом не являются** — решения, а не отложенная работа | пересмотр требует правки `api-conventions.md` (governance), а не задачи в трекере |

> Строки «входит в XC-1» — не исключение из правила, а его вырожденный случай: их исход — **сам
> XC-1**, а критерий проверяется его же DoD. Строки с номерами задач в XC-1 **не** выполняются:
> документ обязан их назвать и не подменять собой.

**O-1. Приведение off-lane кодов к канону (XC-2).** **8 полос / 14 файловых строк** §2.4 (перечень —
§7.3; кардинальность сходится с таблицей по счёту, а не по памяти). Это **ломающее** изменение
поверхности (`404 → 400` там, где `NOT_FOUND` уступает место `FAILED_PRECONDITION`), затрагивающее
UI и newman-суиты всех сервисов. Выносится, потому что: (а) XC-1 без него **полностью выполняет
свою задачу** — клиент получает решающую процедуру; (б) порядок «токен → коды» строго безопаснее
обратного (D6); (в) не отпускается на самотёк — храповик §7.3 не даёт списку расти и не даёт забыть,
каждая строка несёт issue.
- **Учёт: задачи с таким номером в трекере нет — завести** (первым коммитом S1; номер проставляется
  в реестр §9.0 и в каждую из 14 строк §7.3).
- **Критерий приёмки XC-2.** Перечень §7.3 пуст: ни одна peer-полоса не эмитирует код, отличный от
  канона таблицы D2, и ответ на промах каждого из 14 сайтов сверен с базой `2e54f0e` **осознанно
  изменённым**, а не совпавшим случайно.

**O-2. Токены доменных предусловий** (`ZONE_NOT_OPEN`, `CAPACITY_UNAVAILABLE`,
`NAMESPACE_NAME_IS_GLOBAL`, `ROLE_DOES_NOT_COVER_TYPE` из GEO-1/REG-1/IAM-1). Это **вторая ось**:
не «как резолвится идентификатор», а «какое доменное правило нарушено». Смешивать их с полосовым
словарём нельзя — он потеряет свойство закрытости и перестанет быть решающей процедурой (D2).
Требует собственного governance-решения: пространство имён, правила версионирования, политика
раскрытия (часть предусловий инфра-чувствительна — `security.md`). Отдельная под-фаза XC-3.
- **Учёт: задачи с таким номером в трекере нет — завести** (первым коммитом S1).
- **Критерий приёмки XC-3.** У второй оси есть собственное пространство имён с правилом
  версионирования и политикой раскрытия, её токены **не пересекаются** с пятитокенным словарём
  полосы, и гейт §7.2 роняет сборку при попытке эмитировать доменный токен как полосовой.

**O-3. Токены на пути авторизации.** `AUTHZ_DENIED`/`AUTHN_REQUIRED` шлюза уже существуют и живут в
своём namespace. XC-1 их не расширяет и не переносит в сервисы: решение о доступе принимает модель
прав, и дробить его на сервисные токены значило бы плодить вторую систему поверх работающей
(`security.md`, директива владельца 2026-07-27).

**O-4. Локализация сообщений** (`LocalizedMessage`). `pkg/errors` умеет, но по умолчанию не
добавляет — осознанное существующее решение. Токен делает локализацию **возможной** на клиенте
(клиент сам подбирает текст по `reason`), и это ровно тот выигрыш, ради которого прозу можно больше
не парсить. Серверная локализация — отдельное продуктовое решение.

**O-5. Нормализатор ответов на шлюзе.** Рассмотрен в D8 и отвергнут как scope creep: секундное
rolling-окно против превращения шлюза в переписыватель ответов.

**O-6 → под-фаза XC-4. Асимметрия формы доставки «мутация: deny = sync 404 vs miss = 200 + `op.error`».**
Обнаружена при проверке §2.5: для мутаций, чей резолв ушёл в worker
(`services/vpc/internal/apps/kacho/api/subnet/create.go:117-122` — sync-precheck проекта снят
намеренно, `NOT_FOUND` уезжает в `doCreate:200-205`), отказ по правам приходит **синхронным** `404`
от шлюза, а настоящий промах — `200` с ошибкой **внутри** операции. Различие в **форме доставки**
делает их различимыми независимо от того, насколько идентичны код, текст и деталь.

Почему **не** внутри XC-1: это не полоса и не деталь, а форма доставки — чинится либо возвратом
резолва в sync-preflight (что было снято осознанно, как race-prone: тот же файл, комментарий
`:117-122`), либо переводом hide-existence-отказа мутации в ту же async-форму. Оба варианта меняют
поведение шлюза или контракт `Operation` — радиус, несовместимый с аддитивным XC-1.

**Это не «отмечено», а вынесено в названную под-фазу XC-4 с критерием приёмки:**
- **Критерий приёмки XC-4.** Для **каждой** мутации, помеченной `HidesExistenceOnDeny`, чей резолв
  идентификатора выполняется в worker: ответ на «объект существует, доступа нет» и ответ на
  «объекта нет» **неразличимы по форме доставки** — либо оба синхронные с байт-идентичным телом,
  либо оба `200 + Operation`, у которых `result.error` байт-идентичен (код, текст, `details`).
  Проверяется newman-кейсом на каждую такую мутацию (перечень строится из каталога, не вручную) +
  гейтом «мутация с `HidesExistenceOnDeny` и async-резолвом обязана иметь такой кейс».
- **Что делает XC-1 уже сейчас, чтобы XC-4 не деградировал:** XC-1-12 фиксирует, что **деталь**
  идентична в обеих формах доставки, а XC-1-09 — что она переживает round-trip через
  `Operation.error_details`. То есть к моменту XC-4 остаётся закрыть ровно форму, а не содержимое.
- **Учёт: задачи с таким номером в трекере нет — завести.** GitHub Issue (`bug`, `security`,
  `blocked:` XC-1) заводится **первым коммитом S1**; номер в тот же коммит проставляется в
  `obsidian/kacho/KAC/KAC-XC-1.md`, в реестр §9.0 и сюда. Гейт — **пункт DoD S1** («у каждой строки
  реестра §9.0 непустая колонка исхода, `gh issue view <N>` открыт, критерий приёмки внутри»), а
  **не** переход этого документа в APPROVED. Issue закрывается только code-артефактом
  (`git-issues.md`, issue-lifecycle discipline).
  > **Блокирующее исправление круга 2 (самоналоженное предусловие было циркулярным — снято явным
  > решением).** Круг 2 записал «номер проставляется в этот раздел **до перевода документа в
  > APPROVED**». Это предусловие **неисполнимо by construction**, и не из-за забывчивости: по
  > ban #1 и `ai-tooling.md` §lifecycle gate 1 acceptance-док получает APPROVED **до** старта любой
  > работы, а issue — артефакт работы (он заводится в S1). Получается кольцо: документ нельзя
  > одобрить, пока не начата S1, и S1 нельзя начать, пока документ не одобрен. Круг 2 сам себе
  > поставил условие, которое мог бы выполнить только нарушив gate 1.
  > **Решение (не смягчение, а перенос гейта туда, где он исполним):** требование не отменяется и не
  > ослабляется — оно становится **пунктом DoD S1** с наблюдаемым артефактом (`gh issue view <N>`
  > возвращает открытый issue с критерием приёмки) и записью в KAC-trail. Тем самым исход у пункта
  > есть (заведённая задача с номером и критерием), ответственный назван (S1), а проверка
  > предъявляется прогоном, а не обещанием. Номер физически не может стоять в тексте до начала S1 —
  > его подставляет тот же коммит, который заводит issue.

**O-7. Приведение `serviceAccountRefType` к канону `pkg/restype`.** `services/compute/internal/protoconv/protoconv.go:25`
эмитит `reference.Referrer.type = "iam.service_account"` (snake_case) — форма, не совпадающая ни с
одной другой в дереве (`iam.serviceAccount` в каталоге прав и в план-скане iam). Это **wire-поле**
публичного `Instance.serviceAccount`, поэтому смена формы — breaking для клиентов, читающих `type`,
и не может уехать в аддитивный XC-1.
- **Критерий приёмки O-7.** `reference.Referrer.type` во всех эмитирующих сайтах (`compute/protoconv`,
  `vpc/dto/toproto`, `storage/protoconv`) принимает значения **исключительно** из `pkg/restype`;
  гейт роняет сборку на литерале вне набора; комментарий-перечисление
  `proto/kacho/cloud/reference/reference.proto:49-54` заменён ссылкой на набор, и в нём не остаётся
  примеров с несуществующими доменами (`managed-kubernetes`, `managed-mysql`, `loadbalancer`).
- **Учёт: задачи с таким номером в трекере нет — завести.** GitHub Issue заводится в **S5** вместе
  с правкой `reference.proto`; относится к B1/REG-2-домену переименований, поэтому исполняется их
  порядком, а не XC-1. Номер проставляется в реестр §9.0 тем же коммитом.

**O-8 → задача #75 (STOR-AUTHZ-2). Прямой read-путь storage различает «нет доступа» и «нет объекта».**
Найдено при проверке блокирующего замечания круга 2 (§2.7 п.1). Это **не** off-lane-код и **не**
деталь — это самостоятельный existence-oracle **на публичной поверхности storage**:
`{Volume,Snapshot,Image}Service/Get` несут `required_relation: "viewer"` (не `v_get`) и не несут
`hide_existence` (`proto/kacho/cloud/storage/v1/volume_service.proto:26` и соседние; каталог
**генерируется** отсюда — `gateway/Makefile:49`), поэтому `HidesExistenceOnDeny` для них ложна,
storage-типов нет ни среди 22 достижимых, ни в `hideExistenceNotFoundFormats`, и denied `Get` даёт
`403`, а промах — `404 "Volume <id> not found"` (`services/storage/internal/repo/pg/errmap.go:62`).

Почему **не** внутри XC-1: (а) исправление меняет **наблюдаемый код ответа** `403 → 404` на
публичной поверхности трёх ресурсов — это ровно то, чего аддитивный XC-1 не делает, и седьмым
исключением списка D6 оно не объявляется (список закрыт по причине безопасности **peer-границы**, а
не по причине «раз уж мы здесь»); (б) правится **proto-аннотация**, из которой генерируется каталог,
значит требуется byte-identical регенерация **обеих** встроенных копий (iam-seed + middleware шлюза,
гейт `permission-catalog-check`); (в) в storage-суите **51** строка упоминает `403`
(`grep -rn 403 services/storage/tests/newman/cases/*.py | wc -l`), часть придётся переразметить;
(г) это тот же набор строк каталога, который правит уже идущая работа
STOR-AUTHZ-2 (`viewer` → Design-B) — делать его дважды из двух под-фаз значит гарантировать
конфликт. Радиус несовместим с XC-1; **срок и критерий — названы**.

- **Критерий приёмки (срез «XC-5» внутри #75).** Для **каждого** object-scoped read-RPC storage
  (`VolumeService/Get`, `SnapshotService/Get`, `ImageService/Get`): ответ на «объект существует,
  доступа нет» **байт-идентичен** ответу на «объекта нет» — тот же код (`404`), тот же текст
  (взятый **дословно** из repo-слоя владельца, не сочинённый), те же сериализованные `details`
  (`RESOURCE_NOT_FOUND`, `domain = "storage.kacho.cloud"`, `metadata{resource_type, resource_id}`).
  Наблюдаемо: (1) три типа `storage_volume|storage_snapshot|storage_image` входят в множество
  достижимых, выводимое `TestHideExistenceMap_CoversCatalogReachableTypes`, и отображены в
  `hideExistenceNotFoundFormats` — то есть строки перестают быть мёртвыми **тем же изменением**,
  которое делает их достижимыми (D8, атомарность среза); (2) `make -C gateway
  permission-catalog-check` зелёный, обе встроенные копии byte-identical; (3) константа-RED-цель
  сценария XC-1-46 **перевёрнута**, и XC-1-46 после этого утверждает уже паритет, а не расхождение —
  это и есть машинная сдача среза; (4) newman storage-суиты обновлены, ни одного оставшегося
  утверждения `403` на object-scoped read.
- **Учёт: задача уже заведена — это #75 (STOR-AUTHZ-2), новая не создаётся.** Круг 3 записал O-8
  как «под-фазу XC-5», у которой issue «заводится первым коммитом S1». Это было бы **дублем**:
  #75 («каталог storage не перешёл на Design-B — список шире чтения + read-over-grant») правит тот
  же самый набор строк каталога и ту же самую пару `viewer` vs `v_get`, из которой растёт оракул.
  Заводить рядом второй номер на те же строки — гарантировать конфликт правок и два независимых
  «сделано» на одну работу. Поэтому: **исход O-8 — #75**, а «XC-5» остаётся в этом тексте лишь
  как имя среза внутри неё. Первым коммитом S1 в #75 добавляется комментарий со ссылкой на эту
  строку реестра §9.0 и на пин XC-1-46. Критерий #75 («внутрисервисная карта зеркалит каталог прав,
  проверено во всех семи сервисах») и критерий приёмки выше — **совместимы и оба обязательны**:
  первый закрывает причину (карта ↔ каталог), второй — наблюдаемое следствие (deny ≡ miss).

**O-9. Стандартизация newman-харнесса в двух суитах (валидатор) и трёх (таксономия).** По дереву
`tests/newman/scripts/validate-cases.py` отсутствует в **compute** и **iam**;
`tests/newman/docs/CASES-INDEX.md` — в **iam**; `tests/newman/docs/TAXONOMY.md` — в **iam,
registry, storage** (таблица — §7.4). XC-1 на них **не опирается** (его гейт прослеживаемости читает
только имена Go-функций и аннотации `# verifies`), поэтому пробел не блокирует полосу отказа и в
XC-1 не втягивается: это работа харнесса, идущая своим потоком (стандартизация тестового харнесса
семи сервисов), а не часть контракта ошибки.
- **Критерий приёмки O-9.** Во всех **7** суитах существуют `scripts/validate-cases.py`,
  `docs/CASES-INDEX.md`, `docs/TAXONOMY.md`; `validate-cases.py` зелёный в 7 из 7 и падает при
  инъекции дублирующегося case-id (гейт доказан инъекцией, а не наличием файла); каждый case-id
  XC-1 (`*-XCR-*`) зарегистрирован в индексе своей суиты.
- **Учёт: задачи с таким номером в трекере нет — завести** (номер здесь не выдумывается). Заводится
  первым коммитом S1 в потоке стандартизации тестового харнесса семи сервисов, **не** внутри XC-1;
  в DoD XC-1 требования сужены до суит, где артефакт существует (§8), — то есть XC-1 не предъявляет
  несуществующего и не прячет пробел.
  **Смежная строка того же класса, найденная в круге 4:** цель `audit-list-filter` у registry —
  echo-заглушка без скрипта (`services/registry/Makefile:46-47`), а CI перебирает 4 сервиса из 5
  объявленных (`ci.yaml:230`). Это **не** O-9: у пункта есть свой номер — **#81(в)**, критерий — в
  реестре §9.0.

---

## 10. Открытые вопросы к ревьюеру

- **~~Q1~~ — закрыт в круге 2 (D4).** Вопрос был поставлен неверно: он спрашивал про «ресурсы, которых
  нет в перечислении», предполагая, что перечисление — словарь. Проверка по коду показала, что
  словаря нет, а есть **четыре несовместимые таксономии** (`reference.proto` — пять примеров в
  комментарии, три с несуществующими доменами; ключи каталога прав — смешанные ед./мн. число с
  доменом `loadbalancer`; permission-строки — машинно-плюрализованные с дефектами; публичный
  `bootSource.type` — единственное число). Решение — единый `pkg/restype`, форма
  `<rest-домен>.<ресурс в ед. ч.>`, с гейтенной биекцией к каталогу прав. Дефолт на ревью не
  требуется — решение принято и обосновано по коду.
- **~~Q3~~ — закрыт в круге 2 (§7.3).** Храповик считается **по файлам**: `vpc→iam Project` — 7
  строк, итого **8 полос / 14 строк**. Иначе частичное исправление (два файла из семи) невозможно
  отразить, а «список только сокращается» перестаёт быть проверяемым.
- **~~Q2~~ — закрыт в круге 4 решением (открытый вопрос без исхода — тот же долг, что открытый
  пункт).** `resource_type` операции — **доменная форма `<домен>.operation`**, не единая
  `common.operation`. Основание не в предпочтении, а в коде: id операции несёт **per-service**
  префикс (`pkg/ids`: `PrefixOperationVPC`, `PrefixOperationCompute`, `PrefixOperationStorage`,
  `PrefixOperationReg`, `PrefixOperationNLB`, …), таблица `operations` — per-service (`database-per-service`,
  ban #8), общего владельца у типа нет. Единая форма утверждала бы обратное и сломала бы инвариант
  D5 «первый сегмент `Value` == `Owner`» (у `common.operation` владельца нет). Влияние ограничено
  XC-1-25 и семью записями `pkg/restype`. Пересмотр — только правкой `api-conventions.md`.
- **~~Q4~~ — закрыт в круге 4 решением.** Нормализация `domain` шлюза
  (`kacho.cloud.iam.v1` → `gateway.kacho.cloud`) идёт **в S5**, и это не «либо-либо»: круг 4 показал,
  что сайтов **четыре** (`permission_denied_response.go:93,242,273,320`), из них два — REST-JSON-ветки,
  собирающие строку литералом. Отдельным изменением их пришлось бы синхронизировать с XC-1-22/23
  («REST и gRPC совпадают символ-в-символ») через границу PR — то есть ровно та рассинхронизация,
  которую S5 и существует закрыть. Условие безопасности проверено (§2.6): ни один тест и ни один
  newman-кейс на значение `domain` не опирается. В S5 все четыре сайта берут строку из **одной**
  константы — иначе пятый разъедется снова.
