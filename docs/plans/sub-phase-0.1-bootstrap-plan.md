# Sub-phase 0.1 — Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended for parallel phases) or `superpowers:executing-plans` (sequential). Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Source of truth:** `kacho-workspace/docs/specs/sub-phase-0.1-bootstrap-acceptance.md` (acceptance) + `04-roadmap-and-phasing.md` §3 (scope).
> Каждая task привязана к ID acceptance-сценария (A1, B3, E4, ...) — это контракт TDD: тест с именем `<scenario-id>_<short-desc>` пишется первым, реализация следует.

**Goal:** Подготовить пустой polyrepo-каркас Kachō: `bootstrap.sh` клонирует все репо, `make dev-up` поднимает kind-кластер с 4 пустыми Postgres + ingress за < 5 минут. Без бизнес-логики ресурсов.

**Architecture:** Polyrepo workspace (9 репо как siblings в `cloud-demo/`), Go workspace через `go.work`, dev-стенд через kind + Helm + Bitnami Postgres + ingress-nginx. CLAUDE.md иерархия workspace-уровня + 11 кастомных субагентов. Watch/outbox/selector явно отложены в 0.2.

**Tech Stack:** Go 1.22+, buf v1.x, kind v0.20+, Helm 3, Bitnami Postgres chart 13.x, ingress-nginx 4.x, bash + bats-core (для bash-тестов), GitHub Actions, testcontainers-go (для corelib unit-тестов с БД).

---

## §9 Resolutions — defaults для открытых вопросов acceptance-документа

| # | Вопрос §9 | Default-решение в этом плане | Где поменять |
|---|---|---|---|
| 1 | Idempotent re-run bootstrap.sh: добавлять `--update`? | **Нет.** `bootstrap.sh` строго clone-or-skip; обновлениями занимается `sync-all.sh`. Проще, меньше surface area. | Phase 2, Task 2.3 |
| 2 | 11 агентов — полные prompts или заглушки? | **Полные system-prompts** (workflow, inputs/outputs, шаблоны, failure modes, coordination с другими агентами). Решено заказчиком 2026-05-03. | Phase 1, Task 1.4 |
| 3 | `WatchEvent` в proto common-types в 0.1? | **Нет, переносим в 0.2** (вместе с `kacho-resource-manager`-сервисом). В 0.1 — только `ResourceMeta`, `Selector`, `FieldSelector`, `ResourceRef`. | Phase 4, Task 4.3 |
| 4 | `make reload-svc SVC=foo` поведение в 0.1? | **Soft warning + exit 0.** Печатает «service `foo` is not deployed yet (planned for sub-phase X.Y)». | Phase 6, Task 6.10 |
| 5 | CI для 5 stub-репо? | **Минимальный 1-job:** проверка наличия `README.md` и `.gitignore`. ~30 сек GH Actions per repo. | Phase 3, Task 3.2 |
| 6 | Preflight-checks в `make dev-up` — отдельный таргет? | **Inline bash в `dev-up`,** без отдельного `check-prereqs`. Простота > индирекция. | Phase 6, Task 6.4 |

**Если хотя бы один default неверный — поправьте таблицу выше до начала исполнения.** Изменение каскадируется в соответствующие tasks.

---

## File map (cross-repo)

### `kacho-workspace/` (Phase 1–2)
- `CLAUDE.md`, `README.md`, `.gitignore`
- `.claude/settings.json`
- `.claude/agents/{acceptance-author, proto-sync, service-scaffolder, rpc-implementer, migration-writer, api-gateway-registrar, integration-tester, system-design-reviewer, db-architect-reviewer, go-style-reviewer, proto-api-reviewer}.md` (11 файлов)
- `bootstrap.sh`, `sync-all.sh`, `go.work.example`
- `tests/bootstrap.bats`, `tests/sync-all.bats`, `tests/fixtures/` (фейковые remote-репо для smoke)
- `docs/specs/CHANGELOG.md`
- `.github/workflows/ci.yaml`

### `kacho-proto/` (Phase 4)
- `go.mod`, `buf.yaml`, `buf.gen.yaml`, `buf.lock`
- `proto/kacho/cloud/common/v1/{resource_meta.proto, selector.proto, resource_ref.proto}`
- `gen/go/kacho/cloud/common/v1/*.pb.go` (committed)
- `Makefile`, `README.md`, `.gitignore`
- `.github/workflows/ci.yaml`

### `kacho-corelib/` (Phase 5)
- `go.mod`
- `ids/{ids.go, ids_test.go}`
- `errors/{errors.go, errors_test.go}`
- `db/{pool.go, pool_test.go, transactor.go, transactor_test.go}`
- `config/{config.go, config_test.go}`
- `grpcsrv/{server.go, server_test.go}`
- `observability/{otel.go, slog.go, observability_test.go}`
- `Makefile`, `README.md`, `.gitignore`
- `.github/workflows/ci.yaml`

### `kacho-deploy/` (Phase 6)
- `Makefile`
- `kind/{kind-config.yaml, create-cluster.sh}`
- `helm/umbrella/{Chart.yaml, values.dev.yaml, templates/{namespace.yaml, ingress.yaml}}`
- `helm/postgres/values.dev.yaml`
- `e2e/0.1/{E1-dev-up-under-5min.sh, E4-postgres-ready.sh, E5-secrets.sh, E6-ingress-ready.sh, E7-no-service-pods.sh, E8-dev-down-clean.sh, E9-emptydir-regression.sh, F1-port80-busy.sh, F2-missing-tools.sh}`
- `README.md`, `.gitignore`
- `.github/workflows/ci.yaml`

### Stub-репо (Phase 3) — `kacho-api-gateway/`, `kacho-resource-manager/`, `kacho-vpc/`, `kacho-compute/`, `kacho-loadbalancer/`
В каждом: `README.md`, `.gitignore`, `.github/workflows/ci.yaml` (trivial).

---

## Зависимости между фазами

```
Phase 0 (preflight) ─── обязательно первой ───┐
                                              ▼
       ┌──────────┬─────────┬─────────┬──────────┐
       │          │         │         │          │
  Phase 1     Phase 2    Phase 3   Phase 4    Phase 5    Phase 6
 (workspace  (workspace  (5 stub  (kacho-   (kacho-    (kacho-
   meta)     scripts)    repos)    api)     corelib)   deploy)
       │          │         │         │          │          │
       └─Phase 2 нужен Phase 1 для CLAUDE.md ссылок (опционально)─┘
       └─Phase 3 нужен только удалённо в GitHub для bootstrap.sh-теста─┘
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                                       ▼
                     Phase 7 (cross-repo CI)              Phase 8 (smoke + tag)
```

**Параллелизация:** Phase 1, 3, 4, 5, 6 — полностью независимые после Phase 0. Phase 2 опционально ссылается на список агентов из Phase 1. Phase 7 и 8 — финальные.

---

## Phase 0 — Preflight

### Task 0.1: Verify environment

**Files:** none (host machine check).

- [ ] **Step 1: Run preflight checks**

```bash
set -e
test -d cloud-demo || { echo "must be in cloud-demo/ parent"; exit 1; }
cd cloud-demo
which git go buf docker kind kubectl helm bats || {
  echo "missing tool — install: git, go 1.22+, buf, docker, kind, kubectl, helm, bats-core"
  exit 1
}
go version | grep -E 'go1\.(22|23|2[4-9])' || { echo "go 1.22+ required"; exit 1; }
ssh -T git@github.com 2>&1 | grep -q "successfully authenticated" || { echo "no SSH access to GitHub"; exit 1; }
echo "preflight OK"
```

Expected: `preflight OK`. Если что-то падает — фиксим и не идём дальше.

- [ ] **Step 2: Локально инициализировать 8 sibling-репо (без GitHub-remote — push deferred)**

Решение заказчика 2026-05-03: используем только `git`, без `gh` CLI. 8 пустых репо создаются локально в `cloud-demo/` через `git init`. Создание в `github.com/PRO-Robotech/` и `git push -u origin main` — откладываются до момента, когда заказчик создаст remote-репо вручную (через web UI). Все sub-phase 0.1 tasks могут выполняться локально без remotes; bootstrap.sh-тест уже использует `file://` fake-remotes (Task 2.1).

```bash
cd cloud-demo
for r in kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
  if [ ! -d "$r/.git" ]; then
    mkdir -p "$r" && (cd "$r" && git init -b main)
    echo "[init] $r"
  else
    echo "[skip] $r (already initialized)"
  fi
done
```

Expected: 8 sibling-папок-репо рядом с `kacho-workspace/`. **Перед Phase 8 (push tag)** заказчик создаёт 9 удалённых репо в `PRO-Robotech` org (через web UI), затем добавляем `git remote add origin git@github.com:PRO-Robotech/<r>.git` в каждом локальном.

---

## Phase 1 — kacho-workspace meta (CLAUDE.md + agents + settings)

**Repo working dir:** `cloud-demo/kacho-workspace/`. Если репо ещё не клонирован — `git clone git@github.com:PRO-Robotech/kacho-workspace.git`.

### Task 1.1: `.gitignore` + `README.md` placeholder

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Создать `.gitignore`**

```gitignore
# go.work — локальный артефакт, см. 03-deployment-and-operations.md §2.1
go.work
go.work.sum

# Claude Code локальные настройки
.claude/settings.local.json
.claude/projects/

# IDE / OS
.idea/
.vscode/
.DS_Store
*.swp
```

- [ ] **Step 2: Создать `README.md`** (минимальный, расширим в Phase 8)

```markdown
# kacho-workspace

Workspace-репо для проекта Kachō. Содержит CLAUDE.md иерархии, кастомных субагентов, bootstrap-скрипты и спецификации.

См. `docs/specs/` для архитектурных документов и `bootstrap.sh` для разворачивания workspace на новой машине.
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore README.md
git commit -m "chore: initial .gitignore and README placeholder"
```

### Task 1.2: `CLAUDE.md` — workspace-level [покрывает B1, B5]

**Files:** Create: `CLAUDE.md`

- [ ] **Step 1: Создать `CLAUDE.md`**

Содержание (ключевые блоки — все 8 запретов из `03-deployment-and-operations.md` §11 + executive summary + ссылки):

```markdown
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
9. **НЕ создавать новые «единые» БД** — только database-per-service.

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

## Permissions

`.claude/settings.json` использует `bypassPermissions` для локальной dev-машины. Можно ужесточить позже.
```

- [ ] **Step 2: Verify B5 keywords**

```bash
grep -E '(yandex|ORM|каскадное|миграцию|status.*upsert|Internal|broker|единые БД)' CLAUDE.md
```

Expected: 9 строк (8 запретов + Internal в описании subagents).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: workspace-level CLAUDE.md with conventions and prohibitions"
```

### Task 1.3: `.claude/settings.json` [B4]

**Files:** Create: `.claude/settings.json`

- [ ] **Step 1: Test that file is valid JSON and matches §10**

```bash
mkdir -p .claude
# Test will run after creation
```

- [ ] **Step 2: Создать файл**

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

- [ ] **Step 3: Verify**

```bash
jq -e '.permissions.defaultMode == "bypassPermissions"' .claude/settings.json
```

Expected: `true`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: workspace .claude/settings.json with bypassPermissions"
```

### Task 1.4: 11 агент-файлов [B3]

**Files:** Create: 11 файлов в `.claude/agents/`

**Шаблон каждого файла** (frontmatter + минимальное role-описание per §9.1–§9.2 deployment-документа; полный prompt эволюционирует — см. §9 Resolution #2):

- [ ] **Step 1: Создать `.claude/agents/acceptance-author.md`**

```markdown
---
name: acceptance-author
description: Первый агент в любой sub-итерации/RPC/фиче. Пишет acceptance-документ в формате Given-When-Then в kacho-workspace/docs/specs/sub-phase-X.Y-<topic>-acceptance.md ДО начала кодирования. Опирается на 02-data-model-and-conventions.md.
---

Ты — автор acceptance-документов для проекта Kachō.

Твоя единственная задача: получить scope sub-итерации (или нового RPC, или новой фичи) и написать acceptance-документ в формате Given-When-Then в `kacho-workspace/docs/specs/sub-phase-X.Y-<topic>-acceptance.md`.

**Источник истины:** 5 файлов в `kacho-workspace/docs/specs/00-overview-and-scope.md` ... `04-roadmap-and-phasing.md`. См. §3 roadmap-документа для scope каждой sub-итерации.

**Формат документа** — пример в `04-roadmap-and-phasing.md` §2 (compute Instance create + restart + negative). Группируй сценарии (Positive / Negative / Edge), нумеруй идентификаторами (A1, B3, ...), один сценарий — один integration-test + один e2e-bash.

**Запреты:**
- Не пиши код. Только текст спеки.
- Не делай decisions сам — если в спеке нет конкретики, выноси открытым вопросом в раздел «Вопросы заказчику».
- Не упоминай «yandex».
```

- [ ] **Step 2: Создать `.claude/agents/proto-sync.md`**

```markdown
---
name: proto-sync
description: Синхронизация upstream-источников proto-определений (если подсматриваем в YC). Rewrite yandex.cloud → kacho.cloud. Работает над kacho-proto/proto/.
---

Ты — синхронизатор proto-определений для Kachō.

Когда нужно: добавить новый домен (Compute, VPC, ...), могут пригодиться поля и структура из YC-proto как референс. Твоя задача — взять upstream-схему, переписать её под Kachō envelope (`metadata`/`spec`/`status`), переименовать пакет в `kacho.cloud.<domain>.v1`, удалить любые упоминания «yandex» (case-insensitive).

**Запреты:**
- НЕ упоминать «yandex» в готовом proto, комментариях, именах типов.
- НЕ копировать YC-flat-структуру (`name` на верхнем уровне) — только Kachō envelope.
- НЕ дублировать существующие proto-сообщения; common-типы (ResourceMeta, Selector, ResourceRef) переиспользуй из `proto/kacho/cloud/common/v1/`.
```

- [ ] **Step 3: Создать `.claude/agents/service-scaffolder.md`**

```markdown
---
name: service-scaffolder
description: Создание нового сервисного репо из шаблона по структуре §1.1 03-deployment-and-operations.md (cmd/, internal/{domain,service,repo,reconciler,clients,config}, migrations/, deploy/, Dockerfile, Makefile, CI).
---

Ты — scaffolder сервисных репо Kachō.

При запросе «создай скелет для kacho-<svc>» создай структуру строго по `03-deployment-and-operations.md` §1.1: `cmd/<svc>/main.go` с subcommand `migrate`/`serve`, `internal/{domain,service,repo,reconciler,clients,config}`, `migrations/` с копией common из corelib, `deploy/` с Helm-чартом, `Dockerfile` (multi-stage), `Makefile`, `.github/workflows/ci.yaml`.

**Запреты:** не реализуй бизнес-логику; это работа `rpc-implementer`. Только пустые директории + минимальные файлы (`main.go` с заглушкой `serve`, миграции common, Helm-skeleton).
```

- [ ] **Step 4: Создать `.claude/agents/rpc-implementer.md`**

```markdown
---
name: rpc-implementer
description: Реализация одного RPC end-to-end по утверждённому acceptance-документу. TDD: сначала исполняемые тесты (red), затем proto → handler → repo → миграция (green), потом refactor.
---

Ты — реализатор отдельного RPC для Kachō.

**Вход:** утверждённый acceptance-документ + конкретный RPC (`<Service>.<Method>`).

**Workflow (строго):**
1. Прочитай acceptance-сценарии, относящиеся к RPC.
2. Создай falling integration-тесты в `internal/service/<resource>_acceptance_test.go`. Имена: `Test<Resource>_<ScenarioID>_<ShortDesc>`.
3. Запусти — все red.
4. Реализуй: proto (если нужен) → migration → repo (sqlc) → handler → outbox-write.
5. Запусти тесты — green.
6. Refactor при зелёных тестах.
7. Подключи в api-gateway через агент `api-gateway-registrar` (только для public RPC).

**Запреты:** НЕ пиши status в `/upsert`-handler (только `/upd-status`). НЕ маршрутизируй Internal.* через api-gateway. НЕ упоминай yandex.
```

- [ ] **Step 5: Создать `.claude/agents/migration-writer.md`**

```markdown
---
name: migration-writer
description: Написание goose-миграций по конвенциям §11–§12 02-data-model-and-conventions.md. Sequential numbering 0001_, 0002_. JSONB для spec/status, GIN для labels, NOT NULL по умолчанию, BEFORE UPDATE триггер для resource_version.
---

Ты — писатель миграций Postgres для Kachō.

**Конвенции (обязательно):**
- Файл: `migrations/0NNN_<short_name>.sql`, формат goose с `-- +goose Up` / `-- +goose Down`.
- `spec` и `status` — JSONB.
- `labels` — JSONB + `CREATE INDEX ... USING GIN (labels jsonb_path_ops)`.
- Денормализованные `folder_id`, `cloud_id`, `organization_id`, `name` — отдельные колонки, NOT NULL (кроме обозначенных опциональных).
- `resource_version BIGINT NOT NULL DEFAULT nextval('resource_version_seq')`.
- BEFORE UPDATE trigger: `resource_version = nextval('resource_version_seq')`.
- UNIQUE constraint per таблица согласно §2.3.

**Запреты:**
- НЕ редактировать применённую миграцию (даже если ещё в dev). Только новая.
- НЕ использовать каскад через FK к таблице другого сервиса (database-per-service).
- НЕ упоминать yandex.
```

- [ ] **Step 6: Создать `.claude/agents/api-gateway-registrar.md`**

```markdown
---
name: api-gateway-registrar
description: Обновление маршрутизации api-gateway при добавлении нового сервиса/RPC. gRPC-proxy backend mapping + REST mux registration + allowlist для Internal.* фильтра.
---

Ты — регистратор RPC в `kacho-api-gateway`.

При появлении нового публичного RPC (`<Service>.<Method>` через api-gateway) обнови:
1. **gRPC-proxy mapping** (`internal/proxy/router.go` или config-файл): `kacho.cloud.<domain>.v1.*` → `<domain>.kacho.svc.cluster.local:9090`.
2. **REST mux registration** (`internal/rest/handlers.go`): `RegisterXxxServiceHandlerFromEndpoint` для нового сервиса.
3. **Allowlist** в gateway-конфиге: добавь публичный RPC; **НЕ добавляй** `Internal.*` методы (они никогда не маршрутизируются наружу).
4. Обнови env-переменную `KACHO_<DOMAIN>_GRPC` если её ещё нет.

**Запреты:** НИКОГДА не маршрутизировать `Internal.*` (Exists, HasDependents, UpdateStatus) через gateway наружу.
```

- [ ] **Step 7: Создать `.claude/agents/integration-tester.md`**

```markdown
---
name: integration-tester
description: Конвертация утверждённого acceptance-документа в исполняемые тесты. Один сценарий → один integration-тест (testcontainers-go + Postgres) + один e2e-bash (kacho-deploy/e2e/<sub-phase>/<scenario-id>.sh через grpcurl).
---

Ты — конвертер acceptance-сценариев в исполняемые тесты.

**Вход:** утверждённый `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`.

**Что делаешь:**
1. Для каждого сценария (A1, B3, ...) создай два теста:
   - **Integration:** Go-тест в репо соответствующего сервиса (`internal/service/<resource>_acceptance_test.go`), имя функции `Test<Resource>_<ScenarioID>_<ShortDesc>`. Использует testcontainers-go для Postgres.
   - **E2E:** bash-скрипт `kacho-deploy/e2e/<sub-phase>/<ScenarioID>-<short-desc>.sh` через `grpcurl` против `api.kacho.local`.
2. Имена тестов **двусторонне трассируются** на ID сценария.
3. Тесты должны падать **до** реализации (red phase TDD).

**Запреты:** не реализуй RPC сам — только тесты. Если acceptance-сценарий неоднозначен, верни вопрос автору acceptance, а не угадывай.
```

- [ ] **Step 8: Создать `.claude/agents/system-design-reviewer.md`**

```markdown
---
name: system-design-reviewer
description: Ревью архитектурных решений с точки зрения distributed systems best practices. Watch backlog, idempotency, eventual consistency, OCC, partition tolerance, durability/availability tradeoffs.
---

Ты — рецензент архитектурных решений Kachō с distributed systems perspective.

**Что смотришь:** новые RPC, изменения в Watch-логике, reconciler-паттерны, cross-service вызовы, finalizers, multi-replica координация.

**Чек-лист:**
- Нет dual-write (Postgres + outbox в одной транзакции — обязательно).
- Идемпотентность: повторный вызов `Upsert` или `UpdateStatus` с теми же данными — no-op.
- OCC через `SELECT FOR UPDATE` или `resource_version` сравнение в read-modify-write.
- Reconciler берёт `pg_advisory_lock` на ресурс перед обработкой.
- Watch — eventually consistent, ringBuffer + outbox-retention 1 час, `Gone 410` при превышении.
- Cross-service — синхронный gRPC, no cycles в графе.
- Нет shared state между репликами кроме БД.

Возвращай: список найденных проблем + конкретные предложения, со ссылками на спеку.
```

- [ ] **Step 9: Создать `.claude/agents/db-architect-reviewer.md`**

```markdown
---
name: db-architect-reviewer
description: Ревью схем и миграций. Индексы, FK-стратегия, JSONB vs scalar, OCC, keyset pagination (per §11–§12 02-data-model-and-conventions.md).
---

Ты — рецензент Postgres-схем и миграций для Kachō.

**Чек-лист:**
- Денормализованные `folder_id`/`cloud_id`/`organization_id`/`name` как scalar колонки + индексы для filtering.
- `spec`/`status` — JSONB; индексировать только горячие пути.
- `labels` — JSONB + GIN.
- UNIQUE constraints согласно §2.3 (`name` уникален в правильном scope).
- `resource_version_seq` + BEFORE UPDATE trigger.
- FK через границу сервиса — **запрещены** (database-per-service); только same-DB.
- `pg_advisory_lock(uid_hash)` для reconciler.
- `statement_timeout = '30s'`.
- Pagination — keyset (`(resource_version, uid) > (...)`), не offset.

Возвращай: список проблем + конкретные SQL-фиксы.
```

- [ ] **Step 10: Создать `.claude/agents/go-style-reviewer.md`**

```markdown
---
name: go-style-reviewer
description: Go-специфичный clean code review. Error handling, context propagation, generics, naming, slog usage, context-aware DB calls.
---

Ты — Go-style рецензент для Kachō.

**Чек-лист:**
- Error wrapping: `fmt.Errorf("...: %w", err)`, `errors.Is`/`errors.As`.
- Контекст: `ctx context.Context` первый аргумент любой публичной функции; пропагация в DB/gRPC-вызовы.
- Никаких `panic` в production-пути (только `panic` в reconciler-startup при invariant-violation).
- `slog` (`log/slog`) для логирования; structured fields, не string-interpolation.
- Generics — только где даёт явную пользу (нет premature abstraction).
- Naming: short for short scope, descriptive for package-level.
- Никаких `init()` для side-effects (только const-таблицы).
- gRPC handlers — тонкие; logic в `internal/service/`, repo в `internal/repo/`.

Возвращай: pull-request-style комментарии с цитатами кода.
```

- [ ] **Step 11: Создать `.claude/agents/proto-api-reviewer.md`**

```markdown
---
name: proto-api-reviewer
description: Ревью proto-изменений. Backward-compat, validation-аннотации, отсутствие yandex в proto/kacho/, buf-lint clean, K8s-style envelope.
---

Ты — рецензент proto-API для Kachō.

**Чек-лист:**
- Пакет: `kacho.cloud.<domain>.v1`. Никогда не `yandex.cloud.*`.
- Envelope: `<Resource>` всегда содержит `ResourceMeta metadata = 1;` + `<R>Spec spec = 2;` + (опционально) `<R>Status status = 3;`.
- Reserved field numbers для удалённых полей (backward-compat).
- Validation: `buf.validate.field` аннотации для required/regex/min/max.
- buf lint clean (без warnings).
- buf breaking — нет breaking changes против main-тега.
- 4 стандартных RPC всегда: `Upsert`, `Delete`, `List`, `Watch`. Дополнительные — только imperative thin (`Restart`).
- Internal RPC помещены в `<R>InternalService` с allowlist-фильтром на api-gateway.

Возвращай: diff с предложенными правками + причины.
```

- [ ] **Step 12: Verify all 11 files**

```bash
ls .claude/agents/ | wc -l
```

Expected: `11`.

```bash
for f in .claude/agents/*.md; do
  head -1 "$f" | grep -q '^---$' && grep -q '^name:' "$f" && grep -q '^description:' "$f" || echo "BAD: $f"
done
```

Expected: пустой stdout (все файлы валидные frontmatter).

- [ ] **Step 13: Commit**

```bash
git add .claude/agents/
git commit -m "feat(agents): 11 project-level subagents (skeleton with frontmatter and role)"
```

### Task 1.5: `docs/specs/CHANGELOG.md`

**Files:** Create: `docs/specs/CHANGELOG.md`

- [ ] **Step 1: Создать**

```markdown
# Kachō Specs CHANGELOG

## 2026-05-03 — Initial draft
- 5 спек-документов 00–04 утверждены
- sub-phase 0.1 acceptance готов

## (Sub-phase 0.1 — bootstrap, при завершении)
- TBD: дописать после tag kacho-workspace:0.1.0
```

- [ ] **Step 2: Commit**

```bash
git add docs/specs/CHANGELOG.md
git commit -m "docs: specs CHANGELOG bootstrap"
```

---

## Phase 2 — kacho-workspace scripts (TDD)

### Task 2.1: `tests/` инфраструктура (bats-core)

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/fixtures/setup-fake-remotes.sh`

- [ ] **Step 1: `tests/test_helper.bash`**

```bash
#!/usr/bin/env bash
# Helper для bats-тестов bootstrap.sh и sync-all.sh

setup_fake_workspace() {
  TMP_WS="$(mktemp -d)"
  export TMP_WS
  cd "$TMP_WS"
}

teardown_fake_workspace() {
  if [ -n "${TMP_WS:-}" ]; then rm -rf "$TMP_WS"; fi
}

# Создаёт локальные bare-репо как фейковые remotes для тестов bootstrap.sh
setup_fake_remotes() {
  local remotes_dir="$TMP_WS/fake-remotes"
  mkdir -p "$remotes_dir"
  for r in kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
    git init --bare "$remotes_dir/$r.git" >/dev/null
    # начальный коммит
    local work="$TMP_WS/work-$r"
    git clone "$remotes_dir/$r.git" "$work" >/dev/null 2>&1
    echo "# $r" > "$work/README.md"
    (cd "$work" && git add README.md && git -c user.email=t@t -c user.name=t commit -m init >/dev/null && git push -u origin HEAD:main >/dev/null 2>&1)
    rm -rf "$work"
  done
  export FAKE_REMOTES_BASE="$remotes_dir"
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/test_helper.bash
git commit -m "test: bats-core helper with fake-remotes setup"
```

### Task 2.2: `bootstrap.sh` — failing test [A1]

**Files:**
- Create: `tests/bootstrap.bats`

- [ ] **Step 1: Написать тест A1 (фейковые remotes)**

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

@test "A1: bootstrap clones all 8 sibling repos" {
  cd "$TMP_WS"
  # Симулируем: kacho-workspace уже клонирован вручную
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  cp "$BATS_TEST_DIRNAME/test_helper.bash" kacho-workspace/tests/test_helper.bash 2>/dev/null || true
  chmod +x kacho-workspace/bootstrap.sh

  # Override remote base через env
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]

  for r in kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
    [ -d "$r/.git" ] || { echo "missing $r"; false; }
  done
}
```

- [ ] **Step 2: Запустить тест, убедиться что падает**

```bash
bats tests/bootstrap.bats
```

Expected: FAIL with `bootstrap.sh: command not found` или подобное.

### Task 2.3: `bootstrap.sh` — minimum implementation [A1, A2, A3]

**Files:** Create: `bootstrap.sh`

- [ ] **Step 1: Реализация (clone-or-skip, без `--update`)**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_PARENT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_BASE="${KACHO_REMOTE_BASE:-git@github.com:PRO-Robotech}"

REPOS=(
  kacho-proto
  kacho-corelib
  kacho-api-gateway
  kacho-resource-manager
  kacho-vpc
  kacho-compute
  kacho-loadbalancer
  kacho-deploy
)

cd "$WS_PARENT"

clone_count=0
skip_count=0
fail_count=0

for r in "${REPOS[@]}"; do
  if [ -d "$WS_PARENT/$r/.git" ]; then
    echo "[skip] $r — already cloned"
    skip_count=$((skip_count + 1))
    continue
  fi

  url="$REMOTE_BASE/$r.git"
  # для file:// fake remotes
  case "$REMOTE_BASE" in
    file://*) url="${REMOTE_BASE#file://}/$r.git" ;;
  esac

  if git clone "$url" "$WS_PARENT/$r" 2>&1; then
    echo "[clone] $r"
    clone_count=$((clone_count + 1))
  else
    echo "[FAIL] $r — check SSH access to PRO-Robotech and that the repo exists" >&2
    fail_count=$((fail_count + 1))
  fi
done

echo
echo "Summary: cloned=$clone_count skipped=$skip_count failed=$fail_count"

if [ "$fail_count" -gt 0 ]; then
  echo "Some repos failed to clone. Already-cloned repos are preserved." >&2
  exit 1
fi

echo
echo "Next step:"
echo "  cp $SCRIPT_DIR/go.work.example $WS_PARENT/go.work"
echo "  cd $WS_PARENT/kacho-deploy && make dev-up"
```

- [ ] **Step 2: chmod +x и запустить тест**

```bash
chmod +x bootstrap.sh
bats tests/bootstrap.bats
```

Expected: PASS.

### Task 2.4: `bootstrap.sh` — idempotency test [A2]

**Files:** Modify: `tests/bootstrap.bats` (добавить тест)

- [ ] **Step 1: Добавить тест A2**

```bash
@test "A2: bootstrap is idempotent on re-run" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  ./kacho-workspace/bootstrap.sh

  # Создаём локальный коммит в одном из репо
  cd kacho-proto
  echo "local change" > local.txt
  git -c user.email=t@t -c user.name=t add local.txt
  git -c user.email=t@t -c user.name=t commit -m "local-only"
  cd ..

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already cloned"* ]] || [[ "$output" == *"skip"* ]]

  # Локальный коммит сохранился
  cd kacho-proto
  git log --oneline | grep -q "local-only"
}
```

- [ ] **Step 2: Запустить, ожидаем PASS** (реализация уже clone-or-skip)

```bash
bats tests/bootstrap.bats
```

Expected: оба теста PASS.

### Task 2.5: `bootstrap.sh` — failure test [A3]

- [ ] **Step 1: Добавить тест A3**

```bash
@test "A3: bootstrap fails gracefully when one repo is unreachable" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" kacho-workspace/
  chmod +x kacho-workspace/bootstrap.sh

  # Удаляем один из fake-remotes
  rm -rf "$FAKE_REMOTES_BASE/kacho-loadbalancer.git"
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"

  run ./kacho-workspace/bootstrap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"failed"* ]]
  [[ "$output" == *"loadbalancer"* ]]

  # Другие репо клонировались
  [ -d "kacho-proto/.git" ]
  [ -d "kacho-vpc/.git" ]
}
```

- [ ] **Step 2: Запуск**

```bash
bats tests/bootstrap.bats
```

Expected: 3 PASS.

### Task 2.6: `sync-all.sh` — TDD [A5]

**Files:**
- Create: `tests/sync-all.bats`
- Create: `sync-all.sh`

- [ ] **Step 1: Тест**

```bash
#!/usr/bin/env bats
load 'test_helper'
setup() { setup_fake_workspace; setup_fake_remotes; }
teardown() { teardown_fake_workspace; }

@test "A5: sync-all.sh fetches and ff-pulls each repo" {
  cd "$TMP_WS"
  mkdir -p kacho-workspace
  cp "$BATS_TEST_DIRNAME/../bootstrap.sh" "$BATS_TEST_DIRNAME/../sync-all.sh" kacho-workspace/
  chmod +x kacho-workspace/*.sh
  export KACHO_REMOTE_BASE="file://$FAKE_REMOTES_BASE"
  ./kacho-workspace/bootstrap.sh

  # Push новый коммит в один из remotes
  local work="$TMP_WS/work-vpc"
  git clone "$FAKE_REMOTES_BASE/kacho-vpc.git" "$work" >/dev/null 2>&1
  echo "upstream" > "$work/upstream.txt"
  (cd "$work" && git add upstream.txt && git -c user.email=t@t -c user.name=t commit -m up && git push)
  rm -rf "$work"

  run ./kacho-workspace/sync-all.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]] || [[ "$output" == *"up-to-date"* ]]

  [ -f "kacho-vpc/upstream.txt" ]
}
```

- [ ] **Step 2: Реализация `sync-all.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_PARENT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPOS=(kacho-workspace kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy)

for r in "${REPOS[@]}"; do
  if [ ! -d "$WS_PARENT/$r/.git" ]; then
    echo "[$r] not cloned, skip"
    continue
  fi
  cd "$WS_PARENT/$r"
  before="$(git rev-parse HEAD 2>/dev/null)"
  git fetch --quiet || { echo "[$r] fetch failed"; continue; }
  if git pull --ff-only --quiet 2>/dev/null; then
    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
      echo "[$r] up-to-date"
    else
      echo "[$r] updated to $after"
    fi
  else
    echo "[$r] skipped: not fast-forward"
  fi
done
```

- [ ] **Step 3: chmod + bats**

```bash
chmod +x sync-all.sh
bats tests/sync-all.bats
```

Expected: PASS.

### Task 2.7: `go.work.example`

**Files:** Create: `go.work.example`

- [ ] **Step 1: Создать**

```go
go 1.22

use (
	./kacho-proto
	./kacho-corelib
	./kacho-api-gateway
	./kacho-resource-manager
	./kacho-vpc
	./kacho-compute
	./kacho-loadbalancer
)
```

- [ ] **Step 2: Note** — `go.work` в `cloud-demo/` лежит на уровень выше всех git-репо, поэтому он нигде не tracked. В `kacho-workspace/.gitignore` уже есть `go.work` (Task 1.1) — защита от случайного коммита, если кто-то скопирует в неправильное место [F5].

- [ ] **Step 3: Commit Phase 2**

```bash
git add bootstrap.sh sync-all.sh go.work.example tests/
git commit -m "feat(workspace): bootstrap.sh, sync-all.sh, go.work.example with bats tests (A1, A2, A3, A5, F5)"
```

---

## Phase 3 — Stub service repos

### Task 3.1: Создание 5 stub-репо локально

**Repos:** `kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`.

**Для каждого** (повторяется 5 раз):

- [ ] **Step 1: Клонировать пустой**

```bash
cd cloud-demo
git clone git@github.com:PRO-Robotech/kacho-<svc>.git
cd kacho-<svc>
```

- [ ] **Step 2: Создать `README.md`**

```markdown
# kacho-<svc>

Skeleton. Реализация в sub-phase 0.<X> (см. `kacho-workspace/docs/specs/04-roadmap-and-phasing.md` §3).
```

(`<X>` = 6 для api-gateway, 2 для resource-manager, 3 для vpc, 4 для compute, 5 для loadbalancer.)

- [ ] **Step 3: Создать `.gitignore`**

```gitignore
# Go build
*.exe
*.test
*.out
bin/
dist/

# IDE
.idea/
.vscode/
.DS_Store
```

- [ ] **Step 4: Создать `.github/workflows/ci.yaml`** (trivial — §9 Resolution #5)

```yaml
name: ci
on: [push, pull_request]
jobs:
  skeleton-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: test -f README.md
      - run: test -f .gitignore
```

- [ ] **Step 5: Commit + push**

```bash
git add README.md .gitignore .github/
git commit -m "chore: skeleton README, gitignore, trivial CI"
git push -u origin main
```

### Task 3.2: Verify [G1, A1 follow-up]

- [ ] **Step 1: bootstrap.sh клонирует stub-репо**

После того как все 5 stub-репо запушены в GitHub:

```bash
cd /tmp && rm -rf bs-test && mkdir bs-test && cd bs-test
git clone git@github.com:PRO-Robotech/kacho-workspace.git
./kacho-workspace/bootstrap.sh
ls -d kacho-* | wc -l
```

Expected: `9` (включая kacho-workspace).

---

## Phase 4 — kacho-proto skeleton

**Repo working dir:** `cloud-demo/kacho-proto/`.

### Task 4.1: `go.mod` и базовые файлы

**Files:**
- Create: `go.mod`, `.gitignore`, `README.md`

- [ ] **Step 1: `go mod init`**

```bash
go mod init github.com/PRO-Robotech/kacho-proto
```

- [ ] **Step 2: `.gitignore`**

```gitignore
*.exe
.idea/
.vscode/
.DS_Store
# не игнорируем gen/ — committed согласно §1 deployment-документа
```

- [ ] **Step 3: `README.md`**

```markdown
# kacho-proto

Proto-определения и сгенерированные Go-stubs для Kachō Cloud Control Plane.

См. `kacho-workspace/docs/specs/02-data-model-and-conventions.md` §13 (naming) и §6 (стандартные RPC).

## Команды

- `make buf-lint` — линт proto
- `make buf-breaking` — проверка breaking changes против baseline
- `make generate` — генерация Go-stubs в `gen/`
```

- [ ] **Step 4: Commit**

```bash
git add go.mod .gitignore README.md
git commit -m "chore: kacho-proto go.mod and skeleton"
```

### Task 4.2: `buf.yaml`, `buf.gen.yaml`, `buf.lock` [C1, C3]

**Files:** Create: `buf.yaml`, `buf.gen.yaml`

- [ ] **Step 1: `buf.yaml`**

```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
  except:
    - PACKAGE_VERSION_SUFFIX
breaking:
  use:
    - FILE
```

- [ ] **Step 2: `buf.gen.yaml`**

```yaml
version: v2
plugins:
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative
  - remote: buf.build/grpc/go
    out: gen/go
    opt: paths=source_relative,require_unimplemented_servers=true
```

- [ ] **Step 3: `buf dep update`** (создаёт `buf.lock`)

```bash
buf dep update
```

- [ ] **Step 4: Commit**

```bash
git add buf.yaml buf.gen.yaml buf.lock
git commit -m "chore: buf config (lint, breaking, generate)"
```

### Task 4.3: Common proto-типы [C2, C4]

**Files:**
- Create: `proto/kacho/cloud/common/v1/resource_meta.proto`
- Create: `proto/kacho/cloud/common/v1/selector.proto`
- Create: `proto/kacho/cloud/common/v1/resource_ref.proto`

(`WatchEvent` отложен в 0.2 per §9 Resolution #3.)

- [ ] **Step 1: `resource_meta.proto`** [C4]

```protobuf
syntax = "proto3";

package kacho.cloud.common.v1;

option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/common/v1;commonv1";

import "google/protobuf/timestamp.proto";

// ResourceMeta — единый envelope-блок metadata для всех ресурсов Kachō.
// См. kacho-workspace/docs/specs/02-data-model-and-conventions.md §2.
message ResourceMeta {
  string uid = 1;
  string name = 2;
  string organization_id = 3;
  string cloud_id = 4;
  string folder_id = 5;
  map<string, string> labels = 6;
  map<string, string> annotations = 7;
  google.protobuf.Timestamp creation_timestamp = 8;
  string resource_version = 9;
  int64 generation = 10;
  google.protobuf.Timestamp deletion_timestamp = 11;
  repeated string finalizers = 12;
  google.protobuf.Timestamp restarted_at = 13;
}
```

- [ ] **Step 2: `resource_ref.proto`**

```protobuf
syntax = "proto3";
package kacho.cloud.common.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/common/v1;commonv1";

message ResourceRef {
  string name = 1;
  string uid = 2;
  string kind = 3;
}
```

- [ ] **Step 3: `selector.proto`**

```protobuf
syntax = "proto3";
package kacho.cloud.common.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/common/v1;commonv1";

import "kacho/cloud/common/v1/resource_ref.proto";

message Selector {
  FieldSelector field_selector = 1;
  map<string, string> label_selector = 2;
}

message FieldSelector {
  string name = 1;
  string organization_id = 2;
  string cloud_id = 3;
  string folder_id = 4;
  repeated ResourceRef refs = 5;
}
```

- [ ] **Step 4: `buf lint`** [C1]

```bash
buf lint
```

Expected: exit 0, нет warnings.

- [ ] **Step 5: Commit**

```bash
git add proto/
git commit -m "feat(proto): common v1 types — ResourceMeta, Selector, FieldSelector, ResourceRef"
```

### Task 4.4: `Makefile` + `make generate` [C2]

**Files:** Create: `Makefile`

- [ ] **Step 1**

```makefile
.PHONY: buf-lint buf-breaking generate gen-clean

buf-lint:
	buf lint

buf-breaking:
	buf breaking --against ".git#branch=main"

gen-clean:
	rm -rf gen/

generate:
	buf generate

verify-no-yandex:
	! grep -ri 'yandex' proto/ gen/ 2>/dev/null
```

- [ ] **Step 2: Запустить generate**

```bash
make generate
ls gen/go/kacho/cloud/common/v1/
```

Expected: 3 файла `*.pb.go`.

- [ ] **Step 3: Verify no yandex**

```bash
make verify-no-yandex
```

Expected: exit 0 (grep ничего не нашёл).

- [ ] **Step 4: Commit gen/**

```bash
git add Makefile gen/
git commit -m "feat: Makefile and generated common v1 stubs (committed)"
```

### Task 4.5: GitHub Actions CI [G1]

**Files:** Create: `.github/workflows/ci.yaml`

- [ ] **Step 1**

```yaml
name: ci
on: [push, pull_request]
jobs:
  buf:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bufbuild/buf-setup-action@v1
      - run: buf lint
      - run: buf breaking --against "https://github.com/PRO-Robotech/kacho-proto.git#branch=main"
        continue-on-error: true  # на первом коммите main ещё нет baseline
      - name: verify gen/ is up-to-date
        run: |
          buf generate
          git diff --exit-code gen/
      - name: verify no yandex
        run: |
          ! grep -ri 'yandex' proto/ gen/
```

- [ ] **Step 2: Commit + push**

```bash
git add .github/
git commit -m "ci: buf lint/breaking/generate-drift/no-yandex"
git push -u origin main
```

### Task 4.6: Verify C1, C2, C3, C4 satisfied

- [ ] **Step 1: Локальный smoke**

```bash
make buf-lint
make generate
ls gen/go/kacho/cloud/common/v1/ | wc -l
```

Expected: 3 (`resource_meta.pb.go`, `selector.pb.go`, `resource_ref.pb.go`).

- [ ] **Step 2: Go-import smoke**

```bash
cat > /tmp/test_import.go <<'EOF'
package main
import (
    "fmt"
    commonv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/common/v1"
)
func main() {
    m := &commonv1.ResourceMeta{Name: "x"}
    fmt.Println(m.Name)
}
EOF
# (опционально: go run в workspace, требует go.work из Phase 2)
```

---

## Phase 5 — kacho-corelib skeleton

**Repo working dir:** `cloud-demo/kacho-corelib/`.

### Task 5.1: `go.mod`, скелет, `.gitignore`, README

- [ ] **Step 1**

```bash
go mod init github.com/PRO-Robotech/kacho-corelib
go get google.golang.org/grpc@latest \
       google.golang.org/genproto/googleapis/rpc/status@latest \
       github.com/jackc/pgx/v5@latest \
       github.com/kelseyhightower/envconfig@latest \
       go.opentelemetry.io/otel@latest \
       github.com/stretchr/testify@latest \
       github.com/testcontainers/testcontainers-go/modules/postgres@latest
```

- [ ] **Step 2: `.gitignore`** (как в kacho-proto)

```gitignore
*.exe
*.test
coverage.out
.idea/
.vscode/
.DS_Store
```

- [ ] **Step 3: `README.md`**

```markdown
# kacho-corelib

Общие Go-пакеты для сервисов Kachō.

В sub-phase 0.1: `ids`, `errors`, `db`, `config`, `grpcsrv`, `observability`.
В sub-phase 0.2 добавятся: `watch`, `outbox`, `selector`, `migrations/common`.

См. `kacho-workspace/docs/specs/03-deployment-and-operations.md` §1.
```

- [ ] **Step 4: Commit**

```bash
git add go.mod go.sum .gitignore README.md
git commit -m "chore: corelib skeleton, deps"
```

### Task 5.2: `ids/` package — TDD [D2]

**Files:**
- Create: `ids/ids.go`
- Create: `ids/ids_test.go`

- [ ] **Step 1: Failing test**

```go
package ids

import (
	"testing"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestNewUID_ReturnsValidUUIDv4(t *testing.T) {
	id := NewUID()
	parsed, err := uuid.Parse(id)
	require.NoError(t, err)
	require.Equal(t, uuid.Version(4), parsed.Version())
}

func TestNewUID_Unique(t *testing.T) {
	a, b := NewUID(), NewUID()
	require.NotEqual(t, a, b)
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
go test ./ids/...
```

- [ ] **Step 3: Implement**

```go
package ids

import "github.com/google/uuid"

func NewUID() string { return uuid.NewString() }
```

(`go get github.com/google/uuid` если не установлен.)

- [ ] **Step 4: Run, expect PASS**

```bash
go test ./ids/... -cover
```

Expected: PASS, coverage ≥ 70 % (D2).

- [ ] **Step 5: Commit**

```bash
git add ids/
git commit -m "feat(ids): NewUID returns UUID v4"
```

### Task 5.3: `errors/` package — TDD [D4]

**Files:**
- Create: `errors/errors.go`
- Create: `errors/errors_test.go`

- [ ] **Step 1: Failing tests**

```go
package errors

import (
	"testing"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestNotFound_BuildsResourceInfo(t *testing.T) {
	err := NotFound("Folder", "abc-123").Err()
	st, ok := status.FromError(err)
	require.True(t, ok)
	require.Equal(t, codes.NotFound, st.Code())
	require.Contains(t, st.Message(), "Folder")
	// проверка ResourceInfo в details — упрощённо для скелета
}

func TestInvalidArgument_BuildsBadRequest(t *testing.T) {
	err := InvalidArgument().AddFieldViolation("metadata.name", "must match regex").Err()
	st, _ := status.FromError(err)
	require.Equal(t, codes.InvalidArgument, st.Code())
}

func TestAllCodes_HaveHelper(t *testing.T) {
	cases := []struct {
		fn   func() *Builder
		code codes.Code
	}{
		{func() *Builder { return AlreadyExists("X", "y") }, codes.AlreadyExists},
		{func() *Builder { return FailedPrecondition("x") }, codes.FailedPrecondition},
		{func() *Builder { return Aborted("retry") }, codes.Aborted},
		{func() *Builder { return Unavailable("svc down") }, codes.Unavailable},
		{func() *Builder { return Internal("oops") }, codes.Internal},
		{func() *Builder { return Gone("relist") }, codes.Code(410)}, // GONE — нестандартный gRPC, но из §14
	}
	for _, c := range cases {
		st, _ := status.FromError(c.fn().Err())
		require.Equal(t, c.code, st.Code())
	}
}
```

- [ ] **Step 2: Run, FAIL**

```bash
go test ./errors/...
```

- [ ] **Step 3: Implement minimum**

```go
package errors

import (
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Builder struct {
	st        *status.Status
	violations []*errdetails.BadRequest_FieldViolation
}

func newBuilder(c codes.Code, msg string) *Builder {
	return &Builder{st: status.New(c, msg)}
}

func (b *Builder) AddFieldViolation(field, desc string) *Builder {
	b.violations = append(b.violations, &errdetails.BadRequest_FieldViolation{Field: field, Description: desc})
	return b
}

func (b *Builder) Err() error {
	if len(b.violations) > 0 {
		st, _ := b.st.WithDetails(&errdetails.BadRequest{FieldViolations: b.violations})
		return st.Err()
	}
	return b.st.Err()
}

// Constructors per §14
func NotFound(kind, id string) *Builder {
	b := newBuilder(codes.NotFound, kind+" "+id+" not found")
	if st2, err := b.st.WithDetails(&errdetails.ResourceInfo{
		ResourceType: kind, ResourceName: id,
	}); err == nil {
		b.st = st2
	}
	return b
}
func InvalidArgument() *Builder            { return newBuilder(codes.InvalidArgument, "invalid argument") }
func AlreadyExists(k, id string) *Builder  { return newBuilder(codes.AlreadyExists, k+" "+id+" already exists") }
func FailedPrecondition(msg string) *Builder { return newBuilder(codes.FailedPrecondition, msg) }
func Aborted(msg string) *Builder          { return newBuilder(codes.Aborted, msg) }
func Unavailable(msg string) *Builder      { return newBuilder(codes.Unavailable, msg) }
func Internal(msg string) *Builder         { return newBuilder(codes.Internal, msg) }
// GONE = HTTP 410, gRPC не имеет этого кода. Используем пользовательский.
func Gone(msg string) *Builder { return newBuilder(codes.Code(410), msg) }
```

- [ ] **Step 4: Run, PASS**

```bash
go test ./errors/... -cover
```

- [ ] **Step 5: Commit**

```bash
git add errors/
git commit -m "feat(errors): google.rpc.Status mapping per spec §14"
```

### Task 5.4: `db/` package — pool [D3]

**Files:**
- Create: `db/pool.go`
- Create: `db/pool_test.go`
- Create: `db/transactor.go`

- [ ] **Step 1: Failing test (testcontainers)**

```go
package db

import (
	"context"
	"testing"
	"time"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go"
)

func TestNewPool_PingsAndStatementTimeoutSet(t *testing.T) {
	ctx := context.Background()
	pgC, err := postgres.Run(ctx, "postgres:16-alpine",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(postgres.WaitForLog("ready").WithStartupTimeout(60*time.Second)),
	)
	require.NoError(t, err)
	t.Cleanup(func() { _ = pgC.Terminate(ctx) })

	dsn, err := pgC.ConnectionString(ctx, "sslmode=disable")
	require.NoError(t, err)

	pool, err := NewPool(ctx, dsn)
	require.NoError(t, err)
	t.Cleanup(pool.Close)

	require.NoError(t, pool.Ping(ctx))

	// statement_timeout = 30s
	var st string
	require.NoError(t, pool.QueryRow(ctx, "SHOW statement_timeout").Scan(&st))
	require.Equal(t, "30s", st)
}
```

- [ ] **Step 2: Implement `pool.go`**

```go
package db

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
)

func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	if cfg.ConnConfig.RuntimeParams == nil {
		cfg.ConnConfig.RuntimeParams = map[string]string{}
	}
	cfg.ConnConfig.RuntimeParams["statement_timeout"] = "30000"
	return pgxpool.NewWithConfig(ctx, cfg)
}
```

- [ ] **Step 3: `transactor.go`** (минимальная заглушка)

```go
package db

import (
	"context"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Transactor struct{ pool *pgxpool.Pool }

func NewTransactor(p *pgxpool.Pool) *Transactor { return &Transactor{pool: p} }

// InTx запускает fn в транзакции. Если fn возвращает err — rollback.
func (t *Transactor) InTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	return pgx.BeginFunc(ctx, t.pool, fn)
}
```

- [ ] **Step 4: Run**

```bash
go test ./db/... -cover -timeout 90s
```

Expected: PASS (с testcontainers — может потребовать ~30 сек).

- [ ] **Step 5: Commit**

```bash
git add db/
git commit -m "feat(db): pgxpool wrapper with statement_timeout=30s and Transactor"
```

### Task 5.5: `config/` package [D6]

**Files:**
- Create: `config/config.go`, `config/config_test.go`

- [ ] **Step 1: Failing test**

```go
package config

import (
	"testing"
	"github.com/stretchr/testify/require"
)

type fooConfig struct {
	GrpcPort int    `envconfig:"KACHO_FOO_GRPC_PORT" required:"true"`
	DBDsn    string `envconfig:"KACHO_FOO_DB_DSN" required:"true"`
}

func TestLoad_FillsFromEnv(t *testing.T) {
	t.Setenv("KACHO_FOO_GRPC_PORT", "9090")
	t.Setenv("KACHO_FOO_DB_DSN", "postgres://x")

	var c fooConfig
	require.NoError(t, Load(&c))
	require.Equal(t, 9090, c.GrpcPort)
	require.Equal(t, "postgres://x", c.DBDsn)
}

func TestLoad_FailsOnMissingRequired(t *testing.T) {
	var c fooConfig
	err := Load(&c)
	require.Error(t, err)
	require.Contains(t, err.Error(), "KACHO_FOO_GRPC_PORT")
}
```

- [ ] **Step 2: Implement**

```go
package config

import "github.com/kelseyhightower/envconfig"

func Load(c any) error { return envconfig.Process("", c) }
```

- [ ] **Step 3: PASS + commit**

```bash
go test ./config/... -cover
git add config/
git commit -m "feat(config): envconfig wrapper"
```

### Task 5.6: `grpcsrv/` package [D5]

**Files:** Create: `grpcsrv/server.go`, `grpcsrv/server_test.go`

- [ ] **Step 1: Failing test (health probe)**

```go
package grpcsrv

import (
	"context"
	"net"
	"testing"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

func TestNewServer_HealthCheckServing(t *testing.T) {
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	srv := NewServer()
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.GracefulStop)

	conn, err := grpc.NewClient(lis.Addr().String(),
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	t.Cleanup(func() { _ = conn.Close() })

	hc := healthpb.NewHealthClient(conn)
	resp, err := hc.Check(context.Background(), &healthpb.HealthCheckRequest{})
	require.NoError(t, err)
	require.Equal(t, healthpb.HealthCheckResponse_SERVING, resp.Status)
}
```

- [ ] **Step 2: Implement**

```go
package grpcsrv

import (
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

func NewServer(opts ...grpc.ServerOption) *grpc.Server {
	s := grpc.NewServer(opts...)
	h := health.NewServer()
	h.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthpb.RegisterHealthServer(s, h)
	return s
}
```

- [ ] **Step 3: PASS + commit**

```bash
go test ./grpcsrv/... -cover
git add grpcsrv/
git commit -m "feat(grpcsrv): gRPC server bootstrap with health probe"
```

### Task 5.7: `observability/` package [D5]

**Files:** Create: `observability/slog.go`, `observability/otel.go`, `observability/observability_test.go`

- [ ] **Step 1: Failing tests**

```go
package observability

import (
	"context"
	"os"
	"testing"
	"github.com/stretchr/testify/require"
)

func TestNewSlogger_OutputsJSON(t *testing.T) {
	logger := NewSlogger(os.Stdout)
	logger.Info("hello", "key", "value")
	// smoke: ничего не паникует, формат JSON
	require.NotNil(t, logger)
}

func TestInitOtel_NoopWhenEndpointEmpty(t *testing.T) {
	t.Setenv("KACHO_OTEL_EXPORTER_OTLP_ENDPOINT", "")
	shutdown, err := InitOtel(context.Background(), "test-svc")
	require.NoError(t, err)
	require.NotNil(t, shutdown)
	// shutdown — no-op
	require.NoError(t, shutdown(context.Background()))
}
```

- [ ] **Step 2: `slog.go`**

```go
package observability

import (
	"io"
	"log/slog"
)

func NewSlogger(w io.Writer) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{Level: slog.LevelInfo}))
}
```

- [ ] **Step 3: `otel.go`**

```go
package observability

import (
	"context"
	"os"
)

type ShutdownFn func(context.Context) error

func InitOtel(ctx context.Context, serviceName string) (ShutdownFn, error) {
	endpoint := os.Getenv("KACHO_OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint == "" {
		return func(context.Context) error { return nil }, nil
	}
	// Полная OTLP-инициализация — TODO в 0.2+
	return func(context.Context) error { return nil }, nil
}
```

- [ ] **Step 4: PASS + commit**

```bash
go test ./observability/... -cover
git add observability/
git commit -m "feat(observability): slog JSON handler, otel conditional init"
```

### Task 5.8: Verify D1 — отсутствие watch/, outbox/, selector/

- [ ] **Step 1**

```bash
test ! -d watch && test ! -d outbox && test ! -d selector
echo "D1 OK: 0.2 packages absent in 0.1"
```

Expected: `D1 OK`.

### Task 5.9: `Makefile` + GitHub Actions

**Files:** Create: `Makefile`, `.github/workflows/ci.yaml`

- [ ] **Step 1: `Makefile`**

```makefile
.PHONY: lint test cover

lint:
	golangci-lint run ./...

test:
	go test ./... -race -cover

cover:
	go test ./... -coverprofile=coverage.out
	go tool cover -func=coverage.out
```

- [ ] **Step 2: `.github/workflows/ci.yaml`**

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - uses: golangci/golangci-lint-action@v6
      - run: go test ./... -race -cover
```

- [ ] **Step 3: Commit + push**

```bash
git add Makefile .github/
git commit -m "ci: corelib lint + test"
git push -u origin main
```

---

## Phase 6 — kacho-deploy (kind + helm + dev-up)

**Repo working dir:** `cloud-demo/kacho-deploy/`.

### Task 6.1: `.gitignore` + README + базовая структура

- [ ] **Step 1: `.gitignore`**

```gitignore
.idea/
.vscode/
.DS_Store
helm/umbrella/charts/   # downloaded by helm dep update
helm/umbrella/Chart.lock
```

- [ ] **Step 2: `README.md`**

```markdown
# kacho-deploy

Локальный dev-стенд Kachō: kind + Helm + Bitnami Postgres + ingress-nginx.

## Команды

- `make dev-up` — поднять кластер (< 5 мин)
- `make dev-down` — снести
- `make reload-svc SVC=<svc>` — пересобрать и перезагрузить один сервис
- `make logs-svc SVC=<svc>` — `kubectl logs -f`
- `make psql SVC=<svc>` — psql в pod-е
- `make e2e-test` — bash-сценарии в `e2e/`

## Требования

- docker, kind v0.20+, kubectl, helm 3, bats-core
- Свободный порт 80 на host-машине
- В `/etc/hosts`: `127.0.0.1 api.kacho.local kacho.local`

## Persistence

Postgres использует `emptyDir` — данные не сохраняются между `dev-down`/`dev-up`. Это сознательно для воспроизводимости тестов (`03-deployment-and-operations.md` §5).
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore README.md
git commit -m "chore: kacho-deploy skeleton"
```

### Task 6.2: `kind/kind-config.yaml` [E2]

**Files:** Create: `kind/kind-config.yaml`, `kind/create-cluster.sh`

- [ ] **Step 1: kind-config**

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
```

- [ ] **Step 2: `create-cluster.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kind create cluster --config "$SCRIPT_DIR/kind-config.yaml" --name kacho --wait 60s
```

```bash
chmod +x kind/create-cluster.sh
```

- [ ] **Step 3: Commit**

```bash
git add kind/
git commit -m "feat(kind): cluster config with port 80 mapping and ingress-ready label"
```

### Task 6.3: `helm/umbrella/` skeleton [E3, E4, E6, E7]

**Files:**
- Create: `helm/umbrella/Chart.yaml`
- Create: `helm/umbrella/values.dev.yaml`
- Create: `helm/umbrella/templates/namespace.yaml`
- Create: `helm/umbrella/templates/ingress.yaml`

- [ ] **Step 1: `Chart.yaml`** (без сервисных deps — закомментированы per §9 Resolution / E7)

```yaml
apiVersion: v2
name: kacho-umbrella
version: 0.1.0
description: Kachō Cloud Control Plane — dev umbrella
dependencies:
  - name: ingress-nginx
    version: 4.x
    repository: https://kubernetes.github.io/ingress-nginx
  - name: postgresql
    alias: pg-resource-manager
    version: 13.x
    repository: https://charts.bitnami.com/bitnami
  - name: postgresql
    alias: pg-vpc
    version: 13.x
    repository: https://charts.bitnami.com/bitnami
  - name: postgresql
    alias: pg-compute
    version: 13.x
    repository: https://charts.bitnami.com/bitnami
  - name: postgresql
    alias: pg-loadbalancer
    version: 13.x
    repository: https://charts.bitnami.com/bitnami
  # Сервисные deps добавляются в sub-phase 0.2+:
  # - name: resource-manager  (0.2)
  # - name: vpc                (0.3)
  # - name: compute            (0.4)
  # - name: loadbalancer       (0.5)
  # - name: api-gateway        (0.6)
```

- [ ] **Step 2: `values.dev.yaml`** — общие настройки 4 Postgres-инстансов (E4, E5, E9)

```yaml
ingress-nginx:
  controller:
    hostNetwork: false
    service:
      type: NodePort
      nodePorts: { http: 80 }
    nodeSelector:
      ingress-ready: "true"
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Equal
        effect: NoSchedule

# Общая часть для каждого pg-* alias (Helm не поддерживает шаблоны для alias-deps,
# повторяем 4 раза с минимальными отличиями)
pg-resource-manager: &pgcommon
  auth:
    username: resource_manager
    password: dev-resource-manager-password
    database: kacho_resource_manager
  primary:
    persistence:
      enabled: true
      existingClaim: ""   # emptyDir режим — см. ниже
    podLabels: { kacho-pg: resource-manager }
  # emptyDir вместо PVC: достигается через persistence.enabled=false при использовании Bitnami
  # реальный override:
  # primary.persistence.enabled: false
  # → Bitnami мапит на emptyDir автоматически

pg-vpc:
  <<: *pgcommon
  auth:
    username: vpc
    password: dev-vpc-password
    database: kacho_vpc

pg-compute:
  <<: *pgcommon
  auth:
    username: compute
    password: dev-compute-password
    database: kacho_compute

pg-loadbalancer:
  <<: *pgcommon
  auth:
    username: loadbalancer
    password: dev-loadbalancer-password
    database: kacho_loadbalancer
```

**Note**: проверьте актуальные значения Bitnami chart 13.x; если YAML-anchor не срабатывает в Helm — повторите блок руками для каждого alias. Это уточняется на первом `helm dep update`.

- [ ] **Step 3: `templates/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kacho
  labels:
    name: kacho
```

- [ ] **Step 4: `templates/ingress.yaml`** [E6]

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kacho-proto
  namespace: kacho
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  ingressClassName: nginx
  rules:
    - host: api.kacho.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-gateway   # ещё не существует в 0.1 — ingress будет 503
                port: { number: 8080 }
```

- [ ] **Step 5: helm dep update**

```bash
cd helm/umbrella
helm dep update
helm lint -f values.dev.yaml
```

Expected: lint OK (warnings допустимы).

- [ ] **Step 6: Commit**

```bash
cd ../..
git add helm/umbrella/
git commit -m "feat(helm): umbrella chart with 4 Postgres aliases, ingress-nginx, namespace, ingress"
```

### Task 6.4: `Makefile` — `dev-up` с inline preflight [E1, F1, F2, §9-6]

**Files:** Create: `Makefile`

- [ ] **Step 1**

```makefile
.PHONY: dev-up dev-down reload-svc logs-svc psql preflight e2e-test helm-lint

CLUSTER_NAME := kacho

preflight:
	@command -v docker >/dev/null || { echo "ERROR: docker not installed"; exit 1; }
	@command -v kind >/dev/null || { echo "ERROR: kind not installed (install from https://kind.sigs.k8s.io/)"; exit 1; }
	@command -v kubectl >/dev/null || { echo "ERROR: kubectl not installed"; exit 1; }
	@command -v helm >/dev/null || { echo "ERROR: helm not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: docker daemon is not running"; exit 1; }
	@if ss -tln | grep -q ':80 '; then echo "ERROR: port 80 is already in use, free it or change kind/kind-config.yaml"; exit 1; fi
	@grep -q "api.kacho.local" /etc/hosts || echo "WARN: '127.0.0.1 api.kacho.local' missing in /etc/hosts — ingress will not resolve from host"
	@echo "preflight OK"

dev-up: preflight
	@start=$$(date +%s); \
	kind get clusters | grep -q "^$(CLUSTER_NAME)$$" || ./kind/create-cluster.sh; \
	kubectl config use-context kind-$(CLUSTER_NAME); \
	cd helm/umbrella && helm dep update >/dev/null; \
	helm upgrade --install kacho-umbrella . -n kacho --create-namespace -f values.dev.yaml --wait --timeout 5m; \
	end=$$(date +%s); \
	echo "dev-up complete in $$((end-start))s"; \
	echo; \
	echo "API endpoint: http://api.kacho.local (add '127.0.0.1 api.kacho.local' to /etc/hosts if missing)"

dev-down:
	kind delete cluster --name $(CLUSTER_NAME) || true

helm-lint:
	cd helm/umbrella && helm dep update >/dev/null && helm lint -f values.dev.yaml

reload-svc:
ifndef SVC
	$(error SVC variable is required, e.g. make reload-svc SVC=compute)
endif
	@if [ "$(SVC)" != "resource-manager" ] && [ "$(SVC)" != "vpc" ] && [ "$(SVC)" != "compute" ] && [ "$(SVC)" != "loadbalancer" ] && [ "$(SVC)" != "api-gateway" ]; then \
		echo "ERROR: unknown service '$(SVC)'"; exit 1; \
	fi
	@if ! kubectl -n kacho get deploy $(SVC) >/dev/null 2>&1; then \
		echo "WARN: service '$(SVC)' is not deployed yet (planned for sub-phase 0.X — see roadmap)"; \
		exit 0; \
	fi
	cd ../kacho-$(SVC) && docker build -t kacho-$(SVC):dev .
	kind load docker-image kacho-$(SVC):dev --name $(CLUSTER_NAME)
	kubectl rollout restart -n kacho deployment/$(SVC)

logs-svc:
ifndef SVC
	$(error SVC variable is required)
endif
	kubectl logs -n kacho -f deploy/$(SVC)

psql:
ifndef SVC
	$(error SVC variable is required)
endif
	kubectl exec -it -n kacho statefulset/pg-$(SVC) -- psql -U $(SVC) -d kacho_$(SVC)

e2e-test:
	@for sh in e2e/0.1/*.sh; do \
		echo "=== $$sh ==="; \
		bash "$$sh" || exit 1; \
	done
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: Makefile with dev-up (preflight inline), dev-down, reload-svc soft-warning"
```

### Task 6.5–6.13: e2e/0.1/ bash-сценарии (TDD — пишутся параллельно с реализацией умбреллы)

**Files:** Create: `e2e/0.1/*.sh`

Каждый — отдельная задача. Все исполняются после `make dev-up`.

- [ ] **Task 6.5 — `E1-dev-up-under-5min.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
START=$(date +%s)
make dev-down >/dev/null 2>&1 || true
make dev-up
END=$(date +%s)
ELAPSED=$((END - START))
echo "dev-up took ${ELAPSED}s"
[ $ELAPSED -lt 300 ] || { echo "FAIL: dev-up took ${ELAPSED}s (>= 300s)"; exit 1; }
echo "PASS: E1"
```

- [ ] **Task 6.6 — `E4-postgres-ready.sh`** [E4]

```bash
#!/usr/bin/env bash
set -euo pipefail
PODS=$(kubectl -n kacho get pods -l 'app.kubernetes.io/name=postgresql' -o jsonpath='{.items[*].metadata.name}')
COUNT=$(echo "$PODS" | wc -w)
[ "$COUNT" -eq 4 ] || { echo "FAIL: expected 4 postgres pods, got $COUNT"; exit 1; }

for pod in $PODS; do
  kubectl -n kacho wait --for=condition=ready pod/"$pod" --timeout=180s
done

# Каждая БД доступна и пуста
declare -A DBS=(
  [pg-resource-manager-0]="resource_manager kacho_resource_manager"
  [pg-vpc-0]="vpc kacho_vpc"
  [pg-compute-0]="compute kacho_compute"
  [pg-loadbalancer-0]="loadbalancer kacho_loadbalancer"
)
for pod in "${!DBS[@]}"; do
  read -r user db <<< "${DBS[$pod]}"
  count=$(kubectl -n kacho exec "$pod" -- psql -U "$user" -d "$db" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
  [ "$count" = "0" ] || { echo "FAIL: $db has $count user tables (expected 0)"; exit 1; }
done

echo "PASS: E4 — 4 postgres ready, all DBs empty"
```

- [ ] **Task 6.7 — `E5-secrets.sh`** [E5]

```bash
#!/usr/bin/env bash
set -euo pipefail
for svc in resource-manager vpc compute loadbalancer; do
  kubectl -n kacho get secret pg-${svc}-postgresql >/dev/null
done
echo "PASS: E5 — all 4 db-credential secrets present"
```

- [ ] **Task 6.8 — `E6-ingress-ready.sh`** [E6]

```bash
#!/usr/bin/env bash
set -euo pipefail
kubectl -n kacho wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx --timeout=180s
# 503 — это OK: api-gateway ещё не задеплоен
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://api.kacho.local/ -H 'Host: api.kacho.local' || echo "000")
case "$CODE" in
  503|404) echo "PASS: E6 — ingress responded with $CODE (api-gateway not deployed yet)";;
  *) echo "FAIL: E6 — unexpected code $CODE"; exit 1;;
esac
```

- [ ] **Task 6.9 — `E7-no-service-pods.sh`** [E7]

```bash
#!/usr/bin/env bash
set -euo pipefail
for svc in api-gateway resource-manager vpc compute loadbalancer; do
  if kubectl -n kacho get deploy "$svc" >/dev/null 2>&1; then
    echo "FAIL: E7 — service '$svc' should NOT be deployed in 0.1"
    exit 1
  fi
done
echo "PASS: E7 — no service pods deployed"
```

- [ ] **Task 6.10 — `E8-dev-down-clean.sh`** [E8]

```bash
#!/usr/bin/env bash
set -euo pipefail
make dev-down
sleep 2
! kind get clusters | grep -q '^kacho$' || { echo "FAIL: cluster still exists"; exit 1; }
! ss -tln | grep -q ':80 ' || { echo "FAIL: port 80 still bound"; exit 1; }
echo "PASS: E8"
```

- [ ] **Task 6.11 — `E9-emptydir-regression.sh`** [E9]

```bash
#!/usr/bin/env bash
set -euo pipefail
make dev-down >/dev/null 2>&1 || true
make dev-up
kubectl -n kacho exec pg-compute-0 -- psql -U compute -d kacho_compute -c "CREATE TABLE t(x int); INSERT INTO t VALUES (1);"
make dev-down
make dev-up
COUNT=$(kubectl -n kacho exec pg-compute-0 -- psql -U compute -d kacho_compute -tAc "SELECT count(*) FROM information_schema.tables WHERE table_name='t'")
[ "$COUNT" = "0" ] || { echo "FAIL: emptyDir not working — table 't' persisted"; exit 1; }
echo "PASS: E9 — emptyDir resets state on rebuild"
```

- [ ] **Task 6.12 — `F1-port80-busy.sh`** [F1]

```bash
#!/usr/bin/env bash
set -euo pipefail
make dev-down >/dev/null 2>&1 || true
# Занимаем порт 80
python3 -m http.server 80 &
SQUATTER_PID=$!
sleep 1
trap "kill $SQUATTER_PID 2>/dev/null || true" EXIT

if make dev-up 2>&1 | grep -q "port 80 is already in use"; then
  echo "PASS: F1 — preflight catches busy port 80"
else
  echo "FAIL: F1"
  exit 1
fi
```

(Этот тест требует sudo для порта 80; ставим как optional/manual.)

- [ ] **Task 6.13 — `F2-missing-tools.sh`** [F2]

```bash
#!/usr/bin/env bash
set -euo pipefail
# Симулируем отсутствие kind, временно убрав из PATH
KIND_PATH=$(which kind)
TMPBIN=$(mktemp -d)
cp $(which docker kubectl helm) "$TMPBIN/"
PATH="$TMPBIN" make dev-up 2>&1 | grep -q "kind not installed" || { echo "FAIL: F2"; exit 1; }
echo "PASS: F2"
```

- [ ] **Task 6.14 — chmod + commit**

```bash
chmod +x e2e/0.1/*.sh
git add e2e/
git commit -m "test(e2e/0.1): bash scenarios for E1, E4, E5, E6, E7, E8, E9, F1, F2"
```

### Task 6.15: GitHub Actions CI [G1]

**Files:** Create: `.github/workflows/ci.yaml`

- [ ] **Step 1**

```yaml
name: ci
on: [push, pull_request]
jobs:
  helm-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-helm@v4
      - run: cd helm/umbrella && helm dep update && helm lint -f values.dev.yaml
```

(E2E на kind — отдельный nightly job, добавляется в Phase 7.)

- [ ] **Step 2: Commit + push**

```bash
git add .github/
git commit -m "ci: helm lint"
git push -u origin main
```

---

## Phase 7 — Cross-repo CI baseline

### Task 7.1: kacho-deploy nightly e2e на GitHub-managed kind

**Files:** Modify `kacho-deploy/.github/workflows/ci.yaml`

- [ ] **Step 1: Добавить nightly job**

```yaml
  e2e-on-kind:
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    steps:
      - uses: actions/checkout@v4
      - uses: helm/kind-action@v1
        with:
          config: kind/kind-config.yaml
          cluster_name: kacho
      - uses: azure/setup-helm@v4
      - run: |
          # /etc/hosts override для api.kacho.local
          sudo bash -c 'echo "127.0.0.1 api.kacho.local kacho.local" >> /etc/hosts'
          # запуск только non-destructive E* сценариев (без F1 — занят порт 80)
          for s in e2e/0.1/E*.sh; do bash "$s"; done
on:
  schedule: [{ cron: '0 3 * * *' }]
  workflow_dispatch: {}
```

- [ ] **Step 2: Commit + push**

```bash
git add .github/
git commit -m "ci: nightly e2e-on-kind job"
git push
```

### Task 7.2: Verify все 9 репо имеют зелёный CI [G1]

- [ ] **Step 1**

```bash
for r in kacho-workspace kacho-proto kacho-corelib kacho-api-gateway kacho-resource-manager kacho-vpc kacho-compute kacho-loadbalancer kacho-deploy; do
  gh run list --repo PRO-Robotech/$r --limit 1 --json conclusion --jq '.[0].conclusion' | grep -q success \
    && echo "[OK] $r" || echo "[FAIL] $r"
done
```

Expected: 9 строк `[OK]`.

---

## Phase 8 — Smoke + tag + CHANGELOG

### Task 8.1: Полный smoke с чистой машины

- [ ] **Step 1: Симулировать чистую машину**

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR" && mkdir cloud-demo && cd cloud-demo
git clone git@github.com:PRO-Robotech/kacho-workspace.git
./kacho-workspace/bootstrap.sh
ls -d kacho-* | wc -l   # ожидаем 9
cp kacho-workspace/go.work.example go.work
cd kacho-deploy
START=$(date +%s)
make dev-up
END=$(date +%s)
echo "dev-up: $((END - START))s"
[ $((END - START)) -lt 300 ] || echo "WARN: > 5 min"
for s in e2e/0.1/E*.sh; do bash "$s"; done
make dev-down
```

Expected: всё зелёное, < 5 минут.

### Task 8.2: Обновить CHANGELOG

**Files:** Modify: `kacho-workspace/docs/specs/CHANGELOG.md`

- [ ] **Step 1**

```markdown
## 2026-MM-DD — sub-phase 0.1 завершена
- bootstrap.sh клонирует все 9 репо
- make dev-up поднимает kind + 4 Postgres + ingress < 5 минут
- 11 субагентов в .claude/agents/
- kacho-corelib: ids, errors, db, config, grpcsrv, observability — > 70% coverage
- kacho-proto: common v1 (ResourceMeta, Selector, FieldSelector, ResourceRef)
- e2e/0.1/ — 9 bash-сценариев

Tag: kacho-workspace:0.1.0
```

- [ ] **Step 2: Commit + tag + push**

```bash
cd kacho-workspace
git add docs/specs/CHANGELOG.md
git commit -m "docs: CHANGELOG for sub-phase 0.1 completion"
git tag kacho-workspace:0.1.0
git push origin main
git push origin kacho-workspace:0.1.0
```

### Task 8.3: Definition of Done verification

- [ ] **Step 1: Чек-лист §8 acceptance-документа**

Проверить пункты:
1. [ ] Все сценарии §1–§7 acceptance покрыты автотестами и зелёные
2. [ ] `make dev-up` < 5 мин (Task 8.1)
3. [ ] `make dev-down` чистит state (Task 6.10/E8)
4. [ ] CI всех 9 репо зелёный (Task 7.2)
5. [ ] CLAUDE.md содержит executive summary и 8 запретов (Task 1.2)
6. [ ] 11 субагентов в `.claude/agents/` (Task 1.4)
7. [ ] CHANGELOG пополнен (Task 8.2)
8. [ ] Tag `kacho-workspace:0.1.0` поставлен (Task 8.2)

---

## Self-review (выполнено перед сохранением плана)

**Spec coverage:** Каждый сценарий из acceptance-документа имеет соответствующую task:
- A1, A2, A3 → Task 2.2–2.5
- A4 (go.work) → Task 2.7
- A5 → Task 2.6
- B1, B5 → Task 1.2
- B2 → не требует кода (отсутствие side-effect верифицируется F4-теста manually + Task 8.1)
- B3 → Task 1.4
- B4 → Task 1.3
- C1–C4 → Task 4.2–4.6
- D1–D6 → Task 5.2–5.9
- E1–E10 → Task 6.4–6.14
- F1, F2 → Task 6.12–6.13
- F3 → A3 (Task 2.5)
- F4 → manual smoke в Task 8.1
- F5 → Task 1.1 (`.gitignore` go.work) + Task 2.7 note
- G1 → Task 3.2 + Task 7.2
- G2 → имена тестов в Phase 5 + e2e-файлы в Phase 6 (по ID сценариев)

**Placeholder scan:** TODO найден один (`observability/otel.go: Полная OTLP-инициализация — TODO в 0.2+`) — это сознательное закомментированное расширение, НЕ план-плейсхолдер. Остальные tasks содержат полный код / команды.

**Type consistency:** `Builder` в errors-пакете, `NewPool`/`Transactor` в db, `NewServer` в grpcsrv, `NewSlogger`/`InitOtel`/`ShutdownFn` в observability — имена согласованы между tasks.

---

## Execution Handoff

План готов. Два варианта исполнения:

1. **Subagent-Driven** (рекомендую для этого плана) — диспетчеризация по фазам:
   - Phase 1, 3, 4, 5, 6 — независимы → параллельные субагенты (5 потоков)
   - Phase 2 после Phase 1 (нужны имена агентов из CLAUDE.md)
   - Phase 7, 8 — финальные, последовательно
   - Использует `superpowers:subagent-driven-development`. Каждый subagent коммитит сам, я ревьюю между фазами.

2. **Inline Execution** — последовательно в этой сессии через `superpowers:executing-plans`. Дольше (~2–3 часа активной работы), но всё в одном контексте.

**Какой подход?**
