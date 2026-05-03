# Sub-phase 0.6 — API Gateway (cmux + gRPC-proxy + grpc-gateway REST + allowlist) — Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` для исполнения. Acceptance APPROVED commit `88db213` в `kacho-workspace/docs/specs/sub-phase-0.6-api-gateway-acceptance.md` (59 сценариев, 12 групп A–L).

**Goal:** `kacho-api-gateway` — единая точка входа для всех внешних клиентов Kachō. Сервис принимает gRPC и REST на одном порту 8080 через `cmux`-демультиплексор, прозрачно проксирует gRPC-трафик к четырём backend-сервисам через `mwitkow/grpc-proxy`, а REST-запросы обрабатывает через `grpc-gateway` runtime mux. Allowlist-фильтр гарантирует выполнение запрета CLAUDE.md §8: никакой `*InternalService.*`-метод не достигает внешнего клиента — такие вызовы возвращают `NOT_FOUND` (gRPC) / `404` (REST). После завершения итерации все команды `grpcurl` и `curl` из предыдущих acceptance-документов работают через `api.kacho.local:80`; Ingress в helm/umbrella привязан к `api-gateway`-сервису.

**Architecture:** API Gateway НЕ имеет БД, НЕ содержит бизнес-логики. Единственный TCP listener на порту 8080. `cmux` инспектирует первые байты соединения: `Content-Type: application/grpc*` → gRPC listener (proxy), всё остальное → HTTP listener (grpc-gateway REST mux). Backend-адреса конфигурируются через env-переменные; каждый backend получает один постоянный `*grpc.ClientConn`, инициализируемый один раз в composition root. Allowlist — Go-константа `map[string]struct{}` в `internal/allowlist/list.go`; все `*InternalService.*` явно отсутствуют в ней.

**Tech stack:** Go 1.22+, `soheilhy/cmux`, `mwitkow/grpc-proxy`, `grpc-ecosystem/grpc-gateway/v2`, `google.golang.org/grpc`, `log/slog` (stdlib), `google/uuid`, testcontainers-go (mock gRPC-серверы для integration-тестов). Никакого pgx, sqlc, goose — api-gateway не имеет БД.

---

## §0. OQ Resolutions (quick reference)

Все открытые вопросы закрыты в acceptance-документе. Ниже — компактная таблица для реализаторов:

| OQ | Вопрос | Решение |
|---|---|---|
| OQ-1 | Формат allowlist-конфига | **Go-константа** `map[string]struct{}` в `internal/allowlist/list.go`. YAML/ConfigMap — фаза 1. |
| OQ-2 | Имена REST-путей | **`/v1/<resource>/<action>`** без prefix домена (например, `/v1/organizations/upsert`). Пути определяются HTTP-аннотациями в `kacho-proto`. |
| OQ-3 | Имя request-id header | **`X-Request-ID`** (header HTTP/gRPC metadata). Генерируется как UUID v4 если отсутствует. |
| OQ-4 | Watch через REST (grpc-gateway streaming) | `Content-Type: application/json`, chunked transfer. Каждое сообщение — отдельная JSON-строка `{"result": {...}}` (newline-delimited JSON). |
| OQ-5 | Keepalive / idle timeout | **gRPC keepalive interval = 30s** на клиентских соединениях gateway→backend; **nginx `proxy_read_timeout = 120s`** (аннотация на Ingress). |
| OQ-6 | Backend connection pooling | **Один `*grpc.ClientConn` per backend**, инициализируется один раз в `cmd/api-gateway/main.go`. Никакого per-request dial. |

---

## §1. File map (`kacho-api-gateway` — единственный затронутый репо)

> `kacho-proto` не меняется в этой sub-phase (все HTTP-аннотации должны быть добавлены отдельным PR в kacho-proto до Phase D). Изменения в `kacho-deploy` — только umbrella и e2e.

```
kacho-api-gateway/
├── cmd/
│   └── api-gateway/
│       └── main.go                      — composition root (wiring)
├── internal/
│   ├── allowlist/
│   │   ├── list.go                      — Go-константа AllowedMethods + IsAllowed()
│   │   └── list_test.go
│   ├── proxy/
│   │   ├── director.go                  — StreamDirector: domain-routing + allowlist check
│   │   ├── server.go                    — grpc.Server с UnknownServiceHandler
│   │   └── director_test.go
│   ├── restmux/
│   │   ├── mux.go                       — runtime.NewServeMux + Register* всех 4 сервисов
│   │   └── mux_test.go
│   ├── middleware/
│   │   ├── request_id.go                — gRPC interceptor + HTTP middleware
│   │   ├── recovery.go                  — gRPC interceptor (panic → INTERNAL)
│   │   ├── access_log.go                — slog structured log (gRPC + HTTP)
│   │   ├── auth_noop.go                 — placeholder no-op auth interceptor
│   │   └── middleware_test.go
│   ├── health/
│   │   ├── handler.go                   — /healthz, /readyz + gRPC Health
│   │   └── handler_test.go
│   └── config/
│       └── config.go                    — envconfig структура
├── deploy/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       └── service.yaml
├── Dockerfile
├── Makefile
├── go.mod
├── go.sum
├── .gitignore
└── README.md
```

`kacho-deploy/` изменения:
```
kacho-deploy/
├── helm/umbrella/
│   ├── Chart.yaml                       — добавить api-gateway dependency
│   ├── values.dev.yaml                  — добавить api-gateway секцию + Ingress
│   └── templates/
│       └── ingress.yaml                 — (обновить) backend → api-gateway:8080
└── e2e/
    └── 0.6/
        ├── K1-grpc-instance-upsert.sh
        ├── K2-rest-instance-list.sh
        ├── K3-internal-blocked.sh
        ├── K4-full-smoke.sh
        └── K5-ingress-check.sh
```

---

## §2. Phase A — Skeleton (go.mod, deps, .gitignore, README)

**Acceptance scenarios:** служит фундаментом для всех групп.

### A.1 Инициализация репозитория

```
cd kacho-api-gateway
go mod init github.com/PRO-Robotech/kacho-api-gateway
```

### A.2 Зависимости `go.mod`

```go
require (
    // cmux — демультиплексирование TCP
    github.com/soheilhy/cmux v0.1.5

    // gRPC-proxy — прозрачный стриминг-proxy
    github.com/mwitkow/grpc-proxy v0.0.0-20230731113816-f1873b0b0b73

    // grpc-gateway — REST mux
    github.com/grpc-ecosystem/grpc-gateway/v2 v2.19.1

    // gRPC core
    google.golang.org/grpc v1.62.0
    google.golang.org/protobuf v1.33.0

    // proto-stubs (все 4 домена)
    github.com/PRO-Robotech/kacho-proto v0.6.0

    // UUID генерация
    github.com/google/uuid v1.6.0

    // Health protocol
    google.golang.org/grpc/health v1.0.0

    // Тесты
    github.com/stretchr/testify v1.9.0
    github.com/testcontainers/testcontainers-go v0.29.1
)
```

### A.3 .gitignore

Стандартный Go `.gitignore`: `*.exe`, `*.test`, `vendor/`, `bin/`, `dist/`, `.env`, `*.log`.

### A.4 README.md

Краткое описание сервиса. Обязательные секции:
- Пример `grpcurl`-команды через `api.kacho.local:80`
- Пример `curl` REST через `api.kacho.local/v1/`
- Описание allowlist: как добавить новый публичный метод в `internal/allowlist/list.go`
- Список env-переменных: `KACHO_RESOURCE_MANAGER_GRPC`, `KACHO_VPC_GRPC`, `KACHO_COMPUTE_GRPC`, `KACHO_LOADBALANCER_GRPC`
- Команды сборки и запуска

### A.5 Makefile

```makefile
.PHONY: build test lint

build:
	go build -o bin/api-gateway ./cmd/api-gateway

test:
	go test -race ./...

lint:
	golangci-lint run ./...
```

---

## §3. Phase B — Allowlist (`internal/allowlist/`)

**Acceptance scenarios:** D1–D5, E1–E14, E_Exists_canonical, E_HasDependents_canonical, E_UpdateStatus_canonical (26 сценариев)

### B.1 `internal/allowlist/list.go`

Allowlist — исчерпывающая Go-константа типа `map[string]struct{}`. Каждая строка — полный gRPC method path вида `/<package>.<Service>/<Method>`. Правило отбора: **все публичные сервисы каждого домена, но ни один `*InternalService.*`**.

**Публичные сервисы по доменам (источник — `kacho-proto/proto/.../v1/*.proto`):**

```
resourcemanager:
  /kacho.cloud.resourcemanager.v1.OrganizationService/Upsert
  /kacho.cloud.resourcemanager.v1.OrganizationService/Delete
  /kacho.cloud.resourcemanager.v1.OrganizationService/List
  /kacho.cloud.resourcemanager.v1.OrganizationService/Watch
  /kacho.cloud.resourcemanager.v1.CloudService/Upsert
  /kacho.cloud.resourcemanager.v1.CloudService/Delete
  /kacho.cloud.resourcemanager.v1.CloudService/List
  /kacho.cloud.resourcemanager.v1.CloudService/Watch
  /kacho.cloud.resourcemanager.v1.FolderService/Upsert
  /kacho.cloud.resourcemanager.v1.FolderService/Delete
  /kacho.cloud.resourcemanager.v1.FolderService/List
  /kacho.cloud.resourcemanager.v1.FolderService/Watch

vpc:
  /kacho.cloud.vpc.v1.NetworkService/Upsert
  /kacho.cloud.vpc.v1.NetworkService/Delete
  /kacho.cloud.vpc.v1.NetworkService/List
  /kacho.cloud.vpc.v1.NetworkService/Watch
  /kacho.cloud.vpc.v1.SubnetService/Upsert
  /kacho.cloud.vpc.v1.SubnetService/Delete
  /kacho.cloud.vpc.v1.SubnetService/List
  /kacho.cloud.vpc.v1.SubnetService/Watch
  /kacho.cloud.vpc.v1.SecurityGroupService/Upsert
  /kacho.cloud.vpc.v1.SecurityGroupService/Delete
  /kacho.cloud.vpc.v1.SecurityGroupService/List
  /kacho.cloud.vpc.v1.SecurityGroupService/Watch
  /kacho.cloud.vpc.v1.RouteTableService/Upsert
  /kacho.cloud.vpc.v1.RouteTableService/Delete
  /kacho.cloud.vpc.v1.RouteTableService/List
  /kacho.cloud.vpc.v1.RouteTableService/Watch
  /kacho.cloud.vpc.v1.AddressService/Upsert
  /kacho.cloud.vpc.v1.AddressService/Delete
  /kacho.cloud.vpc.v1.AddressService/List
  /kacho.cloud.vpc.v1.AddressService/Watch

compute:
  /kacho.cloud.compute.v1.InstanceService/Upsert
  /kacho.cloud.compute.v1.InstanceService/Delete
  /kacho.cloud.compute.v1.InstanceService/List
  /kacho.cloud.compute.v1.InstanceService/Watch
  /kacho.cloud.compute.v1.InstanceService/Restart
  /kacho.cloud.compute.v1.DiskService/Upsert
  /kacho.cloud.compute.v1.DiskService/Delete
  /kacho.cloud.compute.v1.DiskService/List
  /kacho.cloud.compute.v1.DiskService/Watch
  /kacho.cloud.compute.v1.ImageService/List
  /kacho.cloud.compute.v1.SnapshotService/Upsert
  /kacho.cloud.compute.v1.SnapshotService/Delete
  /kacho.cloud.compute.v1.SnapshotService/List
  /kacho.cloud.compute.v1.SnapshotService/Watch

loadbalancer:
  /kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Upsert
  /kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Delete
  /kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/List
  /kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService/Watch
  /kacho.cloud.loadbalancer.v1.TargetGroupService/Upsert
  /kacho.cloud.loadbalancer.v1.TargetGroupService/Delete
  /kacho.cloud.loadbalancer.v1.TargetGroupService/List
  /kacho.cloud.loadbalancer.v1.TargetGroupService/Watch
```

**Явно отсутствуют (полная матрица Internal-методов из acceptance §5):**

| Domain | Service | Methods |
|---|---|---|
| resourcemanager | `OrganizationInternalService` | `Exists`, `HasDependents` |
| resourcemanager | `CloudInternalService` | `Exists`, `HasDependents` |
| resourcemanager | `FolderInternalService` | `Exists`, `HasDependents` |
| vpc | `NetworkInternalService` | `Exists`, `HasDependents` |
| vpc | `SubnetInternalService` | `Exists`, `HasDependents` |
| vpc | `SecurityGroupInternalService` | `Exists`, `HasDependents` |
| vpc | `RouteTableInternalService` | `Exists`, `HasDependents` |
| vpc | `AddressInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
| compute | `InstanceInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
| compute | `DiskInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
| loadbalancer | `NetworkLoadBalancerInternalService` | `Exists`, `HasDependents`, `UpdateStatus` |
| loadbalancer | `TargetGroupInternalService` | `Exists`, `HasDependents`, `UpdateStatus`, `RemoveTarget` |

### B.2 Структура `list.go`

```go
package allowlist

// AllowedMethods — исчерпывающая карта публично доступных gRPC-методов.
// Все *InternalService.* намеренно отсутствуют (CLAUDE.md запрет #7).
var AllowedMethods = map[string]struct{}{
    // resourcemanager
    "/kacho.cloud.resourcemanager.v1.OrganizationService/Upsert": {},
    // ... (полный список как выше)
}

// IsAllowed возвращает true если fullMethod присутствует в allowlist.
// fullMethod — gRPC method path вида "/package.Service/Method".
func IsAllowed(fullMethod string) bool {
    _, ok := AllowedMethods[fullMethod]
    return ok
}
```

### B.3 Тесты `list_test.go`

- `TestAllowlist_PublicMethodsAllowed`: проверить по матрице что все публичные методы `IsAllowed(m) == true`
- `TestAllowlist_InternalMethodsBlocked`: проверить по матрице E_Exists_canonical + E_HasDependents_canonical + E_UpdateStatus_canonical + RemoveTarget что `IsAllowed(m) == false`
- `TestAllowlist_EmptyPathBlocked`: `IsAllowed("") == false`
- `TestAllowlist_MalformedPathBlocked`: `IsAllowed("//BadPath") == false`

---

## §4. Phase C — gRPC-proxy (`internal/proxy/`)

**Acceptance scenarios:** A1–A7, B1–B4, E1–E14 (gRPC-ветвь), J1–J7 (27 сценариев)

### C.1 `internal/proxy/director.go`

`StreamDirector` реализует `proxy.StreamDirector` интерфейс из `mwitkow/grpc-proxy`:

```go
package proxy

import (
    "context"
    "strings"

    "github.com/mwitkow/grpc-proxy/proxy"
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/metadata"
    "google.golang.org/grpc/status"

    "github.com/PRO-Robotech/kacho-api-gateway/internal/allowlist"
)

// Gateway хранит карту domain → *grpc.ClientConn + ссылку на allowlist.
type Gateway struct {
    // backends: "resourcemanager" → conn, "vpc" → conn, "compute" → conn, "loadbalancer" → conn
    backends map[string]*grpc.ClientConn
}

func New(backends map[string]*grpc.ClientConn) *Gateway {
    return &Gateway{backends: backends}
}

// Director — proxy.StreamDirector.
// Порядок проверок:
//  1. allowlist.IsAllowed — если нет → NOT_FOUND немедленно (backend не вызывается)
//  2. parseDomain — разбираем prefix "/kacho.cloud.<domain>.v1."
//  3. backends[domain] — если нет → UNAVAILABLE
//  4. propagate incoming metadata → outgoing context
func (g *Gateway) Director(
    ctx context.Context,
    fullMethod string,
) (context.Context, *grpc.ClientConn, error) {
    if !allowlist.IsAllowed(fullMethod) {
        return nil, nil, status.Errorf(
            codes.NotFound,
            "method not found: %s", fullMethod,
        )
    }
    domain, err := parseDomain(fullMethod)
    if err != nil {
        return nil, nil, status.Errorf(codes.NotFound, "cannot parse domain from method: %s", fullMethod)
    }
    conn, ok := g.backends[domain]
    if !ok {
        return nil, nil, status.Errorf(codes.Unavailable, "no backend for domain %s", domain)
    }
    // Пробрасываем входящие metadata без изменений
    md, _ := metadata.FromIncomingContext(ctx)
    outCtx := metadata.NewOutgoingContext(ctx, md.Copy())
    return outCtx, conn, nil
}

// parseDomain извлекает domain из gRPC-method-path.
// Формат: "/kacho.cloud.<domain>.v1.<Service>/<Method>"
// Пример: "/kacho.cloud.compute.v1.InstanceService/List" → "compute"
func parseDomain(fullMethod string) (string, error) {
    // Убираем ведущий "/" → "kacho.cloud.<domain>.v1.<Service>/<Method>"
    trimmed := strings.TrimPrefix(fullMethod, "/")
    parts := strings.Split(trimmed, ".")
    // Ожидаем: kacho . cloud . <domain> . v1 . <Service>/Method
    if len(parts) < 4 || parts[0] != "kacho" || parts[1] != "cloud" {
        return "", fmt.Errorf("unexpected method format: %s", fullMethod)
    }
    return parts[2], nil
}
```

### C.2 `internal/proxy/server.go`

```go
package proxy

import (
    "github.com/mwitkow/grpc-proxy/proxy"
    "google.golang.org/grpc"
    "google.golang.org/grpc/health"
    healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

// NewGRPCServer создаёт gRPC-сервер с UnknownServiceHandler для proxy.
// Все известные методы (Health.Check) регистрируются напрямую.
func NewGRPCServer(director *Gateway, interceptors ...grpc.UnaryServerInterceptor) *grpc.Server {
    srv := grpc.NewServer(
        grpc.UnknownServiceHandler(proxy.TransparentHandler(director.Director)),
        grpc.ChainUnaryInterceptor(interceptors...),
        grpc.ChainStreamInterceptor(
            // recovery + request-id — stream interceptors
        ),
    )
    // gRPC Health Check регистрируется напрямую (не через proxy)
    healthSrv := health.NewServer()
    healthSrv.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
    healthpb.RegisterHealthServer(srv, healthSrv)
    return srv
}
```

### C.3 Тесты `director_test.go`

- `TestGateway_A1_GrpcProxyForwardsToBackend`: mock compute-backend (gRPC server на случайном порту), Director маршрутизирует на него корректно
- `TestGateway_A5_UnknownDomainReturnsNotFound`: `kacho.cloud.unknown.v1.FooService/Bar` → `NOT_FOUND`
- `TestGateway_A6_MetadataPropagated`: входящая metadata `x-request-id: client-42` присутствует в outgoing context
- `TestGateway_E1_InternalServiceBlocked`: `FolderInternalService/Exists` → `NOT_FOUND` до вызова Director
- `TestGateway_E6_UpdateStatusBlocked`: `InstanceInternalService/UpdateStatus` → `NOT_FOUND`
- `TestGateway_J3_MalformedMethodPath`: `//BadPath` → `NOT_FOUND`

---

## §5. Phase D — REST mux (`internal/restmux/`)

**Acceptance scenarios:** C1–C9, E11–E14 (REST-ветвь), F6, G1–G4 (14 сценариев)

### D.1 `internal/restmux/mux.go`

grpc-gateway `runtime.ServeMux` регистрирует все **публичные** сервисы всех 4 доменов. `*InternalService.*` **не регистрируются вообще** — это обеспечивает автоматический HTTP 404 для соответствующих URL (сценарии E11–E14).

```go
package restmux

import (
    "context"
    "net/http"

    "github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
    "google.golang.org/grpc"

    // Импорт всех 4 доменов из kacho-proto gen
    resourcemanagerv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/resourcemanager/v1"
    vpcv1             "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1"
    computev1         "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/compute/v1"
    loadbalancerv1    "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/loadbalancer/v1"
)

// BackendEndpoints хранит адреса backend-ов для RegisterXxxServiceHandlerFromEndpoint.
type BackendEndpoints struct {
    ResourceManagerAddr string
    VPCAddr             string
    ComputeAddr         string
    LoadBalancerAddr    string
}

// New возвращает настроенный http.Handler (runtime.ServeMux) со всеми
// зарегистрированными публичными сервисами.
// Internal-сервисы намеренно НЕ регистрируются → автоматический 404.
func New(ctx context.Context, endpoints BackendEndpoints, dialOpts []grpc.DialOption) (http.Handler, error) {
    mux := runtime.NewServeMux()

    // resource-manager: Organization, Cloud, Folder
    if err := resourcemanagerv1.RegisterOrganizationServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ResourceManagerAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := resourcemanagerv1.RegisterCloudServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ResourceManagerAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := resourcemanagerv1.RegisterFolderServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ResourceManagerAddr, dialOpts,
    ); err != nil { return nil, err }

    // vpc: Network, Subnet, SecurityGroup, RouteTable, Address
    if err := vpcv1.RegisterNetworkServiceHandlerFromEndpoint(
        ctx, mux, endpoints.VPCAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := vpcv1.RegisterSubnetServiceHandlerFromEndpoint(
        ctx, mux, endpoints.VPCAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := vpcv1.RegisterSecurityGroupServiceHandlerFromEndpoint(
        ctx, mux, endpoints.VPCAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := vpcv1.RegisterRouteTableServiceHandlerFromEndpoint(
        ctx, mux, endpoints.VPCAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := vpcv1.RegisterAddressServiceHandlerFromEndpoint(
        ctx, mux, endpoints.VPCAddr, dialOpts,
    ); err != nil { return nil, err }

    // compute: Instance, Disk, Image, Snapshot
    if err := computev1.RegisterInstanceServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ComputeAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := computev1.RegisterDiskServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ComputeAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := computev1.RegisterImageServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ComputeAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := computev1.RegisterSnapshotServiceHandlerFromEndpoint(
        ctx, mux, endpoints.ComputeAddr, dialOpts,
    ); err != nil { return nil, err }

    // loadbalancer: NetworkLoadBalancer, TargetGroup
    if err := loadbalancerv1.RegisterNetworkLoadBalancerServiceHandlerFromEndpoint(
        ctx, mux, endpoints.LoadBalancerAddr, dialOpts,
    ); err != nil { return nil, err }
    if err := loadbalancerv1.RegisterTargetGroupServiceHandlerFromEndpoint(
        ctx, mux, endpoints.LoadBalancerAddr, dialOpts,
    ); err != nil { return nil, err }

    // NOTE: *InternalService НЕ регистрируются — автоматический 404

    return mux, nil
}
```

### D.2 Watch-стриминг через REST

grpc-gateway нативно конвертирует server-streaming RPC в chunked HTTP с newline-delimited JSON формата `{"result": {...}}`. Никакой дополнительной логики не требуется — работает из коробки. Клиенты должны читать ответ построчно.

### D.3 Defense-in-depth middleware для REST Internal-путей

Дополнительно к автоматическому 404 от отсутствия регистрации — HTTP-middleware, которое отклоняет любой URL, содержащий подстроку `internal` или `upd-status` в path, с явным 404. Это защита на случай если proto-аннотации когда-то добавят HTTP-путь для Internal-методов случайно.

```go
// internal/restmux/mux.go
func blockInternalPaths(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        p := strings.ToLower(r.URL.Path)
        if strings.Contains(p, "internal") || strings.Contains(p, "upd-status") {
            http.Error(w, `{"code":5,"message":"Not Found"}`, http.StatusNotFound)
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

### D.4 Тесты `mux_test.go`

- `TestGateway_C7_MalformedJSONReturns400`: невалидный JSON тело → HTTP 400
- `TestGateway_C8_UnknownPathReturns404`: `/v1/nonexistent/list` → HTTP 404
- `TestGateway_E11_InternalRESTBlocked`: `POST /v1/instances/upd-status` → HTTP 404
- `TestGateway_E12_FolderExistsRESTBlocked`: `POST /v1/folders/exists` → HTTP 404
- `TestGateway_E13_NetworkExistsRESTBlocked`: `POST /v1/networks/exists` → HTTP 404
- `TestGateway_E14_TargetGroupRemoveTargetRESTBlocked`: `POST /v1/target-groups/remove-target` → HTTP 404

---

## §6. Phase E — cmux split (`cmd/api-gateway/main.go` основной паттерн)

**Acceptance scenarios:** B1–B4 (4 сценария)

### E.1 Паттерн cmux

```go
// cmd/api-gateway/main.go (фрагмент)
import (
    "net"
    "github.com/soheilhy/cmux"
)

func serve(ctx context.Context, cfg *config.Config) error {
    lis, err := net.Listen("tcp", cfg.ListenAddr) // :8080
    if err != nil {
        return fmt.Errorf("listen: %w", err)
    }

    m := cmux.New(lis)

    // ВАЖНО: gRPC matcher должен идти ПЕРВЫМ
    // MatchWithWriters нужен для HTTP/2 (gRPC требует HTTP/2 SETTINGS frame)
    grpcL := m.MatchWithWriters(
        cmux.HTTP2MatchHeaderFieldSendSettings("content-type", "application/grpc"),
    )
    // HTTP/1.1 и h2c без content-type: application/grpc
    httpL := m.Match(cmux.Any())

    errCh := make(chan error, 3)

    go func() { errCh <- grpcServer.Serve(grpcL) }()
    go func() { errCh <- httpServer.Serve(httpL) }()
    go func() { errCh <- m.Serve() }()

    select {
    case err := <-errCh:
        return err
    case <-ctx.Done():
        grpcServer.GracefulStop()
        httpServer.Shutdown(ctx)
        return nil
    }
}
```

### E.2 Важные детали

- `cmux.HTTP2MatchHeaderFieldSendSettings` отправляет HTTP/2 SETTINGS frame при установке соединения, что необходимо для корректного h2c (HTTP/2 cleartext) gRPC без TLS.
- `cmux.Any()` для HTTP listener должен идти последним — он матчит всё, что не попало в предыдущие правила.
- Graceful shutdown: при получении SIGTERM сначала `grpcServer.GracefulStop()` (ждёт завершения streaming RPC), потом `httpServer.Shutdown(ctx)`.

---

## §7. Phase F — Middleware (`internal/middleware/`)

**Acceptance scenarios:** F1–F7 (7 сценариев)

### F.1 `internal/middleware/request_id.go`

Реализует и gRPC interceptor, и HTTP middleware (`net/http`).

**gRPC unary + stream interceptors:**
```go
// UnaryRequestID: извлекает x-request-id из incoming metadata;
// если отсутствует — генерирует uuid.New().String();
// добавляет в outgoing metadata.
func UnaryRequestID(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    ctx, _ = ensureRequestID(ctx)
    return handler(ctx, req)
}

func StreamRequestID(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
    ctx, _ := ensureRequestID(ss.Context())
    wrapped := &wrappedStream{ss, ctx}
    return handler(srv, wrapped)
}
```

**HTTP middleware:**
```go
func HTTPRequestID(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        rid := r.Header.Get("X-Request-ID")
        if rid == "" {
            rid = uuid.New().String()
        }
        r = r.WithContext(context.WithValue(r.Context(), requestIDKey, rid))
        w.Header().Set("X-Request-ID", rid)
        next.ServeHTTP(w, r)
    })
}
```

### F.2 `internal/middleware/recovery.go`

gRPC recovery interceptor (unary + stream). При panic:
1. Логирует `slog.Error("recovered from panic", "panic", p, "stack", string(debug.Stack()))`
2. Возвращает `status.Errorf(codes.Internal, "internal server error")`
3. Gateway продолжает работу

```go
func UnaryRecovery(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
    defer func() {
        if p := recover(); p != nil {
            slog.ErrorContext(ctx, "recovered from panic",
                "panic", p,
                "stack", string(debug.Stack()),
            )
            err = status.Errorf(codes.Internal, "internal server error")
        }
    }()
    return handler(ctx, req)
}
```

### F.3 `internal/middleware/access_log.go`

**gRPC interceptor** (unary + stream):

```go
// Формат: {"level":"INFO","ts":"...","msg":"access",
//           "method":"/kacho.cloud.compute.v1.InstanceService/Upsert",
//           "status":0,"duration_ms":12,"request_id":"..."}
func UnaryAccessLog(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    start := time.Now()
    resp, err := handler(ctx, req)
    code := status.Code(err)
    rid := requestIDFromContext(ctx)
    slog.InfoContext(ctx, "access",
        "method", info.FullMethod,
        "status", int(code),
        "duration_ms", time.Since(start).Milliseconds(),
        "request_id", rid,
    )
    return resp, err
}
```

**HTTP middleware** (для REST):

```go
// Формат: {"level":"INFO","ts":"...","msg":"access",
//           "method":"POST /v1/organizations/list",
//           "status":200,"duration_ms":5,"request_id":"..."}
func HTTPAccessLog(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rw := &responseWriter{ResponseWriter: w, code: http.StatusOK}
        next.ServeHTTP(rw, r)
        rid := requestIDFromHTTPContext(r.Context())
        slog.InfoContext(r.Context(), "access",
            "method", r.Method+" "+r.URL.Path,
            "status", rw.code,
            "duration_ms", time.Since(start).Milliseconds(),
            "request_id", rid,
        )
    })
}
```

### F.4 `internal/middleware/auth_noop.go`

Placeholder no-op. Логирует (опционально) `"auth":"no-op"` без блокировки. Место для AAA в фазе 1.

```go
func UnaryAuthNoop(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
    // no-op: запросы без auth-заголовков проходят насквозь (сценарий F7)
    return handler(ctx, req)
}
```

### F.5 Тесты `middleware_test.go`

- `TestGateway_F1_RequestIDPropagated`: клиент передаёт `x-request-id: test-req-001` → backend получает его
- `TestGateway_F2_RequestIDGenerated`: нет `x-request-id` в запросе → gateway генерирует UUID
- `TestGateway_F3_PanicRecovery`: инжекция panic → recovery interceptor → `INTERNAL` статус, gateway продолжает работу
- `TestGateway_F4_AccessLogFields`: проверка наличия обязательных полей access log
- `TestGateway_F5_AccessLogErrorStatus`: backend возвращает `INVALID_ARGUMENT` → access log `"status":3`
- `TestGateway_F6_RESTAccessLog`: REST-запрос → access log с `"method":"POST /v1/..."` и HTTP status
- `TestGateway_F7_AuthNoopPassthrough`: запрос без auth → `OK` (не блокируется)

---

## §8. Phase G — Health probes (`internal/health/`)

**Acceptance scenarios:** G1–G5 (5 сценариев)

### G.1 `internal/health/handler.go`

```go
package health

import (
    "context"
    "encoding/json"
    "net/http"
    "time"

    healthpb "google.golang.org/grpc/health/grpc_health_v1"
    "google.golang.org/grpc"
)

type Handler struct {
    backends map[string]*grpc.ClientConn // domain → conn
}

func New(backends map[string]*grpc.ClientConn) *Handler {
    return &Handler{backends: backends}
}

// Healthz — liveness probe. Не зависит от состояния backends.
// GET /healthz → 200, body: {"status":"ok"}
func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// Readyz — readiness probe.
// Проверяет grpc.health.v1.Health/Check для каждого backend.
// Если все SERVING → 200; если хоть один NOT_SERVING/недоступен → 503.
func (h *Handler) Readyz(w http.ResponseWriter, r *http.Request) {
    ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
    defer cancel()

    backends := make(map[string]string, len(h.backends))
    allOK := true
    for domain, conn := range h.backends {
        resp, err := healthpb.NewHealthClient(conn).Check(ctx,
            &healthpb.HealthCheckRequest{Service: ""},
        )
        if err != nil || resp.Status != healthpb.HealthCheckResponse_SERVING {
            backends[domain] = "NOT_SERVING"
            allOK = false
        } else {
            backends[domain] = "SERVING"
        }
    }

    status := "ok"
    httpStatus := http.StatusOK
    if !allOK {
        status = "NOT_SERVING"
        httpStatus = http.StatusServiceUnavailable
    }

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(httpStatus)
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status":   status,
        "backends": backends,
    })
}
```

### G.2 Регистрация маршрутов

Health-маршруты регистрируются на отдельном `http.ServeMux` (не на grpc-gateway mux), который оборачивается в цепочку middleware:

```go
healthMux := http.NewServeMux()
healthMux.HandleFunc("/healthz", healthHandler.Healthz)
healthMux.HandleFunc("/readyz", healthHandler.Readyz)
```

В итоговом HTTP handler: health-маршруты обрабатываются первыми, остальные — через grpc-gateway mux.

### G.3 gRPC Health endpoint

gRPC `Health.Check` регистрируется прямо на gRPC-сервере (Phase C.2). При проверке `/readyz` gateway использует свои backend-коннекты для вызова Health на каждом backend.

### G.4 Тесты `handler_test.go`

- `TestGateway_G1_HealthzAlwaysOK`: `/healthz` → 200 даже если backends недоступны
- `TestGateway_G2_ReadyzOKWhenAllServing`: все mock-backend SERVING → 200
- `TestGateway_G3_ReadyzFailsWhenOneDown`: один backend `NOT_SERVING` → 503 с деталями
- `TestGateway_G4_HealthzIndependentOfBackends`: backends недоступны → `/healthz` всё равно 200
- `TestGateway_G5_GRPCHealthCheckServing`: gRPC `Health/Check` → `SERVING`

---

## §9. Phase H — Composition root (`cmd/api-gateway/main.go`)

**Acceptance scenarios:** объединяет все компоненты; проверяется сквозными сценариями H1–H3, I1–I5, J1–J7.

### H.1 `internal/config/config.go`

```go
package config

import (
    "fmt"
    "os"
)

// Config загружается из переменных окружения.
// Все KACHO_*_GRPC обязательны.
type Config struct {
    ListenAddr          string // KACHO_LISTEN_ADDR, default: ":8080"
    ResourceManagerGRPC string // KACHO_RESOURCE_MANAGER_GRPC (обязательно)
    VPCAddr             string // KACHO_VPC_GRPC (обязательно)
    ComputeAddr         string // KACHO_COMPUTE_GRPC (обязательно)
    LoadBalancerAddr    string // KACHO_LOADBALANCER_GRPC (обязательно)
}

func Load() (*Config, error) {
    cfg := &Config{
        ListenAddr:          getEnv("KACHO_LISTEN_ADDR", ":8080"),
        ResourceManagerGRPC: os.Getenv("KACHO_RESOURCE_MANAGER_GRPC"),
        VPCAddr:             os.Getenv("KACHO_VPC_GRPC"),
        ComputeAddr:         os.Getenv("KACHO_COMPUTE_GRPC"),
        LoadBalancerAddr:    os.Getenv("KACHO_LOADBALANCER_GRPC"),
    }
    if cfg.ResourceManagerGRPC == "" || cfg.VPCAddr == "" ||
        cfg.ComputeAddr == "" || cfg.LoadBalancerAddr == "" {
        return nil, fmt.Errorf("all KACHO_*_GRPC env vars are required")
    }
    return cfg, nil
}
```

### H.2 `cmd/api-gateway/main.go` — полная структура

```go
package main

import (
    "context"
    "log/slog"
    "net"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/soheilhy/cmux"
    "google.golang.org/grpc"
    "google.golang.org/grpc/keepalive"

    "github.com/PRO-Robotech/kacho-api-gateway/internal/config"
    "github.com/PRO-Robotech/kacho-api-gateway/internal/health"
    "github.com/PRO-Robotech/kacho-api-gateway/internal/middleware"
    "github.com/PRO-Robotech/kacho-api-gateway/internal/proxy"
    "github.com/PRO-Robotech/kacho-api-gateway/internal/restmux"
)

func main() {
    slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

    cfg, err := config.Load()
    if err != nil {
        slog.Error("config load failed", "error", err)
        os.Exit(1)
    }

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
    defer stop()

    if err := run(ctx, cfg); err != nil {
        slog.Error("gateway error", "error", err)
        os.Exit(1)
    }
}

func run(ctx context.Context, cfg *config.Config) error {
    // 1. Dial backends — один *grpc.ClientConn per backend (OQ-6)
    //    keepalive interval = 30s (OQ-5)
    keepaliveParams := keepalive.ClientParameters{
        Time:                30 * time.Second,
        Timeout:             5 * time.Second,
        PermitWithoutStream: true,
    }
    dialOpts := []grpc.DialOption{
        grpc.WithInsecure(), // cleartext; TLS — фаза 1
        grpc.WithKeepaliveParams(keepaliveParams),
    }

    backends := map[string]*grpc.ClientConn{}
    for domain, addr := range map[string]string{
        "resourcemanager": cfg.ResourceManagerGRPC,
        "vpc":             cfg.VPCAddr,
        "compute":         cfg.ComputeAddr,
        "loadbalancer":    cfg.LoadBalancerAddr,
    } {
        conn, err := grpc.DialContext(ctx, addr, dialOpts...)
        if err != nil {
            return fmt.Errorf("dial %s (%s): %w", domain, addr, err)
        }
        backends[domain] = conn
        defer conn.Close()
    }

    // 2. Build gRPC proxy
    gateway := proxy.New(backends)
    grpcSrv := proxy.NewGRPCServer(gateway,
        middleware.UnaryRequestID,
        middleware.UnaryRecovery,
        middleware.UnaryAccessLog,
        middleware.UnaryAuthNoop,
    )

    // 3. Build REST mux
    restHandler, err := restmux.New(ctx, restmux.BackendEndpoints{
        ResourceManagerAddr: cfg.ResourceManagerGRPC,
        VPCAddr:             cfg.VPCAddr,
        ComputeAddr:         cfg.ComputeAddr,
        LoadBalancerAddr:    cfg.LoadBalancerAddr,
    }, dialOpts)
    if err != nil {
        return fmt.Errorf("build REST mux: %w", err)
    }

    // 4. Health handler
    healthHandler := health.New(backends)

    // 5. HTTP server: health routes + REST mux + middleware chain
    httpMux := http.NewServeMux()
    httpMux.HandleFunc("/healthz", healthHandler.Healthz)
    httpMux.HandleFunc("/readyz", healthHandler.Readyz)
    httpMux.Handle("/", restmux.BlockInternalPaths(restHandler))

    httpChain := middleware.HTTPRequestID(middleware.HTTPAccessLog(httpMux))
    httpSrv := &http.Server{Handler: httpChain}

    // 6. cmux split on :8080
    lis, err := net.Listen("tcp", cfg.ListenAddr)
    if err != nil {
        return fmt.Errorf("listen %s: %w", cfg.ListenAddr, err)
    }

    m := cmux.New(lis)
    grpcL := m.MatchWithWriters(
        cmux.HTTP2MatchHeaderFieldSendSettings("content-type", "application/grpc"),
    )
    httpL := m.Match(cmux.Any())

    slog.Info("api-gateway starting", "addr", cfg.ListenAddr)

    errCh := make(chan error, 3)
    go func() { errCh <- grpcSrv.Serve(grpcL) }()
    go func() { errCh <- httpSrv.Serve(httpL) }()
    go func() { errCh <- m.Serve() }()

    select {
    case err := <-errCh:
        return err
    case <-ctx.Done():
        slog.Info("shutting down")
        grpcSrv.GracefulStop()
        shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        return httpSrv.Shutdown(shutCtx)
    }
}
```

---

## §10. Phase I — Helm chart + Dockerfile

**Acceptance scenarios:** K5 (Ingress), L1 (код и структура).

### I.1 Dockerfile

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/api-gateway ./cmd/api-gateway

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /bin/api-gateway /api-gateway
EXPOSE 8080
ENTRYPOINT ["/api-gateway"]
```

### I.2 `deploy/Chart.yaml`

```yaml
apiVersion: v2
name: api-gateway
description: Kachō API Gateway — cmux + gRPC-proxy + grpc-gateway REST
type: application
version: 0.6.0
appVersion: "0.6.0"
```

### I.3 `deploy/values.yaml`

```yaml
replicaCount: 1
image:
  repository: prorobotech/kacho-api-gateway
  tag: "0.6.0"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

env:
  KACHO_LISTEN_ADDR: ":8080"
  KACHO_RESOURCE_MANAGER_GRPC: "resource-manager.kacho.svc.cluster.local:9090"
  KACHO_VPC_GRPC: "vpc.kacho.svc.cluster.local:9090"
  KACHO_COMPUTE_GRPC: "compute.kacho.svc.cluster.local:9090"
  KACHO_LOADBALANCER_GRPC: "loadbalancer.kacho.svc.cluster.local:9090"

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 256Mi

readinessProbe:
  httpGet:
    path: /readyz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 3
  periodSeconds: 15
```

### I.4 `deploy/templates/deployment.yaml`

Стандартный Deployment manifest по шаблону `03-deployment-and-operations.md` §6. Особенности:
- `containerPort: 8080` — единственный порт (cmux)
- Env-переменные из `values.yaml`
- Liveness/Readiness probes через `/healthz` и `/readyz` на порт 8080

### I.5 `deploy/templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: kacho
spec:
  selector:
    app: api-gateway
  ports:
    - name: http-grpc
      port: 8080
      targetPort: 8080
  type: ClusterIP
```

---

## §11. Phase J — Тесты (unit + integration)

**Acceptance scenarios:** все группы A–J (≥90% покрытие сценариев); L2.

### J.1 Стратегия тестирования

API Gateway не имеет базы данных → нет testcontainers-postgres. Вместо этого:
- **Unit-тесты** для allowlist, director, config, middleware — без внешних зависимостей.
- **Integration-тесты** с mock gRPC-серверами (стандартный `grpc.NewServer()` на случайном порту в тесте) для проверки end-to-end gateway routing.
- **Race detector**: все тесты запускаются с `go test -race ./...` (сценарий J5).

### J.2 Mock gRPC-бэкенд для integration-тестов

```go
// test/helpers/mock_backend.go
package helpers

import (
    "net"
    "testing"
    "google.golang.org/grpc"
    healthpb "google.golang.org/grpc/health/grpc_health_v1"
    "google.golang.org/grpc/health"
)

// StartMockBackend запускает минимальный gRPC-сервер с health endpoint
// на случайном порту. Возвращает адрес и функцию cleanup.
func StartMockBackend(t *testing.T, registerFn func(*grpc.Server)) string {
    t.Helper()
    lis, err := net.Listen("tcp", "127.0.0.1:0")
    if err != nil {
        t.Fatal(err)
    }
    srv := grpc.NewServer()
    healthSrv := health.NewServer()
    healthSrv.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
    healthpb.RegisterHealthServer(srv, healthSrv)
    if registerFn != nil {
        registerFn(srv)
    }
    go srv.Serve(lis)
    t.Cleanup(srv.Stop)
    return lis.Addr().String()
}
```

### J.3 Ключевые integration-тесты

| Test function | Сценарий | Описание |
|---|---|---|
| `TestGateway_A1_GrpcProxyForwardsToBackend` | A1 | gRPC-запрос на compute → proxy направляет на mock compute backend |
| `TestGateway_A2_ResourceManagerRouting` | A2 | resource-manager domain routing |
| `TestGateway_A3_VPCRouting` | A3 | vpc domain routing |
| `TestGateway_A4_LoadBalancerRouting` | A4 | loadbalancer domain routing |
| `TestGateway_A5_UnknownDomainNotFound` | A5 | несуществующий domain → NOT_FOUND |
| `TestGateway_A6_MetadataPropagated` | A6 | x-request-id propagated downstream |
| `TestGateway_A7_WatchStreamingProxy` | A7 | server-streaming Watch через proxy |
| `TestGateway_B1_GRPCRequestGoesToGRPCListener` | B1 | cmux: content-type application/grpc → gRPC listener |
| `TestGateway_B2_RESTRequestGoesToHTTPListener` | B2 | cmux: HTTP/1.1 POST → HTTP listener |
| `TestGateway_B3_ConcurrentGRPCAndREST` | B3 | одновременные gRPC + REST без блокировок |
| `TestGateway_B4_H2CCleartext` | B4 | gRPC без TLS (h2c) |
| `TestGateway_E1_FolderInternalBlocked` | E1 | FolderInternalService/Exists → NOT_FOUND |
| `TestGateway_E_ExistsCanonical_AllBlocked` | E_Exists | матрица 12 Exists-методов → все NOT_FOUND |
| `TestGateway_E_HasDependentsCanonical_AllBlocked` | E_HasDependents | матрица 12 HasDependents → все NOT_FOUND |
| `TestGateway_E_UpdateStatusCanonical_AllBlocked` | E_UpdateStatus | матрица 5 UpdateStatus → все NOT_FOUND |
| `TestGateway_G1_HealthzAlwaysOK` | G1 | /healthz всегда 200 |
| `TestGateway_G2_ReadyzOKWhenAllServing` | G2 | /readyz 200 когда все SERVING |
| `TestGateway_G3_ReadyzFailsWhenOneDown` | G3 | /readyz 503 если backend недоступен |
| `TestGateway_J1_BackendUnavailableReturnsUnavailable` | J1 | backend упал → UNAVAILABLE (код 14) |
| `TestGateway_J2_BackendUnavailableRESTReturns503` | J2 | backend упал → REST 503 |
| `TestGateway_J4_DeadlineExceeded` | J4 | deadline в запросе → DEADLINE_EXCEEDED |
| `TestGateway_J5_ConcurrentRaceDetector` | J5 | 50 горутин → нет data race |
| `TestGateway_J6_ClientDisconnectCleansUp` | J6 | клиент закрыл соединение → goroutine не течёт |
| `TestGateway_J7_OutOfRangePassthrough` | J7 | backend OUT_OF_RANGE → proxy не меняет код |

---

## §12. Phase K — kacho-deploy umbrella update

**Acceptance scenarios:** K1–K5 (5 сценариев), L3.

### K.1 `helm/umbrella/Chart.yaml` — добавить api-gateway dependency

```yaml
dependencies:
  # ... существующие зависимости ...
  - name: api-gateway
    repository: "file://../../kacho-api-gateway/deploy"
    version: "0.6.0"
    alias: api-gateway
```

### K.2 `helm/umbrella/values.dev.yaml` — добавить секцию api-gateway

```yaml
api-gateway:
  replicaCount: 1
  image:
    repository: prorobotech/kacho-api-gateway
    tag: "0.6.0"
  env:
    KACHO_RESOURCE_MANAGER_GRPC: "resource-manager.kacho.svc.cluster.local:9090"
    KACHO_VPC_GRPC: "vpc.kacho.svc.cluster.local:9090"
    KACHO_COMPUTE_GRPC: "compute.kacho.svc.cluster.local:9090"
    KACHO_LOADBALANCER_GRPC: "loadbalancer.kacho.svc.cluster.local:9090"
```

### K.3 Обновление Ingress

Ingress-ресурс в `kacho-deploy/helm/umbrella/templates/ingress.yaml` обновить:
- `backend.service.name: api-gateway`
- `backend.service.port.number: 8080`
- Аннотации:
  ```yaml
  nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
  nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  ```
  > Примечание: для поддержки и gRPC, и HTTP/1.1 на одном ingress-правиле — настраивать `backend-protocol: "GRPC"` только если ingress-nginx поддерживает h2c backend. В dev-окружении с kind рекомендуется проверить совместимость cmux + nginx; при необходимости использовать два отдельных Ingress-ресурса (один для gRPC, второй для REST).

### K.4 e2e bash-скрипты в `kacho-deploy/e2e/0.6/`

Каждый скрипт — самодостаточный, запускается против живого kind-кластера. Структура:
- Проверка переменных окружения (API_HOST по умолчанию `api.kacho.local`)
- Вызов через `grpcurl` или `curl`
- Проверка кода выхода и содержимого ответа через `jq`
- Выход с кодом 0 (успех) или 1 (ошибка)

**K1-grpc-instance-upsert.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail
API_HOST="${API_HOST:-api.kacho.local:80}"
FOLDER_UID="${FOLDER_UID:?FOLDER_UID is required}"
DISK_UID="${DISK_UID:?DISK_UID is required}"
SUBNET_UID="${SUBNET_UID:?SUBNET_UID is required}"

RESP=$(grpcurl -plaintext "$API_HOST" \
  kacho.cloud.compute.v1.InstanceService/Upsert \
  -d "{\"instances\":[{\"metadata\":{\"name\":\"smoke-vm-01\",\"folderId\":\"$FOLDER_UID\"},\"spec\":{\"platformId\":\"standard-v3\",\"zoneId\":\"kacho-zone-a\",\"resources\":{\"cores\":2,\"memory\":\"4Gi\"},\"bootDisk\":{\"diskId\":\"$DISK_UID\"},\"networkInterfaces\":[{\"subnetId\":\"$SUBNET_UID\"}],\"desiredPowerState\":\"RUNNING\"}}]}")
echo "$RESP" | jq -e '.instances[0].metadata.uid != ""'
echo "K1 PASSED"
```

**K3-internal-blocked.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail
API_HOST="${API_HOST:-api.kacho.local:80}"

# Попытка вызвать Internal-метод должна вернуть NOT_FOUND (код 5)
if grpcurl -plaintext "$API_HOST" \
  kacho.cloud.compute.v1.InstanceInternalService/UpdateStatus \
  -d '{"uid":"any-uid","status":{"state":"RUNNING"}}' 2>&1 | grep -q "NotFound"; then
  echo "K3 PASSED: Internal method correctly blocked"
else
  echo "K3 FAILED: Internal method was NOT blocked"
  exit 1
fi
```

**K4-full-smoke.sh:** последовательный прогон 7 команд (OrganizationService/List → NetworkService/Upsert → SubnetService/Upsert → InstanceService/Upsert → TargetGroupService/Upsert → NetworkLoadBalancerService/Upsert → InstanceService/List). Каждая команда проверяется через `jq`.

---

## §13. Phase L — Smoke + tag v0.6.0

**Acceptance scenarios:** K1–K5, L1–L6.

### L.1 Smoke checklist

1. `cd kacho-deploy && make dev-up` — поднять полный kind-кластер (все 5 сервисов включая api-gateway)
2. Проверить pods: `kubectl get pods -n kacho` — все `Running/Ready`
3. Проверить Ingress: `kubectl get ingress -n kacho` — backend `api-gateway`, ADDRESS не пустой
4. Запустить e2e/0.6/K4-full-smoke.sh
5. Проверить блокировку Internal: e2e/0.6/K3-internal-blocked.sh
6. Проверить /healthz и /readyz:
   ```bash
   curl -s http://api.kacho.local/healthz   # → {"status":"ok"}
   curl -s http://api.kacho.local/readyz    # → {"status":"ok","backends":{...}}
   ```
7. `make dev-down` — чистка

### L.2 CHANGELOG

Добавить запись в `kacho-workspace/docs/specs/CHANGELOG.md`:
```markdown
## [0.6.0] — 2026-05-XX — Sub-phase 0.6 API Gateway завершена

### Added
- kacho-api-gateway: cmux + mwitkow/grpc-proxy + grpc-gateway REST на порту 8080
- Allowlist: все *InternalService.* методы заблокированы (NOT_FOUND / 404)
- Middleware: X-Request-ID, recovery, slog access log, auth no-op placeholder
- Health probes: /healthz (liveness), /readyz (readiness + backend checks)
- Ingress в kacho-deploy привязан к api-gateway:8080
- e2e/0.6/*.sh bash-сценарии (K1–K5)
```

### L.3 Tag

```bash
git -C kacho-workspace tag v0.6.0
git -C kacho-api-gateway tag kacho-api-gateway/0.6.0
```

---

## §14. Definition of Done

1. ✅ Все 59 acceptance-сценариев группы A–L покрыты: integration-тестом (A–J) или e2e-bash (K) или структурной проверкой (L)
2. ✅ `kacho-api-gateway` содержит полный file map из §1: `cmd/`, `internal/{allowlist,proxy,restmux,middleware,health,config}/`, `deploy/`, `Dockerfile`, `Makefile`, `go.mod`
3. ✅ Allowlist: все публичные методы присутствуют; все `*InternalService.*` отсутствуют; покрыто тестами матрицы E_*_canonical
4. ✅ cmux: единственный порт 8080; gRPC и REST обрабатываются независимо без конфликтов
5. ✅ gRPC-proxy: прозрачный forwarding metadata; server-streaming Watch работает; domain routing по prefix `kacho.cloud.<domain>.v1`
6. ✅ REST mux: все 4 домена зарегистрированы; `*InternalService.*` не зарегистрированы → автоматический 404
7. ✅ Middleware: X-Request-ID propagated/generated; recovery перехватывает panic; slog access log с обязательными полями; auth no-op
8. ✅ Health: `/healthz` всегда 200; `/readyz` 200/503 в зависимости от backends; gRPC `Health/Check` отвечает `SERVING`
9. ✅ Один `*grpc.ClientConn` per backend; keepalive 30s; никакого per-request dial
10. ✅ `go test -race ./...` завершается с кодом 0; coverage acceptance-сценариев ≥ 90% (A–J)
11. ✅ Helm chart собирается; `helm lint` зелёный; `deploy/` содержит Chart.yaml, values.yaml, templates/
12. ✅ kacho-deploy umbrella обновлён: api-gateway dependency, Ingress backend, аннотация `proxy-read-timeout: "120"`
13. ✅ e2e/0.6/*.sh созданы и зелёные против живого kind-кластера
14. ✅ CHANGELOG обновлён записью о завершении sub-phase 0.6
15. ✅ Tag `v0.6.0` поставлен в kacho-workspace; `kacho-api-gateway/0.6.0` в kacho-api-gateway

---

## §15. Execution mode

Пользователь дал автономию до готового блока. Цепочка субагентов:

1. **Этот план** — skeleton и контракт для исполнения
2. **Phase A subagent** — skeleton: go.mod, .gitignore, README, Makefile; директории `cmd/`, `internal/`
3. **Phase B subagent** — `internal/allowlist/`: list.go (полная карта) + list_test.go (матрица E_*_canonical)
4. **Phase C subagent** — `internal/proxy/`: director.go + server.go + director_test.go (mock backends)
5. **Phase D subagent** — `internal/restmux/`: mux.go (все 4 домена) + mux_test.go (404 для Internal, 400 для malformed JSON)
6. **Phase E** — cmux wiring в `cmd/api-gateway/main.go` (фрагмент); связывание с Phase C+D
7. **Phase F subagent** — `internal/middleware/`: request_id + recovery + access_log + auth_noop + middleware_test.go
8. **Phase G subagent** — `internal/health/`: handler.go + handler_test.go
9. **Phase H subagent** — финальный `cmd/api-gateway/main.go` (composition root): wiring всех компонентов
10. **Phase I subagent** — `deploy/` (Helm chart) + `Dockerfile`
11. **Phase J** — верификация тестов: `go test -race ./...` зелёный
12. **Phase K subagent** — kacho-deploy: umbrella Chart.yaml, values.dev.yaml, Ingress, e2e/0.6/*.sh
13. **Phase L myself** — smoke run (`make dev-up` + e2e/0.6/K4-full-smoke.sh + `make dev-down`), CHANGELOG, tag

**Параллелизм:** Phase B (allowlist) и Phase A (skeleton) независимы и могут идти параллельно. Phase C (proxy) зависит от B (allowlist), но не от D (REST mux). Phase C и Phase D параллельны. Phase F (middleware) не зависит от C/D — параллельна с обоими. Phase G (health) независима — параллельна с C/D/F. Phase H (composition root) блокируется всеми предыдущими (A–G). Phase I (Helm/Docker) независима от H — параллельна. Phase K (kacho-deploy) зависит от I.

После Phase L → стоп → отчёт пользователю → пользователь делает `grpcurl`-проверку и approves smoke.
