# Kachō — Workspace CLAUDE.md

Этот файл загружается Claude Code при работе из любой подпапки `cloud-demo/`.

## Что это за проект

Kachō — облачная управляющая платформа (control plane) с декларативным API в стиле Kubernetes. Воспроизводит подмножество доменов Yandex Cloud в K8s-style envelope (`metadata`/`spec`/`status`). Только control plane, никакого реального data plane.

Полная спека: `kacho-workspace/docs/specs/00-overview-and-scope.md` и далее.

## Naming convention (обязательно)

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** |
| Технические идентификаторы (ASCII) | `kacho` |
| Proto package | `kacho.cloud.<domain>.v1` |
| Имена репо | `kacho-<part>` (с дефисом) |
| k8s namespace | `kacho` |
| Postgres database / schema | `kacho_<domain>` (с подчёркиванием) |
| Env-переменные | `KACHO_<DOMAIN>_<NAME>` |

## Структура репозиториев (polyrepo)

Все репо живут как siblings в `cloud-demo/`:

| Репо | Роль |
|---|---|
| `kacho-workspace` | этот репо: CLAUDE.md, агенты, спеки, bootstrap-скрипты |
| **`kacho-proto`** | **единая центральная директория для всех `.proto`-определений Kachō** (от всех бекендов, всех доменов). Структура: `proto/kacho/cloud/<domain>/v1/*.proto`. Сгенерированные Go-stubs commit-ятся в `gen/go/...`. Импорт сервисов: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/<domain>/v1` |
| `kacho-corelib` | переиспользуемые Go-пакеты (см. ниже) |
| `kacho-api-gateway` | edge: gRPC-proxy + grpc-gateway REST (sub-phase 0.6) |
| `kacho-resource-manager` | Organization / Cloud / Folder (sub-phase 0.2) |
| `kacho-vpc` | Network / Subnet / SecurityGroup / RouteTable / Address (sub-phase 0.3) |
| `kacho-compute` | Instance / Disk / Image / Snapshot (sub-phase 0.4) |
| `kacho-loadbalancer` | NLB / TargetGroup (sub-phase 0.5) |
| `kacho-deploy` | kind + Helm + Postgres-charts, e2e-сценарии |

**Куда складывать новый `.proto`:** ВСЕГДА в `kacho-proto/proto/kacho/cloud/<domain>/v1/`. Сервисные репо НЕ содержат `.proto`-файлов — только Go-импорт сгенерированных stubs из `kacho-proto`. Это упрощает breaking-change detection (один `buf breaking` на всё), синхронизацию версий между сервисами и подключение клиентских SDK.

## Принцип переиспользования через `kacho-corelib`

**Всё, что может быть вынесено в общий компонент для переиспользования в нескольких сервисах — выносится в `kacho-corelib/<package>/`.**

В `kacho-corelib` живут:

- `ids/`, `errors/`, `config/`, `observability/`, `db/` (pgx pool + transactor), `grpcsrv/` (server bootstrap), `grpcclient/` (client factory) — sub-phase 0.1.
- `watch/`, `outbox/`, `selector/` — sub-phase 0.2.
- `migrations/common/` — общие миграции (`resource_events`, `resource_version_seq`, cleanup-функция); синхронизируются в каждое сервисное репо через `make sync-migrations`.
- `audit/` — `AuditLogger` (no-op в текущей фазе, скелет под AAA).

**Перед написанием новой утилиты в сервисном репо** — проверь, есть ли уже подходящий пакет в `kacho-corelib`. Если нет, но логика **будет нужна 2+ сервисам** — оформляй сразу в `kacho-corelib`, не дублируй per-service.

**Исключение:** бизнес-логика конкретного домена (Compute reconciler, VPC ref-validation, NLB target-deregister finalizer) живёт в сервисном репо. В corelib — только горизонтальные cross-cutting concerns.

## Запреты (обязательно соблюдать)

1. **НЕ начинать кодирование** до утверждения acceptance-документа Given-When-Then в `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`. См. `04-roadmap-and-phasing.md` §2.
2. **НЕ упоминать «yandex»** в handwritten-коде, README, комментариях, env-name, именах функций.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая миграция.
6. **НЕ писать в `status` через `/upsert` handler;** только через `/upd-status` (internal).
7. **НЕ маршрутизировать `Internal.*` методы** через api-gateway наружу.
8. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process Watch Hub справляется.
9. **НЕ создавать новые единые БД** — только database-per-service.

## Локальная разработка (быстрые команды)

- Развернуть стенд: `cd kacho-deploy && make dev-up`
- Снести стенд: `cd kacho-deploy && make dev-down`
- Перезапустить один сервис: `cd kacho-deploy && make reload-svc SVC=compute`
- Логи сервиса: `make logs-svc SVC=compute`
- Открыть psql сервиса: `make psql SVC=compute`
- Обновить все репо: `./kacho-workspace/sync-all.sh`

## Спецификация (5 документов)

1. `docs/specs/00-overview-and-scope.md` — обзор и принципы
2. `docs/specs/01-architecture-and-services.md` — граф сервисов, RPC
3. `docs/specs/02-data-model-and-conventions.md` — envelope, schemas
4. `docs/specs/03-deployment-and-operations.md` — kind, helm, CLAUDE.md иерархия
5. `docs/specs/04-roadmap-and-phasing.md` — sub-итерации 0.1–0.7, TDD-workflow

## Subagents (`.claude/agents/`)

Project-level (видны из любой подпапки workspace):

**Task-execution (7):** `acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`.

**Specialist-review (4):** `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`.

**Использовать готовые (не создавать заново):** `Explore`, `Plan`, `general-purpose`, `superpowers:code-reviewer`, `superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`, `superpowers:requesting-code-review`.

> Напоминание: `Internal.*` методы сервисов не должны попадать в api-gateway. Это ответственность `api-gateway-registrar`.

## Permissions

`.claude/settings.json` использует `bypassPermissions` для локальной dev-машины. Можно ужесточить позже.
