# Sub-phase 0.6 (API Gateway — cmux + gRPC-proxy + grpc-gateway REST + allowlist) — Acceptance

**Документ:** acceptance / sub-phase 0.6
**Дата:** 2026-05-03
**Статус:** Draft, на ревью (round 2)
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.6»; `01-architecture-and-services.md` §2.1, §3; `02-data-model-and-conventions.md` §6.2, §13, §14; `CLAUDE.md` — запреты #7 (Internal.* не маршрутизируются).
**Утверждение:** approve выставляет агент `acceptance-reviewer` (заказчик не подключается — он проверяет финальный smoke на шаге 7, см. `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Sub-итерация 0.6 реализует `kacho-api-gateway` — единую точку входа для всех внешних клиентов платформы Kachō. Gateway принимает gRPC и REST на одном порту 8080 через `cmux`-демультиплексор, прозрачно проксирует gRPC-трафик к четырём backend-сервисам (`resource-manager`, `vpc`, `compute`, `loadbalancer`) через `mwitkow/grpc-proxy`, а REST-запросы обрабатывает через `grpc-gateway` runtime mux с регистрацией всех четырёх сервисов. Allowlist-фильтр обеспечивает выполнение запрета #7: ни один метод `*InternalService.*` не достигает внешнего клиента — такие вызовы возвращают `NOT_FOUND` (gRPC) / `404` (REST). Middleware-цепочка включает request-id, recovery и slog access log. После завершения итерации все команды `grpcurl` и `curl` из предыдущих acceptance-документов начинают работать через единый endpoint `api.kacho.local:80`, а Ingress в helm/umbrella привязан к `api-gateway`-сервису.

**Что НЕ входит в 0.6** (явно отложено):

- AAA (auth, authorization, audit) — placeholder-middleware установлен, но содержит no-op; запросы без auth-заголовков проходят насквозь (см. сценарий F7).
- TLS на edge (termination на Ingress) — фаза 1.
- mTLS между gateway и backend — фаза 1.
- Трассировка (OpenTelemetry exporter) — инициализируется условно по env `KACHO_OTEL_EXPORTER_OTLP_ENDPOINT`; в dev по умолчанию выключена.
- Rate limiting и quota-enforcement — `RESOURCE_EXHAUSTED` зарезервирован архитектурно.
- Канарейные deploy (traffic split) — отложено.
- WebSocket / HTTP/2 Server Push — не используется в текущих RPC.

**Зафиксированные соглашения:**

- API Gateway не имеет БД. Только in-memory allowlist + конфиг.
- Port 8080 — единственный TCP listener. cmux инспектирует первые байты соединения: `Content-Type: application/grpc*` → gRPC listener; всё остальное → HTTP/1.1 listener для grpc-gateway.
- Внутренний gRPC-трафик между сервисами (порт 9090) по-прежнему ходит напрямую по cluster-internal DNS; api-gateway не является транзитом для internal RPC.
- Backend-адреса конфигурируются через env: `KACHO_RESOURCE_MANAGER_GRPC`, `KACHO_VPC_GRPC`, `KACHO_COMPUTE_GRPC`, `KACHO_LOADBALANCER_GRPC`.
- **Allowlist реализован как Go-константа** (`map[string]struct{}`) в `internal/allowlist/list.go`. Формат строк — `/<package>.<Service>/<Method>`. Все `*InternalService.*` явно отсутствуют. Переход на ConfigMap (YAML монтируемый в pod) — отложен до фазы 1.
- **REST URL-схема:** `/v1/<resource>/<action>` без prefix домена (например, `/v1/organizations/upsert`, `/v1/networks/list`, `/v1/instances/restart`). Пути определяются HTTP-аннотациями в `kacho-proto`; аннотации должны следовать этой схеме.
- Header `X-Request-ID`: если клиент передал — используется как-есть; если отсутствует — генерируется UUID v4 на gateway. Проваливается downstream как metadata `x-request-id`.
- **Watch-стриминг через REST (grpc-gateway):** `Content-Type: application/json`, chunked transfer encoding. Каждое сообщение — отдельная JSON-строка формата `{"result": {...}}` (newline-delimited JSON). Клиенты должны читать построчно.
- **gRPC keepalive** между gateway и backend: keepalive interval = 30 секунд на клиентских соединениях. `nginx` ingress: `proxy_read_timeout = 120s` (переопределяется в аннотациях Ingress-ресурса).
- **Backend connection pool:** каждый backend получает один постоянный `*grpc.ClientConn`, инициализируемый один раз в `cmd/api-gateway/main.go` (composition root). Никакого per-request dial.
- slog access log формат: `{"level":"INFO","ts":"...","msg":"access","method":"/kacho.cloud.compute.v1.InstanceService/Upsert","status":0,"duration_ms":12,"request_id":"..."}`.
- **Имена integration-тест-функций** следуют паттерну `TestGateway_<ScenarioID>_<ShortDesc>` (например, `TestGateway_A1_GrpcProxyForwardsToBackend`). E2e bash-скрипты — `kacho-deploy/e2e/0.6/<ID>-<short-desc>.sh`.
- Все assertion-ы с ожиданием (Watch streaming, downstream health) используют таймаут 10 секунд в тестах.

---

## 1. Группа A — gRPC-proxy core (mwitkow/grpc-proxy, domain routing)

Сценарии группы A проверяют базовую работу gRPC-proxy: маршрутизацию по domain, прозрачный forwarding metadata и корректную обработку неизвестных сервисов.

### A1. gRPC-proxy пересылает запрос на правильный backend по domain

**ID:** 0.6-A1

**Given** все 4 backend-сервиса подняты и отвечают на gRPC Health.Check (cluster-internal `:<domain>.kacho.svc.cluster.local:9090`)
**And** `kacho-api-gateway` запущен и слушает на порту 8080
**And** в конфиге: `KACHO_COMPUTE_GRPC=compute.kacho.svc.cluster.local:9090`

**When** внешний клиент отправляет gRPC-запрос через api-gateway:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.compute.v1.InstanceService/List \
  -d '{"selectors": []}'
```

**Then** gateway получает запрос на метод `/kacho.cloud.compute.v1.InstanceService/List`
**And** по prefix `kacho.cloud.compute.v1` определяет domain `compute`
**And** направляет запрос на `compute.kacho.svc.cluster.local:9090`
**And** клиент получает ответ `InstanceListResponse` с кодом `OK`
**And** в access log присутствует запись с `"method":"/kacho.cloud.compute.v1.InstanceService/List"` и `"status":0`

### A2. gRPC-proxy пересылает запрос на resource-manager

**ID:** 0.6-A2

**Given** `kacho-resource-manager` подключён: `KACHO_RESOURCE_MANAGER_GRPC=resource-manager.kacho.svc.cluster.local:9090`
**And** default Organization существует

**When** клиент вызывает через gateway:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.resourcemanager.v1.OrganizationService/List \
  -d '{"selectors": []}'
```

**Then** gateway маршрутизирует по prefix `kacho.cloud.resourcemanager.v1` на `resource-manager`
**And** ответ `OrganizationListResponse` содержит хотя бы одну Organization (default)
**And** `metadata.uid` непустой UUID

### A3. gRPC-proxy пересылает запрос на vpc

**ID:** 0.6-A3

**Given** `kacho-vpc` подключён: `KACHO_VPC_GRPC=vpc.kacho.svc.cluster.local:9090`

**When** клиент вызывает:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.vpc.v1.NetworkService/List \
  -d '{"selectors": []}'
```

**Then** gateway маршрутизирует по prefix `kacho.cloud.vpc.v1` на `vpc`
**And** ответ `NetworkListResponse` получен с кодом `OK`

### A4. gRPC-proxy пересылает запрос на loadbalancer

**ID:** 0.6-A4

**Given** `kacho-loadbalancer` подключён: `KACHO_LOADBALANCER_GRPC=loadbalancer.kacho.svc.cluster.local:9090`

**When** клиент вызывает:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/List \
  -d '{"selectors": []}'
```

**Then** gateway маршрутизирует по prefix `kacho.cloud.loadbalancer.v1` на `loadbalancer`
**And** ответ `NetworkLoadBalancerListResponse` получен с кодом `OK`

### A5. Неизвестный gRPC-сервис (несуществующий domain) возвращает NOT_FOUND

**ID:** 0.6-A5

**Given** gateway запущен

**When** клиент отправляет запрос на несуществующий сервис:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.unknown.v1.FooService/Bar \
  -d '{}'
```

**Then** gateway не находит маршрут для domain `unknown`
**And** клиент получает gRPC-статус `NOT_FOUND` (код 5)
**And** `details[].RequestInfo.request_id` непустой (сгенерирован gateway)

### A6. gRPC-proxy прозрачно пробрасывает метаданные запроса (headers)

**ID:** 0.6-A6

**Given** gateway запущен
**And** клиент устанавливает заголовок `x-request-id: client-req-42`

**When** клиент отправляет gRPC-запрос с этим заголовком через gateway на `InstanceService/List`

**Then** backend-сервис `compute` получает metadata `x-request-id: client-req-42` (без изменений)
**And** ответ клиента содержит тот же `x-request-id: client-req-42` в trailing headers или response metadata
**And** access log gateway содержит `"request_id":"client-req-42"`

### A7. gRPC-proxy поддерживает server-streaming RPC (Watch) через proxy

**ID:** 0.6-A7

**Given** gateway запущен
**And** `compute`-сервис запущен, в БД существует Folder `default`

**When** клиент открывает server-streaming Watch через gateway:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.compute.v1.InstanceService/Watch \
  -d '{"selectors": [{"field_selector": {"folder_id": "<folder-uid>"}}], "resource_version": "0"}'
```
**And** в течение 5 секунд выполняется Upsert нового Instance через gateway

**Then** Watch-стрим (через proxy) доставляет событие `ADDED` с полным Instance-объектом
**And** стрим остаётся открытым после первого события (не закрывается)
**And** gateway корректно стримит chunked HTTP/2 frames клиенту без буферизации

---

## 2. Группа B — cmux: демультиплексирование gRPC vs REST на одном порту

Сценарии группы B проверяют, что `cmux` корректно разделяет входящие соединения на двух listener-ах.

### B1. gRPC-запрос (Content-Type: application/grpc) попадает на gRPC listener

**ID:** 0.6-B1

**Given** gateway слушает на порту 8080
**And** cmux настроен: первый matcher — `application/grpc*` → gRPC listener; второй — Any() → HTTP listener

**When** клиент отправляет HTTP/2-запрос с заголовком `Content-Type: application/grpc`

**Then** cmux направляет соединение в gRPC server (не в HTTP mux)
**And** запрос обрабатывается gRPC-proxy
**And** в access log присутствует запись с gRPC-методом (не HTTP-путём)

### B2. REST-запрос (HTTP/1.1 POST) попадает на HTTP listener

**ID:** 0.6-B2

**Given** gateway слушает на порту 8080

**When** клиент отправляет HTTP/1.1 запрос непосредственно на порт 8080 (минуя Ingress):
```
curl -s -X POST http://localhost:8080/v1/instances/list \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Then** cmux направляет соединение в HTTP listener (grpc-gateway mux)
**And** ответ имеет HTTP status 200 и `Content-Type: application/json`
**And** body содержит JSON с полем `instances` (массив, возможно пустой)

### B3. Одновременные gRPC и REST запросы на один порт обрабатываются независимо

**ID:** 0.6-B3

**Given** gateway слушает на порту 8080

**When** два клиента отправляют запросы одновременно:
  - Клиент A: gRPC `InstanceService/List` на порт 8080
  - Клиент B: REST `POST /v1/instances/list` с `{}` на порт 8080

**Then** оба запроса обрабатываются без блокировок
**And** клиент A получает gRPC-ответ (`InstanceListResponse`)
**And** клиент B получает HTTP 200 JSON-ответ
**And** gateway не аварийно завершается

### B4. HTTP/2 cleartext (h2c) поддерживается для gRPC клиентов без TLS

**ID:** 0.6-B4

**Given** gateway запущен без TLS (cleartext HTTP/2)
**And** клиент использует `grpcurl -plaintext` (h2c без upgrade handshake)

**When** клиент вызывает `OrganizationService/List` через `api.kacho.local:80`

**Then** соединение устанавливается без TLS handshake
**And** HTTP/2 кадры проходят cleartext
**And** ответ получен с кодом `OK`

---

## 3. Группа C — REST mux: регистрация всех 4 сервисов, URL-mapping

Сценарии группы C проверяют регистрацию grpc-gateway handler-ов и корректность URL → RPC mapping.

### C1. REST Upsert для InstanceService работает через gateway

**ID:** 0.6-C1

**Given** gateway запущен
**And** Folder `default` существует с uid `<folder-uid>`
**And** существует Disk с uid `<disk-uid>` и Subnet с uid `<subnet-uid>`

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/instances/upsert \
  -H 'Content-Type: application/json' \
  -d '{
    "instances": [{
      "metadata": {"name": "gw-test-vm", "folderId": "<folder-uid>"},
      "spec": {
        "platformId": "standard-v3",
        "zoneId": "kacho-zone-a",
        "resources": {"cores": 2, "memory": "4Gi"},
        "bootDisk": {"diskId": "<disk-uid>"},
        "networkInterfaces": [{"subnetId": "<subnet-uid>"}],
        "desiredPowerState": "RUNNING"
      }
    }]
  }'
```

**Then** HTTP status 200
**And** body содержит `instances[0].metadata.uid` — непустой UUID
**And** body содержит `instances[0].metadata.resourceVersion` — непустая строка
**And** `instances[0].status.state` = `"PROVISIONING"`

### C2. REST List для OrganizationService работает

**ID:** 0.6-C2

**Given** gateway запущен
**And** default Organization существует

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/organizations/list \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Then** HTTP status 200
**And** body содержит `organizations` — массив с хотя бы одной Organization
**And** первый элемент содержит `metadata.name = "default"`

### C3. REST List для NetworkService (vpc) работает

**ID:** 0.6-C3

**Given** gateway запущен

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/networks/list \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Then** HTTP status 200
**And** body содержит `networks` — массив (возможно пустой)

### C4. REST List для NetworkLoadBalancerService работает

**ID:** 0.6-C4

**Given** gateway запущен

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/network-load-balancers/list \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Then** HTTP status 200
**And** body содержит `networkLoadBalancers` — массив (возможно пустой)

### C5. REST Upsert для FolderService работает (resource-manager)

**ID:** 0.6-C5

**Given** gateway запущен
**And** Cloud `default` существует с uid `<cloud-uid>`

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/folders/upsert \
  -H 'Content-Type: application/json' \
  -d '{
    "folders": [{
      "metadata": {"name": "test-folder", "cloudId": "<cloud-uid>"},
      "spec": {"displayName": "Test Folder"}
    }]
  }'
```

**Then** HTTP status 200
**And** body содержит `folders[0].metadata.uid` — непустой UUID

### C6. REST Watch для TargetGroupService (loadbalancer) работает через gateway

**ID:** 0.6-C6

**Given** gateway запущен
**And** Folder `default` существует

**When** клиент открывает HTTP long-poll Watch:
```
curl -s -X POST http://api.kacho.local/v1/target-groups/watch \
  -H 'Content-Type: application/json' \
  -d '{"selectors": [], "resourceVersion": "0"}'
```
**And** в течение 5 секунд выполняется Upsert нового TargetGroup

**Then** HTTP response начинает приходить chunked newline-delimited JSON (`Content-Type: application/json`)
**And** каждое событие — отдельная JSON-строка формата `{"result": {"type": "ADDED", "targetGroup": {...}}}`
**And** HTTP статус не 4xx/5xx

### C7. Malformed JSON в REST-запросе возвращает HTTP 400

**ID:** 0.6-C7

**Given** gateway запущен

**When** клиент отправляет невалидный JSON:
```
curl -s -X POST http://api.kacho.local/v1/instances/list \
  -H 'Content-Type: application/json' \
  -d '{invalid-json'
```

**Then** HTTP status 400
**And** body содержит поле `code` = 3 (INVALID_ARGUMENT) или `message` с описанием ошибки парсинга
**And** gateway не аварийно завершается

### C8. Неизвестный REST-путь возвращает HTTP 404

**ID:** 0.6-C8

**Given** gateway запущен

**When** клиент запрашивает несуществующий путь:
```
curl -s http://api.kacho.local/v1/nonexistent-resource/list
```

**Then** HTTP status 404
**And** body содержит `{"code":5,"message":"Not Found"}`

### C9. REST Restart для InstanceService работает через grpc-gateway

**ID:** 0.6-C9

**Given** gateway запущен
**And** Instance `<instance-uid>` существует в состоянии `RUNNING`

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/instances/restart \
  -H 'Content-Type: application/json' \
  -d '{"instances": [{"metadata": {"uid": "<instance-uid>"}}]}'
```

**Then** HTTP status 200
**And** grpc-gateway транслирует вызов в `kacho.cloud.compute.v1.InstanceService/Restart`
**And** compute-backend обрабатывает запрос (устанавливает `metadata.restartedAt`)
**And** тело ответа содержит обновлённый Instance с заполненным `metadata.restartedAt`

---

## 4. Группа D — Allowlist filter: публичные RPC проходят (positive)

Сценарии группы D проверяют, что все публично объявленные методы успешно пропускаются allowlist-ом.

### D1. Upsert на все сервисы проходит allowlist

**ID:** 0.6-D1

**Given** allowlist содержит `/kacho.cloud.compute.v1.InstanceService/Upsert`

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/Upsert` через gateway

**Then** allowlist не блокирует запрос
**And** запрос проксируется на compute-backend
**And** возвращается ответ с кодом `OK` или доменной ошибкой (не `NOT_FOUND` с message «method blocked»)

### D2. Delete на все сервисы проходит allowlist

**ID:** 0.6-D2

**Given** allowlist содержит методы `Delete` для всех 4 сервисов

**When** клиент вызывает `kacho.cloud.vpc.v1.NetworkService/Delete` через gateway с телом `{"networks": [{"metadata": {"uid": "nonexistent-uid"}}]}`

**Then** allowlist пропускает запрос к vpc-backend
**And** ответ содержит gRPC-код `NOT_FOUND` (от vpc-backend, не от gateway)
**And** `details[].ResourceInfo.resource_id` = `"nonexistent-uid"` (из backend)

### D3. List на все сервисы проходит allowlist

**ID:** 0.6-D3

**Given** allowlist содержит `List`-методы для всех 4 сервисов

**When** клиент поочерёдно вызывает через gateway:
  - `kacho.cloud.resourcemanager.v1.OrganizationService/List`
  - `kacho.cloud.vpc.v1.NetworkService/List`
  - `kacho.cloud.compute.v1.InstanceService/List`
  - `kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/List`

**Then** все 4 запроса проксируются на соответствующие backend-ы
**And** все 4 запроса получают ответ с кодом `OK`

### D4. Watch на все сервисы проходит allowlist

**ID:** 0.6-D4

**Given** allowlist содержит `Watch`-методы для всех 4 сервисов

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.FolderService/Watch` с `resourceVersion: "0"` через gateway

**Then** allowlist пропускает запрос
**And** открывается server-streaming соединение (нет немедленного `NOT_FOUND` от gateway)

### D5. InstanceService/Restart проходит allowlist

**ID:** 0.6-D5

**Given** allowlist содержит `/kacho.cloud.compute.v1.InstanceService/Restart`

**When** клиент вызывает `InstanceService/Restart` через gateway с `metadata.uid` существующего Instance

**Then** allowlist пропускает запрос
**And** backend-сервис обрабатывает запрос и возвращает ответ (OK или доменную ошибку)

---

## 5. Группа E — Allowlist filter: Internal.* методы блокируются (negative)

Сценарии группы E проверяют, что все `*InternalService.*` методы возвращают `NOT_FOUND` (gRPC) или HTTP 404 (REST), не достигая backend.

> **Матрица Internal-методов** (согласно `01-architecture-and-services.md` §3.2):
>
> | Domain | Service | Methods |
> |---|---|---|
> | resourcemanager | `OrganizationInternalService` | `Exists`, `HasDependents` |
> | resourcemanager | `CloudInternalService` | `Exists`, `HasDependents` |
> | resourcemanager | `FolderInternalService` | `Exists`, `HasDependents` |
> | vpc | `NetworkInternalService` | `Exists`, `HasDependents` |
> | vpc | `SubnetInternalService` | `Exists`, `HasDependents` |
> | vpc | `SecurityGroupInternalService` | `Exists`, `HasDependents` |
> | vpc | `RouteTableInternalService` | `Exists`, `HasDependents` |
> | vpc | `AddressInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
> | compute | `InstanceInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
> | compute | `DiskInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
> | loadbalancer | `NetworkLoadBalancerInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
> | loadbalancer | `TargetGroupInternalService` | `Exists`, `HasDependents`, `UpdateStatus`, `RemoveTarget` |
>
> Сценарии E1–E12 покрывают представительные примеры. Сценарии E_Exists_canonical, E_HasDependents_canonical и E_UpdateStatus_canonical обобщают все методы матрицы.

### E1. FolderInternalService.Exists блокируется gateway

**ID:** 0.6-E1

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.resourcemanager.v1.FolderInternalService/Exists`

**When** клиент вызывает:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.resourcemanager.v1.FolderInternalService/Exists \
  -d '{"uid": "some-uid"}'
```

**Then** gateway возвращает gRPC-статус `NOT_FOUND` (код 5) **до** обращения к backend
**And** сообщение содержит `"method not found"` или аналогичное
**And** `details[].RequestInfo.request_id` непустой
**And** backend `resource-manager` НЕ получает этот запрос (нет записи в его access log)

### E2. OrganizationInternalService.Exists блокируется gateway

**ID:** 0.6-E2

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.resourcemanager.v1.OrganizationInternalService/Exists`

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.OrganizationInternalService/Exists` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** backend не достигается

### E3. CloudInternalService.HasDependents блокируется gateway

**ID:** 0.6-E3

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.resourcemanager.v1.CloudInternalService/HasDependents`

**When** клиент вызывает `kacho.cloud.resourcemanager.v1.CloudInternalService/HasDependents` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** backend `resource-manager` НЕ получает запрос

### E4. SubnetInternalService.Exists (vpc) блокируется gateway

**ID:** 0.6-E4

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.vpc.v1.SubnetInternalService/Exists`

**When** клиент вызывает `kacho.cloud.vpc.v1.SubnetInternalService/Exists` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** vpc-backend не получает запрос

### E5. NetworkInternalService.Exists (vpc) блокируется gateway

**ID:** 0.6-E5

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.vpc.v1.NetworkInternalService/Exists`

**When** клиент вызывает `kacho.cloud.vpc.v1.NetworkInternalService/Exists` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** vpc-backend НЕ получает запрос (нет записи в его access log)

### E6. InstanceInternalService.UpdateStatus (compute) блокируется gateway

**ID:** 0.6-E6

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.compute.v1.InstanceInternalService/UpdateStatus`

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceInternalService/UpdateStatus` через gateway с телом `{"uid": "any-uid", "status": {"state": "RUNNING"}}`

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** compute-backend НЕ получает запрос
**And** status compute-ресурса не изменяется

### E7. DiskInternalService.UpdateStatus (compute) блокируется gateway

**ID:** 0.6-E7

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.compute.v1.DiskInternalService/UpdateStatus`

**When** клиент вызывает `kacho.cloud.compute.v1.DiskInternalService/UpdateStatus` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** compute-backend НЕ получает запрос

### E8. InstanceInternalService.Exists (compute) блокируется gateway

**ID:** 0.6-E8

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.compute.v1.InstanceInternalService/Exists`

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceInternalService/Exists` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** compute-backend НЕ получает запрос

### E9. TargetGroupInternalService.RemoveTarget (loadbalancer) блокируется gateway

**ID:** 0.6-E9

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.loadbalancer.v1.TargetGroupInternalService/RemoveTarget`

**When** клиент вызывает `kacho.cloud.loadbalancer.v1.TargetGroupInternalService/RemoveTarget` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5)
**And** loadbalancer-backend не получает запрос

### E10. NetworkLoadBalancerInternalService.UpdateStatus (loadbalancer) блокируется gateway

**ID:** 0.6-E10

**Given** gateway запущен
**And** allowlist НЕ содержит `/kacho.cloud.loadbalancer.v1.NetworkLoadBalancerInternalService/UpdateStatus`

**When** клиент вызывает `kacho.cloud.loadbalancer.v1.NetworkLoadBalancerInternalService/UpdateStatus` через gateway

**Then** gRPC-статус `NOT_FOUND` (код 5) возвращается клиенту
**And** loadbalancer-backend НЕ получает запрос

### E11. REST-путь `/v1/instances/upd-status` снаружи возвращает 404

**ID:** 0.6-E11

**Given** gateway запущен
**And** grpc-gateway НЕ регистрирует handler для Internal-методов

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/instances/upd-status \
  -H 'Content-Type: application/json' \
  -d '{"uid": "any-uid", "status": {"state": "RUNNING"}}'
```

**Then** HTTP status 404
**And** body содержит `{"code":5,"message":"Not Found"}`
**And** compute-backend не получает запрос

### E12. REST-путь `/v1/folders/exists` снаружи возвращает 404

**ID:** 0.6-E12

**Given** gateway запущен

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/folders/exists \
  -H 'Content-Type: application/json' \
  -d '{"uid": "some-uid"}'
```

**Then** HTTP status 404
**And** body содержит `{"code":5,"message":"Not Found"}`

### E13. REST-путь `/v1/networks/exists` (vpc internal) снаружи возвращает 404

**ID:** 0.6-E13

**Given** gateway запущен
**And** grpc-gateway НЕ регистрирует handler для `NetworkInternalService`

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/networks/exists \
  -H 'Content-Type: application/json' \
  -d '{"uid": "some-uid"}'
```

**Then** HTTP status 404
**And** body содержит `{"code":5,"message":"Not Found"}`
**And** vpc-backend не получает запрос

### E14. REST-путь `/v1/target-groups/remove-target` (loadbalancer internal) снаружи возвращает 404

**ID:** 0.6-E14

**Given** gateway запущен
**And** grpc-gateway НЕ регистрирует handler для `TargetGroupInternalService`

**When** клиент отправляет:
```
curl -s -X POST http://api.kacho.local/v1/target-groups/remove-target \
  -H 'Content-Type: application/json' \
  -d '{"uid": "some-uid"}'
```

**Then** HTTP status 404
**And** body содержит `{"code":5,"message":"Not Found"}`
**And** loadbalancer-backend не получает запрос

### E_Exists_canonical. Канонический: все Exists-методы блокируются gateway (матрица)

**ID:** 0.6-E_Exists_canonical

> Этот сценарий обобщает покрытие для всех `Exists`-методов матрицы, не имеющих отдельных сценариев E1–E14.

**Given** gateway запущен
**And** для каждого метода M из нижеследующей матрицы: allowlist НЕ содержит M

**Матрица методов M (gRPC method path):**

| # | Метод |
|---|---|
| 1 | `/kacho.cloud.resourcemanager.v1.OrganizationInternalService/Exists` |
| 2 | `/kacho.cloud.resourcemanager.v1.CloudInternalService/Exists` |
| 3 | `/kacho.cloud.resourcemanager.v1.FolderInternalService/Exists` |
| 4 | `/kacho.cloud.vpc.v1.NetworkInternalService/Exists` |
| 5 | `/kacho.cloud.vpc.v1.SubnetInternalService/Exists` |
| 6 | `/kacho.cloud.vpc.v1.SecurityGroupInternalService/Exists` |
| 7 | `/kacho.cloud.vpc.v1.RouteTableInternalService/Exists` |
| 8 | `/kacho.cloud.vpc.v1.AddressInternalService/Exists` |
| 9 | `/kacho.cloud.compute.v1.InstanceInternalService/Exists` |
| 10 | `/kacho.cloud.compute.v1.DiskInternalService/Exists` |
| 11 | `/kacho.cloud.loadbalancer.v1.NetworkLoadBalancerInternalService/Exists` |
| 12 | `/kacho.cloud.loadbalancer.v1.TargetGroupInternalService/Exists` |

**When** для каждого метода M: клиент вызывает M через gateway (gRPC `grpcurl -plaintext`)

**Then** для каждого вызова: клиент получает gRPC-статус `NOT_FOUND` (код 5)
**And** для каждого вызова: соответствующий backend НЕ получает запрос (нет записи в его access log)

### E_HasDependents_canonical. Канонический: все HasDependents-методы блокируются gateway (матрица)

**ID:** 0.6-E_HasDependents_canonical

> HasDependents-методы не присутствовали в предыдущей редакции — этот сценарий восполняет пробел.

**Given** gateway запущен
**And** для каждого метода M из нижеследующей матрицы: allowlist НЕ содержит M

**Матрица методов M (gRPC method path):**

| # | Метод |
|---|---|
| 1 | `/kacho.cloud.resourcemanager.v1.OrganizationInternalService/HasDependents` |
| 2 | `/kacho.cloud.resourcemanager.v1.CloudInternalService/HasDependents` |
| 3 | `/kacho.cloud.resourcemanager.v1.FolderInternalService/HasDependents` |
| 4 | `/kacho.cloud.vpc.v1.NetworkInternalService/HasDependents` |
| 5 | `/kacho.cloud.vpc.v1.SubnetInternalService/HasDependents` |
| 6 | `/kacho.cloud.vpc.v1.SecurityGroupInternalService/HasDependents` |
| 7 | `/kacho.cloud.vpc.v1.RouteTableInternalService/HasDependents` |
| 8 | `/kacho.cloud.vpc.v1.AddressInternalService/HasDependents` |
| 9 | `/kacho.cloud.compute.v1.InstanceInternalService/HasDependents` |
| 10 | `/kacho.cloud.compute.v1.DiskInternalService/HasDependents` |
| 11 | `/kacho.cloud.loadbalancer.v1.NetworkLoadBalancerInternalService/HasDependents` |
| 12 | `/kacho.cloud.loadbalancer.v1.TargetGroupInternalService/HasDependents` |

**When** для каждого метода M: клиент вызывает M через gateway

**Then** для каждого вызова: клиент получает gRPC-статус `NOT_FOUND` (код 5)
**And** для каждого вызова: соответствующий backend НЕ получает запрос

### E_UpdateStatus_canonical. Канонический: все UpdateStatus-методы блокируются gateway (матрица)

**ID:** 0.6-E_UpdateStatus_canonical

**Given** gateway запущен
**And** для каждого метода M из нижеследующей матрицы: allowlist НЕ содержит M

**Матрица методов M (gRPC method path):**

| # | Метод |
|---|---|
| 1 | `/kacho.cloud.vpc.v1.AddressInternalService/UpdateStatus` |
| 2 | `/kacho.cloud.compute.v1.InstanceInternalService/UpdateStatus` |
| 3 | `/kacho.cloud.compute.v1.DiskInternalService/UpdateStatus` |
| 4 | `/kacho.cloud.loadbalancer.v1.NetworkLoadBalancerInternalService/UpdateStatus` |
| 5 | `/kacho.cloud.loadbalancer.v1.TargetGroupInternalService/UpdateStatus` |

**When** для каждого метода M: клиент вызывает M через gateway

**Then** для каждого вызова: клиент получает gRPC-статус `NOT_FOUND` (код 5)
**And** для каждого вызова: соответствующий backend НЕ получает запрос

---

## 6. Группа F — Middleware (request-id, recovery, slog access log, auth placeholder)

### F1. X-Request-ID от клиента сохраняется и пробрасывается downstream

**ID:** 0.6-F1

**Given** gateway запущен

**When** клиент отправляет gRPC-запрос с metadata `x-request-id: test-req-001`

**Then** compute-backend получает metadata `x-request-id: test-req-001` (без изменений)
**And** ответ клиенту содержит `x-request-id: test-req-001` в gRPC trailing metadata
**And** access log содержит `"request_id":"test-req-001"`

### F2. Отсутствующий X-Request-ID генерируется gateway

**ID:** 0.6-F2

**Given** gateway запущен

**When** клиент отправляет gRPC-запрос без заголовка `x-request-id`

**Then** gateway генерирует UUID v4 и присваивает его request-id
**And** downstream backend получает metadata `x-request-id: <generated-uuid>`
**And** ответ клиенту содержит `x-request-id: <generated-uuid>` в trailing metadata
**And** access log содержит `"request_id":"<generated-uuid>"`

### F3. Panic в handler-е не роняет gateway (recovery middleware)

**ID:** 0.6-F3

**Given** gateway запущен
**And** в тестовом окружении настроен специальный обработчик, вызывающий `panic("test panic")` для метода `/_test/panic` (или через unit-тест инжекции middleware)

**When** вызывается endpoint, провоцирующий panic

**Then** recovery middleware перехватывает panic
**And** клиент получает gRPC-статус `INTERNAL` (код 13) с message `"internal server error"`
**And** gateway продолжает работу и обрабатывает следующий запрос
**And** в логах присутствует запись уровня `ERROR` с `"msg":"recovered from panic"` и stack trace

### F4. slog access log содержит обязательные поля для успешного запроса

**ID:** 0.6-F4

**Given** gateway запущен

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/List` с `x-request-id: log-test-01`

**Then** в stdout gateway появляется JSON-строка уровня `INFO` со следующими полями:
  - `"msg": "access"`
  - `"method": "/kacho.cloud.compute.v1.InstanceService/List"`
  - `"status": 0` (gRPC OK)
  - `"duration_ms"` — неотрицательное число
  - `"request_id": "log-test-01"`
**And** поле `"ts"` присутствует в формате RFC 3339

### F5. slog access log содержит ненулевой status для ошибочного запроса

**ID:** 0.6-F5

**Given** gateway запущен

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/List` с невалидным полем (например, `pageSize = -1`)
**And** backend возвращает `INVALID_ARGUMENT`

**Then** в access log присутствует запись с:
  - `"status": 3` (INVALID_ARGUMENT gRPC код)
  - `"duration_ms"` — неотрицательное число

### F6. REST-запросы также логируются через slog access log

**ID:** 0.6-F6

**Given** gateway запущен

**When** клиент отправляет REST: `POST /v1/organizations/list` с `Content-Type: application/json`

**Then** в stdout gateway появляется JSON-строка уровня `INFO` со следующими полями:
  - `"msg": "access"`
  - `"method": "POST /v1/organizations/list"` (или эквивалентное)
  - `"status": 200`
  - `"duration_ms"` — неотрицательное число
  - `"request_id"` — непустая строка

### F7. Запрос без auth-заголовков проходит через gateway (auth no-op)

**ID:** 0.6-F7

**Given** gateway запущен
**And** auth-middleware установлен как placeholder (no-op)
**And** клиент НЕ передаёт никаких auth-заголовков (`Authorization`, `X-Auth-Token` и т.п.)

**When** клиент вызывает `kacho.cloud.compute.v1.InstanceService/List` через gateway

**Then** gateway не отклоняет запрос по причине отсутствия auth
**And** запрос проксируется на compute-backend
**And** клиент получает ответ с кодом `OK`
**And** auth-middleware логирует (опционально) `"auth":"no-op"` или аналог без блокировки

---

## 7. Группа G — Health probes (/healthz, /readyz, gRPC Health)

### G1. /healthz возвращает 200 OK при живом gateway

**ID:** 0.6-G1

**Given** gateway запущен (даже если backends недоступны)

**When** клиент отправляет:
```
curl -s http://api.kacho.local/healthz
```

**Then** HTTP status 200
**And** body = `"ok"` или `{"status":"ok"}`
**And** ответ приходит за < 1 секунды

### G2. /readyz возвращает 200 OK когда все backends отвечают на Health.Check

**ID:** 0.6-G2

**Given** все 4 backend-сервиса запущены и отвечают на `grpc.health.v1.Health/Check`
**And** gateway запущен

**When** клиент отправляет:
```
curl -s http://api.kacho.local/readyz
```

**Then** HTTP status 200
**And** body содержит `{"status":"ok"}` или `{"status":"SERVING","backends":{"compute":"SERVING",...}}`

### G3. /readyz возвращает 503 когда хотя бы один backend недоступен

**ID:** 0.6-G3

**Given** три из четырёх backend-сервисов запущены
**And** сервис `compute` остановлен (simulированно в тесте: `KACHO_COMPUTE_GRPC=localhost:1` — несуществующий порт)

**When** клиент запрашивает `GET /readyz`

**Then** HTTP status 503
**And** body содержит информацию о неуспешной проверке compute-backend (например, `{"status":"NOT_SERVING","backends":{"compute":"NOT_SERVING",...}}`)

### G4. /healthz не зависит от состояния backends

**ID:** 0.6-G4

**Given** все 4 backends недоступны (gateway запущен в изоляции)

**When** клиент запрашивает `GET /healthz`

**Then** HTTP status 200 (liveness не зависит от downstream)
**And** body = `"ok"` или аналог

### G5. gRPC Health.Check на gateway возвращает SERVING

**ID:** 0.6-G5

**Given** gateway запущен
**And** все backends доступны

**When** клиент вызывает gRPC health check:
```
grpcurl -plaintext api.kacho.local:80 grpc.health.v1.Health/Check -d '{}'
```

**Then** ответ `{"status":"SERVING"}`

---

## 8. Группа H — Cross-service end-to-end через gateway (resource-manager)

### H1. gateway → resource-manager: полный Upsert → List цикл

**ID:** 0.6-H1

**Given** gateway и resource-manager запущены
**And** default Organization существует

**When** клиент через gateway вызывает `CloudService/Upsert`:
  - `metadata.name = "gw-cloud-01"`
  - `metadata.organizationId = <default-org-uid>`
  - `spec.displayName = "Gateway Test Cloud"`

**Then** ответ содержит `clouds[0].metadata.uid` — непустой UUID
**And** последующий вызов `CloudService/List` через gateway возвращает Cloud с `name = "gw-cloud-01"`

### H2. gateway → resource-manager: Watch доставляет ADDED событие

**ID:** 0.6-H2

**Given** клиент A открыл Watch-стрим через gateway: `FolderService/Watch` с `resourceVersion: "0"`

**When** клиент B через gateway вызывает `FolderService/Upsert` нового Folder

**Then** клиент A получает событие `{type: "ADDED", folder: {metadata: {name: "<new-folder>"}}}` через Watch-стрим
**And** событие приходит в течение 5 секунд

### H3. gateway → resource-manager: Delete возвращает NOT_FOUND для несуществующего ресурса

**ID:** 0.6-H3

**Given** gateway и resource-manager запущены

**When** клиент вызывает через gateway `OrganizationService/Delete` с `metadata.uid = "00000000-0000-0000-0000-000000000000"` (несуществующий)

**Then** gRPC-статус `NOT_FOUND` (код 5)
**And** `details[].ResourceInfo.resource_id = "00000000-0000-0000-0000-000000000000"`

---

## 9. Группа I — Cross-service end-to-end через gateway (vpc, compute, loadbalancer)

### I1. gateway → vpc: создание Network, затем Subnet

**ID:** 0.6-I1

**Given** gateway и vpc запущены
**And** Folder `default` существует

**When** клиент последовательно через gateway:
  1. `NetworkService/Upsert` с `metadata.name = "gw-net-01"`, `metadata.folderId = <folder-uid>`
  2. `SubnetService/Upsert` с `metadata.name = "gw-subnet-01"`, `spec.networkId = <network-uid>`, `spec.cidr = "10.100.0.0/24"`

**Then** оба Upsert возвращают `OK` с заполненными `metadata.uid`
**And** `SubnetService/List` через gateway возвращает Subnet с `metadata.name = "gw-subnet-01"`

### I2. gateway → compute: создание Instance, переход PROVISIONING → RUNNING через Watch

**ID:** 0.6-I2

**Given** gateway и compute запущены
**And** Disk `<disk-uid>`, Subnet `<subnet-uid>`, Folder `<folder-uid>` существуют
**And** клиент открыл Watch-стрим через gateway: `InstanceService/Watch` с `selectors[0].field_selector.folder_id = <folder-uid>`

**When** клиент вызывает через gateway `InstanceService/Upsert`:
  - `metadata.name = "e2e-vm-01"`, `metadata.folderId = <folder-uid>`
  - `spec.platformId = "standard-v3"`, `spec.zoneId = "kacho-zone-a"`
  - `spec.resources.cores = 2`, `spec.resources.memory = "4Gi"`
  - `spec.bootDisk.diskId = <disk-uid>`
  - `spec.networkInterfaces[0].subnetId = <subnet-uid>`
  - `spec.desiredPowerState = "RUNNING"`

**Then** Upsert-ответ содержит `status.state = "PROVISIONING"`
**And** через Watch-стрим (через gateway proxy) в течение 60 секунд приходит событие `MODIFIED` с `status.state = "RUNNING"`
**And** события доставляются в реальном времени (не буферизируются до закрытия стрима)

### I3. gateway → loadbalancer: создание TargetGroup с targets

**ID:** 0.6-I3

**Given** gateway и loadbalancer запущены
**And** Instance `<instance-uid>` в состоянии RUNNING, Subnet `<subnet-uid>` существуют
**And** Folder `<folder-uid>` существует

**When** клиент вызывает через gateway `TargetGroupService/Upsert`:
  - `metadata.name = "gw-tg-01"`, `metadata.folderId = <folder-uid>`
  - `spec.targets[0].subnetId = <subnet-uid>`, `spec.targets[0].address = "10.0.0.5"`, `spec.targets[0].instanceId = <instance-uid>`

**Then** ответ содержит `targetGroups[0].metadata.uid` — непустой UUID
**And** `targetGroups[0].status.state = "READY"`

### I4. gateway → loadbalancer: создание NLB и переход CREATING → ACTIVE

**ID:** 0.6-I4

**Given** gateway и loadbalancer запущены
**And** TargetGroup `<tg-uid>` с состоянием READY существует
**And** Folder `<folder-uid>` существует

**When** клиент вызывает через gateway `NetworkLoadBalancerService/Upsert`:
  - `metadata.name = "gw-nlb-01"`, `metadata.folderId = <folder-uid>`
  - `spec.regionId = "kacho-region-a"`
  - `spec.listeners[0].name = "http"`, `spec.listeners[0].port = 80`, `spec.listeners[0].protocol = "TCP"`
  - `spec.attachedTargetGroups[0].targetGroupId = <tg-uid>`

**Then** Upsert-ответ содержит `networkLoadBalancers[0].status.state = "CREATING"` или `"ACTIVE"`
**And** в течение 30 секунд через Watch-стрим (через gateway) приходит событие `MODIFIED` с `status.state = "ACTIVE"`

### I5. gateway проксирует Watch-стрим для compute без обрывов за 30 секунд

**ID:** 0.6-I5

**Given** gateway и compute запущены
**And** клиент открыл Watch-стрим через gateway на `InstanceService/Watch` с `resourceVersion: "0"`
**And** nginx ingress `proxy_read_timeout` установлен ≥ 120s (аннотация на Ingress-ресурсе)
**And** gRPC keepalive interval на клиентских соединениях gateway→backend = 30 секунд

**When** в течение 30 секунд не происходит никаких изменений

**Then** стрим не закрывается (нет EOF от gateway)
**And** gateway не генерирует ошибочных событий
**And** клиент остаётся подключённым (keepalive поддерживается)

---

## 10. Группа J — Негативные сценарии (downstream недоступен, malformed, concurrent)

### J1. Downstream backend UNAVAILABLE → клиент получает UNAVAILABLE (код 14)

**ID:** 0.6-J1

**Given** gateway запущен
**And** сервис compute недоступен (`KACHO_COMPUTE_GRPC=localhost:1`)

**When** клиент вызывает `InstanceService/List` через gateway

**Then** gateway пытается подключиться к compute и получает connection refused
**And** клиент получает gRPC-статус `UNAVAILABLE` (код 14)
**And** message содержит указание на недоступность downstream
**And** `details[].RequestInfo.request_id` непустой
**And** gateway продолжает работу (не падает)

### J2. Downstream backend UNAVAILABLE → REST возвращает HTTP 503

**ID:** 0.6-J2

**Given** gateway запущен
**And** сервис vpc недоступен

**When** клиент отправляет REST: `POST /v1/networks/list` с `{}`

**Then** HTTP status 503
**And** body содержит `{"code":14,"message":"..."}` (grpc-gateway маппит UNAVAILABLE → 503)

### J3. gRPC-запрос с невалидным gRPC-method-path возвращает NOT_FOUND

**ID:** 0.6-J3

**Given** gateway запущен

**When** клиент отправляет gRPC-запрос с path `//BadPath` (не соответствует формату `/<pkg>.<Svc>/<Method>`)

**Then** gateway не паникует
**And** клиент получает gRPC-статус `NOT_FOUND` (код 5) — allowlist-фильтр срабатывает до backend-роутинга
**And** gateway продолжает работу

### J4. Таймаут downstream backend → клиент получает DEADLINE_EXCEEDED

**ID:** 0.6-J4

**Given** gateway запущен
**And** compute-backend настроен на искусственную задержку > 30 секунд (unit-test с mock)
**And** клиент устанавливает deadline 2 секунды через gRPC metadata `grpc-timeout: 2S`

**When** клиент вызывает `InstanceService/List` с deadline 2 секунды

**Then** через 2 секунды клиент получает gRPC-статус `DEADLINE_EXCEEDED` (код 4)
**And** gateway корректно отменяет downstream запрос (context cancellation propagated)

### J5. Concurrent запросы обрабатываются без data race

**ID:** 0.6-J5

**Given** gateway запущен с флагом race detector (`-race` в go test)
**And** все backends подняты

**When** 50 горутин одновременно отправляют `OrganizationService/List` через gateway

**Then** все 50 запросов завершаются с кодом `OK`
**And** go race detector не фиксирует data race
**And** gateway не аварийно завершается

### J6. gRPC stream прерывается при отключении клиента — gateway чисто завершает proxy

**ID:** 0.6-J6

**Given** клиент открыл Watch-стрим через gateway на `InstanceService/Watch`
**And** стрим активен 3 секунды

**When** клиент закрывает соединение (TCP reset / process kill)

**Then** gateway обнаруживает закрытие context
**And** upstream запрос к compute-backend отменяется (context cancel propagated)
**And** горутина proxy-обработчика завершается без goroutine leak
**And** в логах присутствует запись с указанием на завершение стрима (без panic/error)

### J7. Watch-стрим: backend возвращает OUT_OF_RANGE (Gone) — gateway проксирует код без изменений

**ID:** 0.6-J7

**Given** gateway и compute запущены
**And** клиент открыл Watch-стрим с устаревшим `resourceVersion` (за пределами retention-окна outbox)

**When** compute-backend возвращает gRPC-статус `OUT_OF_RANGE` (код 11) с message `"resourceVersion too old, relist required"`

**Then** gateway прозрачно передаёт статус `OUT_OF_RANGE` клиенту без изменения кода или message
**And** стрим закрывается с кодом `OUT_OF_RANGE` (не преобразуется в другой код gateway-ом)
**And** access log gateway содержит `"status":11`

---

## 11. Группа K — End-to-end smoke (Ingress → api-gateway → backend)

Сценарии группы K — финальная вертикальная проверка: весь путь от Ingress до backend через gateway.

### K1. grpcurl через Ingress → gateway → compute: полный путь InstanceService/Upsert

**ID:** 0.6-K1

**Given** kind-кластер поднят (`make dev-up`)
**And** все 4 backend-сервиса задеплоены и в состоянии Ready (kubectl get pods -n kacho)
**And** api-gateway задеплоен в namespace kacho
**And** Ingress настроен на `api.kacho.local:80` → `api-gateway:8080`
**And** /etc/hosts содержит `127.0.0.1 api.kacho.local`
**And** Disk `<disk-uid>`, Subnet `<subnet-uid>`, Folder `<folder-uid>` существуют

**When** выполняется из хоста:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.compute.v1.InstanceService/Upsert \
  -d '{
    "instances": [{
      "metadata": {"name": "smoke-vm-01", "folderId": "<folder-uid>"},
      "spec": {
        "platformId": "standard-v3",
        "zoneId": "kacho-zone-a",
        "resources": {"cores": 2, "memory": "4Gi"},
        "bootDisk": {"diskId": "<disk-uid>"},
        "networkInterfaces": [{"subnetId": "<subnet-uid>"}],
        "desiredPowerState": "RUNNING"
      }
    }]
  }'
```

**Then** команда завершается без ошибки
**And** ответ содержит `instances[0].metadata.uid` — непустой UUID
**And** `instances[0].status.state` = `"PROVISIONING"`

### K2. curl через Ingress → gateway → compute: REST InstanceService/List

**ID:** 0.6-K2

**Given** то же окружение, что в K1
**And** Instance `smoke-vm-01` создан (из K1 или отдельным шагом)

**When** выполняется:
```
curl -s -X POST http://api.kacho.local/v1/instances/list \
  -H 'Content-Type: application/json' \
  -d '{}'
```

**Then** HTTP status 200
**And** body содержит `instances` — массив с хотя бы одним Instance
**And** среди элементов есть Instance с `metadata.name = "smoke-vm-01"`

### K3. Попытка вызова Internal через Ingress → gateway: NotFound

**ID:** 0.6-K3

**Given** то же окружение

**When** выполняется:
```
grpcurl -plaintext api.kacho.local:80 \
  kacho.cloud.compute.v1.InstanceInternalService/UpdateStatus \
  -d '{"uid": "any-uid", "status": {"state": "RUNNING"}}'
```

**Then** gRPC-статус `NOT_FOUND` (код 5)
**And** compute-backend в логах не содержит записи об обработке этого запроса

### K4. Полный вертикальный smoke: все 4 сервиса через gateway

**ID:** 0.6-K4

**Given** полное развёртывание (`make dev-up`)
**And** default Org → Cloud → Folder существуют

**When** последовательно выполняются bash-команды e2e/0.6/K4-full-smoke.sh:
  1. `OrganizationService/List` через grpcurl — возвращает default Org
  2. `NetworkService/Upsert` — создаёт Network `smoke-net`
  3. `SubnetService/Upsert` — создаёт Subnet `smoke-subnet` в `smoke-net`
  4. `InstanceService/Upsert` — создаёт Instance `smoke-vm`
  5. `TargetGroupService/Upsert` — создаёт TargetGroup `smoke-tg` с таргетом из `smoke-vm`
  6. `NetworkLoadBalancerService/Upsert` — создаёт NLB `smoke-nlb` с `smoke-tg`
  7. `InstanceService/List` — проверяет список

**Then** все 7 команд завершаются с кодом 0
**And** все ресурсы видны через соответствующие List-запросы через gateway
**And** `make e2e-test` (если задан e2e-скрипт 0.6) завершается с кодом 0

### K5. Ingress в helm/umbrella привязан к api-gateway Service

**ID:** 0.6-K5

**Given** `kacho-deploy` helm-umbrella chart задеплоен

**When** выполняется:
```
kubectl get ingress -n kacho -o jsonpath='{.items[0].spec.rules[0].http.paths[0].backend.service.name}'
```

**Then** вывод = `api-gateway` (или аналогичное имя Service для api-gateway в namespace kacho)
**And** `kubectl get ingress -n kacho` показывает host `api.kacho.local` и ADDRESS не пустой

---

## 12. Группа L — Definition of Done

### L1. Код и структура репозитория

**ID:** 0.6-L1

**Given** реализация sub-phase 0.6 завершена

**Then** репозиторий `kacho-api-gateway` содержит:
  - `cmd/api-gateway/main.go` — composition root: wiring cmux + gRPC proxy + REST mux + middleware; инициализирует один `*grpc.ClientConn` per backend
  - `internal/proxy/` — gRPC-proxy handler с domain-routing и allowlist-фильтром
  - `internal/restmux/` — grpc-gateway регистрация всех 4 сервисов
  - `internal/middleware/` — request-id, recovery, slog access log, auth no-op placeholder
  - `internal/health/` — /healthz, /readyz, gRPC Health handler
  - `internal/allowlist/list.go` — Go-константа `map[string]struct{}` со всеми публичными методами; `*InternalService.*` отсутствуют
  - `deploy/` — Helm chart для api-gateway (или интеграция в kacho-deploy umbrella)
**And** в `kacho-deploy/helm/umbrella/templates/` присутствует Ingress с backend `api-gateway`
**And** Ingress содержит аннотацию `nginx.ingress.kubernetes.io/proxy-read-timeout: "120"`

### L2. Тесты

**ID:** 0.6-L2

**Then** каждый acceptance-сценарий группы A–J покрыт unit- или integration-тестом с именем `TestGateway_<ID>_<ShortDesc>`
**And** для канонических сценариев E_Exists_canonical, E_HasDependents_canonical, E_UpdateStatus_canonical тест итерируется по матрице методов
**And** integration-тесты используют testcontainers или mock gRPC-серверы (не реальные backends)
**And** `go test ./... -race` завершается с кодом 0
**And** coverage acceptance-сценариев: ≥ 90% сценариев группы A–J покрыты тестами

### L3. E2e bash-сценарии

**ID:** 0.6-L3

**Then** в `kacho-deploy/e2e/0.6/` присутствуют bash-скрипты для сценариев группы K (K1–K5)
**And** `make e2e-test` (или эквивалент) запускает эти скрипты против живого kind-кластера
**And** все e2e-скрипты завершаются с кодом 0

### L4. CI зелёный

**ID:** 0.6-L4

**Then** CI pipeline для `kacho-api-gateway` зелёный: lint, `go vet`, unit-тесты, integration-тесты
**And** CI для `kacho-proto` зелёный (если добавлялись HTTP-аннотации в proto)
**And** CI для `kacho-deploy` зелёный (helm lint + e2e-тест)

### L5. Документация

**ID:** 0.6-L5

**Then** `kacho-api-gateway/README.md` или `CLAUDE.md` содержит:
  - пример `grpcurl` команды через `api.kacho.local:80`
  - пример `curl` REST команды через `api.kacho.local/v1/`
  - описание allowlist-конфига (как добавить новый публичный метод в `internal/allowlist/list.go`)
  - список env-переменных (`KACHO_*_GRPC`)
**And** `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.6

### L6. Тег версии

**ID:** 0.6-L6

**Then** Docker-образ `prorobotech/kacho-api-gateway:0.6.0` успешно собирается
**And** тег `kacho-api-gateway:0.6.0` присутствует в git

---

## 13. Разрешённые вопросы (Resolution table)

Все открытые вопросы предыдущей редакции закрыты. Принятые решения зафиксированы в «Зафиксированные соглашения» (§0) и в тексте сценариев.

| OQ | Вопрос | Решение |
|---|---|---|
| OQ-1 | Формат allowlist-конфига | **Go-константа** (`map[string]struct{}`) в `internal/allowlist/list.go`. YAML/ConfigMap — фаза 1. |
| OQ-2 | Имена REST-путей для resource-manager | **`/v1/<resource>/<action>`** без prefix домена (например, `/v1/organizations/upsert`). Определяется HTTP-аннотациями в `kacho-proto`. |
| OQ-3 | Request-id header name | **`X-Request-ID`** (зафиксировано в предыдущей редакции). |
| OQ-4 | grpc-gateway streaming output format | **`application/json` chunked, newline-delimited JSON**: каждое сообщение — отдельная строка `{"result": {...}}`. |
| OQ-5 | Keepalive / idle timeout | **gRPC keepalive interval = 30s** на клиентских соединениях gateway→backend; **nginx `proxy_read_timeout = 120s`** (аннотация на Ingress). |
| OQ-6 | Backend connection pooling | **Один `*grpc.ClientConn` per backend**, инициализируется один раз в `cmd/api-gateway/main.go`. Никакого per-request dial. |
