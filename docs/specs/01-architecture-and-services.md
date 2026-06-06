# Kachō — Архитектура и сервисы

**Документ:** 01 / 5

## 1. Граф сервисов

```
                     ingress-nginx (HTTP, port 80)
                              │ host=api.kacho.local
                              ▼
                    ┌───────────────────────┐
                    │   kacho-api-gateway   │  edge: gRPC-proxy + grpc-gateway REST
                    └─────┬───────────┬─────┘
        ┌─────────────────┘           └─────────────────┐
        │                                                │
        ▼                                                ▼
┌───────────────────┐                          ┌─────────────────┐
│ resource-manager  │   ◀──── parent validation────  vpc          │
│ Org/Cloud/Folder  │                          │   Networks/SG   │
└───────────────────┘                          └─────┬───────────┘
                                                     │ ref check
                ┌────────────────────────────────────┘
                ▼
       ┌─────────────────┐                   ┌─────────────────┐
       │     compute      │ ◀─ instance ref ── loadbalancer    │
       │  Instances/Disks │                   │ NLB/TargetGroup│
       └─────────────────┘                   └─────────────────┘
```

**Граф зависимостей синхронных gRPC-вызовов:**

- Все ресурсные сервисы → `resource-manager` (валидация `folderId`).
- `vpc` → `compute` (валидация `zoneId` через `compute.v1.ZoneService.Get` — Geography/Region/Zone — домен kacho-compute, эпик `KAC-15`; раньше было наоборот — это ребро удалено).
- `compute` → `vpc` (валидация NIC-spec — `subnetId`/`securityGroupIds`; IPAM-аллокация эфемерных `Address` через `AddressService`/`InternalAddressService`).
- `loadbalancer` → `vpc` (валидация `networkId`) + `compute` (валидация `instanceId` в targets).
- `vpc-implement` (future data-plane sibling, `kacho-vpc-implement`, spec-only) — будущий SRv6 data-plane; прежняя kube-ovn-эпохи control-plane-привязка (write-back состояния NI, чтение vpn_id/node_index у upstream) удалена в KAC-36/79/80.

Циклов нет. Все межсервисные вызовы — синхронный gRPC, internal API (не маршрутизируется через api-gateway наружу на external TLS-endpoint).

## 2. Сервисы

### 2.1 `kacho-api-gateway`

**Роль:** единая точка входа для внешних клиентов. Не содержит бизнес-логики, не имеет БД.

**Поведение:**
- TCP listener на порту 8080 (HTTP/2 cleartext + HTTP/1.1).
- Использует `cmux` для разделения: `Content-Type: application/grpc*` → gRPC-proxy, прочее → REST `runtime.ServeMux` от grpc-gateway.
- **gRPC-proxy** через `grpc.UnknownServiceHandler` (`mwitkow/grpc-proxy`): по gRPC-method-path `/kacho.cloud.<domain>.v1.<Service>/<Method>` определяет `<domain>` и проксирует на соответствующий backend (`compute.kacho.svc.cluster.local:9090`, и т. п.). Поддерживает streaming RPC прозрачно (нужно для `/watch`).
- **REST mux**: импортирует все сгенерированные `RegisterXxxServiceHandlerFromEndpoint`, регистрирует обработчики. REST-маршруты: `POST /v1/<resource>/upsert`, `/delete`, `/list`, `/watch`, и т.п.
- Middleware-цепочка: request-id (`X-Request-ID`), recovery (panic → 500), structured access log (`slog`), placeholder для будущего auth.
- НЕ маршрутизирует internal-RPC (`/upd-status`, internal-`Exists` методы между сервисами): таблица allowlist в gateway-конфиге определяет публично-доступные RPC.
- **Два mux'а**: external TLS-endpoint (advertised, для внешних клиентов) и cluster-internal mux (UI / admin-tooling / port-forward). `Internal*`-сервисы регистрируются **только** на internal mux. Текущая регистрация: `NetworkInterfaceService` — public, `/vpc/v1/networkInterfaces`; Geography (`Region`/`Zone` — public read + admin CRUD через `Internal*`-сервисы) — на `/compute/v1/...` (перенесено из vpc, эпик `KAC-15`).

**Health probes:** `/healthz` (alive), `/readyz` (alive + все backends отвечают на gRPC `Health.Check`).

### 2.2 `kacho-resource-manager`

**Роль:** иерархия Organization → Cloud → Folder. Без lifecycle (мгновенно создаются и удаляются).

**Ресурсы:**

- `Organization` — top-level. Identification: `metadata.name` (глобально уникален).
- `Cloud` — parent: organization. Identification: `metadata.name` (уникален в `metadata.organizationId`).
- `Folder` — parent: cloud. Identification: `metadata.name` (уникален в `metadata.cloudId`).

**API per ресурс:** `/upsert`, `/delete`, `/list`, `/watch`. Нет sub-resource методов (нет lifecycle). Нет `/upd-status` (не имеет смыслового status).

**Bootstrap.** При первом запуске создаются дефолтная Organization → Cloud → Folder (`name=default` на каждом уровне) — чтобы можно было сразу делать ресурсы compute/vpc/lb с валидным `folderId`.

### 2.3 `kacho-vpc`

**Роль:** control plane сетевых ресурсов.

**Ресурсы:**

- `Network` — контейнер для подсетей. Без lifecycle (мгновенно). (Прежний internal-only data-plane-идентификатор VPN на Network — удалён в KAC-36/79/80 вместе с kube-ovn-эпохи control-plane-слоем.)
- `Subnet` — IP-диапазон в Network. Без lifecycle. `v4_cidr_blocks` **не обязателен** на `Create` (подсеть может быть создана без IPv4 CIDR, добавлен позже вербом `:add-cidr-blocks`); `:add-cidr-blocks`/`:remove-cidr-blocks` принимают и `v4_cidr_blocks`, и `v6_cidr_blocks`; `UpdateSubnet` принимает `v6_cidr_blocks` (soft-immutable, как v4 — реальные изменения через вербы).
- `SecurityGroup` + `SecurityGroupRule` — правила фильтрации. Без lifecycle. `network_id` **не обязателен** на `Create` — SG может быть folder-level / не привязан к сети (default-SG-on-network не меняется).
- `RouteTable` + `StaticRoute` — таблицы маршрутизации. Без lifecycle.
- `Address` — IP-адрес. Имеет minimal lifecycle status. Поддерживает internal IPv6: `Address.internal_ipv6_address` (oneof `{address, oneof scope{subnet_id}}`), `CreateAddressRequest.internal_ipv6_address_spec`, `InternalAddressService.AllocateInternalIPv6`; `ListAddressesRequest.subnet_id` фильтрует по v4 ИЛИ v6 internal `subnet_id`. `used_by` — best-effort usage-hint (`kacho.cloud.reference.Reference`), кто привязал адрес.
- `NetworkInterface` (NIC) — first-class ресурс домена kacho-vpc (AWS-ENI-подобный). Принадлежит `Subnet` (`subnet_id`); ссылается на `Address`-ресурсы по id (`v4_address_ids[]`/`v6_address_ids[]` — один Address максимум на одном NIC, enforced на service-слое через `addresses.used` + `address_references`); несёт `security_group_ids[]` (default на `Create` = `Network.default_security_group_id`); имеет `used_by` (`kacho.cloud.reference.Reference` — кто его прикрепил; ставится `AttachToInstance`, чистится `DetachFromInstance`, зеркалит `Address.used_by`); `status ∈ {PROVISIONING, ACTIVE, AVAILABLE, FAILED, DELETING}`. Может быть создан без адресов. Публичная проекция — lean (control-plane-only). NIC compute-инстанса ссылается на VPC-NIC по `nic_id` (device-index — на `compute.v1.NetworkInterface.index`). (Прежняя internal data-plane-проекция NIC удалена в KAC-36/79/80.)

**Cross-service validation:** при `Create` `Subnet` валидируется `networkId` (внутренняя FK same-DB) и `zoneId` (вызов `compute.v1.ZoneService.Get`). При `Create` ресурсов compute/loadbalancer, ссылающихся на VPC-ресурсы, **они** делают gRPC-вызов в `kacho-vpc`.

**FK / dependency-цепочка (всё RESTRICT):** `NetworkInterface → Address → Subnet → Network`. `Address.Delete` блокируется, пока на адрес ссылается NIC; `Subnet.Delete` блокируется, пока есть internal-Address-ы (v4 ИЛИ v6) или хоть один NetworkInterface; `Network.Delete` блокируется, пока есть subnets / route-tables / non-default SG (default SG авто-удаляется). Net-effect: удаление снизу-вверх — NIC → Address → Subnet → Network, с понятным precondition-error на каждом уровне.

### 2.4 `kacho-compute`

**Роль:** control plane виртуальных машин и блочных дисков. Самый сложный сервис — содержит reconciler с симулированным lifecycle.

**Ресурсы:**

- `Instance` — VM. **Полный lifecycle**: `PROVISIONING → RUNNING ⇆ STOPPING → STOPPED ⇆ STARTING → RUNNING; → DELETING → terminal`. `spec.desiredPowerState ∈ {RUNNING, STOPPED}`. Reconciler симулирует переходы с задержками 5–30с.
- `Disk` — блочный диск. Lifecycle: `CREATING → READY ⇆ ATTACHING/DETACHING`. Симулированно.
- `Image` — read-only catalog (родительские образы для дисков). Seed-таблица, всегда `READY`.
- `Snapshot` — снимок диска. Lifecycle: `CREATING (с progress%) → READY`. Симулированно.
- (Прежний internal-only `Hypervisor`-ресурс и `InternalHypervisorService` — kube-ovn-эпохи placement/HW-inventory — удалены в KAC-36/79/80.)

**Sub-resource updates** (только internal, не наружу):
- `/upd-status` — стандартный, для всех ресурсов с lifecycle.

**Imperative thin RPC** (наружу, через api-gateway, тонкая обёртка над `metadata`-control-signals):
- `POST /v1/compute/instances/restart` — устанавливает `metadata.restartedAt = now()`. Reconciler сравнивает с `status.lastRestartCompletedAt`, выполняет stop+start цикл при расхождении.

`Start` и `Stop` НЕ имеют отдельных RPC — реализуются через upsert с `spec.desiredPowerState`. CLI добавит alias-команды поверх.

**Cross-service validation при upsert Instance:**
- `metadata.folderId` → `kacho-resource-manager` (gRPC `Internal.FolderExists`).
- `spec.bootDisk.diskId` → same-DB FK на `disks`.
- `spec.networkInterfaces[].subnetId` → `kacho-vpc` (gRPC `Internal.SubnetExists`).

### 2.5 `kacho-loadbalancer`

**Роль:** control plane Network Load Balancer (L4).

**Ресурсы:**

- `NetworkLoadBalancer` — L4 балансировщик. Lifecycle: `CREATING → ACTIVE`. Listeners и attached target-groups — inline JSONB-поля в `spec`, не отдельные ресурсы (по аналогии с YC NLB).
- `TargetGroup` — группа таргетов (instance + subnet). Lifecycle: `CREATING → READY`.

**Cross-service validation при upsert NLB:**
- `metadata.folderId` → resource-manager.
- `spec.attachedTargetGroups[].targetGroupId` → same-DB FK.

**Cross-service validation при upsert TargetGroup:**
- `spec.targets[].subnetId` → vpc.
- `spec.targets[].address` — IP-адрес, опционально валидируется на принадлежность какому-то Instance (через compute.Internal.HasInstanceWithIP) — пока не валидируется (упрощение).

## 3. Стандартный API на каждый ресурс

### 3.1 Публичные RPC (наружу через api-gateway)

| Метод | REST | Семантика |
|---|---|---|
| `<Service>.Upsert(req)` | `POST /v1/<r>/upsert` | batch create-or-update; identification: `metadata.uid` или `metadata.name` + parent IDs |
| `<Service>.Delete(req)` | `POST /v1/<r>/delete` | batch soft-delete (server выставляет `metadata.deletionTimestamp`); финальное удаление после finalizers cleanup |
| `<Service>.List(req)` | `POST /v1/<r>/list` | через `selectors[]` |
| `<Service>.Watch(req)` | `POST /v1/<r>/watch` | server-streaming, `resourceVersion` cursor |

**Imperative thin-RPC** (только где осмысленно):
| Метод | REST | Семантика |
|---|---|---|
| `<Service>.Restart(req)` | `POST /v1/<r>/restart` | устанавливает `metadata.restartedAt` |
| `NetworkInterfaceService.AttachToInstance(req)` | `POST /vpc/v1/networkInterfaces/{id}:attachToInstance` | ставит `NetworkInterface.used_by` (кто прикрепил) |
| `NetworkInterfaceService.DetachFromInstance(req)` | `POST /vpc/v1/networkInterfaces/{id}:detachFromInstance` | чистит `used_by` |

`NetworkInterfaceService` — стандартный набор `Get`/`List`/`Create`/`Update`/`Delete`/`ListOperations` + `AttachToInstance`/`DetachFromInstance`; REST-префикс `/vpc/v1/networkInterfaces`.

### 3.2 Internal RPC (между сервисами, не наружу)

| Метод | Назначение |
|---|---|
| `<Service>.Internal.<Resource>Exists(uid)` | существует ли ресурс с заданным uid |
| `<Service>.Internal.HasDependentsOn(uid)` | есть ли зависимые ресурсы — для валидации удаления |
| `<Service>.Internal.UpdateStatus(req)` | reconciler пишет в `status` |
| `InternalAddressService.AllocateInternalIPv6` | аллокация internal IPv6 (рядом с `AllocateInternalIPv4`) |

`api-gateway` НЕ маршрутизирует `Internal.*` методы / `Internal*`-сервисы на external TLS-endpoint — только на cluster-internal mux (allowlist-фильтр).

**`ListOperations` переживает удаление ресурса:** история операций (таблица `operations`) не каскад-удаляется вместе с ресурсом; `ListOperations(resource_id)` работает после того, как ресурс удалён (per-service `ListOperations` больше не требует существования ресурса).

## 4. Watch architecture (Kine-style)

Полное описание реализации — в `02-data-model-and-conventions.md` (секция «Watch + Outbox»). Кратко:

1. **Outbox-таблица** в каждой service-БД (`resource_events`) хранит каждое мутирующее действие.
2. **Транзакционная атомарность**: любая мутация ресурса + INSERT в outbox в одной транзакции.
3. **Wake-up через `pg_notify`** на канале `kacho_<svc>` (без payload — только trigger).
4. **In-process Watch Hub** в каждой реплике сервиса:
   - Одна горутина с cursor по `resource_version`.
   - Просыпается на NOTIFY (или ticker 100мс fallback).
   - Читает свежие события из outbox, бродкастит в локальные in-memory channels.
5. **Watch endpoint** (gRPC streaming) — каждый клиентский стрим — горутина, подписана на hub, фильтрует по selector-у, отправляет в gRPC stream.
6. **Catch-up для отстающих клиентов** — клиент с `resourceVersion`, доступной в outbox-retention-окне (1 час), догоняет по запросу. С устаревшим — `Gone 410` → relist.

**Масштаб**: до миллионов ресурсов, до 100k concurrent watchers на сервисный кластер. Точка перехода на внешний broker (NATS JetStream) — заранее заложена, без изменений API.

## 5. Reconciler-pattern

Сервисы с lifecycle (`compute`, `loadbalancer`) имеют reconciler — фоновую горутину, которая:

1. Опрашивает БД на ресурсы с `status.state ≠ desired`-семантикой:
   - Pending creation: `status.state IS NULL OR status.state = 'CREATING'`.
   - Pending state change: `spec.desiredPowerState ≠ status.state` (для Instance).
   - Pending restart: `metadata.restartedAt > status.lastRestartCompletedAt`.
   - Pending deletion: `metadata.deletionTimestamp IS NOT NULL AND finalizers[] != []`.
2. Берёт `pg_advisory_lock` на `resource_uid` (защита от двух reconciler-репик, обрабатывающих один ресурс).
3. Выполняет переход (симулированно — `time.Sleep` на нужный интервал, реальный гипервизор не дёргается).
4. Транзакционно обновляет `status` через `UpdateStatus` (своё internal-RPC) + outbox-event.

**Координация multi-replica:** каждая реплика независимо опрашивает БД. Advisory locks предотвращают двойную обработку. Eventually-consistent.

## 6. Config и DNS

- Каждый сервис конфигурируется через env-переменные (`envconfig`).
- DNS внутри cluster: `<service>.kacho.svc.cluster.local`. В коде используются короткие имена (`compute`, `vpc`), k8s DNS добавляет суффикс.
- Внешний endpoint: `http://api.kacho.local:80` (через ingress).
- Адреса backend-ов в api-gateway-конфиге:
  ```
  KACHO_RESOURCE_MANAGER_GRPC=resource-manager.kacho.svc.cluster.local:9090
  KACHO_VPC_GRPC=vpc.kacho.svc.cluster.local:9090
  KACHO_COMPUTE_GRPC=compute.kacho.svc.cluster.local:9090
  KACHO_LOADBALANCER_GRPC=loadbalancer.kacho.svc.cluster.local:9090
  ```

## 7. Health и observability (минимум)

- **Health probes**: каждый сервис экспонирует `/healthz` (HTTP) и gRPC `grpc.health.v1.Health.Check`. K8s-Liveness и Readiness probes сконфигурированы.
- **Metrics**: `/metrics` Prometheus-эндпоинт на каждом сервисе (закомментированный ServiceMonitor в helm-chart).
- **Tracing**: OpenTelemetry SDK инициализируется условно (env `KACHO_OTEL_EXPORTER_OTLP_ENDPOINT`), в dev по умолчанию выключен.
- **Логи**: structured JSON через `slog` в stdout. K8s `kubectl logs` достаточно в dev.

Production-настройки observability stack (Loki/Grafana/Tempo) — отдельная фаза.
