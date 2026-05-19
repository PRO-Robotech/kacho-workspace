# Sub-phase 3.7 — IAM JIT/PIM + Break-glass + Access Reviews + GDPR Erasure (KAC-127 / YT KAC-123) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` — Decision Log §1, PIM/JIT + Break-glass §11, GDPR erasure pipeline §9.3, Audit schema §9.1, Compliance map §9.4, OpenFGA model v2 §4 (`emergency_admin` relation + `break_glass_window` / `jit_window` Conditions), Threat model §14 (insider rogue admin, stale grants after employee leaves), SLOs §13.6 (revoke propagation ≤ 10s p99), DoD §17.
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 7 (tasks 7.1-7.8).
> **Phase position**: §16 design doc "Migration plan", **Phase 7 of 13**.
> **Predecessors (must be merged before code begin)**:
> - Phase 1 — Foundation (`sub-phase-3.1-iam-foundation-acceptance.md`): migrations `0011..0014` создают таблицы `cluster_break_glass_grants`, `access_bindings_jit_eligibility`, `access_reviews`, `access_review_items`, `gdpr_erasure_requests`, `access_binding_conditions`, `audit_outbox`, `caep_outbox`, расширения `users` (status enum + erasure-aware columns), `cluster_kacho_root` singleton.
> - Phase 2 — AuthN core (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): step-up flow `acr=2 → acr=3` через re-Passkey, JWT `amr`/`acr`/`auth_time`/`kacho_mfa_at` claims, recovery flow.
> - Phase 3 — AuthZ core (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): Conditions `jit_window` / `break_glass_window` уже инициализированы в `access_binding_conditions`; OpenFGA model v2 содержит `cluster.emergency_admin` relation; OPA Rego guardrail "break-glass max 2h" deploy'нут.
> - Phase 6 — Enterprise SSO (`sub-phase-3.6-iam-scim-saml-organization-acceptance.md`): SCIM lifecycle → нужен для cascade-revoke on user disable scenarios, а также `Organization` resource (для cross-account reviewer assignment).
> **Target repos / merge order (топологическая сортировка graf'а)**:
> 1. `PRO-Robotech/kacho-proto` — `kacho.iam.v1.JITEligibilityService` (public CRUD), `AccessBindingService.ActivateJIT` (public action-method), `kacho.iam.v1.InternalBreakGlassService` (internal-only — admin/SRE workflow), `kacho.iam.v1.AccessReviewService` (public — reviewer self-service), `kacho.iam.v1.GdprErasureService` (public), `kacho.iam.notify.v1` *(none — notify уходит из kacho-corelib без proto)*.
> 2. `PRO-Robotech/kacho-corelib` — `corelib/notify/` package: `pagerduty.go` (Events API v2), `slack.go` (webhook + Block Kit), `email.go` (SMTP / SES adapter), `notify.go` (interface + retry + dedup), `notify_testing.go` (in-memory recorder для integration-tests). Опционально `corelib/dedup/` (sliding-window dedup для incident_id).
> 3. `PRO-Robotech/kacho-iam` — `internal/apps/kacho/api/access_binding/activate_jit.go`, `internal/apps/kacho/api/jit_eligibility/{create,update,delete,list,get}.go`, `internal/apps/kacho/api/cluster/{request_break_glass,approve_break_glass,deny_break_glass,list_pending,list_active}.go`, `internal/apps/kacho/api/access_review/{list,get,confirm,revoke,list_items}.go`, `internal/apps/kacho/api/gdpr/{request_erasure,cancel_erasure,list,get}.go`, `internal/apps/kacho/jobs/{jit_expirer,break_glass_expirer,access_review_scheduler,access_review_auto_revoke,gdpr_erasure_processor,break_glass_review_escalator}.go`, `internal/domain/{jit_eligibility,break_glass_grant,access_review,gdpr_erasure_request}.go` (self-validating domain types), `migrations/0021_kac127_phase7_indexes.sql` (если требуются доп. indexes для job-scan производительности).
> 4. `PRO-Robotech/kacho-api-gateway` — `internal/restmux/mux.go` регистрирует **public** `JITEligibilityService` / `AccessBindingService.ActivateJIT` / `AccessReviewService` / `GdprErasureService` на public mux, **Internal**-сервис `InternalBreakGlassService` регистрируется на `internalAddr` блок (не на public). Plus rate-limits per endpoint.
> 5. `PRO-Robotech/kacho-deploy` — secrets: `pagerduty-routing-key`, `slack-webhook-security`, `smtp-credentials` (или `aws-ses-credentials`) → Sealed Secrets / External Secrets Operator; helm-values: `notify.{pagerduty,slack,email}.enabled`, severity mapping per event type; CronJob templates для Phase 7 jobs.
> 6. `PRO-Robotech/kacho-ui` — `pages/iam/jit/{eligibility-list,activate-modal}.tsx`, `pages/iam/break-glass/{request-form,approver-page,list-active}.tsx`, `pages/iam/access-reviews/{list,detail,review-item}.tsx`, `pages/iam/settings/gdpr/{request-erasure,cancel,status}.tsx`.
> 7. `PRO-Robotech/kacho-workspace` — vault: `obsidian/kacho/KAC/KAC-127.md` (Phase 7 update), `obsidian/kacho/resources/iam-jit-eligibility.md` (новый), `obsidian/kacho/resources/iam-break-glass-grant.md` (обновить — уже есть `iam-cluster-admin-grant.md`), `obsidian/kacho/resources/iam-access-review.md` (обновить — уже существует), `obsidian/kacho/resources/iam-gdpr-erasure-request.md` (новый), `obsidian/kacho/rpc/iam-jit-eligibility-service.md` (новый), `obsidian/kacho/rpc/iam-internal-break-glass-service.md` (новый, internal-only-помечен), `obsidian/kacho/rpc/iam-access-review-service.md` (новый), `obsidian/kacho/rpc/iam-gdpr-erasure-service.md` (новый), `obsidian/kacho/packages/corelib-notify.md` (новый), `obsidian/kacho/edges/iam-to-pagerduty.md` (новый), `obsidian/kacho/edges/iam-to-slack.md` (новый), `obsidian/kacho/edges/iam-to-smtp.md` (новый).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 7 — **седьмая код-генерирующая Phase** под KAC-127 и **последняя «privileged-access governance» phase** перед CAEP push pipeline (Phase 8). К моменту начала Phase 7 уже есть:

- **DB-схема Phase 1**: таблицы `cluster_break_glass_grants` (status enum, expires_at CHECK ≤ 2h, 2 approver columns), `access_bindings_jit_eligibility` (user/role/resource scope + max_duration + optional approver + enabled/expires_at), `access_reviews` + `access_review_items` (quarterly recertification), `gdpr_erasure_requests` (status: cool_off / in_progress / completed / cancelled, cool_off_until TIMESTAMPTZ, requested_by + requested_for, optional override approver), `users.status` extended с `BLOCKED` для GDPR pseudonymization.
- **AuthN Phase 2**: step-up `acr=3` через re-Passkey работает; ID-token содержит свежие `amr` claims; recovery flow позволяет вернуть user если он потерял Passkey **до** запроса erasure.
- **AuthZ Phase 3**: Conditions `jit_window(current_time, activated_at, ttl_seconds)` и `break_glass_window(current_time, expires_at)` зарегистрированы в `access_binding_conditions`; OpenFGA model v2 содержит `type cluster relations { ...; define emergency_admin: [user with break_glass_window]; define any_admin: system_admin or emergency_admin; ... }`; OPA Rego guardrail `cluster.break_glass.grant.duration_seconds > 7200 → deny` уже работает.
- **Phase 6 SCIM**: user-disabled-by-IdP события приходят в kacho-iam через SCIM lifecycle hook; `Organization` resource с членами exists для cross-account reviewer assignment.

Phase 7 закладывает **operational governance plane** во весь рост:

1. **JIT (Just-In-Time) eligibility** — отдельная таблица `access_bindings_jit_eligibility` со списком «кто имеет право самостоятельно активировать role X на resource Y на duration не более D». Admin создаёт eligibility row (вне runtime-grant), пользователь нажимает «Activate Admin» в UI → step-up acr=3 → INSERT `access_bindings` со статусом ACTIVE + condition `jit_window(activated_at=now, ttl_seconds=requested)`. Опционально eligibility row содержит `approval_required=true` + `approver_user_id`, тогда вместо immediate-grant создаётся pending request, approver получает Slack/email notification и `/approve`-endpoint.

2. **ActivateJIT step-up** — мутирующий публичный action-method `AccessBindingService.ActivateJIT` обязан иметь свежий step-up token (`acr=3`, `kacho_mfa_at < 5min`). Без step-up → `Unauthenticated` 401 с `error_detail.required_acr=3`. UI ловит и редиректит на re-Passkey-flow.

3. **JIT auto-expire** — никакая отдельная revoke-логика не требуется: `jit_window` Condition в FGA tuple после passing `ttl_seconds` начинает возвращать `denied=true`, что эффективно делает binding неработающим. Дополнительно background job `jit_expirer` (каждые 60s) переводит status binding'а в `EXPIRED` и эмитит audit-event `iam.jit.expired` + outbox CAEP push token-claims-change.

4. **Break-glass workflow** — для emergencies, когда нет существующего eligibility row или нужен **cluster-level admin** (root cluster). **Internal-only** RPC `InternalBreakGlassService.Request{Approve,Deny}BreakGlass` (registered НА internal port, недоступен с external TLS endpoint per запрет #6). Жёсткий 2-person-approve workflow (separation of duties), max-duration 2 часа (OPA-enforced + DB CHECK), auto-expire через `break_glass_window` Condition + background job. **Каждый запрос** триггерит PagerDuty incident P1, Slack `#security-alerts`, email `security@kacho.cloud`. Mandatory post-incident review tracking issue создаётся автоматически — если через 7 дней не resolved, второй Slack escalation ping.

5. **Access Reviews (quarterly recertification)** — cron `access_review_scheduler` запускается 4 раза в год (Q1: 1 января, Q2: 1 апреля, Q3: 1 июля, Q4: 1 октября; configurable). Для каждого активного Account создаётся `access_reviews` row + `access_review_items` (по одному на каждый non-expired access binding на ресурсы account'а), reviewer = account-admin (или Organization-level SCIM-managed group если account → org). Reviewer заходит в UI → видит свой list-pending → confirm (binding остаётся) / revoke (binding revoked + CAEP push). Items без ответа 14 дней → `access_review_auto_revoke` job переводит binding в REVOKED + audit emit + CAEP. Per-tenant флаг `auto_revoke_unanswered` (default true) позволяет отключить (для tenant'ов с custom-process'ом).

6. **GDPR erasure pipeline (Art. 17)** — user через UI или API ⟶ `GdprErasureService.RequestErasure` с step-up acr=3 → INSERT `gdpr_erasure_requests` со status=`cool_off`, `cool_off_until = now() + interval '30 days'`. В течение 30 дней user может `CancelErasure` (status=`cancelled`). Daily cron `gdpr_erasure_processor` processes `cool_off`-expired rows: переводит User.Status=BLOCKED → revoke all access_bindings → delete ReBAC tuples → SCIM-webhook downstream → pseudonymize `users.email/display_name` → `gdpr-erased-<sha256-of-uid>` → hard-delete Kratos identity. **Compliance over erasure**: audit-rows о действиях user'а сохраняются 7 лет (GDPR Art. 17(3)(b) — legal claims defense). **Account-owner edge case**: если user owns Account где есть другие active members → erasure blocked с явной ошибкой "must transfer Account ownership before erasure", manual escalation; admin transfers ownership → retry.

7. **Notifications package** — `corelib/notify/` с тремя adapter'ами (PagerDuty Events API v2, Slack incoming-webhook, SMTP/SES email). Все adapter'ы реализуют `Notifier interface { Send(ctx, event) error }`. **Dedup** per `event.IncidentID` window 5 min (in-memory LRU) предотвращает duplicate-page'ы при retry'ях. **Failover semantics**: notification send failure — audit-log как `notify.delivery_failed`, **НЕ** блокирует main flow (break-glass grant сам по себе остаётся valid; security team replies on audit log как fallback).

8. **UI surfaces** — JIT activate-modal (current user видит свои eligibilities, выбирает duration, кликает activate, проходит re-Passkey); break-glass-approver page (для cluster-admin / SRE-manager view of pending grants + 1-click approve/deny с audit-text-input); access-reviews-list (reviewer'ы видят свои pending items, batch confirm/revoke); GDPR-settings-page (current user requests erasure / sees countdown / cancels).

**Phase 7 НЕ включает** (это Phases 8-13 одного эпика — НЕ «deferred»):

- CAEP push pipeline (subscriber registry, drainer, SET signing, webhook delivery с retry) — **Phase 8**. Phase 7 кладёт rows в `caep_outbox` table (Phase 1 schema), но **drainer** их ещё не consume'ит — это Phase 8. Note: Phase 7 интеграционно тестит «row appeared in caep_outbox с правильным event-type», а не «webhook delivered».
- Full audit pipeline (Kafka + ClickHouse + S3 + HSM signing + SIEM forwarders) — **Phase 9**. Phase 7 пишет audit rows в `audit_outbox` table; **drainer + Kafka producer** — Phase 9.
- SPIFFE/SPIRE in-cluster Workload Identity — **Phase 10**.
- Multi-region active-active deploy + Argo CD + observability stack — **Phase 11**.
- OWASP ASVS L3 + chaos + pentest — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13**.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / proto / Rego / комментариях / env-names / Slack-сообщениях / email-templates / vault-записях — не упоминается; YC-стилистика error-text сохраняется (`"<Resource> %s not found"`, `"<field> is immutable"`, `"Illegal argument <thing>"`) |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx для всех новых таблиц-доступов; `corelib/notify` использует stdlib `net/http`, `net/smtp`, без ORM |
| **Запрет #4** — НЕ каскад через границу сервиса | GDPR erasure pipeline **внутри kacho-iam** — same-DB cascade (FK ON DELETE CASCADE между `users` → `access_bindings_jit_eligibility`); cross-service revoke (kacho-vpc / kacho-compute ресурсы, принадлежавшие user'у) — НЕ cascade, идёт через **emit события** в `caep_outbox` + downstream SCIM webhook (audit-level), без hard-delete cross-DB; resource cleanup в чужих сервисах — manual transfer / по-job'у каждого сервиса отдельно (Phase 11 для prod-clean) |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 1 миграции (`0011..0014`) уже создали все таблицы; в Phase 7 может появиться **новая** миграция `0021_kac127_phase7_indexes.sql` (доп. indexes для job-scan производительности) — НЕ изменение Phase 1 |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `InternalBreakGlassService` регистрируется **только** на internal mux api-gateway (`internalAddr` block), доступен с cluster-internal listener (admin-UI port-forward, SRE-tooling); external TLS `api.kacho.local:443` его НЕ видит. **Public** RPC (JIT eligibility CRUD, ActivateJIT, AccessReview, GdprErasure) — на public mux, **с** acr=3 step-up gate где применимо |
| **Запрет #7** — НЕ broker, пока in-process справляется | Notifications retry — in-process LRU + bounded retry queue; нет Kafka/NATS; PagerDuty/Slack HTTP timeouts 5s + 3 retries с exponential backoff; CAEP outbox — Postgres table (Phase 8 drainer его consume'ит) |
| **Запрет #8** — DB-per-service | все Phase 7 таблицы — внутри `kacho_iam` schema; cross-service refs (revoke binding на vpc-network → real vpc-network resource в kacho-vpc) — через CAEP outbox + downstream subscriber, БЕЗ cross-DB writes |
| **Запрет #9** — async-only мутации | `ActivateJIT` → `Operation` (async); `RequestBreakGlass` / `ApproveBreakGlass` / `DenyBreakGlass` → `Operation`; `Confirm`/`Revoke` access review item → `Operation`; `RequestErasure` / `CancelErasure` → `Operation`; JIT-eligibility CRUD — это конфиг-resource (не мутация compute-style ресурса), но всё равно следует pattern (создание → Operation возвращается, sync-read остаётся sync `Get` / `List`) |
| **Запрет #10** — within-service refs на DB-уровне | **критично для Phase 7**: break-glass state machine `AWAITING_APPROVAL_A → AWAITING_APPROVAL_B → ACTIVE/DENIED/EXPIRED` reализуется **атомарным conditional UPDATE с CAS-условием** на `status` + RETURNING кардинальность (см. §6.7, §6.8); JIT activation duplicate-detection через partial UNIQUE `WHERE status='ACTIVE' AND user_id=X AND role_id=R AND resource_id=ID`; access-review-item state — atomic UPDATE с CAS на `decision IS NULL`; **никакого** software-check-then-act; **критично**: `cluster_break_glass_grants.expires_at` имеет DB-level `CHECK (expires_at <= requested_at + interval '2 hours')` параллельно с OPA guardrail (defense-in-depth) |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 7 содержит: kacho-proto — buf-lint + buf-breaking; corelib/notify — unit-tests с recorded-HTTP backend + integration smoke; kacho-iam — integration-tests testcontainer Postgres (state-machine race-tests для break-glass; jit-duplicate race; access-review concurrent-confirm race; gdpr cool-off concurrent-cancel race) + Rego-unit-tests `opa test policies/` (если расширяются rules); newman cases (см. §7 DoD) — happy + negative для каждого RPC |

---

## 2. Глоссарий / доменная модель Phase 7 (нормативно)

### 2.1 Сущности, **созданные / расширенные** в Phase 7

- **JITEligibility** — конфиг-ресурс «кто имеет право активировать role X на resource Y на duration ≤ D». Поля (от Phase 1 schema):
  - `id TEXT PRIMARY KEY` (prefix `jeg_`),
  - `user_id TEXT REFERENCES users(id) ON DELETE CASCADE NOT NULL`,
  - `role_id TEXT REFERENCES roles(id) ON DELETE RESTRICT NOT NULL`,
  - `resource_type TEXT NOT NULL` (e.g. `vpc_network`, `compute_instance`, `project`, `account`),
  - `resource_id TEXT NOT NULL`,
  - `max_duration INTERVAL NOT NULL DEFAULT '1 hour'` (CHECK `max_duration <= interval '8 hours'`),
  - `approver_user_id TEXT REFERENCES users(id)` (nullable, set если `approval_required=true`),
  - `approval_required BOOL NOT NULL DEFAULT false`,
  - `enabled BOOL NOT NULL DEFAULT true`,
  - `expires_at TIMESTAMPTZ` (nullable — eligibility row may expire itself),
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `created_by TEXT REFERENCES users(id) NOT NULL`.
  - **Lifecycle**: ENABLED → DISABLED (toggling `enabled`); admin-only-mutable (`access_bindings.upsert` permission на parent resource).
  - **Mutable fields**: `enabled`, `expires_at`, `approval_required`, `approver_user_id`, `max_duration`. **Immutable**: `user_id`, `role_id`, `resource_type`, `resource_id`, `created_at`, `created_by` (force delete + recreate).
  - **DB-уровень инварианты**: `CHECK (max_duration > interval '0')`, `CHECK (max_duration <= interval '8 hours')`, partial unique `(user_id, role_id, resource_type, resource_id) WHERE enabled = true` (одна eligibility row per scope в active state).

- **BreakGlassGrant** — emergency cluster-admin grant. Поля (от Phase 1 schema):
  - `id TEXT PRIMARY KEY` (prefix `bgg_`),
  - `subject_user_id TEXT REFERENCES users(id) ON DELETE RESTRICT NOT NULL`,
  - `status TEXT NOT NULL CHECK (status IN ('AWAITING_APPROVAL_A','AWAITING_APPROVAL_B','ACTIVE','EXPIRED','DENIED','REVOKED'))`,
  - `incident_id TEXT NOT NULL` (free-form pointer на PagerDuty/JIRA inc; mandatory not empty CHECK `incident_id <> ''`),
  - `rationale TEXT NOT NULL CHECK (length(rationale) >= 20)`,
  - `requested_by_user_id TEXT REFERENCES users(id) NOT NULL`, *(separate from subject — кто-то от имени SRE)*
  - `requested_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `approved_by_a TEXT REFERENCES users(id)` (nullable until approved),
  - `approved_at_a TIMESTAMPTZ`,
  - `approved_by_b TEXT REFERENCES users(id)` (nullable until approved),
  - `approved_at_b TIMESTAMPTZ`,
  - `denied_by TEXT REFERENCES users(id)` (nullable; populated если any approver rejected),
  - `denied_at TIMESTAMPTZ`,
  - `denial_reason TEXT`,
  - `expires_at TIMESTAMPTZ NOT NULL CHECK (expires_at <= requested_at + interval '2 hours')`,
  - `revoked_at TIMESTAMPTZ`,
  - `post_incident_review_issue_url TEXT` (URL на YouTrack issue / GitHub issue),
  - `post_incident_review_completed_at TIMESTAMPTZ` (set когда review-issue closed).
  - **State machine** (atomic CAS transitions):
    - `AWAITING_APPROVAL_A` → `AWAITING_APPROVAL_B` (via approve-A handler; CAS condition `status='AWAITING_APPROVAL_A' AND approved_by_a IS NULL`).
    - `AWAITING_APPROVAL_A` → `DENIED` (via deny handler at A stage).
    - `AWAITING_APPROVAL_B` → `ACTIVE` (via approve-B; CAS condition `status='AWAITING_APPROVAL_B' AND approved_by_b IS NULL`, дополнительно DB-CHECK `approved_by_a != approved_by_b` — separation of duties).
    - `AWAITING_APPROVAL_B` → `DENIED` (via deny handler at B stage).
    - `ACTIVE` → `EXPIRED` (via job `break_glass_expirer` when `now() > expires_at`).
    - `ACTIVE` → `REVOKED` (via manual revoke by cluster-admin; emergency cancel).
  - **DB-уровень инварианты**:
    - `CHECK (expires_at <= requested_at + interval '2 hours')` — hard cap;
    - `CHECK ((approved_by_a IS NULL) = (approved_at_a IS NULL))` — coherent timestamps;
    - `CHECK ((approved_by_b IS NULL) = (approved_at_b IS NULL))`;
    - `CHECK (approved_by_a IS NULL OR approved_by_b IS NULL OR approved_by_a <> approved_by_b)` — 2-person rule на DB-уровне;
    - `CHECK (approved_by_a IS NULL OR approved_by_a <> subject_user_id)` — no self-approve A;
    - `CHECK (approved_by_b IS NULL OR approved_by_b <> subject_user_id)` — no self-approve B;
    - `CHECK (approved_by_a IS NULL OR approved_by_a <> requested_by_user_id)` — requester ≠ approver A;
    - `CHECK (approved_by_b IS NULL OR approved_by_b <> requested_by_user_id)` — requester ≠ approver B.
  - Side-effect on `ACTIVE` transition: INSERT `fga_outbox` (`cluster:cluster_kacho_root#emergency_admin@user:<subject_id>` Conditional с `break_glass_window(expires_at=$expires)`), INSERT `caep_outbox` (token-claims-change для CAEP push), INSERT `audit_outbox` (`iam.break_glass.activated`), trigger notification fan-out (PagerDuty `resolve` для request-incident → новый `trigger` для grant-incident; Slack message; email).

- **AccessReview** — quarterly recertification campaign. Поля (от Phase 1):
  - `id TEXT PRIMARY KEY` (prefix `arv_`),
  - `account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE NOT NULL`,
  - `quarter TEXT NOT NULL` (формат `YYYY-Q[1-4]`),
  - `scheduled_at TIMESTAMPTZ NOT NULL`,
  - `due_at TIMESTAMPTZ NOT NULL` (default `scheduled_at + interval '14 days'`),
  - `completed_at TIMESTAMPTZ`,
  - `status TEXT NOT NULL CHECK (status IN ('SCHEDULED','IN_PROGRESS','COMPLETED','OVERDUE'))`,
  - `reviewer_user_id TEXT REFERENCES users(id) NOT NULL`,
  - `auto_revoke_unanswered BOOL NOT NULL DEFAULT true`,
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - UNIQUE `(account_id, quarter)`.

- **AccessReviewItem** — single binding в campaign:
  - `id TEXT PRIMARY KEY` (prefix `arvi_`),
  - `review_id TEXT REFERENCES access_reviews(id) ON DELETE CASCADE NOT NULL`,
  - `access_binding_id TEXT REFERENCES access_bindings(id) ON DELETE CASCADE NOT NULL`,
  - `decision TEXT CHECK (decision IS NULL OR decision IN ('keep','revoke','expired_auto'))` (NULL = pending),
  - `decision_at TIMESTAMPTZ`,
  - `decision_by_user_id TEXT REFERENCES users(id)`,
  - `comment TEXT`,
  - UNIQUE `(review_id, access_binding_id)`.

- **GdprErasureRequest** — Art. 17 erasure request. Поля (от Phase 1):
  - `id TEXT PRIMARY KEY` (prefix `gdpr_`),
  - `subject_user_id TEXT REFERENCES users(id) ON DELETE RESTRICT NOT NULL` (user being erased; RESTRICT — нельзя delete user пока есть active request),
  - `requested_by_user_id TEXT REFERENCES users(id) NOT NULL` (обычно тот же что subject; admin-initiated rare),
  - `requested_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `cool_off_until TIMESTAMPTZ NOT NULL` (default `now() + interval '30 days'`),
  - `status TEXT NOT NULL CHECK (status IN ('cool_off','in_progress','completed','cancelled','blocked'))`,
  - `cancellation_at TIMESTAMPTZ`,
  - `cancelled_by_user_id TEXT REFERENCES users(id)`,
  - `completed_at TIMESTAMPTZ`,
  - `block_reason TEXT` (populated если status=blocked, e.g. "owns Account acc_xxx с N team members"),
  - `pseudonymized_email TEXT` (post-erasure value: `gdpr-erased-<sha256-hex-of-subject-user-id>`),
  - `audit_retention_until TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 years'`.
  - Partial UNIQUE `(subject_user_id) WHERE status IN ('cool_off','in_progress')` — одна активная request per user.

### 2.2 Сущности, **используемые** в Phase 7 (read-only от Phase 1-6)

- **User** — `users` table; в Phase 7 пишется только `status` column (BLOCKED для GDPR), pseudonymization rewrites `email` / `display_name`. Phase 7 НЕ создаёт users (это Phase 1 + Phase 6 SCIM).
- **AccessBinding** — `access_bindings` table; Phase 7 INSERTs новые bindings (для JIT activation, для break-glass via fga_outbox path) и UPDATEs status=REVOKED (access review revoke, GDPR cascade). НЕ изменяет схему.
- **AccessBindingCondition** — read-only; Phase 7 ссылается на seeded conditions `jit_window` (id e.g. `cnd_jit_window`) и `break_glass_window` (id e.g. `cnd_break_glass_window`); их параметры (`activated_at`, `ttl_seconds`, `expires_at`) задаются per-binding-instance в access_binding row.
- **Cluster** — singleton `cluster_kacho_root`; Phase 7 пишет FGA tuples `cluster:cluster_kacho_root#emergency_admin@user:<id>` при break-glass ACTIVE transition.
- **Role** — Phase 7 ссылается на existing roles; JIT eligibility отсылает на любой role, break-glass — традиционно `cluster_admin` (но не hardcoded — `subject_user_id` получает `emergency_admin` cluster-relation).
- **AuditOutbox / CaepOutbox** — Phase 7 INSERTs события; drainer'ы — Phase 8 / Phase 9.

### 2.3 Сущности, **создаваемые** в Phase 7 (vault: `obsidian/kacho/resources/`)

- `iam-jit-eligibility.md` — новая запись;
- `iam-break-glass-grant.md` — расширить или (если файл уже создан под `iam-cluster-admin-grant.md`) — добавить раздел "Break-Glass" / разделить на 2 файла (cluster_admin_grants — permanent; cluster_break_glass_grants — temp);
- `iam-access-review.md` — уже существует, расширить под Phase 7 workflow + Items;
- `iam-gdpr-erasure-request.md` — новая запись.

---

## 3. Decision Log (final per phase — no deferred)

Решения номеруются `P7-D<N>`. Каждое — **финальное** для Phase 7 production-edition (round 2: «no strict backward-compat»). Каждое решение имеет: **Контекст** → **Альтернативы** → **Выбор** → **Обоснование**.

### P7-D1: JIT eligibility — отдельная таблица, не флаг на access_bindings

**Контекст**: «pre-authorized self-activation right» vs «active grant» — концептуально разные. Один user может иметь право активировать `vpc_admin` на 10 разных networks, но никогда не активировать (если не нужно).

**Альтернативы**:
- (a) Колонка `jit_eligible BOOL` + `jit_max_duration INTERVAL` на `access_bindings` — eligibility и grant в одной строке.
- (b) Отдельная таблица `access_bindings_jit_eligibility` (Phase 1 schema).

**Выбор**: (b) — отдельная таблица.

**Обоснование**: eligibility не имеет binding lifecycle (нет status, нет expires_at для self, нет condition_id); это просто конфиг. Сливать с `access_bindings` создаст misleading rows со `status=ACTIVE` но без эффективного grant'а. Кроме того, eligibility может иметь parameters (`approval_required`, `approver_user_id`, `max_duration`), которых на access_bindings нет. Отдельная таблица — клин.

### P7-D2: ActivateJIT требует step-up acr=3

**Контекст**: JIT activation — это privilege escalation event (user получает elevated permissions). Эквивалентен по чувствительности тому, как admin грантит роль другому user'у — оба требуют step-up.

**Альтернативы**:
- (a) Только session-acr=2 (Passkey login) достаточно.
- (b) Требовать step-up acr=3 (re-Passkey ≤ 5 min ago) на activate.

**Выбор**: (b).

**Обоснование**: defense-in-depth против session hijack — если злоумышленник украл DPoP-token, без свежей Passkey-подписи он не сможет escalate в admin. Step-up уже работает Phase 2 (acr=2 → acr=3 через recovery flow / WebAuthn assertion). UI ловит 401 `required_acr=3` и редиректит. SLO: re-Passkey добавляет ≤ 3s к activate latency — acceptable.

### P7-D3: Approval workflow — optional flag per eligibility row

**Контекст**: некоторые eligibilities — sensitive (production project; financial); другие — routine (dev project). Force-approval для всех — слишком много friction для dev workflow.

**Альтернативы**:
- (a) Force-approval для всего JIT.
- (b) `approval_required BOOL` на eligibility row — admin при создании eligibility решает.
- (c) Route per role (cluster_admin always requires approval; project_editor — no).

**Выбор**: (b) с recommendations в docs.

**Обоснование**: granular control — admin лучше знает sensitivity конкретного scope. (c) — слишком hardcoded. UI делает default `approval_required=true` для cluster/account-scope eligibilities, `false` для project-scope (recommendation, не enforce).

### P7-D4: Break-glass — 2-person approve (cluster-admin + SRE / second cluster-admin)

**Контекст**: cluster-admin предоставление — самое чувствительное действие в системе. Single-approver открывает insider risk.

**Альтернативы**:
- (a) 1 approver (любой cluster-admin).
- (b) 2 approvers, любые два cluster-admin.
- (c) 2 approvers, разные роли (cluster-admin + SRE-on-call).
- (d) 3 approvers (M-of-N quorum).

**Выбор**: (b) — 2 approvers, оба cluster-admin (или один cluster-admin + один из escalation contacts из tenant-config).

**Обоснование**: SOC 2 CC6.7, ISO 27001 A.5.15, NIST 800-53 AC-6(7) — все requirement separation of duties для privileged grants. 2-of-2 cluster-admin — production-rasstable. (c) сложно для small teams. (d) — слишком ригидно для emergency. **separation of duties enforced на DB-уровне** (CHECK `approved_by_a <> approved_by_b` + CHECK requester ≠ approver). Дополнительно requester НЕ может быть subject (`requested_by_user_id != subject_user_id` mandatory).

### P7-D5: Break-glass max-duration 2 hours, OPA + DB CHECK (defense-in-depth)

**Контекст**: дольше break-glass держится — больше окно для злоумышленника. Mandatory short TTL — стандарт (PagerDuty PIM: 1h default; AWS IAM session: 1h-12h; production: 2h cap).

**Альтернативы**:
- (a) Любая duration на усмотрение approver'ов.
- (b) Soft-cap 2h в OPA Rego.
- (c) Hard-cap 2h: OPA Rego deny + DB CHECK constraint.

**Выбор**: (c).

**Обоснование**: OPA bundle может failure-mode load старую версию rules; DB CHECK — последняя линия (любая INSERT/UPDATE проверится в Postgres). 2 hours — стандартный compromise: достаточно для emergency-debugging, недостаточно для систематического abuse. Если 2h мало → renew workflow (новый break-glass request — нужны опять 2 approvers; нет endless renewals).

### P7-D6: PagerDuty incident P1 on break-glass request + grant

**Контекст**: break-glass — это **always** noteworthy event для security team. Нельзя allow silent grant.

**Альтернативы**:
- (a) Только Slack notification.
- (b) PagerDuty incident при grant (status=ACTIVE).
- (c) PagerDuty incident при **request** (status=AWAITING_APPROVAL_A) + acknowledge / resolve на grant/deny.

**Выбор**: (c).

**Обоснование**: P1 при request означает: «security team немедленно знает о попытке»; даже если запрос denied — оставшееся audit-trail полезен; если approval не приходит вовремя, security team может pro-active reach out. PagerDuty `incident_key` = `bgg_<id>` для dedup. На transition AWAITING → ACTIVE: PD incident updated с status update + Slack thread reply.

### P7-D7: Slack #security-alerts на каждом break-glass event

**Контекст**: PagerDuty — для on-call rotation; Slack — для broader security visibility (audit team, IT compliance, CISO).

**Альтернативы**:
- (a) Только PagerDuty.
- (b) PagerDuty + Slack channel.

**Выбор**: (b).

**Обоснование**: Slack message с Block Kit (subject_user / requested_by / rationale / approve-button с deep-link в UI) — convenient. **Slack message — informational only; нельзя approve break-glass через Slack** (auth gap — нет step-up). Кнопка ведёт в admin-UI с full step-up flow.

### P7-D8: Email security@kacho.cloud — durable record

**Контекст**: Slack messages эфемерны (auto-archive). Email — durable, indexable, available для compliance audits.

**Альтернативы**:
- (a) Только chat + PagerDuty (rely на audit log).
- (b) + Email на каждом event.
- (c) + Email только on ACTIVE / DENIED (terminal states).

**Выбор**: (c).

**Обоснование**: Email per каждый state transition — spam. Email на terminal states (ACTIVE = grant happened; DENIED = legitimate deny case) — useful audit summary. Body содержит timeline + всех participants + rationale.

### P7-D9: Mandatory post-incident review — 7-day SLA, auto-escalation

**Контекст**: break-glass без post-incident review — antipattern (security debt накапливается). Lessons learned — основное value.

**Альтернативы**:
- (a) Polite recommendation, без enforcement.
- (b) Auto-create tracking issue, SLA 7 days, escalation Slack ping если overdue.
- (c) Block future break-glass requests от requester если есть unresolved.

**Выбор**: (b) для round 1, (c) — future Phase (когда YouTrack integration mature).

**Обоснование**: balance между rigor и operational flexibility. (c) рискует self-DoS в production incident chains. Job `break_glass_review_escalator` запускается daily, для каждого `cluster_break_glass_grants` где `post_incident_review_completed_at IS NULL AND now() > approved_at_b + interval '7 days'` — emit Slack escalation message + email.

### P7-D10: JIT auto-expire через Condition `jit_window` (Phase 3 evaluated)

**Контекст**: JIT-binding со `status=ACTIVE` но без revocation — security risk. Need automatic revoke.

**Альтернативы**:
- (a) Background job revoke (status=ACTIVE → REVOKED на TTL expire).
- (b) Condition-based auto-deny (FGA Check возвращает denied на expired Condition).
- (c) Hybrid: Condition denies (immediate effect) + job updates status (data-consistency).

**Выбор**: (c).

**Обоснование**: Condition `jit_window(current_time, activated_at, ttl_seconds)` evaluates на каждом Check — immediate effect (≤ next request). Background job `jit_expirer` (60s tick) пишет `access_bindings.status='EXPIRED'`, emits audit `iam.jit.expired`, emits caep_outbox (token-claims-change). UI видит EXPIRED → не показывает «active». Defense-in-depth: даже если job lag'нул, Condition отказывает.

### P7-D11: Break-glass auto-expire — аналогично JIT (Condition + job)

Тот же pattern: `break_glass_window` Condition + `break_glass_expirer` job каждые 60s. Дополнительно при EXPIRED transition — emit Slack message «break-glass grant expired», PagerDuty incident resolve.

### P7-D12: Access Reviews — quarterly cron (Q1 Jan 1, Q2 Apr 1, Q3 Jul 1, Q4 Oct 1)

**Контекст**: SOC 2 CC6.6 / ISO 27001 A.5.18 — recurring recertification of access rights. Standard cadence — quarterly.

**Альтернативы**:
- (a) Monthly (12 reviews / year — слишком много).
- (b) Quarterly (4 reviews / year — standard).
- (c) Semi-annual (2 reviews — too sparse для compliance).

**Выбор**: (b) с per-tenant override (admin может set `account.access_review_cadence='quarterly'|'semi_annual'|'monthly'`).

**Обоснование**: industry default. Дата start (1 Jan / 1 Apr / 1 Jul / 1 Oct) — fixed на UTC 00:00 → predictable для reviewers. Configurable cadence — Phase 11 (Phase 7 — quarterly default).

### P7-D13: Access Review items без ответа после 14 days — auto-revoke

**Контекст**: reviewer-fatigue → ignored campaigns → stale grants → security risk.

**Альтернативы**:
- (a) No-op, send reminders.
- (b) Auto-revoke unanswered after N days.
- (c) Per-tenant flag + default 14 days.

**Выбор**: (c).

**Обоснование**: SOC 2 enforce-not-just-monitor требует action. 14 days — достаточный buffer для reviewer travel/PTO. Per-tenant flag `auto_revoke_unanswered` allows opt-out для tenants с custom-process'ом (e.g. legal review). Default true. Job `access_review_auto_revoke` daily.

### P7-D14: GDPR erasure — 30-day cool-off period

**Контекст**: GDPR Art. 17 даёт право на erasure, но reasonable processing time допустим (Recital 39). Cool-off защищает от accidental / coerced erasure requests.

**Альтернативы**:
- (a) Immediate erasure on request.
- (b) Short cool-off (24h-7d).
- (c) Long cool-off (30d) — industry standard.
- (d) No cool-off, but require multi-factor confirmation + email-verify.

**Выбор**: (c) + email confirmation immediately.

**Обоснование**: 30d позволяет user'у cancel (typo, coercion, change of mind); aligns с retention practices major cloud providers (AWS, GCP — 30d). Email confirmation immediately + reminder emails on day 7 / 14 / 21. Если user logs in via Passkey в течение 30d → auto-cancel (assumption: account is still wanted).

### P7-D15: GDPR erasure — cascade revoke + pseudonymize + audit retention 7y

**Контекст**: «erasure» в GDPR — это не «delete every record»; legal claims defense allows pseudonymization (Recital 30). Audit logs нужны 7y per SOC 2 / ISO 27001 / FedRAMP retention.

**Альтернативы**:
- (a) Hard-delete всё (audit included).
- (b) Hard-delete identity rows, pseudonymize PII в audit (keep audit).
- (c) Hard-delete identity (Kratos), revoke bindings, pseudonymize `users.email/display_name`, keep audit rows с pseudonymized user_id reference 7y.

**Выбор**: (c).

**Обоснование**: GDPR Art. 17(3)(b) allows retention для legal claims; audit retention — compliance requirement. Pseudonymization (Art. 4(5)) — accepted technique. `users.email` → `gdpr-erased-<sha256(user_id)>` (deterministic — same user same hash → audit cross-reference works); `users.display_name` → `Erased User`. Kratos identity hard-deleted (no auth possible). All access_bindings → status=REVOKED. ReBAC tuples deleted via outbox.

### P7-D16: GDPR account-owner edge case — block until ownership transferred

**Контекст**: если user owns Account где есть active members, erasure ломает tenant (no owner → can't manage).

**Альтернативы**:
- (a) Auto-transfer ownership на самого старого admin.
- (b) Auto-delete Account (cascade VPC, compute, lb resources).
- (c) Block erasure until manual transfer, обязательная escalation на admin/support.

**Выбор**: (c).

**Обоснование**: (a) — surprise для random admin'а; (b) — потеря data чужих team members (нарушение их contracts); (c) — explicit, user-action-required. Status `blocked` + `block_reason` field; UI показывает user'у инструкцию «transfer Account X ownership first». Admin manually transfers (existing Phase 6 RPC `AccountService.TransferOwnership`) → user retries → erasure proceeds.

### P7-D17: Notifications fail-open

**Контекст**: что если PagerDuty / Slack / SMTP недоступны на момент break-glass grant?

**Альтернативы**:
- (a) Block grant до successful notification delivery (fail-closed).
- (b) Emit audit-event "notify.delivery_failed", grant идёт через (fail-open).

**Выбор**: (b).

**Обоснование**: break-glass — emergency-tool. Если security team нужен grant, не блокировать его на временной недоступности SaaS. Audit log — fallback (security team monitors `audit_outbox` independent of notification channels). Phase 9 SIEM alert «notify.delivery_failed» — high-priority.

### P7-D18: Notifications retry — bounded with exponential backoff

3 retries, base 1s, max 30s (1, 2, 4, 8, 16, 30 capped); after 3-rd failure → audit `notify.delivery_failed` + drop. **No persistent queue в Phase 7** (per запрет #7 — broker не вводим). Phase 9 audit pipeline + Kafka может potentially заменить notification path (security team subscribes audit-topic), но это Phase 9 decision.

### P7-D19: PagerDuty dedup via `incident_key = bgg_<grant_id>`

PagerDuty Events API v2 уже поддерживает `dedup_key`. Same dedup_key → existing incident updated (not new). Phase 7 uses `bgg_<id>` → AWAITING request creates incident; ACTIVE update incident с note; EXPIRED/REVOKED resolve incident; DENIED resolve с note "denied".

### P7-D20: Slack message threading — single thread per break-glass

Initial message в `#security-alerts` имеет thread_ts; subsequent updates (approve-A, approve-B, ACTIVE, EXPIRED) posted as thread replies. Reduces channel noise.

### P7-D21: Email — transactional (not bulk)

SMTP / SES adapter. From-address `security-notifications@kacho.cloud` (fixed; configurable via env). Templates — Go text/template embedded в `corelib/notify/email_templates/`. Per-event template (request, approve, deny, expire). HTML + plaintext alternative.

### P7-D22: Email confirmation для GDPR на каждом state-transition

GDPR Art. 17 рекомендует transparent process. Email на: request created (with 30d cool-off info + cancel link), reminder day-7 / day-14 / day-21, processing started (day-30), completion. **Note**: после pseudonymization email уже не работает (адрес pseudonymized) → последний email отправляется ДО pseudonymization step.

### P7-D23: Access Review reviewer assignment — account-admin (Phase 7 default)

**Контекст**: кто reviews access bindings для account X?

**Альтернативы**:
- (a) Любой account-admin (random pick).
- (b) Specific user picked at scheduling time (admin configures).
- (c) Auto-pick account-owner.

**Выбор**: (c) с override (admin может change reviewer в UI before due date).

**Обоснование**: account-owner — natural responsibility. Override allows for delegation. SCIM-managed group reviewer (Phase 6 enterprise) — Phase 8+ feature (Phase 7 — simple user pick).

### P7-D24: JIT activation duplicate detection

Если user уже имеет ACTIVE binding для (role, resource) — что делать при second ActivateJIT?

**Альтернативы**:
- (a) Reject `AlreadyExists`.
- (b) Idempotent — return existing binding's operation_id.
- (c) Extend duration (replace TTL).

**Выбор**: (a) — `AlreadyExists` с pointer на existing binding id.

**Обоснование**: explicit. User видит существующий active binding в UI → может или подождать expiry, или revoke existing + create new. (b) hides state from user. (c) — surprise (TTL changed without obvious action).

### P7-D25: JIT activation request validation — duration ≤ max_duration

Если client requests `duration_seconds=14400` (4h) но eligibility row has `max_duration=interval '1 hour'` — InvalidArgument с конкретным сообщением `"duration_seconds=14400 exceeds eligibility max_duration=3600"`. Min duration = 60s (no infinitesimal grants).

### P7-D26: Access Review item — confirm vs revoke vs expired_auto

3-value decision: `keep` (binding stays unchanged), `revoke` (binding → REVOKED + CAEP), `expired_auto` (auto-revoke from job; reviewer didn't respond in time). Confirm — no-op on binding (decision recorded only). Revoke — atomic UPDATE binding SET status=REVOKED WHERE id=$bid AND status='ACTIVE' RETURNING — CAS pattern.

### P7-D27: Break-glass revoke (manual emergency cancel) — cluster-admin can revoke ACTIVE

Если security team realizes the grant was mistake (or compromised approver), need to revoke immediately. **Не** auto-expire (которое позже). Endpoint `InternalBreakGlassService.RevokeBreakGlass` — only cluster-admin (separate authz), CAS UPDATE `status='ACTIVE' → 'REVOKED'`, audit emit, CAEP push.

### P7-D28: All Phase 7 events emit caep_outbox tuples (Phase 8 will deliver)

Phase 7 не имеет live CAEP delivery (это Phase 8), но ВСЕ events которые меняют user's permissions (JIT activate, JIT expire, break-glass active, break-glass expire/deny, access review revoke, GDPR erasure) → INSERT в `caep_outbox` table с правильным SET-shape (token-claims-change или session-revoked). Drainer добавится в Phase 8 → events будут replayed для existing subscribers (acceptable initial lag).

---

## 4. Architecture flow diagrams

### 4.1 JIT activation (без approval)

```
User (acr=2 in session) clicks "Activate Admin" in UI on eligibility row jeg_xxx
    │
    ▼
UI POST /iam/v1/access_bindings:activateJIT
   { eligibility_id: "jeg_xxx", duration_seconds: 3600 }
   Authorization: DPoP <access_token_acr2>
    │
    ▼
api-gateway:
   - DPoP validate ✓
   - Principal extract: user=usr_alice, acr=2, mfa_at=...
   - Forward grpc kacho-iam:9090
    │
    ▼
kacho-iam AccessBindingService.ActivateJIT:
   1. Check acr ≥ 3 → FAIL (current acr=2) → return Unauthenticated{required_acr=3}
    │
    ▼
UI receives 401, redirects to /auth/step-up?return=/iam/jit/activate?eligibility_id=jeg_xxx
    │
    ▼
Kratos WebAuthn assertion (re-Passkey) → new ID-token with acr=3, kacho_mfa_at=<now>
    │
    ▼
Hydra issues new access_token (acr=3)
    │
    ▼
UI retries ActivateJIT с new token
    │
    ▼
kacho-iam AccessBindingService.ActivateJIT:
   1. acr ≥ 3 ✓
   2. Load eligibility row jeg_xxx: enabled=true, max_duration=3600s, approval_required=false ✓
   3. Check user_id matches caller ✓
   4. Check no existing ACTIVE binding for (user, role, resource_type, resource_id) — partial-UNIQUE check
   5. BEGIN TX:
      a. INSERT operations row → op_xxx (status=running)
      b. INSERT access_bindings row:
         { id: acb_xxx, subject_type: user, subject_id: usr_alice,
           role_id: role_vpc_admin, resource_type: vpc_network, resource_id: net_xxx,
           status: ACTIVE,
           condition_id: cnd_jit_window,
           condition_params: {"activated_at": "<now>", "ttl_seconds": 3600},
           expires_at: now + 3600s,
           created_via: "jit_activation",
           jit_eligibility_id: jeg_xxx }
      c. INSERT fga_outbox: Write tuple `vpc_network:net_xxx#admin@user:usr_alice[jit_window]` with Condition params
      d. INSERT caep_outbox: SET event `token_claims_change` for usr_alice
      e. INSERT audit_outbox: event `iam.jit.activated` (CADF-compatible payload)
      f. COMMIT
   6. UPDATE operations.done=true, operation_id pointing back
   7. Return Operation{ id: op_xxx, done: false } (client polls until done=true)
    │
    ▼
fga_outbox drainer (Phase 3 baseline) → OpenFGA Write tuple → effective Check ALLOW
    │
    ▼
NOTIFY kacho_iam_subjects → all per-service Check-caches invalidate usr_alice entry ≤ 1s
    │
    ▼
At T+3600s, Condition jit_window evaluates false → FGA Check returns denied
At T+3600s + ≤60s, jit_expirer job:
   - UPDATE access_bindings SET status='EXPIRED' WHERE id=acb_xxx AND status='ACTIVE'
   - INSERT fga_outbox: Delete tuple
   - INSERT caep_outbox: token_claims_change
   - INSERT audit_outbox: iam.jit.expired
```

### 4.2 JIT activation **with** approval workflow

```
User triggers ActivateJIT (как 4.1) on eligibility с approval_required=true, approver_user_id=usr_bob
    │
    ▼ (after step-up acr=3)
kacho-iam AccessBindingService.ActivateJIT:
   1. Load eligibility — approval_required=true ✓
   2. BEGIN TX:
      a. INSERT access_bindings_jit_pending row { id: jp_xxx, eligibility_id, requested_at, duration, approver }
      b. INSERT audit_outbox: iam.jit.activation_requested
      c. COMMIT (no access_bindings row yet!)
   3. Async: corelib/notify Slack DM to usr_bob "Alice requested admin on net_xxx for 1h. [Approve] [Deny]"
   4. Async: email usr_bob
   5. Return Operation{done: false} (client polls; will not done until approval/deny/timeout)
    │
    ▼
usr_bob clicks deep-link → UI step-up acr=3 → POST /iam/v1/jit-pending/jp_xxx:approve
    │
    ▼
kacho-iam JitPendingService.Approve:
   1. acr ≥ 3 ✓
   2. Authorize: caller must == jp_xxx.approver_user_id (CAS UPDATE WHERE approver_user_id=$caller AND decision IS NULL RETURNING)
   3. CAS UPDATE jit_pending SET decision='approved', decided_at=now, decided_by=$caller
   4. INSERT access_bindings (as in 4.1 step 5b/c/d/e) + Operation transition
   5. Audit: iam.jit.activation_approved
   6. Slack thread reply "approved"
    │
    ▼
Operation polled by Alice's UI → done=true → effective grant
```

If approver doesn't act in 24h, separate job `jit_pending_expirer` (Phase 7 scope) transitions jit_pending to `decision='timeout_expired'`, original Operation completes with error, audit emit.

### 4.3 Break-glass — full lifecycle

```
Step 1: Request
─────────────────
SRE-on-call (usr_charlie) opens PagerDuty inc-12345; needs cluster_admin to debug;
no existing eligibility row for cluster scope (intentionally — cluster-admin is JIT-not-supported,
only break-glass).
   │
   ▼ UI step-up acr=3
POST /iam/v1/internal/cluster:requestBreakGlass
   { subject_user_id: usr_charlie, incident_id: "PAG-INC-12345",
     rationale: "Customer-impact production outage on eu-central. Need cluster-admin to inspect FGA writes.",
     duration_seconds: 7200 }
   (note: this is on INTERNAL listener — admin-UI port-forward or cluster-internal callers only)
    │
    ▼
api-gateway internal mux → kacho-iam InternalBreakGlassService.RequestBreakGlass
   1. acr ≥ 3 ✓
   2. Authorize: caller (= requested_by_user_id) must have permission `cluster.break_glass.request`
      (role assigned to all members of SCIM-managed group `kacho-sre-on-call`)
   3. Validate: duration ≤ 7200s (OPA Rego "break-glass max 2h" enforces; DB CHECK reinforces)
   4. BEGIN TX:
      a. INSERT cluster_break_glass_grants:
         { id: bgg_xxx, subject_user_id: usr_charlie, status: 'AWAITING_APPROVAL_A',
           incident_id: 'PAG-INC-12345', rationale, requested_by_user_id: $caller,
           requested_at: now, expires_at: now + 7200s,
           post_incident_review_issue_url: NULL }
      b. INSERT audit_outbox: iam.break_glass.requested
      c. INSERT operations row → op_yyy
      d. COMMIT
   5. Async notification fan-out (in goroutine, fail-open):
      - PagerDuty: trigger P1 incident, incident_key='bgg_xxx',
        summary "Break-glass requested by Charlie for Charlie. INC-12345.",
        custom_details: {rationale, expires_at, ...}
      - Slack #security-alerts: Block Kit message with [Approve A][Deny] buttons (link to UI)
        thread_ts saved for future replies
      - Email security@kacho.cloud: HTML+plaintext summary
   6. Return Operation{done: false}

Step 2: Approve-A (first approver)
─────────────────
Cluster-admin Dana sees PagerDuty + Slack; opens UI; step-up acr=3.
POST /iam/v1/internal/cluster/break-glass/bgg_xxx:approveA  Authz: cluster.break_glass.approve permission
   1. acr ≥ 3 ✓
   2. Authorize permission ✓
   3. Validate Dana != subject_user_id (usr_charlie) ✓
   4. Validate Dana != requested_by_user_id (also usr_charlie) ✓
   5. CAS UPDATE: SET status='AWAITING_APPROVAL_B', approved_by_a=$caller, approved_at_a=now
      WHERE id=$bgg_id AND status='AWAITING_APPROVAL_A' AND approved_by_a IS NULL
      RETURNING ... — if 0 rows → FailedPrecondition "not in AWAITING_APPROVAL_A state"
   6. Audit iam.break_glass.approved_a
   7. PagerDuty: incident note "Approved-A by Dana"
   8. Slack thread reply
   9. Email security@: thread update

Step 3: Approve-B (second approver — must be different person)
─────────────────
Cluster-admin Eve (or second-on-call) clicks approve. POST .../bgg_xxx:approveB
   1. acr ≥ 3 ✓
   2. Authorize ✓
   3. Validate Eve != subject_user_id, Eve != requested_by_user_id, Eve != approved_by_a (Dana)
      → DB CHECK + service-level check
   4. CAS UPDATE: SET status='ACTIVE', approved_by_b=$caller, approved_at_b=now
      WHERE id=$bgg_id AND status='AWAITING_APPROVAL_B' AND approved_by_b IS NULL AND approved_by_a <> $caller
      RETURNING ... — 0 rows → FailedPrecondition
   5. INSERT fga_outbox: Write tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_charlie[break_glass_window]`
      condition_params: {expires_at: <bgg.expires_at>}
   6. INSERT caep_outbox: SET event session_revoked для usr_charlie (force re-token with elevated claims)
   7. INSERT audit_outbox: iam.break_glass.activated (CADF event)
   8. INSERT post_incident_review tracking issue (create via YT / GitHub API; URL written back to bgg row)
   9. Async PagerDuty: incident NOTE "ACTIVATED — Charlie has emergency_admin until <expires>"
   10. Slack thread "🚨 ACTIVE: cluster_admin granted to Charlie. Expires <timestamp>. Review issue: <url>"
   11. Email security@: ACTIVATION CONFIRMATION

Step 4a: Auto-expire (T+2h)
─────────────────
break_glass_expirer job (60s ticks):
   1. SELECT id FROM cluster_break_glass_grants WHERE status='ACTIVE' AND expires_at < now()
   2. For each: CAS UPDATE status='EXPIRED' WHERE id=$id AND status='ACTIVE'
   3. INSERT fga_outbox: Delete tuple
   4. INSERT caep_outbox: token_claims_change
   5. INSERT audit_outbox: iam.break_glass.expired
   6. PagerDuty: resolve incident
   7. Slack thread "✅ Break-glass expired"
   8. (No email per terminal-only D8? — actually expire IS terminal, email IS sent)
   9. NOTIFY kacho_iam_subjects → caches invalidate Charlie's permissions

Step 4b: Alternative — Manual Revoke (emergency cancel)
─────────────────
Compromised-approver scenario: Eve realizes she approved by mistake.
POST .../bgg_xxx:revoke (cluster.break_glass.revoke permission)
   1. CAS UPDATE: status='ACTIVE' → 'REVOKED', revoked_at=now
   2. Same fanout as expire (delete tuple, caep, audit, notifications)

Step 5: Post-incident review (7d SLA)
─────────────────
break_glass_review_escalator job (daily 09:00 UTC):
   1. SELECT id, subject_user_id, requested_by_user_id, post_incident_review_issue_url
        FROM cluster_break_glass_grants
        WHERE post_incident_review_completed_at IS NULL
        AND approved_at_b < now() - interval '7 days'
        AND status IN ('EXPIRED','REVOKED')   -- only successful grants need PIR
   2. For each: Slack escalation message, email to all approvers + subject + manager
   3. Audit: iam.break_glass.post_incident_review_overdue
```

### 4.4 Access Review quarterly cycle

```
Quarterly cron access_review_scheduler (1 Jan / 1 Apr / 1 Jul / 1 Oct UTC 00:00):
   1. SELECT * FROM accounts WHERE status='ACTIVE'
   2. For each account:
      a. Resolve reviewer = account.owner_user_id (or override field)
      b. INSERT access_reviews { id: arv_xxx, account_id, quarter: "2026-Q2",
            scheduled_at: now, due_at: now + 14d, status: 'SCHEDULED',
            reviewer_user_id, auto_revoke_unanswered: true }
      c. SELECT * FROM access_bindings WHERE
            (resource_type='account' AND resource_id=$aid)
            OR resource_id IN (SELECT id FROM projects WHERE account_id=$aid)
            -- (cross-account project members ALSO get review-items for their bindings on this account)
            AND status='ACTIVE' AND (expires_at IS NULL OR expires_at > now())
      d. For each binding: INSERT access_review_items { id: arvi_xxx, review_id: arv_xxx,
            access_binding_id, decision: NULL }
      e. UPDATE access_reviews.status='IN_PROGRESS'
   3. Send email to each reviewer "You have N items to review for Q2 2026 by <due_at>"
   4. Slack DM to reviewer (if integrated)

Daily reminder job (until due_at):
   - Send reminder email at 7d / 3d / 1d before due_at if items still pending

Reviewer interaction (in UI):
   GET /iam/v1/access_reviews?reviewer_user_id=self&status=IN_PROGRESS
   → list of campaigns with item counts
   GET /iam/v1/access_reviews/arv_xxx/items?decision=null
   → list of pending items with binding details
   POST /iam/v1/access_reviews/arv_xxx/items/arvi_yyy:confirm  → decision='keep', no binding change
   POST /iam/v1/access_reviews/arv_xxx/items/arvi_yyy:revoke   → decision='revoke', cascade:
      - CAS UPDATE access_bindings SET status='REVOKED' WHERE id=$bid AND status='ACTIVE'
      - INSERT fga_outbox (Delete tuple)
      - INSERT caep_outbox (token_claims_change)
      - INSERT audit_outbox: iam.access_review.revoked

After all items have decisions:
   UPDATE access_reviews SET status='COMPLETED', completed_at=now
   Audit: iam.access_review.completed

Auto-revoke job (daily 09:00 UTC):
   FOR review WHERE status='IN_PROGRESS' AND now() > due_at AND auto_revoke_unanswered=true:
      FOR item WHERE decision IS NULL:
         CAS UPDATE access_review_items SET decision='expired_auto', decision_at=now WHERE id=$iid AND decision IS NULL
         CAS UPDATE access_bindings SET status='REVOKED' WHERE id=$bid AND status='ACTIVE'
         outbox emits
      UPDATE access_reviews.status='OVERDUE' (then 'COMPLETED' when all items decided)
```

### 4.5 GDPR erasure pipeline

```
T+0: User submits erasure request (UI / API)
─────────────────
User (acr=2 session) → UI Settings → GDPR → "Request data erasure"
   → UI step-up acr=3 → POST /iam/v1/gdpr/requestErasure {} (subject = self)
   Or admin-initiated: POST /iam/v1/gdpr/requestErasure { subject_user_id: usr_xxx }
      (requires `iam.gdpr.request_on_behalf` permission, rare)
   │
   ▼
kacho-iam GdprErasureService.RequestErasure:
   1. acr ≥ 3 ✓
   2. If subject != caller, authz ✓
   3. Check no existing active request (partial-UNIQUE on (subject_user_id) WHERE status IN ('cool_off','in_progress')) → AlreadyExists if dup
   4. Check ownership block: SELECT count(*) FROM accounts WHERE owner_user_id=$subject_user_id
        AND id IN (SELECT account_id FROM users WHERE id <> $subject_user_id AND status='ACTIVE')
      — if > 0 → INSERT request with status='blocked', block_reason populated
   5. Else BEGIN TX:
      a. INSERT gdpr_erasure_requests:
         { id: gdpr_xxx, subject_user_id, requested_by_user_id: $caller,
           requested_at: now, cool_off_until: now + 30d, status: 'cool_off' }
      b. INSERT audit_outbox: iam.gdpr.erasure_requested
      c. INSERT operations row
      d. COMMIT
   6. Async: send confirmation email to user.email (subject + body explain 30d cool-off, cancel link)
   7. Schedule reminder emails day-7 / 14 / 21 (via separate gdpr_reminder_job)
   8. Return Operation{done: true, response: { request_id: gdpr_xxx, cool_off_until }}

T+30: Daily cron processes
─────────────────
gdpr_erasure_processor (daily 02:00 UTC, idempotent):
   1. SELECT id, subject_user_id FROM gdpr_erasure_requests
        WHERE status='cool_off' AND cool_off_until <= now()
        FOR UPDATE SKIP LOCKED
   2. For each request:
      a. UPDATE status='in_progress', started_at=now
      b. Re-check ownership block (state may have changed in 30d) — if blocked → status='blocked', email
      c. BEGIN TX (idempotent — each step uses WHERE NOT already_done):
         - UPDATE users SET status='BLOCKED' WHERE id=$subj
         - UPDATE access_bindings SET status='REVOKED' WHERE subject_id=$subj AND status='ACTIVE'
         - INSERT fga_outbox: Delete all tuples for subject (worker drains)
         - INSERT caep_outbox: session_revoked (force logout)
         - Pseudonymize: UPDATE users SET email=$pseudonym, display_name='Erased User'
           WHERE id=$subj (pseudonym = "gdpr-erased-" || encode(sha256(id::bytea),'hex'))
         - INSERT audit_outbox: iam.gdpr.erasure_in_progress
         COMMIT
      d. Async: send "processing started" email (TO original email, BEFORE pseudonymize commit? — order matters: email FIRST, then pseudonymize; if email fails, retry)
      e. Async: SCIM webhook to downstream subscribers
      f. Async: Kratos admin DELETE /admin/identities/<kratos_identity_id>
      g. UPDATE status='completed', completed_at=now
      h. INSERT audit_outbox: iam.gdpr.erasure_completed

If error during processing: status stays 'in_progress', retried next day (idempotent).
Final state: users row exists with pseudonymized PII; bindings revoked; audit rows retained 7y.

Cancel pathway:
─────────────────
User logs in within 30d → middleware checks gdpr_erasure_requests for active request → auto-cancel
   or
User explicit POST /iam/v1/gdpr/cancelErasure { request_id: gdpr_xxx }
   1. acr ≥ 3 (if interactive)
   2. CAS UPDATE: status='cool_off' → 'cancelled', cancelled_at=now, cancelled_by_user_id=$caller
      WHERE id=$id AND status='cool_off' RETURNING — 0 rows → FailedPrecondition "cannot cancel non-active request"
   3. Audit: iam.gdpr.erasure_cancelled
   4. Email confirmation
```

---

## 5. Декомпозиция (что строится, где, и в каком порядке)

### 5.1 kacho-proto (PR #1)

**Path**: `proto/kacho/cloud/iam/v1/`.

New / extended files:
- `jit_eligibility_service.proto` — `service JITEligibilityService { rpc Create, Update, Delete, Get, List }`; message `JITEligibility { id, user_id, role_id, resource_type, resource_id, max_duration, approver_user_id, approval_required, enabled, expires_at, created_at, created_by }`; `CreateJITEligibilityRequest`, `UpdateJITEligibilityRequest` (with `update_mask`), etc.
- `access_binding_service.proto` (extend existing) — add `rpc ActivateJIT(ActivateJITRequest) returns (operation.Operation)`. Request: `{ eligibility_id, duration_seconds, justification }`. Response Operation metadata: `ActivateJITMetadata{ access_binding_id, eligibility_id, duration_seconds, expires_at }`.
- `internal_break_glass_service.proto` — `service InternalBreakGlassService { RequestBreakGlass, ApproveBreakGlass, DenyBreakGlass, RevokeBreakGlass, ListPending, ListActive, Get }`. **Internal-only marker** in comments: «registered only on internal mux, not exposed на external TLS».
- `access_review_service.proto` — `service AccessReviewService { List, Get, ListItems, ConfirmItem, RevokeItem }`. Internal admin RPC `service InternalAccessReviewService { TriggerSchedulerNow }` (manual quarterly run trigger; otherwise daily cron).
- `gdpr_erasure_service.proto` — `service GdprErasureService { RequestErasure, CancelErasure, List, Get }`. Internal `service InternalGdprErasureService { ListAll, FailedRetries }` (admin observability).

Buf-lint must pass; buf-breaking must pass (additive only).

### 5.2 kacho-corelib (PR #2)

**Path**: `corelib/notify/`.

New files:
- `notify.go` — `type Event struct { Kind string; IncidentKey string; Severity string; Subject string; Body string; Fields map[string]string; ThreadKey string }`; `type Notifier interface { Send(ctx, ev Event) error }`; `type Fanout struct { Notifiers []Notifier; Dedup *DedupCache }`; `func (f *Fanout) Send(ctx, ev Event)` — calls each notifier с retry / dedup.
- `pagerduty.go` — Events API v2 client: `type PagerDuty struct { RoutingKey, HTTPClient }`; `Send` maps Event → PD payload; uses `incident_key` for dedup; supports `event_action: trigger | acknowledge | resolve`. Retries 3x with exp backoff.
- `slack.go` — Incoming webhook + Block Kit builder: `type Slack struct { WebhookURL, HTTPClient, Channel string }`; supports threading via `thread_ts` (caller passes ThreadKey → resolved via storage); first message stores ts in `notify_slack_threads` table (or in-memory map keyed by IncidentKey).
- `email.go` — SMTP/SES adapter (interface for swap): `type Email struct { Transport EmailTransport; From string }`; templates loaded from `email_templates/*.txt` and `*.html` via `embed.FS`; per-Kind template selection.
- `notify_testing.go` — `type Recorder struct { Sent []Event }` (implements `Notifier`); used in tests for assert «event was sent».
- `dedup.go` — sliding-window LRU keyed by IncidentKey (avoid double-fire on retries).

Unit tests:
- `pagerduty_test.go` — http test server, assert request body shape, retry on 5xx.
- `slack_test.go` — webhook test server, assert Block Kit json, threading.
- `email_test.go` — fake SMTP, assert From/To/Body templates rendered.
- `notify_test.go` — fanout behavior, dedup correctness.

### 5.3 kacho-iam (PR #3)

**Path**: `kacho-iam/internal/...`.

#### Domain layer
- `internal/domain/jit_eligibility.go` — self-validating type: `New(...)` validates `max_duration > 0 && <= 8h`, `resource_type ∈ {project,account,organization,vpc_network,...}`, etc.
- `internal/domain/break_glass_grant.go` — state-machine helpers (`CanTransitionTo(currentStatus, newStatus) bool`); validates duration ≤ 2h.
- `internal/domain/access_review.go` + `access_review_item.go`.
- `internal/domain/gdpr_erasure_request.go` — validates state transitions; computes pseudonym from user_id.

#### Service / use-case layer
- `internal/apps/kacho/api/access_binding/activate_jit.go` — main flow: load eligibility, validate caller, validate duration ≤ max, check no duplicate, atomic INSERT + outbox tuples + audit. If `approval_required`, instead of inserting access_bindings, INSERT `access_bindings_jit_pending` (new table per migration 0021? or use existing operations machinery — TBD per implementer; design preference: use `jit_pending` table — see §6.16 for table schema).
- `internal/apps/kacho/api/jit_eligibility/{create,update,delete,get,list}.go` — CRUD; create/update writes via Writer transaction; immutability enforced on Update via update_mask validation.
- `internal/apps/kacho/api/cluster/{request_break_glass,approve_break_glass,deny_break_glass,revoke_break_glass,list_pending,list_active,get_break_glass}.go` — handlers. State transitions strictly via CAS UPDATE WHERE status=$expected RETURNING.
- `internal/apps/kacho/api/access_review/{list,get,list_items,confirm_item,revoke_item}.go`.
- `internal/apps/kacho/api/gdpr/{request_erasure,cancel_erasure,list,get}.go`.

#### Background jobs
- `internal/apps/kacho/jobs/jit_expirer.go` — 60s tick; UPDATEs expired ACTIVE bindings → EXPIRED + outbox + audit.
- `internal/apps/kacho/jobs/break_glass_expirer.go` — 60s tick; same pattern.
- `internal/apps/kacho/jobs/access_review_scheduler.go` — quarterly cron (4 fixed dates per year UTC midnight) — triggered via internal cron lib (e.g. `robfig/cron`) или CronJob Kubernetes (`kacho-deploy` CronJob calls `InternalAccessReviewService.TriggerSchedulerNow` — preferred per запрет #7 "no broker, use simplest").
- `internal/apps/kacho/jobs/access_review_auto_revoke.go` — daily 09:00 UTC.
- `internal/apps/kacho/jobs/access_review_reminder.go` — daily; sends reminder emails on 7d/3d/1d.
- `internal/apps/kacho/jobs/break_glass_review_escalator.go` — daily.
- `internal/apps/kacho/jobs/gdpr_erasure_processor.go` — daily 02:00 UTC.
- `internal/apps/kacho/jobs/gdpr_reminder.go` — daily; sends 7d/14d/21d reminders.
- `internal/apps/kacho/jobs/jit_pending_expirer.go` — checks approval-pending requests; 24h timeout → expired.

#### Repository layer
- `internal/repo/jit_eligibility_repo.go`, `break_glass_grant_repo.go`, `access_review_repo.go`, `access_review_item_repo.go`, `gdpr_erasure_request_repo.go`, `jit_pending_repo.go` (если table вводится).
- Each repo: Reader (Get/List/check helpers) + Writer (atomic INSERT/CAS UPDATE с RETURNING кардинальностью; map SQLSTATE 23xxx → service sentinel errors).

#### Migration (optional)
- `migrations/0021_kac127_phase7_indexes.sql` — добавить `CREATE INDEX CONCURRENTLY` если нужно для job-scan производительности (e.g. `access_bindings(expires_at) WHERE status='ACTIVE'` для jit_expirer; `cluster_break_glass_grants(expires_at) WHERE status='ACTIVE'`). Если table `access_bindings_jit_pending` нужна (см. P7-D3 — yes, нужна для approval pending state) — CREATE TABLE статement в эту же миграцию (это новая таблица, не правка Phase 1).

#### Wiring (composition root)
- `cmd/kacho-iam/main.go` — register all новые gRPC services + start jobs goroutines + wire notify.Fanout (PagerDuty + Slack + Email from env).

### 5.4 kacho-api-gateway (PR #4)

**Path**: `kacho-api-gateway/internal/restmux/mux.go` extend:
- **public mux**: register `JITEligibilityService`, `AccessBindingService.ActivateJIT` (new RPC; existing service block updated), `AccessReviewService`, `GdprErasureService`. REST paths: `/iam/v1/jitEligibilities`, `/iam/v1/accessBindings:activateJIT`, `/iam/v1/accessReviews`, `/iam/v1/accessReviews/{id}/items`, `/iam/v1/gdpr/requests`.
- **internal mux**: register `InternalBreakGlassService`, `InternalAccessReviewService`, `InternalGdprErasureService`. REST paths under `/iam/v1/internal/...`.
- Rate-limits: ActivateJIT — 10 req/s per principal; RequestBreakGlass — 5 req/min cluster-wide (rare event); GDPR — 1 req/h per principal.

### 5.5 kacho-deploy (PR #5)

**Path**: `helm/umbrella/`.

- `values.yaml` extends:
  ```yaml
  iam:
    notify:
      pagerduty: { enabled: true, routingKeySecret: "pagerduty-routing-key" }
      slack:    { enabled: true, webhookSecret: "slack-webhook-security", channel: "#security-alerts" }
      email:    { enabled: true, smtp: { hostSecret: "smtp-host", credentialsSecret: "smtp-credentials" }, from: "security-notifications@kacho.cloud" }
  ```
- Sealed Secrets / External Secrets Operator templates для secret loading.
- CronJob templates для jobs (если deployment delegate'ит cron внешнему K8s scheduler): `access-review-scheduler-cronjob.yaml` (schedule: `0 0 1 1,4,7,10 *`), `access-review-auto-revoke-cronjob.yaml`, etc. **Альтернатива**: jobs запускаются in-process в `kacho-iam` (preferred — меньше moving parts). Решение в Phase 7 — in-process goroutines (per запрет #7 simplification), но идемпотентные (multiple replicas safe via SELECT FOR UPDATE SKIP LOCKED + advisory locks).

### 5.6 kacho-ui (PR #6)

**Path**: `kacho-ui/src/pages/iam/`.

- `jit/EligibilityList.tsx` — admin view: list eligibilities на ресурсе, create/edit/delete forms.
- `jit/ActivateModal.tsx` — user view: own eligibilities, click activate → re-Passkey modal → progress indicator → activated.
- `break-glass/RequestForm.tsx` — SRE submits request (visible only with `cluster.break_glass.request` permission); shows form, posts to internal API via UI's internal proxy.
- `break-glass/ApproverPage.tsx` — cluster-admin view: list pending grants, click approve → step-up → approve.
- `break-glass/ListActive.tsx` — view active break-glass grants (read-only audit page).
- `access-reviews/List.tsx` + `Detail.tsx` + `ItemRow.tsx` — reviewer workflow.
- `settings/gdpr/RequestErasure.tsx` — user GDPR settings.

### 5.7 kacho-workspace (PR #7)

Vault updates (см. §«Predecessors» list). KAC-127 note updated с Phase 7 PRs.

---

## 6. Сценарии Given-When-Then (нормативные acceptance-тесты)

> Каждый сценарий имеет уникальный **ID** `7-NN`, используется для трассировки к integration / newman cases. Negative-сценарии содержат ожидаемый gRPC код. Все мутирующие RPC возвращают `Operation` (запрет #9).

### 6.1 JIT Eligibility CRUD

#### Сценарий 7-01: Admin creates JIT eligibility (happy path)

**ID**: `7-01`

**Given** account `acc_x` существует и `usr_admin_alice` имеет permission `iam.access_bindings.upsert` на `acc_x`
**And** user `usr_bob_dev` существует в account `acc_x`
**And** role `role_vpc_admin` существует с permissions `vpc.networks.*`
**And** vpc-network `net_yyy` существует в project `prj_yyy` в `acc_x`

**When** `usr_admin_alice` (acr=2) calls `JITEligibilityService/Create` через REST POST `/iam/v1/jitEligibilities` body:
  - user_id = "usr_bob_dev"
  - role_id = "role_vpc_admin"
  - resource_type = "vpc_network"
  - resource_id = "net_yyy"
  - max_duration = "3600s"
  - approval_required = false
  - enabled = true

**Then** response = `Operation { id: op_xxx, done: false }` HTTP 200
**And** клиент polls `OperationService.Get(op_xxx)` пока done=true
**And** `op_xxx.response` = `JITEligibility { id: jeg_xxx, ... }`
**And** в `access_bindings_jit_eligibility` появляется row с `created_by=usr_admin_alice`, `enabled=true`
**And** в `audit_outbox` появляется event `iam.jit_eligibility.created` с CADF payload
**And** `usr_bob_dev` через `JITEligibilityService.List` (filter by `user_id=self`) видит свою eligibility

#### Сценарий 7-02: Create JIT eligibility — max_duration exceeds 8 hours

**ID**: `7-02`

**Given** same preconditions as 7-01

**When** caller passes `max_duration = "36000s"` (10 hours)

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ code: 3, message: "Illegal argument max_duration: must be in range (0, 8 hours]" }`
**And** no row inserted в `access_bindings_jit_eligibility`
**And** audit emits `iam.jit_eligibility.create_rejected` с reason `validation_error`

#### Сценарий 7-03: Create JIT eligibility — caller lacks permission

**ID**: `7-03`

**Given** `usr_random_carol` не имеет permission `iam.access_bindings.upsert` на `acc_x`

**When** `usr_random_carol` calls `JITEligibilityService/Create` с теми же params

**Then** response = HTTP 403 `PERMISSION_DENIED`, body `{ code: 7, message: "permission denied" }`
**And** audit emits `iam.jit_eligibility.create_denied`

#### Сценарий 7-04: Update JIT eligibility — toggle enabled

**ID**: `7-04`

**Given** eligibility `jeg_xxx` существует с `enabled=true`

**When** `usr_admin_alice` calls `JITEligibilityService/Update` с `update_mask=["enabled"]`, `enabled=false`

**Then** response = `Operation { done: true, response: JITEligibility { enabled: false } }`
**And** в БД row updated
**And** audit emits `iam.jit_eligibility.updated`
**And** subsequent `ActivateJIT` на `jeg_xxx` → `FAILED_PRECONDITION` (см. 7-13)

#### Сценарий 7-05: Update JIT eligibility — try to mutate immutable field

**ID**: `7-05`

**Given** eligibility `jeg_xxx` существует

**When** `usr_admin_alice` calls `Update` с `update_mask=["user_id"]`, `user_id="usr_other"`

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "user_id is immutable after JITEligibility.Create" }`
**And** row unchanged

#### Сценарий 7-06: Delete JIT eligibility

**ID**: `7-06`

**Given** eligibility `jeg_xxx` существует, no ACTIVE access_bindings derived from it

**When** `usr_admin_alice` calls `Delete`

**Then** response = `Operation { done: true }`
**And** row deleted (FK ON DELETE CASCADE из `users` НЕ срабатывает; delete — explicit)
**And** audit emits `iam.jit_eligibility.deleted`

#### Сценарий 7-07: List JIT eligibilities — filtering

**ID**: `7-07`

**Given** 5 eligibilities существуют (3 для `usr_bob_dev`, 2 для `usr_eve_dev`), все в `acc_x`

**When** `usr_admin_alice` calls `List` без filter

**Then** response содержит все 5 (ListObjects from Phase 4 ACL применяется — admin видит)

**When** `usr_bob_dev` calls `List`

**Then** response содержит только 3 свои (фильтрация на authz-layer)

### 6.2 ActivateJIT Happy Path

#### Сценарий 7-08: ActivateJIT — happy path (no approval required)

**ID**: `7-08`

**Given** eligibility `jeg_xxx` существует, enabled=true, user=usr_bob_dev, role=role_vpc_admin, resource=vpc_network:net_yyy, max_duration=3600s, approval_required=false
**And** `usr_bob_dev` имеет fresh acr=3 token (re-Passkey ≤ 5 min ago)

**When** `usr_bob_dev` calls `AccessBindingService/ActivateJIT` через REST POST `/iam/v1/accessBindings:activateJIT` body:
  - eligibility_id = "jeg_xxx"
  - duration_seconds = 1800
  - justification = "Debugging customer-impact incident INC-123"

**Then** response = `Operation { id: op_xxx, done: false }` HTTP 200
**And** клиент polls `OperationService.Get` → eventually done=true
**And** `op_xxx.response` = `AccessBinding { id: acb_xxx, status: ACTIVE, subject_id: usr_bob_dev, role_id: role_vpc_admin, resource_type: vpc_network, resource_id: net_yyy, condition_id: cnd_jit_window, expires_at: now+1800s, jit_eligibility_id: jeg_xxx }`
**And** в `fga_outbox` появляется row Write tuple `vpc_network:net_yyy#admin@user:usr_bob_dev[jit_window(activated_at=<now>, ttl_seconds=1800)]`
**And** drainer pushes tuple в OpenFGA в ≤ 1s; FGA Check для `usr_bob_dev` на `vpc.networks.update` для `net_yyy` returns ALLOW
**And** в `audit_outbox` появляется event `iam.jit.activated` с full CADF payload (actor=usr_bob_dev, target=acb_xxx, action=activate, outcome=success)
**And** в `caep_outbox` появляется row event type `token_claims_change` для subject=usr_bob_dev

#### Сценарий 7-09: ActivateJIT — без step-up returns Unauthenticated

**ID**: `7-09`

**Given** eligibility `jeg_xxx` существует
**And** `usr_bob_dev` имеет only acr=2 token (signed in, no re-Passkey)

**When** `usr_bob_dev` calls `ActivateJIT` с params eligibility_id=jeg_xxx

**Then** response = HTTP 401 `UNAUTHENTICATED`, body `{ code: 16, message: "step-up required", details: [{ "@type": "type.googleapis.com/google.rpc.ErrorInfo", reason: "STEP_UP_REQUIRED", metadata: { required_acr: "3", current_acr: "2", current_mfa_at: "..." } }] }`
**And** no row in access_bindings
**And** audit emits `iam.jit.activate_rejected` с reason `step_up_required`

#### Сценарий 7-10: ActivateJIT — duration exceeds max_duration

**ID**: `7-10`

**Given** eligibility с `max_duration=3600s`, acr=3

**When** caller passes `duration_seconds = 7200`

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "duration_seconds=7200 exceeds eligibility max_duration=3600" }`

#### Сценарий 7-11: ActivateJIT — duration_seconds below minimum

**ID**: `7-11`

**Given** eligibility, acr=3

**When** caller passes `duration_seconds = 30` (below min 60s)

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "duration_seconds: must be in range [60, max_duration]" }`

#### Сценарий 7-12: ActivateJIT — user_id mismatch

**ID**: `7-12`

**Given** eligibility `jeg_xxx` has `user_id=usr_bob`, acr=3 token of `usr_eve`

**When** `usr_eve` calls `ActivateJIT` с `eligibility_id=jeg_xxx`

**Then** response = HTTP 403 `PERMISSION_DENIED`, body `{ message: "eligibility user_id mismatch" }`
**And** audit `iam.jit.activate_denied`

#### Сценарий 7-13: ActivateJIT — eligibility disabled

**ID**: `7-13`

**Given** eligibility `jeg_xxx`, `enabled=false`

**When** `usr_bob_dev` (acr=3, correct user) calls `ActivateJIT`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "JIT eligibility is disabled" }`

#### Сценарий 7-14: ActivateJIT — eligibility row itself expired

**ID**: `7-14`

**Given** eligibility `jeg_xxx` has `expires_at = now - interval '1 hour'` (eligibility itself expired)

**When** `usr_bob_dev` calls `ActivateJIT`

**Then** response = HTTP 412 `FAILED_PRECONDITION`, body `{ message: "JIT eligibility expired" }`

#### Сценарий 7-15: ActivateJIT — duplicate ACTIVE binding (idempotency / AlreadyExists)

**ID**: `7-15`

**Given** `usr_bob_dev` already has ACTIVE `access_bindings.id=acb_existing` for role_vpc_admin on net_yyy

**When** `usr_bob_dev` calls `ActivateJIT` for same scope (same eligibility)

**Then** response = HTTP 409 `ALREADY_EXISTS`, body `{ message: "active binding already exists", details: [{ resource_id: "acb_existing", expires_at: "..." }] }`
**And** no new row inserted

#### Сценарий 7-16: ActivateJIT — concurrent dual activate (DB-level race protection)

**ID**: `7-16`

**Given** eligibility `jeg_xxx`, no existing ACTIVE binding

**When** two concurrent ActivateJIT requests fire simultaneously от usr_bob_dev (e.g. UI double-click bug)

**Then** ровно **одна** request succeeds (response Operation done=true с binding); другая получает HTTP 409 `ALREADY_EXISTS` (partial UNIQUE на `(user_id, role_id, resource_type, resource_id) WHERE status='ACTIVE'` срабатывает на 23505)
**And** в БД ровно 1 row в access_bindings
**And** integration test (testcontainers) запускает 10 concurrent goroutines, asserts exactly 1 succeeds, 9 ALREADY_EXISTS

### 6.3 ActivateJIT — with Approval Workflow

#### Сценарий 7-17: ActivateJIT с approval — pending request created

**ID**: `7-17`

**Given** eligibility `jeg_zzz` с `approval_required=true`, `approver_user_id=usr_lead_dana`
**And** `usr_bob_dev` (acr=3) eligible for this eligibility

**When** `usr_bob_dev` calls `ActivateJIT` (eligibility_id=jeg_zzz, duration_seconds=3600)

**Then** response = `Operation { id: op_xxx, done: false }`
**And** клиент polls — Operation остаётся done=false до approval/deny/timeout
**And** в `access_bindings_jit_pending` появляется row `{ id: jp_xxx, eligibility_id: jeg_zzz, requested_by: usr_bob_dev, decision: NULL, duration_seconds: 3600 }`
**And** **no** row в `access_bindings` пока
**And** в `audit_outbox` event `iam.jit.activation_requested`
**And** через corelib/notify Slack DM отправляется approver `usr_lead_dana`: "Alice requested admin role on net_yyy for 1h. [Approve][Deny] <link>"
**And** email approver получает копию

#### Сценарий 7-18: Approve pending JIT — grant materializes

**ID**: `7-18`

**Given** pending JIT request `jp_xxx` существует
**And** approver `usr_lead_dana` имеет fresh acr=3 token

**When** `usr_lead_dana` calls `JitPendingService/Approve` (или `AccessBindingService.ApproveJitActivation`) с `pending_id=jp_xxx`

**Then** response = `Operation { done: true }`
**And** CAS UPDATE jit_pending row → `decision='approved'`, `decided_by=usr_lead_dana`, `decided_at=now`
**And** access_bindings row inserted (как в 7-08)
**And** fga_outbox + caep_outbox + audit_outbox rows
**And** Original `op_xxx` (от Alice's ActivateJIT) → done=true с response=AccessBinding
**And** Slack thread reply "✅ Approved by Dana" + email подтверждение Bob

#### Сценарий 7-19: Deny pending JIT

**ID**: `7-19`

**Given** pending JIT `jp_xxx`

**When** approver calls `JitPendingService/Deny` с reason "out of business hours"

**Then** CAS UPDATE decision='denied', no access_bindings row
**And** original Operation done=true с `result.error = { code: PERMISSION_DENIED, message: "approval denied: out of business hours" }`
**And** audit `iam.jit.activation_denied`
**And** Slack + email notification к requester

#### Сценарий 7-20: JIT pending — approver self-denial (cannot approve own)

**ID**: `7-20`

**Given** eligibility `jeg_zzz` имеет `user_id=usr_bob_dev`, `approver_user_id=usr_bob_dev` (misconfig — same person both)

**When** `usr_bob_dev` calls ActivateJIT, потом своим же токеном — Approve

**Then** Approve call returns HTTP 412 `FAILED_PRECONDITION`, body `{ message: "approver cannot approve own JIT activation request" }`
**And** pending request остаётся decision=NULL (eventually expires via timeout job 24h)

#### Сценарий 7-21: JIT pending — timeout expire

**ID**: `7-21`

**Given** pending JIT `jp_xxx` created 25h ago, decision=NULL

**When** `jit_pending_expirer` job runs

**Then** CAS UPDATE jit_pending → `decision='timeout_expired'`, decided_at=now
**And** original Operation done=true с error DEADLINE_EXCEEDED "approval timeout"
**And** audit `iam.jit.activation_timeout`

### 6.4 JIT Auto-Expire

#### Сценарий 7-22: JIT auto-expire via Condition (effective-immediate)

**ID**: `7-22`

**Given** access_binding `acb_xxx` ACTIVE, condition `jit_window`, `expires_at=now+5s`
**And** FGA Check at `now` returns ALLOW

**When** time passes 5s (или test triggers manual clock advance)

**Then** Next FGA Check (same context) returns DENY (Condition `jit_window` evaluates false)
**And** No latency — effective on next request, no wait for job

#### Сценарий 7-23: JIT auto-expire — job updates row + emits events

**ID**: `7-23`

**Given** binding `acb_xxx` ACTIVE, expires_at = now - 1 min
**And** `jit_expirer` job tick

**When** job runs (60s tick)

**Then** CAS UPDATE access_bindings SET status='EXPIRED' WHERE id=acb_xxx AND status='ACTIVE' RETURNING — 1 row
**And** fga_outbox row Delete tuple
**And** caep_outbox row token_claims_change
**And** audit_outbox event `iam.jit.expired`
**And** Subject Bob's UI shows binding as EXPIRED (List filter status=ACTIVE no longer returns acb_xxx)

#### Сценарий 7-24: JIT auto-expire — cache invalidation ≤ 10s

**ID**: `7-24`

**Given** binding expired via job (7-23)

**When** any kacho-service Check для usr_bob_dev на vpc.networks.update for net_yyy

**Then** Check returns DENY (cache invalidated via NOTIFY kacho_iam_subjects within ≤ 10s SLA)
**And** Phase 3 baseline ensures this — Phase 7 just verifies the contract holds for JIT expire

### 6.5 Break-glass Request

#### Сценарий 7-25: Break-glass request — happy path

**ID**: `7-25`

**Given** SRE-on-call `usr_charlie` имеет permission `cluster.break_glass.request` (via SCIM group `kacho-sre-on-call`)
**And** `usr_charlie` имеет fresh acr=3 token
**And** PagerDuty integration enabled (routing key configured)
**And** Slack webhook configured for #security-alerts
**And** email SMTP configured

**When** `usr_charlie` calls `InternalBreakGlassService/RequestBreakGlass` через **internal mux** (admin-UI port-forward or cluster-internal listener) POST `/iam/v1/internal/cluster:requestBreakGlass`:
  - subject_user_id = "usr_charlie"
  - incident_id = "PAG-INC-12345"
  - rationale = "Customer-impact production outage on eu-central network plane. Need cluster-admin для inspect FGA writer state."
  - duration_seconds = 7200

**Then** response = `Operation { id: op_xxx, done: false }`
**And** Polled Operation eventually done=true (after notification fanout completes async — но request itself is synchronously committed)
**And** в `cluster_break_glass_grants` row inserted: `{ id: bgg_xxx, status: 'AWAITING_APPROVAL_A', subject_user_id: usr_charlie, requested_by_user_id: usr_charlie, rationale, expires_at: now+7200s }`
**And** в `audit_outbox` event `iam.break_glass.requested` с full CADF payload
**And** PagerDuty Events API v2 POST called: `event_action=trigger`, `routing_key=$key`, `dedup_key=bgg_xxx`, `payload.severity=critical`, `payload.summary="Break-glass requested: usr_charlie / INC PAG-INC-12345"`, `payload.custom_details={rationale, requested_at, expires_at, subject_user_id}` — returns 202
**And** Slack webhook called: Block Kit message в #security-alerts, thread_ts saved
**And** Email sent to `security@kacho.cloud` с HTML+plaintext template "break_glass_request.html.tmpl"
**And** No access_bindings row yet (grant is NOT active)

#### Сценарий 7-26: Break-glass request — duration > 2h rejected by OPA + DB CHECK

**ID**: `7-26`

**Given** same preconditions

**When** caller passes `duration_seconds = 10800` (3 hours)

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "Illegal argument duration_seconds: break-glass cannot exceed 2 hours" }`
**And** OPA Rego rule `cluster.break_glass.grant.duration_seconds > 7200 → deny` fires
**And** Even if OPA bypassed (e.g. bug), DB CHECK `expires_at <= requested_at + interval '2 hours'` rejects INSERT (23514) → service layer translates to FAILED_PRECONDITION
**And** No row inserted

#### Сценарий 7-27: Break-glass request — empty rationale

**ID**: `7-27`

**Given** caller acr=3, has permission

**When** caller passes `rationale = ""` (or < 20 chars)

**Then** response = HTTP 400 `INVALID_ARGUMENT`, body `{ message: "Illegal argument rationale: must be at least 20 characters" }`
**And** DB CHECK reinforces (length ≥ 20)

#### Сценарий 7-28: Break-glass request — caller lacks permission

**ID**: `7-28`

**Given** `usr_random` НЕ имеет permission `cluster.break_glass.request`

**When** calls `RequestBreakGlass`

**Then** HTTP 403 `PERMISSION_DENIED`, audit emit

#### Сценарий 7-29: Break-glass request — endpoint NOT visible on external TLS

**ID**: `7-29`

**Given** external client `yc`-style CLI hits `https://api.kacho.cloud:443/iam/v1/internal/cluster:requestBreakGlass`

**Then** API gateway returns HTTP 404 NOT FOUND (internal mux not registered on external listener — Phase 7 cross-check verifies endpoint is invisible)
**And** No call reaches kacho-iam
**And** No row inserted, no audit, no notifications

### 6.6 Break-glass Approval Workflow

#### Сценарий 7-30: Approve-A — happy path

**ID**: `7-30`

**Given** bgg `bgg_xxx` in status `AWAITING_APPROVAL_A`
**And** cluster-admin `usr_dana` имеет permission `cluster.break_glass.approve`, acr=3, не равен subject_user_id и не равен requested_by_user_id

**When** `usr_dana` POSTs `/iam/v1/internal/cluster/break-glass/bgg_xxx:approveA`

**Then** response = `Operation { done: true }`
**And** CAS UPDATE cluster_break_glass_grants SET status='AWAITING_APPROVAL_B', approved_by_a=usr_dana, approved_at_a=now WHERE id=bgg_xxx AND status='AWAITING_APPROVAL_A' AND approved_by_a IS NULL RETURNING — 1 row
**And** audit `iam.break_glass.approved_a`
**And** PagerDuty incident updated (note "Approved-A by Dana")
**And** Slack thread reply
**And** Email NOT sent (D8 — emails only on terminal states; ACTIVE and DENIED — yes; approval intermediate — no)

#### Сценарий 7-31: Approve-A — concurrent dual approve (only one wins)

**ID**: `7-31`

**Given** bgg in AWAITING_APPROVAL_A
**And** two cluster-admins both click approveA simultaneously

**When** two requests fire

**Then** ровно одна succeeds (CAS UPDATE returns 1 row); другая returns HTTP 412 `FAILED_PRECONDITION` (`status != AWAITING_APPROVAL_A` after first commit)
**And** integration race-test (testcontainers) запускает 5 concurrent approveA → exactly 1 succeeds

#### Сценарий 7-32: Approve-A — subject tries self-approve

**ID**: `7-32`

**Given** bgg has `subject_user_id=usr_charlie`, status AWAITING_APPROVAL_A
**And** `usr_charlie` тоже имеет `cluster.break_glass.approve` permission (e.g. is cluster-admin)

**When** `usr_charlie` calls approveA

**Then** HTTP 403 `PERMISSION_DENIED`, body `{ message: "subject cannot approve own break-glass grant" }`
**And** DB CHECK constraint `approved_by_a IS NULL OR approved_by_a <> subject_user_id` blocks (defense-in-depth)

#### Сценарий 7-33: Approve-A — requester ≠ approver-A

**ID**: `7-33`

**Given** bgg has `requested_by_user_id=usr_alpha`, subject=usr_charlie

**When** `usr_alpha` calls approveA

**Then** HTTP 403 `PERMISSION_DENIED`, body `{ message: "requester cannot approve own break-glass request" }`

#### Сценарий 7-34: Approve-B — happy path

**ID**: `7-34`

**Given** bgg `bgg_xxx` in `AWAITING_APPROVAL_B`, approved_by_a=usr_dana
**And** cluster-admin `usr_eve` имеет permission, acr=3, не равен subject / requester / approved_by_a

**When** `usr_eve` POSTs `:approveB`

**Then** response = `Operation { done: true }`
**And** CAS UPDATE cluster_break_glass_grants SET status='ACTIVE', approved_by_b=usr_eve, approved_at_b=now WHERE id=bgg_xxx AND status='AWAITING_APPROVAL_B' AND approved_by_b IS NULL AND approved_by_a <> usr_eve RETURNING — 1 row
**And** В `fga_outbox` row Write tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_charlie[break_glass_window(expires_at=<bgg.expires_at>)]`
**And** В `caep_outbox` row event `session_revoked` для usr_charlie (force re-token)
**And** В `audit_outbox` event `iam.break_glass.activated`
**And** Post-incident review tracking issue created (e.g. via YT API or GitHub issue creation), URL written back to bgg row `post_incident_review_issue_url`
**And** PagerDuty incident updated с note "ACTIVATED", severity stays critical
**And** Slack thread "🚨 ACTIVE: emergency_admin granted to usr_charlie until <expires>. Post-incident review: <url>"
**And** Email security@: ACTIVATION SUMMARY (template `break_glass_activated.html.tmpl`)

#### Сценарий 7-35: Approve-B — approver_b == approver_a (rejection)

**ID**: `7-35`

**Given** bgg in AWAITING_APPROVAL_B, approved_by_a=usr_dana
**And** `usr_dana` somehow attempts approveB

**When** `usr_dana` POSTs approveB

**Then** HTTP 412 `FAILED_PRECONDITION`, body `{ message: "second approver must be different from first" }`
**And** CAS UPDATE WHERE approved_by_a <> $caller — 0 rows
**And** DB CHECK `approved_by_a IS NULL OR approved_by_b IS NULL OR approved_by_a <> approved_by_b` reinforces

#### Сценарий 7-36: Deny break-glass at A stage

**ID**: `7-36`

**Given** bgg in AWAITING_APPROVAL_A

**When** `usr_dana` POSTs `:deny` с reason "rationale too vague — please re-request"

**Then** CAS UPDATE status='AWAITING_APPROVAL_A' → 'DENIED', denied_by=usr_dana, denial_reason
**And** Audit `iam.break_glass.denied`
**And** PagerDuty resolve incident with note "DENIED at A by Dana"
**And** Slack thread "❌ DENIED at approval-A by Dana — reason: ..."
**And** Email security@ with denial details (template `break_glass_denied.html.tmpl`)

#### Сценарий 7-37: Deny break-glass at B stage

**ID**: `7-37`

**Given** bgg in AWAITING_APPROVAL_B (already approved-A by Dana)

**When** `usr_eve` POSTs deny с reason

**Then** CAS UPDATE → DENIED
**And** Audit, PagerDuty resolve, Slack thread, email
**And** No fga_outbox / caep_outbox emits (нет grant)

### 6.7 Break-glass Auto-Expire & Revoke

#### Сценарий 7-38: Break-glass auto-expire — Condition denies immediately

**ID**: `7-38`

**Given** bgg ACTIVE с expires_at=now+5s, FGA tuple Write committed
**And** FGA Check for usr_charlie на `cluster.compute.instances.delete` returns ALLOW

**When** 5s elapse

**Then** Next FGA Check returns DENY (Condition `break_glass_window` evaluates false)

#### Сценарий 7-39: Break-glass auto-expire — job updates row + cleanup

**ID**: `7-39`

**Given** bgg ACTIVE, expires_at=now-1min

**When** `break_glass_expirer` job ticks (60s)

**Then** CAS UPDATE status='ACTIVE' → 'EXPIRED' WHERE id=bgg_xxx AND status='ACTIVE' RETURNING — 1 row
**And** fga_outbox Delete tuple
**And** caep_outbox token_claims_change for usr_charlie
**And** audit `iam.break_glass.expired`
**And** PagerDuty incident resolved with note "EXPIRED"
**And** Slack thread "✅ Break-glass expired"
**And** Email security@: EXPIRATION SUMMARY (template)

#### Сценарий 7-40: Break-glass — manual revoke (emergency cancel)

**ID**: `7-40`

**Given** bgg ACTIVE, security team realizes mistake
**And** `usr_admin_alice` имеет permission `cluster.break_glass.revoke`

**When** POST `/iam/v1/internal/cluster/break-glass/bgg_xxx:revoke` с reason

**Then** CAS UPDATE status='ACTIVE' → 'REVOKED', revoked_at=now
**And** Same fanout as expire (delete tuple, caep, audit `iam.break_glass.revoked`, PagerDuty resolve, Slack, email)

#### Сценарий 7-41: Break-glass — single 2-person rule enforced at DB level (defense-in-depth)

**ID**: `7-41`

**Given** Hypothetical attack: developer with DB-direct access tries to INSERT row directly с approved_by_a=usr_x, approved_by_b=usr_x (same user)

**When** INSERT executes against DB

**Then** Postgres rejects с 23514 (CHECK constraint `approved_by_a IS NULL OR approved_by_b IS NULL OR approved_by_a <> approved_by_b`)
**And** Audit log fails to record (no app path), но database log captures the violation
**And** Integration test inserts via raw SQL и asserts CHECK rejects

### 6.8 Break-glass Notifications

#### Сценарий 7-42: PagerDuty integration — incident created with correct dedup_key

**ID**: `7-42`

**Given** Mock PagerDuty server in integration test

**When** Break-glass request flow runs (7-25)

**Then** Recorded PagerDuty request body matches:
  - `routing_key` = configured key (от env)
  - `event_action` = "trigger"
  - `dedup_key` = "bgg_xxx" (grant id)
  - `payload.summary` contains subject + incident_id
  - `payload.severity` = "critical"
  - `payload.source` = "kacho-iam"
  - `payload.custom_details.rationale` = original rationale text
**And** Subsequent state transitions (approveA, approveB, expire) PATCH same incident (event_action=acknowledge / resolve with same dedup_key)

#### Сценарий 7-43: PagerDuty failure — fail-open

**ID**: `7-43`

**Given** PagerDuty endpoint returns 503

**When** Break-glass request flow runs

**Then** Grant request itself still successful (status=AWAITING_APPROVAL_A)
**And** Audit emit `notify.delivery_failed` с `target=pagerduty`, `event=break_glass.requested`, `retries=3`
**And** Test asserts: bgg row exists, notify_delivery_failed audit exists, no exception propagated to user
**And** SIEM (Phase 9) would alert on `notify.delivery_failed` rate > 0

#### Сценарий 7-44: Slack integration — Block Kit shape correct

**ID**: `7-44`

**Given** Mock Slack webhook in test

**When** Break-glass request runs

**Then** Recorded Slack POST body matches:
  - JSON with `channel`, `blocks[]` Block Kit array
  - First block — section "🚨 Break-Glass Requested"
  - Second block — fields с subject_user, requester, rationale, expires_at
  - Action block — buttons "Approve A" / "Deny" с deep-link URLs to UI
  - `thread_ts` initially null (first message)
**And** Slack returns `{ok: true, ts: "1620000000.001234"}`; ts stored для future thread replies
**And** subsequent approve/deny calls Slack с `thread_ts=1620000000.001234`

#### Сценарий 7-45: Email integration — SMTP RFC822 message rendered

**ID**: `7-45`

**Given** Mock SMTP server in test (e.g. `mailhog` или test-double)

**When** Break-glass ACTIVE transition

**Then** Recorded SMTP DATA matches:
  - From: `security-notifications@kacho.cloud` (configured)
  - To: `security@kacho.cloud`
  - Subject: `[Kachō Security] Break-Glass ACTIVATED: usr_charlie / INC-12345`
  - Content-Type: multipart/alternative (text + html)
  - Plaintext body contains rationale, expires_at, approvers
  - HTML body renders template `break_glass_activated.html.tmpl`

#### Сценарий 7-46: Notification dedup — 3 retries don't double-fire

**ID**: `7-46`

**Given** PagerDuty first call returns 500, succeeds on retry

**When** Break-glass request retries

**Then** Mock PD receives 2 calls (1 failure + 1 success); both have same `dedup_key`; PD itself deduplicates
**And** Local dedup cache prevents 3rd call within 5min window (if logic triggers same event)

### 6.9 Break-glass Post-Incident Review

#### Сценарий 7-47: Post-incident review issue auto-created

**ID**: `7-47`

**Given** Break-glass reaches ACTIVE state (7-34)

**Then** YouTrack issue (or GitHub issue if YT integration not configured) created с template:
  - Title: `[Post-Incident Review] Break-Glass usr_charlie / INC PAG-INC-12345`
  - Body: timeline (requested, approved-A, approved-B, expected expire), participants, rationale
  - Labels: `security`, `post-incident-review`
  - Due in 7 days
**And** Issue URL stored в `cluster_break_glass_grants.post_incident_review_issue_url`

#### Сценарий 7-48: PIR escalation — 7-day SLA breached

**ID**: `7-48`

**Given** bgg ACTIVE > 8 days ago, status=EXPIRED, post_incident_review_completed_at IS NULL

**When** `break_glass_review_escalator` daily job runs

**Then** Slack #security-alerts message "⚠️ Overdue post-incident review: <pir-url>"
**And** Email to subject + approvers + their manager
**And** Audit `iam.break_glass.post_incident_review_overdue`
**And** Job idempotent — re-running same day doesn't duplicate (uses last_escalation_sent_at column or similar)

#### Сценарий 7-49: PIR completion marks grant resolved

**ID**: `7-49`

**Given** bgg EXPIRED, PIR issue exists
**And** Admin closes PIR issue via UI / API

**When** Webhook from issue tracker (or polling job) detects closure

**Then** UPDATE cluster_break_glass_grants SET post_incident_review_completed_at=now
**And** Audit `iam.break_glass.post_incident_review_completed`
**And** Escalation job no longer fires for this grant

### 6.10 Access Reviews — Scheduling & Auto-Revoke

#### Сценарий 7-50: Quarterly cron scheduler creates campaigns

**ID**: `7-50`

**Given** 3 active Accounts exist: `acc_alpha`, `acc_beta`, `acc_gamma`
**And** Each account has owner_user_id, и by-default account-admin assigned
**And** Current date = 2026-04-01 00:00 UTC

**When** `access_review_scheduler` job runs (or `InternalAccessReviewService.TriggerSchedulerNow` called)

**Then** 3 rows inserted в `access_reviews`:
  - `(acc_alpha, '2026-Q2', scheduled_at=now, due_at=now+14d, reviewer=acc_alpha.owner_user_id, status='SCHEDULED')`
  - Same for beta, gamma
**And** For each account, `access_review_items` populated с по одному row на каждый ACTIVE access_binding в scope (account-level + project-level bindings on account's projects)
**And** Status updated to IN_PROGRESS after items committed
**And** Email sent to each reviewer
**And** Audit emit `iam.access_review.scheduled` per account
**And** Idempotency: re-running scheduler same day → UNIQUE `(account_id, quarter)` blocks duplicate (23505) → service skips, no new rows

#### Сценарий 7-51: Reviewer lists pending campaigns

**ID**: `7-51`

**Given** reviewer `usr_alpha_owner` has access_review for Q2 2026 на `acc_alpha` со 10 pending items

**When** GET `/iam/v1/accessReviews?reviewer_user_id=self&status=IN_PROGRESS`

**Then** Response = `ListAccessReviewsResponse { reviews: [{ id: arv_xxx, account_id: acc_alpha, quarter: "2026-Q2", item_count: 10, pending_count: 10, due_at: ... }] }`

#### Сценарий 7-52: Reviewer confirms item (keep)

**ID**: `7-52`

**Given** access_review_item `arvi_yyy` в `arv_xxx`, decision=NULL, binding=acb_zzz (vpc_admin on net_aaa)

**When** Reviewer POSTs `/iam/v1/accessReviews/arv_xxx/items/arvi_yyy:confirm` с comment "still needed for Q2 project deliverable"

**Then** Response = `Operation { done: true }`
**And** CAS UPDATE access_review_items SET decision='keep', decision_at=now, decision_by=reviewer, comment WHERE id=arvi_yyy AND decision IS NULL RETURNING — 1 row
**And** access_bindings row `acb_zzz` unchanged (binding stays ACTIVE)
**And** Audit `iam.access_review.confirmed`

#### Сценарий 7-53: Reviewer revokes item

**ID**: `7-53`

**Given** Same starting state

**When** Reviewer POSTs `:revoke` с comment "user left team"

**Then** Response = `Operation { done: true }`
**And** CAS UPDATE access_review_items SET decision='revoke', decision_by, decision_at, comment
**And** CAS UPDATE access_bindings SET status='REVOKED' WHERE id=acb_zzz AND status='ACTIVE' RETURNING — 1 row
**And** fga_outbox row Delete tuple
**And** caep_outbox row token_claims_change for binding subject
**And** Audit `iam.access_review.revoked`

#### Сценарий 7-54: Confirm — double-decision rejected

**ID**: `7-54`

**Given** item arvi_yyy already has decision='keep'

**When** Reviewer attempts second POST :revoke

**Then** HTTP 412 `FAILED_PRECONDITION`, body `{ message: "decision already recorded" }` (CAS UPDATE 0 rows)

#### Сценарий 7-55: Auto-revoke after 14 days — happy path

**ID**: `7-55`

**Given** access_review arv_xxx с due_at = now - 1 day, auto_revoke_unanswered=true, 5 items remain decision=NULL
**And** `access_review_auto_revoke` daily job runs

**When** Job iterates pending items

**Then** For each pending item:
  - CAS UPDATE access_review_items SET decision='expired_auto', decision_at=now
  - CAS UPDATE access_bindings SET status='REVOKED'
  - fga + caep + audit emits per item
**And** Access_review.status='OVERDUE' (until all items decided), then 'COMPLETED'
**And** Email sent to reviewer (and account-owner if different) with summary "5 bindings auto-revoked due to overdue review"

#### Сценарий 7-56: Auto-revoke opt-out per tenant

**ID**: `7-56`

**Given** account `acc_beta` has `access_review_auto_revoke=false` (admin disabled)
**And** Review `arv_beta_q2` due_at < now, 3 items pending

**When** Auto-revoke job runs

**Then** Items NOT auto-revoked
**And** Status updates to `OVERDUE`
**And** Email to reviewer "5 bindings overdue, please review manually"
**And** No audit `iam.access_review.revoked` events for these items

#### Сценарий 7-57: Access review reminder cadence (7d / 3d / 1d before due)

**ID**: `7-57`

**Given** review `arv_xxx` IN_PROGRESS, items pending, due_at = now + 7 days, 3 days, 1 day, respectively

**When** `access_review_reminder` daily job runs

**Then** Email reminder sent at each milestone with current pending counts
**And** Idempotent — same day re-run doesn't duplicate (uses last_reminder_sent_at)

#### Сценарий 7-58: Access review concurrent confirm/revoke race

**ID**: `7-58`

**Given** Two reviewers (account has 2 admins, both assigned as reviewers? — actually 1 reviewer per review by D23, but admin override scenario) somehow both try to act on same item

**When** Concurrent POST `:confirm` from reviewer A and POST `:revoke` from reviewer B

**Then** Exactly one wins (CAS UPDATE first one commits)
**And** Other returns 412 FAILED_PRECONDITION

### 6.11 GDPR Erasure

#### Сценарий 7-59: Request erasure — happy path (self-initiated)

**ID**: `7-59`

**Given** `usr_bob` is normal user (not Account owner), acr=3 token

**When** `usr_bob` POSTs `/iam/v1/gdpr/requestErasure` body `{}` (self-implied)

**Then** Response = `Operation { done: true, response: GdprErasureRequest { id: gdpr_xxx, status: 'cool_off', cool_off_until: now+30d } }`
**And** Row inserted в `gdpr_erasure_requests`
**And** Audit `iam.gdpr.erasure_requested`
**And** Email sent to user.email с confirmation, 30-day timeline, cancel link
**And** UI shows countdown timer

#### Сценарий 7-60: Request erasure — without step-up rejected

**ID**: `7-60`

**Given** user acr=2 only

**When** RequestErasure called

**Then** HTTP 401 UNAUTHENTICATED, `STEP_UP_REQUIRED` (analogous to JIT 7-09)

#### Сценарий 7-61: Request erasure — account owner with active members blocked

**ID**: `7-61`

**Given** `usr_charlie` owns `acc_charlie` со 3 other ACTIVE users in account

**When** `usr_charlie` POSTs requestErasure

**Then** Response = `Operation { done: true, response: GdprErasureRequest { status: 'blocked', block_reason: "Subject owns Account acc_charlie with 3 active members. Transfer ownership before requesting erasure." } }`
**And** Row inserted с status=blocked (kept for audit trail; user can retry after transferring)
**And** Audit `iam.gdpr.erasure_blocked` со cause
**And** Email to user with explanation + link to transfer-ownership UI

#### Сценарий 7-62: Request erasure — duplicate active request rejected

**ID**: `7-62`

**Given** `usr_bob` has existing request in status `cool_off`

**When** `usr_bob` POSTs second requestErasure

**Then** HTTP 409 ALREADY_EXISTS, body `{ message: "active erasure request exists", details: [{ resource_id: "gdpr_xxx", cool_off_until: ... }] }`
**And** Partial UNIQUE `(subject_user_id) WHERE status IN ('cool_off','in_progress')` enforces (23505)

#### Сценарий 7-63: Cancel erasure — within cool-off

**ID**: `7-63`

**Given** request `gdpr_xxx` в status=cool_off, day-15 of 30

**When** `usr_bob` POSTs `/iam/v1/gdpr/{id}:cancelErasure`

**Then** Response = `Operation { done: true }`
**And** CAS UPDATE status='cool_off' → 'cancelled', cancellation_at=now, cancelled_by=usr_bob WHERE id=gdpr_xxx AND status='cool_off' RETURNING — 1 row
**And** Audit `iam.gdpr.erasure_cancelled`
**And** Email confirmation "your erasure request was cancelled"

#### Сценарий 7-64: Cancel erasure — after cool-off expired (too late)

**ID**: `7-64`

**Given** request `gdpr_xxx` status=in_progress (processor already started)

**When** Cancel attempted

**Then** HTTP 412 FAILED_PRECONDITION, body `{ message: "cannot cancel: request already in processing" }` (CAS 0 rows)

#### Сценарий 7-65: Cancel erasure — auto-cancel on user login during cool-off

**ID**: `7-65`

**Given** request `gdpr_xxx` cool_off, user logs in via Passkey on day-5

**When** User session middleware detects active erasure request

**Then** Auto-cancellation triggered: UPDATE status='cancelled', cancelled_by=NULL (system), reason='user_logged_in'
**And** Audit `iam.gdpr.erasure_auto_cancelled`
**And** User shown notification "Your pending erasure was auto-cancelled because you logged in"

#### Сценарий 7-66: GDPR erasure processor — full pipeline happy path

**ID**: `7-66`

**Given** request `gdpr_xxx` cool_off_until = now - 1 hour, status=cool_off, subject usr_bob has 3 ACTIVE access_bindings, 5 ReBAC tuples, Kratos identity exists, email = bob@example.com
**And** No Account ownership block

**When** `gdpr_erasure_processor` daily job runs

**Then** Sequence executed:
  1. UPDATE status='cool_off' → 'in_progress', started_at=now
  2. Re-check ownership block — still clean
  3. UPDATE users SET status='BLOCKED' WHERE id=usr_bob
  4. UPDATE access_bindings SET status='REVOKED' WHERE subject_id=usr_bob AND status='ACTIVE' — 3 rows updated
  5. INSERT fga_outbox: Delete each of 5 tuples
  6. INSERT caep_outbox: session_revoked event
  7. INSERT audit_outbox: iam.gdpr.erasure_in_progress
  8. Send "processing started" email to bob@example.com (BEFORE pseudonymize so email still valid)
  9. UPDATE users SET email='gdpr-erased-<sha256(usr_bob)>', display_name='Erased User' WHERE id=usr_bob
  10. Call Kratos admin API: DELETE /admin/identities/<kratos_id>
  11. INSERT audit_outbox: iam.gdpr.erasure_completed
  12. UPDATE status='completed', completed_at=now
**And** users row exists с pseudonymized email
**And** All bindings revoked
**And** Kratos identity gone (subsequent login impossible)
**And** Audit row retained (audit_retention_until = now + 7y)

#### Сценарий 7-67: GDPR processor — re-check ownership block at processing time

**ID**: `7-67`

**Given** request cool_off → ready to process
**And** During 30-day cool-off, user became owner of new account (state changed)

**When** Processor runs, re-checks ownership

**Then** UPDATE status='in_progress' → 'blocked', block_reason
**And** Email user "erasure paused — please transfer ownership"
**And** Re-enters processing queue daily (job idempotent)

#### Сценарий 7-68: GDPR processor — idempotency on partial failure

**ID**: `7-68`

**Given** request in_progress, processor crashed after step 6 (caep_outbox emit), before step 9 (pseudonymize)

**When** Processor re-runs next day

**Then** Steps идемпотентно re-execute:
  - users.status=BLOCKED already → UPDATE no-op (WHERE status='ACTIVE' filter)
  - access_bindings already REVOKED → 0 rows updated
  - fga_outbox: re-emits OK (drainer dedup by hash)
  - Pseudonymize step proceeds (UPDATE WHERE email NOT LIKE 'gdpr-erased-%')
  - Kratos delete — Kratos returns 404 if already gone, no-op
  - UPDATE status='completed'

#### Сценарий 7-69: GDPR — admin-initiated erasure (on user's behalf, e.g. legal request)

**ID**: `7-69`

**Given** admin `usr_admin_alice` has special permission `iam.gdpr.request_on_behalf`
**And** Target user `usr_legal_person`

**When** admin POSTs `/iam/v1/gdpr/requestErasure { subject_user_id: usr_legal_person }`

**Then** Same flow as 7-59 but `requested_by_user_id = usr_admin_alice`, `subject_user_id = usr_legal_person`
**And** Email goes to BOTH legal_person.email AND admin.email
**And** Audit с both fields

#### Сценарий 7-70: GDPR — audit retention 7 years after pseudonymize

**ID**: `7-70`

**Given** Erasure completed at time T

**When** Query `audit_outbox` (или Phase 9 audit-stream) at T+5y for events related to usr_bob

**Then** All events retained, subject_id still references usr_bob (with pseudonymized email)
**And** `audit_retention_until` on request row = T + 7y
**And** Phase 9 retention job (when deployed) НЕ deletes audit rows before audit_retention_until

### 6.12 Notification & Alerting Integrations

#### Сценарий 7-71: All 3 channels fire on ACTIVE transition

**ID**: `7-71`

**Given** Mock servers для PagerDuty, Slack, SMTP all up

**When** Break-glass reaches ACTIVE (7-34)

**Then** All 3 mocks recorded exactly 1 message each (with `dedup_key=bgg_xxx`, `thread_ts=...`, To=security@)

#### Сценарий 7-72: Slack failure — others still succeed

**ID**: `7-72`

**Given** Slack webhook returns 500

**When** Break-glass flow

**Then** PagerDuty recorded; Email recorded; Slack failed; `notify.delivery_failed` audit emit для Slack only
**And** Grant transition still successful

#### Сценарий 7-73: Email template rendering — Go template safe (no injection)

**ID**: `7-73`

**Given** Break-glass rationale = `"<script>alert(1)</script>"` (malicious input)

**When** Email rendered

**Then** HTML body has `&lt;script&gt;alert(1)&lt;/script&gt;` (auto-escaped by html/template)
**And** Plaintext body has raw text but is plaintext so no XSS

### 6.13 Vault & Documentation

#### Сценарий 7-74: Vault entries created/updated post-merge

**ID**: `7-74`

**Given** Phase 7 PRs merged

**Then** Vault contains:
  - `obsidian/kacho/resources/iam-jit-eligibility.md` (новый, 1-3KB)
  - `obsidian/kacho/resources/iam-break-glass-grant.md` (новый или extended)
  - `obsidian/kacho/resources/iam-access-review.md` (updated с Phase 7 workflow details)
  - `obsidian/kacho/resources/iam-gdpr-erasure-request.md` (новый)
  - `obsidian/kacho/rpc/iam-jit-eligibility-service.md` (новый — method table, REST mapping)
  - `obsidian/kacho/rpc/iam-internal-break-glass-service.md` (новый, помечен internal-only)
  - `obsidian/kacho/rpc/iam-access-review-service.md` (новый)
  - `obsidian/kacho/rpc/iam-gdpr-erasure-service.md` (новый)
  - `obsidian/kacho/packages/corelib-notify.md` (новый)
  - `obsidian/kacho/edges/iam-to-pagerduty.md` (новый)
  - `obsidian/kacho/edges/iam-to-slack.md` (новый)
  - `obsidian/kacho/edges/iam-to-smtp.md` (новый)
  - `obsidian/kacho/KAC/KAC-127.md` (Phase 7 PR-list updated)
**And** Each file 1-3KB, narrow scope per workspace `CLAUDE.md`

---

## 7. Definition of Done (Phase 7)

### Functional

- [ ] **JIT eligibility CRUD** — Create/Update/Delete/Get/List public RPC реализованы, max_duration ≤ 8h enforced на DB CHECK + service validation, immutable fields enforced via update_mask.
- [ ] **ActivateJIT** — public RPC реализован: step-up acr=3 required (Unauthenticated returned otherwise), duration ≤ max_duration validated, duplicate-ACTIVE detection via partial UNIQUE, INSERT access_bindings + fga_outbox + caep_outbox + audit_outbox atomic transaction, jit_window Condition applied.
- [ ] **JIT approval workflow** — pending request table populated when approval_required=true, approver receives Slack DM + email, approve transitions to grant (same atomicity), deny / timeout-expire handled.
- [ ] **JIT auto-expire** — Condition `jit_window` denies effective-immediately; background job `jit_expirer` (60s) transitions ACTIVE → EXPIRED and emits all outbox events.
- [ ] **Break-glass workflow** — Internal RPC `RequestBreakGlass` / `ApproveBreakGlassA` / `ApproveBreakGlassB` / `DenyBreakGlass` / `RevokeBreakGlass` реализованы, registered only on internal mux, 2-person separation of duties enforced via DB CHECK + service validation + CAS UPDATE.
- [ ] **Break-glass duration cap 2h** — OPA Rego deny + DB CHECK (defense-in-depth).
- [ ] **Break-glass auto-expire** — Condition + background job `break_glass_expirer` (60s); manual revoke endpoint реализован.
- [ ] **Break-glass notifications** — PagerDuty incident on request (P1 critical) + state updates + resolve on terminal; Slack #security-alerts threaded messages; email security@ on ACTIVE / DENIED / EXPIRED / REVOKED.
- [ ] **Break-glass PIR** — tracking issue auto-created on ACTIVE, URL stored on bgg row; escalation Slack/email if not resolved in 7 days (job `break_glass_review_escalator`).
- [ ] **Access reviews quarterly** — cron scheduler creates campaigns 4x/year (configurable), items populated, reviewer notified, confirm/revoke endpoints реализованы.
- [ ] **Access review auto-revoke** — daily job revokes pending items after due_at, per-tenant opt-out via `auto_revoke_unanswered` flag.
- [ ] **Access review reminders** — 7d / 3d / 1d email reminders before due_at.
- [ ] **GDPR erasure request** — public RPC with step-up acr=3, 30-day cool-off, email confirmation + reminders, cancel endpoint, account-owner block detection.
- [ ] **GDPR erasure processor** — daily job processes cool-off expired requests, cascades (revoke bindings + delete ReBAC tuples + pseudonymize PII + Kratos delete), idempotent on partial failures.
- [ ] **GDPR audit retention 7y** — audit rows tagged with `audit_retention_until`, NOT deleted before that timestamp.
- [ ] **`corelib/notify`** — PagerDuty, Slack, Email adapters реализованы с retry + exp backoff, in-process dedup, fanout interface, fail-open on individual channel failure.

### Tests / CI (per запрет #11)

- [ ] **kacho-proto** — `buf lint` зелёный, `buf breaking` зелёный (additive only).
- [ ] **kacho-corelib/notify** — unit-tests на каждый adapter с recorded HTTP/SMTP backend; integration smoke test.
- [ ] **kacho-iam integration tests** (testcontainers Postgres):
  - JIT activate happy + duplicate-race (10 concurrent goroutines → exactly 1 succeeds);
  - Break-glass state machine: AWAITING_APPROVAL_A concurrent dual-approve race → exactly 1 wins; B-stage same-as-A approver race blocked at DB CHECK; subject self-approve blocked;
  - Access review concurrent confirm/revoke race → exactly 1 wins;
  - GDPR concurrent cancel-during-processing race → cancel returns FAILED_PRECONDITION if processor already started;
  - GDPR processor idempotency: kill mid-pipeline → re-run completes без duplicate effects;
  - Auto-expire jobs: insert near-expiry rows, advance clock (or short TTL in test), verify EXPIRED transition + outbox emits.
- [ ] **kacho-iam Rego tests** (если расширяются OPA rules): `opa test policies/` зелёный (Phase 3 baseline already has `break-glass max 2h` rule; Phase 7 might add `jit_window present` validation).
- [ ] **kacho-deploy** — `helm template` golden tests pass; secrets templates validate (sealed-secrets / external-secrets CRD).
- [ ] **Newman cases** (`tests/newman/cases/iam_jit_*.py`, `iam_break_glass_*.py`, `iam_access_review_*.py`, `iam_gdpr_*.py`) — happy + negative per RPC, generated via `gen.py`, run в `make e2e-test`:
  - JIT: create eligibility / activate happy / activate without step-up / duplicate ALREADY_EXISTS / duration > max INVALID_ARGUMENT / disabled FAILED_PRECONDITION.
  - Break-glass (via internal-port-forward in test setup): request happy + duration > 2h rejection + approve-A + approve-B with separation of duties + deny + auto-expire.
  - Access review: list pending + confirm + revoke + double-decision rejected.
  - GDPR: request happy + cancel + duplicate ALREADY_EXISTS + owner-block + processor full pipeline (with cool-off shortened for tests via env).
- [ ] **Notification mocks** — tests use recorded HTTP/SMTP backends (no real PagerDuty/Slack/SMTP calls in CI).
- [ ] **CI integration** — `make test-integration && make e2e-test` зелёный.

### Operational

- [ ] **Background jobs** registered в kacho-iam main composition root: jit_expirer, break_glass_expirer, access_review_scheduler, access_review_auto_revoke, access_review_reminder, break_glass_review_escalator, gdpr_erasure_processor, gdpr_reminder, jit_pending_expirer.
- [ ] **Job idempotency** — multi-replica safe (SELECT FOR UPDATE SKIP LOCKED + advisory lock per job-name).
- [ ] **Runbook** `docs/runbooks/break-glass.md` exists в kacho-deploy или kacho-iam: how to request, approve, revoke, troubleshoot, contact escalation list.
- [ ] **Runbook** `docs/runbooks/gdpr-erasure.md` exists: customer-support process for assisting users, admin manual transfer-ownership flow.
- [ ] **PagerDuty integration** configured in prod values (routing key, escalation policy linked).
- [ ] **Slack channel** `#security-alerts` created и webhook configured.
- [ ] **Email** `security-notifications@kacho.cloud` provisioned (SMTP creds or SES IAM role).

### Security / Compliance

- [ ] **Step-up acr=3 enforced** on: `ActivateJIT`, all `InternalBreakGlassService` RPCs, all `GdprErasureService` mutations, `AccessReviewService` revoke (confirm — acr=2 OK).
- [ ] **Internal RPCs not exposed on external endpoint** — verification test in api-gateway integration suite: `https://api.kacho.local/iam/v1/internal/...` returns 404.
- [ ] **DB CHECK constraints** on critical invariants: break-glass duration ≤ 2h, 2-person separation, approver-not-subject, approver-not-requester.
- [ ] **Audit retention** — `audit_retention_until` column populated on all Phase 7 events, default 7 years.
- [ ] **PagerDuty / Slack / Email failures fail-open** — main flow not blocked; audit notes failure.
- [ ] **No secrets in code / Helm values** — все credentials через Sealed Secrets / External Secrets.

### Documentation

- [ ] **This document** approved by `acceptance-reviewer`.
- [ ] **YouTrack subtasks** created per Phase 7 task (7.1-7.8) and linked to KAC-123 epic + this acceptance.
- [ ] **Vault updates** — все entries из §6.13 created/updated.
- [ ] **API reference** in `kacho-proto` proto files — comprehensive godoc.

### Code Quality (no tech debt)

- [ ] Clean Architecture respected: domain (self-validating types), service (use-cases, ports), repo/clients (adapters), handler (thin transport).
- [ ] sqlc + handwritten pgx; no ORM (запрет #3).
- [ ] No "yandex" mentions (запрет #2).
- [ ] All cross-service operations through edge-helpers (notify package) — no inline HTTP клиент code in handlers.

---

## 8. Cross-Repo PR Chain (топологический порядок merge)

```
1. kacho-proto                   ← new services protobufs (JITEligibility, ActivateJIT extension,
   PR #1                            InternalBreakGlass, AccessReview, GdprErasure)
                                    Tests: buf lint + buf breaking + golden generated Go stubs
                                    Reviewer: proto-api-reviewer
                                    Merge → triggers downstream CI

2. kacho-corelib                 ← corelib/notify package (PagerDuty + Slack + Email + Fanout +
   PR #2                            Dedup + Testing Recorder)
                                    Tests: unit-tests на каждый adapter, race-free dedup test
                                    Reviewer: go-style-reviewer
                                    Merge → after PR #1 if any cross-import (нет в Phase 7)

3. kacho-iam                     ← domain + service + repo + jobs + handlers (per §5.3)
   PR #3                            + migration 0021 (indexes + access_bindings_jit_pending table)
                                    Tests: integration tests (testcontainers) + unit + race-tests
                                    Reviewers: rpc-implementer, db-architect-reviewer, go-style-reviewer
                                    Merge → after PR #1 + PR #2

4. kacho-api-gateway             ← mux extension: public + internal-mux registration
   PR #4                            Tests: integration smoke + verify internal not on external listener
                                    Reviewer: api-gateway-registrar
                                    Merge → after PR #3

5. kacho-deploy                  ← Helm values + Sealed Secrets templates + CronJobs (if external sched)
   PR #5                            + runbooks/break-glass.md, gdpr-erasure.md
                                    Tests: helm template golden tests + helmfile lint
                                    Reviewer: deploy-author (или general)
                                    Merge → after PR #3 + PR #4

6. kacho-ui                      ← Vite/React pages per §5.6
   PR #6                            Tests: component tests + Playwright e2e (smoke)
                                    Reviewer: ui-author
                                    Merge → after PR #4 (UI uses public+internal mux through proxy)

7. kacho-workspace               ← vault updates (12+ files) + KAC-127.md PRs added
   PR #7                            No code; doc-only PR
                                    Reviewer: acceptance-author (или acceptance-reviewer)
                                    Merge → last
```

Each PR ссылается на `KAC-127` (vault label) + `KAC-123` (YT epic) + specific Phase-7 subtask KAC-N.

---

## 9. Out of scope (Phase 7) — НЕ deferred, just other Phases

- **CAEP push pipeline delivery** — Phase 8. Phase 7 пишет в `caep_outbox`, drainer (HTTP push с SET signing + retry + subscriber registry) — Phase 8.
- **Audit pipeline full** — Phase 9. Phase 7 пишет в `audit_outbox`, Kafka producer + ClickHouse consumer + S3 batch writer + HSM signing + SIEM forwarders + detection rules — Phase 9.
- **SPIFFE/SPIRE in-cluster + Cilium mesh** — Phase 10.
- **Multi-region active-active + Argo CD + Grafana + Alertmanager + RTO/RPO** — Phase 11.
- **OWASP ASVS L3 + chaos + pentest engagement** — Phase 12.
- **Vault closeout (30+ files final pass)** — Phase 13.

**Inside-Phase-7 deferrals**: НЕТ — production edition без deferrals (per round 2 feedback). Все feature и tests, перечисленные в §6 и §7 — обязательны для DoD.

---

## 10. Open questions — РЕШЕНО (нет открытых)

Все вопросы Phase 7 закрыты в §3 Decision Log P7-D1..P7-D28. Если ревьюер обнаружит unclear место — поднимает в `acceptance-reviewer` round, итерируем до APPROVED.

Конкретные «micro-question» декларативы, на которые часто спрашивают и ответ зафиксирован:

| Вопрос | Ответ (где) |
|---|---|
| JIT pending table — нужна или нет? | Да, отдельная `access_bindings_jit_pending` (P7-D3 + миграция 0021) |
| Break-glass max duration — 1h or 2h? | 2h (P7-D5) |
| Кто approver A vs B? | Любые 2 cluster-admin (P7-D4); separation enforced на DB |
| Post-incident review tracker — YT или GitHub? | Configurable, default YT (см. helm values) |
| Access review cadence — quarterly fixed dates? | 1 Jan / 1 Apr / 1 Jul / 1 Oct UTC 00:00 (P7-D12); per-tenant override deferred to Phase 11 |
| Access review reviewer assignment — owner or admin? | Account owner default + admin override (P7-D23) |
| GDPR cool-off — 30 days? | Да (P7-D14); auto-cancel on login during cool-off (7-65) |
| GDPR pseudonym format? | `gdpr-erased-<sha256(user_id_hex)>` (P7-D15) |
| Email auto-cancellation on logon — bug or feature? | Feature (7-65) — implicit consent to keep account |
| Account owner block — strict requirement? | Strict; manual transfer required (P7-D16) |
| Notification failures — fail-open? | Yes (P7-D17); audit emit `notify.delivery_failed` |
| In-process jobs или K8s CronJob? | In-process goroutines per запрет #7 (см. §5.5); idempotent via advisory locks |
| Notify retry — sync queue or async? | Bounded in-process retry queue, 3 retries exp backoff (P7-D18) |
| Slack approval buttons — clickable from Slack? | НЕТ; deep-link в UI с step-up flow only (P7-D7) |
| Email transport — SMTP / SES? | Interface; both configurable per env (P7-D21) |

---

**End of acceptance document.**

> **Reviewer note**: per workspace `CLAUDE.md` запрет #1, кодирование Phase 7 не начинается до `acceptance-reviewer` APPROVED stamp. Этот документ — gate. Round 2 feedback "production edition, no strict backward-compat" учтён.
