# Sub-phase 3.4 — IAM AuthZ: List filtering via OpenFGA ListObjects (KAC-127 / YT KAC-123) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §7 «List filtering — final design», corelib/authz interface §7, SLA table §7, Architecture §2.
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 4 (tasks 4.1-4.5).
> **Phase position**: §16 design doc «Migration plan», **Phase 4 of 13**.
> **Predecessors (must be merged before Phase 4 code begins)**:
> - **Phase 1 — Foundation** (`sub-phase-3.1-iam-foundation-acceptance.md`): migrations `0011..0014` (multi-scope `roles`, `access_bindings`, `cluster_kacho_root` singleton, `permission_catalog.json`), outbox→FGA tuple writer, `kacho_iam_subjects` NOTIFY channel.
> - **Phase 2 — AuthN core** (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): JWT с `amr` / `acr` / `auth_time` / `cnf.jkt` / `ext_claims.kacho_mfa_at` / `ext_claims.kacho_device_compliance` / `ext_claims.kacho_source_ip`, api-gateway DPoP/mTLS validation, **Principal-extraction** в gRPC-metadata (используется в Phase 4 для ContextualTuples).
> - **Phase 3 — AuthZ core** (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): OpenFGA Authorization Model v2 (full DSL design §4 — `cluster`, `organization`, `account`, `project`, `vpc_*`, `compute_*`, `lb_*` types + 7 Conditions), Conditional `corelib/authz` Check, OPA sidecar pipeline, `corelib/authz/listobjects.go` **skeleton** (interface + package — Phase 4 fills implementation), `kacho_iam_subjects` LISTEN/NOTIFY contract.
> - **KAC-108 / E3 baseline** (`sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md`): single-Check parent pattern для List-RPC — **superseded в Phase 4** (см. §3 Decision Log P4-D1; user feedback round 2 2026-05-19 «придерживаться старой конвенции не надо»).
> **Target repos / merge order (топологическая сортировка graph'а)**:
> 1. `PRO-Robotech/kacho-corelib` — `authz/listobjects.go` (full implementation), `authz/listobjects_lru.go` (LRU cache), `authz/listobjects_invalidate.go` (LISTEN goroutine), `authz/listusers.go` (separate API для subject→resources обращений), `authz/metrics.go` (`corelib_authz_listobjects_*`), integration tests с testcontainers openfga + Postgres.
> 2. `PRO-Robotech/kacho-vpc` — переписать 9 List-RPC handlers (`network`, `subnet`, `security_group`, `route_table`, `address`, `gateway`, `private_endpoint`, `network_interface`, `address_pool`); add `repo.ListByIDs(ctx, ids []string, pageSize int32, pageToken string)` per-domain.
> 3. `PRO-Robotech/kacho-compute` — переписать 4 List-RPC handlers (`instance`, `disk`, `image`, `snapshot`).
> 4. `PRO-Robotech/kacho-loadbalancer` — переписать 2 List-RPC handlers (`network_load_balancer`, `target_group`).
> 5. `PRO-Robotech/kacho-iam` — переписать 9 List-RPC handlers (`account`, `project`, `user`, `service_account`, `group`, `role`, `access_binding`, `jit_eligibility`, `federation_trust_policy`); `AccessBindingService.List` уникален — использует **ListUsers** API когда фильтрация идёт по resource, **ListObjects** когда по subject (см. §6.5 / P4-D8).
> 6. `PRO-Robotech/kacho-test` — `k6/list_filter_kac127_phase4.js`, `newman/cases/list_filter_*.py` (per-service), `k6/results/KAC-127-phase4-list-filter.md` artifact.
> 7. `PRO-Robotech/kacho-deploy` — Helm values для `KACHO_AUTHZ_LISTOBJECTS_CACHE_TTL=5s`, `KACHO_AUTHZ_LISTOBJECTS_MAX_PAGE=10000`, `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN=false`; dashboards и alert rules (Grafana panels: cache-hit-ratio, listobjects-duration-p95, listobjects-errors-total, listen-invalidate-latency).
> 8. `PRO-Robotech/kacho-workspace` — vault обновления (`obsidian/kacho/KAC/KAC-127.md`, `obsidian/kacho/architecture/list-filtering-pipeline.md`, `obsidian/kacho/edges/all-services-to-openfga-listobjects.md`, `obsidian/kacho/rpc/*-list-service.md` для каждого изменённого List-RPC).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 4 — **четвёртая code-emitting Phase** под KAC-127. К моменту начала Phase 4 уже есть:

1. **DB-foundation** (Phase 1): multi-scope `roles`, polymorphic `access_bindings`, `access_binding_conditions`, `cluster_admin_grants`, FGA outbox writer.
2. **AuthN plane** (Phase 2): Kratos + Hydra DPoP-bound JWT, api-gateway Principal-extraction.
3. **AuthZ plane** (Phase 3): OpenFGA model v2 (полный DSL с типами `cluster`/`organization`/`account`/`project`/`vpc_*`/`compute_*`/`lb_*` + 7 Conditions), OPA sidecar, Conditional Check.

**Что Phase 4 принципиально меняет** (по user feedback 2026-05-19 round 2 «придерживаться старой конвенции не надо»):

- **KAC-108 D-8 (single-Check на parent) — упраздняется целиком**. Раньше `Network.List`
  делал ОДИН Check (`viewer@project:<requested_project_id>`) и возвращал все networks этого
  project (без per-resource scope). Это покрывало narrow happy-path (один phenotype: «листинг
  в пределах одного project»), но **не поддерживало**:
  - List без `project_id` filter (например, «все networks, которые я вижу» в admin-UI);
  - **fine-grained** grants на конкретный ресурс (binding `viewer@vpc_network:net_X` для
    User вне project owner-set);
  - cross-project listing для `cluster_admin` / `org_admin` / `account_admin` (надо вернуть
    networks из всех project'ов внутри cascade-scope без enum'а project'ов на стороне клиента);
  - shared resources (network shared via project-share — Phase 6+).
- **Замена**: каждый List-RPC во **всех 4 сервисах** (vpc / compute / loadbalancer / iam)
  спрашивает у `corelib/authz`: «список **id** объектов типа `<type>`, на которые у этого
  Principal есть relation `<viewer|editor|admin>`», получает `[]string` от
  **OpenFGA ListObjects API** (`POST /stores/{id}/list-objects`), и фильтрует SQL запросом
  `WHERE id = ANY($1::text[])`. Это устраняет дыру и приводит фильтрацию list-результатов в
  full ReBAC-consistency с per-RPC Check'ом из Phase 3.
- **Cache 5s LRU + LISTEN-invalidate**: чтобы повторные List'ы из того же principal'а не
  делали FGA round-trip каждый раз, `corelib/authz/listobjects.go` поддерживает LRU
  с TTL=5s и **per-subject invalidate** через `LISTEN kacho_iam_subjects` (channel создан
  Phase 1 / E3 baseline, payload — `subject_id`, см. §2.5 Phase 3 «cache invalidation contract»).
  AccessBinding mutation → outbox → FGA Write + NOTIFY → каждая per-pod cache invalidate-ит
  записи `(principal_id, *, *)`.
- **Conditions honored**: `mfa_fresh`, `non_expired`, `source_ip_in_range`, `break_glass_window`,
  `jit_window`, `business_hours`, `device_compliant` — FGA Conditions evaluated **на стороне
  FGA-engine** при ListObjects (так же, как при Check). Phase 4 передаёт ContextualTuples из
  Principal'а (acr / amr / mfa_at / source_ip / device_attestation / current_time) — те же
  поля, что Phase 3 передавал в Check. ID попадает в результат только если все его
  Conditions evaluate true.
- **Cluster-admin / org-admin / account-admin cascade — natively через FGA** (DSL v2):
  `vpc_network#viewer = ... or viewer from project` (где `project#viewer = ... or viewer from
  account`, и так далее). ListObjects sees cascade automatically — extra short-circuit
  on client side **НЕ нужен** (P4-D11).
- **Performance SLA — production-verified** (design §7): p95 ≤100ms (cache miss, ≤100 IDs),
  p99 ≤250ms, cache hit ratio ≥80% в steady state. Validation через `k6/list_filter_kac127_phase4.js`
  на dev-стенде `e2c825` (1000 networks/project, 1000 RPS sustained 30min).

**Phase 4 НЕ включает** (это Phases 5-13 одного и того же epic'а — НЕ "deferred"):

- Federation Exchange RPC (RFC 8693 Token Exchange) + SA Hydra-clients — **Phase 5**.
- SCIM 2.0 endpoint + SAML bridge + Organization-UI — **Phase 6**.
- JIT activation RPC + Break-glass workflow + 2-person approval + Access Reviews automation +
  GDPR erasure — **Phase 7** (Phase 4 уже **honors** `jit_window` / `break_glass_window`
  Conditions в ListObjects-результатах, но сами workflow'ы `ActivateJIT` / `RequestBreakGlass` —
  Phase 7).
- CAEP push pipeline (session-revoked, credential-change SET delivery, drainer) — **Phase 8**
  (Phase 4 использует только LISTEN/NOTIFY от собственного outbox; внешние SET-subscribers
  начинаются в Phase 8).
- Audit pipeline Kafka + ClickHouse + S3 + HSM Merkle — **Phase 9**. Phase 4 пишет audit-emit
  через `audit_outbox` row insert на каждый ListAllowedIDs call (вместе с mutation-стороной
  Phase 3), но **drainer / consumer / external delivery** — Phase 9. Это сделано так чтобы
  Phase 9 не пришлось мигрировать существующие row'ы (forward-compatible выпуск).
- SPIFFE/SPIRE + Cilium mesh — **Phase 10**.
- Multi-region + Argo CD + Grafana дашборды (только базовые добавляются здесь) — **Phase 11**.
- OWASP ASVS L3 + fuzzing + chaos + pentest — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13** (Phase 4 обновляет только свои edges/rpc/architecture).

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED. |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / proto / Go-имена / env-name / commit-messages / k6-scenarios не упоминается; YC-стилистика error-text (`Permission denied`, `Resource '<X>' not found`) — остаётся для error-mapping FGA-`NotFound`. |
| **Запрет #3** — НЕ ORM | `openfga-go-sdk` — это HTTP/gRPC-клиент к FGA (не ORM); `repo.ListByIDs` — handwritten pgx + sqlc (как и весь остальной repo-layer); cache — go-native LRU `hashicorp/golang-lru/v2` (не ORM-cache). |
| **Запрет #4** — НЕ каскад через границу сервиса | ListObjects — read-only call; никаких cascade-delete'ов. AccessBinding deletion (в `kacho-iam`) и вытекающий outbox event → FGA Write + NOTIFY — это **в пределах одного сервиса** (`kacho-iam`); cross-service эффекты — только реактивный LISTEN на пер-pod cache (это не cascade-delete, это invalidate). |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 4 НЕ имеет новых миграций; вся schema-foundation в Phase 1. Если в ходе implementation выявится missing column / index — открывается **новая** миграция `0016_kac127_phase4_audit_outbox_listobjects.sql` per affected сервис (per-service migration, не правка Phase 1). Конкретно: `audit_outbox` (минимальный skeleton — `id`, `event_type`, `principal_id`, `resource_type`, `relation`, `result_count`, `created_at`) добавляется в kacho-iam DB как Phase 4 row-insert side; drainer / consumer — Phase 9 (forward-compat). |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | InternalAddressPoolService.List (`kacho-vpc`) и Internal Region/Zone List (`kacho-compute`) — остаются Internal-only; их List-handler переписывается на ListAllowedIDs **с тем же internal-only визитом** (api-gateway регистрирует через `restmux.RegisterInternal()`, не `RegisterPublic()`). Sentinel filter: для Internal admin RPC ListAllowedIDs зовётся с `objectType=vpc_address_pool` (DSL type — admin-managed) + relation=`viewer` где relation определена ТОЛЬКО для cluster-admin/system-viewer (см. DSL §4 design); таким образом regular tenant получает empty list даже если случайно нашёл internal endpoint. |
| **Запрет #7** — НЕ broker | LISTEN/NOTIFY (Postgres native) + in-memory LRU — никакого Kafka/NATS в Phase 4. Phase 9 vводит Kafka; Phase 4 forward-compatible (`audit_outbox` row insert — drainer Phase 9). |
| **Запрет #8** — DB-per-service | Каждый сервис sохраняет свою БД. ListAllowedIDs возвращает только **id-string**; SQL `WHERE id = ANY($1::text[])` — внутри одной DB сервиса. Cross-service refs (`account_id`, `project_id` в vpc/compute) — software-validation на request-path осталась с Phase 1 (не изменяется здесь). |
| **Запрет #9** — async-only мутации | Phase 4 НЕ добавляет мутирующих RPC; только переписывает существующие **read-only** `List` RPC (они и были sync). `AccessBindingService.List` остаётся sync (read), хотя `AccessBindingService.Upsert/Delete` — async (Phase 1). |
| **Запрет #10** — within-service refs на DB-уровне | ListObjects-результат — массив id; SQL `WHERE id = ANY($1::text[])` — primary-key filter, не FK-проверка. Все FK / partial UNIQUE / EXCLUDE / CAS — остаются как в Phase 1 (этот regime не нарушается; запрос is read-only `SELECT`). |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 4 содержит: kacho-corelib — unit (`listobjects_test.go`) + integration (`listobjects_integration_test.go` с testcontainers openfga + Postgres) + race-test для LISTEN-invalidate; per-service repos — integration (`list_integration_test.go` per resource) + newman case (`<svc>/tests/newman/cases/list_<resource>.py`); kacho-test — k6 SLA artifact + newman cross-service `cases/list_filter_*.py`. Newman 1 happy-path + ≥1 negative (anonymous → empty, cross-tenant → empty, missing JWT → Unauthenticated) **в одном PR** с handler-changes. |

---

## 2. Глоссарий / доменная модель Phase 4 (нормативно)

### 2.1 Сущности и API, **используемые** в Phase 4 (от Phase 1/2/3 — read-only здесь)

- **OpenFGA Authorization Model v2** (Phase 3 deployed): типы `cluster`, `organization`,
  `account`, `project`, `vpc_network`, `vpc_subnet`, `vpc_security_group`, `vpc_route_table`,
  `vpc_address`, `vpc_gateway`, `vpc_private_endpoint`, `vpc_network_interface`,
  `vpc_address_pool`, `compute_instance`, `compute_disk`, `compute_image`, `compute_snapshot`,
  `lb_network_load_balancer`, `lb_target_group`. Pinned `authorization_model_id` per request.
- **Conditions** (Phase 3 loaded): `mfa_fresh`, `non_expired`, `source_ip_in_range`,
  `break_glass_window`, `jit_window`, `business_hours`, `device_compliant`. Evaluated by
  FGA-engine при ListObjects вызове в той же манере, что и при Check.
- **Principal** (Phase 2 extraction; design §7): struct `{ID, Type, AccountID, OrganizationID,
  ACR, AMR, MFAAt, SourceIP, DeviceAttestation, ClusterAdmin, BreakGlassActive}` —
  доступен через `authn.MustPrincipal(ctx)` в каждом RPC-handler'е.
- **`kacho_iam_subjects` LISTEN channel** (Phase 1 / E3 baseline): Postgres NOTIFY-канал;
  payload — `subject_id` string (например, `usr_abc123`); fired by outbox-worker после
  successful FGA Write. Phase 4 cache подписывается на этот канал и invalidate-ит записи
  с matching `principal_id`.
- **OpenFGA ListObjects API** — `POST /stores/{store_id}/list-objects`:
  ```json
  {
    "authorization_model_id": "01HXX...",
    "type": "vpc_network",
    "relation": "viewer",
    "user": "user:usr_abc123",
    "contextual_tuples": { "tuple_keys": [...] },
    "context": { "current_time": "2026-05-19T12:00:00Z", "client_ip": "10.0.0.1", "mfa_at": "..." },
    "consistency": "MINIMIZE_LATENCY"
  }
  ```
  Response — `{ "objects": ["vpc_network:net-1", "vpc_network:net-7"], "continuation_token": "" }`.
- **OpenFGA ListUsers API** — `POST /stores/{store_id}/list-users`:
  ```json
  {
    "object": { "type": "vpc_network", "id": "net-1" },
    "relation": "viewer",
    "user_filters": [{ "type": "user" }]
  }
  ```
  Response — `{ "users": [{ "object": { "type": "user", "id": "usr_alice" } }, ...] }`.
  **Используется только в `AccessBindingService.List` когда фильтрация по ресурсу** (см. §6.5).
- **`audit_outbox` table** (kacho-iam; Phase 4 row-insert side): новая таблица skeleton.
  Drainer / consumer — Phase 9 forward-compatible. Phase 4 row-inserts являются best-effort
  side effect (failure to insert не блокирует ListAllowedIDs).

### 2.2 Сущности, **добавляемые** в Phase 4

- **`corelib/authz.ListObjectsClient`** — interface:
  ```go
  type ListObjectsClient interface {
      ListAllowedIDs(
          ctx context.Context,
          principal Principal,
          objectType, relation string,
          opts ListObjectsOptions,
      ) (ids []string, consistencyToken string, err error)

      ListAllowedUsers(
          ctx context.Context,
          objectType, objectID, relation string,
          userFilters []UserFilter,
          opts ListUsersOptions,
      ) (users []SubjectRef, err error)
  }
  ```
  Implementation в `corelib/authz/listobjects.go` (LRU cache + OpenFGA SDK adapter).

- **`corelib/authz.ListObjectsOptions`** — struct:
  ```go
  type ListObjectsOptions struct {
      Consistency        ConsistencyLevel    // MINIMIZE_LATENCY (default) or HIGHER_CONSISTENCY
      ConsistencyToken   string              // for paginated follow-ups (FGA returns it)
      ContextualTuples   []ContextualTuple   // additional tuples for this single eval
      ResourceScopeHint  string              // optional project_id / account_id for cache key
      AuthzModelID       string              // pinned model_id (from Helm Secret)
      MaxResults         int32               // default 10000; FGA hard-limit upstream
  }
  ```
- **`corelib/authz.SubjectRef`** — struct `{Type string, ID string}`.
- **`corelib/authz.cacheKey`** — `(principal_id, principal_type, object_type, relation, resource_scope_hint, authz_model_id)`; cache value — `(ids []string, expires_at time.Time, continuation_token string)`.
- **LISTEN goroutine** — long-lived pgx-connection-bound goroutine, спит на
  `Conn.WaitForNotification(ctx)`; на каждый NOTIFY parses `subject_id` payload и invalidates
  все cache entries with matching `principal_id`. Goroutine рестартуется при connection-loss
  (exponential backoff: 200ms → 5s; см. §5.1 design).
- **Metrics** (added to corelib):
  - `corelib_authz_listobjects_called_total{service,object_type,relation,outcome}` —
    counter; outcome ∈ {`hit`, `miss`, `error`, `empty_grant`}.
  - `corelib_authz_listobjects_duration_seconds{service,object_type,relation,outcome}` —
    histogram (default buckets: 0.001..5).
  - `corelib_authz_listobjects_cache_size{service}` — gauge.
  - `corelib_authz_listobjects_cache_evictions_total{service,reason}` — counter; reason ∈ {`ttl`, `lru`, `notify_invalidate`}.
  - `corelib_authz_listen_notify_invalidates_total{service}` — counter.
  - `corelib_authz_listen_connection_status{service}` — gauge (1 = healthy, 0 = reconnecting).
- **`audit_outbox` table** — kacho-iam side; minimal schema `(id uuid pk, event_type text, principal_id text, principal_type text, object_type text, relation text, result_count int, source_service text, created_at timestamptz default now())`. Inserted on every ListAllowedIDs call from any backend (sent via Internal RPC `kacho.iam.audit.v1.AuditOutboxService.Emit` — fire-and-forget с 100ms-deadline; failure → metric increment, NO request-blocking).

### 2.3 Phase 4 pipeline (нормативно)

```
api-gateway (Phase 2 Principal-extraction) ───► backend service (e.g., kacho-vpc NetworkService.List)
                                                       │
                                                       ▼
                                            authn.MustPrincipal(ctx)
                                                       │
                                                       ▼
                                            corelib/authz.ListAllowedIDs(p, "vpc_network", "viewer", opts)
                                                       │
                                                       ├─ cache.Get(key) ── HIT ──► return cached (ids, "")
                                                       │
                                                       └─ MISS ──► OpenFGA POST /list-objects
                                                                      ▲
                                                                      │ pinned model_id (from KACHO_OPENFGA_MODEL_ID env)
                                                                      │ contextual_tuples = principal.ContextualTuples()
                                                                      │ context = {current_time, client_ip, mfa_at, ...}
                                                                      ▼
                                                                  FGA-engine evaluates DSL v2 + Conditions
                                                                      │
                                                                      ▼
                                                                  Response { objects: ["vpc_network:net-1", ...] }
                                                                      │
                                                       ┌──────────────┘
                                                       ▼
                                            cache.Put(key, ids, ttl=5s)
                                                       │
                                                       ▼
                                            audit_outbox emit (best-effort, 100ms deadline) ──► Phase 9 drainer (future)
                                                       │
                                                       ▼
                                            return (ids, continuation_token)
                                                       │
                                                       ▼
                                            repo.ListByIDs(ctx, ids, page_size, page_token)
                                                       │
                                                       ▼
                                            SELECT * FROM <table>
                                                  WHERE id = ANY($1::text[])
                                                    AND ($2::text='' OR id > $2)  -- keyset pagination
                                                  ORDER BY id ASC
                                                  LIMIT $3
                                                       │
                                                       ▼
                                            return Response { items, next_page_token }
```

LISTEN-invalidate flow:
```
AccessBindingService.Upsert (Phase 1) ──► outbox row ──► outbox-worker
                                                              │
                                                              ▼
                                                          FGA Write + NOTIFY kacho_iam_subjects, payload=<subject_id>
                                                              │
                                              ┌───────────────┴───────────────┐
                                              ▼                               ▼
                                  per-pod LISTEN goroutine #1     per-pod LISTEN goroutine #N
                                              │                               │
                                              ▼                               ▼
                                  cache.InvalidateBySubject(<subject_id>)  (same)
                                              │
                                              ▼
                                  cache_evictions_total{reason="notify_invalidate"} += affected entries
```

### 2.4 SLA targets (production-verified, design §7)

| Op | p50 | p95 | p99 | p99.9 |
|---|---|---|---|---|
| ListObjects (cache hit) | 0.1ms | 0.5ms | 1ms | 2ms |
| ListObjects (miss, ≤100 ids) | 10ms | **50ms** | **100ms** | 200ms |
| ListObjects (miss, ≤1000 ids) | 25ms | **100ms** | **250ms** | 500ms |
| Cache hit ratio | **≥80%** measured (steady state) | | | |
| LISTEN-invalidate latency (binding-change → cache evict) | **≤1s p95** | | | |

Failure of any SLA → CI / k6 gate red, не merge.

---

## 3. Decision Log (P4-D1..D-13 — нормативно)

| Decision | Choice | Rationale |
|---|---|---|
| **P4-D1**: KAC-108 single-Check parent vs ListObjects-per-RPC | **ListObjects на каждый List-RPC; single-Check parent целиком упраздняется** (no legacy mode). | User feedback round 2 2026-05-19 «придерживаться старой конвенции не надо»; single-Check has fundamental coverage holes (fine-grained per-resource grants, listing без project_id, cluster_admin cross-project listing). |
| **P4-D2**: Cache strategy | **LRU 5s TTL** in-process per-pod + **LISTEN-invalidate** via `kacho_iam_subjects` channel. | Design §7 frozen. 5s — стабильный compromise between cache hit ratio (≥80% steady state) and revoke-latency (max 5s до evict, or ≤1s with LISTEN). |
| **P4-D3**: FGA Consistency default | **`MINIMIZE_LATENCY`** для общего случая; **`HIGHER_CONSISTENCY`** explicit для post-own-Write reads (e.g., `AccessBindingService.Upsert(binding); AccessBindingService.List(by_subject=me)` — second call uses HIGHER_CONSISTENCY чтобы увидеть свой только что добавленный binding). | Most List-RPC — periodic UI poll / `yc compute instance list` script, где stale-by-1s acceptable. Read-your-own-writes требует HIGHER. |
| **P4-D4**: Empty grant result | **`return &EmptyResponse{}, nil` (HTTP 200 / gRPC OK)**, **НЕ** PermissionDenied / NotFound. | Tenant doesn't get information that "X exists but you can't see it"; consistent с YC List-semantics (empty list — valid result). Negative test enforced (`UC-L05`). |
| **P4-D5**: Pagination semantics | **Internal `MaxResults=10000`** for ListObjects (FGA upstream hard-limit anyway); если FGA returns `continuation_token` non-empty — call ещё раз (loop within ListAllowedIDs, return combined). SQL pagination — separate keyset `WHERE id > $page_token ORDER BY id LIMIT $page_size` over filtered ids. Page token = base64(`<fga_continuation_token>:<db_last_id>`). | FGA `continuation_token` — server-side cursor; DB-side keyset — stable across cache invalidation (id is immutable PK). |
| **P4-D6**: Fail-mode | **Fail-closed**: FGA unavailable → return `Unavailable` (gRPC code) → REST 503. Cache continues to serve until 5s TTL expires (graceful degradation). NO fail-open default. **Feature flag `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN`** allows fail-open for **reads only** in degraded conditions — default OFF; enabling logs WARN + raises Critical alert (design §17 "Reliability targets"). | Fail-closed default consistent с Phase 3 OPA/FGA fail-mode (design §5.7). Fail-open option существует ради single-region availability SLO, но это explicit operator choice, not default. |
| **P4-D7**: Conditions evaluation | **Honored at ListObjects** — FGA-engine evaluates Conditions per object; objects whose Conditions evaluate `false` excluded из result. Phase 4 passes ContextualTuples + context-map identical to Phase 3 Check (same Principal extraction). | DSL v2 has Conditions; if not honored at ListObjects, `mfa_fresh`-conditioned bindings would leak into list view (bypass). |
| **P4-D8**: Per-type vs per-service ListObjects | **One ListObjects call per object type** (vpc_network, vpc_subnet, compute_instance, etc.) — NO batching across types. Reason: FGA ListObjects API parameter `type` is singular; batching is not native upstream. | Avoids leaky abstraction (don't fabricate fake "service-level" call that FGA doesn't have). |
| **P4-D9**: ContextualTuples / context map content | From Principal: `acr`, `amr`, `mfa_at`, `source_ip`, `device_attestation`, `current_time`, `principal.cluster_admin`, `principal.break_glass_active`. Same set as Phase 3 Check. | Conditions need same context for List as for individual Check; otherwise semantic mismatch. |
| **P4-D10**: SQL filter form | **`WHERE id = ANY($1::text[])`** parameterized; binary-protocol typed array `text[]`. NO `IN ('a','b','c')` string-concat. | Parameterized → no SQL injection (id with `'; DROP TABLE` rejected at parameter level; verified UC `P4.GWT-36`). Postgres pg_protocol array — efficient single-statement binding. |
| **P4-D11**: Cluster-admin / org-admin / account-admin cascade | **Native через FGA DSL v2** (`vpc_network#viewer = ... or viewer from project`, recursively). NO client-side short-circuit ("if principal.ClusterAdmin → return all"). | Single source of truth; FGA already handles cascade; bypass would skip Condition evaluation (break-glass duration check etc.). |
| **P4-D12**: Pinned `authorization_model_id` | Always pinned (read from `KACHO_OPENFGA_MODEL_ID` env / k8s Secret). NO implicit "latest". | Model v2 → v3 transitions during Phase 6+ require consistent behavior; pinned model_id ensures atomic cutover (rolling restart on Secret change, ordered post-bootstrap-job). Phase 3 baseline. |
| **P4-D13**: AccessBindingService.List specific — ListUsers vs ListObjects | Filter by **subject (who-has-what)** → `ListObjects` (object_type=relevant resource type, user=specified subject). Filter by **resource (who-has-access-to-X)** → `ListUsers` (separate FGA API). When **both filters** present → ListObjects + post-filter by resource_id (rare case). When **neither** filter → ListObjects with `objectType=access_binding` would be meaningless; this is a different path — falls back to per-scope viewer check (e.g., must have `viewer@project:<project_id>` to list bindings within that project). | FGA has separate APIs for two directions; using wrong one returns wrong direction of relation graph. |

---

## 4. Target architecture (компактно)

### 4.1 ASCII edges (новые на Phase 4)

```
                ┌────────────────────┐
                │  api-gateway       │
                │  (Phase 2 Princip.)│
                └─────────┬──────────┘
                          │ gRPC
              ┌───────────┼─────────────┬────────────────┬─────────────┐
              ▼           ▼             ▼                ▼             ▼
       kacho-iam    kacho-vpc      kacho-compute   kacho-loadbalancer  (...other future)
              │           │             │                │
              │           │             │                │
              ▼           ▼             ▼                ▼
   ┌─────────────────────────────────────────────────────────────┐
   │      corelib/authz.ListAllowedIDs (per-pod LRU 5s)          │
   └────────────┬─────────────────────────┬──────────────────────┘
                │ miss                    │ LISTEN-invalidate
                ▼                         ▲
        OpenFGA HTTP/gRPC                 │
        POST /list-objects                │
                │                         │
                │                Postgres NOTIFY kacho_iam_subjects
                ▼                         ▲
        FGA-engine evaluate                │
        DSL v2 + Conditions                │
                │                         │
                ▼                         │
        return objects[]                  │
                                          │
                                          │
                AccessBindingService.Upsert (Phase 1)
                          │
                          ▼
                  outbox row + outbox-worker
                          │
                          ▼
                  FGA Write + NOTIFY <subject_id>
```

### 4.2 Что добавляется в каждый репо

**kacho-corelib**:
- `authz/listobjects.go` — public interface + implementation (`fgaListObjectsClient`).
- `authz/listobjects_lru.go` — `hashicorp/golang-lru/v2` wrapper с TTL.
- `authz/listobjects_invalidate.go` — LISTEN goroutine с reconnect.
- `authz/listusers.go` — separate API для AccessBindingService.List by-resource (P4-D13).
- `authz/principal_to_context.go` — Principal → ContextualTuples + context-map (shared с Phase 3 Check).
- `authz/listobjects_test.go` — unit (mock FGA SDK).
- `authz/listobjects_integration_test.go` — testcontainers openfga (1.6.x) + Postgres 16, includes LISTEN race-test.
- `authz/metrics.go` — extension с listobjects_* metrics.

**kacho-vpc** (9 handlers; clean-architecture layer split per репо's CLAUDE.md):
- `internal/apps/kacho/api/network/list.go` — new file (handler delegates to use-case).
- `internal/apps/kacho/api/network/list_usecase.go` — use-case: ListAllowedIDs → repo.ListByIDs.
- Same pattern для subnet, security_group, route_table, address, gateway, private_endpoint, network_interface, address_pool.
- `internal/repo/kacho/pg/<resource>_repo.go` — add `ListByIDs(ctx, ids, pageSize, pageToken)` method per resource.
- `internal/repo/kacho/pg/*_list_integration_test.go` — testcontainers Postgres per resource.

**kacho-compute** (4 handlers): instance, disk, image, snapshot (same pattern).
**kacho-loadbalancer** (2 handlers): network_load_balancer, target_group (same pattern).
**kacho-iam** (9 handlers): account, project, user, service_account, group, role, access_binding (special-case per P4-D13), jit_eligibility, federation_trust_policy.

**kacho-test**:
- `tests/k6/list_filter_kac127_phase4.js` — SLA validation.
- `tests/k6/results/KAC-127-phase4-list-filter.md` — artifact (committed after run on dev).
- `tests/newman/cases/list_filter_*.py` per-service variants (mirror UC-L01..L06, UC-Z02, UC-A02, UC-A07, UC-P03, UC-U05, UC-SA02, UC-AB03, UC-G03).

**kacho-deploy**:
- `helm/umbrella/values.yaml` — add `authz.listobjects.cacheTtl=5s`, `authz.listobjects.maxResults=10000`, `authz.listobjects.failOpen=false`, env-injection в всех 4 backend deployments.
- `helm/umbrella/templates/grafana-dashboards/listobjects.json` — dashboard panels (cache-hit-ratio, listobjects-duration-p95-by-service, listen-invalidate-lag, fga-listobjects-errors-rate).
- `helm/umbrella/templates/alertmanager-rules/listobjects-rules.yaml` — alerts: `ListObjectsP95High` (≥150ms 5min), `ListObjectsCacheHitRatioLow` (≤60% 15min), `ListenConnectionDown` (=0 for 60s), `ListObjectsErrorsRateHigh` (≥1% 5min).

**kacho-workspace**:
- `obsidian/kacho/KAC/KAC-127.md` updated (Phase 4 checklist marked).
- `obsidian/kacho/architecture/list-filtering-pipeline.md` (new, 1-3KB).
- `obsidian/kacho/edges/all-services-to-openfga-listobjects.md` (new).
- `obsidian/kacho/rpc/*-list-*.md` для каждой изменённой List-RPC (краткое, 1-3KB, акцент на «filter via ListAllowedIDs»).

### 4.3 Latency budget (per-RPC List, дополнение к Phase 3 §4.4)

| Step | Budget |
|---|---|
| api-gateway authn (Principal extraction, validated DPoP, cached JWKS) | ≤2ms p95 (from Phase 2) |
| corelib/authz.ListAllowedIDs **cache hit** | ≤1ms p95 |
| corelib/authz.ListAllowedIDs **cache miss** (single page, ≤100 ids) | ≤50ms p95, ≤100ms p99 |
| corelib/authz.ListAllowedIDs **cache miss** (≤1000 ids) | ≤100ms p95, ≤250ms p99 |
| repo.ListByIDs (`WHERE id = ANY($1)`) on 1000 networks with project_id index + id PK index | ≤10ms p95 (verified via k6) |
| Network round-trip к FGA (cluster-internal, gRPC keepalive pool) | ≤5ms p95 |
| audit_outbox emit (fire-and-forget с 100ms deadline) | ≤0ms p95 (asynchronous, deadline-bounded if blocking) |
| **Total p95 List-RPC end-to-end (cache miss, ≤100 ids)** | **≤80ms** |
| **Total p95 List-RPC end-to-end (cache hit, ≤100 ids)** | **≤15ms** |

### 4.4 Cache-key composition (нормативно)

```
cacheKey(p Principal, objectType, relation string, scopeHint, modelID string) string {
    return fmt.Sprintf("%s|%s|%s|%s|%s|%s",
        p.Type, p.ID, objectType, relation, scopeHint, modelID)
}
```

Notes:
- `scopeHint` — optional; for endpoints accepting `project_id` filter (e.g., `ListNetworksRequest.project_id`), set to that value. For "list everything I can see" requests, empty. Different scope hints → different cache entries (avoiding cross-pollination).
- `modelID` — pinned per request from env; included in key so rolling restart с new model_id invalidates cache implicitly (entries with old `modelID` aren't queried; LRU eventually evicts).
- `principal.cluster_admin` / `principal.break_glass_active` flags — NOT in key explicitly; they affect ContextualTuples → FGA Conditions evaluation, but they're stable per JWT TTL (15min, Phase 2). Cache miss happens naturally when JWT rotates. NOT a security risk — Phase 8 CAEP пушит session-revoked → api-gateway evict session.
- `acr` / `amr` / `mfa_at` — NOT in key; these don't affect FGA result for Conditional bindings — FGA evaluates per request with full context. Cache stores result of "current Conditions evaluation for this Principal"; if Principal changes (re-login после step-up), JWT changes → Principal.ID stays but TTL может expire → cache miss naturally. Edge case where same Principal.ID has stale Conditions cache for ≤5s is acceptable (TTL-bounded).

---

## 5. Декомпозиция по компонентам (что именно реализуется)

### 5.1 `corelib/authz/listobjects.go` — реализация ListAllowedIDs

Файлы:
- `authz/listobjects.go` — interface + struct `fgaListObjectsClient`.
- `authz/listobjects_lru.go` — wrapper over `hashicorp/golang-lru/v2` with TTL.
- `authz/listobjects_invalidate.go` — LISTEN goroutine.
- `authz/listusers.go` — separate ListUsers implementation.
- `authz/principal_to_context.go` — shared helper (used by both Check and ListAllowedIDs).
- Все тесты — `*_test.go` (unit) + `*_integration_test.go` (testcontainers).

Конструктор:
```go
func NewListObjectsClient(
    fgaSdk openfgaSdk.OpenFgaApi,
    storeID, modelID string,
    listenConn *pgx.Conn,
    listenChannel string,
    cfg ListObjectsCacheConfig,
) (ListObjectsClient, error)
```
где `ListObjectsCacheConfig = { TTL time.Duration; MaxEntries int; ServiceName string }`.

Метод `ListAllowedIDs`:
1. Build cache key (см. §4.4).
2. cache.Get(key) → if hit and not expired → emit metric `outcome=hit`, return cached.
3. Build `ContextualTuples` from `principal_to_context.go` (used by Phase 3 Check — DRY shared).
4. Call FGA `POST /list-objects` через openfga-go-sdk; pass pinned `authorization_model_id` from opts.AuthzModelID (or env-default).
5. If FGA returns error → emit metric `outcome=error`, return `Unavailable`-mapped gRPC error.
6. If FGA returns `continuation_token` non-empty → loop call until empty или MaxResults breached.
7. Strip "type:" prefix from each `objects[]` entry (e.g., `vpc_network:net-1` → `net-1`).
8. cache.Put(key, ids, ttl=5s).
9. audit_outbox emit (fire-and-forget, ≤100ms deadline; goroutine с context derived).
10. Emit metric `outcome=miss` или `outcome=empty_grant` (if len(ids)==0), `duration_seconds`.
11. Return (ids, continuation_token).

Метод `ListAllowedUsers`:
1. Build cache key — separate cache (different LRU instance; same TTL). Key — `(objectType, objectID, relation, modelID)`.
2. cache.Get(key) → hit → return.
3. FGA `POST /list-users` → response `users[]` → strip prefix.
4. Cache + return.

LISTEN goroutine (`listobjects_invalidate.go`):
- On startup, claims a dedicated pgx.Conn (separate from main pool).
- `LISTEN kacho_iam_subjects` → loop `conn.WaitForNotification(ctx)`.
- On NOTIFY, parse payload (subject_id string).
- For each cache (objects + users):
  - For objects-cache: scan all entries, remove any whose key starts with `*|<subject_id>|*` (principal_id at position 2 в key formula §4.4).
  - For users-cache: invalidate entries where invalidating subject is listed in cached `users[]` (linear scan; cache size bounded by MaxEntries — OK at scale ≤10000 entries).
- Increment `corelib_authz_listen_notify_invalidates_total`.
- On connection-loss (`pgconn.PgError` или EOF) → close cache invalidation (skip; better stale-by-5s than crash), close conn, sleep exponential backoff (200ms, 400ms, 800ms, 1.6s, 3.2s, max 5s), reconnect. Metric `corelib_authz_listen_connection_status=0` during reconnect.

### 5.2 Per-service handler rewrite (pattern)

Single canonical template (`kacho-vpc/internal/apps/kacho/api/network/list_usecase.go`):

```go
type ListNetworksUseCase struct {
    authz authz.ListObjectsClient
    repo  NetworkRepoReader
    audit audit.Logger
}

func (uc *ListNetworksUseCase) Execute(
    ctx context.Context,
    p authn.Principal,
    req *vpcv1.ListNetworksRequest,
) (*vpcv1.ListNetworksResponse, error) {
    consistency := authz.MinimizeLatency
    if req.GetConsistency() == vpcv1.Consistency_CONSISTENCY_HIGHER {
        consistency = authz.HigherConsistency
    }

    ids, _, err := uc.authz.ListAllowedIDs(ctx, p, "vpc_network", "viewer", authz.ListObjectsOptions{
        Consistency:       consistency,
        ResourceScopeHint: req.ProjectId,
        AuthzModelID:      uc.authz.PinnedModelID(),
    })
    if err != nil {
        return nil, errs.Wrap(errs.ErrUnavailable, "authz lookup failed: %v", err)
    }
    if len(ids) == 0 {
        return &vpcv1.ListNetworksResponse{Networks: nil, NextPageToken: ""}, nil
    }

    networks, nextToken, err := uc.repo.ListByIDs(ctx, ids, req.GetPageSize(), req.GetPageToken())
    if err != nil {
        return nil, errs.Wrap(errs.ErrInternal, "list networks: %v", err)
    }
    return &vpcv1.ListNetworksResponse{Networks: networks, NextPageToken: nextToken}, nil
}
```

Repo method (`internal/repo/kacho/pg/network_repo.go`):
```go
func (r *NetworkRepo) ListByIDs(ctx context.Context, ids []string, pageSize int32, pageToken string) ([]*vpcv1.Network, string, error) {
    if len(ids) == 0 {
        return nil, "", nil
    }
    if pageSize <= 0 || pageSize > 1000 {
        pageSize = 100
    }
    cursor, _ := decodePageToken(pageToken) // base64(last_id); empty token → ""

    rows, err := r.pool.Query(ctx, `
        SELECT id, project_id, name, description, labels, created_at, status_code, ...
        FROM networks
        WHERE id = ANY($1::text[])
          AND ($2::text = '' OR id > $2)
        ORDER BY id ASC
        LIMIT $3 + 1
    `, ids, cursor, pageSize)
    // ... scan, return with nextToken if rows > pageSize.
}
```

### 5.3 `AccessBindingService.List` — особый случай (P4-D13)

Spec для request:
```protobuf
message ListAccessBindingsRequest {
  oneof filter {
    string subject_id = 1;     // "list bindings WHERE subject = X"
    Resource resource = 2;     // "list bindings WHERE resource = Y"
  }
  string project_id = 3;       // scope; required for default-deny matrix
  int32 page_size = 4;
  string page_token = 5;
}
```

Handler:
```go
switch f := req.Filter.(type) {
case *ListAccessBindingsRequest_SubjectId:
    // Direction: who-has-what (find all bindings where subject=f.SubjectId).
    // Use ListObjects of "access_binding" type for relation "of_subject"
    // (DSL pattern: access_binding#of_subject:[user]); list bindings affecting this subject.
    // Authorize: requester must have viewer@account:<subject_account_id> OR be subject themselves.
    ...
case *ListAccessBindingsRequest_Resource:
    // Direction: who-has-access-to-Y.
    // Use ListUsers (object=f.Resource, relation=viewer/editor/admin).
    users, err := uc.authz.ListAllowedUsers(ctx, f.Resource.Type, f.Resource.Id, "viewer", []UserFilter{
        {Type: "user"}, {Type: "service_account"}, {Type: "group"},
    }, ListUsersOptions{Consistency: ...})
    // Map users → access_bindings DB rows via SELECT WHERE subject_id IN ($users) AND resource_id = $f.Resource.Id.
    ...
}
```

(Detailed flow в §6.5.)

### 5.4 Fail-modes (нормативно)

| Failure | Behavior | Recovery |
|---|---|---|
| FGA unreachable (network / 503) | `ListAllowedIDs` returns `Unavailable` gRPC code; handler maps to REST 503. If cache has fresh entry (≤5s TTL) — that entry IS returned (graceful degradation). | FGA recovers → next miss succeeds. |
| FGA returns 4xx (auth / bad input) | Server-side bug in our model_id pinning или contextual_tuples — return `Internal`; alert fires. | Operator investigates; pause deploys until fix. |
| LISTEN connection lost | Goroutine reconnects with exponential backoff (200ms..5s); cache continues serving but new invalidations missed during reconnect window. Metric `listen_connection_status=0`. | After reconnect, cache MAY have stale entries for up-to-5s (TTL expires anyway); operator gets alert `ListenConnectionDown ≥60s`. |
| Postgres `audit_outbox` insert fails | Metric `audit_outbox_emit_errors_total += 1`; **request NOT blocked** (audit is best-effort). | Phase 9 drainer catches up; pre-Phase-9 явное log-warn. |
| `repo.ListByIDs` SQL error | Map per `mapRepoErr` to `Internal`; handler returns 500. | Operator investigates; could be DB connection saturation. |
| LRU cache memory pressure | LRU evict (lru_reason=`lru`); next request misses naturally. | Operator может tune `MaxEntries`. |
| `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN=true` activated | On FGA-error, return **all** ids from `repo.List(no-filter)` (degraded mode); audit_outbox emit `event_type=fail_open_activated`; raise Critical alert. | Operator de-escalates; flag flips back off after FGA recovery. **Default OFF**. |

---

## 6. GWT-сценарии (42 scenarios — exceeds ≥40 mandated)

> **Convention**: каждый сценарий имеет ID `P4.GWT-NN`. UC backreferences (`UC-X` from §3-4 of test migration matrix) указаны inline для traceability.

### 6.1 corelib ListAllowedIDs — core (6 scenarios)

#### Scenario P4.GWT-01: cache miss → OpenFGA call → result cached → second call hit
**UC**: UC-L01

**Given** OpenFGA store seeded with tuples:
- `vpc_network:net-1#viewer@user:usr_alice`
- `vpc_network:net-2#viewer@user:usr_alice`

**And** `corelib/authz` cache initialized empty for service `kacho-vpc`.

**And** Principal = `{Type: user, ID: usr_alice, ACR: "2", AMR: ["pwd","webauthn"]}`.

**When** `ListAllowedIDs(ctx, principal, "vpc_network", "viewer", opts={Consistency: MINIMIZE_LATENCY, AuthzModelID: <pinned>})` first called.

**Then** OpenFGA SDK call `POST /list-objects` is made (verifiable via fixture interceptor counter).
**And** Response `ids = ["net-1", "net-2"]` returned (deterministic alphabetical order — see GWT-05).
**And** Metric `corelib_authz_listobjects_called_total{service="kacho-vpc", object_type="vpc_network", relation="viewer", outcome="miss"} += 1`.
**And** Metric `corelib_authz_listobjects_duration_seconds{...}` observed with sane value (≤100ms).
**And** Cache contains entry with key `user|usr_alice|vpc_network|viewer||<modelID>`.

**When** Same call made again within 5s.

**Then** OpenFGA SDK call counter unchanged (NO second round-trip).
**And** Response `ids = ["net-1", "net-2"]` (same).
**And** Metric `corelib_authz_listobjects_called_total{...outcome="hit"} += 1`.
**And** `duration_seconds` observation ≤1ms (cache lookup only).

#### Scenario P4.GWT-02: cache hit returns same IDs without OpenFGA round-trip
**UC**: UC-L01

**Given** Cache populated from prior call с `(usr_alice, vpc_network, viewer) → ["net-1", "net-7"]`, expires_at = now() + 5s.

**When** `ListAllowedIDs` called с identical args within 3s.

**Then** Result `ids = ["net-1", "net-7"]` (same instances or copy — implementation-dependent; equal in value).
**And** Zero FGA SDK calls.
**And** `outcome="hit"` metric increment.

#### Scenario P4.GWT-03: fail-closed on OpenFGA unavailable → Unavailable error (not partial result)
**UC**: UC-L01 + UC-L05 negative

**Given** OpenFGA control-plane down (kubelet kills pod; service endpoint returns connection-refused).

**And** Cache empty (cold start).

**And** `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN=false` (default).

**When** `ListAllowedIDs(usr_alice, vpc_network, viewer)` called.

**Then** OpenFGA SDK times out per configured deadline (5s default).
**And** Result is gRPC `codes.Unavailable` error with message `authz lookup failed: ...` (mapped to REST 503).
**And** Handler converts: `vpc.NetworkService.List` returns `Unavailable` → api-gateway 503 to client.
**And** Cache NOT polluted with empty entry (failed eval does not store).
**And** Metric `corelib_authz_listobjects_called_total{...outcome="error"} += 1`.

#### Scenario P4.GWT-04: principal ContextualTuples передаются (acr=2 vs acr=3 → different Conditions results)
**UC**: UC-L01 + UC-C03 (mfa_fresh condition)

**Given** OpenFGA store has tuple:
`vpc_network:net-secret#admin@user:usr_alice[mfa_fresh]`
where `mfa_fresh` evaluates `acr_value == "3" && "webauthn" in amr_claims && current_time - mfa_at < 15m`.

**And** Two principals:
- `P1 = {ID: usr_alice, ACR: "2", AMR: ["pwd"], MFAAt: <30m ago>}` (no recent step-up).
- `P2 = {ID: usr_alice, ACR: "3", AMR: ["pwd", "webauthn"], MFAAt: <5m ago>}` (recent step-up).

**When** `ListAllowedIDs(P1, vpc_network, admin)` called.

**Then** Result `ids = []` (net-secret excluded — Conditions failed because acr != 3).

**When** `ListAllowedIDs(P2, vpc_network, admin)` called.

**Then** Result `ids = ["net-secret"]` (Conditions evaluated true).
**And** Each call hit FGA separately (cache key differs only by Principal.ID, which is same, but actually the cache stores results per `cacheKey = (P.Type, P.ID, type, relation, scope, modelID)` — same key — so the SECOND call within 5s WOULD hit cache; this scenario tests that **fresh** invocation gives different results when contexts differ. Test setup: each invocation comes from different request lifecycle with stale-cache eviction между ними OR cache disabled in this test (`cacheTtl=0`).)

#### Scenario P4.GWT-05: deterministic ordering — sorted ids in result для stable pagination
**UC**: UC-L02 + UC-L06

**Given** OpenFGA returns `objects = ["vpc_network:net-z", "vpc_network:net-a", "vpc_network:net-m"]` (unsorted).

**When** `ListAllowedIDs` invoked.

**Then** Returned `ids = ["net-a", "net-m", "net-z"]` — alphabetically sorted (corelib applies `sort.Strings`).
**And** Subsequent identical call returns same order.

**Rationale**: keyset-pagination `WHERE id > $page_token ORDER BY id ASC` requires deterministic ordering of `ids[]`; FGA does NOT guarantee order — corelib sorts before returning.

#### Scenario P4.GWT-06: pagination > 10000 IDs → follow-up call with continuation token
**UC**: UC-L06

**Given** User has 15000 vpc_network bindings (e.g., `cluster_admin` cascading to всех networks).

**When** `ListAllowedIDs(usr_admin, vpc_network, viewer, opts={MaxResults: 10000})` called.

**Then** Internal implementation makes **2** FGA calls:
- First call returns `objects[]` (10000 entries) + `continuation_token = "tok_xyz"`.
- Second call с `continuation_token="tok_xyz"` returns remaining 5000 + empty continuation_token.

**And** Aggregated result `ids[]` length = 15000.
**And** Both FGA calls observable via SDK interceptor (count=2).
**And** Returned `consistencyToken = ""` (final; not paginated further).
**And** Operator alert NOT triggered (this is normal cluster-admin scenario).

### 6.2 Empty grant (3 scenarios)

#### Scenario P4.GWT-07: user with 0 bindings → ListNetworks returns 200 empty, не 403
**UC**: UC-L05, UC-A07, UC-U05, UC-P03

**Given** User `usr_newbie` has zero AccessBindings to any vpc_network (and no cluster/org/account/project cascade grants).

**When** `kacho-vpc.NetworkService.List` called с Authorization: Bearer usr_newbie's DPoP-bound JWT.

**Then** Handler does `ListAllowedIDs(usr_newbie, vpc_network, viewer)` → returns `ids = []`.
**And** Handler short-circuits: returns `&vpcv1.ListNetworksResponse{Networks: nil, NextPageToken: ""}` with gRPC OK.
**And** Client receives `200 OK` (REST) с empty `networks: []` array.
**And** NO `PermissionDenied` / NO `Forbidden`.
**And** Metric `outcome="empty_grant"` increment.

#### Scenario P4.GWT-08: user with 0 bindings + cluster-admin tuple → returns all
**UC**: UC-L04 (cluster cascade)

**Given** User `usr_root` has no per-resource bindings, но `cluster:cluster_kacho_root#system_admin@user:usr_root` tuple exists.

**When** `ListAllowedIDs(usr_root, vpc_network, viewer)`.

**Then** FGA evaluates cascade `vpc_network#viewer = ... or viewer from project` → `project#viewer = ... or viewer from account` → `account#viewer = ... or any_admin from cluster` → resolves to **all** networks.
**And** Result `ids[]` = all network ids across all projects.
**And** k6 test verifies на 1000-network corpus: all 1000 returned.

#### Scenario P4.GWT-09: SA with 0 bindings → returns empty (consistent с user path)
**UC**: UC-L05

**Given** ServiceAccount `sa_app` has zero bindings.

**When** `kacho-vpc.NetworkService.List` called via SA token (Hydra `client_credentials` JWT).

**Then** Handler does `ListAllowedIDs({Type: service_account, ID: sa_app}, ...)` → returns `ids = []`.
**And** Returns 200 empty (same path as user).
**And** Consistent default-deny matrix UC-Z02 (Phase 4 §6.4 design — SA scope tested identically to user scope).

### 6.3 2-id grant + 100-id grant (3 scenarios)

#### Scenario P4.GWT-10: user with 2 explicit per-resource bindings → returns exactly those 2
**UC**: UC-L01 + UC-L02

**Given** Tuples:
- `vpc_network:net-1#viewer@user:usr_alice`
- `vpc_network:net-2#viewer@user:usr_alice`

**And** Other 998 networks exist в БД с no relation к usr_alice.

**When** `kacho-vpc.NetworkService.List(usr_alice)`.

**Then** `ListAllowedIDs` returns `["net-1", "net-2"]`.
**And** SQL `SELECT ... WHERE id = ANY(['net-1','net-2'])` matches 2 rows.
**And** Response `networks: [{id: "net-1", ...}, {id: "net-2", ...}]`, length=2.
**And** `next_page_token = ""` (≤page_size).

#### Scenario P4.GWT-11: user with 100 bindings → returns 100 networks
**UC**: UC-L01 + UC-L02 + UC-L06 (pagination)

**Given** 100 tuples `vpc_network:net-{001..100}#viewer@user:usr_alice`.
**And** Request `page_size=50, page_token=""`.

**When** First call.

**Then** Returned 50 networks (sorted by id), `next_page_token = base64("net-050")`.

**When** Second call с `page_token = next_page_token`.

**Then** Returned next 50 networks (net-051..net-100), `next_page_token = ""`.

**And** Two FGA calls? — **NO**: FGA вернул все 100 в одном вызове, и corelib закешировал; pagination всё-таки происходит на DB-уровне.
**And** Cache key not affected by page_token (FGA call is per-Principal, not per-page).

#### Scenario P4.GWT-12: user with bindings к removed networks (FGA tuple orphan from DB) → returns only live
**UC**: UC-L02 negative (graceful dangling-ref)

**Given** Tuples:
- `vpc_network:net-alive#viewer@user:usr_alice`
- `vpc_network:net-gone#viewer@user:usr_alice` (network was deleted from `networks` table; tuple-delete didn't fire yet due to outbox lag).

**When** `ListAllowedIDs(usr_alice, vpc_network, viewer)`.

**Then** FGA returns `["net-alive", "net-gone"]`.

**When** `repo.ListByIDs(ctx, ["net-alive", "net-gone"], ...)`.

**Then** SQL `WHERE id = ANY(...)` matches only "net-alive" — Postgres skips non-existent row.
**And** Response `networks: [{id: "net-alive"}]`, length=1.
**And** Client sees only live networks (graceful dangling-ref handling per workspace `CLAUDE.md` §«Кросс-доменные ссылки» — even within-service: stale tuples cleaned by outbox eventually).

### 6.4 Cluster-admin / project-admin cascade (5 scenarios)

#### Scenario P4.GWT-13: cluster-admin → returns all networks across all accounts
**UC**: UC-L04 + UC-Z02 (cluster scope)

**Given** `cluster:cluster_kacho_root#system_admin@user:usr_root` tuple.

**And** 1000 networks exist across 50 accounts × 20 projects.

**When** `ListAllowedIDs(usr_root, vpc_network, viewer)`.

**Then** Result `ids[]` length=1000 (all networks).
**And** Cascade computed via DSL v2: `vpc_network#viewer = ... or viewer from project → project#viewer = ... or viewer from account → account#viewer = ... or any_admin from cluster`.
**And** NO client-side short-circuit (`if principal.ClusterAdmin → return all`) — purely FGA-driven (P4-D11).

#### Scenario P4.GWT-14: cluster-admin revoked → cache invalidate ≤1s → next call returns subset
**UC**: UC-Z03 (reactivity ≤5s upgraded to ≤1s via LISTEN)

**Given** `usr_root` has cluster_admin tuple; current cache hit returns 1000 networks.

**When** `AccessBindingService.Delete(binding to cluster_admin for usr_root)` called.

**Then** outbox row inserted (Phase 1 atomic outbox-on-mutation).
**And** outbox-worker (within 200ms typical) consumes row → FGA Delete tuple + `NOTIFY kacho_iam_subjects, 'usr_root'`.
**And** All backend pods' LISTEN goroutine receives NOTIFY within 1s.
**And** Each pod invokes `cache.InvalidateBySubject("usr_root")` → entries with key starting `user|usr_root|*` evicted.

**When** Subsequent `kacho-vpc.NetworkService.List(usr_root)` after NOTIFY.

**Then** Cache miss → FGA ListObjects re-evaluated → cascade now absent → returns only directly-granted (e.g., 0 networks if no other bindings).
**And** Metric `corelib_authz_listen_notify_invalidates_total += 1`.
**And** k6 measure of "AccessBinding.Delete → next List returns reduced set" latency: p95 ≤1s.

#### Scenario P4.GWT-15: break-glass active → cluster-admin included DURING window; after expiry → excluded
**UC**: UC-LC04 partial + UC-C-break_glass_window

**Given** Tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_oncall[break_glass_window]`.

**And** Condition `break_glass_window(current_time, expires_at)` evaluates true when `current_time < expires_at`.

**And** `expires_at = now() + 30min`.

**When** `ListAllowedIDs(usr_oncall, vpc_network, viewer)` called.

**Then** FGA evaluates Condition with `context.current_time = now()` → returns true → tuple active → cascade applies → returns all networks.

**When** Same call after 35min (без re-step-up; same JWT if not expired).

**Then** FGA evaluates → `current_time > expires_at` → Condition false → tuple excluded → returns empty (or whatever non-emergency bindings).
**And** Cache TTL=5s → at worst stale-by-5s; eventual consistency met.

#### Scenario P4.GWT-16: project-admin cascade — admin@project:prj_x → ListAllowedIDs (vpc_network, admin) returns all networks in prj_x
**UC**: UC-L04

**Given** Tuple `project:prj_x#admin@user:usr_pm`.
**And** Networks {net-x1, net-x2, net-x3} have `project_id=prj_x`.
**And** Networks {net-y1, net-y2} have `project_id=prj_y` (other project).
**And** FGA tuples mirror: `vpc_network:net-x1#project@project:prj_x`, etc. (Phase 1 outbox-worker populated).

**When** `ListAllowedIDs(usr_pm, vpc_network, admin)`.

**Then** Cascade `vpc_network#admin = ... or admin from project` matches net-x1, net-x2, net-x3.
**And** Result `ids = ["net-x1", "net-x2", "net-x3"]` (excludes net-y*).

#### Scenario P4.GWT-17: user has editor@project:prj_x + viewer@vpc_network:net_y outside project → returns project networks + net_y
**UC**: UC-L01 + UC-L04

**Given**:
- Tuple `project:prj_x#editor@user:usr_dev`.
- Tuple `vpc_network:net_y#viewer@user:usr_dev` (net_y is in prj_z, unrelated).

**When** `ListAllowedIDs(usr_dev, vpc_network, viewer)`.

**Then** Union of:
- (a) Networks from prj_x via cascade editor → viewer (DSL: viewer = ... or editor from project).
- (b) Direct binding net_y.

**And** Result includes prj_x networks + net_y; excludes other prj_z networks.

#### Scenario P4.GWT-18: Project moved to another Account → ListAllowedIDs cache invalidate via subject_change_outbox
**UC**: UC-A06 + UC-Z03

**Given** Project `prj_finance` lives in `acc_aurora`; binding `account:acc_aurora#viewer@user:usr_auditor` → cascade gives usr_auditor access to all networks in prj_finance.

**And** Cache hit (usr_auditor → list of N networks).

**When** `ProjectService.Move(prj_finance, target_account=acc_horizon)` (Phase 1 atomic CAS).

**Then** outbox row inserted → outbox-worker emits FGA Write `project:prj_finance#account@account:acc_horizon` (replacing prior) + NOTIFY for every subject in old account who had inherited access.

**Implementation detail**: outbox-worker doesn't enumerate all subjects (could be 10k); instead, it emits **scope-broad NOTIFY** with payload `"scope:account:acc_aurora"` (a special payload format). corelib LISTEN handler treats `scope:` prefix as "invalidate any cache entry whose ResourceScopeHint or recursive cascade includes acc_aurora". For Phase 4 simplicity: cache.InvalidateAll() when prefix is `scope:` (conservative — better some over-invalidation than missing subject).

**And** Subsequent `NetworkService.List(usr_auditor)` returns empty (binding removed via cascade-break).
**And** Trade-off documented (open question Q-scope-invalidate resolved in §10).

### 6.5 Per-service integration (7 scenarios)

#### Scenario P4.GWT-19: kacho-vpc NetworkService.List uses ListAllowedIDs
**UC**: UC-L01 + UC-A07

**Given** vpc service deployed Phase 4 build; cache configured TTL=5s.

**When** Client sends `GET /vpc/v1/networks?project_id=prj_x` через api-gateway.

**Then** api-gateway extracts Principal from DPoP-bound JWT.
**And** Forwards к vpc gRPC `NetworkService.List`.
**And** Handler invokes `uc.authz.ListAllowedIDs(p, "vpc_network", "viewer", opts={ResourceScopeHint: "prj_x"})`.
**And** SQL `SELECT ... WHERE id = ANY($ids) AND project_id = $1 ORDER BY id`.
**And** Response shape `{networks: [...], nextPageToken: ""}`.

#### Scenario P4.GWT-20: kacho-compute InstanceService.List uses ListAllowedIDs
**UC**: UC-L01 + UC-Z02 (compute service coverage)

**Given** compute service deployed Phase 4.

**When** Client `GET /compute/v1/instances?project_id=prj_x`.

**Then** Same pattern: `ListAllowedIDs(p, "compute_instance", "viewer", ...)`.
**And** Filters by `WHERE id = ANY($ids) AND project_id = $1`.
**And** Returns `{instances: [...], nextPageToken: ""}`.

#### Scenario P4.GWT-21: kacho-loadbalancer NetworkLoadBalancerService.List uses ListAllowedIDs
**UC**: UC-L01 + lb service coverage

**Given** loadbalancer service deployed Phase 4.

**When** Client `GET /loadbalancer/v1/networkLoadBalancers?folder_id=...` (note: YC-style still `folder_id` в proto-path, но internally `project_id` per Phase 1 KAC-124 rename).

**Then** Same ListAllowedIDs pattern with type=`lb_network_load_balancer`.

#### Scenario P4.GWT-22: kacho-iam ProjectService.List uses ListAllowedIDs
**UC**: UC-P03 + UC-L01

**Given** iam service deployed Phase 4.

**When** Client `GET /iam/v1/projects?account_id=acc_aurora`.

**Then** Handler does `ListAllowedIDs(p, "project", "viewer", opts={ResourceScopeHint: "acc_aurora"})`.
**And** Returns projects within acc_aurora visible к principal.

#### Scenario P4.GWT-23: kacho-iam AccessBindingService.List by subject_id — uses ListObjects
**UC**: UC-AB03 (ListBySubject)

**Given** Tuples:
- `vpc_network:net-1#viewer@user:usr_alice`
- `project:prj_x#admin@user:usr_alice`

**And** AccessBinding rows in `access_bindings` table mirror these.

**When** Client calls `AccessBindingService.List(filter={subject_id: "usr_alice"})`.

**Then** Handler determines direction: filter is by subject → use **ListObjects** strategy.
**And** For each of the recognized FGA object types (vpc_network, project, ...) handler iterates and calls `ListAllowedIDs(usr_alice, <type>, <relation>)` per type — costly but correct. Alternative implementation note: a single call with `objectType="access_binding"` would require introducing the `access_binding` type в FGA DSL; **NOT** introduced в Phase 4 (P4-D13 decision). The iteration is bounded — N <= number of FGA object types in DSL (~19); each call ≤50ms p95 → total p95 ≤1s — acceptable for AccessBindings List (admin-facing endpoint).
**And** Result: list of bindings matching usr_alice as subject (after SQL join filter).

#### Scenario P4.GWT-24: AccessBindingService.List by resource — uses ListUsers (P4-D13)
**UC**: UC-AB03 (ListByResource)

**Given** Tuples:
- `vpc_network:net-1#viewer@user:usr_alice`
- `vpc_network:net-1#editor@user:usr_bob`
- `vpc_network:net-1#admin@user:usr_carol`

**When** Client `AccessBindingService.List(filter={resource: {type: vpc_network, id: net-1}})`.

**Then** Handler invokes for relation in [admin, editor, viewer]:
`uc.authz.ListAllowedUsers(ctx, "vpc_network", "net-1", relation, user_filters=[user, service_account, group])`.

**And** Aggregates users from 3 calls → unique subject set {usr_alice, usr_bob, usr_carol}.

**And** Authorize check: requester (the caller) must have viewer@vpc_network:net-1 themselves — `Check(principal, "viewer", "vpc_network", "net-1")` before listing other subjects (a fine-grained "you must see the resource yourself to enumerate its grantees").

**And** SQL `SELECT * FROM access_bindings WHERE resource_type='vpc_network' AND resource_id='net-1' AND subject_id IN ($subjects)` (joined with subject-allowance).

#### Scenario P4.GWT-25: Internal-only resource (AddressPool) — list-filtered same way
**UC**: запрет #6 + UC-L01

**Given** AddressPool — Internal admin resource (kacho-vpc, см. workspace `CLAUDE.md` §«Запреты» #6).
**And** Tuple `vpc_address_pool:pool-1#viewer@user:usr_admin` (admin user with cluster-admin).

**When** Client tries `InternalAddressPoolService.List` через internal-port 9091 (admin-UI).

**Then** Handler invokes `ListAllowedIDs(p, "vpc_address_pool", "viewer")`.
**And** Cluster-admin cascade applies → list all pools.

**When** Same call comes through external TLS endpoint (port 443) (запрет #6 violation attempt).

**Then** api-gateway DOES NOT register `InternalAddressPoolService` on public mux → request returns 404.
**And** Phase 4 does NOT change this — verified by `kacho-api-gateway` integration test `internal_only_routing_test.go`.

### 6.6 LISTEN invalidate (3 scenarios)

#### Scenario P4.GWT-26: AccessBinding Upsert → cache invalidate per-pod ≤1s
**UC**: UC-Z03 (reactivity)

**Given** 3 backend pods running (vpc x3); each holds cache `(usr_alice, vpc_network, viewer) → ["net-1"]`.

**When** `AccessBindingService.Upsert(subject_id=usr_alice, resource=vpc_network:net-2, relation=viewer)`.

**Then** outbox row inserted.
**And** outbox-worker processes: FGA Write tuple `vpc_network:net-2#viewer@user:usr_alice` + `NOTIFY kacho_iam_subjects, 'usr_alice'`.

**And** Each of the 3 pods' LISTEN goroutine receives NOTIFY within ≤1s (measured via test instrumentation).
**And** Each pod cache invalidates entries `user|usr_alice|*`.
**And** Metric `corelib_authz_listen_notify_invalidates_total` += 1 per pod.

**When** `kacho-vpc.NetworkService.List(usr_alice)` issued to any of 3 pods after NOTIFY.

**Then** Cache miss → FGA ListObjects returns ["net-1", "net-2"].

**And** End-to-end latency measure (Upsert → next List sees new tuple): k6 verifies p95 ≤1s, p99 ≤2s.

#### Scenario P4.GWT-27: AccessBinding Revoke (status REVOKED) → same invalidation behavior
**UC**: UC-Z03 + UC-AB04 (delete-resurrect)

**Given** Tuple `vpc_network:net-1#viewer@user:usr_alice` exists; cache hit returns ["net-1"].

**When** `AccessBindingService.Delete(binding_id)` (which transitions status to REVOKED in DB, FGA Delete by outbox-worker).

**Then** outbox row → FGA Delete + NOTIFY 'usr_alice'.
**And** Cache invalidated per-pod ≤1s.

**When** Next `List` for usr_alice.

**Then** ids = [] (binding removed).

#### Scenario P4.GWT-28: Group member change → fanout NOTIFY per member
**UC**: UC-G05 (Group member changes affect access)

**Given** Group `grp_admins` has 50 members. Tuple `vpc_network:net-1#admin@group:grp_admins#member`.
**And** 50 caches per pod each containing `(member_id, vpc_network, admin) → ["net-1"]`.

**When** `GroupService.RemoveMember(grp_admins, member=usr_x)`.

**Then** outbox row → outbox-worker:
1. FGA Delete tuple `group:grp_admins#member@user:usr_x`.
2. NOTIFY `kacho_iam_subjects, 'usr_x'`.

**And** Per-pod LISTEN evicts cache `user|usr_x|*` ≤1s.

**Scope question**: should removing a member fanout NOTIFY to all OTHER members (because their group-graph changed)? — **No**, individual member tuples are not affected by another member's removal; their access through this group is preserved. The single NOTIFY for usr_x is sufficient. Documented as Q-group-fanout in §10.

**And** Next `List(usr_x)` returns reduced set (lost group cascade access to net-1).

### 6.7 k6 SLA validation (5 scenarios)

#### Scenario P4.GWT-29: 1000 networks/project, N=1 binding, 100 RPS sustained 5min → p95 ≤100ms, p99 ≤250ms
**UC**: UC-L03

**Given** 1000 networks seeded в kacho-vpc DB.
**And** Each of 100 user accounts has 1 binding to one network.
**And** k6 scenario: 100 concurrent VUs, sustained 5min, each VU calls `NetworkService.List` every 3s on average.

**When** k6 run on dev-stand `e2c825` (DR-like with 3 backend replicas, OpenFGA cluster 3 replicas).

**Then** k6 metrics:
- `http_req_duration{op=ListNetworks} p95 ≤ 100ms`.
- `http_req_duration{op=ListNetworks} p99 ≤ 250ms`.
- `cache_hit_ratio ≥ 80%`.
- `error_rate ≤ 0.01%`.

**Artifact**: `kacho-test/tests/k6/results/KAC-127-phase4-list-filter.md` committed (file with rendered HTML chart + JSON metrics).

#### Scenario P4.GWT-30: same workload, N=100 bindings → SLA still met
**UC**: UC-L03 + UC-L02 (100-id grant)

**Given** Same as GWT-29, но каждый user has 100 bindings.

**When** k6 run.

**Then** SLA met (p95 ≤100ms, p99 ≤250ms) despite larger result-set (100 ids).
**And** `repo.ListByIDs` SQL latency ≤10ms p95 (id PK index + project_id index).

#### Scenario P4.GWT-31: 1000 networks/project, N=500 bindings, 1000 RPS sustained 30min → SLA p95 ≤100ms; cache hit ratio ≥80%
**UC**: UC-L03 (production-realistic load)

**Given** Same corpus, 1000 RPS distributed across 1000 unique users (each with 500 bindings).
**And** Sustained 30 minutes.

**When** k6 run on dev-stand с full HPA + OpenFGA cluster.

**Then**:
- `p95 ListObjects (cache miss, ≤500 ids) ≤ 100ms`.
- `p99 ≤ 250ms`.
- `cache_hit_ratio ≥ 80%` (steady state after warm-up).
- `error_rate ≤ 0.1%`.
- Memory: cache size bounded by `MaxEntries`; no OOM.

#### Scenario P4.GWT-32: LISTEN-invalidate stress — 1000 revokes/min → cache invalidation latency p95 ≤1s
**UC**: UC-Z03 + UC-I04

**Given** 1000 users each with cache hits.
**And** k6 scenario: 1000 AccessBinding.Delete per minute (sustained 10 min).

**When** k6 run, instrumented with timestamps: `(t_delete_committed, t_pod_invalidated)`.

**Then** p95 `t_pod_invalidated - t_delete_committed ≤ 1s`.
**And** No NOTIFY-loss observed (counter `notify_received_total ≥ 1000 * 10 = 10000` per pod).
**And** No LISTEN reconnects during run (`listen_connection_status = 1` constant).

#### Scenario P4.GWT-33: FGA cluster downtime simulation → fail-closed; cache continues for 5s TTL
**UC**: UC-L05 + UC-L01 graceful degradation

**Given** Cache populated (e.g., 100 entries fresh, ≤5s old).

**When** FGA service stopped (kubectl scale openfga --replicas=0).

**Then** For requests that **hit cache**: response succeeds (graceful degradation).
**And** For requests that **miss cache**: returns `Unavailable` 503 (fail-closed).
**And** After 5s TTL all entries expired → all requests now return 503.

**When** FGA scaled back up.

**Then** New requests cache-miss → FGA call succeeds → cache repopulates.
**And** System recovers without manual intervention.
**And** Total `error_count` reflects only requests during 5s-after-cache-expiry window.

### 6.8 OpenFGA model versioning (2 scenarios)

#### Scenario P4.GWT-34: pinned authorization_model_id per ListObjects call — backward-compat across v2 → v3
**UC**: UC-I02 (model versioning)

**Given** Two FGA authorization models in store:
- model v2 (current pinned, in Secret `openfga-model-id: 01HXX_v2`).
- model v3 (newer, in store but not pinned).

**When** `ListAllowedIDs` invoked with `opts.AuthzModelID = "01HXX_v2"` (from env).

**Then** FGA call includes `authorization_model_id: 01HXX_v2`.
**And** Result reflects v2 model semantics (e.g., if v3 introduced new relation `vpc_network#operator` not in v2, query for that relation under v2 returns NOT_FOUND/Internal).

**When** Helm chart updates `openfga-model-id` Secret to `01HXX_v3` + rolling restart.

**Then** Backends pick up new model_id from env on restart.
**And** Existing cache entries (with old model_id in key) eventually expire; new entries use v3.
**And** No request returns inconsistent / partial data (FGA evaluates against single pinned model per request).

#### Scenario P4.GWT-35: model v3 deployed → next List uses new model — old cached results expired in 5s
**UC**: UC-I02 + UC-Z03

**Given** Pre-v3 cache populated for usr_alice.

**When** Helm upgrade: openfga-model-id Secret rotated к v3.

**Then** Rolling restart: each backend pod restarts with new env value.
**And** Pre-restart cache discarded (in-memory).
**And** Post-restart cache empty → first call cache-miss → FGA call with v3 model_id → fresh evaluation.
**And** SLA preserved (cache repopulates within first few requests).

### 6.9 SQL filter pattern (3 scenarios)

#### Scenario P4.GWT-36: WHERE id = ANY($1::text[]) — SQL injection-safe
**UC**: UC-L02 negative + запрет #3

**Given** Maliciously-named id in FGA tuple (test fixture; cannot happen in production due to id-prefix validation, но defense-in-depth):
`vpc_network:'; DROP TABLE networks; --#viewer@user:usr_attacker`.

**When** `ListAllowedIDs(usr_attacker, vpc_network, viewer)` returns ids=["'; DROP TABLE networks; --"].
**And** `repo.ListByIDs(ctx, ids, ...)` SQL: `WHERE id = ANY($1::text[])` with `ids` as parameter (text array).

**Then** Postgres treats `$1` as opaque text-array — NO SQL execution from id contents.
**And** No matching row in `networks` table → empty result.
**And** Tables intact (no DROP).
**And** Defense verified via integration test `repo/.../*list_sqli_test.go`.

#### Scenario P4.GWT-37: empty ids array → no SQL query executed (short-circuit)
**UC**: UC-L05 optimization

**Given** `ListAllowedIDs` returned empty ids.

**When** Handler proceeds.

**Then** `if len(ids) == 0 { return EmptyResponse, nil }` — SQL `ListByIDs` NOT invoked.
**And** Zero DB queries observed in metric `pgx_query_total`.

#### Scenario P4.GWT-38: 10000 ids in array → query executes successfully
**UC**: UC-L06 (high-cardinality grant)

**Given** Cluster-admin returns 10000 vpc_network ids.

**When** `repo.ListByIDs(ctx, ids[10000], pageSize=100, pageToken="")`.

**Then** SQL `WHERE id = ANY($1::text[])` parameter accepts array of 10000 elements (Postgres parameter limit: 65535 parameters per query, ANY with array parameter counts as 1 — well within).
**And** Query plan uses `Index Scan` on PK + `Bitmap Heap Scan` if needed; executes ≤50ms even with 10000 IN-clause-equivalent.
**And** Pagination still correct (returns first 100 sorted, etc.).

### 6.10 Conditions in ListObjects (4 scenarios)

#### Scenario P4.GWT-39: mfa_fresh condition — user without recent step-up sees less; with step-up sees more
**UC**: UC-C03 + UC-L01

**Given** Tuple `vpc_network:net-secret#admin@user:usr_alice[mfa_fresh]` (Conditional binding с mfa_fresh).

**And** Other tuple `vpc_network:net-public#admin@user:usr_alice` (unconditional).

**Scenario A**: usr_alice без recent MFA — Principal `{ACR: "2", AMR: ["pwd"], MFAAt: <30m ago>}`.

**When** `ListAllowedIDs(P_A, vpc_network, admin)`.

**Then** Result = ["net-public"] (net-secret excluded by Conditions).

**Scenario B**: usr_alice c recent MFA — Principal `{ACR: "3", AMR: ["pwd","webauthn"], MFAAt: <5m ago>}`.

**When** `ListAllowedIDs(P_B, vpc_network, admin)`.

**Then** Result = ["net-public", "net-secret"].

#### Scenario P4.GWT-40: source_ip_in_range — outside CIDR → ID excluded from list
**UC**: UC-C08

**Given** Tuple `vpc_network:net-restricted#admin@user:usr_alice[source_ip_in_range]`.

**And** Allowed CIDRs = `["10.0.0.0/8"]`.

**Scenario A**: usr_alice's request from 192.168.1.1 (outside).

**When** `ListAllowedIDs` invoked; context includes `client_ip: 192.168.1.1`.

**Then** Condition false → net-restricted excluded.

**Scenario B**: from 10.0.0.5 (inside).

**When** `ListAllowedIDs` invoked.

**Then** Condition true → net-restricted included.

#### Scenario P4.GWT-41: JIT eligibility window — within ttl_seconds → included; after expiry → excluded
**UC**: UC-LC02 + UC-C-jit_window

**Given** Tuple `compute_instance:inst-prod#admin@user:usr_dev[jit_window]`.

**And** Condition `jit_window(current_time, activated_at, ttl_seconds)`.

**And** `activated_at = now() - 5min`, `ttl_seconds = 3600` (1h window).

**When** `ListAllowedIDs(usr_dev, compute_instance, admin)` (within window).

**Then** Condition true → inst-prod included.

**When** Same call 65min later.

**Then** Condition false → inst-prod excluded (cache stale-by-≤5s acceptable per design).

#### Scenario P4.GWT-42: break_glass_window — active emergency_admin returns all; after expiry → subset
**UC**: UC-LC04 + UC-C-break_glass_window

**Given** Tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_oncall[break_glass_window]`.

**And** `expires_at = now() + 30min`.

**When** `ListAllowedIDs(usr_oncall, vpc_network, viewer)` within 30min.

**Then** Cascade `vpc_network#viewer = ... or viewer from project ... or any_admin from cluster` includes emergency_admin → all networks returned.

**When** Same call 35min later.

**Then** Condition false → cascade breaks → only non-emergency bindings (if any) returned.
**And** Tied to UC-LC04 (Phase 7 break-glass workflow) — Phase 4 honors Conditions correctly DURING active window.

---

## 7. Definition of Done (Phase 4 closure)

### Functional
- [ ] `corelib/authz/listobjects.go` — full implementation (LRU + LISTEN-invalidate + FGA SDK adapter) merged; replaces Phase 3 skeleton.
- [ ] `corelib/authz/listusers.go` — separate ListUsers implementation for AccessBindingService.List by-resource path.
- [ ] All 4 services (kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-iam) переписали свои List-RPC handlers:
  - kacho-vpc: 9 handlers (network, subnet, security_group, route_table, address, gateway, private_endpoint, network_interface, **address_pool — Internal-only path preserved**).
  - kacho-compute: 4 handlers (instance, disk, image, snapshot).
  - kacho-loadbalancer: 2 handlers (network_load_balancer, target_group).
  - kacho-iam: 9 handlers (account, project, user, service_account, group, role, access_binding (special-case P4-D13), jit_eligibility, federation_trust_policy).
- [ ] All `repo.ListByIDs(ctx, ids, pageSize, pageToken)` methods implemented per resource.
- [ ] Empty grant returns 200 empty (not 403); zero PermissionDenied confusion.
- [ ] Cluster-admin / org-admin / account-admin / project-admin cascade works natively through FGA DSL v2 (no client-side short-circuit).
- [ ] Conditions evaluated at ListObjects (mfa_fresh, source_ip_in_range, jit_window, break_glass_window, etc.) — verified per GWT-39..GWT-42.
- [ ] FGA Consistency default = MINIMIZE_LATENCY; HIGHER_CONSISTENCY available via request flag.
- [ ] Pagination — internal MaxResults=10000; > → continuation_token follow-up internal call (transparent to handler).
- [ ] LISTEN-invalidate latency ≤1s p95 (k6 GWT-32 verifies).
- [ ] Fail-closed default; `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN` flag default OFF.

### Tests / CI
- [ ] **Integration tests** (testcontainers Postgres + openfga 1.6.x; per запрет #11):
  - `kacho-corelib/authz/listobjects_integration_test.go` — cache hit/miss, LISTEN race, Conditions, pagination > 10000.
  - `kacho-corelib/authz/listusers_integration_test.go` — ListUsers happy-path + Conditions.
  - `kacho-vpc/internal/repo/kacho/pg/<resource>_list_integration_test.go` — для каждого of 9 resources: ListByIDs happy + empty + sqli + 10k-array.
  - Same для kacho-compute (4 files), kacho-loadbalancer (2), kacho-iam (9).
- [ ] **Newman cases** (per запрет #11; 1+ happy + 1+ negative per RPC):
  - `kacho-test/tests/newman/cases/list_filter_vpc_networks.py` — covers UC-L01, L02, L05; GWT-07, GWT-10, GWT-13.
  - Same per-service variants for compute / loadbalancer / iam.
  - `kacho-test/tests/newman/cases/list_filter_listen_invalidate.py` — GWT-26..GWT-28.
  - `kacho-test/tests/newman/cases/list_filter_conditions.py` — GWT-39..GWT-42 (requires real DPoP JWT с varying ACR; uses Kratos+Hydra dev fixture from Phase 2).
- [ ] **k6 load test** `kacho-test/tests/k6/list_filter_kac127_phase4.js`:
  - Three scenarios: GWT-29 (smoke 100 RPS), GWT-30 (100-binding), GWT-31 (1000 RPS 30min sustained).
  - Asserts SLA inline (`check()` calls для p95 / p99 / cache_hit_ratio).
  - Run on dev стенд `e2c825` (k6 Job manifest in kacho-deploy `helm/umbrella/templates/k6-job-kac127-phase4.yaml`).
  - Result artifact: `kacho-test/tests/k6/results/KAC-127-phase4-list-filter.md` committed.
- [ ] CI green:
  - kacho-corelib: `go test ./authz/... -race`.
  - kacho-vpc / kacho-compute / kacho-loadbalancer / kacho-iam: `go test ./...`.
  - kacho-test: `bash tests/newman/run.sh && bash tests/k6/run-smoke.sh`.
  - kacho-deploy: `helm lint && helm template` + `promtool check rules`.

### Operational
- [ ] Helm values exposed: `authz.listobjects.cacheTtl` (default 5s), `authz.listobjects.maxResults` (default 10000), `authz.listobjects.failOpen` (default false), `authz.listobjects.consistency` (default MINIMIZE_LATENCY).
- [ ] Env injection: all 4 backend deployments get `KACHO_AUTHZ_LISTOBJECTS_*` env from Helm values.
- [ ] Grafana dashboard `kacho-authz-listobjects` — panels:
  - Cache hit ratio (per service, time series).
  - ListObjects duration p95/p99 (per service, per object_type).
  - FGA errors rate.
  - LISTEN connection status (per service, per pod replica).
  - LISTEN invalidate rate.
  - Cache size & evictions.
- [ ] Alertmanager rules `listobjects-rules.yaml`:
  - `ListObjectsP95High` — p95 ≥150ms 5min (warning).
  - `ListObjectsCacheHitRatioLow` — ≤60% 15min (info).
  - `ListenConnectionDown` — listen_connection_status=0 for 60s (critical).
  - `ListObjectsErrorsRateHigh` — error rate ≥1% 5min (critical).
  - `ListObjectsFailOpenActivated` — fail-open flag=true (critical, paging).
- [ ] Pre-prod smoke test in dev стенд: scale FGA cluster to 0, verify fail-closed behavior; restore; verify recovery.

### Security / Compliance
- [ ] Запрет #6 enforced: Internal admin RPC (InternalAddressPoolService.List, etc.) preserved as Internal-only; api-gateway public mux registration unchanged; integration test `kacho-api-gateway/internal/restmux/internal_only_routing_test.go` passes (cited in Phase 3 §6.16).
- [ ] Запрет #2 enforced: `grep -rn "yandex" kacho-corelib/authz/ kacho-vpc/internal/apps/kacho/api/.../list*.go ...` returns 0.
- [ ] Запрет #10: ListByIDs uses parameterized SQL `WHERE id = ANY($1::text[])`; no string-concat / no injection vectors (integration test GWT-36).
- [ ] No tenant-level information leak: empty grant returns 200 empty, не NotFound, не PermissionDenied (GWT-07; consistent with YC-style List semantics).
- [ ] Cross-tenant: Account A user requesting `NetworkService.List` does NOT see Account B networks (covered by ListObjects scope-cascade naturally; verified in GWT-29 fixture + newman case `list_filter_cross_tenant_deny.py`).
- [ ] Conditions correctly honored at list-time (mfa_fresh and friends) — GWT-39..GWT-42 in CI.
- [ ] Fail-open flag default OFF; enabling logs at WARN level + raises Critical alert.

### Documentation
- [ ] `obsidian/kacho/KAC/KAC-127.md` updated — Phase 4 checklist marked; PR links added per merge.
- [ ] New: `obsidian/kacho/architecture/list-filtering-pipeline.md` (1-3KB, ASCII pipeline + LRU + LISTEN-invalidate + Conditions overlay).
- [ ] New: `obsidian/kacho/edges/all-services-to-openfga-listobjects.md` (new runtime edge от vpc / compute / lb / iam → OpenFGA `/list-objects`).
- [ ] New (per service): `obsidian/kacho/rpc/vpc-list-handlers-phase4.md`, `obsidian/kacho/rpc/compute-list-handlers-phase4.md`, `obsidian/kacho/rpc/lb-list-handlers-phase4.md`, `obsidian/kacho/rpc/iam-list-handlers-phase4.md` — каждая 1-3KB, описывает: какие RPC, какие relation/type pairs, любые service-specific edges.
- [ ] Updated: `obsidian/kacho/architecture/authz-pipeline.md` (Phase 3 created) — добавить раздел "List-filtering layer (Phase 4)".
- [ ] `kacho-iam/README.md` мини-секция "List filtering pipeline" (Phase 4 reference).
- [ ] `kacho-iam/CLAUDE.md` — добавить раздел "ListObjects vs ListUsers — when to use which" (P4-D13 reference).
- [ ] `docs/specs/01-architecture-and-services.md` дополнено разделом "Phase 4 — ListObjects per List-RPC" (delta from Phase 3).

### Code quality
- [ ] All Go code passes `golangci-lint` (workspace default config).
- [ ] No `TODO` / `FIXME` / `XXX` comments in production code (`grep -r TODO kacho-corelib/authz/list* */internal/apps/kacho/api/.../list*.go` returns 0).
- [ ] Production-edition: no `wontfix` / `out-of-scope` / `deferred` items intra-Phase 4.
- [ ] `Tests-followup` strings not allowed in commit messages or PR descriptions (verified by PR reviewer per запрет #11).

---

## 8. Cross-repo PR-chain (порядок merge — топосорт)

| # | Репо | PR title | Что включает |
|---|---|---|---|
| **1** | `kacho-corelib` | `[KAC-127][Phase 4] authz/listobjects.go full impl + listusers + LISTEN-invalidate` | `authz/listobjects.go`, `listobjects_lru.go`, `listobjects_invalidate.go`, `listusers.go`, `principal_to_context.go`, `metrics.go` extension; unit + integration tests с testcontainers (openfga 1.6.x + Postgres 16); race-test for LISTEN reconnect |
| **2a** | `kacho-vpc` | `[KAC-127][Phase 4] List-RPC rewrite to ListAllowedIDs (9 handlers + ListByIDs repos)` | Per-resource list_usecase.go + list.go handler; repo.ListByIDs methods; integration tests per resource; newman case `list_filter_vpc_networks.py` etc. |
| **2b** | `kacho-compute` | `[KAC-127][Phase 4] List-RPC rewrite — 4 handlers` | Same pattern, 4 resources. |
| **2c** | `kacho-loadbalancer` | `[KAC-127][Phase 4] List-RPC rewrite — 2 handlers` | Same pattern, 2 resources. |
| **2d** | `kacho-iam` | `[KAC-127][Phase 4] List-RPC rewrite — 9 handlers; AccessBindingService.List special-case (ListUsers)` | All 9 handlers; AccessBindingService.List special-case logic; integration; newman. |
| **3** | `kacho-test` | `[KAC-127][Phase 4] k6 + newman list-filter tests` | k6 scenario file + results .md placeholder; newman cases для cross-service coverage; smoke run script. |
| **4** | `kacho-deploy` | `[KAC-127][Phase 4] Helm values + Grafana dashboard + Alerts` | values.yaml extension; dashboard JSON; alertmanager rules; per-chart env injection |
| **5** | `kacho-workspace` | `[KAC-127][Phase 4] vault: list-filtering pipeline + edges + per-service RPC docs` | Files в obsidian/kacho per §7 Documentation block. |

Branch policy: branch `KAC-127` в каждом из 7 затронутых репо; после merge — `gh pr merge --delete-branch`.

CI ref-pins (temporary, removed после merge):
- Steps 2a/2b/2c/2d: pin `kacho-corelib-ref: KAC-127`.
- Step 3: pin all of `kacho-corelib`/`kacho-vpc`/`kacho-compute`/`kacho-loadbalancer`/`kacho-iam` к `KAC-127`.
- Step 4: pin all to KAC-127 во время build.
- After all merged: revert refs к `main` в next batch-commit.

---

## 9. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| OpenFGA ListObjects latency spikes под cluster-admin scenario (15000 ids) | High | Pinned `MaxResults=10000`; loop with continuation_token bounded by max 5 round-trips (50000 ids cap); SLO target ≤250ms p99 verified in GWT-31; alert `ListObjectsP95High` |
| Cache stampede на cold start (1000 RPS hitting cold cache) | Medium | LRU cache supports concurrent access (no global lock — `sync.RWMutex` per shard, hashicorp/golang-lru/v2 internally); FGA can handle 1000 concurrent ListObjects (pre-Phase-4 load-test on dev cluster of 3 replicas) |
| LISTEN goroutine deadlock / blocked invalidation | Medium | Goroutine uses dedicated pgx.Conn (separate from main pool); `WaitForNotification` with context cancellation; reconnect loop logged + metric'd; integration test `listobjects_listen_race_test.go` exercises 1000 concurrent updates + reads |
| FGA Conditions evaluation overhead at scale | Low | Conditions are CEL with simple predicates (time comparison, ip range); FGA-engine evaluates fast (~1μs per Condition); k6 test confirms p95 within budget |
| Cache memory pressure — 1000s of users × 19 object types × per-pod | Medium | `MaxEntries=10000` per cache (configurable via Helm); LRU evicts oldest; eviction metric monitored; pod memory limits set (256Mi default) |
| LISTEN-NOTIFY connection-instability в multi-AZ Postgres cluster | Medium | Exponential backoff reconnect (200ms..5s); during reconnect window cache stale-by-≤5s (TTL bounded); alert `ListenConnectionDown ≥60s` |
| ListObjects API returns inconsistent results under MINIMIZE_LATENCY (eventually-consistent read replica) | Low | For read-your-own-writes (e.g., post-Upsert read), client passes `Consistency: CONSISTENCY_HIGHER` flag → ListObjects uses HIGHER_CONSISTENCY → strict read. Default MINIMIZE_LATENCY acceptable for periodic UI polling. |
| Scope-invalidate (Project.Move case GWT-18) — cache.InvalidateAll() too coarse | Low | Phase 4 accepts cache.InvalidateAll() as best-effort; Phase 5+ может optimize. Documented in vault `architecture/list-filtering-pipeline.md`. Project.Move is rare admin op (≤1/day per tenant typical). |
| Fail-open default off — operator forgets to flip during incident | Medium | Runbook in vault `obsidian/kacho/architecture/list-filtering-pipeline.md` § "Fail-open procedure"; on-call playbook update; tested via tabletop exercise (Phase 12). |
| Cross-pod cache divergence — pod A invalidates faster than pod B → User sees different list per pod | Low | LISTEN is broadcast — all pods receive NOTIFY simultaneously (Postgres semantics); divergence window ≤1s p99; UI is fault-tolerant (re-fetch on visible inconsistency). |

---

## 10. Out of Scope (явно отложено в Phases 5-13)

| Feature | Phase |
|---|---|
| Federation Exchange RPC (RFC 8693) + SA Hydra-clients + Federation Trust Policy validation | Phase 5 |
| SCIM 2.0 endpoint + SAML bridge + Organization-UI cascader | Phase 6 |
| JIT activation RPC + Break-glass workflow + 2-person approval + Access Reviews + GDPR erasure | Phase 7 (Phase 4 only HONORS `jit_window` / `break_glass_window` Conditions; workflows themselves — Phase 7) |
| CAEP drainer + SET signing + webhook delivery + retry/backoff for external IdP subscribers | Phase 8 (Phase 4 uses only LISTEN/NOTIFY from own outbox; Phase 8 adds external SET delivery) |
| Audit pipeline Kafka + ClickHouse + S3+Glacier + HSM Merkle | Phase 9 (Phase 4 inserts row into `audit_outbox` table; drainer / consumer — Phase 9 — forward-compat) |
| SPIFFE/SPIRE + Cilium service mesh | Phase 10 |
| Multi-region active-active + `api.kacho.cloud` TLS + Argo CD | Phase 11 |
| OWASP ASVS L3 + fuzzing + chaos + pentest + bug bounty | Phase 12 |
| Vault closeout (30+ files; final architecture) | Phase 13 |
| Optimized scope-invalidate replacing `cache.InvalidateAll()` for Project.Move (GWT-18) | Phase 5+ (Phase 4 accepts conservative invalidate) |
| Cross-cluster cache coherence (если многорегиональный deploy в Phase 11) | Phase 11 (Phase 4 — single-cluster) |
| Pre-fetch cache warming (hint API) | Phase 12+ (Phase 4 starts cold) |

В Phase 4 НЕ делаются никакие из вышеперечисленных. Если в ходе implementation возникнет вопрос "может, всё-таки сделать X сейчас" — ответ "нет", это нарушение production-edition discipline.

---

## 11. Open Questions Resolved (inline)

| Q | Resolution |
|---|---|
| **Q-list-vs-list-users**: ListObjects vs ListUsers — что использовать в AccessBindingService.List? | **P4-D13 resolved**. ListUsers — для "who has access to resource X" (filter by resource). ListObjects — для "what resources can X access" (filter by subject). AccessBindingService.List has two-direction filter — switch on `req.Filter` oneof. Filter by subject → ListObjects (call per-FGA-type loop, accept N round-trips up to 19 types). Filter by resource → ListUsers (single call, multi-relation aggregate). When **both** present → ListObjects (subject path is more selective in practice) + SQL `AND resource_id = $resource`. When **neither** → falls back к standard scope-Check (must have viewer@project:<...> to list within project). |
| **Q-pagination-semantics**: Pagination с MINIMIZE_LATENCY — sequential follow-up calls могут видеть разные snapshot'ы. | Page tokens encode `(fga_continuation_token, db_last_id)` базе64. Each follow-up call uses pinned continuation_token from FIRST call — FGA-side cursor пиннится. DB-side keyset uses last_id (immutable). Cache TTL extended до session-end if continuation_token open (LRU TTL doesn't expire mid-pagination — implementation detail in `listobjects.go`). After last page, cursor cleared. |
| **Q-cache-key-include-acr**: должен ли ACR / AMR быть частью cache key? | **Нет**. Cache key = (principal_id, principal_type, object_type, relation, scope, model_id). Conditions evaluated per request с context.now() / context.client_ip / context.mfa_at — FGA re-runs eval each Check (cache stores **result** of evaluation для given current Conditions snapshot). Edge case: if usr_alice's ACR changes (step-up) between two requests within 5s TTL, second request gets stale cached result. Acceptable — 5s window; verified by GWT-39 setup with cacheTtl=0. Future Phase 5+ может introduce key extension under feature-flag. |
| **Q-group-fanout**: Group member removal — should NOTIFY fanout к other members? | **No.** Removing usr_x from group doesn't affect other members' access. Only usr_x's cache needs invalidation. Documented in GWT-28. |
| **Q-scope-invalidate**: Project.Move — too coarse to enumerate all subjects who had cascade access; use scope-broad payload? | Yes, payload format `scope:account:<old_account_id>` triggers `cache.InvalidateAll()` per-pod. Conservative — better some over-invalidation than missing subject. Phase 5+ может optimize via materialized subject-graph. |
| **Q-paginate-keyed-by-fga-vs-db**: Pagination cursor — FGA или DB? | **Both**, hierarchically. Outer loop: FGA pagination (continuation_token from FGA, used only когда `len(ids) > MaxResults`). Inner loop: DB pagination (keyset on id). Page token combines both base64-encoded (`<fga_token>:<db_last_id>`). Most realistic case: FGA returns ≤10000 ids in single call → outer loop trivial; DB pagination used to slice. |
| **Q-audit-emit-required-or-best-effort**: должен ли List request fail если audit_outbox emit fails? | **Best-effort, NOT required**. audit_outbox emit (Internal RPC к kacho-iam) с 100ms deadline; failure → metric increment, NO request blocking. Rationale: list is read; missing audit row не critical (eventually-emitted via retry если success — но Phase 4 doesn't add retry; Phase 9 will). Trade-off acceptable. |
| **Q-empty-grant-vs-permission-denied**: empty list vs PermissionDenied — какая user-facing semantics? | **Empty list always**. P4-D4 — consistent с YC List behavior. Tenant doesn't learn that "resources exist somewhere but you can't see them" — defense-in-depth + UX-consistency. PermissionDenied только при absent auth (anonymous) — handled by api-gateway pre-handler interceptor, not corelib. |
| **Q-listusers-cache-separate**: Should ListUsers cache be separate LRU from ListObjects cache? | **Yes** — separate LRU. Different cache key shape (`(objectType, objectID, relation)` vs `(principalID, ...)`); mixing them causes false cache-misses. Same TTL=5s; same LISTEN-invalidate (NOTIFY 'subject_id' invalidates **users-cache** entries where subject is listed in cached `users[]` — implementation detail in `listobjects_invalidate.go`). |
| **Q-fail-open-mode**: explicit list of operations that may fail-open vs always fail-closed | Fail-open available ONLY for **reads** (List, Get) when `KACHO_AUTHZ_LISTOBJECTS_FAIL_OPEN=true`. Mutations (Phase 1-3 Create/Update/Delete) **always fail-closed** — flag не influence их. Documented в `obsidian/kacho/architecture/list-filtering-pipeline.md` § Fail-modes. |
| **Q-conditions-context-current-time-precision**: должен ли `current_time` округляться до секунды? | Yes, **truncate to second** (YC-style timestamp; design §«Architecture» frozen). FGA Conditions receive `current_time` truncated. Avoids cache stampede with sub-second variation. |
| **Q-which-relation-by-default**: `List` без explicit relation — какая дефолтная (viewer / editor / admin)? | **viewer** (lowest privilege). DSL v2 has `viewer = ... or editor` cascade — viewer-grants include editor-grants implicitly. List should show maximum visible set → viewer. Explicit per-RPC: most List handlers hardcode `"viewer"`; AccessBindingService.List iterates [admin, editor, viewer] when by-resource. |

---

## 12. Связь с регламентом (повтор для reviewer convenience)

- **Запрет #1**: gate is this document → APPROVED → код starts.
- **Запрет #2**: no "yandex" — verified `grep -rn yandex kacho-corelib/authz/list* */internal/apps/kacho/api/.../list*.go = 0`.
- **Запрет #3**: openfga-go-sdk — gRPC client (не ORM); pgx + sqlc — handwritten (не ORM); hashicorp/golang-lru/v2 — go-native LRU library (не ORM-cache).
- **Запрет #4**: ListObjects + ListUsers — read-only; никаких cross-service cascades.
- **Запрет #5**: zero new migrations in Phase 4 corelib/vpc/compute/lb; `audit_outbox` table — new Phase 4 migration в kacho-iam (`0016_kac127_phase4_audit_outbox.sql`); правка Phase 1 — нет.
- **Запрет #6**: Internal admin RPC (InternalAddressPoolService.List, etc.) — Internal-only enforced via Phase 3 baseline routing; Phase 4 doesn't expose them.
- **Запрет #7**: no broker; Postgres LISTEN/NOTIFY + in-process LRU.
- **Запрет #8**: DB-per-service preserved; ListByIDs SQL inside one DB per service; cross-service refs unchanged.
- **Запрет #9**: List = read; remains sync. No new mutations Phase 4.
- **Запрет #10**: ListByIDs uses `WHERE id = ANY($1)` (PK-equality, not FK-check); software-side checks обнаружены — отсутствуют.
- **Запрет #11**: integration + newman + k6 в каждом PR; never "tests-followup".

---

## 13. Phase 4 changelog

- **2026-05-19** — DRAFT v1 создан (`acceptance-author`). Decision Log P4-D1..P4-D13 закрыт inline. 42 GWT scenarios (target ≥40 met — exceeded by 2). Out-of-scope = Phases 5-13 (no intra-Phase deferred items). User feedback round 2 (no backward-compat KAC-108 single-Check) inline-resolved в P4-D1.

---

**Конец документа.** APPROVED gate → `acceptance-reviewer`.
