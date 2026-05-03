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
