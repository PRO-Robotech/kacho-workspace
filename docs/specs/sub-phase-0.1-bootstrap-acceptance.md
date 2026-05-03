# Sub-phase 0.1 (Bootstrap) — Acceptance

**Документ:** acceptance / sub-phase 0.1
**Дата:** 2026-05-03
**Статус:** Draft, для утверждения заказчиком
**Источник требований:** `04-roadmap-and-phasing.md` §3 «Sub-итерация 0.1 — Bootstrap», `03-deployment-and-operations.md` §1–§11, `00-overview-and-scope.md` §4.8.
**Утверждение:** только после approve этого документа разрешено приступать к написанию плана и кода (см. `04-roadmap-and-phasing.md` §2, шаг 2 → шаг 3).

---

## 0. Цель sub-итерации (1 абзац для контекста)

Подготовить «пустой каркас» платформы Kachō: разработчик с чистой машины должен за один скрипт получить рабочее workspace из polyrepo-структуры (`kacho-workspace`, `kacho-api`, `kacho-corelib`, `kacho-deploy` и заглушки сервисных репо), а одной make-командой — поднять локальный kind-кластер с ingress и четырьмя пустыми Postgres-инстансами (БД созданы, схем ещё нет). Никакой бизнес-логики ресурсов (Org/Cloud/Folder/Network/Instance/...) в этой sub-итерации не реализуется — это произойдёт в 0.2+. Здесь же фиксируется CLAUDE.md-иерархия и набор из 11 кастомных субагентов (`acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`, `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`).

**Что НЕ входит в 0.1** (явно отложено):
- `kacho-corelib/watch/` и `kacho-corelib/outbox/` — sub-phase 0.2.
- `kacho-corelib/selector/` — sub-phase 0.2.
- Любые proto-файлы конкретных доменов (`resourcemanager`, `vpc`, `compute`, `loadbalancer`) — каркасные доменные пакеты появляются в 0.2–0.5.
- Сервисные репо (`kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`) — клонируются как пустые заглушки (только `README.md` + `.gitignore`); реализация в 0.2+.

---

## 1. Группа A — Bootstrap polyrepo workspace

### A1. Чистый bootstrap на пустой машине

**Given** разработчик находится в пустой директории `cloud-demo/`
**And** у разработчика есть SSH-ключ, добавленный в `github.com/PRO-Robotech`
**And** установлены `git`, `bash` (или `zsh`), `make`

**When** разработчик выполняет:
```bash
cd cloud-demo
git clone git@github.com:PRO-Robotech/kacho-workspace.git
./kacho-workspace/bootstrap.sh
```

**Then** в `cloud-demo/` появляются siblings-директории всех репо из таблицы §1 документа `03-deployment-and-operations.md`:
- `kacho-workspace/` (склонирован вручную)
- `kacho-api/`
- `kacho-corelib/`
- `kacho-api-gateway/`
- `kacho-resource-manager/`
- `kacho-vpc/`
- `kacho-compute/`
- `kacho-loadbalancer/`
- `kacho-deploy/`

**And** каждая директория является валидным git-репозиторием с `origin = git@github.com:PRO-Robotech/<repo>.git`
**And** код выхода скрипта = 0
**And** скрипт печатает на stdout инструкцию о следующем шаге («скопируйте `kacho-workspace/go.work.example` в `cloud-demo/go.work`»)
**And** `~/.claude/CLAUDE.md` остаётся неизменённым (хеш файла до и после bootstrap совпадает)
**And** содержимое `~/.claude/` (других файлов) не модифицировано.

### A2. Идемпотентный повторный запуск

**Given** все репо из A1 уже склонированы и в части из них есть локальные коммиты или uncommitted изменения

**When** разработчик повторно запускает `./kacho-workspace/bootstrap.sh`

**Then** скрипт **не пытается** делать `git clone` поверх существующих директорий
**And** скрипт **не делает** `git pull`/`git fetch` без явного флага (uncommitted-изменения и текущая ветка пользователя сохраняются)
**And** скрипт сообщает «X repos already present, skipping clone» и завершается с кодом 0
**And** ни один локальный коммит и ни одно untracked-изменение в дочерних репо не теряется.

### A3. Bootstrap при недоступном GitHub

**Given** один из репо (например, `kacho-loadbalancer`) ещё не создан в `github.com/PRO-Robotech`, либо у разработчика нет к нему доступа

**When** разработчик запускает `./kacho-workspace/bootstrap.sh`

**Then** скрипт печатает осмысленное сообщение об ошибке вида `failed to clone kacho-loadbalancer: <git stderr>`
**And** код выхода ≠ 0
**And** уже успешно склонированные репо остаются на диске (не удаляются)
**And** сообщение содержит подсказку: проверить SSH-ключ и доступ к GitHub-org `PRO-Robotech`.

### A4. `go.work` подключение

**Given** все репо склонированы согласно A1
**And** `cloud-demo/go.work` отсутствует

**When** разработчик выполняет `cp kacho-workspace/go.work.example cloud-demo/go.work`

**Then** в `cloud-demo/go.work` присутствует `use` для всех Go-репо: `kacho-api`, `kacho-corelib`, `kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`
**And** запуск `go work sync` в `cloud-demo/` завершается без ошибок
**And** `cloud-demo/go.work` **отсутствует** в `.gitignore` ни одного из дочерних репо, но **присутствует** локально и не коммитится (это локальный артефакт, см. `03-deployment-and-operations.md` §2.1).

### A5. `sync-all.sh` — обновление всех репо

**Given** все репо склонированы и находятся на ветке `main`
**And** в каждом репо `git status` чистый

**When** разработчик запускает `./kacho-workspace/sync-all.sh`

**Then** скрипт делает `git fetch && git pull --ff-only` в каждом репо
**And** при невозможности fast-forward (локальные расхождения) — печатает имя репо и пропускает его без модификации
**And** итоговый отчёт содержит per-repo статус (`up-to-date`, `updated to <sha>`, `skipped: not fast-forward`).

---

## 2. Группа B — CLAUDE.md-иерархия и subagents

### B1. Workspace-CLAUDE.md виден из любой подпапки `cloud-demo/`

**Given** workspace bootstrap-нут согласно A1
**And** `kacho-workspace/CLAUDE.md` существует и содержит executive summary спеки + запреты из `03-deployment-and-operations.md` §11

**When** разработчик запускает новый chat Claude Code в:
- `cloud-demo/`
- `cloud-demo/kacho-compute/`
- `cloud-demo/kacho-deploy/helm/umbrella/`

**Then** в каждом из этих случаев Claude Code загружает `kacho-workspace/CLAUDE.md` как часть контекста
**And** запреты из §11 (`НЕ упоминать yandex`, `НЕ ORM`, `НЕ редактировать применённые миграции`, `НЕ писать в status через /upsert`, `НЕ маршрутизировать Internal.* через api-gateway`, `НЕ вводить broker`, `НЕ создавать единые БД`) видны ассистенту.

### B2. `~/.claude/CLAUDE.md` не модифицируется bootstrap-ом

**Given** существует `~/.claude/CLAUDE.md` с пользовательскими предпочтениями (например, language=ru)

**When** разработчик выполняет полный bootstrap (A1) и любой `make`-таргет из `kacho-deploy`

**Then** хеш `~/.claude/CLAUDE.md` до и после совпадает
**And** хеш всех остальных файлов в `~/.claude/` (кроме того, что Claude Code сам пишет в `~/.claude/projects/...`) совпадает.

### B3. 11 кастомных субагентов доступны

**Given** `kacho-workspace/.claude/agents/` существует

**When** разработчик из любой подпапки `cloud-demo/` запускает Claude Code и команду `/agents`

**Then** в списке project-level агентов присутствуют все 11 имён, перечисленных в `03-deployment-and-operations.md` §9.1–§9.2:
- task-execution: `acceptance-author`, `proto-sync`, `service-scaffolder`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`
- specialist-review: `system-design-reviewer`, `db-architect-reviewer`, `go-style-reviewer`, `proto-api-reviewer`

**And** каждый из 11 файлов `kacho-workspace/.claude/agents/<name>.md` имеет YAML-frontmatter с минимум `name`, `description`, и инструкции в теле, соответствующие назначению из §9.1–§9.2.

### B4. `.claude/settings.json` workspace-уровня

**Given** существует `kacho-workspace/.claude/settings.json`

**When** разработчик открывает файл

**Then** содержимое строго соответствует `03-deployment-and-operations.md` §10:
```json
{ "permissions": { "defaultMode": "bypassPermissions" } }
```
**And** файл — валидный JSON
**And** в `.gitignore` workspace-репо отсутствует `settings.json` (он коммитится; `settings.local.json` — наоборот, в gitignore).

### B5. CLAUDE.md упоминает все ключевые конвенции и запреты

**Given** разработчик читает `kacho-workspace/CLAUDE.md`

**When** разработчик ищет ключевые слова

**Then** документ содержит ссылки или дословные упоминания:
- naming convention (`Kachō` / `kacho` / `kacho_<domain>` / `kacho-<part>`)
- ссылку на 5 файлов спеки `docs/specs/00..04`
- все 8 запретов из §11 (`yandex`, ORM, каскад между сервисами, миграции, status-через-upsert, Internal-через-gateway, broker, единые БД)
- обязательность acceptance-документа **до** кодирования (см. `00-overview-and-scope.md` §4.8 и `04-roadmap-and-phasing.md` §2)
- инструкции локальной разработки `make dev-up` / `make reload-svc` / `make logs-svc` / `make psql`.

---

## 3. Группа C — `kacho-api` каркас

### C1. `buf lint` зелёный

**Given** репо `kacho-api/` склонировано
**And** установлен `buf` (версия из `Makefile` или README)

**When** разработчик выполняет `cd kacho-api && make buf-lint` (или `buf lint`)

**Then** код выхода = 0
**And** stdout не содержит warning/error.

### C2. `buf generate` создаёт стабы для common-типов

**Given** в `kacho-api/proto/` присутствуют только common-типы (без доменных сервисов): `ResourceMeta`, `Selector`, `FieldSelector`, `ResourceRef`, и envelope-типы для Watch (`WatchEvent` с `event_type ∈ {ADDED, MODIFIED, DELETED}`)
**And** `kacho-api/buf.yaml` и `kacho-api/buf.gen.yaml` сконфигурированы согласно `02-data-model-and-conventions.md` §13 (proto package = `kacho.cloud.<domain>.v1`, Go-import = `github.com/PRO-Robotech/kacho-api/gen/go/kacho/cloud/<domain>/v1`)

**When** разработчик выполняет `make generate`

**Then** в `kacho-api/gen/go/...` появляются сгенерированные `.pb.go`-файлы для common-типов
**And** сгенерированные файлы коммитятся в репо (committed, см. `03-deployment-and-operations.md` §1)
**And** ни один сгенерированный файл не содержит подстроки `yandex` (case-insensitive grep).

### C3. `buf breaking` сконфигурирован

**Given** `kacho-api/.github/workflows/ci.yaml` или `Makefile` содержит таргет `buf-breaking`

**When** разработчик выполняет `make buf-breaking` против тега `v0.1.0` (или другого baseline)

**Then** на чистом state (без изменений в proto) код выхода = 0
**And** при искусственно сломанном поле в common-типе (например, переименование `ResourceMeta.uid → id`) код выхода ≠ 0 и stdout содержит описание breaking-change-а.

### C4. Common-типы соответствуют спецификации

**Given** сгенерированы Go-стабы из `kacho-api/proto/`

**When** разработчик импортирует пакет в Go-код

**Then** доступны типы:
- `ResourceMeta` с полями `uid`, `name`, `organization_id`, `cloud_id`, `folder_id`, `labels` (map<string,string>), `annotations`, `creation_timestamp`, `resource_version`, `generation`, `deletion_timestamp`, `finalizers` (repeated string), `restarted_at` (см. `02-data-model-and-conventions.md` §2.1)
- `Selector` с `field_selector` + `label_selector`
- `FieldSelector` с `name`, `organization_id`, `cloud_id`, `folder_id`, `refs`
- `ResourceRef` с `name`, `uid`, `kind`
- `WatchEvent` с `event_type` (enum `ADDED|MODIFIED|DELETED`) и `resource_version`.

---

## 4. Группа D — `kacho-corelib` каркас

### D1. Перечень пакетов соответствует scope sub-phase 0.1

**Given** репо `kacho-corelib/` склонировано

**When** разработчик выполняет `ls kacho-corelib/`

**Then** присутствуют директории, перечисленные в `04-roadmap-and-phasing.md` §3 для Bootstrap: `ids/`, `errors/`, `db/`, `config/`, `grpcsrv/`, `observability/`
**And** **отсутствуют** директории `watch/`, `outbox/`, `selector/` (они появятся в 0.2 — фиксируется как явный negative-сценарий, чтобы избежать преждевременной реализации).

### D2. `go test ./...` зелёный

**Given** в каждом из пакетов §D1 есть минимальный набор юнит-тестов (smoke-уровня — например, `ids.NewUID()` возвращает валидный UUIDv4, `errors.FromCode(codes.NotFound)` возвращает `*status.Status` с правильным `code`)

**When** разработчик выполняет `cd kacho-corelib && go test ./...`

**Then** код выхода = 0
**And** все юнит-тесты зелёные
**And** покрытия (`-cover`) для каждого пакета ≥ 70 % (нижняя планка для skeleton-кода, ужесточается в следующих фазах).

### D3. `db.Pool` создаёт работающий `*pgxpool.Pool`

**Given** доступен Postgres (через testcontainers)

**When** разработчик вызывает `corelib/db.NewPool(ctx, dsn)` с валидным DSN

**Then** возвращается рабочий `*pgxpool.Pool`
**And** `pool.Ping(ctx)` возвращает nil
**And** `statement_timeout = '30s'` установлен на соединении (см. `02-data-model-and-conventions.md` §11).

### D4. `errors` маппинг

**Given** разработчик использует `corelib/errors`

**When** вызываются хелперы

**Then** `errors.NotFound("Folder", uid).Status()` возвращает `*google.rpc.Status` с `code = NOT_FOUND` и `details[]`, содержащим `ResourceInfo` с `resource_type = "Folder"` и `resource_name = uid`
**And** `errors.InvalidArgument(...)` укладывается в формат `BadRequest.field_violations[]`
**And** все коды из `02-data-model-and-conventions.md` §14 имеют соответствующий хелпер (`OK`, `INVALID_ARGUMENT`, `NOT_FOUND`, `ALREADY_EXISTS`, `FAILED_PRECONDITION`, `ABORTED`, `RESOURCE_EXHAUSTED`, `UNAVAILABLE`, `INTERNAL`, `GONE`).

### D5. `grpcsrv` и `observability` — health и slog

**Given** разработчик встраивает `corelib/grpcsrv` и `corelib/observability` в smoke-сервер

**When** сервер запускается и принимает gRPC-запросы

**Then** `grpc.health.v1.Health.Check` отвечает `SERVING`
**And** stdout содержит structured JSON-логи через `slog`
**And** OpenTelemetry SDK инициализирован условно: при `KACHO_OTEL_EXPORTER_OTLP_ENDPOINT=""` экспортер — no-op (см. `01-architecture-and-services.md` §7).

### D6. `config` через envconfig

**Given** Go-программа использует `corelib/config`

**When** в окружении выставлены `KACHO_FOO_GRPC_PORT=9090`, `KACHO_FOO_REST_PORT=8080`, `KACHO_FOO_DB_DSN=...`

**Then** структура конфига заполняется корректно
**And** при отсутствии required-поля — `Load()` возвращает ошибку с указанием конкретного env-имени.

---

## 5. Группа E — `kacho-deploy` и `make dev-up`

### E1. `make dev-up` поднимает кластер за < 5 минут

**Given** все репо склонированы согласно A1
**And** установлены `docker`, `kind`, `kubectl`, `helm`
**And** в `/etc/hosts` host-машины присутствует строка `127.0.0.1 api.kacho.local kacho.local`
**And** на host-машине свободен порт 80
**And** запущен docker-демон

**When** разработчик выполняет `cd kacho-deploy && make dev-up`

**Then** wall-clock время от старта команды до её завершения < 5 минут (на типичной dev-машине ≥ 4 CPU / 8 GB RAM)
**And** код выхода = 0
**And** stdout печатает в конце сообщение «доступно на http://api.kacho.local» с напоминанием про `/etc/hosts` (см. `03-deployment-and-operations.md` §2.2 шаг 7).

### E2. kind cluster с правильным kind-config

**Given** `make dev-up` завершился успешно

**When** разработчик выполняет `kind get clusters`

**Then** в выводе присутствует `kacho`
**And** `kubectl --context kind-kacho get nodes` показывает control-plane node с label `ingress-ready=true`
**And** node экспонирует `containerPort: 80` → `hostPort: 80` (см. `03-deployment-and-operations.md` §3).

### E3. Namespace `kacho` создан

**When** разработчик выполняет `kubectl get ns kacho`

**Then** namespace в статусе `Active`.

### E4. 4 Postgres-инстанса ready

**When** разработчик выполняет `kubectl get pods -n kacho`

**Then** в выводе присутствуют ровно 4 pod-а с alias-ами из `03-deployment-and-operations.md` §5: `pg-resource-manager-*`, `pg-vpc-*`, `pg-compute-*`, `pg-loadbalancer-*`
**And** все 4 pod-а в статусе `Running` и `Ready 1/1`
**And** в каждом pod-е `psql -U <svc> -d <db>` (например, `psql -U compute -d kacho_compute`) подключается успешно
**And** в каждой БД нет ни одной user-таблицы (`SELECT count(*) FROM information_schema.tables WHERE table_schema='public'` = 0): схемы добавляются в 0.2+.

### E5. Per-service credentials Secrets

**When** разработчик выполняет `kubectl get secret -n kacho`

**Then** для каждой из 4 Postgres-БД существует Secret вида `<svc>-db-credentials`, содержащий ключ `dsn` (по соглашению §6 шаблона deployment.yaml)
**And** DSN указывает на правильный k8s-service (`pg-<svc>.kacho.svc.cluster.local`) и правильную БД (`kacho_<svc>`)
**And** ни один Secret не залогирован в stdout/stderr `make dev-up` в plaintext-виде.

### E6. Ingress-nginx ready

**When** разработчик выполняет `kubectl get pods -n kacho -l app.kubernetes.io/name=ingress-nginx` (или соответствующий label из chart-а)

**Then** ingress-controller в статусе `Running` и `Ready`
**And** `curl -i http://api.kacho.local/` возвращает HTTP-ответ от ingress (статус **404 или 503** — это OK, потому что api-gateway ещё не задеплоен в 0.1)
**And** ответ содержит заголовки `Server: nginx`-семейства, подтверждающие, что ingress принял запрос (а не connection refused / DNS-fail).

### E7. **Никаких** сервисных Pod-ов не создано

**Given** sub-phase 0.1 не реализует доменные сервисы

**When** разработчик выполняет `kubectl get pods -n kacho` (исключая Postgres и ingress)

**Then** **отсутствуют** Pod-ы с именами `api-gateway-*`, `resource-manager-*`, `vpc-*`, `compute-*`, `loadbalancer-*`
**And** в `helm/umbrella/Chart.yaml` зависимости на эти 5 сервисных chart-ов либо отсутствуют, либо закомментированы, либо защищены feature-flag-ом, выключенным в `values.dev.yaml`.

### E8. `make dev-down` чистит state полностью

**Given** `make dev-up` отработал успешно

**When** разработчик выполняет `make dev-down`

**Then** код выхода = 0
**And** `kind get clusters` не содержит `kacho`
**And** все docker-контейнеры с label `io.x-k8s.kind.cluster=kacho` удалены
**And** на host-машине освобождён порт 80.

### E9. `emptyDir` persistence — данные не переживают rebuild

**Given** `make dev-up` отработал, разработчик руками создал в `pg-compute` тестовую таблицу и вставил строку

**When** разработчик выполняет `make dev-down && make dev-up`

**Then** новая БД `kacho_compute` пуста (тестовой таблицы нет)
**And** это поведение явно задокументировано в `kacho-deploy/README.md` или `kacho-workspace/CLAUDE.md` как **сознательное** для воспроизводимости тестов (см. `03-deployment-and-operations.md` §5).

### E10. `make reload-svc` присутствует, но в 0.1 ничего не перезагружает

**Given** `Makefile` в `kacho-deploy/`

**When** разработчик читает `make help`

**Then** упомянуты таргеты `dev-up`, `dev-down`, `reload-svc`, `logs-svc`, `psql`, `integration-test`, `e2e-test` (как минимум скелет/заглушки)
**And** `make reload-svc SVC=compute` в 0.1 возвращает осмысленную ошибку «service `compute` is not deployed yet (planned for sub-phase 0.4)» либо просто завершается с предупреждением и кодом 0 — конкретное поведение фиксируется в плане.

---

## 6. Группа F — Negative-сценарии и failure modes

### F1. `make dev-up` при занятом порту 80

**Given** на host-машине порт 80 уже занят другим процессом (например, локальный nginx)

**When** разработчик запускает `make dev-up`

**Then** скрипт завершается с кодом ≠ 0
**And** в stderr — осмысленное сообщение «port 80 is already in use, free it or change kind-config.yaml»
**And** kind-кластер либо не создан, либо удалён (state не остаётся «полусломанным»).

### F2. `make dev-up` без установленного `kind`/`docker`/`kubectl`/`helm`

**Given** в PATH отсутствует один из инструментов

**When** разработчик запускает `make dev-up`

**Then** скрипт делает preflight-check
**And** при отсутствии инструмента — печатает «<tool> is not installed: see <link to install>» и завершается с кодом ≠ 0 **до** попытки что-либо создать.

### F3. `bootstrap.sh` без SSH-доступа к GitHub

См. A3.

### F4. Запуск Claude Code из `~/` (вне `cloud-demo/`) не подгружает workspace-CLAUDE.md

**Given** разработчик находится в `~/` (где нет `kacho-workspace/`)

**When** запускается новый chat Claude Code

**Then** workspace-CLAUDE.md (`kacho-workspace/CLAUDE.md`) **не** загружается в контекст
**And** только `~/.claude/CLAUDE.md` влияет на поведение
**And** запреты из §11 не применяются (это ожидаемое поведение, защищающее «общий» chat от случайного применения проектных правил).

### F5. Защита от случайного коммита `go.work`

**Given** `cloud-demo/go.work` создан локально

**When** разработчик внутри любого из дочерних репо (`kacho-api/`, `kacho-corelib/`, и т.д.) выполняет `git status`

**Then** `go.work` **не** виден как untracked file внутри дочерних репо (потому что лежит на уровень выше — в `cloud-demo/`, которая сама не git-репо)
**And** в `kacho-workspace/.gitignore` присутствует строка `go.work` (защита от случайного коммита, если разработчик ошибочно положит его в `kacho-workspace/`).

---

## 7. Группа G — CI и трассируемость

### G1. CI каждого репо зелёный на пустом состоянии

**Given** все репо склонированы и не модифицированы (свежий `git clone` от main)

**When** GitHub Actions прогоняет `.github/workflows/ci.yaml` каждого репо

**Then** для `kacho-api`: jobs `lint` (buf lint), `breaking` (buf breaking against baseline tag), `generate` (buf generate, проверка отсутствия диффа в `gen/`) — зелёные.
**And** для `kacho-corelib`: jobs `lint` (golangci-lint), `test` (go test ./...) — зелёные.
**And** для `kacho-deploy`: job `helm-lint` (`helm lint helm/umbrella`) — зелёный.
**And** для сервисных репо-заглушек (`kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`): минимальный CI-job, проверяющий наличие `README.md` и `.gitignore` — зелёный.

### G2. Acceptance ↔ test mapping

**Given** этот документ принят
**And** integration-тесты для 0.1 будут написаны в репо `kacho-corelib`, `kacho-api` и `kacho-deploy/e2e/0.1/`

**When** автор тестов открывает acceptance-документ

**Then** каждому сценарию (A1–A5, B1–B5, C1–C4, D1–D6, E1–E10, F1–F5, G1) соответствует **ровно один** integration-тест или e2e-bash-сценарий с именем, повторяющим идентификатор сценария (например, `TestBootstrap_A1_FreshCloneOnEmptyMachine`, `kacho-deploy/e2e/0.1/E4-postgres-ready.sh`)
**And** трассируемость двусторонняя: по имени теста можно найти сценарий и наоборот.

---

## 8. Definition of Done sub-phase 0.1

Sub-итерация считается завершённой, когда **все** условия выполнены:

1. Все сценарии §1–§7 этого документа покрыты автотестами (integration или e2e-bash) и проходят на CI и локально.
2. `make dev-up` на чистой машине выполняется за < 5 минут и поднимает кластер с 4 ready Postgres + ingress.
3. `make dev-down` полностью убирает state.
4. CI всех 9 репо (`kacho-workspace`, `kacho-api`, `kacho-corelib`, `kacho-api-gateway`, `kacho-resource-manager`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer`, `kacho-deploy`) — зелёный.
5. `kacho-workspace/CLAUDE.md` содержит executive summary и все 8 запретов из `03-deployment-and-operations.md` §11.
6. Все 11 субагентов из §9.1–§9.2 присутствуют в `kacho-workspace/.claude/agents/`.
7. `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.1.
8. Тег `kacho-workspace:0.1.0` поставлен на main (по конвенции `04-roadmap-and-phasing.md` §6 п.5, адаптированной под non-сервисное репо).

---

## 9. Вопросы заказчику (нужны для approve)

Этот блок — для разрешения до approve. После approve блок удаляется или заменяется на «Resolved».

1. **A2 / idempotency:** допустимо ли давать `bootstrap.sh` опциональный флаг `--update`, который при повторном запуске делает `git pull --ff-only`? Или политика «никогда не трогать рабочее дерево пользователя» строгая?
2. **B3 / агенты:** все 11 файлов агентов пишутся **в этой** sub-итерации, или часть может прийти заглушками (только frontmatter), а тело наполняется по мере появления соответствующих доменов? (Например, `proto-api-reviewer` может быть полезен только когда в `kacho-api/proto/` появятся доменные сервисы — это 0.2+.)
3. **C2 / proto common-types:** `WatchEvent` в 0.1 — это только тип в proto (без сервиса) или вообще не нужен в 0.1, потому что `Watch`-RPC появляется в 0.2 вместе с `kacho-resource-manager`? Я заложил минимальный common-тип в 0.1, чтобы зафиксировать envelope; готов вынести в 0.2, если так чище.
4. **E10 / `make reload-svc`:** какой режим в 0.1 — early-error («сервиса нет, ждите 0.4») или soft-warning?
5. **G1 / CI service-stubs:** для пустых сервисных репо-заглушек оставляем CI с одним trivial job-ом или вообще без `.github/workflows/`? Я склоняюсь к минимальному CI ради единообразия, но это лишние GitHub Actions minutes.
6. **F2 / preflight-checks:** делаем check в чистом bash или используем что-то более структурированное (например, `make check-prereqs` отдельным таргетом, который вызывается из `dev-up`)?

---

**После approve этого документа:**
- Конвертация сценариев в тесты — задача субагента `integration-tester` (см. `03-deployment-and-operations.md` §9.1).
- План реализации — `kacho-workspace/docs/plans/sub-phase-0.1-bootstrap-plan.md` (через `superpowers:writing-plans`), каждый шаг плана ссылается на один или несколько идентификаторов сценариев из этого документа.
