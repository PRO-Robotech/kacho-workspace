<!--
Copyright (c) PRO-Robotech
SPDX-License-Identifier: BUSL-1.1
-->

# Sub-phase ADM-1 · geo (каталог размещения управляется с внешнего края) — Acceptance

> **Статус:** DRAFT
> **Статическая форма:** DRAFT; действующий вердикт выводится из внешнего события и записи ревью
> (`.claude/rules/change-graph.md` §2 «Вердикт привязан к ОТПЕЧАТКУ, а не к документу»)
> **История review:** только дописывается; прежние строки не редактируются
> - 2026-10-07 · круг 1 · CHANGES_REQUESTED · `52b153d5c0e6813286084d5b3f3f07692552b0f7330dd299d6adfe7c58869ead` · `docs/specs/reviews/sub-phase-ADM-1-geo-placement-catalog-admin-acceptance/52b153d5c0e6813286084d5b3f3f07692552b0f7330dd299d6adfe7c58869ead.yaml`
> **Дата:** 2026-10-07
> **Эпик/issue:** PRO-Robotech/kacho#3092 (служба geo и край); консоль — #3094; проба посадки
> admin-плоскости — #3091 (зависимость консольной части, не предмет этого документа)
> **Родительская приёмка:** `docs/specs/sub-phase-ADM-1-admin-surface-acceptance.md` (одобрена,
> круг 4). Этот документ — конкретизация её стадий **S1** (expand) и **S2** (migrate) для
> очереди 1 (§5.1 родителя: «каталог размещения») по образцу уже посаженного пула адресов
> (`AddressPoolService`, коммит продукта `ea07e7fff5`). Нормы родителя (Р1–Р11) здесь не
> пересказываются; ниже — только то, что для geo конкретно или отличается.
> **Ревизия замера:** продукт `PRO-Robotech/kacho` @ `ffbe930dbe`

## Обзор

Создание, правка и удаление регионов и зон сегодня объявлены только во внутренних службах
`InternalRegionService` и `InternalZoneService` и обслуживаются только внутренним слушателем
края. Консоль на посадке внешнего края зовёт `/geo/v1/internal/{regions,zones}` и получает
`404`: край по запрету 6 эти службы наружу не выводит, и это верно. Под-фаза добавляет
административные глаголы в **публичные** `RegionService` и `ZoneService` на канонические пути
`/geo/v1/regions` и `/geo/v1/zones`, под правом `system_admin` @ `cluster` и с тем же порогом
подтверждения личности, что у внутренних близнецов; внутренние службы остаются на внутреннем
слушателе без изменений; консоль на внешнем крае переходит на публичные пути.

## Что НЕ входит

- **Стадия S3 родителя** (снятие внутренних `Create/Update/Delete`). Внутренние службы живут
  дальше без изменений; их снятие — отдельное решение со своим предикатом «ноль
  производственных вызывающих» (посев стенда зовёт внутренний путь — §2 Р7).
- **`GetInternal`** региона и зоны — корзина Б родителя (§3.2): полная проекция с `infra`
  остаётся только внутренней.
- **Инфраструктурный блок (`infra`) на публичном входе** — ни на `Create`, ни на `Update`
  (§2 Р3).
- **Публичная служба администраторов кластера** (iam/kaname) — #3093 и kaname#661, своя
  приёмка в доме службы доступа.
- **Сама проба посадки admin-плоскости** (`ui-future/shared/src/lib/admin-plane-posture.ts`) —
  #3091. Здесь используется только её **исход** (§2 Р6).
- **Опрос операции geo на внешнем крае** (`GET /operations/{id}`): мутации geo завершаются в
  самом ответе (П4), и под-фаза публичный опрос их операций не утверждает; прежняя проба этого
  пути снята как неконтрактная (`services/geo/tests/newman/cases/operation.py:14-21`).
- Поток изменений (подписка) на регионы и зоны: у geo его нет, под-фаза его не заводит.

## 1. Перепись производителей (до сценариев)

Каждая строка — что в дереве **уже** производит факт, на который опирается «Тогда», с
координатой и командой. Ревизия — `ffbe930dbe`.

| # | факт | координата | чем получено |
|---|---|---|---|
| П1 | внутренние мутации региона и зоны: `Create/Update/Delete` → `corelib.operation.Operation`, право `system_admin`, scope `cluster`/`*`, `required_acr_min = "1"` у всех шести | `proto/kacho/cloud/geo/v1/internal_catalog_service.proto:34-198` | `grep -n 'rpc \|required_relation\|acr_min' …/internal_catalog_service.proto` |
| П2 | имена прав мутаций: `geo.regions.{create,update,delete}`, `geo.zones.{create,update,delete}`; у близнеца пула адресов публичный глагол несёт **то же** имя права, что внутренний | `gateway/internal/middleware/embed/permission_catalog.json:403-480`; пул — `:1420` против `:1730` | `grep -n 'geo.regions\|geo.zones' …/permission_catalog.json` |
| П3 | публичное чтение — `viewer` @ `cluster`, `acr_min = "1"`, поимённо названо справочником в гейте подстановочных отношений | `proto/kacho/cloud/geo/v1/region_service.proto:20-55`; `gateway/internal/middleware/permission_catalog_wildcard_relation_test.go:82-85` | чтение файлов |
| П4 | мутация завершается **синхронно**: `Operation` с `done=true` в самом ответе, `response` — публичный `Region`/`Zone` либо `Empty` для удаления; отказ хранилища — в `Operation.error`, синхронный отказ проверки входа — gRPC-статусом | `services/geo/internal/apps/kacho/shared/syncop/syncop.go:1-40`; `…/api/region/region.go:229-290,318-345` | чтение |
| П5 | тексты отказов: `invalid region id '<X>'` · `zone id '<Z>' must be prefixed by its regionId '<R>'` · `countryCode must be an ISO-3166 alpha-2 code` · `region <id> is not empty` · `<Resource> <id> not found` · `<Resource> <id> already exists` · `<Resource> <id> violates a reference constraint` · `regionId is immutable after Zone.Create` · `numericInfraId is immutable after <R>.Create` | `services/geo/internal/domain/geo.go:40,52,66`; `…/api/region/region.go:240-242,341`; `…/api/zone/zone.go:239-243`; `services/geo/internal/repo/kacho/dberr/dberr.go:39,56,60` | `grep -n 'invalidArg(\|Errorf' …` |
| П6 | эти отказы уже утверждаются на внутреннем пути (HTTP-статус + код, либо `Operation.error`) | `services/geo/tests/newman/cases/internal-region.py:81-82,129,177`; `…/internal-zone.py:85-86,106-107,129,134-136` | `grep -n 'assert_operation_failed\|assert_grpc_code' …` |
| П7 | неизвестный ключ тела край **отбрасывает** (решение края, взвешенное и записанное), неизвестное значение перечисления — отвергает | `gateway/internal/restmux/mux.go:360-400` | чтение |
| П8 | внешний слушатель отвечает `404` на все восемь пар `/geo/v1/internal/…` | `gateway/internal/restmux/geo_test.go:109` `TestGeo_S5_InternalPathsRejectedOnExternal` | чтение |
| П9 | публичные пары `POST/PATCH/DELETE /geo/v1/{regions,zones}` **не** разрешаются во внутренний FQN | `gateway/internal/middleware/geo_catalog_test.go:137` `TestRestRouter_Geo_S5_InternalPathNotPublicCRUD` | чтение |
| П10 | регистрация публичных geo-служб на крае — в цикле по обоим mux, внутренних — только при `geoInternalAddr` и только на `internalMux` | `gateway/internal/restmux/mux.go:684-712` | чтение |
| П11 | принципалы проб: `jwtBootstrap` — `system_admin` @ `cluster` (миграция kaname 0058, детерминированно); `jwtPureNoBindings` — без кластерных кортежей, кроме пола `system_viewer` для чтения справочника | `tests/authz-fixtures/prodseed_matrix.py:440-490,856,876` | чтение |
| П12 | базовый каталог стенда (`ru-central1` и зоны) засевается посевом через **внутренний** путь | `tests/authz-fixtures/prodseed_matrix.py:496-520`; `deploy/scripts/geo-baseline.sql` | чтение |
| П13 | администратор-человек консоли (`admin@prorobotech.ru`) получает `system_admin` @ `cluster` посевом **best-effort** — при отсутствии пользователя шаг молча пропускается | `tests/authz-fixtures/prodseed_matrix.py:476-495` | чтение |
| П14 | у служебных SA-токенов проб уровень подтверждения не проверяется (`acr`-exempt) — поведенческий отказ по порогу на стенде этими токенами **не конструируется**; механизм порога держат тесты края | `tests/authz-fixtures/prodseed_matrix.py:7`; `gateway/internal/middleware/auth_basic_stepup_internal_test.go:24`, `…/permission_catalog_acr_invariant_test.go:252-405` | чтение |
| П15 | инфраструктурный блок (`RegionInfra`/`ZoneInfra`) вне службы geo не читает никто | `git grep -ln -i 'NumericInfraId\|numeric_infra_id' -- services gateway pkg ':!*_test.go' ':!pkg/api/'` — 23 файла: 16 в `services/geo/`, 5 в `services/registry/`, 2 в `services/storage/`; семь попаданий вне geo — утверждения **отсутствия** собственного поля с таким именем у своих ресурсов, а не читатели блока geo (разбор по референту — запись ревью круга 1, `non_blocking` п.1) | команда, разбор попаданий по референту |
| П16 | консоль: мутации регионов и зон идут на `GEO_INTERNAL_{REGIONS,ZONES}_PATH`, форма правки читается с `GetInternal` (`readForEdit`), в форме — поля `infra.*` | `ui-future/shared/src/api/geo.ts:31-32`; `ui-future/shared/src/lib/resource-registry.tsx:4061-4310` | чтение |
| П17 | консоль: экран раздела прячет действия при посадке `absent`; посадка определяется пробой #2692 | `ui-future/system/src/pages/SystemPage/SystemPage.tsx:73-81` | чтение |
| П18 | пробы, утверждающие, что публичный `POST /geo/v1/{regions,zones}` **не обслуживается** (их предмет меняется этой под-фазой) | `services/geo/tests/newman/cases/admin-not-on-public.py` — `ANP-REG-CR-NOT-PUBLIC`, `ANP-ZON-CR-NOT-PUBLIC` | чтение |
| П20 | изъятие загрузочного гейта мутаций в дескрипторе geo обосновано **двумя** предметами: (1) «доставлять нечего» — geo ничего не эмитит владельцу прав; (2) «отвергать нечего» — все мутации на `Internal*`-службах; самоистечение держит проба по предмету (2) `TestGeoServesNoGatedMutation` тем же предикатом, что исполняет гейт (`/Create` службы, имя которой не начинается с `Internal`) | `services/geo/cmd/kacho-geo/serve.go:333-364`; `services/geo/cmd/kacho-geo/describe_test.go:133`; предикат — `corelib@v1.10.0 servicehost/links.go:196` | чтение |
| П21 | общий конструктор дескриптора **отвергает** гейт мутаций, принесённый службой с пустой или неприменимой осью эмиссии («проводка без предмета») | `corelib@v1.10.0 servicecontract/contract.go:1363-1371` | чтение |
| П22 | отказ по порогу подтверждения на крае: REST — `401`, `{"code":16,"message":"insufficient_user_authentication"}` и вызов повышения в `WWW-Authenticate`; нативный gRPC — `UNAUTHENTICATED` с тем же текстом; текст — одна константа | `gateway/internal/middleware/auth_stepup.go:139-143,208,231` | чтение |
| П23 | отказ общей проверки маски на неизвестном пути: `INVALID_ARGUMENT`, `message` = `invalid argument`, нарушение поля `update_mask` с описанием `unknown field in update_mask: <путь>`; неизменяемые пути отвергаются раньше, своим текстом (`numericInfraId is immutable after Region.Create` и для пути `infra.numericInfraId`) | `corelib@v1.10.0 validate/validate.go:304-313`, `errors/errors.go:80`; `services/geo/internal/apps/kacho/api/region/region.go:237-243` | чтение |
| П24 | фикстура человека-арендатора консоли без кластерных кортежей: свежая регистрация и вход через экраны | `ui-future/e2e/specs/fixtures.ts:534` (`registerAndSignIn`) | чтение |
| П19 | радиус по имени механизма — **62** файла | `git grep -ln 'geo/v1/internal\|InternalRegionService\|InternalZoneService' -- gateway/ services/ ui-future/ deploy/ ':!*.pb.go' ':!*.pb.gw.go' \| wc -l` | команда |

Производителя **нет** у четырёх фактов; каждый назван с исходом: публичные глаголы (заводятся
этой под-фазой), гейт «публичный вход без `infra`» (заказан в DoD), шаг-условие
«администратор-человек держит `system_admin`» (заказан в DoD, П13 молчит при неудаче), проба
самоистечения изъятия гейта мутаций по предмету «доставлять нечего» (§Р8, заказана в DoD п.2).

## 2. Решения

### Р1. Глаголы встают в существующие публичные службы, а не в новую

`RegionService` и `ZoneService` получают `Create`, `Update`, `Delete`. У пула адресов
публичной службы не было вовсе, поэтому она заводилась; у geo она есть и уже несёт `Get`/`List`
на тех же путях. Шаблон службы (`api-conventions.md` §«Форма ресурса») — чтение и мутации
одного ресурса в одной службе, адрес ресурса один:

| глагол | HTTP | путь |
|---|---|---|
| `RegionService/Create` | `POST` | `/geo/v1/regions` |
| `RegionService/Update` | `PATCH` | `/geo/v1/regions/{regionId}` |
| `RegionService/Delete` | `DELETE` | `/geo/v1/regions/{regionId}` |
| `ZoneService/Create` | `POST` | `/geo/v1/zones` |
| `ZoneService/Update` | `PATCH` | `/geo/v1/zones/{zoneId}` |
| `ZoneService/Delete` | `DELETE` | `/geo/v1/zones/{zoneId}` |

В отличие от пула адресов, публичный и внутренний пути geo **различны**
(`/geo/v1/internal/…` у внутренних) — окна сосуществования на одной паре (метод, путь) нет,
норма Р11 родителя применяется в вырожденной форме.

### Р2. Право и порог — те же, что у внутреннего близнеца, дословно

Каждый из шести публичных глаголов несёт: `permission` — то же имя, что у внутреннего
близнеца (П2); `required_relation = "system_admin"`; `scope_extractor` — `cluster`/`*`;
`required_acr_min` — **равный** значению внутреннего близнеца (сегодня `"1"` у всех шести, П1).
Порог принадлежит действию, а не адресу: разойдись значения, публичный путь стал бы более
дешёвым способом совершить то же действие. Равенство держится пробой по паре записей
каталога (сценарий 15), а не совпадением на сегодня.

### Р3. Публичный вход не несёт `infra`

Публичные сообщения запроса — **отдельные** от внутренних и не содержат поля `infra`:

| глагол | поля тела |
|---|---|
| создание региона | `id`, `countryCode`, `status` |
| правка региона | `countryCode`, `status`, `updateMask` |
| создание зоны | `id`, `regionId`, `status` |
| правка зоны | `status`, `updateMask` |

Изменяемые через публичную маску поля: регион — `status`, `countryCode`; зона — `status`.
Путь маски, называющий `infra` или любое его подполе, отвергается синхронно
`INVALID_ARGUMENT` с именем этого пути в нарушении поля `update_mask` (П23; маска — строка,
край её не отбрасывает); неизменяемый путь — своим текстом неизменяемости, раньше общей проверки.
`status` на входе допустим: это действие администратора, а публичная проекция его значение
уже выводит (`openForPlacement`, `placementBlockedReason`).

**Следствие, принятое явно.** Регион или зона, созданные публичным глаголом, получают
`numericInfraId = 0` («не назначен»), а поле неизменяемо после создания, поэтому назначить его
можно только внутренним созданием. Читателя у блока вне geo нет (П15), поэтому следствие не
меняет ни одного наблюдаемого поведения платформы; изменяемые подполя `infra` зоны остаются
доступны внутренней правкой.

### Р4. Ответ и предупреждения

Ответ — `Operation`, `done=true` в самом ответе (П4); `response` — публичная проекция
(`Region`/`Zone`) у создания и правки, `Empty` у удаления; метаданные — `{regionId|zoneId}` и
`warnings`. Предупреждение о создании закрытым для размещения не называет внутренних путей
или служб: его читает вызывающий публичного API, и указание на недоступный ему адрес было бы
ложной подсказкой.

### Р5. Внутренние службы остаются, и проба изоляции не ослабевает

`InternalRegionService`/`InternalZoneService` — без изменений в контракте и регистрации:
только `internalMux`, только при `geoInternalAddr` (П10). Восемь пар `/geo/v1/internal/…` на
внешнем слушателе — `404` (П8), проба не правится. Публичные глаголы обязаны быть смонтированы
и на внешнем, и на внутреннем слушателе (цикл П10).

### Р6. Консоль: публичный путь всегда, кроме операторской посадки

Режим формы выбирается исходом пробы посадки (#3091):

- посадка **`present`** (край обслуживает внутреннюю плоскость) — поведение консоли не
  меняется: внутренние пути, поля `infra`, чтение формы с `GetInternal`, вкладка полной
  проекции. Всё, что сделано для оператора, остаётся доступным;
- **любая другая** посадка — создание, правка и удаление идут на публичные пути §Р1; в форме
  нет полей `infra`; начальное значение `status` в форме правки **выводится** из публичной
  проекции: регион — `openForPlacement ? UP : DOWN`; зона — `placementBlockedReason == ZONE_DOWN
  ? DOWN : UP` (порядок старшинства объявлен в `geo_common.proto`, вывод точен); вкладки полной
  проекции нет.

Кнопки мутаций регионов и зон **не** зависят от того, есть ли admin-плоскость: эти экраны
теперь обслуживаются на обеих посадках. Отказ вызывающему без права показывается словами
(`403`), а не превращается в «раздела нет».

### Р7. Пробы, у которых меняется предмет

- `ANP-REG-CR-NOT-PUBLIC`, `ANP-ZON-CR-NOT-PUBLIC` (П18) утверждали «публичный `POST
  /geo/v1/{regions,zones}` не обслуживается». После под-фазы это ложь. Предмет пары остаётся —
  «внутренний глагол не достижим снаружи», — меняется **представитель** публичной ноги: она
  бьёт `POST /geo/v1/internal/{regions,zones}` на внешнем слушателе и ждёт `404` (сценарий 12).
  Переворот ожидания на прежнем пути вместо смены представителя — нарушение.
- `TestRestRouter_Geo_S5_InternalPathNotPublicCRUD` (П9) остаётся верным без правок; рядом
  ставится положительный близнец — те же шесть пар разрешаются в `RegionService`/`ZoneService`.
- `TestGeoServesNoGatedMutation` (П20) после под-фазы **обязан** покраснеть: `RegionService/Create`
  и `ZoneService/Create` подпадают под предикат гейта. Решение — §Р8: проба снимается вместе с
  предметом (2) и заменяется пробой по предмету (1); её покраснение не «чинится» правкой ожидания.
- Посев стенда (П12) остаётся на внутреннем пути: он исполняется внутри кластера и не является
  вызывающим-человеком.
- Остальные файлы радиуса (П19) — документация службы и консоли, называющая мутации
  «только внутренними», — правятся тем же изменением; утверждение, пережившее предмет, не
  оставляется.

### Р8. Загрузочный гейт мутаций: причина изъятия переписывается на «доставлять нечего»

Публичные `Create` делают geo службой с гейтируемыми мутациями, и предмет (2) изъятия (П20)
становится ложным. **Гейт не приносится**: общий конструктор дескриптора отвергает гейт у службы
без эмиссии (П21), а смысл гейта — не принимать создание, пока не поднят путь доставки намерений
владельцу прав, — у geo пуст: ни публичное, ни внутреннее создание намерений не порождает
(каталог кластера, пообъектных грантов нет — ось `Emits` неприменима с причиной). Решение:

- причина изъятия `BootGate` в дескрипторе geo называет **только** предмет (1); фраза «все
  мутации — на `Internal*`-службах» из неё и из комментария снимается тем же изменением, что
  заводит публичные глаголы;
- `TestGeoServesNoGatedMutation` снимается вместе со своим предметом и заменяется пробой
  самоистечения по предмету (1) — `TestGeoBootGateExemptionRestsOnNoEmission`: дескриптор geo,
  собранный боевой конфигурацией, объявляет ось эмиссии **неприменимой**, и гейт мутаций —
  неприменимым; проба падает с именем оси, если эмиссия объявлена значением (тогда изъятие
  пережило бы предмет, и гейт обязан прийти);
- рядом — положительный контроль того, что проба способна упасть: дескриптор той же службы с
  объявленной непустой эмиссией и неприменимым гейтом проба отвергает; и контроль предмета
  перехода — среди служимых методов есть гейтируемые (`RegionService/Create`,
  `ZoneService/Create`) и они названы в логе пробы счётом, чтобы «изъятие по (1)» не читалось
  как «гейтировать нечего».

Наблюдаемое поведение API от решения не меняется: публичное создание не ждёт пути доставки, как
не ждёт его сегодня внутреннее.

## 3. Сценарии

ID — `ADM-1-GEO-<NN>`, трассируются в имена проб. Субъекты: **`admin`** — `jwtBootstrap`
(П11); **`tenant`** — `jwtPureNoBindings` (П11); **`anon`** — запрос без принципала. Все
запросы — на **внешний** слушатель (`{{baseUrl}}`), если не сказано иное. `{{runId}}` —
суффикс прогона; каждый сценарий заводит свои объекты и снимает их.

Синхронные отказы проверки входа (сценарии 08 и 11) утверждаются **integration-пробой
службы** обеими сторонами каждой оси (DoD п.2), а newman несёт **по одному** кейсу на
отображение `INVALID_ARGUMENT` в `400` (DoD п.4) — `e2e-flow.md` §5 (`no-reassert-unit-property`).
Отказы хранилища в `Operation.error` (сценарии 09, 10) утверждаются обоими: integration-пробой
(DoD п.2) и newman (DoD п.4). Изоляция внутренних путей (сценарий 12) — Go-пробой края и
newman (DoD пп. 3, 4).

### Класс 1. Администратор управляет каталогом с внешнего края

**Сценарий 01: регион создаётся администратором; арендатору — отказ, и региона нет**

**ID:** ADM-1-GEO-01

**Given** край в боевой посадке, внешний слушатель обслуживает публичные пути
**And** региона `adm1g-{{runId}}` не существует

**When** `tenant` вызывает `POST /geo/v1/regions` с payload:
  - `id` = `adm1g-{{runId}}`
  - `countryCode` = `RU`
  - `status` = `UP`

**Then** `403`, `code` = `PERMISSION_DENIED`
**And** `GET /geo/v1/regions/adm1g-{{runId}}` под `tenant` → `404`, `code` = `NOT_FOUND`

**When** `admin` вызывает `POST /geo/v1/regions` с тем же payload
**Then** `200`; тело — `Operation` с `done=true`, без `error`, `metadata.regionId` =
`adm1g-{{runId}}`, `response.id` = `adm1g-{{runId}}`
**And** `GET /geo/v1/regions/adm1g-{{runId}}` под `tenant` → `200`, `countryCode` = `RU`,
`openForPlacement` = `true`, непустой `createdAt`

---

**Сценарий 02: зона создаётся администратором в регионе; арендатору — отказ**

**ID:** ADM-1-GEO-02

**Given** регион `adm1g-{{runId}}` существует со `status` = `UP` (создан `admin` публичным путём)

**When** `tenant` вызывает `POST /geo/v1/zones` с payload:
  - `id` = `adm1g-{{runId}}-a`
  - `regionId` = `adm1g-{{runId}}`
  - `status` = `UP`

**Then** `403`, `PERMISSION_DENIED`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` → `404`, `NOT_FOUND`

**When** `admin` вызывает тот же запрос
**Then** `200`, `Operation` `done=true` без `error`, `response.id` = `adm1g-{{runId}}-a`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` под `tenant` → `200`, `regionId` =
`adm1g-{{runId}}`, `openForPlacement` = `true`, `placementBlockedReason` = `NONE`

---

**Сценарий 03: правка статуса региона видна в обеих проекциях**

**ID:** ADM-1-GEO-03

**Given** регион `adm1g-{{runId}}` (`UP`) и его зона `adm1g-{{runId}}-a` (`UP`)

**When** `tenant` вызывает `PATCH /geo/v1/regions/adm1g-{{runId}}` с payload:
  - `status` = `DOWN`
  - `updateMask` = `status`

**Then** `403`, `PERMISSION_DENIED`
**And** `GET /geo/v1/regions/adm1g-{{runId}}` → `openForPlacement` = `true` (не изменилось)

**When** `admin` вызывает тот же запрос
**Then** `200`, `Operation` `done=true` без `error`, `response.openForPlacement` = `false`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` → `openForPlacement` = `false`,
`placementBlockedReason` = `REGION_DOWN`
**And** `PATCH` того же региона под `admin` с `status` = `UP`, `updateMask` = `status` →
`Operation` без `error`; зона снова `NONE`

---

**Сценарий 04: правка статуса зоны**

**ID:** ADM-1-GEO-04

**Given** регион `adm1g-{{runId}}` (`UP`) и зона `adm1g-{{runId}}-a` (`UP`)

**When** `tenant` вызывает `PATCH /geo/v1/zones/adm1g-{{runId}}-a` с `status` = `DOWN`,
`updateMask` = `status`
**Then** `403`, `PERMISSION_DENIED`; зона по-прежнему `NONE`

**When** `admin` вызывает тот же запрос
**Then** `Operation` `done=true` без `error`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` → `openForPlacement` = `false`,
`placementBlockedReason` = `ZONE_DOWN`

---

**Сценарий 05: удаление зоны и региона**

**ID:** ADM-1-GEO-05

**Given** регион `adm1g-{{runId}}` и зона `adm1g-{{runId}}-a`

**When** `tenant` вызывает `DELETE /geo/v1/zones/adm1g-{{runId}}-a`
**Then** `403`, `PERMISSION_DENIED`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` → `200`

**When** `admin` вызывает `DELETE /geo/v1/zones/adm1g-{{runId}}-a`, затем
`DELETE /geo/v1/regions/adm1g-{{runId}}`
**Then** обе — `200`, `Operation` `done=true` без `error`
**And** `GET /geo/v1/zones/adm1g-{{runId}}-a` → `404`, `message` = `Zone adm1g-{{runId}}-a not found`
**And** `GET /geo/v1/regions/adm1g-{{runId}}` → `404`, `NOT_FOUND`

### Класс 2. Отказы по канону на публичном пути

**Сценарий 06: регион с зонами не удаляется; без зон — удаляется**

**ID:** ADM-1-GEO-06

**Given** регион `adm1g-ne-{{runId}}` с зоной `adm1g-ne-{{runId}}-a`

**When** `admin` вызывает `DELETE /geo/v1/regions/adm1g-ne-{{runId}}`
**Then** `200`; `Operation` `done=true`, `error.code` = `9` (`FAILED_PRECONDITION`),
`error.message` = `region adm1g-ne-{{runId}} is not empty`
**And** `GET /geo/v1/regions/adm1g-ne-{{runId}}` → `200`

**When** `admin` удаляет зону, затем повторяет удаление региона
**Then** `Operation` без `error`; `GET` региона → `404`

---

**Сценарий 07: повторное создание того же id**

**ID:** ADM-1-GEO-07

**Given** `admin` создал регион `adm1g-dup-{{runId}}` (первый вызов — `Operation` без `error`)

**When** `admin` повторяет `POST /geo/v1/regions` с `id` = `adm1g-dup-{{runId}}`
**Then** `200`; `Operation` `done=true`, `error.code` = `6` (`ALREADY_EXISTS`),
`error.message` = `Region adm1g-dup-{{runId}} already exists`

---

**Сценарий 08: неверная форма входа — синхронный `INVALID_ARGUMENT`**

**ID:** ADM-1-GEO-08

**Given** `admin` создал публичным путём регионы `adm1g-cp-{{runId}}` и `adm1g-other-{{runId}}`
(оба `UP`; снимаются тем же кейсом)
**And** зоны `adm1g-cp-{{runId}}-a` и регионов `adm1g-ok-{{runId}}`, `adm1g-cc-{{runId}}` не существует

**When** `admin` вызывает `POST /geo/v1/regions` с `id` = `Bad_Id`
**Then** `400`, `code` = `INVALID_ARGUMENT`, `message` = `invalid region id 'Bad_Id'`

**When** `admin` вызывает `POST /geo/v1/zones` с `id` = `adm1g-cp-{{runId}}-a`,
`regionId` = `adm1g-other-{{runId}}`
**Then** `400`, `INVALID_ARGUMENT`,
`message` = `zone id 'adm1g-cp-{{runId}}-a' must be prefixed by its regionId 'adm1g-other-{{runId}}'`

**When** `admin` вызывает `POST /geo/v1/regions` с `id` = `adm1g-cc-{{runId}}`, `countryCode` = `rus`
**Then** `400`, `INVALID_ARGUMENT`, `message` = `countryCode must be an ISO-3166 alpha-2 code`

**And** (близнецы, тем же набором) каждый из трёх запросов, отличающийся **одним** полем —
`id` = `adm1g-ok-{{runId}}`; `regionId` = `adm1g-cp-{{runId}}`; `countryCode` = `RU`, —
даёт `Operation` без `error`. Регион `adm1g-other-{{runId}}` существует, поэтому отрицательная
нога зоны отличается от близнеца **только** несовпадением префикса

---

**Сценарий 09: зона в несуществующем регионе**

**ID:** ADM-1-GEO-09

**Given** региона `adm1g-ghost-{{runId}}` не существует

**When** `admin` вызывает `POST /geo/v1/zones` с `id` = `adm1g-ghost-{{runId}}-a`,
`regionId` = `adm1g-ghost-{{runId}}`
**Then** `200`; `Operation` `done=true`, `error.code` = `9` (`FAILED_PRECONDITION`),
`error.message` = `Zone adm1g-ghost-{{runId}}-a violates a reference constraint`
**And** `GET /geo/v1/zones/adm1g-ghost-{{runId}}-a` → `404`

**And** (близнец) после создания региона `adm1g-ghost-{{runId}}` тот же запрос → `Operation`
без `error`

---

**Сценарий 10: правка несуществующего региона**

**ID:** ADM-1-GEO-10

**When** `admin` вызывает `PATCH /geo/v1/regions/adm1g-none-{{runId}}` с `status` = `UP`,
`updateMask` = `status`
**Then** `200`; `Operation` `done=true`, `error.code` = `5` (`NOT_FOUND`),
`error.message` = `Region adm1g-none-{{runId}} not found`

**And** (близнец) тот же запрос к существующему региону → `Operation` без `error`

---

**Сценарий 11: маска публичной правки не достаёт до `infra` и неизменяемых полей**

**ID:** ADM-1-GEO-11

**Given** зона `adm1g-m-{{runId}}-a` существует

**When** `admin` вызывает `PATCH /geo/v1/zones/adm1g-m-{{runId}}-a` с `updateMask` =
`infra.hostClasses`
**Then** `400`, `INVALID_ARGUMENT`, `message` = `invalid argument`; `details` несёт нарушение
поля `update_mask` с описанием `unknown field in update_mask: infra.hostClasses` (П23)

**When** `admin` вызывает тот же `PATCH` с `updateMask` = `regionId`
**Then** `400`, `INVALID_ARGUMENT`, `message` = `regionId is immutable after Zone.Create`

**When** `admin` вызывает `PATCH /geo/v1/regions/<регион зоны>` с `updateMask` =
`infra.numericInfraId`
**Then** `400`, `INVALID_ARGUMENT`, `message` = `numericInfraId is immutable after Region.Create` (П23)

**And** (близнец) тот же `PATCH` зоны с `updateMask` = `status`, `status` = `DOWN` →
`Operation` без `error`

### Класс 3. Внутреннее остаётся внутренним, публичное не несёт инфраструктуры

**Сценарий 12: внутренние пути снаружи не обслуживаются, изнутри — обслуживаются**

**ID:** ADM-1-GEO-12

**Given** край поднят с обоими слушателями

**When** `admin` на **внешнем** слушателе вызывает `POST /geo/v1/internal/regions` и
`POST /geo/v1/internal/zones` (тела нет — исход решается парой метод-путь)
**Then** оба — `404`

**When** `admin` на **внутреннем** слушателе вызывает `POST /geo/v1/internal/regions` с
`id` = `adm1g-int-{{runId}}`
**Then** `200`, `Operation` без `error` (снимается тем же кейсом)

**And** на уровне края восемь пар `/geo/v1/internal/…` на внешнем слушателе дают `404`, а шесть
пар `/geo/v1/{regions,zones}` разрешаются в `RegionService`/`ZoneService`, а не во внутренние

---

**Сценарий 13: публичные ответы не несут сырого статуса и `infra`; полная проекция — только внутри**

**ID:** ADM-1-GEO-13

**Given** `admin` создал публичным путём регион `adm1g-pj-{{runId}}` (`UP`) и зону
`adm1g-pj-{{runId}}-a` (`DOWN`)

**When** читаются: тело ответа публичного создания (`Operation.response`), `GET
/geo/v1/regions/adm1g-pj-{{runId}}`, `GET /geo/v1/zones/adm1g-pj-{{runId}}-a`
**Then** ни в одном теле нет ключей `infra` и `status`

**When** `admin` на **внутреннем** слушателе вызывает `GET
/geo/v1/internal/zones/adm1g-pj-{{runId}}-a`
**Then** `200`, `status` = `DOWN`; `infra.numericInfraId` отсутствует или равен `0` (Р3)

---

**Сценарий 14: два глагола пишут одно и то же**

**ID:** ADM-1-GEO-14

**Given** входы `{id: A, countryCode: RU, status: UP}` и `{id: B, countryCode: RU, status: UP}`

**When** `A` создан публичным глаголом, `B` — внутренним (без `infra`)
**Then** `GetInternal` обоих совпадает по всем полям, кроме `id` и `createdAt`
**And** публичные `GET` обоих совпадают по всем полям, кроме `id` и `createdAt`
**And** строка аудита мутации у обоих несёт один и тот же набор ключей и непустого исполнителя

Integration-проба службы geo (обе стороны в одном процессе); то же для зоны и для правки.

### Класс 4. Право и порог

**Сценарий 15: запись каталога публичного глагола равна записи внутреннего близнеца**

**ID:** ADM-1-GEO-15

**Given** каталог прав края

**When** для каждой из шести пар (`RegionService/X`, `InternalRegionService/X`) и
(`ZoneService/X`, `InternalZoneService/X`), `X` ∈ {`Create`, `Update`, `Delete`}, сравниваются
записи
**Then** у публичной записи `permission`, `required_relation` (`system_admin`),
`scope_extractor` (`cluster`/`*`) и `required_acr_min` равны внутренней
**And** отношение `system_admin` не выполняется подстановочным субъектом — гейт подстановочных
отношений публичные мутации **не** перечисляет как справочник

**And** (инъекция) временная правка `required_acr_min` одной публичной записи роняет пробу
**с её FQN**; законная пара проходит молча

---

**Сценарий 16: аноним не проходит; аутентифицированный — проходит до проверки права**

**ID:** ADM-1-GEO-16

**When** `anon` вызывает `POST /geo/v1/regions`, `PATCH /geo/v1/regions/ru-central1`,
`DELETE /geo/v1/zones/ru-central1-a`
**Then** все три — `401`, `UNAUTHENTICATED`

**And** (положительный контроль в том же кейсе) `POST /geo/v1/regions` под `tenant` — `403`
(аутентификация пройдена, право проверено), под `admin` с `id` = `adm1g-an-{{runId}}` —
`Operation` без `error`

---

**Сценарий 17: порог подтверждения личности публичного глагола исполняется**

**ID:** ADM-1-GEO-17

**Given** проба края с принципалом-человеком, держащим `system_admin` @ `cluster`, и токеном с
уровнем подтверждения ниже `required_acr_min` записи

**When** вызывается `POST /geo/v1/regions`
**Then** REST: `401`, тело `code` = `16` (`UNAUTHENTICATED`), `message` =
`insufficient_user_authentication`, заголовок `WWW-Authenticate` несёт вызов повышения (П22);
нативный gRPC: `UNAUTHENTICATED`, `message` = `insufficient_user_authentication`
**And** `POST /geo/v1/internal/regions` на внутреннем слушателе при том же токене даёт тот же код
и тот же текст
**And** (близнец) тот же принципал с уровнем, равным порогу, — проходит

Конструируется Go-пробой края: служебные SA-токены стенда уровень не несут (П14), поэтому на
стенде этот сценарий не строится и newman его не утверждает.

### Класс 5. Консоль

**Сценарий 18: администратор управляет регионами и зонами из консоли на внешнем крае**

**ID:** ADM-1-GEO-18

**Given** консоль подключена к внешнему краю (посадка admin-плоскости — не `present`, #3091)
**And** администратор-человек консоли держит `system_admin` @ `cluster` (шаг-условие, П13)

**When** администратор открывает `/system/regions`, создаёт регион `e2e-{{runId}}` формой,
переводит его в `DOWN` формой правки, затем на `/system/zones` создаёт зону
`e2e-{{runId}}-a` и удаляет её, затем удаляет регион
**Then** каждое действие завершается без отказа, список отражает результат без перезагрузки
страницы
**And** за всё время пробы консоль не отправила **ни одного** запроса на `/geo/v1/internal/`
(журнал сети пробы); мутации ушли на пути §Р1
**And** форма правки показала текущий `status`, выведенный из публичной проекции (§Р6), и не
показала полей `infra`

**And** (отрицательный близнец, тот же экран) арендатор консоли без кластерных кортежей —
фикстура `registerAndSignIn` (П24), свежая регистрация с `{{runId}}` в адресе — открывает
`/system/regions` (чтение справочника ему доступно, П3), отправляет ту же форму создания с
`id` = `e2e-t-{{runId}}`; консоль получает `403` и показывает отказ словами, а не «раздела нет» и
не `404`; региона `e2e-t-{{runId}}` после этого нет (`GET` под `admin` → `404`)

---

**Сценарий 19: операторская посадка сохраняет полную форму**

**ID:** ADM-1-GEO-19

**Given** исход пробы посадки — `present`

**When** открыта форма создания и правки зоны
**Then** поля `infra.*` присутствуют, мутации уходят на `/geo/v1/internal/zones`, форма правки
читается с `GetInternal`

**And** (близнец) при любом другом исходе — та же форма без `infra.*`, мутации на
`/geo/v1/zones`

Проба уровня компонента консоли с подставленным исходом посадки (обе ветки в одном наборе).

## 4. Сценарий → производитель

| ID | что производит «Тогда» | координата | чем измерено / исход |
|---|---|---|---|
| 01–05 | публичные `Create/Update/Delete` региона и зоны | **нет** — заводятся этой под-фазой (#3092): контракт `region_service.proto`/`zone_service.proto`, обработчик на публичном слушателе geo, запись каталога, регистрация П10 | исход: заказан производитель (#3092) |
| 01 | `Operation` `done=true` с `response` в самом ответе мутации (опрос операции не требуется и сценарием не утверждается) | `services/geo/internal/apps/kacho/shared/syncop/syncop.go` | П4 |
| 01–05 | `403` на крае до службы | механизм проверки права края, уже исполняемый для пула адресов | `services/vpc/tests/newman/cases/public-pool.py` (`jwtPureNoBindings` → `403`) |
| 01, 05 | `404` + `<Resource> <id> not found` на чтении | `services/geo/internal/apps/kacho/shared/serviceerr/lanes.go:47` | П5/П6 |
| 06 | `region <id> is not empty` в `Operation.error` | `…/api/region/region.go:341` | П6 `internal-region.py:177` |
| 07 | `already exists` в `Operation.error` | `…/repo/kacho/dberr/dberr.go:56` | П6 `internal-region.py:129` |
| 08 | три текста `INVALID_ARGUMENT` | `services/geo/internal/domain/geo.go:40,52,66` | П6 |
| 09 | `violates a reference constraint` | `…/dberr/dberr.go:60` | П6 `internal-zone.py:129` |
| 10 | `NOT_FOUND` в `Operation.error` правки | `…/api/region/region.go:267` (`directReadLane`) | чтение; newman-утверждения на внутреннем пути нет — integration-проба службы обязательна |
| 11 | `INVALID_ARGUMENT` на `infra.*` в публичной маске | **нет** — публичный known-set заводится этой под-фазой; текст отказа — общая проверка маски (П23); неизменяемые тексты — `zone.go:239-243`, `region.go:240-242` | исход: заказан производитель (#3092) |
| 12 | `404` внутренних путей снаружи; разрешение публичных пар | П8, П9; публичный близнец разрешения — **нет** | исход: близнец заказан (#3092, край) |
| 13 | отсутствие `infra`/`status` в публичных телах | сообщения `region.proto`, `zone.proto` (полей нет by construction); гейт «публичный вход без `infra`» — **нет** | исход: заказан производитель — проба дескрипторов публичных служб geo (#3092) |
| 14 | равенство двух путей записи | один use-case за обоими (П4) | исход: заказана integration-проба (#3092) |
| 15 | равенство записей каталога | `permission_catalog_acr_invariant_test.go` (счёт), `permission_catalog_wildcard_relation_test.go` | исход: проба пары заказана (#3092) |
| 16 | `401` анонима | `services/geo/tests/newman/cases/authz-deny.py:288-299` (внутренний путь) | П6 |
| 17 | `401`/`UNAUTHENTICATED` + `insufficient_user_authentication` по порогу | `gateway/internal/middleware/auth_stepup.go:139-143,208,231` (П22); механизм — `auth_basic_stepup_internal_test.go:24` | П14; исход: Go-проба края на новом FQN заказана (#3092) |
| 18 | консоль на публичных путях | **нет** — #3094; шаг-условие администратора-человека — **нет** (П13 молчит); арендатор близнеца — `registerAndSignIn` (П24) | исход: заказаны производители (#3094 консоль; шаг-условие — посев стенда) |
| 19 | две ветки формы по исходу посадки | **нет** — #3094; исход посадки — #3091 | исход: заказан производитель (#3094) |

## 5. Стадийность

Стадии — S1 и S2 родителя; S0 родителя к geo не применяется (публичный и внутренний пути
различны, представитель проб изоляции не переезжает).

### S1 — служба и край (#3092)

**Что:** контракт шести глаголов (§Р1, §Р3), обработчик на публичном слушателе geo, записи
каталога (§Р2), allowlist края, регистрация публичных служб на обоих mux; смена представителя
публичной ноги в `admin-not-on-public.py` (§Р7); правка документации радиуса П19 тем же
изменением.

**Предикат перехода:** сценарии 01–17 зелёные; `buf breaking` зелёный (только добавление);
`TestGRPCMountParity_*` и проба изоляции внешнего края зелёные; `make -C services/geo
audit-list-filter` зелёный; существующие внутренние пробы geo зелёные **без правок**, кроме
двух кейсов `admin-not-on-public.py` (§Р7) и пробы самоистечения изъятия гейта, заменённой по
§Р8; `TestGeoBootGateExemptionRestsOnNoEmission` и её контроль зелёные, `TestGeoServesNoGatedMutation`
в дереве нет (`git grep -n TestGeoServesNoGatedMutation -- services/geo` → пусто).

**Откат:** снять публичную регистрацию и записи каталога; внутренний путь не тронут.

### S2 — консоль (#3094, после #3091 и S1)

**Что:** §Р6.

**Предикат перехода:** сценарии 18–19 зелёные на развёрнутом стенде внешней посадки; в теле
браузерной пробы — `// verifies #3094`.

**Откат:** вернуть режим формы к внутренним путям; публичные глаголы аддитивны и остаются.

## 6. DoD

1. **Контракт:** `proto/kacho/cloud/geo/v1/region_service.proto` и `zone_service.proto` несут
   шесть глаголов §Р1 с аннотациями §Р2; публичные сообщения запроса не содержат `infra`;
   `buf lint` и `buf breaking` зелёные; регенерация закоммичена.
2. **Служба geo:** глаголы обслуживаются на публичном gRPC-слушателе через те же use-case'ы,
   что у внутренних; публичный known-set маски — §Р3; падающая integration-проба до кода
   (сценарии 08–11, 14), обе стороны каждой оси; причина изъятия гейта мутаций и проба её
   самоистечения — по §Р8.
3. **Край:** записи каталога прав (`gateway/internal/middleware/embed/permission_catalog.json`), allowlist, регистрация на обоих
   mux; сценарии 12, 15, 17 — Go-пробы края; положительный близнец к П9.
4. **Сквозная проба newman** на внешнем крае: сценарии 01–07, 09, 10, 12, 13, 16 и по одному
   кейсу отображения на каждый код отказа; коллекция — с записью ведомости производителя;
   `admin-not-on-public.py` — со сменой представителя §Р7; `TestNewmanCollectionsSendNoUnknownRequestFields`
   зелёный.
5. **Конструируемость посевом:** все объекты сценариев 01–16 заводятся самой пробой с
   суффиксом `{{runId}}` и снимаются ею; принципалы — `jwtBootstrap` и `jwtPureNoBindings`
   из `prodseed_matrix.py`; базовый каталог (П12) не используется как предмет мутаций. Для
   сценария 18 — **отдельный шаг-условие** прогона, утверждающий, что администратор-человек
   консоли держит `system_admin` @ `cluster` (вопрос модели прав), и падающий словами «условие
   не создано», а не молчаливый пропуск П13.
6. **Консоль:** §Р6; сценарии 18 (playwright на стенде внешней посадки) и 19 (компонентная
   проба); `geo.ts` и шапка реестра перестают утверждать «мутация по публичному пути не
   смаршрутизирована».
7. **Включение (решение владельца ws#951):** публичные глаголы включены во всех поставляемых
   профилях без отдельной ручки; изменение выкачено на стенд шагом после волны; сценарии 01–05
   и 18 повторены на выкаченном стенде, вывод — комментарием `DoD-proof @<sha>` в #3092 и #3094.
8. **Trail записок:** `resources/` и `rpc/` по geo Region/Zone — новые публичные глаголы,
   право, порог, следствие §Р3.
