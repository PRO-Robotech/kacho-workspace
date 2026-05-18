# Sub-phase 2.0 — IAM E3: OpenFGA REBAC + Check-interceptor + реактивность — Acceptance

> **Status**: DRAFT v2 — awaiting acceptance-reviewer (v1 review returned 7 blockers + 4 important)
> **Date**: 2026-05-17
> **YouTrack**: [KAC-108](https://prorobotech.youtrack.cloud/issue/KAC-108) — child of epic [KAC-104](https://prorobotech.youtrack.cloud/issue/KAC-104)
> **Parent overview**: [[sub-phase-2.0-iam-overview-acceptance]]
> **Blocked by**:
> - [KAC-105](https://prorobotech.youtrack.cloud/issue/KAC-105) (E0 — `access_bindings` table, stub openfga-bootstrap-job, AccessBindingService skeleton).
> - [KAC-107](https://prorobotech.youtrack.cloud/issue/KAC-107) (E2 — auth-interceptor резолвит Principal через `InternalIamService.LookupSubject`; без него Check некого проверять).
> **Blocks**: [KAC-109](https://prorobotech.youtrack.cloud/issue/KAC-109) (E4 — signup-flow создаёт первое default-admin binding'и через FGA-write; UI отображает effective permissions / hides admin-actions для viewer).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`

---

## 0. Преамбула — что эта sub-итерация

Это **полноразмерный acceptance** sub-эпика **E3**, открытого после APPROVED'а E0 (skeleton + stub-bootstrap-job) и E2 (Zitadel/OIDC + Principal). E3 включает Authorization (REBAC) для всей публичной поверхности Kachō:

1. **OpenFGA полная DSL-модель** (overview §4) применяется поверх stub-модели E0 через replaced helm `openfga-bootstrap-job` (Job-hook `post-install,post-upgrade`).
2. **AccessBindingService.Upsert/Delete** транзакционно (a) пишет row в `kacho_iam.access_bindings`, (b) пишет outbox-row в `kacho_iam.outbox` (FGA-write event), (c) пишет outbox-row в `kacho_iam.subject_change_outbox` (subject-invalidate notification) — **всё в одной DB-TX** (godzila §16 outbox pattern).
3. **kacho-iam outbox-reader worker (FGA tuple writer)** drain'ит `outbox` → пишет tuples в OpenFGA с retry; на success — `UPDATE outbox SET sent_at=now()`.
4. **Resource lifecycle → parent tuples**: kacho-iam подписан на **новый Internal gRPC server-stream `InternalResourceLifecycleService.Subscribe`** каждого ресурсного сервиса (vpc / compute / loadbalancer) — НЕ через deprecated `InternalWatchService` (см. D-13; workspace 1.0 удалил Watch RPC). На `Network.Create` / `Subnet.Create` / `Instance.Create` / ... — peer-service пушит lifecycle-event через свой outbox → server-stream к kacho-iam; kacho-iam пишет tuple `<type>:<id>#parent@project:<project_id>` (или `network:<network_id>` для subnet). На `Delete` — untuple. **Decision D-1: centralized FGA-owner в kacho-iam** (не в каждом сервисе); **D-13: новый specialized Internal RPC** (не reuse deprecated Watch).
5. **Per-service Check-interceptor** (kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-iam) — gRPC unary/stream interceptor зовёт `InternalIamService.Check(subject, relation, object)` к kacho-iam:9091 gRPC-direct. Mapping `RPC → (relation, object)` через `metadata.go` per-service.
6. **Реактивность ≤10s**: revoke binding → subject_change_outbox → kacho-iam `subject_change_notifier` worker → `pg_notify('kacho_iam_subjects', subject_id)` → per-service Check-cache LISTEN-loop инвалидирует positive entries для subject. Worst-case ограничен TTL=5s + propagation ≤1s ⇒ ≤10s гарантированно.
7. **Fail-modes**: на OpenFGA-unavailable — fail-closed (`PermissionDenied`); dev break-glass env var `KACHO_<SVC>_AUTHZ__BREAKGLASS=true` обходит Check (logs WARN).
8. **DoD #5 (overview)** — реактивность ≤10s **измерима** в integration + newman + k6.

После E3 любой публичный RPC возвращает `PermissionDenied` если subject не имеет требуемого permission, и реактивно перестаёт пускать в течение ≤10s после revoke. E3 — последний gate перед E4 (signup-flow + UI IAM).

---

## 1. Связь с регламентом и запретами (нормативно)

| # | Запрет / правило (workspace `CLAUDE.md`) | Применение в E3 |
|---|------------------------------------------|-----------------|
| 1 | НЕ начинать кодинг до APPROVED acceptance | Этот документ + reviewer cycle → APPROVED → `superpowers:writing-plans` → integration-tester → rpc-implementer |
| 2 | НЕ упоминать `yandex` | Все error-text'ы / переменные / комментарии — `kacho.cloud.*` / `KACHO_*` |
| 3 | НЕ использовать ORM | sqlc + pgx для `outbox` / `access_bindings` / `subject_change_outbox` (E0 уже использует это) |
| 4 | НЕ каскадно удалять через границу сервиса | На VPC.Network.Delete → kacho-iam Untuple, но **не удаляет** access_bindings (они — данные владельца, FK невозможен) |
| 5 | НЕ редактировать применённую миграцию | Новые таблицы / индексы — отдельные миграции (`0005_fga_outbox.sql`, `0006_subject_change_outbox.sql`, `0007_fga_model_version_idx.sql`) |
| 6 | `Internal.*` не на external endpoint | `InternalIamService.Check` / `InternalSubjectChangeNotificationService` — port 9091 cluster-internal; api-gateway не маршрутизирует на external TLS |
| 7 | НЕ broker (Kafka/NATS) до in-process | NOTIFY/LISTEN на Postgres connection (godzila §16) — отдельный pgx-connection не из пула |
| 8 | НЕ cross-DB FK | FGA tuples и `access_bindings` — разные БД (`openfga` Postgres vs `kacho_iam` Postgres); консистентность через outbox-retry, **не** через 2PC |
| 9 | НЕ sync возврат ресурса из мутаций | `AccessBindingService.Upsert/Delete` возвращают `Operation` (corelib pattern); реактивность считается от commit DB-TX, не от ack клиента |
| 10 | НЕ software refcheck для within-service инвариантов | `access_bindings_unique` constraint (overview §4 — E0); FGA-tuple-write идемпотентен (FGA дедуплицирует Write на existing tuple) |
| 11 | НЕ мёрджить новый RPC без тестов в том же PR | Каждый PR (kacho-iam / kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-api-gateway / kacho-deploy) обязан содержать integration + newman case'ы для добавляемого функционала; explicit чек-лист в §6 DoD |

**Связь с evgeniy** (skill `evgeniy`):
- §16 outbox pattern — `kacho_iam.outbox` обновляется одной TX вместе с `access_bindings`; worker dedicated pgx-conn для LISTEN.
- §2 use-case pattern — `internal/apps/kacho/api/access_binding/upsert.go`, `delete.go` — каждый use-case в своём файле, не fat-service.
- §10 metadata.go — `RPC → permission` mapping per service в `internal/metadata/permission_map.go`.

---

## 2. Decision Log (зафиксированные решения этого sub-эпика)

| ID  | Decision                                                                                                       | Rationale                                                                                                                                                                       | Alternatives rejected                                                                                                                              |
|-----|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| D-1 | **Tuple writer ownership = (B) kacho-iam centralized FGA-owner**                                              | Single source of truth для FGA tuples; kacho-iam — единственный сервис, импортирующий openfga-go-sdk; подписан на **`InternalResourceLifecycleService.Subscribe`** (D-13, новый — НЕ deprecated `InternalWatchService`) каждого ресурсного сервиса для lifecycle tuples | (A) per-service writer — дублирует openfga-client в каждом сервисе, fragmented retry-config, race между access-binding-write и resource-tuple-write; (C) gateway-centralized — gateway не должен лезть в FGA-write (write-path != check-path) |
| D-2 | **Check-interceptor = per-service** (vpc / compute / lb / iam), не gateway-centralized                        | Per-service interceptor имеет typed access к request fields (project_id, network_id, …); gateway-centralized требует generic reflection-based extraction → fragile + slower      | (A) gateway-centralized — gateway-сервис должен знать структуру каждого request, нарушение слоистости; (C) gateway + per-service — двойная Check, нарушение NFR-3 (≤1 Check per RPC) |
| D-3 | **Cache invalidation = NOTIFY push** (Postgres pg_notify), не polling                                          | Sub-second propagation; стабильно для in-process eventual-consistency (godzila §16); 0 cost при steady state                                                                    | (A) TTL only ≥10s — не выполняет DoD #5 (revoke ≤10s); (B) polling каждые 1s — load на kacho-iam при N pods × M services; (C) Kafka — запрет #7 |
| D-4 | **Computed relations** (DSL `admin from project`), не explicit per-resource tuples                            | Overview §5 решение #9 — одна tuple на project покрывает все networks/subnets/instances в нём; resource lifecycle создаёт только `parent` tuple (1 на ресурс)                  | Materialize все permissions per-resource — write amplification O(N×M); custom-roles per-resource — Phase 2.1+ (overview §9) |
| D-5 | **Outbox-pattern для FGA-write** (atomic в TX, eventual ≤2s через worker), не sync FGA-write в handler        | godzila §16; sync-в-handler — если FGA unavailable, handler застрянет на retry или вернёт частичный success (row есть, tuple нет); outbox-pattern + reconciler — proven pattern | (A) sync FGA-write в handler — частичный success при FGA-unavailable, латентность Upsert > NFR-6 (200ms); (B) hybrid — best-effort sync + outbox-failover — две code-path'и, тесты сложнее |
| D-6 | **Fail-closed default** на OpenFGA-unavailable; **break-glass env var** `KACHO_<SVC>_AUTHZ__BREAKGLASS=true` (dev-only) | Defensive (security over availability); break-glass для dev-debugging (нагрузка/манчинг FGA-instance) + production-incident response (рукой выставляется + alert)                | Fail-open — расходится с security expectations; per-RPC granular fail-mode — over-engineered на MVP |
| D-7 | **Lifecycle tuples от resource servic'а к kacho-iam — через push (D-13: новый `InternalResourceLifecycleService.Subscribe` server-stream), не sync RPC** | Реактивно (push); resource service не блокируется на kacho-iam unavailability; kacho-iam догоняет via outbox-resume после restart. **Reuse deprecated `InternalWatchService` (workspace 1.0) запрещён** — D-13 вводит новый specialized RPC | sync `InternalIamService.RegisterResource` — couples resource-service deploy к iam-availability (resource-create fails если iam down); periodic reconciliation — extra load + stale tuples; reuse deprecated `InternalWatchService` — нарушает workspace «Watch RPC удалён с 1.0» |
| D-8 | **Один Check per RPC (NFR-3)** — для List-RPC: Check `viewer on parent_scope`, **без per-item filtering**       | Overview §5 решение #7; per-item filtering = N+1 Check, не вытягивает NFR-2 (≤20ms p95) при List на 100+ ресурсов; ListObjects-pattern — Phase 2.1+ если SLA не вытягивает      | Per-item filtering on each List — N+1 Check call (overview §9) |
| D-9 | **Subject cache TTL = 5s** в Check-interceptor; positive results cached, negative — НЕ кешируются               | TTL=5s + NOTIFY-invalidate ⇒ worst-case revoke propagation ≤10s (5s TTL + 1s NOTIFY + 2s outbox-drain + buffer); negative cache рискует stale на grant (грант не виден до TTL-expiry) | TTL=30s (как для subject-cache в E2) — не выполняет DoD #5; negative-cache — расходится с UX («дал права — почему не работает?») |
| D-10 | **Bootstrap-job в kacho-deploy заменяет stub-model E0 на полную DSL** через `WriteAuthorizationModel` API; **новый model_id**; tuples от старой stub-model **остаются** (stub model — minimal `type user`, не содержит tuples production-релевантных) | Idempotent: re-apply детектирует «model_id уже сохранён в Secret `kacho-iam-openfga-store`» → re-validates via ReadAuthorizationModel → skip; новая DSL → new model_id → write к Secret | Tuple migration — overkill для stub→full переход (stub нет реальных tuples); полная re-bootstrap — теряет dev-state |
| D-11 | **Creator-tuple sync write inline** — в `kacho-vpc` (и других ресурсных сервисах) Create handler выполняет **синхронный FGA-write** для own-creator tuple (например `user:<creator_principal_id> admin vpc_network:<new_id>`) **до return Operation** клиенту. Остальные subjects (через project-cascade, group-cascade, resource lifecycle parent-tuple) получают права через обычный async outbox + resource-lifecycle-subscriber pipeline (D-13). | Закрывает «Create+immediate-Get propagation window»: tenant выполнил Create → сразу Get/Update/Delete — должен пройти Check без race на async-propagation (≤2s окно D-5). Sync FGA-write только для creator-tuple (1 tuple, ≤10ms p95) добавляет ≤10ms к NFR-6 budget Create (200ms) — fits. Outbox-pattern остаётся primary для resource-lifecycle parent tuples (через resource-lifecycle-subscriber) и для AccessBinding tuples. | Полностью async (D-5 alone) — есть окно ≤2s где creator получает PermissionDenied на собственный только что созданный ресурс (UX broken); полностью sync для всех tuples — Create handler couples к openfga availability (нарушает D-7 reactive resource lifecycle); только parent-tuple sync — не помогает creator получить admin (parent-tuple = project, project tuples создаются E4 на signup; для resource-scope создателя нужен resource-tuple) |
| D-12 | **No cascade-delete bindings on User.Delete** — `UserService.Delete` остаётся behavior из E0 (`FailedPrecondition` если ещё есть bindings). E3 НЕ добавляет cascade-delete. Admin сначала вручную revoke'ит все bindings через `AccessBindingService.Delete` (каждый binding → свой outbox/subject_change pipeline) → потом вызывает `UserService.Delete`. Tuple cleanup идёт через обычный AccessBindingService.Delete pipeline для каждого binding'а. | Cascade-delete bindings = implicit large-fanout outbox-writes на один RPC (для user с 100+ bindings — 100+ outbox rows + 100+ subject_change rows в одной TX → блокирует таблицу + большой commit); admin должен **видеть и контролировать** revoke (audit-trail per-binding); CASCADE в SQL только для same-DB FK (запрет #4) — не помогает cross-process side-effects. | E3 cascade-delete с fanout — breaks atomic transaction guarantees (большой commit lock); soft-delete user — overhead для E3 scope; deferred cascade (background job) — раздувает scope E3 (job lifecycle, retry, error handling) и не нужен MVP |
| D-13 | **Resource-lifecycle eventing — push from peer-service через новый Internal gRPC server-stream `kacho-iam.InternalResourceLifecycleService.Subscribe(stream)`** — НЕ переиспользует deprecated `InternalWatchService` (удалён в workspace 1.0). vpc/compute/lb пушат resource-events (Create/Delete/Move + parent IDs) в свой outbox + публикуют через новый Internal gRPC server-stream к kacho-iam. kacho-iam подписывается на каждый peer-service `InternalResourceLifecycleService.Subscribe` (long-lived server-stream); peer-service worker drain'ит свой outbox → отправляет в stream. Cursor (`last_event_id`) хранится у kacho-iam (`kacho_iam.watch_cursors`); peer-service отправляет с `event_id` для resume. **Нарушения запрета #8 (database-per-service) — НЕТ**: kacho-iam НЕ читает peer-service Postgres напрямую (LISTEN/SELECT); вся коммуникация через gRPC. | Workspace CLAUDE.md явно говорит «Watch RPC удалён с 1.0»; reuse имени `InternalWatchService` создаёт путаницу. Новое имя `InternalResourceLifecycleService` отражает узкое назначение (resource lifecycle events для FGA-tuple sync). Push (server-stream) vs poll-LISTEN на peer DB: первое — соблюдает #8 (нет cross-DB-conn), второе — нарушает (kacho-iam нужны peer-DB credentials → split-brain если schema changes). Push pattern uniform для всех 3 peer'ов (vpc/compute/lb). | (A) Direct LISTEN на peer-Postgres → нарушает запрет #8 (cross-DB connections + credentials proliferation + schema-coupling); (B) `InternalWatchService` reuse — нарушает «Watch RPC deprecated» rule + general-purpose Watch API в E3 для специфической задачи; (C) Kafka/NATS broker — запрет #7 |

---

## 3. Target architecture (компактно)

### 3.1 ASCII edges (новые на E3)

```
                       ┌──────────────────────────────────────────┐
                       │   client (UI / kacho-yc / Newman / k6)   │
                       └─────────────────┬────────────────────────┘
                                         │ HTTPS, OIDC JWT (E2)
                                         ▼
                       ┌──────────────────────────────────────────┐
                       │           kacho-api-gateway              │
                       │   auth-interceptor (E2) → Principal      │
                       │   ──────────────────────────────────     │
                       │   (NO authz here in E3; per-service)     │
                       └─────────────────┬────────────────────────┘
                                         │ gRPC (Principal в ctx-metadata)
                                         ▼
        ┌────────────────────┬────────────────────┬─────────────────┬────────────────┐
        │                    │                    │                 │                │
        ▼                    ▼                    ▼                 ▼                ▼
┌──────────────┐   ┌──────────────────┐  ┌─────────────────┐  ┌───────────┐  ┌─────────────┐
│ kacho-vpc    │   │ kacho-compute    │  │ kacho-loadbal.. │  │ kacho-iam │  │ ... future..│
│              │   │                  │  │                 │  │           │  │             │
│ authz-       │   │ authz-           │  │ authz-          │  │ authz-    │  │             │
│ interceptor  │   │ interceptor      │  │ interceptor     │  │ intercep  │  │             │
│ (E3)         │   │ (E3)             │  │ (E3)            │  │ (E3)      │  │             │
└──────┬───────┘   └──────┬───────────┘  └────────┬────────┘  └─────┬─────┘  └─────────────┘
       │                  │                       │                 │
       │ Check(subj,rel,obj) gRPC to kacho-iam:9091 (InternalIamService.Check) — 1 per RPC
       ▼                  ▼                       ▼                 ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              kacho-iam (gRPC :9091)                                  │
│                                                                                      │
│   InternalIamService.Check(subj, rel, obj) ──┐                                       │
│                                              │                                       │
│   AccessBindingService.Upsert/Delete ──┐     │                                       │
│   (E0 RPC, now writes FGA outbox)      │     │                                       │
│                                        ▼     ▼                                       │
│                              ┌──────────────────────────┐                            │
│                              │   kacho-iam Postgres     │                            │
│                              │  ─ access_bindings (E0)  │                            │
│                              │  ─ outbox (E3 new)       │ ─── LISTEN/NOTIFY ──┐      │
│                              │  ─ subject_change_outbox │     'kacho_iam_*'   │      │
│                              │  ─ fga_model_version     │                     │      │
│                              └────────────┬─────────────┘                     │      │
│                                           │ outbox-drain                      │      │
│                              ┌────────────▼─────────────┐                     │      │
│                              │  fga-tuple-writer worker │ ── Write/Delete ──► OpenFGA│
│                              │  subject-change-notifier │ ── pg_notify  ─────────┐   │
│                              │  ───────────────────     │                        │   │
│                              │  resource-lifecycle      │ ◄── stream ── kacho-vpc /  │
│                              │  worker (subscribed to ──┘                  kacho-compute/
│                              │   InternalResourceLifecycle                  kacho-lb │
│                              │   Service.Subscribe per                              │
│                              │   resource svc — D-13)                              │
│                              └──────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                       ▲                            │
                                       │                            │ NOTIFY 'kacho_iam_subjects'
                                       │                            ▼
                          ┌────────────┴──────────────────────────────────────────┐
                          │  per-service authz-cache invalidation listener        │
                          │  (in kacho-vpc / kacho-compute / kacho-loadbalancer / │
                          │   kacho-iam — dedicated pgx-conn LISTEN-loop)         │
                          └───────────────────────────────────────────────────────┘
```

### 3.2 Что добавляется в каждый репо

| Repo                 | Что добавляется                                                                                                                                                            |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| kacho-proto          | `internal_iam_service.proto`: rpc `Check(subj, rel, obj) → (allowed bool)` (новый method, не было в E0); **`internal_resource_lifecycle_service.proto`** (D-13, новый): `service InternalResourceLifecycleService { rpc Subscribe(SubscribeRequest) returns (stream ResourceLifecycleEvent); }` — реализуется в kacho-vpc / kacho-compute / kacho-loadbalancer (НЕ в kacho-iam); kacho-iam — единственный consumer. **НЕ** переиспользует deprecated `InternalWatchService` (workspace 1.0 удалил, см. D-13) |
| kacho-corelib        | `authz/` package: `Interceptor` (gRPC unary/stream), `Cache` (TTL=5s positive-only, with LISTEN-invalidate; per-RPC Check-result cache, см. B1 в §4.3), `CheckClient` wrapping `InternalIamService.Check`; `outbox/` уже существует, **не меняется** (godzila §16); **`resourcelifecycle/`** (D-13, новый): server-side helper для peer-service (vpc/compute/lb) реализующий `InternalResourceLifecycleService.Subscribe` поверх per-service outbox + cursor protocol |
| kacho-iam (proto)    | `InternalIamService.Check` (новый method); расширение `internal_iam_service.proto`; `InternalResourceLifecycleService` proto живёт в kacho-proto (см. row выше) |
| kacho-iam (impl)     | `internal/clients/openfga_client.go` (Write/Delete/Check tuples wrapper); `internal/apps/kacho/api/access_binding/upsert.go` / `delete.go` — расширение E0-stub'а: пишут outbox-row в одной TX с access_bindings INSERT/DELETE; `internal/jobs/fga_tuple_writer.go` (drain outbox → openfga.Write/Delete); `internal/jobs/subject_change_notifier.go` (drain subject_change_outbox → pg_notify); `internal/jobs/resource_lifecycle_subscriber.go` (D-13: subscribe на `InternalResourceLifecycleService.Subscribe` каждого peer kacho-vpc/compute/lb → outbox-write для lifecycle tuples); `internal/apps/kacho/internal_api/iam/check.go` (InternalIamService.Check handler — обёртка над openfga.Check, exposed on :9091); миграции `0005..0007` |
| kacho-vpc            | `internal/interceptors/authz.go` (использует `corelib/authz.Interceptor`); `internal/metadata/permission_map.go` (RPC → (object_type, relation, object_id extractor)) — table-driven; регистрация interceptor в `cmd/kacho-vpc/main.go` |
| kacho-compute        | то же, что kacho-vpc, +stream-interceptor для potential streaming RPC |
| kacho-loadbalancer   | то же |
| kacho-iam            | + self-authz (iam-admin RPC проверяются через FGA `account#admin` / `project#admin`) |
| kacho-api-gateway    | НЕТ изменений в E3 (auth-interceptor уже из E2; authz делегирован на backend per-service per Decision D-2); единственное мелкое — комментарий в `internal/interceptors/authz_stub.go` что E3 переносит authz в backend и удаляет E2-stub |
| kacho-deploy         | helm `openfga-bootstrap-job.yaml` — заменяет stub-model полной DSL; configmap `openfga-authorization-model` обновляется на полную DSL (overview §4); + new helm-template для `kacho-iam` worker enablement (env `KACHO_IAM_WORKERS__FGA_TUPLE_WRITER__ENABLED=true`); + new helm-values для break-glass env per-service |
| kacho-workspace      | docs/specs (этот файл); vault entries: `obsidian/kacho/edges/iam-to-openfga-check-write.md`, `edges/vpc-to-iam-check.md`, `edges/compute-to-iam-check.md`, `edges/loadbalancer-to-iam-check.md`, `packages/corelib-authz.md`, `packages/corelib-resourcelifecycle.md` (D-13), `packages/iam-internal-jobs-fga-tuple-writer.md`, `packages/iam-internal-jobs-subject-change-notifier.md`, `packages/iam-internal-jobs-resource-lifecycle-subscriber.md` (D-13 — renamed from resource-watch); KAC-tracker: `obsidian/kacho/KAC/KAC-108.md` |

### 3.3 Cross-repo runtime edges (новые на E3)

| Edge                                                           | Protocol      | Sync/async    | Purpose                                                                |
|----------------------------------------------------------------|---------------|---------------|------------------------------------------------------------------------|
| kacho-vpc / compute / lb / iam → kacho-iam:9091                | gRPC          | sync (≤20ms)  | `InternalIamService.Check(subj, rel, obj)` — per-RPC authz             |
| kacho-iam → openfga:8080                                       | HTTP REST     | sync          | `Write` / `Delete` / `Check` tuples (через openfga-go-sdk)             |
| kacho-iam → kacho-vpc:9091, compute:9091, lb:9091              | gRPC stream   | async         | **`InternalResourceLifecycleService.Subscribe`** (D-13, new — НЕ `InternalWatchService` (deprecated в workspace 1.0)) — kacho-iam subscribe'ит к каждому peer; peer пушит lifecycle events из своего outbox через server-stream; cursor (`last_event_id`) хранит kacho-iam в `kacho_iam.watch_cursors` |
| kacho-iam Postgres `kacho_iam_subjects` channel → per-service authz-cache listener | pg_notify | push          | Subject permission invalidation                                       |

> **Запрет #6**: `InternalIamService.Check` — port 9091, cluster-internal, не маршрутизируется через api-gateway на external TLS.

### 3.4 Why per-service interceptor (а не gateway)

Decision D-2 обосновывается:
1. **Typed access к request fields**: `vpc.NetworkService.Get(GetNetworkRequest{network_id})` — interceptor извлекает `network_id` из typed proto-message; gateway-centralized потребует reflection-based field-extraction → fragile, slower.
2. **Object resolution**: `vpc.NetworkService.Create(CreateNetworkRequest{project_id})` — object для Check = `project:<project_id>`, не `vpc_network` (создаваемый ресурс ещё не существует). Mapping `Create → object=parent` требует знания структуры — естественно живёт в сервисе-владельце.
3. **NFR-3 (≤1 Check per RPC)**: gateway-centralized + per-service дубль (если backend ещё раз Check для validation) — нарушает; per-service single-source.
4. **Composability**: future RPC проверяющие composite permissions (например `compute.InstanceService.Create` требует `editor on project` + `use on subnet` + `use on security_group`) — естественно описаны в backend metadata, не в gateway.

### 3.5 Latency budget для D-1 (per-RPC Check path, NFR-2 ≤20ms p95) — **CLOSED**

Decision D-1 централизует FGA-write/read в kacho-iam: per-service interceptor → `InternalIamService.Check` к kacho-iam:9091 → openfga:8080. Это +1 hop по сравнению с альтернативой «backend → openfga напрямую». Раскладка p95-бюджета (на cache miss; cache hit ≪1ms):

| Сегмент | p95 |
|---|---|
| Cache lookup (in-memory, sync.Map) | ≤0.5ms |
| Cache miss → gRPC client encode + send → kacho-iam (intra-cluster gRPC over HTTP/2; loopback / pod-to-pod ClusterIP) | ≤5ms |
| kacho-iam `InternalIamService.Check` handler (decode + validate + log) | ≤1ms |
| kacho-iam → openfga.Check (gRPC intra-cluster, тот же namespace `kacho`) | ≤5ms |
| OpenFGA Check execution (small store ≤10k tuples; computed relations ≤5 nesting) | ≤8ms |
| Response path (openfga → kacho-iam → backend, includes deserialization) | ≤0.5ms |
| **Total p95** | **≈20ms** — fits NFR-2 ≤20ms |

**Допущения:**
- kacho-iam, openfga, backend в одном Kubernetes namespace (`kacho`) → ClusterIP-routing, latency ≤1ms/hop median, ≤5ms p95 включая HTTP/2 settling.
- OpenFGA — 3 replicas (helm default; см. §8 Risks); load balancing через Kubernetes Service.
- Backend interceptor использует **per-process gRPC connection pool к kacho-iam** (corelib `authz.CheckClient` keeps long-lived connection; не пересоздаёт на каждый Check).

**Cache hit path** (steady-state ≥95% hit ratio — GWT-22): ≤0.5ms; не доходит до kacho-iam → openfga. Cache miss происходит на первом RPC subject'а после `make dev-up` / pod restart / TTL expiry (5s) / NOTIFY invalidate.

**Fallback / overrun:** если p95 >20ms — alert `KachoAuthzCheckLatencyHigh` (>20ms p95 для 5 минут sustained); ops escalates → openfga scale + Postgres FGA read replicas (Phase 2.1).

**Decision D-1 vs «backend → openfga direct»** (расходится на 1 hop = ≤5ms; backend → openfga direct sub-15ms p95, но требует distributed model_id + openfga client lib в каждом backend, расширение secrets-attack-surface). **Trade-off закрыт в пользу D-1** (централизация >wins для maintainability в MVP); если NFR-2 нарушается — фасад прозрачен для миграции на direct в Phase 2.1 (corelib `authz.CheckClient` interface; реализация под капотом меняется без backend changes).

**Q1 (Open Questions §11)** — закрыт этим расчётом.

---

## 4. Декомпозиция по компонентам (что именно реализуется)

### 4.1 OpenFGA authorization model — full DSL

**Файл:** `kacho-deploy/helm/umbrella/charts/openfga-bootstrap/files/authorization-model.fga` (заменяет stub из E0).

**Содержание:** DSL целиком из overview §4 (lines 282-398) — типы `user`, `service_account`, `group`, `role` (без relations, source-of-truth в kacho_iam.roles), `account`, `project`, `vpc_network`, `vpc_subnet`, `vpc_security_group`, `vpc_route_table`, `vpc_address`, `compute_instance`, `compute_disk`, `lb_nlb`, `lb_target_group`.

**Replace mechanism (D-10):** Bootstrap-job в `kacho-deploy/helm/umbrella/templates/openfga-bootstrap-job.yaml`:
1. `kubectl get secret kacho-iam-openfga-store -o jsonpath='{.data.store_id}'` — извлекает store_id из E0.
2. `fga --api-url=$OPENFGA_URL --store-id=$STORE_ID model write --file=/etc/openfga-model/authorization-model.fga` — пишет новую модель; возвращает `model_id`.
3. `kubectl patch secret kacho-iam-openfga-store -p '{"data":{"authorization_model_id":"<base64>"}}'` — обновляет Secret с новым `authorization_model_id`.
4. Idempotent: re-apply детектирует `if [ "$EXISTING_MODEL_ID" = "$NEW_MODEL_ID" ]` через `fga model list --store-id` + compare with latest → skip-write.

**Что важно для E0→E3 миграции:** stub-model из E0 содержит только `type user` (без relations) — заведомо нет production-tuples. Перезапись на full DSL не теряет данные; tuples начнут писаться при первом `AccessBindingService.Upsert` post-E3.

**Где хранится SHA-256 локального DSL (I8):** хеш `dsl_sha256` (SHA-256 от `authorization-model.fga`-файла на момент применения) хранится в **`kacho_iam.fga_model_version.dsl_sha256`** (см. миграцию `0007_fga_model_version_track.sql` ниже в §4.2). На re-apply bootstrap-job вычисляет SHA локально → сверяет с current row для активного `authorization_model_id` (по факту, через `SELECT dsl_sha256 FROM kacho_iam.fga_model_version WHERE authorization_model_id = $current_id`) → если совпадают, skip-write (GWT-02). Это единственное место хранения; helm ConfigMap содержит **DSL-источник** (для применения), но НЕ хеш.

### 4.2 kacho-iam — outbox + worker'ы

**Миграция `0005_fga_outbox.sql`:**

```sql
CREATE TABLE kacho_iam.outbox (
    id            bigserial    PRIMARY KEY,
    event_type    text         NOT NULL,  -- 'fga.tuple.write' | 'fga.tuple.delete'
    payload       jsonb        NOT NULL,  -- {tuples:[{user,relation,object}, ...]}
    created_at    timestamptz  NOT NULL DEFAULT now(),
    sent_at       timestamptz,            -- NULL = pending; set when worker successfully writes to FGA
    last_error    text,                   -- error from last failed attempt
    attempt_count integer      NOT NULL DEFAULT 0,

    CONSTRAINT outbox_event_type_check
        CHECK (event_type IN ('fga.tuple.write', 'fga.tuple.delete'))
);

CREATE INDEX outbox_pending_idx ON kacho_iam.outbox (created_at) WHERE sent_at IS NULL;
```

**Миграция `0006_subject_change_outbox.sql`:**

```sql
CREATE TABLE kacho_iam.subject_change_outbox (
    id            bigserial    PRIMARY KEY,
    subject_id    text         NOT NULL,  -- usr_xxx / sva_xxx / grp_xxx
    op            text         NOT NULL,  -- 'binding_upsert' | 'binding_delete' | 'group_member_change'
    created_at    timestamptz  NOT NULL DEFAULT now(),
    notified_at   timestamptz,

    CONSTRAINT subject_change_op_check
        CHECK (op IN ('binding_upsert', 'binding_delete', 'group_member_change'))
);

CREATE INDEX subject_change_pending_idx ON kacho_iam.subject_change_outbox (created_at) WHERE notified_at IS NULL;
```

**Миграция `0007_fga_model_version_track.sql`:**

```sql
CREATE TABLE kacho_iam.fga_model_version (
    id                       bigserial   PRIMARY KEY,
    authorization_model_id   text        NOT NULL UNIQUE,
    dsl_sha256               text        NOT NULL,
    applied_at               timestamptz NOT NULL DEFAULT now(),
    applied_by               text        NOT NULL DEFAULT 'bootstrap-job'
);
```

**Worker `internal/jobs/fga_tuple_writer.go`:**
- Loop: `SELECT id, event_type, payload FROM outbox WHERE sent_at IS NULL ORDER BY id LIMIT 100`.
- Per row: `openfga.Write` или `openfga.Delete` по `event_type`; on success `UPDATE outbox SET sent_at=now() WHERE id=$1`; on failure `UPDATE outbox SET attempt_count=attempt_count+1, last_error=$err WHERE id=$1`.
- Retry: exponential backoff (5s → 10s → 30s → 60s) до attempt_count=10; после — alert via Prometheus + manual ops intervention.
- Idempotent: openfga-go-sdk `Write` на existing tuple возвращает 409 — мапится в success (treat as already-written).

**Worker `internal/jobs/subject_change_notifier.go`:**
- Loop: `SELECT id, subject_id FROM subject_change_outbox WHERE notified_at IS NULL ORDER BY id LIMIT 100`.
- Per row: `pg_notify('kacho_iam_subjects', subject_id::text)`; `UPDATE subject_change_outbox SET notified_at=now()`.
- Notification frequency: ≤500ms idle-loop sleep + LISTEN на own channel `kacho_iam_subject_outbox_added` (трuger `subject_change_outbox_notify_trigger` после INSERT — wake-up worker без polling).

**Worker `internal/jobs/resource_lifecycle_subscriber.go`** (D-13 — НЕ legacy `resource_watch.go`):
- Подписан на **`InternalResourceLifecycleService.Subscribe`** (long-lived gRPC server-stream) каждого resource-сервиса: kacho-vpc, kacho-compute, kacho-loadbalancer (новый RPC, см. §3.2 / §3.3).
- Filter events: `event.resource_kind IN ('network','subnet','security_group','address','instance','disk','nlb','target_group')` + `event.op IN ('Create','Delete','Move')`.
- Per event: построить FGA-tuple(s) и `INSERT INTO kacho_iam.outbox (event_type, payload)` в TX (через `repo.OutboxRepo.Insert(ctx, tx, …)`).
- `Move` (project_id changed): два события — `delete old parent tuple` + `write new parent tuple`.
- Restart-resistance: cursor хранится в `kacho_iam.watch_cursors (service text PRIMARY KEY, last_event_id text)`; на restart — resume с `last_event_id`, не пропускает события.
- **Peer-service outbox retention** (см. §8 Risks I9): vpc/compute/lb обязаны хранить lifecycle-events ≥ **1 hour** (bump default helm-values `outbox.retention=1h`); если меньше — на kacho-iam restart > retention окно дольше — события теряются → FGA-tuples desync → MANUAL fga-tuples reconcile required (Phase 2.1+ tool); E3 не покрывает.

### 4.3 corelib `authz/` package

> **Важно (B1, two caches not one)**: в системе живут **два разных кеша** с разной семантикой — НЕ путать:
>
> | Кеш | Где | Ключ | TTL | Инвалидация | Назначение |
> |---|---|---|---|---|---|
> | **Subject lookup cache** (E2) | api-gateway auth-interceptor | OIDC subject claim (`sub`) → Principal (usr_xxx / sva_xxx) | **30s** | TTL only | Снизить нагрузку на `InternalIamService.LookupSubject` при steady-state traffic |
> | **Check-result cache** (E3 — этот раздел) | per-service authz-interceptor (vpc/compute/lb/iam) | `(principal_id, relation, object_type, object_id)` → `allowed=true` | **5s** | TTL + `pg_notify('kacho_iam_subjects', subject_id)` push-invalidate | Снизить FGA-Check call rate; обеспечить ≤10s revoke propagation (NFR-5) |
>
> Разные кеши → разные ключи → разные TTL → разные мест invalidation. Здесь и далее в §4.3, §4.8, §5.7 «cache» = **Check-result cache** (TTL=5s).

**Файлы:**
- `kacho-corelib/authz/interceptor.go` — gRPC unary + stream interceptor.
- `kacho-corelib/authz/cache.go` — TTL-cache positive results.
- `kacho-corelib/authz/check_client.go` — wrapper над gRPC client к InternalIamService.Check.

**Interceptor logic (unary):**
1. Извлечь `Principal` из `ctx.Value(principal.CtxKey)` (E2-corelib).
2. Lookup `(object_type, relation, object_id_extractor)` в per-service `metadata.PermissionMap` (передаётся через DI; per-service mapping).
3. Если RPC не в map — fail-closed (`PermissionDenied` + WARN `unauthorized_rpc_not_mapped`).
4. Resolve `object_id` через `extractor(req)` — typed function per-RPC.
5. Cache.Get(`(principal.id, relation, object_type, object_id)`) → если hit positive → next; если hit negative (timestamped expired) → перезапросить.
6. Cache.Miss → `checkClient.Check(ctx, subj=principal.id, rel=relation, obj=fmt.Sprintf("%s:%s", object_type, object_id))` → если `allowed=true` → cache.Set positive (TTL=5s) + next; если `allowed=false` → `PermissionDenied` (нет cache).
7. On FGA-unavailable (gRPC `Unavailable`) → fail-closed (`PermissionDenied`); если `KACHO_<SVC>_AUTHZ__BREAKGLASS=true` → next + WARN `authz_breakglass_used`.

**Cache invalidation:**
- Dedicated pgx-conn (не из пула) → `LISTEN kacho_iam_subjects` (Postgres NOTIFY-channel).
- On NOTIFY (`subject_id` в payload) → `cache.InvalidateBySubject(subject_id)` (sweep по entries).
- Reconnect: на conn-drop → reconnect + initial drain (`SELECT subject_id FROM kacho_iam.subject_change_outbox WHERE notified_at > $last_seen` через Internal gRPC `IamService.DrainRecentChanges` для catch-up; или просто полная invalidation при reconnect — conservative).

**Cache TTL = 5s** (D-9). Worst-case revoke propagation:
- t=0: AccessBindingService.Delete COMMIT → `subject_change_outbox` INSERT + `outbox` INSERT (delete-tuple)
- t≤500ms: `subject_change_notifier` drain → `pg_notify`
- t≤1s: per-service LISTEN-loop получает NOTIFY → cache.InvalidateBySubject
- t≤2s: `fga_tuple_writer` drain → openfga.Delete tuple
- Next Check after t≥1s (cache miss) → openfga.Check returns allowed=false → PermissionDenied
- **Worst-case (NOTIFY lost / kacho-iam restart between drain и notify)**: TTL=5s expiry → cache miss → openfga.Check fresh → openfga have updated tuple by t≤2s → PermissionDenied at t≤5s
- **Absolute worst-case (fga_tuple_writer retry-backoff exhausted)**: openfga still has stale tuple → Check returns allowed=true → false-positive. Mitigation: tuple-writer max-retry alert при attempt_count>5 → ops intervention. SLA: ≤10s assuming healthy fga_tuple_writer.

### 4.4 Per-service metadata.go — RPC permission map

**Файл `kacho-vpc/internal/metadata/permission_map.go`:**

```go
package metadata

import (
    "context"
    "github.com/PRO-Robotech/kacho-corelib/authz"
    vpcv1 "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1"
)

var PermissionMap = authz.RPCMap{
    // NetworkService
    "/kacho.cloud.vpc.v1.NetworkService/Create": {
        ObjectType: "project",
        Relation:   "editor",
        ObjectExtractor: func(req any) (string, error) {
            r := req.(*vpcv1.CreateNetworkRequest)
            return r.GetProjectId(), nil
        },
    },
    "/kacho.cloud.vpc.v1.NetworkService/Get": {
        ObjectType: "vpc_network",
        Relation:   "viewer",
        ObjectExtractor: func(req any) (string, error) {
            r := req.(*vpcv1.GetNetworkRequest)
            return r.GetNetworkId(), nil
        },
    },
    "/kacho.cloud.vpc.v1.NetworkService/Update": {
        ObjectType: "vpc_network", Relation: "editor",
        ObjectExtractor: func(req any) (string, error) {
            return req.(*vpcv1.UpdateNetworkRequest).GetNetworkId(), nil
        },
    },
    "/kacho.cloud.vpc.v1.NetworkService/Delete": {
        ObjectType: "vpc_network", Relation: "admin",
        ObjectExtractor: func(req any) (string, error) {
            return req.(*vpcv1.DeleteNetworkRequest).GetNetworkId(), nil
        },
    },
    "/kacho.cloud.vpc.v1.NetworkService/List": {
        ObjectType: "project", Relation: "viewer",
        ObjectExtractor: func(req any) (string, error) {
            return req.(*vpcv1.ListNetworksRequest).GetProjectId(), nil
        },
    },
    // SubnetService, AddressService, SecurityGroupService, RouteTableService,
    // GatewayService, PrivateEndpointService, NetworkInterfaceService — аналогично.
    // ИТОГО ~40 RPC × {Create/Get/Update/Delete/List/...} = ~40 entries для kacho-vpc.

    // InternalResourceLifecycleService (D-13) и прочие Internal* — НЕ покрываются authz (доступ через cluster-internal :9091; запрет #6).
}
```

**Аналогично:**
- `kacho-compute/internal/metadata/permission_map.go` — ~30 entries (InstanceService, DiskService, ImageService, SnapshotService, DiskTypeService).
- `kacho-loadbalancer/internal/metadata/permission_map.go` — ~15 entries (NetworkLoadBalancerService, TargetGroupService).
- `kacho-iam/internal/metadata/permission_map.go` — ~30 entries (AccountService, ProjectService, UserService, ServiceAccountService, GroupService, RoleService, AccessBindingService).

**Edge case — scope-conditional object (overview §4.2):**
- `iam.AccessBindingService.Upsert` — object зависит от scope в request: `request.scope.account_id` ⇒ `account:<id>`, `request.scope.project_id` ⇒ `project:<id>`, `request.scope.resource_*` ⇒ `<resource_type>:<id>`.
- Extractor возвращает оба `(object_type, object_id)` через extended interface (`ObjectResolver`); метаdата для таких RPC использует `Resolver` вместо статических `ObjectType`+`Extractor`.

### 4.5 kacho-iam InternalIamService.Check handler

**Proto** (`kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto` — extension):

```protobuf
service InternalIamService {
  // E0/E2 existing:
  rpc LookupSubject(LookupSubjectRequest) returns (LookupSubjectResponse);
  rpc UpsertUserMirror(UpsertUserMirrorRequest) returns (User);

  // E3 new:
  rpc Check(CheckRequest) returns (CheckResponse);
}

message CheckRequest {
  string subject_id  = 1; // "user:usr_xxx" | "service_account:sva_xxx" | "group:grp_xxx#member"
  string relation    = 2; // "viewer" | "editor" | "admin" | "use" | "start_stop"
  string object      = 3; // "project:prj_xxx" | "vpc_network:enpYYY" | "account:acc_xxx" | ...
  string trace_id    = 4; // for correlation logs
}

message CheckResponse {
  bool   allowed = 1;
  string reason  = 2; // empty if allowed=true; human-readable on deny
}
```

**Handler** (`kacho-iam/internal/apps/kacho/internal_api/iam/check.go`):
- Thin wrapper: `openfga.Check(ctx, model_id=fromCache, store_id=fromCache, subject, relation, object)` → return.
- Latency budget: ≤20ms p95 (NFR-2) — openfga.Check сам по себе <10ms p95 на small store; sub-30ms gRPC round-trip iam→openfga inside cluster.
- Caching на side iam: НЕТ (cache на side каждого backend interceptor — overview §5 решение #7).

### 4.6 kacho-iam — AccessBindingService.Upsert/Delete (расширение E0)

E0 уже имеет CRUD `access_bindings`. E3 добавляет **транзакционный outbox-write**:

**Upsert (расширение от E0 stub):**

```go
// kacho-iam/internal/apps/kacho/api/access_binding/upsert.go
func (uc *UpsertUseCase) Execute(ctx context.Context, in UpsertInput) (Output, error) {
    tx, err := uc.txMgr.Begin(ctx)
    defer tx.Rollback(ctx)

    // 1. INSERT (or ON CONFLICT DO UPDATE) row в access_bindings
    binding, err := uc.bindingRepo.Upsert(ctx, tx, ...)

    // 2. Expand role.permissions → []FGATuple (см. overview §4.1)
    tuples := expandRoleToTuples(binding.Subject, binding.Role, binding.Scope)

    // 3. INSERT outbox row {event_type='fga.tuple.write', payload={tuples}}
    if err := uc.outboxRepo.Insert(ctx, tx, "fga.tuple.write", tuples); err != nil { return ... }

    // 4. INSERT subject_change_outbox row {subject_id, op='binding_upsert'}
    if err := uc.subjectChangeRepo.Insert(ctx, tx, binding.SubjectID, "binding_upsert"); err != nil { return ... }

    // 5. COMMIT (atomic — все три INSERT либо все, либо никакие)
    return tx.Commit(ctx)
}
```

**Delete:** аналогично — `event_type='fga.tuple.delete'`, `op='binding_delete'`.

**Role permissions → FGA tuples expansion (`expandRoleToTuples`):**

| Role (system)        | Scope                | Resulting FGA tuple(s)                                                                |
|----------------------|----------------------|---------------------------------------------------------------------------------------|
| roles/iam.admin      | account:acc_X        | `user:usr_Y admin account:acc_X`                                                      |
| roles/iam.viewer     | account:acc_X        | `user:usr_Y member account:acc_X` (для viewer-на-IAM — read-access через member)     |
| roles/vpc.admin      | project:prj_X        | `user:usr_Y admin project:prj_X` (computed на vpc_network/subnet/sg/... admin)        |
| roles/vpc.editor     | project:prj_X        | `user:usr_Y editor project:prj_X` (computed на vpc_*  editor)                          |
| roles/vpc.viewer     | project:prj_X        | `user:usr_Y viewer project:prj_X`                                                     |
| roles/compute.admin  | project:prj_X        | `user:usr_Y admin project:prj_X` **+** для каждого `compute_*`-типа explicit relation: но Decision D-4 говорит «computed relations» — единственная tuple `admin project` уже достаточна |
| roles/loadbalancer.* | project:prj_X        | то же по pattern |

> Для system-roles `roles/<module>.<level>` и project-scope — раскладка тривиальна (одна tuple `<level> project:<id>`); computed-relations в DSL покрывают все child-типы (vpc_network, vpc_subnet, …).
> Для custom-роли — раскладка ограничена под-набором default-permissions; non-default permissions → reject в `RoleService.Create` (E0 validation); итог: custom-role раскладывается так же как одна из default-ролей.
> Resource-scope binding (`scope.resource_type='vpc_network', resource_id='enpXXX'`) — раскладывается в tuple `<level> vpc_network:enpXXX` (минуя project — для granular на 1 ресурс).

### 4.7 kacho-iam — Resource lifecycle tuples writer (D-1, D-13)

**`internal/jobs/resource_lifecycle_subscriber.go`** (D-13: subscribe на новый `InternalResourceLifecycleService.Subscribe` — НЕ deprecated `InternalWatchService`):

```go
type ResourceLifecycleSubscriber struct {
    vpcClient        vpcv1.InternalResourceLifecycleServiceClient
    computeClient    computev1.InternalResourceLifecycleServiceClient
    lbClient         lbv1.InternalResourceLifecycleServiceClient
    outboxRepo       OutboxRepo
    cursorRepo       WatchCursorRepo
}

func (rs *ResourceLifecycleSubscriber) RunVPC(ctx context.Context) error {
    cursor, _ := rs.cursorRepo.Get(ctx, "vpc")
    stream, err := rs.vpcClient.Subscribe(ctx, &vpcv1.SubscribeRequest{ResumeFromEventId: cursor})
    for {
        ev, err := stream.Recv()
        if err != nil { /* reconnect, resume from cursor */ }
        switch ev.Kind {
        case "network":
            rs.handleNetworkEvent(ctx, ev)
        case "subnet":
            rs.handleSubnetEvent(ctx, ev)
        // ...
        }
        rs.cursorRepo.Update(ctx, "vpc", ev.EventId)
    }
}

func (rs *ResourceLifecycleSubscriber) handleNetworkEvent(ctx context.Context, ev ResourceLifecycleEvent) {
    switch ev.Op {
    case "Create":
        tuple := FGATuple{User: fmt.Sprintf("project:%s", ev.ProjectId), Relation: "project", Object: fmt.Sprintf("vpc_network:%s", ev.ResourceId)}
        rs.outboxRepo.Insert(ctx, nil, "fga.tuple.write", []FGATuple{tuple})
    case "Delete":
        tuple := FGATuple{User: fmt.Sprintf("project:%s", ev.ProjectId), Relation: "project", Object: fmt.Sprintf("vpc_network:%s", ev.ResourceId)}
        rs.outboxRepo.Insert(ctx, nil, "fga.tuple.delete", []FGATuple{tuple})
    case "Move":
        // project_id changed: delete old + write new
        rs.outboxRepo.Insert(ctx, nil, "fga.tuple.delete", []FGATuple{{User: fmt.Sprintf("project:%s", ev.OldProjectId), Relation: "project", Object: fmt.Sprintf("vpc_network:%s", ev.ResourceId)}})
        rs.outboxRepo.Insert(ctx, nil, "fga.tuple.write", []FGATuple{{User: fmt.Sprintf("project:%s", ev.ProjectId), Relation: "project", Object: fmt.Sprintf("vpc_network:%s", ev.ResourceId)}})
    }
}
```

**Параллельно для:**
- `vpc_subnet` parent = `vpc_network:<network_id>` (по факту иерархия subnet→network, не subnet→project).
- `vpc_security_group` parent = `vpc_network:<network_id>`.
- `vpc_address` parent = `project:<project_id>` (Address привязан к Project, не к Network — overview §4 DSL line 354).
- `compute_instance`, `compute_disk` parent = `project:<project_id>`.
- `lb_nlb`, `lb_target_group` parent = `project:<project_id>`.

**Что НЕ writeable lifecycle:** Resource-scope `AccessBinding` (custom granular) — handled через `AccessBindingService.Upsert` напрямую (4.6).

### 4.8 Fail-modes (D-6)

**Default fail-closed:**
- OpenFGA unavailable (network error, timeout >2s) → interceptor возвращает `PermissionDenied` + Prometheus counter `kacho_authz_fga_unavailable_denials_total`.
- InternalIamService.Check unavailable → fail-closed (same).
- Cache disabled → fail-closed (configuration error).

**Break-glass:**
- ENV per-service: `KACHO_VPC_AUTHZ__BREAKGLASS=true` / `KACHO_COMPUTE_AUTHZ__BREAKGLASS=true` / ...
- При true: interceptor пропускает все RPC без Check; logs WARN `authz_breakglass_used` (rate-limited 1/s); Prometheus alert `KachoAuthzBreakglassActive`.
- Production deploy: env **не выставлен** (helm values default `breakglass: false`); ops может выставить вручную через `kubectl set env deployment/kacho-vpc KACHO_VPC_AUTHZ__BREAKGLASS=true` в incident response (rollback по timer).

**Dev convenience:**
- `make dev-up` поднимает с `breakglass: false` по умолчанию; integration tests без auth-token упадут с PermissionDenied — это **expected** (тест должен передавать valid Principal через E2 auth-interceptor mock).
- Local dev override: `kacho-deploy/values.dev.yaml` может содержать `breakglass: true` для быстрого smoke-теста без OIDC setup.

---

## 5. GWT-сценарии

Все сценарии E3.GWT-NN. Минимум **20 сценариев** по группам.

### 5.1 OpenFGA bootstrap (3 сценария)

#### Scenario E3.GWT-01: helm install заменяет stub-model на полную DSL — store created + new model_id записан в Secret

**ID:** 2.0-E3-GWT-01

**Given** свежий dev-стенд (`make dev-down` если был поднят)
**And** E0 (KAC-105) merged — stub-model (`type user`) уже применена при первом `make dev-up` post-E0
**And** Secret `kacho-iam-openfga-store` существует со старым `authorization_model_id` (stub)

**When** разработчик выполняет `cd project/kacho-deploy && make dev-up` (helm upgrade)
**And** helm hook `openfga-bootstrap` job стартует post-upgrade
**And** job извлекает `store_id` из существующего Secret
**And** job пишет полную DSL (~100 строк) через `fga model write --file=/etc/openfga-model/authorization-model.fga --store-id=$STORE_ID` → возвращает новый `authorization_model_id`
**And** job выполняет `kubectl patch secret kacho-iam-openfga-store -p '{"data":{"authorization_model_id":"<base64-new>"}}'`

**Then** `kubectl get secret kacho-iam-openfga-store -o jsonpath='{.data.authorization_model_id}' | base64 -d` возвращает новый model_id (отличается от stub)
**And** `kubectl exec openfga-XXX -- fga model list --store-id=$STORE_ID` показывает 2+ models (stub + полная); latest = full DSL
**And** Job `openfga-bootstrap` status = `Complete` (одна попытка, `succeeded: 1`)
**And** `kacho_iam.fga_model_version` содержит row с новым `authorization_model_id` + `dsl_sha256` + `applied_at`
**And** kacho-iam pod на startup читает `authorization_model_id` из Secret через `env: valueFrom: secretKeyRef:` и использует для всех Check/Write calls

#### Scenario E3.GWT-02: helm upgrade с тем же DSL — idempotent (skip-write, ничего не меняется)

**ID:** 2.0-E3-GWT-02

**Given** dev-стенд поднят (GWT-01 выполнен), full DSL применена, `authorization_model_id` в Secret = `mdl_v2`
**And** `kacho_iam.fga_model_version` содержит ровно одну row для `mdl_v2`

**When** разработчик выполняет `make dev-up` повторно (без изменений в DSL — `authorization-model.fga` SHA-256 не изменился)
**And** helm hook `openfga-bootstrap` job re-runs
**And** job вычисляет SHA-256 локального DSL → сравнивает с `kacho_iam.fga_model_version.dsl_sha256` для current `mdl_v2`

**Then** job логирует `model_id mdl_v2 matches dsl SHA-256, skipping write` и exit-code = 0
**And** в `kacho_iam.fga_model_version` НЕТ нового row (count = 1)
**And** Secret `authorization_model_id` не меняется
**And** `kubectl exec openfga-XXX -- fga model list --store-id=$STORE_ID` показывает то же кол-во моделей, что до

#### Scenario E3.GWT-03: helm rollback на старый chart — bootstrap-job не падает, current model остаётся в FGA

**ID:** 2.0-E3-GWT-03

**Given** dev-стенд поднят с `mdl_v2` (full DSL)
**And** разработчик выпустил `mdl_v3` (изменил DSL — добавил новый тип) → `make dev-up` apply → Secret = `mdl_v3`

**When** разработчик решает откатить: `helm rollback kacho-umbrella <revision-of-v2>`
**And** Helm применяет old templates (включая bootstrap-job с DSL версии v2)
**And** Job re-runs

**Then** Job детектирует `mdl_v2` SHA-256 в локальном файле — уже в `kacho_iam.fga_model_version`, но Secret содержит `mdl_v3`
**And** Job **переключает Secret обратно на `mdl_v2`** (новый row в `fga_model_version` для `mdl_v2` НЕ создаётся — уже существует)
**And** OpenFGA сохраняет обе версии модели (`mdl_v2` и `mdl_v3`); active = `mdl_v2`
**And** Существующие tuples — продолжают работать (Decision D-10 — tuples model-agnostic для backward-compatible изменений)
**And** Если `mdl_v3 → mdl_v2` изменение DSL **breaking** (relation удалён) — Check для удалённого relation вернёт error от OpenFGA → interceptor fail-closed (`PermissionDenied`); ops alert через `kacho_authz_fga_check_errors_total`

### 5.2 AccessBinding → tuples (3 сценария)

#### Scenario E3.GWT-04: AccessBindingService.Upsert (User, vpc.editor, Project) пишет outbox + tuple появляется в FGA ≤2s

**ID:** 2.0-E3-GWT-04

**Given** В `kacho_iam.users` есть `usr_alice`; в `kacho_iam.projects` есть `prj_dev` (account=`acc_default`)
**And** В `kacho_iam.access_bindings` НЕТ строк для `(usr_alice, vpc.editor, prj_dev)`
**And** OpenFGA store healthy; `fga tuple read --user=user:usr_alice --object=project:prj_dev` возвращает empty

**When** Admin-клиент вызывает `POST /iam/v1/accessBindings` с payload:
- `subject = { type: 'user', id: 'usr_alice' }`
- `role = 'roles/vpc.editor'`
- `scope = { type: 'project', project_id: 'prj_dev' }`

**Then** Response — `Operation{done=true, response: AccessBinding{id: 'bnd_xxx', ...}}` (sync done в E0; в E3 — same)
**And** `SELECT count(*) FROM kacho_iam.access_bindings WHERE subject_id='usr_alice' AND role_id='rol00000000000000vpced' AND resource_type='iam_project' AND resource_id='prj_dev'` = 1
**And** `SELECT count(*) FROM kacho_iam.outbox WHERE event_type='fga.tuple.write' AND payload->'tuples' @> '[{"user":"user:usr_alice","relation":"editor","object":"project:prj_dev"}]'` = 1
**And** `SELECT count(*) FROM kacho_iam.subject_change_outbox WHERE subject_id='usr_alice' AND op='binding_upsert'` = 1
**And** В течение ≤2s `fga_tuple_writer` worker drain'ит outbox-row → `openfga.Write` succeeds → `UPDATE outbox SET sent_at=now() WHERE id=$1`
**And** `SELECT sent_at IS NOT NULL FROM kacho_iam.outbox WHERE id=$1` = true в ≤2s
**And** `fga tuple read --user=user:usr_alice --object=project:prj_dev` возвращает `[{relation: editor, ...}]`
**And** В течение ≤500ms `subject_change_notifier` worker drain → `pg_notify('kacho_iam_subjects', 'usr_alice')`
**And** В per-service authz-cache (kacho-vpc / compute / lb) entries для `usr_alice` invalidated (даже если до этого их не было — no-op для уже пустого cache)

#### Scenario E3.GWT-05: AccessBindingService.Upsert (ServiceAccount, vpc.viewer, Project) — tuple с SA-prefix корректно записан

**ID:** 2.0-E3-GWT-05

**Given** В `kacho_iam.service_accounts` есть `sva_ci_runner` в `prj_dev`

**When** Admin-клиент вызывает `POST /iam/v1/accessBindings` с:
- `subject = { type: 'service_account', id: 'sva_ci_runner' }`
- `role = 'roles/vpc.viewer'`
- `scope = { type: 'project', project_id: 'prj_dev' }`

**Then** `kacho_iam.outbox` содержит row `{event_type: 'fga.tuple.write', payload: {tuples: [{user: 'service_account:sva_ci_runner', relation: 'viewer', object: 'project:prj_dev'}]}}` (note: `user:` префикс — `service_account:`, не `user:`)
**And** В ≤2s tuple в OpenFGA: `fga tuple read --user=service_account:sva_ci_runner --object=project:prj_dev` → `[{relation: viewer}]`
**And** `subject_change_outbox.subject_id = 'sva_ci_runner'` (без префикса — id хватает unique через `sva_` prefix)

#### Scenario E3.GWT-06: AccessBindingService.Upsert (Group, vpc.editor, Project) — tuple с #member resolution

**ID:** 2.0-E3-GWT-06

**Given** В `kacho_iam.groups` есть `grp_dev_team` в `acc_default`
**And** Members: usr_bob, usr_charlie (через `POST /iam/v1/groups/grp_dev_team/members`)
**And** При group-member-add — выписаны 2 tuples (см. overview Scenario E4.GWT-06): `group:grp_dev_team member user:usr_bob`, `group:grp_dev_team member user:usr_charlie`

**When** Admin-клиент вызывает `POST /iam/v1/accessBindings` с:
- `subject = { type: 'group', id: 'grp_dev_team' }`
- `role = 'roles/vpc.editor'`
- `scope = { type: 'project', project_id: 'prj_dev' }`

**Then** `kacho_iam.outbox` содержит row с tuple `{user: 'group:grp_dev_team#member', relation: 'editor', object: 'project:prj_dev'}` (note: `#member` — указывает «все members группы»)
**And** В ≤2s в OpenFGA: `fga check --user=user:usr_bob --relation=editor --object=project:prj_dev` → `allowed: true` (через computed group#member)
**And** Аналогично для charlie: `fga check --user=user:usr_charlie --relation=editor --object=project:prj_dev` → `allowed: true`
**And** `subject_change_outbox` содержит **N rows** (по одному per member группы): `subject_id='usr_bob'`, `subject_id='usr_charlie'` — group binding инвалидирует cache всех members (kacho-iam knows group membership через `group_members` table)

### 5.3 AccessBinding delete → untuples (2 сценария)

#### Scenario E3.GWT-07: AccessBindingService.Delete — tuple удаляется из FGA, subject-cache invalidated

**ID:** 2.0-E3-GWT-07

**Given** GWT-04 выполнен — usr_alice имеет editor на prj_dev; tuple `user:usr_alice editor project:prj_dev` в FGA
**And** Per-service authz-cache в kacho-vpc содержит positive entry `(usr_alice, editor, project:prj_dev)` (после ≥1 RPC call)

**When** Admin-клиент вызывает `DELETE /iam/v1/accessBindings/{bnd_xxx}`

**Then** `SELECT count(*) FROM kacho_iam.access_bindings WHERE id='bnd_xxx'` = 0
**And** `kacho_iam.outbox` содержит row `{event_type: 'fga.tuple.delete', payload: {tuples: [{user: 'user:usr_alice', relation: 'editor', object: 'project:prj_dev'}]}}`
**And** `kacho_iam.subject_change_outbox` содержит row `{subject_id: 'usr_alice', op: 'binding_delete'}`
**And** В ≤2s `fga_tuple_writer` worker → `openfga.Delete(tuple)` succeeds; tuple отсутствует в FGA: `fga tuple read --user=user:usr_alice --object=project:prj_dev` → empty
**And** В ≤500ms `subject_change_notifier` → `pg_notify('kacho_iam_subjects', 'usr_alice')`
**And** В kacho-vpc authz-cache entry для `usr_alice` invalidated (`cache.Get(usr_alice, editor, project:prj_dev)` → miss)
**And** Следующий call `POST /vpc/v1/networks` с Principal=usr_alice → cache.Miss → `InternalIamService.Check` → openfga.Check → `allowed=false` → `PermissionDenied`

#### Scenario E3.GWT-08: User.Delete без cascade — admin вручную revoke'ит все bindings до Delete (D-12)

**ID:** 2.0-E3-GWT-08

**Given** usr_bob имеет 3 binding'а: `(vpc.editor, prj_dev)` (id `bnd_001`), `(compute.viewer, prj_dev)` (id `bnd_002`), `(lb.viewer, prj_test)` (id `bnd_003`)
**And** В FGA соответственно 3 tuples
**And** В per-service cache есть entries для bob
**And** **(D-12)** `UserService.Delete` НЕ имеет cascade-bindings behavior; остаётся E0 поведение — `FailedPrecondition` если есть bindings; admin обязан revoke вручную → потом Delete

**When (попытка 1 — DENY)** Admin-клиент вызывает `DELETE /iam/v1/users/usr_bob` **без** предварительного revoke

**Then** Response — `FailedPrecondition` `{message: "user has active access_bindings, revoke them first; found 3 bindings"}` (E0 sentinel preserved)
**And** `SELECT count(*) FROM kacho_iam.users WHERE id='usr_bob'` = 1 (НЕ удалён)
**And** `kacho_iam.access_bindings` для usr_bob — нетронут (3 rows)
**And** Никаких outbox / subject_change_outbox rows НЕ записано

**When (попытка 2 — manual revoke chain)** Admin последовательно вызывает:
1. `DELETE /iam/v1/accessBindings/bnd_001` → 202 Operation done; pipeline (outbox `fga.tuple.delete` для vpc.editor tuple + subject_change `usr_bob op=binding_delete`)
2. `DELETE /iam/v1/accessBindings/bnd_002` → 202 Operation done; pipeline (compute.viewer tuple delete + subject_change)
3. `DELETE /iam/v1/accessBindings/bnd_003` → 202 Operation done; pipeline (lb.viewer tuple delete + subject_change)
4. `DELETE /iam/v1/users/usr_bob`

**Then** После 1-3: `SELECT count(*) FROM kacho_iam.access_bindings WHERE subject_id='usr_bob'` = 0; **3** outbox rows `{event_type: 'fga.tuple.delete', ...}` записаны (one per binding); **3** subject_change_outbox rows `{subject_id: 'usr_bob', op: 'binding_delete'}` записаны (один per AccessBindingService.Delete call) — admin видит каждый revoke как отдельную audit-trail запись
**And** В ≤2s все 3 tuples в FGA удалены: `fga tuple read --user=user:usr_bob` → empty
**And** В ≤500ms cache invalidation отправлена (после каждого revoke; per-service cache для usr_bob инвалидируется на каждом NOTIFY)
**And** После шага 4: `SELECT count(*) FROM kacho_iam.users WHERE id='usr_bob'` = 0 (precondition satisfied — no bindings)
**And** Следующий RPC с Principal=usr_bob (если кто-то ещё держит токен) → `PermissionDenied` (no tuples, no allowed; user-mirror gone)

**Note (D-12 rationale):** E3 не вводит cascade-delete bindings ради:
- **Atomic-TX preservation** — cascade на user с 100+ bindings = 100+ outbox rows + 100+ subject_change rows в одной TX → blocks `kacho_iam.outbox` table + большой commit-lock; manual chain распределяет нагрузку.
- **Audit-trail** — admin видит и контролирует каждый revoke (per-binding log + Operation); cascade скрывает детали.
- **Запрет #4 (no cascade через границу сервиса)** — выходит из строя если cascade подразумевает peer-service notification fanout.

Cascade-delete bindings — **Phase 2.1+** при реальной необходимости (через background job с rate-limiting, не в одной TX).

### 5.4 Resource lifecycle → parent tuples (3 сценария)

#### Scenario E3.GWT-09: Network.Create в kacho-vpc — kacho-iam resource-lifecycle-subscriber worker создаёт parent-tuple `vpc_network#project@project:<id>`

**ID:** 2.0-E3-GWT-09

**Given** alice (admin@acc_default → admin@project через computed) залогинена
**And** В kacho-iam `resource_lifecycle_subscriber` worker подключён к `vpc.InternalResourceLifecycleService.Subscribe` (long-lived gRPC server-stream — D-13, новый RPC; НЕ deprecated `InternalWatchService`); `kacho_iam.watch_cursors.vpc.last_event_id` = `ev_initial`

**When** alice вызывает `POST /vpc/v1/networks` с `{name: 'dev-net', project_id: 'prj_dev'}`
**And** kacho-vpc создаёт network с id `enp123`; в outbox kacho-vpc — event `{kind: 'network', op: 'Create', resource_id: 'enp123', project_id: 'prj_dev', event_id: 'ev_001'}`
**And** kacho-iam resource-lifecycle-subscriber worker получает event через gRPC stream

**Then** Worker строит tuple: `{user: 'project:prj_dev', relation: 'project', object: 'vpc_network:enp123'}` (note: `user` поле OpenFGA tuple = "subject side"; в данном случае subject = project, relation = parent-mapping `project`, object = ресурс)
**And** Worker INSERT'ит `kacho_iam.outbox` row `{event_type: 'fga.tuple.write', payload: {tuples: [<above>]}}`
**And** Worker `UPDATE kacho_iam.watch_cursors SET last_event_id='ev_001' WHERE service='vpc'`
**And** В ≤2s `fga_tuple_writer` drain → `openfga.Write` → tuple в FGA
**And** Verify: `fga check --user=user:usr_alice --relation=admin --object=vpc_network:enp123` → `allowed: true` (computed через `admin from project` + alice's admin@account → admin@project)
**And** Verify: `fga check --user=user:usr_alice --relation=viewer --object=vpc_network:enp123` → `allowed: true` (computed cascade)

#### Scenario E3.GWT-10: Subnet.Create наследует от Network (parent = vpc_network, не project)

**ID:** 2.0-E3-GWT-10

**Given** Network `enp123` существует с tuple `project:prj_dev project vpc_network:enp123` (из GWT-09)
**And** В FGA: `fga check --user=user:usr_alice --relation=viewer --object=vpc_network:enp123` → `allowed: true`

**When** alice вызывает `POST /vpc/v1/subnets` с `{name: 'subnet-a', network_id: 'enp123', cidr: '10.0.0.0/24'}`
**And** kacho-vpc создаёт subnet `sub456` в network `enp123`
**And** kacho-vpc emit'ит event `{kind: 'subnet', op: 'Create', resource_id: 'sub456', network_id: 'enp123', project_id: 'prj_dev', event_id: 'ev_002'}`
**And** kacho-iam resource-lifecycle-subscriber worker строит **tuple** с parent = **network**, не project: `{user: 'vpc_network:enp123', relation: 'network', object: 'vpc_subnet:sub456'}` (DSL: `vpc_subnet` has `define network: [vpc_network]`)

**Then** В ≤2s tuple в FGA
**And** Verify computed: `fga check --user=user:usr_alice --relation=viewer --object=vpc_subnet:sub456` → `allowed: true` (chain: alice admin@account → admin@project → admin@vpc_network → admin@vpc_subnet через computed `admin from network from project`)
**And** Verify: `fga check --user=user:usr_bob --relation=viewer --object=vpc_subnet:sub456` (bob — без bindings) → `allowed: false`

#### Scenario E3.GWT-11: Network.Move на другой Project — untuple old, retuple new

**ID:** 2.0-E3-GWT-11

**Given** Network `enp123` в project `prj_dev` (из GWT-09); tuple `project:prj_dev project vpc_network:enp123` exists
**And** Existue `prj_staging` (другой project в том же account)
**And** bob имеет binding `(vpc.viewer, prj_dev)` (но НЕТ binding'а на prj_staging)
**And** Verify: `fga check --user=user:usr_bob --relation=viewer --object=vpc_network:enp123` → `allowed: true`

**When** alice вызывает `POST /vpc/v1/networks/enp123:move` с `{project_id: 'prj_staging'}` (Move RPC — overview §4.2)
**And** kacho-vpc atomic update `UPDATE networks SET project_id='prj_staging' WHERE id='enp123'`
**And** Emit event `{kind: 'network', op: 'Move', resource_id: 'enp123', old_project_id: 'prj_dev', new_project_id: 'prj_staging', event_id: 'ev_003'}`
**And** kacho-iam `resource_lifecycle_subscriber` handles Move: INSERT outbox row 1 `{event_type: 'fga.tuple.delete', payload: {tuples: [{user: 'project:prj_dev', relation: 'project', object: 'vpc_network:enp123'}]}}`, row 2 `{event_type: 'fga.tuple.write', payload: {tuples: [{user: 'project:prj_staging', relation: 'project', object: 'vpc_network:enp123'}]}}`

**Then** В ≤2s обе FGA-операции выполнены
**And** Verify: `fga check --user=user:usr_bob --relation=viewer --object=vpc_network:enp123` → `allowed: false` (bob потерял доступ через project chain)
**And** Verify: `fga check --user=user:usr_alice --relation=viewer --object=vpc_network:enp123` → `allowed: true` (alice имеет admin@account → admin@new_project через computed cascade)
**And** Подтверждение по тестам: `GET /vpc/v1/networks/enp123` с bob token → 403; с alice token → 200

### 5.5 Check positive (2 сценария)

#### Scenario E3.GWT-12: Owner (admin@account) проходит Check на любой RPC любого ресурса в любом project'е этого account

**ID:** 2.0-E3-GWT-12

**Given** alice имеет binding `(admin, scope: account:acc_default)` (default-admin из E4 signup flow, но в integration-тесте — seed-binding)
**And** В acc_default есть projects: `prj_dev`, `prj_staging` (создан alice'й)
**And** В prj_dev есть Network `enp123`; в prj_staging — `enp456`

**When** alice вызывает (через api-gateway, OIDC JWT → Principal=usr_alice):
1. `GET /vpc/v1/networks/enp123` (project=prj_dev)
2. `GET /vpc/v1/networks/enp456` (project=prj_staging)
3. `DELETE /vpc/v1/networks/enp123`
4. `POST /vpc/v1/networks` в prj_staging
5. `POST /compute/v1/instances` в prj_dev (`zone_id: zon_kacho_a`, `network_interfaces: [{subnet_id: sub789}]`)

**Then** Все 5 RPC возвращают 200/202 (без `PermissionDenied`)
**And** Метрика `kacho_authz_check_total{result="allowed"}` инкрементируется на каждый RPC (5 раз)
**And** `kacho_authz_check_duration_seconds` p95 ≤ 20ms (NFR-2)
**And** `kacho_authz_check_total{result="cache_hit"}` — после первого call alice'и cached subject; следующие 4 — cache hits (>3 из 5)
**And** `Operation.principal_id` в `kacho_vpc.operations` / `kacho_compute.operations` для async-RPC = `usr_alice` (E4 functionality, но в E3 integration-test уже должен работать после E2)

#### Scenario E3.GWT-13: Viewer-binding на Project позволяет Get/List на все child-resources (computed cascade)

**ID:** 2.0-E3-GWT-13

**Given** В `prj_dev` есть 5 Network'ов (enp001..enp005), в каждом по 2 subnet'а (sub001..sub010)
**And** bob имеет binding `(viewer, scope: project:prj_dev)` — выписан через GWT-04 pattern; tuple `user:usr_bob viewer project:prj_dev` в FGA
**And** Resource lifecycle tuples для всех 5 networks + 10 subnets созданы через resource-lifecycle-subscriber (GWT-09, GWT-10)

**When** bob вызывает:
1. `GET /vpc/v1/networks/enp003`
2. `GET /vpc/v1/subnets/sub007`
3. `GET /vpc/v1/networks?projectId=prj_dev` (list)

**Then** Все 3 RPC возвращают 200
**And** Для RPC #1: `fga check --user=user:usr_bob --relation=viewer --object=vpc_network:enp003` — computed: user → viewer@project → viewer@vpc_network через `viewer from project` (DSL line 326)
**And** Для RPC #2: computed cascade `user → viewer@project → viewer@vpc_network → viewer@vpc_subnet`
**And** Для RPC #3 (List): Check `viewer on project:prj_dev` → pass → kacho-vpc возвращает все 5 networks (без per-item filtering — D-8)
**And** Метрика `kacho_authz_check_calls_per_rpc_total` для каждого RPC = 1 (NFR-3)

### 5.6 Check negative (3 сценария)

#### Scenario E3.GWT-14: Viewer пытается Create — DENY

**ID:** 2.0-E3-GWT-14

**Given** bob — viewer на prj_dev (GWT-13 setup)

**When** bob вызывает `POST /vpc/v1/networks` с `{name: 'new-net', project_id: 'prj_dev'}`

**Then** Response — gRPC `PermissionDenied` (HTTP 403) с body `{code: 7, message: "permission denied", details: [{...rpc-mapping: editor required on project:prj_dev}]}`
**And** Network `new-net` НЕ создан (`SELECT count(*) FROM kacho_vpc.networks WHERE name='new-net'` = 0)
**And** Метрика `kacho_authz_check_total{result="denied"}` инкрементируется
**And** В log kacho-vpc — WARN `authz_denied user=usr_bob rpc=NetworkService/Create object=project:prj_dev relation=editor`
**And** No Operation создана (нет side-effect)

#### Scenario E3.GWT-15: User без bindings — DENY на read любого ресурса

**ID:** 2.0-E3-GWT-15

**Given** Создан new user `usr_eve` (через signup); в `kacho_iam.access_bindings` НЕТ rows для usr_eve

**When** eve вызывает `GET /vpc/v1/networks/enp123` (existing network)

**Then** Response — `PermissionDenied`
**And** `fga check --user=user:usr_eve --relation=viewer --object=vpc_network:enp123` → `allowed: false`
**And** Negative result НЕ кешируется (cache.Set вызывается только на allowed=true)
**And** Следующий call eve через ≤5s — повторно идёт в FGA Check (cache miss); если admin успел grant binding — eve получает 200 immediately после реактивности (≤10s через NOTIFY); см. GWT-19

#### Scenario E3.GWT-16: Cross-account access — DENY (admin на acc_X не имеет доступа в acc_Y)

**ID:** 2.0-E3-GWT-16

**Given** Существуют 2 account'а: `acc_alpha` (alice — admin), `acc_beta` (bob — admin)
**And** В `acc_beta` есть project `prj_beta_main` + Network `enp_beta_xxx`
**And** alice **не** имеет bindings на `acc_beta` или его projects

**When** alice вызывает `GET /vpc/v1/networks/enp_beta_xxx` (зная id, например, leak from logs)

**Then** Response — `PermissionDenied`
**And** `fga check --user=user:usr_alice --relation=viewer --object=vpc_network:enp_beta_xxx` → `allowed: false` (FGA не находит path)
**And** Кросс-аккаунтные bindings отсутствуют в DSL (overview §9 — Phase 3.0+); попытка `POST /iam/v1/accessBindings` со scope в другом account → `PermissionDenied` (alice не admin@acc_beta)

### 5.7 Реактивность (3 сценария)

#### Scenario E3.GWT-17: Revoke применяется в ≤10s (DoD #5; NFR-5)

**ID:** 2.0-E3-GWT-17

**Given** bob имеет binding `(editor, project:prj_dev)`; cached в kacho-vpc cache (≥1 успешный call)
**And** bob делает цикл `POST /vpc/v1/networks` каждые 1s (debug-loop через grpcurl); все запросы успешны

**When** В момент `t0` alice вызывает `DELETE /iam/v1/accessBindings/{bob_binding_id}`
**And** `kacho-iam` atomic TX: (1) DELETE row, (2) outbox row delete-tuple, (3) subject_change_outbox row
**And** `subject_change_notifier` worker drain'ит → `pg_notify('kacho_iam_subjects', 'usr_bob')`
**And** kacho-vpc authz-cache listener получает NOTIFY → `cache.InvalidateBySubject('usr_bob')`
**And** `fga_tuple_writer` worker drain'ит → openfga.Delete tuple

**Then** Bob's следующий RPC в момент `t0 + Δ` (Δ ≤ 1s typical, Δ ≤ 10s worst) возвращает `PermissionDenied`
**And** Test измеряет Δ: `Δ = first_denied_request_timestamp - t0`; assertion `Δ ≤ 10s`
**And** Typical случай: Δ ≤ 1s (NOTIFY быстро дошёл, cache invalidated, next call → cache miss → FGA Check → updated FGA → DENY)
**And** Worst case (NOTIFY lost / connection drop): cache TTL=5s expiry → cache miss at t0+5s → FGA Check → DENY at t0+5s+latency
**And** Метрика `kacho_authz_revoke_propagation_seconds` histogram (measured в test): p99 ≤ 10s

#### Scenario E3.GWT-18: Grant нового binding виден ≤1s (NOTIFY pushes positive cache invalidation, even for empty entries)

**ID:** 2.0-E3-GWT-18

**Given** В `prj_dev` есть 3 Network'а: net-a, net-b, net-c (resource tuples созданы)
**And** bob — без bindings; попытка `GET /vpc/v1/networks/net-a` → `PermissionDenied`
**And** **Cache в kacho-vpc для bob**: пустой (negative не кешируется)

**When** В момент `t0` alice вызывает `POST /iam/v1/accessBindings` с `(subject: User:usr_bob, role: viewer, scope: project:prj_dev)`
**And** outbox + subject_change_outbox + fga_tuple_writer pipeline

**Then** В ≤2s tuple `user:usr_bob viewer project:prj_dev` в FGA
**And** В ≤500ms NOTIFY → cache invalidation (no-op для empty cache)
**And** В момент `t0 + Δ` (Δ ≤ 1s typical, ≤ 2s worst) bob вызывает `GET /vpc/v1/networks/net-a` → 200 OK
**And** Computed cascade: bob может также `GET net-b`, `net-c`, `GET /vpc/v1/subnets/*` в этих networks (всё через `viewer from project` cascade)
**And** Bob **не может** `POST /vpc/v1/networks` (нужен editor) → `PermissionDenied`
**And** Bob **не может** `DELETE /vpc/v1/networks/net-a` (нужен admin) → `PermissionDenied`

#### Scenario E3.GWT-19: Restart api-gateway / per-service pod не теряет revoke (DoD #5; NFR-5 restart-resistance)

**ID:** 2.0-E3-GWT-19

**Given** bob имеет binding `(viewer, vpc_network:enp_specific)` (resource-scope, не project-level — explicit tuple `user:usr_bob viewer vpc_network:enp_specific`)
**And** В FGA tuple existue; bob делает `GET /vpc/v1/networks/enp_specific` → 200 (cache warm в kacho-vpc для bob)
**And** В момент `t0` alice вызывает `DELETE /iam/v1/accessBindings/{bob_resource_binding_id}`
**And** FGA-tuple удалена через outbox pipeline в ≤2s; pg_notify отправлен в ≤500ms

**When** В момент `t0 + 500ms` (NOTIFY возможно ещё в transit) разработчик выполняет `kubectl rollout restart deployment/kacho-vpc -n kacho`
**And** Ждёт `kubectl rollout status` → новый pod Ready, старый Terminated
**And** Bob делает повторный `GET /vpc/v1/networks/enp_specific`

**Then** Response — `PermissionDenied`
**And** Новый kacho-vpc pod НЕ имеет stale cache (in-memory cache reset на restart)
**And** Cache miss → `InternalIamService.Check` → openfga.Check → `allowed=false` (tuple уже удалена)
**And** `kubectl get pods -n kacho -l app=kacho-vpc -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'` для нового pod = 0
**And** Authz-cache listener в новом pod подключается к LISTEN-channel через ≤2s; до этого — все Check идут в FGA (slower, но correct fail-closed)
**And** Тест assertit: ZERO RPC bob'а после restart прошли (no false-positive grace-period)

### 5.8 Fail-modes (2 сценария)

#### Scenario E3.GWT-20: OpenFGA unavailable — все Check fail-closed; metric incremented

**ID:** 2.0-E3-GWT-20

**Given** Стенд up; alice — admin@account; alice's RPC проходят
**And** В test environment: kill openfga pod via `kubectl delete pod openfga-XXX -n kacho` (или `kubectl scale --replicas=0 deployment/openfga`)
**And** kacho-iam Check handler начинает получать `Unavailable` от openfga в ≤2s

**When** alice вызывает `GET /vpc/v1/networks/enp123`
**And** kacho-vpc interceptor cache miss (cache TTL expired или first call) → `InternalIamService.Check` к kacho-iam → kacho-iam openfga-client returns `Unavailable`
**And** kacho-iam Check returns `Internal: "openfga unavailable"` error

**Then** kacho-vpc interceptor maps gRPC error → fail-closed `PermissionDenied`
**And** alice (даже admin) получает `PermissionDenied` — это **expected** (defense-in-depth: лучше DENY всем, чем allow всех)
**And** Метрика `kacho_authz_fga_unavailable_denials_total` инкрементируется
**And** Prometheus alert `KachoAuthzFGAUnavailable` срабатывает (firing if rate > 1/min для 5 минут)
**And** Ops scale openfga обратно `kubectl scale --replicas=1 deployment/openfga` → recovery — все RPC возвращаются к 200 в течение ≤30s

#### Scenario E3.GWT-21: Break-glass env enables все RPC + WARN log + alert

**ID:** 2.0-E3-GWT-21

**Given** OpenFGA down (incident-state из GWT-20); все RPC получают `PermissionDenied`
**And** Ops для recovery / debugging выставляет: `kubectl set env deployment/kacho-vpc KACHO_VPC_AUTHZ__BREAKGLASS=true -n kacho`
**And** kacho-vpc pod restarts с новым env

**When** alice (admin) вызывает `GET /vpc/v1/networks/enp123` после restart

**Then** Response — 200 (Check bypass'нул)
**And** В log kacho-vpc — WARN `authz_breakglass_used user=usr_alice rpc=NetworkService/Get` (rate-limited 1/s — не spam)
**And** Метрика `kacho_authz_breakglass_total` инкрементируется
**And** Prometheus alert `KachoAuthzBreakglassActive` (always-firing while breakglass=true) — ops видит, что прод в break-glass mode
**And** После recovery openfga, ops откатывает: `kubectl set env deployment/kacho-vpc KACHO_VPC_AUTHZ__BREAKGLASS-`; pod restarts; alert clears

### 5.9 NFR (2 сценария)

#### Scenario E3.GWT-22: Check latency p95 ≤ 20ms (NFR-2) — k6 load test

**ID:** 2.0-E3-GWT-22

**Given** k6-script `kacho-test/loadtests/authz_check_latency.js`: 100 VUs, 1000 RPS, 60s duration; payload = `GET /vpc/v1/networks/{id}` для existing networks
**And** 5 test users, по одному admin binding'у на каждый; mix queries

**When** k6 run в течение 60s

**Then** k6 thresholds:
- `http_req_duration{name:vpc-network-get}` p95 < 50ms (overall RPC, включая FGA Check)
- `kacho_authz_check_duration_seconds` p95 < 20ms (только Check segment, через Prometheus query)
- `kacho_authz_check_calls_per_rpc_total` per-RPC = 1 (NFR-3)
- Cache hit ratio ≥ 95% (`rate(kacho_authz_cache_hits_total[1m]) / rate(kacho_authz_check_total[1m])`)

#### Scenario E3.GWT-23: AccessBindingService.Upsert pipeline latency p95 ≤ 200ms (NFR-6)

**ID:** 2.0-E3-GWT-23

**Given** k6-script `kacho-test/loadtests/access_binding_upsert.js`: 10 VUs, 50 RPS, 60s; payload = `POST /iam/v1/accessBindings` для random (user, role, project)

**When** k6 run

**Then** k6 thresholds:
- `http_req_duration{name:access-binding-upsert}` p95 < 200ms (includes: DB INSERT row + outbox INSERT + subject_change INSERT + TX commit + Operation response)
- Note: `fga_tuple_writer` async — НЕ включён в p95 (eventual в ≤2s по DoD #2)
- DB connection pool не exhausted: `pgxpool_acquire_duration_seconds` p99 < 50ms
- Metric `kacho_iam_access_binding_upsert_total` incremented exactly 3000 раз (50 RPS × 60s)

### 5.10 Create+immediate-Get propagation window mitigation (B2; D-11) — 1 сценарий

#### Scenario E3.GWT-24: Creator-tuple sync write inline в Create handler — immediate Get/Update/Delete без async-propagation race

**ID:** 2.0-E3-GWT-24

**Given** alice имеет binding `(editor, project:prj_dev)` — может Create network'и
**And** `kacho_iam.outbox` empty (clean state); per-service authz-cache (kacho-vpc) пустой
**And** `fga_tuple_writer` worker **paused** (для воспроизведения worst-case async-окна; в production worker всегда running, но мы тестируем именно creator-tuple sync-path, который НЕ зависит от worker'а)

**When** alice вызывает `POST /vpc/v1/networks` с `{name: 'fresh-net', project_id: 'prj_dev'}` в момент `t0`
**And** kacho-vpc Create handler:
1. Внутри своей TX создаёт network row (`enp999`)
2. Записывает свой outbox row для resource-lifecycle event (для kacho-iam subscriber → parent-tuple async pipeline; eventual в ≤2s)
3. **(D-11)** Перед `tx.Commit()` — синхронно вызывает `iamClient.WriteCreatorTuple(ctx, &iamv1.WriteCreatorTupleRequest{Subject: "user:usr_alice", Relation: "admin", Object: "vpc_network:enp999"})` (новый Internal RPC на kacho-iam:9091; thin wrapper над `openfga.Write`); ожидает success ≤10ms p95
4. `tx.Commit()`
5. Return `Operation{done=true, response: Network{id:'enp999', ...}}`

**And** alice **сразу** (в момент `t0 + Δ_create`, где `Δ_create` ≤ 200ms NFR-6 RPC budget) вызывает:
- `GET /vpc/v1/networks/enp999`
- `DELETE /vpc/v1/networks/enp999` (для проверки admin-relation сразу же)

**Then** Create response получен alice'ой в `t0 + Δ_create ≤ 200ms`
**And** Sync-tuple `user:usr_alice admin vpc_network:enp999` уже в OpenFGA до того, как Operation возвращён alice (write выполнен **до** `tx.Commit()`)
**And** Immediate `GET /vpc/v1/networks/enp999` → 200 (cache miss → `InternalIamService.Check` → openfga.Check `user:usr_alice viewer vpc_network:enp999` → computed `admin → viewer` → allowed=true) **без race**
**And** Immediate `DELETE /vpc/v1/networks/enp999` → 202 (admin allowed)
**And** Async parent-tuple `project:prj_dev project vpc_network:enp999` (от resource-lifecycle pipeline) появляется в FGA в ≤2s (НЕ блокировал Create response) — это покрывает доступ для **других** subjects через project-cascade (GWT-09 logic)
**And** Если `iamClient.WriteCreatorTuple` fails (FGA unavailable) во время sync-step (3): Create handler **rollback'ит TX** (network НЕ создан) → возвращает `Unavailable` клиенту с retry hint; **никаких partial-state** ресурсов без owner-tuple
**And** Метрика `kacho_iam_creator_tuple_sync_write_latency_seconds` p95 ≤ 10ms; включён в NFR-6 budget (200ms total Create) — fits с margin

**Note:** D-11 ограничивает sync-write **только creator-tuple** (1 запись в FGA). Все остальные tuples (resource lifecycle parent-tuple, AccessBinding tuples, group-cascade) остаются async через outbox-pattern (D-5, D-7). Sync-path добавляет ≤10ms к NFR-6 (200ms) — fits с margin. Альтернатива (полностью async) ломает UX «создал → не могу прочитать в течение 2s». Альтернатива (полностью sync для всех tuples) couples Create к openfga availability для **всех** resource-cascade (нарушает D-7).

### 5.11 Group membership change fanout (B4; D-9 reactivity) — 1 сценарий

#### Scenario E3.GWT-25: Group.RemoveMember → subject_change_outbox fanout per remaining member → cache invalidate для удалённого ≤10s

**ID:** 2.0-E3-GWT-25

**Given** В `kacho_iam.groups` есть `grp_devops` в `acc_default`
**And** Members: usr_alice, usr_bob, usr_charlie (3 члена)
**And** Group binding: `(grp_devops, vpc.editor, project:prj_dev)` существует; в FGA tuple `group:grp_devops#member editor project:prj_dev` (GWT-06 pattern)
**And** Все 3 пользователя могут `POST /vpc/v1/networks` в `prj_dev` (через group#member → editor cascade)
**And** В kacho-vpc authz-cache positive entries для всех 3 (после ≥1 успешного call каждого)
**And** `fga_tuple_writer` worker running healthy

**When** В момент `t0` alice (admin@acc_default → может управлять group'ами) вызывает `DELETE /iam/v1/groups/grp_devops/members/usr_charlie`
**And** kacho-iam `GroupMemberService.Delete` handler в **одной TX**:
1. `DELETE FROM kacho_iam.group_members WHERE group_id='grp_devops' AND user_id='usr_charlie'`
2. `INSERT INTO kacho_iam.outbox (event_type, payload)` — `fga.tuple.delete` для `group:grp_devops#member member user:usr_charlie` (group-member tuple unlink)
3. **(B4 fanout)** `INSERT INTO kacho_iam.subject_change_outbox (subject_id, op)` для **удалённого** субъекта `usr_charlie` с `op='group_member_change'` — **именно один row, ТОЛЬКО для удаляемого user'а** (не для оставшихся members — те сохраняют свои tuples)
4. `tx.Commit()`

**And** `subject_change_notifier` worker drain'ит → `pg_notify('kacho_iam_subjects', 'usr_charlie')` в ≤500ms
**And** Per-service authz-cache listeners (vpc/compute/lb) получают NOTIFY → `cache.InvalidateBySubject('usr_charlie')` в ≤1s
**And** `fga_tuple_writer` worker → `openfga.Delete` group-member tuple в ≤2s

**Then** Charlie's следующий `POST /vpc/v1/networks` в `prj_dev` в `t0 + Δ` возвращает `PermissionDenied`
**And** Δ ≤ 10s (DoD #5 reactivity); typical Δ ≤ 1s (NOTIFY-push + cache miss → FGA fresh Check → group-member tuple gone → no path)
**And** Alice и Bob **продолжают работать** без disruption (их cache entries НЕ инвалидированы — они остаются members группы; их tuples не трогали)
**And** В FGA: `fga check --user=user:usr_charlie --relation=editor --object=project:prj_dev` → `allowed: false` (no path)
**And** В FGA: `fga check --user=user:usr_alice --relation=editor --object=project:prj_dev` → `allowed: true` (всё ещё member)
**And** Метрика `kacho_iam_group_member_remove_total` инкрементируется
**And** Метрика `kacho_authz_revoke_propagation_seconds` (для usr_charlie) p99 ≤ 10s (same SLA как для AccessBinding.Delete — D-9)

**Note:** Alternative path — **AccessBinding.Delete для Group-subject** (например `DELETE /iam/v1/accessBindings/{group_binding_id}`) — invalidate'ит cache **ВСЕХ** members (по `SELECT user_id FROM kacho_iam.group_members WHERE group_id=$1` → INSERT N subject_change_outbox rows в одной TX); это **отдельный** сценарий, покрытый GWT-06 / GWT-07 patterns (Group subject ⇒ fanout per member). GWT-25 покрывает **противоположный** случай: один user удалён из группы, остальные остаются — invalidate **только** для удалённого. Q2 (Open Questions §11) — закрыт этим сценарием.

### 5.12 Scope-conditional iam.AccessBindingService.Upsert (B5; §4.4 edge case) — 1 сценарий с 3 sub-cases

#### Scenario E3.GWT-26: AccessBindingService.Upsert на разных scope (account / project / resource) → Check на корректном scope-object, cross-scope DENY

**ID:** 2.0-E3-GWT-26

**Given** Существуют:
- `acc_alpha` (alice — admin@acc_alpha; binding `user:usr_alice admin account:acc_alpha` в FGA)
- `prj_alpha_main` в acc_alpha
- `acc_beta` (bob — admin@acc_beta); alice **не имеет** bindings в acc_beta
- `vpc_network:enp_alpha_xxx` в prj_alpha_main (resource lifecycle tuple `project:prj_alpha_main project vpc_network:enp_alpha_xxx` существует)
**And** Per-service `iam.AccessBindingService.Upsert` permission map использует `ObjectResolver` (§4.4 edge case): extractor возвращает `(object_type, object_id)` зависимо от `scope` поля в request:
- `scope.account_id` → `("account", account_id)`, relation `admin`
- `scope.project_id` → `("project", project_id)`, relation `admin`
- `scope.resource_type='vpc_network', resource_id` → `("vpc_network", resource_id)`, relation `admin`

**When (sub-case A: account-scope binding by account-admin — ALLOW)** alice вызывает `POST /iam/v1/accessBindings` с:
- `subject = {type: 'user', id: 'usr_charlie'}`
- `role = 'roles/iam.viewer'`
- `scope = {type: 'account', account_id: 'acc_alpha'}`

**Then** kacho-iam interceptor: object = `account:acc_alpha`, relation = `admin`; Check → `user:usr_alice admin account:acc_alpha` → allowed=true → **passed**
**And** Binding создан; outbox + subject_change + FGA-tuple `user:usr_charlie member account:acc_alpha` (E0 system-role expansion §4.6 table) в ≤2s

**When (sub-case B: project-scope binding by account-admin — ALLOW via cascade)** alice вызывает `POST /iam/v1/accessBindings` с:
- `subject = {type: 'user', id: 'usr_dave'}`
- `role = 'roles/vpc.editor'`
- `scope = {type: 'project', project_id: 'prj_alpha_main'}`

**Then** interceptor: object = `project:prj_alpha_main`, relation = `admin`; Check → `user:usr_alice admin project:prj_alpha_main` (computed `admin from account` — alice admin@acc_alpha → admin@project) → allowed=true → **passed**
**And** Binding создан; FGA tuple `user:usr_dave editor project:prj_alpha_main` в ≤2s

**When (sub-case C: cross-scope DENY — admin одного account пытается выписать binding в чужом account)** alice (admin только в acc_alpha) вызывает `POST /iam/v1/accessBindings` с:
- `subject = {type: 'user', id: 'usr_eve'}`
- `role = 'roles/iam.viewer'`
- `scope = {type: 'account', account_id: 'acc_beta'}` (alice НЕ admin)

**Then** interceptor: object = `account:acc_beta`, relation = `admin`; Check → `user:usr_alice admin account:acc_beta` → allowed=false → **`PermissionDenied`**
**And** Binding НЕ создан (`SELECT count(*) FROM kacho_iam.access_bindings WHERE subject_id='usr_eve' AND resource_id='acc_beta'` = 0)
**And** Ни outbox, ни subject_change_outbox rows НЕ записаны (Check failed до handler логики)
**And** Метрика `kacho_authz_check_total{result="denied",rpc="AccessBindingService/Upsert"}` инкрементируется
**And** log WARN: `authz_denied user=usr_alice rpc=AccessBindingService/Upsert object=account:acc_beta relation=admin`

**Additional sub-cases (covered briefly, без полного GWT-разбора, но требуют newman+integration coverage):**
- **D**: resource-scope binding (`scope.resource_type='vpc_network'`, `resource_id='enp_alpha_xxx'`) — admin@project (через account cascade) — allow (alice admin@account → admin@project → admin@vpc_network через chained computed)
- **E**: resource-scope binding на ресурс в чужом account — deny (alice не admin@acc_beta → не admin@vpc_network в acc_beta)

**Note:** Этот сценарий закрывает Q4 (Open Questions §11). Permission map для `iam.AccessBindingService.Upsert` — `ObjectResolver`-вариант (§4.4); тесты обязаны cover **все 3 scope-paths** (account / project / resource) + DENY pattern. Cross-scope DENY критично для tenant-isolation security.

---

## 6. Definition of Done (E3 closure)

| # | DoD пункт                                                                                                  | Verification                                                                                                                                                            |
|---|-------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1 | OpenFGA full DSL applied; `kacho_iam.fga_model_version` содержит current model_id; helm idempotent          | Newman case `e3-bootstrap-idempotent`; integration test `TestBootstrapJobReapplyNoNew` (kacho-deploy)                                                                  |
| 2 | `AccessBindingService.Upsert` → tuple в FGA ≤ 2s (eventual via outbox)                                      | Integration test `TestAccessBindingUpsert_TupleWrittenWithin2s` (kacho-iam, testcontainers openfga); newman case `e3-binding-write-propagates`                          |
| 3 | `AccessBindingService.Delete` → tuple удалена ≤ 2s; subject cache invalidated                              | Integration test `TestAccessBindingDelete_TupleRemovedWithin2s`; newman case `e3-binding-delete-propagates`                                                              |
| 4 | Каждый публичный RPC (vpc/compute/lb/iam) проверяется через `InternalIamService.Check`                      | Integration test per-service (e.g. `vpc_authz_interceptor_test.go`) + table-test `TestAllRPCsHavePermissionMapping`; missing entry → FAIL                                 |
| 5 | Реактивность: revoke binding → enforced DENY ≤10s (NFR-5); включает Group.RemoveMember fanout (GWT-25)     | Newman case `e3-revoke-propagation-bounded` + `e3-group-member-remove-reactivity`; k6 `revoke_propagation.js` with `delta < 10s` assertion                              |
| 6 | 1 Check per RPC (NFR-3) — composite relations работают (admin@project ⇒ admin@vpc_network через computed) | Integration test `TestOneCheckPerRPC` (Prometheus counter); GWT-12 / GWT-13 verify computed cascade                                                                     |
| 7 | Fail-closed default на FGA-unavailable; break-glass env-var dev-only                                        | Integration test `TestFGAUnavailable_AllRPCsDenied` (kill openfga in testcontainers); test `TestBreakglassBypasses_WarnLogged` (env override + log capture)             |
| 8 | Concurrent integration test: revoke в момент работающего RPC цикла → next request DENIED в ≤10s            | Integration test `TestConcurrentRevokeWithRequestLoop` (goroutines: 1 cycle GET each 1s + 1 DELETE binding at t=5s; assert: first denied request at t=5s+Δ, Δ ≤ 10s)   |
| 9 | Restart-resistance: pod restart во время revoke — no stale cache, DENY immediate                            | Integration test `TestPodRestartLosesCacheCorrectly` (in-memory cache reset on process start); GWT-19 newman case                                                       |

**Артефакты:**
- Все integration tests зелёные в каждом затронутом репо (vpc/compute/loadbalancer/iam/api-gateway).
- Все newman cases зелёные (минимум: `e3-bootstrap`, `e3-binding-write`, `e3-binding-delete`, `e3-revoke-propagation`, `e3-fga-unavailable`, `e3-breakglass`, **`e3-creator-tuple-immediate-get`** (GWT-24, D-11), **`e3-group-member-remove-reactivity`** (GWT-25), **`e3-scope-conditional-access-binding`** (GWT-26 — 3 sub-cases + cross-scope DENY), **`e3-user-delete-precondition-no-cascade`** (GWT-08, D-12)).
- k6 thresholds passed для GWT-22, GWT-23.
- Vault entries обновлены (см. §3.2 list); **+ новые entries для D-13**: `obsidian/kacho/rpc/vpc-internal-resource-lifecycle-service.md`, `rpc/compute-internal-resource-lifecycle-service.md`, `rpc/loadbalancer-internal-resource-lifecycle-service.md`, `packages/corelib-resourcelifecycle.md`, `edges/vpc-to-iam-resource-lifecycle.md`, `edges/compute-to-iam-resource-lifecycle.md`, `edges/loadbalancer-to-iam-resource-lifecycle.md`, `packages/iam-internal-jobs-resource-lifecycle-subscriber.md`.
- KAC-108.md финализирован: `Status: done`, все PR ссылки.

---

## 7. Cross-repo PR-chain (порядок merge)

Топологический порядок (по `replace ../` graph из workspace `CLAUDE.md`):

| # | Repo                | Branch        | PR scope                                                                                            | Зависит от  |
|---|---------------------|---------------|------------------------------------------------------------------------------------------------------|-------------|
| 1 | kacho-proto         | KAC-108       | `InternalIamService.Check` rpc + расширения `internal_iam_service.proto`; gen Go-stubs               | (none)      |
| 2 | kacho-corelib       | KAC-108       | `authz/` package (interceptor + cache + check_client + LISTEN-loop)                                  | PR #1       |
| 3 | kacho-iam           | KAC-108       | миграции 0005-0007 + outbox + 3 worker'а + InternalIamService.Check handler + AccessBindingService.Upsert/Delete расширение | PR #1, #2 |
| 4 | kacho-vpc           | KAC-108       | `internal/interceptors/authz.go` + `metadata/permission_map.go` + register в main.go                | PR #2 (corelib/authz); может pin to PR #3 branch до merge через `ref:KAC-108` в CI |
| 5 | kacho-compute       | KAC-108       | то же                                                                                                | PR #2; parallel с #4 |
| 6 | kacho-loadbalancer  | KAC-108       | то же                                                                                                | PR #2; parallel с #4, #5 |
| 7 | kacho-api-gateway   | KAC-108       | удаление E2 authz-stub (no-op interceptor) + comment про per-service delegation                      | PR #1 (для clarity) |
| 8 | kacho-deploy        | KAC-108       | helm openfga-bootstrap-job replace stub→full DSL + configmap update + helm-values для break-glass    | PR #3, #4, #5, #6 (нужны image-tags новых backend versions)  |
| 9 | kacho-workspace     | KAC-108       | этот acceptance APPROVED → status DRAFT→APPROVED; vault entries; KAC-108.md = done                  | After all  |

**Параллельность:**
- PR #1 → blocks #2 → blocks #3, #4, #5, #6
- #3, #4, #5, #6 — параллельны после #2 merge
- #8 — последний (нужны image-tags из #3..#6)

**CI pinning (per workspace `CLAUDE.md` §«Кросс-репо зависимости»):**
- В `.github/workflows/ci.yaml` каждого зависимого репо временно `ref: KAC-108` для upstream sibling'ов; снимается на merge upstream.
- Пример: kacho-vpc PR CI pins `kacho-proto` ref:KAC-108 → после kacho-proto merged → snap to `ref: main`.

---

## 8. Risks & Mitigations

| Risk                                                                                            | Mitigation                                                                                                                                                       |
|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| OpenFGA single-instance bottleneck (read-heavy через Check)                                     | Helm enables 3 replicas (OpenFGA supports horizontal scale); LoadBalancer service в front; Postgres read-replicas для FGA в Phase 2.1 если нужно                |
| FGA tuple inconsistency между access_bindings и FGA (outbox-row stuck attempt_count > 5)        | Prometheus alert `KachoIamOutboxStuck` (fires when outbox.attempt_count > 5 для row > 5 min); ops может вручную replay через `bin/kacho-iam-migrator outbox-replay --id=N` или `--all-failed` |
| Cache invalidation NOTIFY lost (drop по network glitch)                                         | TTL=5s гарантирует bounded staleness; LISTEN-loop reconnects automatically (pgx); периодический full-cache-clear каждые 60s (configurable) — `KACHO_<SVC>_AUTHZ__FULL_CACHE_CLEAR_INTERVAL=60s` |
| Computed relations DSL ambiguity для edge cases (например `vpc_subnet` admin via 3 paths: own tuple OR admin@network OR admin@project) | DSL line 332 (`admin from network`) + `admin from project` (через `network from project from project`) — OpenFGA `Check` handles ambiguity (returns true если any path resolves); test coverage E3.GWT-12, GWT-13 |
| Resource-watch worker miss event (gRPC stream drop) при kacho-iam crash | Cursor persistence в `kacho_iam.watch_cursors`; resume from last_event_id на restart; vpc/compute/lb retain outbox events ≥ 1 hour (configurable) |
| Permission map drift (RPC added в backend, не в map → fail-closed) | Build-time test `TestAllRPCsHavePermissionMapping` — reflects gRPC service descriptors через generated proto, fails build при missing RPC; добавлен в CI каждого backend repo |
| Newman cases для революции — flaky timing (NOTIFY propagation jitter) | Polling assertion вместо fixed-sleep: `wait_for_status_change(retries=20, interval=500ms, max=10s)`; не использовать `sleep(10)`; documented в newman-kacho-style |
| Custom-role permissions раскладка edge case (permission `vpc.networks.read` без `vpc.subnets.read` — granular) | Decision §4: custom-role permissions ОГРАНИЧЕНЫ под-набором default-permissions на 2.0; granular = Phase 2.1+; E0 `RoleService.Create` validation reject'ит unsupported combinations |
| **Denied-request storm bypasses cache → high load на kacho-iam.Check** (D-9: negative results НЕ кешируются → attacker может flooding `GET /vpc/v1/networks/*` от unauthorized user → каждый запрос идёт в FGA Check) | **Rate-limit per Principal** в per-service authz-interceptor: `KACHO_<SVC>_AUTHZ__DENY_RATE_LIMIT=100/s` (configurable; default 100/s per Principal); on threshold → возвращать `ResourceExhausted` (HTTP 429) с retry-after header; не пройдёт в FGA Check; метрика `kacho_authz_deny_rate_limited_total{principal_id}`. Token-bucket per Principal (in-memory, evict on inactivity). Реализуется в corelib `authz/interceptor.go` (общий код для всех backends). Альтернативы: negative-cache TTL ≤1s (compromise stale-grant UX — D-9 rejected); per-IP rate-limit (не помогает при authenticated attacker — Principal-aware нужен) |

---

## 9. Out of Scope (явно отложено)

| Тема                                                                | Куда вынесено                                  |
|----------------------------------------------------------------------|------------------------------------------------|
| UI блок IAM с эффективными permissions visualization                | E4 (KAC-109)                                   |
| Audit log записей `(subject, action, resource, allowed)` — для AAA  | Phase 2.1 (`kacho-audit-log` сервис)           |
| Per-tenant quota на permissions / bindings                          | Phase 2.1 (overview §9)                         |
| `ListObjects`-based per-item filtering для List-RPC                 | Phase 2.1 если NFR-2 (≤20ms) под нагрузкой не вытягивает |
| ABAC (атрибутные политики, e.g. `where label.env='prod'`)           | Phase 2.2+ (overview §9)                        |
| Cross-account bindings (User в acc_X получает binding на prj в acc_Y) | Phase 3.0 (overview §9)                       |
| OpenFGA model versioning + tuple migration на breaking DSL change   | Sub-эпик в Phase 2.1 (model_v3 first time)     |
| Granular custom-roles (любая permission combination)                | Phase 2.1 (нужен PermissionBuilder UI + audit) |
| Operation.principal для async-операций (E4) — НЕ в E3 (E3 just verifies E2 principal propagation работает) | E4 (KAC-109)                                   |
| RM deprecation                                                       | E5 (KAC-110)                                   |

---

## 10. Связь с регламентом (повтор для reviewer)

- **Запрет #1** (acceptance before code): этот документ + reviewer cycle до APPROVED.
- **Запрет #2** (no yandex): все error-texts / env / proto-fields — kacho-namespace.
- **Запрет #6** (Internal not on external TLS): `InternalIamService.Check`, `InternalSubjectChangeNotificationService` — :9091 cluster-internal; api-gateway routes только `/iam/v1/*` (public RPCs).
- **Запрет #7** (no broker): pg_notify/LISTEN на dedicated pgx-conn (godzila §16) — proven outbox-pattern.
- **Запрет #8** (DB-per-service): kacho_iam Postgres и openfga Postgres — раздельные БД; consistency через outbox-retry, не cross-DB FK.
- **Запрет #9** (no sync resource return): AccessBindingService.Upsert/Delete возвращают Operation (corelib).
- **Запрет #10** (DB-уровень refcheck): `access_bindings_unique` UNIQUE (E0); outbox FK на access_bindings.id НЕТ (outbox-rows могут пережить binding-row delete для retry).
- **Запрет #11** (tests-required в том же PR): §6 DoD каждый пункт линкуется на конкретный test-файл.

**evgeniy regulation:**
- §2 (use-case pattern): `internal/apps/kacho/api/access_binding/{upsert,delete,list_by_resource,list_by_subject,get}.go` — каждый use-case в отдельном файле.
- §10 (metadata.go): per-service `internal/metadata/permission_map.go` — table-driven RPC → permission mapping; не fat-switch.
- §16 (outbox + LISTEN на dedicated conn): `internal/jobs/subject_change_notifier.go` + per-service `internal/cache/subject_invalidate_listener.go` (dedicated pgx-conn вне пула).

---

## 11. Open Questions (для acceptance-reviewer)

### Резолвированы в v2

1. **Q1 — `InternalIamService.Check` vs direct openfga.Check (latency budget)** → **RESOLVED v2 / B3**: см. §3.5 «Latency budget для D-1» — `interceptor → kacho-iam (≤5ms intra-cluster) + kacho-iam → openfga (≤5ms) + openfga query (≤8ms) ≈ 20ms p95` fits NFR-2. D-1 централизация **закрыта**; миграция на direct в Phase 2.1 — прозрачна через corelib `authz.CheckClient` interface (без backend changes).

2. **Q2 — Group membership change fanout** → **RESOLVED v2 / B4**: см. **GWT-25** (§5.11) — `Group.RemoveMember` записывает subject_change_outbox row **только для удалённого user'а**; cache invalidation per-Principal через `pg_notify`. Для `AccessBinding.Delete` с Group-subject — fanout per-member через `SELECT user_id FROM group_members WHERE group_id=$1` (GWT-06 / GWT-07 patterns extend на это).

4. **Q4 — Scope-conditional `iam.AccessBindingService.Upsert` Check** → **RESOLVED v2 / B5**: см. **GWT-26** (§5.12) — 3 sub-cases (account / project / resource scope) + cross-scope DENY. ObjectResolver-based permission map (§4.4 edge case).

### Non-blocking (оставить как post-APPROVE follow-up)

3. **Performance test для resource-lifecycle-subscriber worker под высокой нагрузкой** — если создаются 1000 networks за минуту, worker должен write 1000 outbox rows + `fga_tuple_writer` drain в ≤2s SLA. Может быть bottleneck при бурсте. **Предложение**: load test в **Phase 2.1** (`kacho-test/loadtests/resource_lifecycle_burst.js`); MVP E3 покрывает steady-state (GWT-22/23). Reviewer ack: non-blocking для APPROVE.

5. **Bootstrap-job DSL location** — sub-chart vs main chart vs separate configmap. Выбран sub-chart `openfga-bootstrap/files/authorization-model.fga`. Reviewer может предпочесть main chart configmap. Non-blocking; решается в kacho-deploy PR (#8 в chain §7).

---

## 12. Changelog

- **2026-05-17 — DRAFT v1**: первая полноразмерная версия (`acceptance-author` agent). Расширение STUB-предшественника в полный GWT-разбор: 23 сценария, 9 DoD пунктов, Decision Log из 10 пунктов, Cross-repo PR-chain, Risks/Mitigations, Open Questions. Awaiting `acceptance-reviewer`.

- **2026-05-17 — DRAFT v2** (`acceptance-author` agent, response to v1 reviewer: 7 blockers + 4 important):
  - **B1 (TTL clarification, §4.3)**: добавлена врезка про **два разных cache** в системе — subject lookup cache (api-gateway, E2, TTL=30s) vs Check-result cache (per-service authz, E3, TTL=5s). Разные ключи / разная invalidation / разная цель.
  - **B2 (Create+immediate-Get propagation gap, §5.10 GWT-24)**: новый сценарий + **D-11 (creator-tuple sync write inline)** в Decision Log — `kacho-vpc/compute/lb` Create handler выполняет sync FGA-write для own-creator tuple до `tx.Commit()` (≤10ms latency overhead на NFR-6); устраняет race «создал → не могу прочитать в течение 2s».
  - **B3 (D-1 latency budget, §3.5 new)**: явный расчёт `5ms+5ms+8ms = ~18ms p95` для `interceptor → kacho-iam → openfga → response`; fits NFR-2 (≤20ms). D-1 централизация **закрыта** как trade-off; миграция на direct в Phase 2.1 — прозрачна через `authz.CheckClient` interface.
  - **B4 (Group.RemoveMember fanout, §5.11 GWT-25)**: новый сценарий — `Group.RemoveMember` invalidate'ит cache **только удалённого** user'а (one subject_change_outbox row), оставшиеся members работают без disruption. DoD #5 reactivity (≤10s) подтверждён.
  - **B5 (Scope-conditional `iam.AccessBindingService.Upsert`, §5.12 GWT-26)**: новый сценарий + 3 sub-cases (account / project / resource scope) + cross-scope DENY pattern. ObjectResolver-based permission map (§4.4 edge case закреплён в тестах).
  - **B6 (User.Delete cascade, §5.3 GWT-08 переформулирован)**: E3 НЕ вводит cascade; admin вручную revoke'ит bindings → потом Delete; **D-12 (no cascade-delete bindings on User.Delete)** в Decision Log зафиксирован.
  - **B7 (InternalWatchService dilemma, D-13)**: введён **новый Internal RPC `InternalResourceLifecycleService.Subscribe`** (server-stream от peer-service → kacho-iam) — НЕ reuse deprecated `InternalWatchService` (workspace 1.0 удалил). §3.1 ASCII / §3.2 repos / §3.3 edges / §4.7 worker code обновлены (`resource_watch.go` → `resource_lifecycle_subscriber.go`); запрет #8 не нарушен (gRPC vs cross-DB LISTEN).
  - **I8 (§4.1)**: явно указано `kacho_iam.fga_model_version.dsl_sha256` как место хранения SHA-256 локального DSL.
  - **I9 (§4.2 worker note)**: явно прописано требование «vpc/compute/lb outbox retention ≥ 1 hour» (cross-repo helm-values bump).
  - **I10 (§8 Risk new row)**: добавлен риск «Denied-request storm bypasses cache → high load на kacho-iam.Check» с mitigation rate-limit per Principal (token-bucket в corelib `authz/interceptor.go`, configurable `KACHO_<SVC>_AUTHZ__DENY_RATE_LIMIT`).
  - **I11 (§3.2 / §4 / D-13)**: явно «E3 вводит NewService `InternalResourceLifecycleService` — НЕ переиспользует deprecated `InternalWatchService`».
  - **Open Questions §11**: Q1/Q2/Q4 → **RESOLVED** (через B3/B4/B5 соответственно); Q3/Q5 — non-blocking, остаются post-APPROVE.
  - **Decision Log**: +3 решения (D-11, D-12, D-13). D-7 обновлён под D-13 (новый RPC вместо deprecated Watch).
  - **GWT-count**: 23 → **26 сценариев** (+ GWT-24, GWT-25, GWT-26). DoD §6 без изменений (новые scenarios покрывают существующие DoD #2, #5, #6 — extended coverage).
  - **Файл-стат**: ~1050 → ~1180 строк (+~130 строк новых scenarios/decisions/sections; нет deletions кроме переформулировки GWT-08).
