# Sub-phase 0.7 (UI + BFF — kacho-ui-bff + kacho-ui) — Acceptance

**Документ:** acceptance / sub-phase 0.7
**Дата:** 2026-05-03
**Статус:** Draft, на ревью
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.7»; `01-architecture-and-services.md` §2–§3; `02-data-model-and-conventions.md` §1–§2, §6–§8, §14; `00-overview-and-scope.md`; `CLAUDE.md` — запреты #2 (#7 не применяется: BFF — не api-gateway, Internal-методы сюда не дотягиваются).
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.7 добавляет к платформе Kachō Web-интерфейс, построенный по стандартному стеку PRO-Robotech: `kacho-ui` (Vite + React + TypeScript, основан на шаблоне `openapi-ui`) и `kacho-ui-bff` (Go) — Backend-for-Frontend, транслирующий K8s-style HTTP/WebSocket запросы от `@prorobotech/openapi-k8s-toolkit` в gRPC-вызовы к `kacho-api-gateway`. BFF обеспечивает K8s API envelope (`apiVersion/kind/metadata/spec/status`) поверх Kachō-envelope, реализует discovery (OpenAPI-спека, `getKinds`), folder-to-namespace маппинг, RBAC-заглушку и WebSocket-Watch. UI кастомизируется через переменные среды и навигационные CRD (`front.in-cloud.io/v1alpha1`). После завершения итерации браузерный клиент может просматривать и редактировать все ресурсы всех доменов через единый UI, не делая прямых gRPC-вызовов.

**Что НЕ входит в 0.7** (явно отложено):

- AAA (auth, authorization, audit) — RBAC-заглушка всегда возвращает `allowed: true`; никакой реальной проверки прав.
- TLS на edge — cleartext HTTP, аналогично прочим сервисам.
- Реальный multi-cluster — только один виртуальный кластер `kacho`.
- OpenAPI-спека из buf-плагина — если buf-плагин для openapi-v3 не готов, BFF генерирует hand-rolled спеку; выбор фиксируется в §1.
- Pagination в UI — BFF запрашивает до 1000 ресурсов; полноценная paginated прокрутка отложена.
- Реальный server-push (SSE, long-poll fallback) — только WebSocket Watch.

**Зафиксированные соглашения:**

- **K8s-group-mapping:** каждый Kachō-домен публикуется как отдельная API-группа вида `<domain>.kacho.cloud/v1` (например, `vpc.kacho.cloud/v1`). Plural-имена — нижний регистр, слитно (таблица в §0.1).
- **K8s-namespace = folder-uid:** BFF использует `metadata.namespace` как `folderId`. Кластерно-scoped ресурсы (Organization, Cloud) не имеют namespace.
- **K8s-envelope shape:** BFF преобразует каждый Kachō-ресурс в объект:
  ```json
  {
    "apiVersion": "<domain>.kacho.cloud/v1",
    "kind": "<Kind>",
    "metadata": {
      "uid": "<kacho-uid>",
      "name": "<kacho-name>",
      "namespace": "<folder-uid>",
      "labels": {},
      "annotations": {},
      "creationTimestamp": "<ISO8601>",
      "resourceVersion": "<decimal-string>"
    },
    "spec": { ... },
    "status": { ... }
  }
  ```
  Кластерно-scoped объекты не содержат поле `namespace`.
- **Watch-message shape (WebSocket):** каждое сообщение — JSON-строка `{"type":"ADDED"|"MODIFIED"|"DELETED","object":{...K8s-envelope...}}`, разделённые `\n`.
- **OpenAPI-спека:** генерируется BFF вручную (hand-rolled) на основе информации из статической таблицы `kindRegistry`. Buf-плагин для openapi-v3 — отдельная задача вне scope 0.7 (OQ-1).
- **BFF-адрес api-gateway:** `KACHO_BFF_GATEWAY_ADDR` (env, default `api-gateway.kacho.svc.cluster.local:9090` — прямой gRPC, не REST).
- **Имена integration-тест-функций:** `Test<Component>_<ScenarioID>_<ShortDesc>` (например, `TestBFF_A1_ClusterList`). E2e bash-скрипты — `kacho-deploy/e2e/0.7/<ID>-<short-desc>.sh`.
- Все временны́е assertion-ы (Watch, lifecycle) используют таймаут 60 секунд.

### §0.1 Таблица маппинга ресурсов

| Kachō ресурс | K8s group | version | plural | kind | Scoped |
|---|---|---|---|---|---|
| Organization | `resourcemanager.kacho.cloud` | `v1` | `organizations` | `Organization` | cluster |
| Cloud | `resourcemanager.kacho.cloud` | `v1` | `clouds` | `Cloud` | cluster |
| Folder | `resourcemanager.kacho.cloud` | `v1` | `folders` | `Folder` | cluster |
| Network | `vpc.kacho.cloud` | `v1` | `networks` | `Network` | namespaced |
| Subnet | `vpc.kacho.cloud` | `v1` | `subnets` | `Subnet` | namespaced |
| SecurityGroup | `vpc.kacho.cloud` | `v1` | `securitygroups` | `SecurityGroup` | namespaced |
| RouteTable | `vpc.kacho.cloud` | `v1` | `routetables` | `RouteTable` | namespaced |
| Address | `vpc.kacho.cloud` | `v1` | `addresses` | `Address` | namespaced |
| Instance | `compute.kacho.cloud` | `v1` | `instances` | `Instance` | namespaced |
| Disk | `compute.kacho.cloud` | `v1` | `disks` | `Disk` | namespaced |
| Image | `compute.kacho.cloud` | `v1` | `images` | `Image` | namespaced |
| Snapshot | `compute.kacho.cloud` | `v1` | `snapshots` | `Snapshot` | namespaced |
| NetworkLoadBalancer | `loadbalancer.kacho.cloud` | `v1` | `networkloadbalancers` | `NetworkLoadBalancer` | namespaced |
| TargetGroup | `loadbalancer.kacho.cloud` | `v1` | `targetgroups` | `TargetGroup` | namespaced |

---

## 1. Группа A — kacho-ui-bff: cluster discovery и базовые endpoint-ы

Сценарии группы A проверяют базовую инфраструктуру BFF: список кластеров, встроенные заглушки и health-probe.

### A1. GET /api/clusters возвращает список с единственным виртуальным кластером `kacho`

**ID:** 0.7-A1

**Given** `kacho-ui-bff` запущен с `KACHO_BFF_CLUSTER_NAME=kacho` (env, default `kacho`)

**When** клиент отправляет:
```
GET /api/clusters
```

**Then** HTTP status 200, Content-Type: application/json
**And** тело содержит массив с одним элементом:
```json
[{"name": "kacho", "displayName": "Kachō", "apiVersion": "v1"}]
```
**And** ответ приходит за < 200 мс (static response, без вызова gRPC)

### A2. GET /api/clusters/{cluster}/k8s/api/v1 возвращает built-in resources stub

**ID:** 0.7-A2

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/api/v1
```

**Then** HTTP status 200
**And** тело содержит поле `"kind": "APIResourceList"` и поле `"resources"` — массив (возможно пустой или содержащий `namespaces`)
**And** BFF не обращается к gRPC (статическая заглушка)

### A3. Неизвестный кластер в path возвращает 404

**ID:** 0.7-A3

**Given** BFF запущен с единственным кластером `kacho`

**When** клиент отправляет:
```
GET /api/clusters/unknown-cluster/k8s/api/v1
```

**Then** HTTP status 404
**And** тело содержит поле `"message"` с описанием «cluster not found»

### A4. /healthz BFF возвращает 200 OK

**ID:** 0.7-A4

**Given** BFF запущен (независимо от доступности api-gateway)

**When** клиент отправляет:
```
GET /healthz
```

**Then** HTTP status 200
**And** тело = `"ok"` или `{"status":"ok"}`

### A5. /readyz возвращает 200 когда api-gateway доступен

**ID:** 0.7-A5

**Given** BFF запущен
**And** api-gateway доступен по `KACHO_BFF_GATEWAY_ADDR` (gRPC Health.Check возвращает SERVING)

**When** клиент отправляет:
```
GET /readyz
```

**Then** HTTP status 200
**And** тело содержит `{"status":"ok"}`

### A6. /readyz возвращает 503 когда api-gateway недоступен

**ID:** 0.7-A6

**Given** BFF запущен
**And** api-gateway недоступен (`KACHO_BFF_GATEWAY_ADDR=localhost:1`)

**When** клиент отправляет:
```
GET /readyz
```

**Then** HTTP status 503
**And** тело содержит `{"status":"not_ready","reason":"gateway unreachable"}` или аналог

---

## 2. Группа B — OpenAPI discovery (swagger, getKinds)

Сценарии группы B проверяют discovery-endpoint-ы, используемые `@prorobotech/openapi-k8s-toolkit` для построения навигации.

### B1. GET openapi-bff/swagger/{cluster} возвращает валидную OpenAPI v3 спеку

**ID:** 0.7-B1

**Given** BFF запущен с зарегистрированными 14 ресурсами (таблица §0.1)

**When** клиент отправляет:
```
GET /api/clusters/kacho/openapi-bff/swagger/swagger/kacho
```

**Then** HTTP status 200, Content-Type: application/json
**And** тело содержит поле `"openapi": "3.0.x"` или `"3.1.x"`
**And** тело содержит поле `"info.title"` = `"Kachō API"` (или `"kacho"`)
**And** раздел `"paths"` содержит записи для каждого ресурса из таблицы §0.1 (≥ 14 групп путей)
**And** каждый путь для namespaced-ресурса содержит параметр `"namespace"` в path
**And** кластерно-scoped ресурсы (Organization, Cloud, Folder) не содержат параметр `"namespace"` в path

### B2. GET openapi-bff/search/kinds/getKinds возвращает список Kind-ов с group/version/plural

**ID:** 0.7-B2

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/openapi-bff/search/kinds/getKinds
```

**Then** HTTP status 200, Content-Type: application/json
**And** тело содержит массив с ≥ 14 элементами
**And** каждый элемент содержит поля `"group"`, `"version"`, `"kind"`, `"plural"`, `"namespaced": true/false`
**And** присутствует элемент `{"group":"vpc.kacho.cloud","version":"v1","kind":"Network","plural":"networks","namespaced":true}`
**And** присутствует элемент `{"group":"resourcemanager.kacho.cloud","version":"v1","kind":"Organization","plural":"organizations","namespaced":false}`

### B3. getKinds содержит Folder с namespaced=false (кластерно-scoped)

**ID:** 0.7-B3

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/openapi-bff/search/kinds/getKinds
```

**Then** в ответе присутствует элемент с `"kind":"Folder"` и `"namespaced":false`
**And** тот же элемент имеет `"group":"resourcemanager.kacho.cloud"`

### B4. OpenAPI спека содержит схемы spec и status для Instance

**ID:** 0.7-B4

**Given** BFF запущен

**When** клиент получает спеку (`B1`) и смотрит схему для `Instance`

**Then** компонент `"schemas.Instance"` или путь для `instances` содержит вложенные поля `"spec"` и `"status"`
**And** `"spec"` содержит как минимум `"platformId"`, `"zoneId"`, `"resources"`, `"desiredPowerState"`
**And** `"status"` содержит как минимум `"state"`

### B5. Повторный вызов getKinds идемпотентен (same response)

**ID:** 0.7-B5

**Given** BFF запущен

**When** клиент дважды вызывает `GET /api/clusters/kacho/openapi-bff/search/kinds/getKinds`

**Then** оба ответа идентичны по составу (порядок элементов может отличаться)
**And** BFF не делает gRPC-вызовов (kindRegistry статичен)

---

## 3. Группа C — K8s envelope translation (Kachō → K8s)

Сценарии группы C проверяют корректность преобразования Kachō-envelope в K8s-формат на уровне конкретных полей.

### C1. Kachō Network преобразуется в K8s-envelope с корректными полями

**ID:** 0.7-C1

**Given** BFF получил от `kacho-api-gateway` (`NetworkService/List`) ресурс Network:
```json
{
  "metadata": {
    "uid": "net-uid-1234",
    "name": "my-net",
    "folderId": "folder-uid-abcd",
    "cloudId": "cloud-uid-xyz",
    "organizationId": "org-uid-xyz",
    "labels": {"env": "dev"},
    "creationTimestamp": "2026-05-03T10:00:00Z",
    "resourceVersion": "42"
  },
  "spec": {"displayName": "My Network"},
  "status": {"state": "ACTIVE"}
}
```

**When** BFF преобразует ресурс в K8s-envelope

**Then** результирующий объект содержит:
  - `apiVersion` = `"vpc.kacho.cloud/v1"`
  - `kind` = `"Network"`
  - `metadata.uid` = `"net-uid-1234"`
  - `metadata.name` = `"my-net"`
  - `metadata.namespace` = `"folder-uid-abcd"` (= folderId)
  - `metadata.labels.env` = `"dev"`
  - `metadata.creationTimestamp` = `"2026-05-03T10:00:00Z"`
  - `metadata.resourceVersion` = `"42"`
  - `spec.displayName` = `"My Network"`
  - `status.state` = `"ACTIVE"`
**And** объект НЕ содержит поля `metadata.folderId`, `metadata.cloudId`, `metadata.organizationId` на верхнем уровне metadata (они не K8s-стандартные; могут присутствовать в `metadata.annotations` или `spec` — на усмотрение BFF)

### C2. Кластерно-scoped Organization не содержит поле namespace в metadata

**ID:** 0.7-C2

**Given** BFF получил от api-gateway Organization с `metadata.name = "default-org"`, `metadata.uid = "org-uid-1"`

**When** BFF преобразует ресурс

**Then** результирующий K8s-объект содержит:
  - `apiVersion` = `"resourcemanager.kacho.cloud/v1"`
  - `kind` = `"Organization"`
  - `metadata.uid` = `"org-uid-1"`
  - `metadata.name` = `"default-org"`
**And** поле `metadata.namespace` **отсутствует** (Organization — cluster-scoped)

### C3. Instance с lifecycle-status корректно преобразуется

**ID:** 0.7-C3

**Given** BFF получил от api-gateway Instance:
```json
{
  "metadata": {"uid": "inst-uid-1", "name": "vm-01", "folderId": "folder-1"},
  "spec": {"platformId": "standard-v3", "desiredPowerState": "RUNNING"},
  "status": {"state": "RUNNING", "ips": {"internal": "10.0.0.5"}}
}
```

**When** BFF преобразует ресурс

**Then** K8s-объект содержит:
  - `apiVersion` = `"compute.kacho.cloud/v1"`
  - `kind` = `"Instance"`
  - `metadata.namespace` = `"folder-1"`
  - `status.state` = `"RUNNING"`
  - `status.ips.internal` = `"10.0.0.5"`

### C4. Обратное преобразование K8s-envelope → Kachō-upsert payload корректно

**ID:** 0.7-C4

**Given** UI посылает в BFF POST для создания Network:
```json
{
  "apiVersion": "vpc.kacho.cloud/v1",
  "kind": "Network",
  "metadata": {
    "name": "new-net",
    "namespace": "folder-uid-abcd",
    "labels": {"team": "infra"}
  },
  "spec": {"displayName": "New Network"}
}
```

**When** BFF конвертирует запрос в Kachō-upsert payload для `NetworkService/Upsert`

**Then** итоговый Kachō-payload содержит:
  - `metadata.name` = `"new-net"`
  - `metadata.folderId` = `"folder-uid-abcd"` (из `metadata.namespace`)
  - `metadata.labels.team` = `"infra"`
  - `spec.displayName` = `"New Network"`
**And** поле `status` в Kachō-payload отсутствует или пустое (status не передаётся через upsert — запрет #6)

### C5. resourceVersion в K8s-envelope — строка, даже если Kachō возвращает число

**ID:** 0.7-C5

**Given** BFF получает от api-gateway `metadata.resourceVersion = 100` (числовое значение в JSON)

**When** BFF строит K8s-envelope

**Then** `metadata.resourceVersion` в ответе — JSON-строка `"100"`, не число `100`

---

## 4. Группа D — Resource List (GET k8s/apis/.../plural)

Сценарии группы D проверяют endpoint LIST для каждой группы ресурсов.

### D1. List Networks (namespaced) с фильтрацией по namespace (folderId)

**ID:** 0.7-D1

**Given** BFF запущен, api-gateway доступен
**And** В Folder `folder-uid-abcd` существуют Network `net-1` и `net-2`
**And** В другом Folder `folder-uid-xyz` существует Network `net-3`

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-abcd/networks
```

**Then** HTTP status 200
**And** тело содержит `"kind": "NetworkList"`, `"apiVersion": "vpc.kacho.cloud/v1"`
**And** поле `"items"` содержит ровно 2 элемента (`net-1`, `net-2`)
**And** каждый элемент имеет K8s-envelope shape (apiVersion, kind, metadata.uid, metadata.name, metadata.namespace = `"folder-uid-abcd"`)
**And** `net-3` отсутствует в ответе
**And** BFF вызвал gRPC `NetworkService/List` с selector `folderId = "folder-uid-abcd"`

### D2. List Networks без указания namespace возвращает все сети (cluster-wide)

**ID:** 0.7-D2

**Given** В системе существуют Network в нескольких Folder

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/networks
```

**Then** HTTP status 200
**And** `"items"` содержит все Networks из всех Folder
**And** BFF вызвал `NetworkService/List` с пустым selector-ом (или без folderId-фильтра)

### D3. List Organizations (cluster-scoped) не требует namespace в path

**ID:** 0.7-D3

**Given** В системе существует default Organization

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/resourcemanager.kacho.cloud/v1/organizations
```

**Then** HTTP status 200
**And** `"kind"` = `"OrganizationList"`
**And** `"items"` содержит как минимум одну Organization
**And** элементы не содержат поле `metadata.namespace`

### D4. List Instances возвращает только ресурсы целевого Folder

**ID:** 0.7-D4

**Given** В Folder `folder-uid-1` существуют Instance `vm-1` и `vm-2`

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/compute.kacho.cloud/v1/namespaces/folder-uid-1/instances
```

**Then** `"items"` содержит ровно 2 элемента
**And** каждый item имеет `"kind": "Instance"` и `"metadata.namespace": "folder-uid-1"`

### D5. List для пустого Folder возвращает пустой items-массив

**ID:** 0.7-D5

**Given** Folder `empty-folder-uid` существует, но не содержит ни одного ресурса vpc.kacho.cloud

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/empty-folder-uid/networks
```

**Then** HTTP status 200
**And** `"items"` = `[]`
**And** BFF вернул успех (не 404)

### D6. List для несуществующего group/version возвращает 404

**ID:** 0.7-D6

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/unknown.kacho.cloud/v1/widgets
```

**Then** HTTP status 404
**And** тело содержит `{"kind":"Status","apiVersion":"v1","status":"Failure","reason":"NotFound","code":404}`

### D7. List NetworkLoadBalancers фильтруется по namespace

**ID:** 0.7-D7

**Given** В Folder `folder-lb-uid` существует NLB `nlb-1`

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/loadbalancer.kacho.cloud/v1/namespaces/folder-lb-uid/networkloadbalancers
```

**Then** HTTP status 200
**And** `"items"` содержит `nlb-1` с `"kind": "NetworkLoadBalancer"`

### D8. List содержит поле metadata.resourceVersion на уровне списка

**ID:** 0.7-D8

**Given** BFF выполнил List Networks

**When** клиент получает ответ

**Then** на верхнем уровне присутствует `"metadata": {"resourceVersion": "<string>"}` — snapshot-version для последующего Watch
**And** значение непустое

---

## 5. Группа E — Resource Get-by-name (GET .../plural/{name})

Сценарии группы E проверяют получение единичного ресурса.

### E1. GET Instance по имени в namespace возвращает один объект

**ID:** 0.7-E1

**Given** Instance `vm-01` существует в Folder `folder-uid-1` с uid `inst-uid-42`

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/compute.kacho.cloud/v1/namespaces/folder-uid-1/instances/vm-01
```

**Then** HTTP status 200
**And** тело содержит один K8s-объект (не список)
**And** `"kind"` = `"Instance"`
**And** `"metadata.name"` = `"vm-01"`
**And** `"metadata.uid"` = `"inst-uid-42"`
**And** `"metadata.namespace"` = `"folder-uid-1"`
**And** BFF вызвал `InstanceService/List` с selector `name = "vm-01", folderId = "folder-uid-1"` и взял первый элемент

### E2. GET несуществующего ресурса возвращает K8s NotFound Status

**ID:** 0.7-E2

**Given** Instance `nonexistent-vm` не существует в Folder `folder-uid-1`

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/compute.kacho.cloud/v1/namespaces/folder-uid-1/instances/nonexistent-vm
```

**Then** HTTP status 404
**And** тело содержит:
```json
{"kind":"Status","apiVersion":"v1","status":"Failure","reason":"NotFound","message":"instances \"nonexistent-vm\" not found","code":404}
```

### E3. GET Organization (cluster-scoped) по имени без namespace

**ID:** 0.7-E3

**Given** Organization `default` существует

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/resourcemanager.kacho.cloud/v1/organizations/default
```

**Then** HTTP status 200
**And** `"kind"` = `"Organization"`
**And** `"metadata.name"` = `"default"`
**And** поле `"metadata.namespace"` отсутствует

### E4. GET Network с некорректным именем (невалидный DNS-label) возвращает 400

**ID:** 0.7-E4

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-1/networks/INVALID_NAME_UPPER
```

**Then** HTTP status 400
**And** тело содержит `{"kind":"Status","reason":"BadRequest","code":400}` или аналог

### E5. GET ресурса возвращает status с lifecycle-полями

**ID:** 0.7-E5

**Given** Disk `disk-01` в состоянии `READY` существует в Folder `folder-uid-1`

**When** клиент отправляет GET по имени `disk-01`

**Then** ответ содержит `"status.state": "READY"`
**And** поле `"status"` присутствует и не пустое

---

## 6. Группа F — Resource Upsert (POST/PUT → Kachō Upsert RPC)

Сценарии группы F проверяют создание и обновление ресурсов через K8s-style POST/PUT.

### F1. POST создаёт новый Network (K8s POST → Kachō Upsert)

**ID:** 0.7-F1

**Given** BFF запущен, api-gateway доступен
**And** Folder `folder-uid-1` существует

**When** клиент отправляет:
```
POST /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-1/networks
Content-Type: application/json

{
  "apiVersion": "vpc.kacho.cloud/v1",
  "kind": "Network",
  "metadata": {"name": "new-network", "namespace": "folder-uid-1"},
  "spec": {"displayName": "New Network"}
}
```

**Then** HTTP status 201
**And** тело содержит K8s-объект с `"metadata.uid"` — непустой UUID
**And** `"metadata.name"` = `"new-network"`
**And** `"metadata.resourceVersion"` — непустая строка
**And** BFF вызвал `NetworkService/Upsert` с `metadata.name = "new-network"`, `metadata.folderId = "folder-uid-1"`

### F2. PUT обновляет существующий Network (K8s PUT → Kachō Upsert)

**ID:** 0.7-F2

**Given** Network `existing-net` существует в Folder `folder-uid-1` с uid `net-uid-existing`

**When** клиент отправляет:
```
PUT /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-1/networks/existing-net
Content-Type: application/json

{
  "apiVersion": "vpc.kacho.cloud/v1",
  "kind": "Network",
  "metadata": {"name": "existing-net", "namespace": "folder-uid-1", "uid": "net-uid-existing"},
  "spec": {"displayName": "Updated Network"}
}
```

**Then** HTTP status 200
**And** `"metadata.uid"` = `"net-uid-existing"` (тот же uid)
**And** `"spec.displayName"` = `"Updated Network"`
**And** `"metadata.resourceVersion"` изменился по сравнению с предыдущей версией

### F3. POST с полем status в теле — status игнорируется, не передаётся в Kachō Upsert

**ID:** 0.7-F3

**Given** BFF запущен
**And** Folder `folder-uid-1` существует

**When** клиент отправляет POST с телом, содержащим поле `"status": {"state": "RUNNING"}`:
```json
{
  "apiVersion": "compute.kacho.cloud/v1",
  "kind": "Instance",
  "metadata": {"name": "test-vm", "namespace": "folder-uid-1"},
  "spec": {"platformId": "standard-v3", "desiredPowerState": "RUNNING"},
  "status": {"state": "RUNNING"}
}
```

**Then** BFF НЕ передаёт поле `status` в `InstanceService/Upsert` payload (запрет #6)
**And** HTTP статус 201 или 200 (успех)
**And** `status.state` в ответе определяется reconciler-ом, а не переданным значением

### F4. POST с некорректным именем (не DNS-label) возвращает K8s-style 422

**ID:** 0.7-F4

**Given** BFF запущен

**When** клиент отправляет POST с `"metadata.name": "INVALID NAME WITH SPACES"`

**Then** BFF возвращает HTTP status 422 (Unprocessable Entity)
**And** тело содержит `{"kind":"Status","reason":"Invalid","code":422}` с описанием нарушения

### F5. POST создаёт Folder (cluster-scoped) без namespace в body

**ID:** 0.7-F5

**Given** Cloud `default-cloud` существует с uid `cloud-uid-1`

**When** клиент отправляет:
```
POST /api/clusters/kacho/k8s/apis/resourcemanager.kacho.cloud/v1/folders
Content-Type: application/json

{
  "apiVersion": "resourcemanager.kacho.cloud/v1",
  "kind": "Folder",
  "metadata": {"name": "new-folder"},
  "spec": {"cloudId": "cloud-uid-1", "displayName": "New Folder"}
}
```

**Then** HTTP status 201
**And** тело содержит `"metadata.uid"` — непустой UUID
**And** `"metadata.name"` = `"new-folder"`
**And** поле `"metadata.namespace"` отсутствует в ответе

### F6. POST создаёт Instance — ответ содержит status.state = PROVISIONING

**ID:** 0.7-F6

**Given** Folder `folder-uid-1` существует
**And** Disk `disk-uid-1`, Subnet `subnet-uid-1` существуют

**When** клиент отправляет POST для создания Instance:
```json
{
  "apiVersion": "compute.kacho.cloud/v1",
  "kind": "Instance",
  "metadata": {"name": "bff-vm-01", "namespace": "folder-uid-1"},
  "spec": {
    "platformId": "standard-v3",
    "zoneId": "kacho-zone-a",
    "resources": {"cores": 2, "memory": "4Gi"},
    "bootDisk": {"diskId": "disk-uid-1"},
    "networkInterfaces": [{"subnetId": "subnet-uid-1"}],
    "desiredPowerState": "RUNNING"
  }
}
```

**Then** HTTP status 201
**And** `"status.state"` = `"PROVISIONING"` в первом ответе
**And** `"metadata.uid"` непустой

### F7. PUT с namespace в path, отличающимся от namespace в body, возвращает 400

**ID:** 0.7-F7

**Given** BFF запущен

**When** клиент отправляет PUT:
```
PUT /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-A/networks/my-net
```
**And** тело содержит `"metadata.namespace": "folder-B"` (не совпадает с path)

**Then** HTTP status 400
**And** тело содержит `{"kind":"Status","reason":"BadRequest","code":400,"message":"namespace in path and body mismatch"}`

---

## 7. Группа G — Resource Delete (DELETE → Kachō Delete RPC)

Сценарии группы G проверяют удаление ресурсов.

### G1. DELETE Network → вызов Kachō Delete, ответ 200 с deletionTimestamp

**ID:** 0.7-G1

**Given** Network `net-to-delete` существует в Folder `folder-uid-1` с uid `net-del-uid`

**When** клиент отправляет:
```
DELETE /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-1/networks/net-to-delete
```

**Then** HTTP status 200
**And** BFF вызвал `NetworkService/Delete` с `metadata.name = "net-to-delete"`, `metadata.folderId = "folder-uid-1"`
**And** тело ответа содержит K8s-объект с заполненным `"metadata.deletionTimestamp"` (мягкое удаление)

### G2. DELETE несуществующего ресурса возвращает K8s 404

**ID:** 0.7-G2

**Given** Network `ghost-net` не существует

**When** клиент отправляет DELETE для `ghost-net`

**Then** HTTP status 404
**And** тело содержит `{"kind":"Status","reason":"NotFound","code":404}`
**And** BFF вызвал `NetworkService/Delete`, получил gRPC `NOT_FOUND` и правильно отобразил на 404

### G3. DELETE Organization (cluster-scoped) — корректный маппинг

**ID:** 0.7-G3

**Given** Organization `test-org` существует

**When** клиент отправляет:
```
DELETE /api/clusters/kacho/k8s/apis/resourcemanager.kacho.cloud/v1/organizations/test-org
```

**Then** HTTP status 200
**And** BFF вызвал `OrganizationService/Delete` с `metadata.name = "test-org"` (без folderId)

### G4. DELETE с зависимыми ресурсами возвращает K8s 409 Conflict

**ID:** 0.7-G4

**Given** Network `protected-net` содержит Subnet (зависимый ресурс)
**And** Kachō-backend вернёт gRPC `FAILED_PRECONDITION` при попытке удаления

**When** клиент отправляет DELETE для `protected-net`

**Then** HTTP status 409 (Conflict)
**And** тело содержит `{"kind":"Status","reason":"Conflict","code":409}` с описанием причины

---

## 8. Группа H — WebSocket Watch (K8s-style watch=true → gRPC Watch stream)

Сценарии группы H проверяют WebSocket-Watch.

### H1. WebSocket Watch открывается и получает начальный список (LIST+WATCH семантика)

**ID:** 0.7-H1

**Given** BFF запущен, api-gateway доступен
**And** В Folder `folder-uid-1` существуют Network `net-1`, `net-2`

**When** клиент открывает WebSocket соединение:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid-1/networks?watch=true
Upgrade: websocket
Connection: Upgrade
```

**Then** WebSocket handshake успешен (HTTP 101 Switching Protocols)
**And** BFF первым делом отправляет ADDED-события для всех существующих ресурсов (`net-1`, `net-2`) с `"type": "ADDED"`
**And** каждое сообщение — JSON-строка формата:
```json
{"type":"ADDED","object":{"apiVersion":"vpc.kacho.cloud/v1","kind":"Network","metadata":{...},"spec":{...},"status":{...}}}
```
**And** после initial dump BFF подписывается на gRPC Watch с полученным `resourceVersion`

### H2. Watch получает ADDED при создании нового ресурса

**ID:** 0.7-H2

**Given** WebSocket Watch открыт на Networks в Folder `folder-uid-1` (из H1)
**And** Initial dump уже отправлен

**When** другой клиент создаёт Network `net-3` в `folder-uid-1` (через POST или gRPC)

**Then** Watch-стрим доставляет сообщение:
```json
{"type":"ADDED","object":{"apiVersion":"vpc.kacho.cloud/v1","kind":"Network","metadata":{"name":"net-3","namespace":"folder-uid-1","uid":"..."},...}}
```
**And** сообщение приходит в течение 5 секунд
**And** соединение остаётся открытым

### H3. Watch получает MODIFIED при изменении ресурса

**ID:** 0.7-H3

**Given** WebSocket Watch открыт на Networks в Folder `folder-uid-1`
**And** Network `net-1` существует

**When** другой клиент обновляет labels у `net-1` (Upsert с новыми labels)

**Then** Watch-стрим доставляет сообщение с `"type": "MODIFIED"` и обновлёнными labels в `object.metadata.labels`

### H4. Watch получает DELETED при удалении ресурса

**ID:** 0.7-H4

**Given** WebSocket Watch открыт на Networks в Folder `folder-uid-1`
**And** Network `net-2` существует

**When** `net-2` удаляется (через DELETE-запрос)

**Then** Watch-стрим доставляет сообщение с `"type": "DELETED"` и последним известным состоянием объекта в `object`

### H5. Watch с устаревшим resourceVersion получает BOOKMARK и relist-сигнал

**ID:** 0.7-H5

**Given** BFF запущен
**And** Kachō gRPC Watch возвращает `OUT_OF_RANGE` для слишком старого resourceVersion

**When** клиент открывает Watch с `?watch=true&resourceVersion=1` (слишком старый)

**Then** BFF получает gRPC `OUT_OF_RANGE` от api-gateway
**And** BFF закрывает WebSocket с кодом 410 (Gone) или отправляет сообщение `{"type":"ERROR","object":{"kind":"Status","code":410,"reason":"Gone","message":"resourceVersion too old, relist required"}}`

### H6. Закрытие WebSocket клиентом корректно завершает gRPC Watch stream

**ID:** 0.7-H6

**Given** WebSocket Watch открыт и активен

**When** клиент закрывает WebSocket соединение (close frame или TCP reset)

**Then** BFF отменяет context gRPC Watch stream
**And** горутина BFF завершается без goroutine leak
**And** в логах BFF нет panic или error уровня ERROR (только INFO «watch closed»)

### H7. Watch фильтрует события по namespace (folderId)

**ID:** 0.7-H7

**Given** Watch открыт на Networks в `folder-uid-A`
**And** В `folder-uid-B` создаётся Network `net-in-B`

**When** `net-in-B` создаётся в `folder-uid-B`

**Then** Watch для `folder-uid-A` **не получает** событие для `net-in-B`
**And** BFF вызвал gRPC Watch с selector `folderId = "folder-uid-A"`

### H8. Watch для cluster-scoped ресурса (Organization) работает без namespace в path

**ID:** 0.7-H8

**Given** BFF запущен

**When** клиент открывает WebSocket:
```
GET /api/clusters/kacho/k8s/apis/resourcemanager.kacho.cloud/v1/organizations?watch=true
```

**Then** WebSocket handshake успешен
**And** BFF подписывается на `OrganizationService/Watch` без folderId-фильтра
**And** события ADDED/MODIFIED/DELETED для Organizations поступают корректно

---

## 9. Группа I — Folder = Namespace mapping (list namespaces)

Сценарии группы I проверяют специальный маппинг Folder → K8s namespace.

### I1. GET namespaces возвращает список Folder-ов как K8s Namespace-объекты

**ID:** 0.7-I1

**Given** В системе существуют Folder `folder-dev` (uid: `f-dev-uid`) и Folder `folder-prod` (uid: `f-prod-uid`)

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/api/v1/namespaces
```

**Then** HTTP status 200
**And** тело содержит `"kind": "NamespaceList"`, `"apiVersion": "v1"`
**And** `"items"` содержит ≥ 2 элемента
**And** каждый элемент имеет `"kind": "Namespace"`, `"apiVersion": "v1"`
**And** для `folder-dev`: `"metadata.name": "f-dev-uid"`, `"metadata.labels.kacho.cloud/folder-name": "folder-dev"`
**And** BFF вызвал `FolderService/List` для получения данных

### I2. GET конкретного namespace возвращает один Folder

**ID:** 0.7-I2

**Given** Folder `folder-dev` с uid `f-dev-uid` существует

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/api/v1/namespaces/f-dev-uid
```

**Then** HTTP status 200
**And** тело содержит `"kind": "Namespace"`, `"metadata.name": "f-dev-uid"`
**And** `"metadata.labels.kacho.cloud/folder-name": "folder-dev"` присутствует
**And** `"status.phase": "Active"`

### I3. GET несуществующего namespace возвращает 404

**ID:** 0.7-I3

**Given** Folder с uid `nonexistent-uid` не существует

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/api/v1/namespaces/nonexistent-uid
```

**Then** HTTP status 404
**And** тело содержит `{"kind":"Status","reason":"NotFound","code":404}`

### I4. openapi-k8s-toolkit получает список Folder-ов через namespace endpoint для селектора папки

**ID:** 0.7-I4

**Given** `@prorobotech/openapi-k8s-toolkit` настроен с `USE_NAMESPACE_NAV=true`
**And** BFF запущен и доступен UI

**When** UI инициализируется и запрашивает namespace-список

**Then** toolkit получает список Folder-ов через `/api/v1/namespaces`
**And** sidebar UI содержит Folder-ы в качестве namespace-селектора
**And** при выборе Folder все resource-запросы фильтруются по соответствующему `metadata.namespace`

---

## 10. Группа J — RBAC stub (selfsubjectaccessreviews always allow)

### J1. POST selfsubjectaccessreviews всегда возвращает allowed=true

**ID:** 0.7-J1

**Given** BFF запущен
**And** `@prorobotech/openapi-k8s-toolkit` отправляет RBAC-проверку для ресурса

**When** клиент отправляет:
```
POST /api/clusters/kacho/k8s/apis/authorization.k8s.io/v1/selfsubjectaccessreviews
Content-Type: application/json

{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SelfSubjectAccessReview",
  "spec": {
    "resourceAttributes": {
      "verb": "create",
      "group": "vpc.kacho.cloud",
      "resource": "networks",
      "namespace": "folder-uid-1"
    }
  }
}
```

**Then** HTTP status 201
**And** тело содержит:
```json
{
  "apiVersion": "authorization.k8s.io/v1",
  "kind": "SelfSubjectAccessReview",
  "status": {"allowed": true}
}
```
**And** BFF не обращается к gRPC или внешним системам — это статическая заглушка

### J2. selfsubjectaccessreviews для любого verb/resource/namespace возвращает allowed=true

**ID:** 0.7-J2

**Given** BFF запущен

**When** клиент отправляет selfsubjectaccessreview с любой комбинацией verb (`get`, `list`, `delete`, `create`, `update`), group, resource, namespace

**Then** всегда возвращается `"status": {"allowed": true}`
**And** HTTP статус всегда 201

---

## 11. Группа K — Трансляция ошибок (gRPC → K8s HTTP Status)

Сценарии группы K проверяют корректное преобразование gRPC-кодов в K8s HTTP Status objects.

### K1. gRPC NOT_FOUND → HTTP 404 + K8s Status NotFound

**ID:** 0.7-K1

**Given** api-gateway вернёт gRPC `NOT_FOUND` (код 5) при вызове `InstanceService/List` с неверным folderId

**When** клиент запрашивает GET instances для несуществующего namespace

**Then** HTTP status 404
**And** тело:
```json
{"kind":"Status","apiVersion":"v1","status":"Failure","reason":"NotFound","code":404,"message":"..."}
```

### K2. gRPC INVALID_ARGUMENT → HTTP 400 + K8s Status BadRequest

**ID:** 0.7-K2

**Given** api-gateway вернёт gRPC `INVALID_ARGUMENT` (код 3) для невалидного поля

**When** BFF получает эту ошибку от gRPC

**Then** HTTP status 400
**And** тело содержит `{"kind":"Status","reason":"BadRequest","code":400,"details":{"causes":[...]}}`
**And** поле `details.causes` содержит список нарушений (field violations) из gRPC `BadRequest.field_violations`

### K3. gRPC FAILED_PRECONDITION → HTTP 409 Conflict

**ID:** 0.7-K3

**Given** api-gateway вернёт gRPC `FAILED_PRECONDITION` (код 9) при попытке удалить ресурс с зависимостями

**When** BFF получает эту ошибку

**Then** HTTP status 409
**And** тело содержит `{"kind":"Status","reason":"Conflict","code":409}`

### K4. gRPC ALREADY_EXISTS → HTTP 409 Conflict (AlreadyExists reason)

**ID:** 0.7-K4

**Given** api-gateway вернёт gRPC `ALREADY_EXISTS` (код 6)

**When** BFF получает эту ошибку

**Then** HTTP status 409
**And** тело содержит `{"kind":"Status","reason":"AlreadyExists","code":409}`

### K5. gRPC UNAVAILABLE → HTTP 503 Service Unavailable

**ID:** 0.7-K5

**Given** api-gateway недоступен или вернул gRPC `UNAVAILABLE` (код 14)

**When** BFF пытается выполнить List-вызов

**Then** HTTP status 503
**And** тело содержит `{"kind":"Status","reason":"ServiceUnavailable","code":503}`

### K6. gRPC INTERNAL → HTTP 500 Internal Server Error

**ID:** 0.7-K6

**Given** api-gateway вернёт gRPC `INTERNAL` (код 13)

**When** BFF получает эту ошибку

**Then** HTTP status 500
**And** тело содержит `{"kind":"Status","reason":"InternalError","code":500}`

### K7. gRPC OUT_OF_RANGE (Gone) → HTTP 410 для Watch

**ID:** 0.7-K7

**Given** gRPC Watch стрим завершается с `OUT_OF_RANGE`

**When** BFF получает этот код

**Then** BFF отправляет клиенту HTTP 410 (или WebSocket error message с кодом 410) с `"reason":"Expired"` (resourceVersion истёк)

### K8. Таблица полного маппинга gRPC → HTTP зафиксирована в BFF

**ID:** 0.7-K8

**Given** BFF реализован

**Then** в `internal/translator/errors.go` (или аналоге) присутствует полная таблица маппинга:

| gRPC-код | HTTP-статус | K8s reason |
|---|---|---|
| OK | 200/201 | — |
| INVALID_ARGUMENT | 400 | BadRequest |
| NOT_FOUND | 404 | NotFound |
| ALREADY_EXISTS | 409 | AlreadyExists |
| FAILED_PRECONDITION | 409 | Conflict |
| ABORTED | 409 | Conflict |
| UNAVAILABLE | 503 | ServiceUnavailable |
| INTERNAL | 500 | InternalError |
| OUT_OF_RANGE (Watch) | 410 | Expired |
| RESOURCE_EXHAUSTED | 429 | TooManyRequests |

---

## 12. Группа L — kacho-ui кастомизация (env vars, logo, sidebar)

Сценарии группы L проверяют кастомизацию UI-приложения.

### L1. VITE_APP_TITLE устанавливает заголовок приложения

**ID:** 0.7-L1

**Given** `kacho-ui` собран с `VITE_APP_TITLE=Kachō`

**When** пользователь открывает UI в браузере

**Then** заголовок страницы (`<title>`) содержит `"Kachō"`
**And** навигационная шапка отображает `"Kachō"` или логотип

### L2. VITE_BFF_BASE_URL направляет API-запросы к kacho-ui-bff

**ID:** 0.7-L2

**Given** `kacho-ui` собран с `VITE_BFF_BASE_URL=http://ui-bff.kacho.local`

**When** toolkit отправляет запрос на `/api/clusters`

**Then** браузер отправляет запрос на `http://ui-bff.kacho.local/api/clusters`
**And** не на прямой api-gateway

### L3. Sidebar содержит навигационные группы из kindRegistry BFF

**ID:** 0.7-L3

**Given** `@prorobotech/openapi-k8s-toolkit` получил данные через `getKinds`
**And** ответ содержит 14 ресурсов из таблицы §0.1

**When** пользователь открывает sidebar UI

**Then** sidebar содержит навигационные группы, соответствующие API-группам:
  - «Resource Manager» (или `resourcemanager.kacho.cloud/v1`)
  - «VPC» (или `vpc.kacho.cloud/v1`)
  - «Compute» (или `compute.kacho.cloud/v1`)
  - «Load Balancer» (или `loadbalancer.kacho.cloud/v1`)
**And** в каждой группе перечислены соответствующие ресурсы (Network, Subnet, ... в VPC)

### L4. Folder-selector отображается вместо стандартного namespace-selector

**ID:** 0.7-L4

**Given** UI настроен с `USE_NAMESPACE_NAV=true`
**And** Folder-ы загружены через `/api/v1/namespaces`

**When** пользователь видит namespace-selector (dropdown или список)

**Then** selector отображает Folder-ы по их `kacho.cloud/folder-name` label (human-readable имя)
**And** при выборе Folder ресурсные запросы фильтруются по соответствующему Folder-uid (= namespace)

### L5. VITE_CLUSTER_NAME задаёт имя кластера в UI

**ID:** 0.7-L5

**Given** `kacho-ui` собран с `VITE_CLUSTER_NAME=kacho`

**When** toolkit инициализируется

**Then** все запросы включают `/api/clusters/kacho/...` в path

### L6. Пользователь может просмотреть список Instances в UI

**ID:** 0.7-L6

**Given** UI развёрнут и доступен в браузере
**And** В Folder `default` существуют Instance `vm-1` и `vm-2`
**And** Пользователь выбрал Folder `default` в селекторе

**When** пользователь переходит в раздел «Compute / Instance»

**Then** страница отображает список с 2 записями
**And** каждая запись содержит имя, статус (RUNNING/PROVISIONING/...) и uid
**And** нет JavaScript-ошибок в консоли браузера

### L7. Пользователь может открыть форму создания Network

**ID:** 0.7-L7

**Given** UI развёрнут
**And** Пользователь в разделе «VPC / Network»

**When** пользователь нажимает кнопку «Create» (или аналог из openapi-ui template)

**Then** открывается форма создания с полями согласно OpenAPI-спеке для Network
**And** поля `metadata.name`, `metadata.namespace` присутствуют в форме

---

## 13. Группа M — kacho-ui Helm chart + ENV таблица

### M1. kacho-ui Helm chart деплоится без ошибок

**ID:** 0.7-M1

**Given** `kacho-ui/deploy/Chart.yaml` присутствует
**And** `values.dev.yaml` содержит корректные значения env-переменных

**When** выполняется `helm lint kacho-ui/deploy/`

**Then** команда завершается с кодом 0 без ошибок lint

### M2. ENV-таблица kacho-ui зафиксирована в documentation

**ID:** 0.7-M2

**Given** реализация завершена

**Then** `kacho-ui/CLAUDE.md` или `README.md` содержит таблицу всех обязательных переменных среды:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `VITE_APP_TITLE` | `Kachō` | Заголовок приложения в `<title>` и шапке |
| `VITE_BFF_BASE_URL` | `http://ui-bff.kacho.local` | Базовый URL kacho-ui-bff |
| `VITE_CLUSTER_NAME` | `kacho` | Имя виртуального кластера |
| `VITE_USE_NAMESPACE_NAV` | `true` | Отображать Folder-ы как namespace-ы в навигации |

### M3. kacho-ui Pod стартует с корректными env из ConfigMap

**ID:** 0.7-M3

**Given** umbrella chart задеплоен с `ui.enabled=true`

**When** выполняется `kubectl get pods -n kacho | grep kacho-ui`

**Then** Pod `kacho-ui-*` в состоянии Running
**And** `kubectl exec` в Pod показывает переменную `VITE_BFF_BASE_URL` установленной

---

## 14. Группа N — kacho-ui-bff Helm chart

### N1. kacho-ui-bff Helm chart деплоится без ошибок

**ID:** 0.7-N1

**Given** `kacho-ui-bff/deploy/Chart.yaml` присутствует

**When** выполняется `helm lint kacho-ui-bff/deploy/`

**Then** команда завершается с кодом 0

### N2. kacho-ui-bff Pod читает KACHO_BFF_GATEWAY_ADDR из Secret или ConfigMap

**ID:** 0.7-N2

**Given** umbrella chart задеплоен с `ui-bff.enabled=true`
**And** `KACHO_BFF_GATEWAY_ADDR=api-gateway.kacho.svc.cluster.local:9090` задан в values

**When** BFF Pod запускается

**Then** Pod в состоянии Running
**And** BFF успешно подключается к api-gateway (readyz = 200)

### N3. ENV-таблица kacho-ui-bff зафиксирована в documentation

**ID:** 0.7-N3

**Given** реализация завершена

**Then** `kacho-ui-bff/CLAUDE.md` или `README.md` содержит таблицу:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `KACHO_BFF_GATEWAY_ADDR` | `api-gateway.kacho.svc.cluster.local:9090` | gRPC адрес api-gateway |
| `KACHO_BFF_HTTP_PORT` | `8080` | HTTP-порт BFF |
| `KACHO_BFF_CLUSTER_NAME` | `kacho` | Имя виртуального кластера |
| `KACHO_BFF_LOG_LEVEL` | `info` | Уровень логирования (slog) |

### N4. umbrella chart обновлён: добавлены зависимости ui и ui-bff

**ID:** 0.7-N4

**Given** `kacho-deploy/helm/umbrella/Chart.yaml` присутствует

**When** разработчик инспектирует секцию `dependencies`

**Then** секция содержит записи для `kacho-ui` и `kacho-ui-bff`
**And** `helm dependency update` завершается без ошибок

---

## 15. Группа O — Cross-service: UI → BFF → api-gateway → backend

Сценарии группы O проверяют полный path прохождения запроса через все слои.

### O1. Полный путь List: UI → BFF → api-gateway → vpc → ответ UI

**ID:** 0.7-O1

**Given** kind-кластер поднят (`make dev-up` с поддержкой sub-phase 0.7)
**And** UI доступен на `http://kacho.local` (или аналоге)
**And** api-gateway, vpc, resource-manager подняты
**And** В Folder `default` существует Network `e2e-net`

**When** пользователь через браузер (или curl с имитацией) отправляет GET:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/{folder-uid}/networks
```

**Then** BFF получает запрос, вызывает gRPC `NetworkService/List`
**And** api-gateway проксирует вызов на vpc-backend
**And** ответ UI содержит `"items"` с Network `e2e-net`
**And** суммарная задержка ответа < 500 мс (в dev-кластере)

### O2. Полный путь Create: UI POST → BFF → api-gateway → compute → status PROVISIONING

**ID:** 0.7-O2

**Given** Полное развёртывание активно
**And** Disk, Subnet, Folder существуют

**When** через UI (или curl) создаётся Instance (`POST /api/clusters/kacho/k8s/apis/compute.kacho.cloud/v1/namespaces/.../instances`)

**Then** ответ содержит `"status.state": "PROVISIONING"`
**And** через 60 секунд GET того же Instance возвращает `"status.state": "RUNNING"` (reconciler отработал)

### O3. Полный путь Watch: UI WebSocket → BFF → api-gateway → compute → событие MODIFIED

**ID:** 0.7-O3

**Given** UI открыл WebSocket Watch на instances в Folder `default`
**And** Initial dump отправлен

**When** через другой клиент Instance переходит из PROVISIONING в RUNNING

**Then** WebSocket Watch доставляет событие `{"type":"MODIFIED","object":{"status":{"state":"RUNNING"},...}}`
**And** UI (или тест) получает событие в течение 30 секунд

### O4. BFF использует прямой gRPC к api-gateway (не REST через HTTP)

**ID:** 0.7-O4

**Given** BFF сконфигурирован с `KACHO_BFF_GATEWAY_ADDR=api-gateway.kacho.svc.cluster.local:9090`

**Then** BFF использует `*grpc.ClientConn` к api-gateway (не HTTP REST клиент)
**And** при wireshark/tcpdump анализе трафик от BFF к api-gateway — HTTP/2 с Content-Type application/grpc
**And** не используются prost-to-json конвертеры или grpc-gateway REST клиенты

---

## 16. Группа P — End-to-end UI smoke (browser-driven)

### P1. make e2e-test UI smoke: полный сценарий через curl/websocat

**ID:** 0.7-P1

**Given** kind-кластер поднят
**And** все сервисы: api-gateway, resource-manager, vpc, compute, loadbalancer, ui-bff задеплоены и Ready
**And** /etc/hosts содержит `127.0.0.1 kacho.local ui-bff.kacho.local`

**When** выполняется bash e2e-скрипт `kacho-deploy/e2e/0.7/P1-full-smoke.sh`:
  1. GET `/api/clusters` → получить кластер `kacho`
  2. GET `/api/clusters/kacho/openapi-bff/search/kinds/getKinds` → убедиться 14 kinds
  3. GET `/api/clusters/kacho/k8s/api/v1/namespaces` → получить список Folder-ов
  4. GET `.../namespaces/{folder-uid}/networks` → пустой список
  5. POST `.../namespaces/{folder-uid}/networks` → создать Network `smoke-net`
  6. GET `.../namespaces/{folder-uid}/networks/smoke-net` → убедиться создан
  7. DELETE `.../namespaces/{folder-uid}/networks/smoke-net` → удалить
  8. GET `.../namespaces/{folder-uid}/networks/smoke-net` → 404

**Then** все шаги завершаются с ожидаемыми HTTP-статусами
**And** скрипт завершается с кодом 0

### P2. make e2e-test: Watch events через websocat

**ID:** 0.7-P2

**Given** то же окружение что в P1

**When** bash e2e-скрипт `kacho-deploy/e2e/0.7/P2-watch-smoke.sh`:
  1. Открывает WebSocket Watch на networks в folder через `websocat` или `curl --no-buffer`
  2. В фоне создаёт Network `watch-net` через POST
  3. Ожидает ADDED-события с `name=watch-net`

**Then** событие получено в течение 10 секунд
**And** скрипт завершается с кодом 0

### P3. CI pipeline kacho-ui-bff зелёный

**ID:** 0.7-P3

**Given** реализация завершена

**Then** `.github/workflows/ci.yaml` в `kacho-ui-bff` содержит шаги: `make lint`, `make test`, `make integration-test`
**And** CI завершается с кодом 0
**And** `go test ./... -race` зелёный

### P4. CI pipeline kacho-ui зелёный

**ID:** 0.7-P4

**Given** реализация завершена

**Then** `.github/workflows/ci.yaml` в `kacho-ui` содержит шаги: `npm install`, `npm run lint`, `npm run build`
**And** `npm run build` завершается с кодом 0 (нет TypeScript-ошибок)
**And** размер итогового bundle `dist/` < 10 МБ

---

## 17. Группа Q — Негативные сценарии

### Q1. 404 для неизвестного resource kind в path

**ID:** 0.7-Q1

**Given** BFF запущен

**When** клиент отправляет:
```
GET /api/clusters/kacho/k8s/apis/vpc.kacho.cloud/v1/namespaces/folder-uid/widgets
```

**Then** HTTP status 404
**And** тело содержит `{"kind":"Status","reason":"NotFound","code":404}` (ресурс `widgets` не зарегистрирован)

### Q2. 400 для POST с телом, не являющимся валидным JSON

**ID:** 0.7-Q2

**Given** BFF запущен

**When** клиент отправляет POST с телом `{invalid-json`:

**Then** HTTP status 400
**And** тело содержит `{"kind":"Status","reason":"BadRequest","code":400,"message":"invalid JSON body"}`
**And** BFF не падает и обрабатывает последующие запросы

### Q3. 503 когда api-gateway недоступен при запросе List

**ID:** 0.7-Q3

**Given** BFF запущен
**And** api-gateway недоступен (`KACHO_BFF_GATEWAY_ADDR=localhost:1`)

**When** клиент запрашивает GET Networks

**Then** HTTP status 503
**And** тело содержит `{"kind":"Status","reason":"ServiceUnavailable","code":503}`
**And** BFF не падает (graceful degradation)

### Q4. WebSocket Watch при потере соединения с api-gateway — BFF отправляет ошибку и закрывает

**ID:** 0.7-Q4

**Given** WebSocket Watch активен
**And** api-gateway внезапно становится недоступным (gRPC stream обрывается)

**When** gRPC Watch stream завершается с ошибкой `UNAVAILABLE`

**Then** BFF отправляет WebSocket-сообщение:
```json
{"type":"ERROR","object":{"kind":"Status","code":503,"reason":"ServiceUnavailable","message":"upstream unavailable"}}
```
**And** BFF закрывает WebSocket с appropriate close code
**And** горутина BFF завершается чисто

### Q5. 400 при попытке POST с namespace в path, отличающимся от namespace в body

**ID:** 0.7-Q5

**Given** BFF запущен

**When** POST содержит `metadata.namespace: folder-B` при path `.../namespaces/folder-A/networks`

**Then** HTTP status 400 с сообщением о несоответствии namespace (дублирует F7, проверяет в negative-контексте)

### Q6. 422 при попытке создать ресурс с именем, нарушающим DNS-label constraint

**ID:** 0.7-Q6

**Given** BFF запущен

**When** POST тело содержит `"metadata.name": "INVALID-UPPER-CASE"`

**Then** BFF возвращает 422 до обращения к gRPC
**And** тело содержит `{"kind":"Status","reason":"Invalid","code":422,"details":{"causes":[{"field":"metadata.name","message":"must match ..."}]}}`

### Q7. Обращение к BFF с корректным кластером, но несуществующим namespace — прозрачная ошибка от backend

**ID:** 0.7-Q7

**Given** BFF запущен

**When** клиент запрашивает resources в namespace `00000000-0000-0000-0000-000000000000` (несуществующий folder)

**Then** BFF вызывает gRPC List с folderId = `"00000000-0000-0000-0000-000000000000"`
**And** api-gateway возвращает пустой список (или NOT_FOUND в зависимости от реализации backend)
**And** BFF возвращает 200 с пустым `items` (или 404 если backend вернул NOT_FOUND)

---

## 18. Группа R — Definition of Done

### R1. Структура репозитория kacho-ui-bff

**ID:** 0.7-R1

**Given** реализация sub-phase 0.7 завершена

**Then** репозиторий `kacho-ui-bff` содержит:
  - `cmd/ui-bff/main.go` — composition root: HTTP-сервер, gRPC-клиент к api-gateway
  - `internal/handler/` — HTTP-обработчики (list, get, upsert, delete, watch, namespaces, discovery, rbac)
  - `internal/translator/` — K8s envelope ↔ Kachō envelope conversion; errors.go (gRPC→HTTP маппинг)
  - `internal/registry/` — kindRegistry: статическая таблица 14 ресурсов (group, version, plural, kind, namespaced, gRPC-сервисное имя)
  - `internal/openapi/` — генератор hand-rolled OpenAPI v3 спеки из kindRegistry
  - `internal/watch/` — WebSocket-to-gRPC Watch bridge
  - `deploy/` — Helm chart (Deployment, Service, ConfigMap)
  - `Makefile` — lint, test, integration-test, docker
  - `Dockerfile` — multi-stage: builder + minimal runtime
  - `.github/workflows/ci.yaml`

### R2. Структура репозитория kacho-ui

**ID:** 0.7-R2

**Given** реализация завершена

**Then** репозиторий `kacho-ui` содержит:
  - `src/` — React+TypeScript приложение на базе `openapi-ui` template
  - `package.json` с зависимостью `@prorobotech/openapi-k8s-toolkit`
  - `public/` — статические ресурсы (логотип Kachō)
  - `deploy/` — Helm chart
  - `.env.example` с переменными из M2-таблицы
  - `.github/workflows/ci.yaml`

### R3. Integration-тесты BFF

**ID:** 0.7-R3

**Then** каждый acceptance-сценарий групп A–K покрыт тестом с именем `Test<Component>_<ScenarioID>_<ShortDesc>`
**And** BFF-тесты используют mock gRPC-сервер (не реальный api-gateway)
**And** `go test ./... -race` завершается с кодом 0 в репо `kacho-ui-bff`
**And** покрытие сценариев A–K ≥ 90%

### R4. E2e bash-сценарии

**ID:** 0.7-R4

**Then** в `kacho-deploy/e2e/0.7/` присутствуют bash-скрипты для сценариев P1, P2
**And** `make e2e-test` запускает эти скрипты против живого kind-кластера
**And** все скрипты завершаются с кодом 0

### R5. kacho-deploy umbrella chart обновлён

**ID:** 0.7-R5

**Then** `kacho-deploy/helm/umbrella/Chart.yaml` включает `kacho-ui` и `kacho-ui-bff` как dependencies
**And** `helm install kacho-umbrella --dry-run` завершается без ошибок
**And** `make dev-up` после обновления umbrella поднимает UI и BFF наряду с остальными сервисами

### R6. Документация

**ID:** 0.7-R6

**Then** `kacho-ui-bff/CLAUDE.md` содержит: описание BFF-routing logic, env-таблицу (N3), пример curl-команды для List/Watch
**And** `kacho-ui/CLAUDE.md` содержит: инструкцию `npm run dev`, env-таблицу (M2), описание кастомизации логотипа
**And** `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.7

### R7. Тег версии

**ID:** 0.7-R7

**Then** Docker-образ `prorobotech/kacho-ui-bff:0.7.0` успешно собирается
**And** Docker-образ `prorobotech/kacho-ui:0.7.0` успешно собирается
**And** теги `kacho-ui-bff:0.7.0` и `kacho-ui:0.7.0` присутствуют в git

---

## 19. Открытые вопросы

| OQ | Вопрос | Статус |
|---|---|---|
| OQ-1 | **OpenAPI generation source:** генерировать спеку из buf-плагина (openapi-v3 protoc plugin) или hand-rolled из kindRegistry? | **Зафиксировано:** hand-rolled в 0.7. Buf-плагин — отдельная задача вне scope. |
| OQ-2 | **Watch protocol:** использовать чистый WebSocket или HTTP chunked (SSE-like)? `@prorobotech/openapi-k8s-toolkit` ожидает WebSocket? | Нужно уточнение по API toolkit-а. BFF реализует WebSocket; если toolkit поддерживает оба — WebSocket приоритетен. |
| OQ-3 | **Initial LIST перед WATCH:** должен ли BFF делать initial List и отправлять ADDED-события до подписки на Watch, или клиент сам делает List перед открытием Watch? | Зафиксировано (H1): BFF делает LIST + WATCH в одном соединении (as per K8s informer pattern). |
| OQ-4 | **UI-репо:** использовать `PRO-Robotech/openapi-ui` как git submodule/fork или создать новый репо с копированием файлов template? | Нужно решение. Рекомендация: fork `openapi-ui` в `kacho-ui`. |
| OQ-5 | **Ингресс для UI:** нужен ли отдельный Ingress rule для `kacho.local` (UI) в дополнение к `api.kacho.local` (api-gateway)? | Нужно уточнение. Предположительно: `kacho.local` → `kacho-ui:80`; `ui-bff.kacho.local` → `kacho-ui-bff:8080`. |
| OQ-6 | **RBAC-заглушка:** toolkit отправляет `selfsubjectaccessreviews` перед каждым CRUD-действием? Нужно ли кэшировать ответы (always-allow) в BFF или каждый раз отвечать statically? | Рекомендация: stateless always-allow без кэша. |
| OQ-7 | **Кастомизация sidebar через CRD (`front.in-cloud.io/v1alpha1`):** навигационные CRD объявлены как отдельный ресурс, обслуживаемый BFF? Или это часть getKinds-ответа? | Уточнить с командой toolkit. В 0.7 sidebar формируется из getKinds (kindRegistry); CRD-навигация — в будущем. |
