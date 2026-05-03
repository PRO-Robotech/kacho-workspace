# Kachō Specs CHANGELOG

## 2026-05-03 — Initial draft
- 5 спек-документов 00–04 утверждены
- sub-phase 0.1 acceptance готов и утверждён заказчиком
- sub-phase 0.1 implementation plan готов

## 2026-05-03 — Design change: kacho-api → kacho-proto

Заказчик переименовал proto-репо: `kacho-api` → `kacho-proto`. Семантика: единая центральная директория для всех `.proto`-определений Kachō (от всех текущих и будущих бекендов и доменов). Сервисные репо НЕ содержат `.proto`-файлов — только Go-импорт сгенерированных stubs из `github.com/PRO-Robotech/kacho-proto/gen/go/...`.

Затронуто: bootstrap.sh, sync-all.sh, go.work.example, CLAUDE.md, 6 агентов (`proto-sync`, `proto-api-reviewer`, `rpc-implementer`, `service-scaffolder`, `integration-tester`, `api-gateway-registrar`), 5 спек-документов (`00–04`), acceptance + plan для sub-phase 0.1, go.mod и proto go_package option в самом `kacho-proto`.

## 2026-05-03 — Sub-phase 0.1 (Bootstrap) завершена

Скелет polyrepo Kachō готов. Один скрипт + одна make-команда поднимают пустой
dev-стенд за < 3 минут.

**Что готово:**

- 9 sibling-репо в `cloud-demo/`:
  - `kacho-workspace` — этот репо: CLAUDE.md, 11 субагентов, спеки, bootstrap-скрипты, bats-тесты
  - `kacho-proto` — единая центральная директория для всех `.proto` Kachō. Common-типы (`ResourceMeta`, `Selector`, `FieldSelector`, `ResourceRef`) + сгенерированные Go-stubs в `gen/go/`
  - `kacho-corelib` — 6 пакетов 0.1: `ids`, `errors`, `db`, `config`, `grpcsrv`, `observability` (coverage 71-100% per package)
  - 5 service-stub-репо: `kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` (README + .gitignore + trivial CI)
  - `kacho-deploy` — kind + Helm + Bitnami Postgres + ingress-nginx + 9 e2e-bash-сценариев

- `bootstrap.sh` (clone-or-skip 8 sibling) + `sync-all.sh` (fetch + ff-pull) — TDD через bats, 4/4 PASS
- `go.work.example` — 7 Go-модулей
- Workspace-CLAUDE.md с naming convention, 9 запретами, секциями про Clean Architecture, kacho-corelib reuse, kacho-proto центральный proto-репо, git/коммиты
- 11 project-level субагентов с full system-prompts (~145–243 строк каждый)

**Smoke (Phase 8.1):**
- `make dev-up` = 179 сек (<5 мин — E1 PASS)
- 5 pods Running: ingress-nginx + 4 Postgres
- E4 (4 postgres ready), E5 (4 secrets), E6 (ingress 503), E7 (no service pods), E8 (dev-down clean) — все PASS
- E9 (emptyDir regression) — не прогонялось в smoke (требует dev-down/up цикла, ~6 мин); скрипт готов
- F1 (port80-busy) — требует sudo, manual; F2 (missing-tools) — manual

**Design changes по ходу 0.1:**
- `kacho-api` → `kacho-proto`: единая proto-репа для всех бекендов
- Принцип переиспользования через `kacho-corelib` зафиксирован в CLAUDE.md
- Чистая архитектура (Uncle Bob) — обязательное требование Kachō; зафиксировано в CLAUDE.md и 4 агентах (`rpc-implementer`, `service-scaffolder`, `go-style-reviewer`, `system-design-reviewer`)
- Git-конвенция: коммиты подписываются git-config-именем, без Co-Authored-By trailers
- Bitnami images переехали → используем `bitnamilegacy/postgresql`
- Ingress в `helm/post-install/`, не в umbrella templates (admission webhook race-condition)

**Не входит в 0.1, перенесено:**
- `kacho-corelib/watch/`, `outbox/`, `selector/` — sub-phase 0.2
- `WatchEvent` proto — sub-phase 0.2 (вместе с `kacho-resource-manager`)
- Сервисные deps в helm/umbrella — sub-phase 0.2+ (commented in Chart.yaml)
- Push в `github.com/PRO-Robotech/...` — отложено: заказчик создаёт remote-репо вручную, потом push 9 локальных историй

**Tag:** `kacho-workspace:0.1.0`
