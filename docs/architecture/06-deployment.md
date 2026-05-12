# 06 — Deployment (dev)

Только dev-стенд через kind+helm. Production-deployment не описан (нужен
`yc` provider или подобное; out of scope текущего спринта).

## kind cluster

`kacho-deploy/kind/kind-config.yaml` — single-node, port `28080`
переадресован на ingress-nginx. Cluster name: `kacho`.

```yaml
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 28080
        protocol: TCP
```

(Hostport был 80 → 28080 потому что 80 на dev-машине занят.)

## Helm umbrella

`kacho-deploy/helm/kacho-umbrella/` — wrapper-chart с зависимостями:

```
kacho-umbrella
├── ingress-nginx           edge для UI (cluster-local через 28080)
├── pg-resource-manager     postgres-operator или bitnami chart
├── pg-vpc                  postgres-operator или bitnami chart
└── netbox (legacy)         не используется (исторически — до встроенного IPAM)
```

Сервисы Kachō (resource-manager, vpc, api-gateway, ui) — отдельные
deployment'ы внутри umbrella. Каждый имеет:
- Init container `migrate up` — прокатывает миграции из `internal/migrations/`
  через `goose`-style (embedded `embed.FS`).
- Liveness/readiness — `/healthz` `/readyz`.
- ConfigMap с env-переменными.

## Команды (`kacho-deploy/Makefile`)

```bash
# Полный поднять стенд (kind create + helm install + ждать ready)
make dev-up

# Снести
make dev-down

# Перезалить один сервис: docker build → kind load → kubectl rollout restart
make reload-svc SVC=vpc
make reload-svc SVC=api-gateway
make reload-svc SVC=resource-manager
# UI вне whitelist, билдится вручную:
cd ../kacho-ui && make docker && \
  kind load docker-image kacho-ui:dev --name kacho && \
  kubectl rollout restart -n kacho deployment/ui

# Логи
make logs-svc SVC=vpc

# psql сервиса
make psql SVC=vpc   # → exec в pg-vpc-0 как user `vpc` в db `kacho_vpc`

# E2E
make e2e-test       # → newman через kacho-test
```

## Port-forward для локального доступа

```bash
# Public REST (для UI, kacho-tui, curl)
kubectl -n kacho port-forward svc/api-gateway 18080:8080

# UI prebuilt static
kubectl -n kacho port-forward svc/ui 18000:8080

# vpc internal gRPC (для kachoctl-ipam)
kubectl -n kacho port-forward svc/vpc 19091:9091

# Postgres (psql напрямую)
kubectl -n kacho port-forward statefulset/kacho-umbrella-pg-vpc 15432:5432
```

## Миграции

Каждый сервис — отдельная цепочка (per-service DB).

`kacho-vpc/internal/migrations/`:
```
0001_operations.sql              ← copy from corelib (sync через make sync-migrations)
0002_networks.sql
0003_subnets.sql
0004_addresses.sql
0005_route_tables.sql
0006_addresses_subnet_fk.sql     ← computed-column internal_subnet_id для UNIQUE
0007_subnets_cidr_exclude.sql    ← EXCLUDE USING gist для CIDR overlap
0008_security_groups.sql
0009_id_format_to_text.sql       ← UUID → TEXT
0010_vpc_outbox.sql
0011_gateways.sql
0012_private_endpoints.sql
0014_addresses_external_pool_id.sql  ← нумерация прыгает (0013 был removed)
0015_address_pools.sql               ← AddressPool + bindings
0016_address_pool_selectors.sql      ← добавил selector_labels (был network_pool_selector)
0017_addresses_external_ip_uniq_skip_empty.sql
0018_networks_folder_name_unique.sql
0019_regions_zones.sql               ← Region + Zone first-class + seed ru-central1
0020_address_pools_zone.sql          ← region_id (TEXT) → zone_id FK
0021_address_pools_drop_folder.sql   ← AddressPool становится глобальным
0022_pool_selector_to_cloud.sql      ← drop network_pool_selector + add cloud_pool_selector + UNIQUE(region_id, name) для zones
```

Запреты:
- НЕ редактировать применённую миграцию. Только новая.
- НЕ изменять `0001_operations.sql` локально — синхронизируется из corelib.
- `make sync-migrations` копирует общие миграции из corelib → каждый сервис.

## Network/CIDR layout (dev)

| Что | CIDR | Где |
|---|---|---|
| Subnet client default | `10.0.0.0/24` (test-данные) | через `Subnet.Create` |
| AddressPool default zone-a | `198.51.100.0/24` (TEST-NET-2) | seed через kachoctl |
| AddressPool premium | `203.0.113.0/30` (TEST-NET-3) | demo selector |
| AddressPool global zone-b | `203.0.113.0/24` | через kachoctl |

Используем RFC 5737 TEST-NET ranges чтобы не пересекаться с реальным интернетом.

## Sync репо (для локальной разработки)

`kacho-workspace/sync-all.sh` — обходит `project/*` и делает `git pull --ff-only`.

`kacho-workspace/bootstrap.sh` — клонирует все sibling-репо в `project/` (если
ещё нет).

## Что убирать перед прогоном newman

`kacho-deploy/Makefile`:
```bash
make seed-ipam   # NOOP сейчас. См. README — admin должен явно создать pool.
```

Перед прогоном master collection — нужны admin-pool'ы (иначе external Address
allocate упадёт). Минимум:

```bash
PF_INT=19091
kubectl -n kacho port-forward svc/vpc $PF_INT:9091 &
cd ../kacho-vpc && ./bin/kachoctl-ipam pool create \
  --kind EXTERNAL_PUBLIC \
  --zone-id ru-central1-a \
  --cidr 198.51.100.0/24 \
  --is-default \
  --name newman-default
```
