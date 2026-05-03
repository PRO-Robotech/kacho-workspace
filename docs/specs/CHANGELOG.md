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

**Tag:** `v0.1.0` (`kacho-workspace:0.1.0` отменён — `:` невалиден в git tag)

## 2026-05-03 — Sub-phase 0.2 (Resource Manager + Watch infrastructure) завершена

**Что готово:**
- `kacho-corelib`: добавлены `migrations/common/`, `outbox/`, `watch/`, `selector/` (purposes per spec §8). Coverage: outbox 100%, selector 87.7%, watch 74.5%.
- `kacho-proto/proto/kacho/cloud/resourcemanager/v1/`: Organization, Cloud, Folder + Internal services + WatchEvent в common/v1.
- `kacho-resource-manager`: Clean Architecture (handler → service → repo с port-интерфейсами); migrations 0001/0002 с triggers; sqlc-генерированные stubs; default Org/Cloud/Folder bootstrap (idempotent); helm chart 0.2.0; coverage 63.3%.
- `kacho-deploy/helm/umbrella` 0.2.0: раскомментирован resource-manager dep.
- `kacho-corelib/grpcsrv`: добавлен `reflection.Register(s)` (для grpcurl).

**Smoke (Phase D 0.2):**
- `make dev-up`: 5 pods (4 Postgres + ingress) + resource-manager Pod (1/1 Running)
- `grpcurl OrganizationService/List`: возвращает default-org с uid + resourceVersion
- `grpcurl CloudService/Upsert`: создаёт smoke-test-cloud в default-org
- `grpcurl CloudService/List`: показывает default + smoke-test-cloud

**Найденные/исправленные проблемы:**
- goose не парсит `$$ ... $$` без явных `-- +goose StatementBegin/End` — добавлены в common migration
- Bitnami secret имеет ключ `password` (для custom user), не `postgres-password` (admin) — поправлен resource-manager values.yaml
- gRPC reflection не был зарегистрирован — добавлен в `kacho-corelib/grpcsrv.NewServer()`

**Acceptance:** 71 сценарий, 9 групп (A-I); APPROVED round 2 (commit `1df396b`).

**Tag:** `v0.2.0` (в kacho-workspace; запушен после сборки git-remote)

## 2026-05-03 — Sub-phase 0.3 (VPC) завершена

**Что готово:**
- `kacho-proto/proto/kacho/cloud/vpc/v1/`: Network, Subnet, SecurityGroup+Rule, RouteTable+StaticRoute, Address + VpcInternalService (5×Exists, 5×HasDependents, UpdateAddressStatus). 12 .pb.go committed.
- `kacho-vpc`: 48 файлов, 6649 строк. Clean Architecture (handler→service→repo с port-интерфейсами + cross-service FolderClient). 7/7 integration tests PASS (B1, B5, C1, D3, F1, G1, H4). Coverage service-layer 31.4%.
- `kacho-deploy/helm/umbrella` 0.3.0: vpc dep раскомментирован.

**Smoke (Phase D 0.3):**
- `make dev-up`: 6 pods (4 Postgres + ingress + resource-manager + vpc), все Running 1/1
- vpc + resource-manager оба listening :9090 в кластере
- `grpcurl NetworkService/Upsert` создаёт smoke-net в default-folder
- `grpcurl NetworkService/List` показывает созданную сеть с status.state=ACTIVE
- Address allocation из 203.0.113.0/24 работает (UNIQUE constraint)

**Acceptance:** 82 сценария, 10 групп (A-J); APPROVED round 2 (commit `809b41b`).

**Известные ограничения:**
- Клиент при upsert vpc-ресурса передаёт полную цепочку organizationId+cloudId+folderId; сервер не дёргает дополнительный Internal RPC к resource-manager для derive parents (это потребовало бы новый `Folder.Internal.GetParents` метод). Перенесено на улучшение в будущих фазах.

**Tag:** `v0.3.0`

## 2026-05-03 — Sub-phase 0.4 (Compute) завершена

**Что готово:**
- `kacho-proto/proto/kacho/cloud/compute/v1/`: Instance, Disk, Image (read-only catalog), Snapshot + ComputeInternalService с RemoveTargetFinalizer. 10 .pb.go committed. Instance enum БЕЗ RESTARTING (per design nit-1).
- `kacho-compute`: полный сервис с reconciler-ом. Clean Architecture (handler→service→repo + cross-service FolderClient + SubnetClient). 3 миграции (common + initial + seed-каталоги: zones, disk_types, platforms, images_catalog). Coverage service-layer 64.1%.
- `kacho-deploy/helm/umbrella` 0.4.0: compute dep раскомментирован.

**Reconciler (новое в 0.4):**
- Lifecycle handlers per kind (Instance, Disk, Snapshot)
- Симулированные задержки: SimConfig env-driven (`KACHO_COMPUTE_SIM_*_MIN_MS/MAX_MS`); test override до 100-200ms
- pg_advisory_lock per resource_uid для multi-replica
- Snapshot progress: 0→25→50→75→100, sleep(total/4) (per OQ-2)
- Instance disk-attach phase в PROVISIONING (per OQ-3)
- Restart cycle: STOPPING→STOPPED→STARTING→RUNNING (без RESTARTING enum)
- Finalizer disk-detach: `compute.kacho.io/disk-detach` cleanup перед физическим DELETE

**Smoke (Phase D 0.4):**
- `make dev-up`: 7 pods (4 Postgres + ingress + resource-manager + vpc + compute), все Running 1/1
- compute reconciler started; gRPC :9090
- `grpcurl ImageService/List` возвращает seed-каталог: ubuntu-22.04-lts, ubuntu-20.04-lts, debian-11
- `grpcurl DiskService/Upsert` создаёт smoke-disk в state=STATE_CREATING
- Через 8 секунд reconciler переводит state=STATE_READY (full lifecycle через CREATING→READY validated)

**Acceptance:** 88 сценариев, 16 групп (A-P); APPROVED round 1 (commit `9bc31d0`).

**Tag:** `v0.4.0`

## 2026-05-03 — Sub-phase 0.5 (LoadBalancer) завершена

**Что готово:**
- `kacho-proto/proto/kacho/cloud/loadbalancer/v1/`: NetworkLoadBalancer + TargetGroup + LoadBalancerInternalService с RemoveTarget RPC. 6 .pb.go committed.
- `kacho-loadbalancer`: 24 теста PASS (19 unit + 5 integration), coverage 63.8%. Clean Architecture с reconciler-ом для NLB lifecycle (CREATING→ACTIVE 5-15s simulated). TG synchronous (READY in tx). Cross-service clients к resource-manager/vpc/compute.
- `kacho-deploy/helm/umbrella` 0.6.0: loadbalancer + api-gateway deps раскомментированы.

**Smoke (Phase D 0.5):** включён в полный stack-smoke 0.6 ниже.

**Acceptance:** 81 сценарий, 13 групп (A-N); APPROVED round 2 (commit `5e4d5e7`).

**Tag:** `v0.5.0`

## 2026-05-03 — Sub-phase 0.6 (API Gateway) завершена

**Что готово:**
- `kacho-api-gateway`: cmux + gRPC-proxy (`mwitkow/grpc-proxy`) + REST mux skeleton + allowlist (63 публичных RPC) + middleware (request-id, recovery, slog access log, auth-noop) + health (HTTP /healthz /readyz + gRPC Health). 30 unit-тестов PASS. Persistent gRPC-connection pool с keepalive 30s.
- Allowlist excludes ALL `*InternalService` методов; defense-in-depth через `HasInternalSuffix(methodPath)` проверку.
- Helm chart 0.6.0 с Ingress (host: api.kacho.local, backend-protocol: GRPC, proxy-read-timeout: 120s).

**Известное ограничение:** REST мaршруты не активны — proto-файлы Kachō не содержат `google.api.http` аннотаций. Grpc-gateway ServeMux инициализирован, но routes возвращают 404. gRPC через port 8080 полностью работает. REST UX перенесён на phase 1 (требует addition `import "google/api/annotations.proto"` + URL опции в каждый proto RPC).

**FULL STACK SMOKE (Phase D 0.5+0.6):**
- `make dev-up`: 10 pods (4 Postgres + ingress + 5 services), все Running 1/1
- HTTP `/healthz` через api-gateway → `{"status":"ok"}`
- HTTP `/readyz` → `{"status":"ok","backends":{"compute":"SERVING","loadbalancer":"SERVING","resourcemanager":"SERVING","vpc":"SERVING"}}`
- **gRPC через gateway (с proto-файлами для grpcurl):**
  - `OrganizationService/List` — возвращает default-org через resource-manager
  - `ImageService/List` — возвращает seed-каталог (ubuntu-22.04-lts, ubuntu-20.04-lts, debian-11) через compute
  - **`FolderInternalService/Exists` — заблокирован: `Code: NotFound, Message: unknown method: /...FolderInternalService/Exists`**. Подтверждение CLAUDE.md prohibition #7: Internal.* методы НЕ маршрутизируются наружу через api-gateway.
- Access log: structured JSON через slog с request-id propagation работает.

**Найденные/исправленные проблемы:**
- loadbalancer port 9094 → 9090 для consistency с другими backends (gateway конфигурирован на :9090).
- helm/post-install/ingress.yaml удалён — api-gateway chart теперь владеет ingress.

**Acceptance:** 59 сценариев в 12 группах (A-L); APPROVED round 2 (commit `88db213`).

**Tag:** `v0.6.0`

---

## Sub-phase 0.x (Bootstrap phase) — ИТОГ

7 sub-итераций (0.1-0.6 + 0.7 e2e в составе 0.6) завершены. Полный control plane Kachō (Org/Cloud/Folder/Network/Subnet/SG/RT/Address/Instance/Disk/Image/Snapshot/NLB/TG) работает в kind-кластере с api-gateway фронтендом, allowlist-фильтрацией Internal, Watch-инфраструктурой, reconciler-ами для compute и loadbalancer.

**Tags:** v0.1.0, v0.2.0, v0.3.0, v0.4.0, v0.5.0, v0.6.0

## 2026-05-03 — Sub-phase 0.7 (Web UI) завершена

**Что готово:**

- `kacho-proto` — google.api.http annotations добавлены во все 14 публичных сервисов (3+5+4+2). Регенерированы `*.pb.gw.go` через grpc-gateway plugin. URL convention: `POST /v1/<resource-plural-kebab>/<action>`. Internal services НЕ аннотированы (CLAUDE.md prohibition #7).
- `kacho-api-gateway` — REST mux активирован: `RegisterXxxServiceHandlerFromEndpoint` для всех 14 public services. Добавлен `tmc/grpc-websocket-proxy/wsproxy` для WebSocket-streaming Watch RPC. middleware/access_log responseWriter wrapper теперь прокидывает Flusher (chunked stream) и Hijacker (WS upgrade).
- `kacho-ui` — новый репо, single SPA: Vite 6 + React 19 + TypeScript 5.7 + Tailwind 3.4 + shadcn-style components (Radix Dialog/DropdownMenu/Tabs/Slot) + TanStack Query 5.66 + React Router 7. ~1500 строк TS.
- `kacho-deploy/helm/umbrella` 0.7.0: добавлен ui dep (nginx-served, ingress на console.kacho.local).

**SPA features:**
- Generic подход через `ResourceSpec` registry — одна реализация покрывает все 14 ресурсов.
- ResourceListPage — list + filter + Action column (View/Edit/Delete).
- ResourceDetailPage — Tabs (Overview/Spec/Status/Raw JSON) + Restart action для Instance.
- Form-based Create/Edit Dialog со schema-driven полями: string/text/int/enum/ref/array/bool. Toggle Form↔JSON для advanced. ref-fields подгружают list через `/v1/<r>/list` (folder-scoped когда нужно).
- StatusBadge color-coded по lifecycle state.
- DashboardPage с 10 stat cards.
- Sidebar группирован: Resource Manager / VPC / Compute / Load Balancer.
- Folder selector в шапке (LocalStorage-persisted).

**Watch через WebSocket (вместо polling):**
- `useResourceWatch` hook — initial List + один длинный WebSocket к `/v1/<r>/watch?method=POST`.
- Flow: client opens WS → sends body как первый frame (wsproxy proxy-ит как POST к grpc-gateway) → server-stream events приходят back каждый отдельным WS text frame.
- Обработка ADDED/MODIFIED/DELETED → update local cache; OUT_OF_RANGE → relist; server-close → reconnect с exponential backoff 1s..10s.
- WatchIndicator (live/listing/reconnecting/offline) в UI.
- nginx UI-pod: `Upgrade: websocket` headers + `proxy_buffering off` + 3600s read timeout.

**Smoke (Phase D 0.7):**
- 10 pods Running (4 Postgres + ingress + 5 backend + ui)
- `POST /v1/<r>/list` через UI nginx → 200
- WS handshake `ws://.../v1/<r>/watch?method=POST` → `101 Switching Protocols`
- Browser flow проверен: создание ресурсов через формы, edit, delete, live-обновление status через Watch (Disk CREATING→READY за секунды).

**Найденные/исправленные проблемы:**
- wsproxy после WS upgrade использует оригинальный HTTP method (GET для WebSocket initiation); Watch RPC зарегистрирован как POST в grpc-gateway → Method Not Allowed. Фикс: query-param `?method=POST` в WS URL — wsproxy `MethodOverrideParam`.
- access_log middleware не прокидывал Flusher → grpc-gateway не мог стримить chunked. Hijacker не реализован → wsproxy не мог делать WS upgrade.
- httpSrv.WriteTimeout=120s резал long-lived streams. Снят (=0).

**Tag:** `v0.7.0`

## 2026-05-03 — Methodology change: acceptance approve gate ушёл к агенту

Заказчик: рутинный approve acceptance-документа уходит от человека к агенту. Заказчик подключается только к финальной верификации (smoke / e2e). TDD-дисциплина сохраняется — её соблюдают сами агенты.

**Что изменилось:**

- Добавлен 12-й агент `acceptance-reviewer` (specialist-review) — единственный gate между acceptance-документом и кодом. Возвращает `✅ APPROVED` или `❌ CHANGES REQUESTED` с замечаниями. Re-review цикл итеративный.
- `kacho-workspace/CLAUDE.md` запрет #1 — теперь approve выставляет `acceptance-reviewer`, а не заказчик.
- `04-roadmap-and-phasing.md §2 шаг 2` и `§5 пункт 3` — review заказчика → review `acceptance-reviewer`. Эскалация заказчику только при scope-конфликте или ≥3 нерезультативных раундах.
- `03-deployment-and-operations.md §9` — 11 → 12 агентов; `acceptance-reviewer` добавлен в §9.2.
- `acceptance-author` агент — переориентирован на координацию с `acceptance-reviewer` (а не заказчиком).

## 2026-05-03 — Sub-phase 0.6 (API Gateway) завершена

**Что готово:**

- `kacho-api-gateway`: 26 файлов, ~1900 строк. Единая точка входа платформы Kachō на порту 8080.
- `cmd/api-gateway/main.go` — composition root: cmux + gRPC-proxy + REST mux + middleware chain + health.
- `internal/allowlist/list.go` — Go-константа из 63 публичных RPC-путей; `HasInternalSuffix` — эшелонированная защита от Internal-методов (запрет #7 CLAUDE.md).
- `internal/proxy/` — gRPC-proxy через `mwitkow/grpc-proxy`; директор маршрутизирует по domain (`kacho.cloud.<domain>.v1.*`); один `*grpc.ClientConn` per backend с keepalive 30s.
- `internal/restmux/` — grpc-gateway ServeMux скелет; REST `/v1/...` недоступен до добавления HTTP-аннотаций в proto (задокументировано, фаза 1).
- `internal/middleware/` — request_id (preserve/generate UUID v4), recovery (panic → INTERNAL), access_log (slog JSON), auth_noop placeholder (F7).
- `internal/health/` — /healthz (liveness, всегда 200), /readyz (readiness, grpc Health.Check на каждый backend), gRPC `grpc.health.v1.Health/Check`.
- `deploy/` — Helm chart 0.6.0 (Deployment + Service + Ingress с `proxy-read-timeout=120`); Dockerfile (parent-context pattern).

**Тесты (30 тестов, `go test ./... -race` OK):**
- `allowlist`: матрица Internal-методов (E_Exists/E_HasDependents/E_UpdateStatus canonical), все публичные методы
- `proxy`: A1–A5, E1, J3 — директор, routing, блокировка
- `middleware`: F1, F2, F3, F6, F7
- `health`: G1, G3
- `gateway_test` (интеграция с mock-backends): A1, A5, E1, G1, G5, J5

**Принятые решения:**
- REST через grpc-gateway: proto-файлы `kacho-proto` не содержат `google.api.http` аннотаций → REST `/v1/...` не работает до фазы 1. Архитектурный скелет готов, 14 `RegisterXxx` вызовов задокументированы в `internal/restmux/mux.go`.
- cmux matcher: `HTTP2MatchHeaderFieldSendSettings("content-type", "application/grpc")` + `Any()` fallback.
- Backend domains: `"resourcemanager"` / `"vpc"` / `"compute"` / `"loadbalancer"` — извлекаются из pkgParts[2] пути метода.

**Smoke (helm lint, docker build):**
- `helm lint deploy/` — 0 chart(s) failed
- `docker build -f kacho-api-gateway/Dockerfile -t kacho-api-gateway:dev .` — успешно

**Acceptance:** 59 сценариев, 11 групп (A-K); APPROVED commit `88db213`.

**Tag:** `v0.6.0`
