# Конвенции API Kachō

Собственные конвенции продукта. Соблюдай их как нормативные требования (не как
подражание чужим облакам). Стиль выработан и зафиксирован — менять только осознанно.

## Форма ресурса — flat message + Operations

Каждый ресурс — **плоский** message с domain-полями на верхнем уровне (без
K8s-envelope `spec`/`status`/`metadata`/`resourceVersion`/`generation`/`finalizers`):

```protobuf
message Instance {
  string id = 1;
  string project_id = 2;
  google.protobuf.Timestamp created_at = 3;
  string name = 4;
  string description = 5;
  map<string,string> labels = 6;
  string zone_id = 7;
  Status status = 10;        // enum, не nested message
  // ...domain-specific поля плоско
}
```

Service-шаблон: **read — sync, мутации — async через `Operation`**:

```protobuf
service InstanceService {
  rpc Get(GetInstanceRequest) returns (Instance);                  // sync
  rpc List(ListInstancesRequest) returns (ListInstancesResponse);  // sync
  rpc Create(CreateInstanceRequest) returns (operation.Operation); // async
  rpc Update(UpdateInstanceRequest) returns (operation.Operation); // async
  rpc Delete(DeleteInstanceRequest) returns (operation.Operation); // async
}
```

`Operation` (`kacho.cloud.operation.v1`): `id`, `description`, `created_at`,
`done`, `metadata: Any`, `oneof result { google.rpc.Status error | Any response }`.
Клиент поллит `OperationService.Get(id)` до `done=true`. **Watch RPC не существует**
(полл List 2-5 c или Operation.Get для in-flight).

**`Operation.done` = durability предмета мутации, НЕ видимость downstream side-effect
(non-negotiable).** `done=true` означает «ресурс закоммичен» (`w.Commit()` в worker-fn) —
и ТОЛЬКО это. **Категорически запрещено гейтить `done` на видимость eventually-consistent
downstream-эффекта** (owner-tuple в OpenFGA, зеркало в другом сервисе, drain outbox): это
(а) переопределяет контракт Operation (ban #9 — предмет = «создать Network», не «распространить
FGA-tuple»); (б) на fail-closed рождает **phantom-ресурс** (row закоммичен, имя занято UNIQUE,
но op=ERROR → клиент видит fail → retry ловит `AlreadyExists` → get воспринимает как 404); (в)
конвертирует ограниченный read-after-write лаг в неограниченный hard-fail под нагрузкой на
downstream. Kachō **eventually-consistent by design** (async Operation, polling, replica isolation):
side-effect материализуется в ограниченном окне (at-least-once outbox+drainer+reconciler), а
«создал→сразу мутирую» обеспечивается **bounded client-retry** на кратком 403/404-окне, НЕ серверным
confirm-барьером. Инцидент owner-tuple-opgate (2026-07): confirm-gate на видимость owner-tuple
удалён по system-design-review как ban #9-нарушение (см. `data-integrity.md` cross-domain authz).

## Naming / формат

- **JSON (REST через api-gateway): camelCase** — `<resource>Id`, `projectId`, `labels`, `createdAt`.
- **REST-пути**: `/<service>/v1/<resource>`, suffix-actions через `:verb` (`/subnets/{id}:addCidrBlocks`).
- **Стандартные методы ресурса**: `Get`/`List` (sync) + `Create`/`Update`/`Delete` (async Operation).
  Доп. действия — отдельные RPC с `:verb`-путём.
- **Timestamps**: в proto-ответе truncate до **секунд** (`CreatedAt.Truncate(time.Second)`); БД хранит микросекунды.
- **ID**: `kacho-corelib/ids.NewID(<prefix>)` — 3-char prefix + 17-char crockford-base32. Тип ресурса читается по prefix.
- **id-prefix — hyphen-канон (going-forward, B3)**: **новые** ресурсы адресуются формой
  `<prefix>-<crockford-base32>` (`ins-…`, `ns-…`, `mt-…`) — дефис-разделитель, prefix бывает
  2+ символа (не фикс-3). Legacy слитная форма `<prefix><17-base32>` (`net…`, `epd…`) остаётся
  валидной; сервисы мигрируют свой prefix **по одному** в собственном редизайне. Router
  `corevalidate.ResourceID` классифицирует **обе** формы **аддитивно** (legacy-приём не отзывается):
  крокфорд-тело дефиса не содержит → дефис = однозначный дискриминатор новой формы. Канон
  hyphen-префиксов — `ids.KnownHyphenPrefixes()` (единый источник) + config-extra
  `KACHO_EXTRA_RESOURCE_ID_HYPHEN_PREFIXES` (новый домен без релиза corelib). **`NewID`-генерация
  ещё НЕ мигрирована** (эмитит legacy 3-char) — Phase-0-фундамент только учит router принимать
  hyphen **вперёд** миграции сервисов.

## Error-format

- gRPC `status.Error(code, message)`; REST через grpc-gateway → `{code, message, details:[]}` + `google.rpc.Status`.
- Коды: `INVALID_ARGUMENT` (формат/валидация), `NOT_FOUND` (well-formed-но-нет),
  `FAILED_PRECONDITION` (состояние ресурса не позволяет), `ALREADY_EXISTS` (UNIQUE),
  `UNAVAILABLE` (peer недоступен — fail-closed для мутаций), `INTERNAL` (фикс. текст, **без leak'а pgx/SQL**).
- Тон сообщений — единый и стабильный: `"<Resource> %s not found"`,
  `"<field> is immutable after <Resource>.Create"`, `"Illegal argument <thing>"`,
  `"network is not empty"`. Тексты — часть контракта; меняются только осознанно (через тикет).
- malformed id → sync `InvalidArgument "invalid <res> id '<X>'"` первым стейтментом RPC
  (`corevalidate.ResourceID`); well-formed-но-нет → `NotFound` через `repo.Get`.

### By-lane code-split — NOT_FOUND vs FAILED_PRECONDITION по **линии** резолва id (обязательно)

Код «id well-formed, но не резолвится» зависит от **линии**, а не от ресурса:

- **direct-read lane** — own-owned id, `repo.Get` **своей** БД → нет строки = **`NOT_FOUND`**
  (`"<Resource> <id> not found"`). Это «я не нашёл СВОЙ ресурс».
- **peer-validate lane** — foreign id, cross-service peer-вызов владельцу на request-path
  (`Create`/`Update`) → нет/не то состояние у владельца = **`FAILED_PRECONDITION`** (НЕ NOT_FOUND:
  consumer не «не нашёл своё», а «предусловие на ЧУЖОЙ ресурс не выполнено»); владелец недоступен =
  **`UNAVAILABLE`** (fail-closed для мутаций).
- **Format-check — только own-owned id** (B4): malformed own-id → sync `INVALID_ARGUMENT`
  (`corevalidate.ResourceID`, prefix-router); foreign id **не** prefix-checked — existence-only
  peer-validate (чужой prefix — не наш словарь).

Клиент **машинно** различает линии по **`reason`-token** в `rpc.Status.details`
(`google.rpc.ErrorInfo.reason`), НЕ парся прозу message (тон message стабилен, но не парсибелен).
`ErrorInfo.domain = "<service>.kacho.cloud"`, `metadata = {resource_type, resource_id}`:

| `reason` | code | линия | смысл |
|---|---|---|---|
| `INVALID_RESOURCE_ID` | INVALID_ARGUMENT | sync-format | malformed own-id (prefix-router, первым стейтментом) |
| `RESOURCE_NOT_FOUND` | NOT_FOUND | direct-read | own-owned id well-formed, строки в своей БД нет |
| `PEER_RESOURCE_MISSING` | FAILED_PRECONDITION | peer-validate | foreign id не существует у владельца |
| `PEER_RESOURCE_STATE` | FAILED_PRECONDITION | peer-validate | foreign ресурс есть, состояние не позволяет |
| `PEER_UNAVAILABLE` | UNAVAILABLE | peer-validate | владелец недоступен (fail-closed мутации) |

Split энфорсится **на обеих сторонах**: geo Region/Zone.Get **direct** → `RESOURCE_NOT_FOUND`/NOT_FOUND
(GEO-1-34/35); consumer (vpc/compute/nlb), валидируя `zoneId`/`regionId` **peer** через geo, на geo-miss
маппит в `PEER_RESOURCE_MISSING`/FAILED_PRECONDITION. Regression: assert `reason`-token И code (не только
code) — тон message остаётся стабильным контрактом, но клиент ключуется на token.

## update_mask discipline

`Update` принимает `google.protobuf.FieldMask update_mask`:
- mask содержит **unknown** поле → `InvalidArgument` (`corevalidate.UpdateMask` с known-set).
- mask содержит **hard-immutable** поле → `InvalidArgument` (`"<field> is immutable after <R>.Create"`).
- mask **пустой** → full-object PATCH: применяются все mutable-поля; immutable из тела silently игнорируются.
- mask содержит mutable поле → применяется; валидируется по тем же правилам, что Create.

Единая дисциплина для всех ресурсов всех сервисов (parity по форме между ресурсами обязателен).

## Структура ресурсов — проектируем удобно

Состав ресурсов/методов проектируем в чистой форме под задачу, не копируя ничей
чужой API: `NetworkInterface` — first-class ресурс VPC (ENI-подобная модель, NIC
отдельно от Instance); `AddressPool` — admin-only ресурс (Internal*); oneof/replace-
семантика там, где удобнее (напр. AddressPool split v4/v6, KAC-71). Осознанные
дизайн-решения документируй в `docs/architecture/` соответствующего сервиса.

## Reference-типы — 3-way naming (B1, НЕ overload одного идентификатора)

Три РАЗНЫЕ семантики ссылки — три разных типа. **Переименование landed-типов запрещено**
(сломало бы wire-форму) — disambiguation достигается именами, не relocation:

- **`reference.Referrer{type,id,name°}`** (пакет `kacho.cloud.reference`) — generic **cross-owner
  dependency handle** (class-C, graceful-dangling: референт удалён → DETACHED/degraded, не паника).
  `type` — dotted `domain.resource` из shared-каталога; `name°` — output-only best-effort зеркало
  на момент привязки. Плюс `reference.Reference{referrer,type(MANAGED_BY|USED_BY),owned}` (reverse).
  Landed: vpc (NIC/Address/SG `usedBy°`), storage (Volume `usedBy°`), compute (`Instance.serviceAccountId`).
- **`iam.v1.ResourceRef{type,id}`** — **closed-table authz/AccessBinding target** (БЕЗ `name`;
  `type` — из закрытого FGA object-type словаря). Живёт в `authorize_service.proto` (пакет
  `kacho.cloud.iam.v1`); переиспользуется `AccessBinding.target` **в том же пакете** через import —
  БЕЗ relocation (F8 iam-редизайн добавляет поле; wire/Go-тип `iamv1.ResourceRef` уже доступен,
  buf-clean). НЕ несёт `name` (least-info, anti-oracle).
- **`OciReferrer`/`ArtifactRef`** — **OCI-1.1 artifact-граф** registry (подпись/SBOM/аттестация).
  Сейчас `Referrer` в пакете `kacho.cloud.registry.v1` (FQN отличается от generic — коллизии нет,
  только читаемостная неоднозначность). Каноничный rename → `OciReferrer` вводится в **REG-2**
  (buf-breaking, registry-домен) — Phase-0 НЕ добавляет мёртвый скелет (LEAN, ban #11).

Правило выбора: dependency-handle → **`Referrer`**; authz-target → **`ResourceRef`**; OCI-граф →
**`OciReferrer`**. Один и тот же id в разных ролях — разные типы, не overload.

## Pagination / filter

- Cursor-based: `(created_at, id)` ORDER BY ASC; `page_token` — opaque base64 `{created_at,id}`.
- `page_size` через `corevalidate.PageSize` (0 → default 50, max 1000); garbage token → `InvalidArgument`.
  page_size вне `[0..1000]` → `InvalidArgument` (**отвергается, не clamp'ится**).
- `filter` — `kacho-corelib/filter.Parse` с whitelist полей (текущая фаза — `name=`).
- **Валидация pagination — ДО listauthz empty-grant short-circuit** (см. Gotcha ниже).

## Gotcha'и (выведены из audit-раундов — частые нарушения конвенций)

- **Timestamp truncate — на КАЖДОМ ресурсе И под-записи.** `.Truncate(time.Second)` для
  `created_at`/`updated_at` во ВСЕХ proto-ответах, включая вложенные сущности (напр.
  `AddressPoolAddressEntry`, а не только «главный» `AddressPool`). Микросекунды с БД не текут на wire.
- **Malformed-id — ПЕРВЫМ стейтментом RPC.** `corevalidate.ResourceID(id, <prefix>)` до любого
  repo-вызова → sync `InvalidArgument "invalid <res> id '<X>'"`. Без format-check malformed-id
  уходит в `repo.Get` и возвращает `NotFound` (неверно). well-formed-но-нет → `NotFound`.
- **Immutable-check в Update — ДО `corevalidate.UpdateMask`.** known-set маски НЕ содержит
  immutable-полей, поэтому `UpdateMask` отвергнет их первым как generic «unknown field» вместо
  конвенционного `"<field> is immutable after <R>.Create"`. Порядок: immutable-switch → UpdateMask.
- **DEFERRABLE INITIALLY DEFERRED FK — 23503 на COMMIT, не на INSERT.** Ошибка приходит из
  `tx.Commit()`, а не из INSERT-стейтмента → маршрутизируй **commit-ошибку** через
  constraint-aware mapper (с owner-id hint), а не sentinel-only fallback, иначе 23503 попадёт в
  INTERNAL вместо `FailedPrecondition "User <id> not found"`. (Deferral — осознанный, для
  order-independence сидов; см. `data-integrity.md` SQLSTATE-маппинг.)
- **List: валидация pagination — ДО listauthz empty-grant short-circuit.** List-хендлеры с
  per-object listauthz (compute/nlb/vpc) при пустом гранте (`len(AllowedIDs)==0`) отдают пустую
  страницу РАНО — часто и в use-case, и в repo — **до** того как repo декодирует/валидирует
  `page_token`/`page_size`. Тогда malformed-token / `page_size>1000` при пустом гранте утекают в
  `200 {[]}` вместо `400 InvalidArgument` — расхождение с конвенцией и между сервисами
  (реальный баг: compute disk/image/nlb; vpc был эталоном — валидирует рано). Порядок в хендлере:
  **`ValidatePagination(page_token, page_size)` → listauthz-resolve → empty-grant short-circuit →
  repo**. Repo-декод остаётся authoritative backstop; sync-guard в use-case/handler делает 400
  детерминированным независимо от grant-state. Regression: unit на `ValidatePagination`
  (garbage-token/`>1000` → `InvalidArgument`) в КАЖДОМ сервисе с этим паттерном.
