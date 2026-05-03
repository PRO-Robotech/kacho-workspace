# Kachō Cloud Control Plane — Обзор и Scope

**Документ:** 00 / 5
**Дата:** 2026-05-03
**Статус:** Draft, для ревью

## 1. Что это

Kachō — облачная управляющая платформа (control plane) с декларативным API в стиле Kubernetes/SGroups. Воспроизводит подмножество доменов Yandex Cloud (поля и семантика ресурсов) в Kubernetes-style envelope (`metadata` + `spec` + `status`).

**Только control plane.** Никаких реальных гипервизоров, SDN, dataplane-агентов. Lifecycle ресурсов с симулированными переходами состояний (PROVISIONING → RUNNING) — через server-side reconciler с искусственными задержками.

## 2. Цели

1. **Декларативный API**, симметричный современным K8s-style cloud control planes (Crossplane, ACK, GCP Config Connector). Единый паттерн для всех ресурсов: `upsert`/`delete`/`list`/`watch` + sub-resource updates.
2. **Состав полей** ресурсов — берём из Yandex Cloud для familiar-домена (Compute, VPC, Load Balancer): `cores`, `memory`, `networkInterfaces`, `bootDisk`, и т. д.
3. **Иерархия**: Organization → Cloud → Folder, как в YC. Без k8s-namespace.
4. **Масштабируемость**: архитектура с расчётом на миллионы ресурсов (Postgres Outbox + in-process Watch Hub, Kine-style).
5. **Open для будущего расширения**: AAA (IAM/mTLS/audit), observability stack, дополнительные домены (Object Storage, Managed DBs) — вне scope текущей фазы, но архитектурные точки для расширения зарезервированы.

## 3. Non-goals (явно вне scope)

- **Реальный data plane**: гипервизоры, VXLAN, eBPF, BGP, dataplane-агенты.
- **AAA**: IAM, federation, RBAC, mTLS, audit-сервис.
- **TLS на edge**: сейчас HTTP-only. TLS добавляется одной фазой с AAA.
- **Совместимость с Yandex Cloud Terraform-провайдером и Yandex Cloud Go SDK**: полностью отброшено. K8s-style envelope (`metadata`/`spec`) несовместим с YC-flat-структурой proto. Будем использовать собственные клиентские инструменты.
- **Биллинг, квоты, monitoring, console UI, DNS, Object Storage, Managed Databases, Functions, Container Registry** — отдельные домены, отдельные фазы.
- **Multi-region active-active, multi-cluster federation** — single region в текущей фазе.
- **Message broker (Kafka/NATS)** — заменён локальной outbox+in-process-hub архитектурой.

## 4. Принципы дизайна

1. **Declarative > Imperative.** Желаемое состояние в `spec`, наблюдаемое в `status`, контрольные сигналы в `metadata`. Reconciler сходится к декларации.
2. **Single source of truth.** Postgres — primary store; outbox — журнал событий; in-process hub — fan-out. Никаких dual-write race conditions.
3. **Service autonomy.** Database-per-service, polyrepo, каждое репо самодостаточно (склонировал — собрал).
4. **Standard envelope.** `metadata` / `spec` / `status` / `refs` единообразны для всех ресурсов.
5. **Generic API surface.** 4 стандартных RPC (`upsert`/`delete`/`list`/`watch`) на каждый ресурс + узкий набор sub-resource (`upd-status`, тонкие imperative-RPC для discrete-триггеров).
6. **K8s-conventional control signals.** `metadata.deletionTimestamp`, `metadata.finalizers[]`, `metadata.generation`, `metadata.restartedAt` — те же роли, что в Kubernetes.
7. **Future-proof scaling path.** Architecture даёт линейный рост через replicas; точка перехода на внешний broker и distributed DB чётко определена и не ломает API.

## 5. Сервисы текущей фазы (5)

| Сервис | Ресурсы | Postgres БД |
|---|---|---|
| `kacho-api-gateway` | — (edge proxy) | — |
| `kacho-resource-manager` | Organization, Cloud, Folder | `kacho_resource_manager` |
| `kacho-vpc` | Network, Subnet, SecurityGroup, RouteTable, Address | `kacho_vpc` |
| `kacho-compute` | Instance, Disk, Image (read-only catalog), Snapshot | `kacho_compute` |
| `kacho-loadbalancer` | NetworkLoadBalancer, TargetGroup | `kacho_loadbalancer` |

## 6. Бренд и naming

- Бренд: **Kachō** (макрон над `ō`).
- ASCII в технических идентификаторах: **`kacho`**.
- Proto package: **`kacho.cloud.<domain>.v1`** (например, `kacho.cloud.compute.v1`).
- Имена репо: **`kacho-<part>`** с дефисом.
- k8s namespace: **`kacho`**.
- Postgres-схемы: **`kacho_<domain>`** с подчёркиванием.

Полная таблица naming convention — в `02-data-model-and-conventions.md`.

## 7. Стек

- **Язык**: Go 1.22+.
- **API**: gRPC + grpc-gateway (REST-фасад).
- **Proto**: buf (lint, breaking-change detection, code generation).
- **БД**: Postgres 16, `pgx/v5`, `sqlc` для типизированных запросов, `goose` для миграций.
- **Watch**: Postgres outbox + in-process Watch Hub (Kine-inspired) с Postgres `LISTEN/NOTIFY` как wake-up signal.
- **Логи / metrics / tracing**: `slog`, OpenTelemetry SDK.
- **Контейнеризация и orchestration**: Docker, Helm, kind.
- **Тесты**: `testing` + `testify` + `testcontainers-go` для интеграционных.

## 8. Дорожная карта

**Текущая фаза (Bootstrap)** разбита на 7 sub-итераций (0.1–0.7). Каждая sub-итерация получает свой план реализации (см. `04-roadmap-and-phasing.md`).

**Будущие фазы** (порядок приоритета):

1. AAA — IAM, mTLS, audit, RBAC.
2. Observability — Loki, Grafana, Tempo, Prometheus.
3. HA / Production — Postgres replication, multi-replica services, External Secrets, real ingress.
4. Расширение доменов — DNS, Object Storage, Managed DBs, и далее.

## 9. Дальнейшее чтение

- **Архитектура и сервисы** — `01-architecture-and-services.md`
- **Модель данных и конвенции** — `02-data-model-and-conventions.md`
- **Развёртывание и эксплуатация** — `03-deployment-and-operations.md`
- **Дорожная карта и фазирование** — `04-roadmap-and-phasing.md`
