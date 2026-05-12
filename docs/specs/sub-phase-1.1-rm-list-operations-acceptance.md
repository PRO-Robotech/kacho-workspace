# Sub-phase 1.1 (Resource Manager — ListOperations) — Acceptance

**Документ:** acceptance / sub-phase 1.1
**Дата:** 2026-05-11
**Статус:** Draft, на ревью
**Источник требований:** `01-architecture-and-services.md` (API contract — Operations); workspace `CLAUDE.md` §«API contract — flat resources + Operations»; verbatim YC parity (`/resource-manager/v1/clouds/{cloud_id}/operations`, `/resource-manager/v1/folders/{folder_id}/operations`).
**Утверждение:** approve выставляет агент `acceptance-reviewer`.

---

## 0. Цель sub-итерации

Распространить уже работающий в `kacho-vpc` паттерн per-resource `ListOperations` на `kacho-resource-manager` для ресурсов **Cloud** и **Folder**. После этой итерации UI и `yc` CLI могут получать историю операций конкретного облака/папки тем же способом, как они уже делают для VPC-ресурсов.

**В скоупе:**
- `CloudService.ListOperations` (REST: `GET /resource-manager/v1/clouds/{cloud_id}/operations`).
- `FolderService.ListOperations` (REST: `GET /resource-manager/v1/folders/{folder_id}/operations`).
- `OrganizationService.ListOperations` (REST: `GET /organization-manager/v1/organizations/{organization_id}/operations`).
- service-слой: `Cloud/Folder/Organization.ListOperations(ctx, id, Pagination) → ([]operations.Operation, string, error)`.
- handler-слой: маппинг proto request/response, `*_id` validation.
- api-gateway allowlist: добавить три новых full-method names.
- unit-тесты handler + service.

**Вне скоупа:**
- Compute / LoadBalancer ListOperations — отдельный sub-phase (по решению заказчика только RM + VPC сейчас).
- Централизованный `OperationService.List` с фильтром по ресурсу — намеренно не делаем (YC parity: только per-resource list внутри домена).
- Изменение proto-контракта — `ListCloudOperations*` / `ListFolderOperations*` уже определены в `kacho-proto/proto/kacho/cloud/resourcemanager/v1/{cloud,folder}_service.proto`.
- Изменение `opsproxy` — префиксы `b1g`/`bpf` для resourcemanager уже зарегистрированы; ListOperations всё равно идёт прямо в RM, не через opsproxy.
- IAM-проверки на operations (предполагаем что вызывающий имеет права на ресурс — handler делает `Get` ресурса до возврата операций; в текущей фазе AAA — заглушка).

**Зафиксированные соглашения:**
- Пагинация — cursor-based, как в VPC (`(created_at, id)` ORDER BY ASC).
- `page_size` по умолчанию — 50 (как в `operations.Repo.List`).
- `page_token` opaque base64.
- `cloud_id` / `folder_id` пустой → `INVALID_ARGUMENT` синхронно.
- Несуществующий `cloud_id` / `folder_id` → `NOT_FOUND` (handler делает `Get` перед List).
- `resource_id` в операциях резолвится автоматически через protobuf-reflection в `operations.Repo.Create` (поля метаданных с суффиксом `_id`: `cloud_id`, `folder_id`).

---

## 1. Группа A — Service слой

### A1. CloudService.ListOperations возвращает операции конкретного cloud

**Given** есть Cloud `c1` в БД
**And** в `operations` есть 3 записи с `resource_id=c1` и 2 записи с `resource_id=c2`

**When** вызывается `CloudService.ListOperations(ctx, "c1", Pagination{PageSize: 50})`

**Then** возвращается ровно 3 операции
**And** все они имеют `resource_id=c1` (через metadata.cloud_id)
**And** `nextPageToken == ""` (помещаются в одну страницу)

### A2. CloudService.ListOperations пагинируется

**Given** есть Cloud `c1`
**And** в `operations` есть 75 записей с `resource_id=c1`

**When** вызывается `ListOperations(ctx, "c1", Pagination{PageSize: 50})`
**Then** возвращается 50 операций
**And** `nextPageToken != ""`

**When** повторно вызывается с этим `pageToken`
**Then** возвращается 25 операций
**And** `nextPageToken == ""`

### A3. CloudService.ListOperations отдаёт NotFound для несуществующего cloud

**Given** Cloud `c-missing` отсутствует

**When** вызывается `ListOperations(ctx, "c-missing", Pagination{})`

**Then** возвращается ошибка с gRPC code `NOT_FOUND`
**And** текст ошибки соответствует verbatim YC: `"Cloud %s not found"` или эквивалент через `mapRepoErr`.

### A4. FolderService.ListOperations — аналогичные A1–A3 сценарии для Folder

Те же сценарии для `FolderService.ListOperations(ctx, folderID, Pagination)`.

---

## 2. Группа B — Handler слой

### B1. CloudHandler.ListOperations требует cloud_id

**Given** handler инициализирован

**When** вызывается `ListOperations(ctx, &rmpb.ListCloudOperationsRequest{CloudId: ""})`

**Then** возвращается ошибка `INVALID_ARGUMENT` с сообщением `cloud_id required`.

### B2. CloudHandler.ListOperations маппит результат в proto

**Given** service-слой замокан и возвращает 2 `operations.Operation`

**When** вызывается handler.ListOperations с непустым `CloudId`

**Then** возвращается `*rmpb.ListCloudOperationsResponse` с `Operations` длиной 2
**And** каждый элемент `Operations[i]` — это `operationToProto(&ops[i])` (зеркалит уже используемый mapping).

### B3. FolderHandler.ListOperations — аналогичные B1–B2 сценарии для Folder.

---

## 3. Группа C — API Gateway integration

### C1. Allowlist содержит новые RPC

**Given** gateway собран

**Then** `allowlist.Allow` содержит:
- `/kacho.cloud.resourcemanager.v1.CloudService/ListOperations`
- `/kacho.cloud.resourcemanager.v1.FolderService/ListOperations`

### C2. REST-route доступен через gateway

**Given** деплой kind поднят с обновлёнными rm + gateway

**When** клиент шлёт `GET http://gateway/resource-manager/v1/clouds/{id}/operations` для существующего cloud

**Then** возвращается HTTP 200 с JSON `{ "operations": [...], "nextPageToken": "" }`.

---

## 4. Definition of Done

- [ ] Все сценарии §1–3 покрыты unit-тестами (service: моки `CloudRepo`, `FolderRepo`, `operations.Repo`; handler: моки `*Service`).
- [ ] `go test ./...` зелёный в `kacho-resource-manager` и `kacho-api-gateway`.
- [ ] `go build ./...` зелёный в обоих репо.
- [ ] kind-стенд поднят (`make dev-up`), `make reload-svc SVC=resource-manager` + `SVC=api-gateway` прошли без ошибок.
- [ ] Smoke-curl C2 (через port-forward на api-gateway) возвращает 200 с операцией от предшествующего `Create cloud`.
