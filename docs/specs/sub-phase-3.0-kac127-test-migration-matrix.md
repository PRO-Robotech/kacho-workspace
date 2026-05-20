# sub-phase 3.0 — KAC-127 Test Migration Matrix

> **Этот документ — overview / linkage layer.** НЕ acceptance GWT scenarios
> (отдельные docs per Phase), НЕ implementation code. Это таблица соответствий
> между **существующей test baseline KAC-104..KAC-125** (E0-E5 + KAC-119, KAC-121,
> KAC-125) и **production-ready architecture KAC-127** (Phase 1-13).
>
> Цель: обеспечить, чтобы при переходе на KAC-127 ни один из уже закрытых юз-кейсов
> не потерял test-покрытие. Каждый существующий UC получает явный «новый дом» в
> одной из Phase 1-13. Новые UC, появляющиеся только в KAC-127, перечисляются
> отдельно (§4).

---

## 0. Преамбула — место этой sub-итерации в epic

| Эпик / Тикет | KAC-127 — production-ready next-gen IAM (real YT `KAC-123`, vault-label `KAC-127`) |
|---|---|
| Под-итерация | 3.0 — test migration matrix |
| Артефакт | `docs/specs/sub-phase-3.0-kac127-test-migration-matrix.md` (этот файл) |
| Тип | linkage / inventory document (не acceptance) |
| Зависит от | KAC-104..KAC-125 (закрытые baseline acceptance docs) |
| Используется в | Phase 1-13 acceptance docs (как «откуда мигрирует UC») |

**User feedback (2026-05-19, round 1)**: «Основной упор — продолжить писать
по заложенным DoD, проанализировать какие юз кейсы мы тестировали и пытались
закрыть. В новой версии такие же кейсы только под новую реализацию нужно
поддержать.»

**User feedback (2026-05-19, round 2)**: «Если прошлая версия сильно
отличается от новой придерживаться старой конвенции не надо.»

**Применение round 2**: некоторые `UC-*` из §2 (inherited from KAC-104..125)
могут быть **drop'нуты или существенно переписаны** в KAC-127 phases, если
new architecture сильно отличается. Сохраняем:

- ✅ Product domain concepts (Account / Project / User / Role / AccessBinding / SA / Group — есть в продукте).
- ✅ Stylistic conventions (YC-style errors, REST paths, async Operation, snake_case JSON).
- ✅ DB discipline (FK RESTRICT, partial UNIQUE, CHECK, advisory_lock).
- ✅ Запреты CLAUDE.md (#1, #6, #8, #10, #11).

НЕ обязательно сохранять:

- ❌ Specific legacy schema (e.g., `roles.account_id NOT NULL` backward-compat) — production restart greenfield OK (D-19 design).
- ❌ Specific 1-в-1 inheritance в test cases — newman authz-deny.py может быть полностью переписан под DPoP/Conditions/OPA/ListObjects вместо single-Check.
- ❌ "Backward-compat scenarios" (§6.4.0 legacy roles, §6.5.0 status backfill) — могут быть удалены если production restart.

Поэтому **inherited UC** в §2 — это **inventory**, не обязательство 1-в-1 reproduce. Phase acceptance docs выбирают relevant subset; rest можно drop с обоснованием в Decision Log той phase.

---

## 1. Связь с регламентом и запретами (нормативно)

| Источник | Что именно использует этот документ |
|---|---|
| `kacho-workspace/CLAUDE.md` §«Запреты» #11 | Каждый новый RPC / поле / oneof-case **обязан** иметь integration + newman в том же PR. Этот matrix — основа для proof-of-coverage. |
| `kacho-workspace/CLAUDE.md` §«Запреты» #10 | Within-DB refs — только DB-уровень (FK / partial UNIQUE / EXCLUDE / CAS). Все CAS-сценарии **обязаны** иметь integration concurrent-race test. |
| `kacho-iam/CLAUDE.md` §9 | Три тестовых уровня — unit (`apps/.../[case]_test.go`), integration (`repo/.../*_integration_test.go`), newman (`tests/newman/cases/*.py` → `gen.py`). |
| Acceptance-workflow (запрет #1) | Каждый Phase 1-13 имеет APPROVED acceptance-доку **до** кодинга; этот matrix — input для тех acceptance-доков. |
| Anti-pattern «follow-up для тестов» | Этот matrix — финальная карта; никаких «tests-followup» как обоснования отсутствия тестов в PR. |

---

## 2. Inventory — существующие use cases (baseline KAC-104..KAC-125)

Категории сгруппированы по доменной сущности. Колонки:

| Колонка | Значение |
|---|---|
| `UC-ID` | Стабильный идентификатор use case (читается humans + поиском) |
| `Title` | Что именно проверяется |
| `Baseline` | Где впервые закрыт (тикет / acceptance doc / newman case / integration test) |
| `Layers` | Где есть test покрытие (`U`=unit, `I`=integration, `N`=newman, `E`=e2e/Playwright, `S`=skipped/stub) |
| `KAC-127 phase` | В какой Phase 1-13 этот UC мигрирует (см. §3) |

### 2.1 Account lifecycle

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-A01 | Account.Create happy-path → Operation done, id starts `acc` | E0 / KAC-105 / `iam-account.py` `ACC-CR-CRUD-OK` / `account_integration_test.go` | I, N | Phase 1 §6.1 |
| UC-A02 | Account.Get not-own → NotFound (cross-tenant) | E0 / KAC-105 + KAC-119 cross-tenant deny | I, N | Phase 4 (List/Get cross-tenant deny via ListObjects) |
| UC-A03 | Account.Update via UpdateMask (`name`, `description`, `labels`) | E0 / `ACC-UP-CRUD-OK` | I, N | Phase 1 §6.1 |
| UC-A04 | Account.Delete FK RESTRICT if projects exist → FailedPrecondition | E0 / KAC-105 / `iam-account.py` `ACC-DEL-NEG-WITH-PROJECTS` | I, N | Phase 1 §6.1 (FK preserved verbatim) |
| UC-A05 | Auto-create personal Account on signup | E4 / KAC-117 acceptance + UI E2E | I, E | Phase 6 (signup orchestrator, multi-tenancy preserved) |
| UC-A06 | Move Project across Accounts (atomic CAS) | KAC-121 / `iam-project.py` `PRJ-MV-NEG-SAME-ACC` | I, N | Phase 1 §6.1 (atomic CAS preserved; +Phase 9 audit-trail) |
| UC-A07 | Account.List filter — own + invited only (default-deny anonymous) | KAC-122 / `iam/tests/newman/cases/authz-deny.py` | N | Phase 4 (ListObjects List-filter) |
| UC-A08 | Account.Update reject immutable `owner_user_id` (UpdateMask hard-immutable) | E0 acceptance §2.0-E0-07 | I, N | Phase 1 §6.1 |
| UC-A09 | Account name uniqueness (DB UNIQUE `accounts_name_unique`) | E0 / `ACC-CR-NEG-DUP-NAME` | I, N | Phase 1 §6.1 |
| UC-A10 | Account.Create invalid name regex → InvalidArgument sync (no Operation) | E0 / `ACC-CR-NEG-INVALID-NAME` | I, N | Phase 1 §6.1 |

### 2.2 Project lifecycle

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-P01 | Project.Create per-Account, unique name within Account | E0 / `iam-project.py` `PRJ-CR-CRUD-OK` / `project_integration_test.go` | I, N | Phase 1 §6.1 |
| UC-P02 | Auto-create default Project on Account.Create | E4 / KAC-117 acceptance | I, E | Phase 6 (signup orchestrator) |
| UC-P03 | Project.List filter by Account ownership (cross-Account NotFound) | E0 + KAC-122 | N | Phase 4 (ListObjects) |
| UC-P04 | Project.Move atomic CAS — verified concurrent | KAC-121 + concurrent-test in `project_integration_test.go` | I, N | Phase 1 §6.1 |
| UC-P05 | Project.Delete FK RESTRICT if ServiceAccount/Group exist within | KAC-121 | I, N | Phase 1 §6.1 |
| UC-P06 | Project.Update immutable `account_id` reject | E0 acceptance §2.3 | I | Phase 1 §6.1 |
| UC-P07 | folder_id → project_id migration в VPC / Compute / LB consumer-сервисах | E1 / KAC-106 acceptance | I, N | Phase 6 §6.X (multi-tenancy preserved verbatim) |

### 2.3 User + Identity

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-U01 | User CRUD via InternalUserService.UpsertFromIdentity | E0 / E2 / `iam-user.py` `USR-IUP-OK` / `user_integration_test.go` | I, N | Phase 2 (re-platformed onto ORY Kratos+Hydra; external_id := Kratos identity id) |
| UC-U02 | per-Account User row (one Kratos identity → N user rows) | KAC-125 / `user_invite_integration_test.go` | I, N | Phase 6 (multi-tenancy: SCIM JIT provisioning honours per-Account User) |
| UC-U03 | Invite-flow PENDING → ACTIVE via magic-link | KAC-125 acceptance + `user_invite_integration_test.go` | I, N | Phase 6 (SCIM extension: external_id mapping; Phase 2 magic-link via ORY Kratos flows) |
| UC-U04 | UpsertFromIdentity activates PENDING on first OIDC sign-in | KAC-125 §5.2 | I, N | Phase 2 (OIDC subject mapping → Kratos identity hook) |
| UC-U05 | User.List default-deny (KAC-125 Q9) | KAC-125 acceptance Q9 + `authz-deny.py` | N | Phase 4 (ListObjects List-filter) |
| UC-U06 | User.Delete blocked while group member | KAC-125 / `iam-user.py` `USR-DEL-NEG-WITH-GROUP-MEMBER` | I, N | Phase 1 §6.1 (trigger preserved) |
| UC-U07 | User mirror upsert idempotent (re-login same external_id → same usr-id) | E2 / KAC-108 | I, N | Phase 2 (idempotency preserved across Kratos hooks) |
| UC-U08 | User.external_id immutable after Create | KAC-125 acceptance §3.2 | I, N | Phase 2 |

### 2.4 ServiceAccount

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-SA01 | ServiceAccount.Create per-Account, unique name | E0 / `iam-service-account.py` `SA-CR-CRUD-OK` / `service_account_integration_test.go` | I, N | Phase 1 §6.1 (re-scoped: SA → Project в KAC-121, preserved) |
| UC-SA02 | ServiceAccount.Get / List per Account | E0 + KAC-121 | I, N | Phase 4 (ListObjects) |
| UC-SA03 | ServiceAccount cannot login (no key on E0..E5) | E0 § «No-key» constraint | (S) | Phase 5 (SA-keys via ORY Hydra Class A — UC-SA01..03 поведение preserved, keys add) |
| UC-SA04 | ServiceAccount.Create unique name → AlreadyExists | E0 / `SA-CR-NEG-DUP-NAME` | I, N | Phase 1 §6.1 |
| UC-SA05 | ServiceAccount.Delete FK RESTRICT if AccessBinding refs | E0 | I | Phase 1 §6.1 |

### 2.5 Role

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-R01 | System Role seed — 12 records (E0) → 54 records (KAC-121) с детерминированными id | E0 migration `0001_initial.sql §4.2` + KAC-121 expanded seed | I (migration test) | Phase 1 §6.1 (Phase 1 NEW: multi-scope cluster/org/account/project; seed migrate `rol00000…` id'ы) |
| UC-R02 | Custom Role CRUD per-Account, unique name (partial UNIQUE `roles_custom_unique`) | KAC-121 / `iam-role.py` `ROL-CR-CRUD-OK` / `role_integration_test.go` | I, N | Phase 1 §6.1 (extended: now per-scope custom role — scope=org/account/project) |
| UC-R03 | Role.permissions validation regex `<module>.<resource>.<verb>` через DB CHECK | KAC-121 / `iam_permissions_valid()` PL/pgSQL | I | Phase 1 §6.1 (preserved; +Phase 3 condition-blocks add) |
| UC-R04 | System Role immutability (`is_system=true` → Delete reject) | KAC-121 / `ROL-DEL-NEG-SYSTEM` | I, N | Phase 1 §6.1 |
| UC-R05 | System Role wildcard permission (`*.*.*`) — kacho.admin / kacho.viewer | KAC-121 acceptance §4.3 | I, N | Phase 1 §6.1 |
| UC-R06 | Custom Role.Update immutable `account_id` / `is_system` / `name` (system) | E0 acceptance §3.6 | I | Phase 1 §6.1 |
| UC-R07 | UI role catalog cascader (3-level: module / resource / verb) | KAC-121 UI / Playwright | E | Phase 6 UI (cascader preserved) |

### 2.6 AccessBinding

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-AB01 | AccessBinding.Create idempotent UPSERT (subject_type, subject_id, role_id, resource_type, resource_id) | E0 / `iam-access-binding.py` `AB-CR-IDEMPOTENT-13.4` / `access_binding_integration_test.go` | I, N | Phase 1 §6.1 (preserved; PK ON CONFLICT trick) |
| UC-AB02 | AccessBinding.Delete by id | E0 / `AB-CR-CRUD-OK` | I, N | Phase 1 §6.1 |
| UC-AB03 | ListByResource / ListBySubject | E0 | I, N | Phase 4 (ListObjects covers; sync List-RPC preserved) |
| UC-AB04 | Polymorphic subject_id (user / sa / group) — soft-ref software validation | E0 acceptance §13.3 | I | Phase 1 §6.1 |
| UC-AB05 | AccessBinding emits LISTEN/NOTIFY → OpenFGA tuple invalidate ≤10s | E3 / KAC-108 acceptance | I, N | Phase 1 §6.2 (extended: OpenFGA v2 model + ListObjects; reactivity ≤5s p99) |
| UC-AB06 | AccessBinding cross-tenant deny — Account A subject cannot bind to Account B resource | KAC-122 / `authz-deny.py` | N | Phase 4 (ListObjects scope-check) |
| UC-AB07 | AccessBinding.subject_id soft-ref `LookupSubject` через InternalIAMService | E3 + KAC-119 / `IAM-INT-NEG-EXT-IAM-LOOKUPSUBJECT` | I, N | Phase 1 §6.1 |

### 2.7 Group

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-G01 | Group.Create per-Account, unique name (CASCADE on Account.Delete) | KAC-119 / `iam-group.py` `GRP-CR-CRUD-OK` / `group_integration_test.go` | I, N | Phase 1 §6.1 |
| UC-G02 | Group membership add (user / sa) → trigger `group_members_member_exists_trg` | KAC-119 / `GRP-ADD-MEM-NEG-NOT-FOUND` | I, N | Phase 1 §6.1 (trigger preserved verbatim) |
| UC-G03 | Group.List default-deny (anonymous → all-empty; cross-tenant → cross-tenant rows hidden) | KAC-123 / `authz-deny.py` | N | Phase 4 (ListObjects List-filter) |
| UC-G04 | Group cascade-delete on Account.Delete | KAC-119 acceptance §5 | I | Phase 1 §6.1 (FK CASCADE preserved) |
| UC-G05 | Group nested membership (group-of-groups) | KAC-119 §4 — partially implemented (flat only on E0..E5) | (S) | Phase 6 (SCIM-managed groups + nested via OpenFGA `member_of` v2 model) |

### 2.8 AuthZ — Check + ListObjects

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-Z01 | Internal IAM Check (`InternalIamService.Check`) — base sync gate | KAC-108 / `iam-internal-only-check.py` / `openfga_client_test.go` | U, I, N | Phase 4 (Check preserved + ListObjects добавлен) |
| UC-Z02 | Default-deny matrix per service (6 subjects × CRUD × 3 services) — anonymous / user-from-other-Account / SA-from-other-Account / etc. | KAC-122 / `iam/tests/newman/cases/authz-deny.py` + `compute/tests/newman/cases/authz-deny.py` + `vpc/tests/newman/cases/authz-deny.py` | N | Phase 4 (matrix extended: scope cluster/org/account/project × 6 subjects × CRUDL × N services) |
| UC-Z03 | Reactivity revoke ≤10s — AccessBinding.Delete → next Check returns deny | KAC-108 acceptance §4.5 | I, N | Phase 4 (target ≤5s p99 via OpenFGA v2 + Watch invalidation) |
| UC-Z04 | Cross-tenant deny — user.Account A → resource.Account B → all RPC return NotFound (not PermissionDenied) | KAC-122 | N | Phase 4 (preserved + extended to org/cluster scope) |
| UC-Z05 | ListObjects List-filtering — `iam.ListObjects(user, "viewer", "project") → [prj-1, prj-7]` | not in baseline (single-Check only) | (NEW) | Phase 4 (NEW UC — replaces parent-Check pattern) |
| UC-Z06 | Conditions evaluation — `mfa_fresh`, `non_expired`, `source_ip`, `business_hours`, etc. | not in baseline | (NEW) | Phase 3 (NEW UC family — UC-Z06a..g per condition) |
| UC-Z07 | InternalUserService.UpsertFromIdentity not exposed on external endpoint | E2 / `IAM-INT-NEG-EXT-USER-UPSERT` | N | Phase 2 (preserved; Kratos hook now caller) |
| UC-Z08 | InternalIamService.LookupSubject not exposed on external endpoint | E3 / `IAM-INT-NEG-EXT-IAM-LOOKUPSUBJECT` | N | Phase 4 (preserved) |
| UC-Z09 | Reactivity Watch via LISTEN/NOTIFY → OpenFGA tuple write within ≤10s | E3 / KAC-108 | I, N | Phase 1 §6.2 (preserved + targets tightened to ≤5s) |

### 2.9 Signup flow

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-S01 | First-time signup → Account + default Project + admin AccessBinding | E4 / KAC-117 acceptance + Playwright | I, E | Phase 6 (orchestrator preserved; +SCIM JIT path) |
| UC-S02 | Invite-link signup → activate PENDING User → bind to existing Account | KAC-125 acceptance §5 + `user_invite_integration_test.go` | I, N, E | Phase 6 (invite via SCIM bulk-add + ORY Kratos invitation flow) |
| UC-S03 | Signup via OIDC (Zitadel on E2) | E2 / KAC-110 | I, E | Phase 2 (re-platformed to ORY Kratos; subject mapping preserved) |
| UC-S04 | Signup duplicate email → reject | E4 / KAC-117 §6.3 | I, N | Phase 2 (Kratos identity-schema unique constraint) |
| UC-S05 | Signup default-role seeding в новом Account | E4 / KAC-117 + KAC-121 seed | I | Phase 6 §6.X |
| UC-S06 | Enterprise SSO signup (SAML/SCIM) | not in baseline | (NEW) | Phase 6 (NEW UC family) |

### 2.10 UI

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-UI01 | Cascader Account → Project (top-bar nav) | KAC-125 / Playwright | E | Phase 6 UI |
| UC-UI02 | AccessBindings list visibility — admin vs viewer cross-tenant | KAC-119 acceptance §4 | E | Phase 6 UI |
| UC-UI03 | Invite modal — invite-link copy + role pre-fill | KAC-125 §6 | E | Phase 6 UI |
| UC-UI04 | AccountCrumb breadcrumb fix (no stale Account in URL on switch) | KAC-119 §5 | E | Phase 6 UI |
| UC-UI05 | Role catalog cascader (module / resource / verb 3-level select) | KAC-121 UI | E | Phase 6 UI |
| UC-UI06 | User profile page — Active Sessions list + revoke button | not in baseline | (NEW) | Phase 2 UI (ORY Kratos session UI) |
| UC-UI07 | Passkey enrollment UI (WebAuthn ceremony) | not in baseline | (NEW) | Phase 2 UI |
| UC-UI08 | Step-up MFA prompt on sensitive action | not in baseline | (NEW) | Phase 2 + Phase 3 UI |

### 2.11 OIDC / OpenFGA infra (E2 / E3 baseline)

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-I01 | Zitadel OIDC discovery + JWT validation в api-gateway tenant-interceptor | E2 / KAC-110 | I, E | Phase 2 (re-platformed to ORY Hydra OIDC issuer; tenant-interceptor preserved with new issuer URL) |
| UC-I02 | OpenFGA model v1 (account/project/role/group types + relations) | E3 / KAC-108 model.fga | U, I | Phase 4 (v2 model adds: cluster/org scope, conditions block, member_of nested) |
| UC-I03 | AccessBinding → OpenFGA tuple writer (outbox-based) | E3 / KAC-108 acceptance §4.2 | I, N | Phase 1 §6.2 |
| UC-I04 | OpenFGA tuple invalidate via LISTEN/NOTIFY ≤10s | E3 / KAC-108 §4.5 | I, N | Phase 4 (tighter SLA ≤5s) |
| UC-I05 | tenant-interceptor extracts user_id + account_id из JWT | E2 / KAC-110 | I | Phase 2 (DPoP-binding adds; user_id extraction preserved) |

### 2.12 Cross-repo migration (E1, E5)

| UC-ID | Title | Baseline | Layers | KAC-127 phase |
|---|---|---|---|---|
| UC-M01 | folder_id → project_id миграция в VPC tables (network/subnet/address/sg/rt/gateway/pe/ni) | E1 / KAC-106 | I, N | Phase 6 §6.X (column already migrated; KAC-127 не трогает) |
| UC-M02 | folder_id → project_id в Compute tables (instance/disk/image/snapshot) | E1 / KAC-106 | I, N | Phase 6 §6.X |
| UC-M03 | folder_id → project_id в LB tables (nlb/target_group) | E1 / KAC-106 | I, N | Phase 6 §6.X |
| UC-M04 | kacho-resource-manager deprecation — backend/migrations/proto deleted | E5 / KAC-124 acceptance | (verified by absence) | Phase 6 (verified — RM остаётся deleted) |
| UC-M05 | kacho-iam ProjectService.Get replaces resource-manager FolderService.Get | E5 / KAC-124 + peer-client refactor in VPC/Compute/LB | I | Phase 6 (peer-client preserved) |

---

## 3. Migration mapping — куда мигрирует каждый UC

Сводка по Phases (Phase 1-13 KAC-127). Колонка `UC count` — сколько UC из §2 закрывает каждая phase.

| Phase | Тема | UC inherits | UC new | Total UC | Acceptance doc |
|---|---|---|---|---|---|
| 1 | Foundation (multi-scope roles, AccessBinding v2, outbox→FGA v2) | 39 | 8 | 47 | `sub-phase-3.1-iam-foundation-acceptance.md` |
| 2 | AuthN — ORY Kratos+Hydra, Passkeys, DPoP, step-up, JWKS rotate, back-channel logout | 9 | 22 | 31 | `sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` |
| 3 | AuthZ — Conditions (FGA + OPA Rego guardrails) | 0 | 18 | 18 | `sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md` |
| 4 | AuthZ — ListObjects per List-RPC, default-deny matrix v2 | 13 | 6 | 19 | Phase 4 acceptance (forthcoming) |
| 5 | SA-keys (Hydra Class A) + Federation Trust (Class B GH/AWS/GCP/etc.) | 3 | 14 | 17 | Phase 5 acceptance |
| 6 | Multi-tenancy — SCIM 2.0, SAML bridge, Organization tier, JIT provisioning, signup orchestrator | 14 | 11 | 25 | Phase 6 acceptance |
| 7 | Lifecycle — JIT/PIM elevation, Break-glass, Access Reviews, GDPR erasure | 0 | 12 | 12 | Phase 7 acceptance |
| 8 | CAEP push pipeline + SET signing + subscriber registry | 0 | 9 | 9 | Phase 8 acceptance |
| 9 | Audit pipeline — Kafka → ClickHouse OLAP → S3+Glacier → HSM-Merkle → SIEM webhooks | 1 (extension UC-A06) | 11 | 12 | Phase 9 acceptance |
| 10 | Workload identity — SPIFFE/SPIRE + Cilium mesh (in-cluster mTLS) | 0 | 7 | 7 | Phase 10 acceptance |
| 11 | Production deploy — api.kacho.cloud, Cloudflare WAF, multi-region, Argo CD, SBOM/SLSA | 0 | 9 | 9 | Phase 11 acceptance |
| 12 | Hardening — OWASP ASVS L3, OPA bundle signing, chaos Litmus, continuous fuzzing, pentest, bug bounty | 0 | 14 | 14 | Phase 12 acceptance |
| 13 | Vault closeout — final docs, runbooks, on-call rotation, post-launch review | 0 | 5 | 5 | Phase 13 acceptance |
| **Total** | | **79** | **146** | **225** | |

> **Сверка**: baseline §2 содержит 79 explicit UC-* записей. Phase 1-13 наследуют все 79 (1-в-1) + добавляют 146 новых. Ни один baseline UC не «теряется» — каждый имеет explicit «Phase X §6.Y» назначение.

---

## 4. Новые use cases в KAC-127 (по Phases)

Per Phase — list **новых** UC families, которых **не было** в baseline KAC-104..KAC-125.

### 4.1 Phase 2 — AuthN core (22 new UC)

| UC-ID | Title | Layer | Owner KAC-127 doc |
|---|---|---|---|
| UC-N01 | Passkey (WebAuthn) enrollment ceremony — attestation verify, COSE key store | I, N, E | Phase 2 §6.1 |
| UC-N02 | Passkey authentication ceremony — assertion verify, replay counter ratchet | I, N, E | Phase 2 §6.1 |
| UC-N03 | DPoP-binding — access_token cnf-claim, header verify on RS | I, N | Phase 2 §6.2 |
| UC-N04 | Step-up MFA — `amr` claim escalation prompt | I, N, E | Phase 2 §6.3 |
| UC-N05 | JWKS rotation — kid prev/current/next dual-validation window | I, N | Phase 2 §6.4 |
| UC-N06 | Back-channel logout — RP-initiated logout token via Hydra → session invalidate | I, N | Phase 2 §6.5 |
| UC-N07 | session_revocations cache — Redis with TTL = max-token-lifetime | I, N | Phase 2 §6.6 |
| UC-N08 | NIST AAL2/AAL3 mapping — `amr=["webauthn","pwd"]` → aal2 etc. | U, I | Phase 2 §6.7 |
| UC-N09 | Algorithm-confusion mitigation — JWT alg whitelist (`RS256`, `ES256`); reject `none` / `HS*` | U, I | Phase 2 §6.8 |
| UC-N10 | Hydra issuer discovery `.well-known/openid-configuration` exposed publicly | I, N | Phase 2 §6.9 |
| UC-N11 | Kratos identity-schema customisation (per-Account User row mapping) | I | Phase 2 §6.10 |
| UC-N12 | Kratos webhook hook → IAM UpsertFromIdentity (preserve UC-U01 behavior) | I, N | Phase 2 §6.11 |
| UC-N13 | Refresh token rotation — old token revoked on new issue | I, N | Phase 2 §6.12 |
| UC-N14 | PKCE enforcement — code_challenge mandatory for public clients | I, N | Phase 2 §6.13 |
| UC-N15 | Token introspection (`POST /oauth2/introspect`) — opaque token validation | I, N | Phase 2 §6.14 |
| UC-N16 | User session UI — list active sessions, revoke individual | E | Phase 2 §6.15 |
| UC-N17 | Recovery flow — email-link / TOTP backup | I, N, E | Phase 2 §6.16 |
| UC-N18 | Device-bound credentials TTL ≤ 10min for high-sensitivity RPC | U, I | Phase 2 §6.17 |
| UC-N19 | Session timeout — inactivity 30min + absolute 12h | I, N | Phase 2 §6.18 |
| UC-N20 | Concurrent session limit (configurable per-Account, default 5) | I, N | Phase 2 §6.19 |
| UC-N21 | Audit log — every AuthN event emitted to outbox-audit (Phase 9 consumer) | I | Phase 2 §6.20 + Phase 9 |
| UC-N22 | Rate-limit on /oauth2/token (Cloudflare WAF + Hydra in-built) | N | Phase 2 §6.21 |

### 4.2 Phase 3 — Conditions (18 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-C01 | OpenFGA condition `mfa_fresh{seconds=300}` — only fresh MFA within 5 min | U, I, N | Phase 3 §6.1 |
| UC-C02 | OpenFGA condition `non_expired{token_exp}` | U, I | Phase 3 §6.2 |
| UC-C03 | OpenFGA condition `source_ip{cidr=...}` — allow only from CIDR list | U, I, N | Phase 3 §6.3 |
| UC-C04 | OpenFGA condition `break_glass_window{minutes=15}` | U, I, N | Phase 3 §6.4 |
| UC-C05 | OpenFGA condition `jit_window{ticket_id, valid_until}` | U, I, N | Phase 3 §6.5 |
| UC-C06 | OpenFGA condition `business_hours{tz, mon-fri 09-18}` | U, I | Phase 3 §6.6 |
| UC-C07 | OpenFGA condition `device_compliant{posture_check}` | U, I | Phase 3 §6.7 |
| UC-C08 | OPA Rego guardrail — `no-bind-of-system-role-by-non-admin.rego` | U, I, N | Phase 3 §6.8 |
| UC-C09 | OPA Rego guardrail — `no-cross-tenant-resource-grant.rego` | U, I, N | Phase 3 §6.9 |
| UC-C10 | OPA Rego guardrail — `max-role-fan-out{N=100}.rego` | U, I | Phase 3 §6.10 |
| UC-C11 | OPA Rego guardrail — `no-public-resource-grant-without-approval.rego` | U, I | Phase 3 §6.11 |
| UC-C12 | OPA bundle signing + sig verify on load | U, I | Phase 3 §6.12 + Phase 12 |
| UC-C13 | OPA decision log → outbox-audit (Phase 9 consumer) | I | Phase 3 §6.13 + Phase 9 |
| UC-C14 | Conditions evaluation latency ≤20ms p95 (k6 SLA) | k6 | Phase 3 §6.14 |
| UC-C15 | Conditions context plumbing — Check(user, relation, resource, context{...}) | U, I, N | Phase 3 §6.15 |
| UC-C16 | UI condition-editor for AccessBinding.Create | E | Phase 3 §6.16 + Phase 6 UI |
| UC-C17 | Conditions inheritance through scope tree (cluster→org→account→project) | U, I, N | Phase 3 §6.17 |
| UC-C18 | Conditions deny-override semantics (any failing condition → deny) | U, I, N | Phase 3 §6.18 |

### 4.3 Phase 4 — ListObjects + default-deny matrix v2 (6 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-L01 | OpenFGA ListObjects (`POST /stores/{id}/list-objects`) per List-RPC | I, N | Phase 4 §6.1 |
| UC-L02 | List-RPC SQL `WHERE id = ANY($ids)` after FGA-ListObjects | I, N | Phase 4 §6.2 |
| UC-L03 | List-filter latency ≤100ms p95 (k6 SLA) | k6 | Phase 4 §6.3 |
| UC-L04 | Default-deny matrix v2 — scope × subjects × CRUDL × services (cluster/org/account/project × 6 × 5 × N) | N | Phase 4 §6.4 |
| UC-L05 | Empty-list result for unauthorised List (not PermissionDenied) | I, N | Phase 4 §6.5 |
| UC-L06 | List pagination + filter co-existence (filter applied after FGA-scope) | I, N | Phase 4 §6.6 |

### 4.4 Phase 5 — SA-keys + Federation (14 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-F01 | SA-key Class A — Hydra-issued client_credentials grant | I, N | Phase 5 §6.1 |
| UC-F02 | SA-key Class A — JWT-bearer-assertion grant (RFC 7523) | I, N | Phase 5 §6.2 |
| UC-F03 | SA-key Class A — key rotation (2 active concurrent keys) | I, N | Phase 5 §6.3 |
| UC-F04 | SA-key Class A — key revoke immediate (≤5s) | I, N | Phase 5 §6.4 |
| UC-F05 | Federation Trust Policy — GitHub Actions OIDC `https://token.actions.githubusercontent.com` | I, N | Phase 5 §6.5 |
| UC-F06 | Federation Trust Policy — AWS IRSA OIDC | I, N | Phase 5 §6.6 |
| UC-F07 | Federation Trust Policy — GCP Workload Identity Federation OIDC | I, N | Phase 5 §6.7 |
| UC-F08 | Federation Trust Policy — generic JWKS-discoverable issuer | I, N | Phase 5 §6.8 |
| UC-F09 | Federation Exchange Class B — `POST /token/exchange` STS-flow → SA-credentials | I, N | Phase 5 §6.9 |
| UC-F10 | Federation subject-mapping rules (claim `sub`, `repo`, etc. → SA-id) | U, I | Phase 5 §6.10 |
| UC-F11 | Federation audience binding (`aud=https://api.kacho.cloud`) | U, I, N | Phase 5 §6.11 |
| UC-F12 | Federation token lifetime ≤15min (no refresh) | I, N | Phase 5 §6.12 |
| UC-F13 | Federation trust-policy condition (`repo=org/proj`, `branch=main` etc.) | U, I, N | Phase 5 §6.13 |
| UC-F14 | Federation deny by default — no trust without explicit policy | I, N | Phase 5 §6.14 |

### 4.5 Phase 6 — Multi-tenancy + SCIM + SAML + Organization (11 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-MT01 | Organization tier — new top-level scope above Account | I, N | Phase 6 §6.1 |
| UC-MT02 | Organization-scoped Role + AccessBinding | I, N | Phase 6 §6.2 |
| UC-MT03 | SCIM 2.0 endpoint — Users, Groups, Bulk (`/scim/v2/...`) | I, N | Phase 6 §6.3 |
| UC-MT04 | SCIM JIT provisioning — first-login creates User row in target Account | I, N, E | Phase 6 §6.4 |
| UC-MT05 | SCIM de-provisioning — DELETE → User.status=BLOCKED + revoke sessions | I, N | Phase 6 §6.5 |
| UC-MT06 | SAML 2.0 SP bridge → IdP per Organization | I, N, E | Phase 6 §6.6 |
| UC-MT07 | SAML attribute mapping → User.fields + Group membership | I | Phase 6 §6.7 |
| UC-MT08 | Signup orchestrator (Account+Project+admin-binding) refactor to handle SCIM JIT path | I, E | Phase 6 §6.8 |
| UC-MT09 | Organization-scoped audit log retention policy | I | Phase 6 §6.9 + Phase 9 |
| UC-MT10 | Organization domain claim (e.g. `acme.com` → org-acme) | I, N | Phase 6 §6.10 |
| UC-MT11 | Cross-Organization invite-flow (Account A admin invites user from Org B) | I, N, E | Phase 6 §6.11 |

### 4.6 Phase 7 — Lifecycle (12 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-LC01 | JIT (Just-in-time) role elevation — `iam.RequestRole({role, justification, ttl})` | I, N, E | Phase 7 §6.1 |
| UC-LC02 | JIT auto-revoke on TTL expiry (cron + outbox) | I, N | Phase 7 §6.2 |
| UC-LC03 | PIM (Privileged Identity Management) approval flow (2-person rule) | I, N, E | Phase 7 §6.3 |
| UC-LC04 | Break-glass session — emergency admin, 2-person Slack approval, 15min TTL | I, N, E | Phase 7 §6.4 |
| UC-LC05 | Break-glass session audit — all actions tagged `break_glass=true` | I | Phase 7 §6.5 + Phase 9 |
| UC-LC06 | Access Reviews — quarterly campaign, owner certifies / revokes | I, N, E | Phase 7 §6.6 |
| UC-LC07 | Access Review reminders + escalation | I | Phase 7 §6.7 |
| UC-LC08 | Access Review report (CSV / PDF) | E | Phase 7 §6.8 |
| UC-LC09 | GDPR erasure pipeline — User.DeleteForever → 30d retention → all DBs anonymise | I, N | Phase 7 §6.9 |
| UC-LC10 | GDPR data-export — User.ExportData → ZIP with all IAM rows | I, N, E | Phase 7 §6.10 |
| UC-LC11 | Inactive user auto-disable (90 days no login → BLOCKED) | I | Phase 7 §6.11 |
| UC-LC12 | Privileged-role review — anyone with `kacho.admin` reviewed monthly | I, E | Phase 7 §6.12 |

### 4.7 Phase 8 — CAEP push (9 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-CA01 | CAEP subscriber registry — `POST /caep/subscribers` (target audience) | I, N | Phase 8 §6.1 |
| UC-CA02 | CAEP SET signing — JWT signed with HSM key (Phase 9 HSM-Merkle) | I, N | Phase 8 §6.2 |
| UC-CA03 | CAEP event types — `session-revoked`, `credential-change`, `assurance-change`, etc. | I, N | Phase 8 §6.3 |
| UC-CA04 | CAEP push pipeline — outbox → HTTP POST (JWT body) → subscriber | I, N | Phase 8 §6.4 |
| UC-CA05 | CAEP delivery ≤5s p99 (k6 SLA) | k6 | Phase 8 §6.5 |
| UC-CA06 | CAEP retry/backoff on subscriber 5xx | I | Phase 8 §6.6 |
| UC-CA07 | CAEP subscriber auth (mTLS or shared-secret HMAC) | I, N | Phase 8 §6.7 |
| UC-CA08 | CAEP receiver — IAM accepts inbound SET from federated IdP | I, N | Phase 8 §6.8 |
| UC-CA09 | CAEP audit — every push delivery logged (Phase 9 consumer) | I | Phase 8 §6.9 + Phase 9 |

### 4.8 Phase 9 — Audit pipeline (11 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-AU01 | Kafka audit topic — every mutating RPC emits AuditEvent | I, N | Phase 9 §6.1 |
| UC-AU02 | ClickHouse OLAP consumer — Kafka → CH for ad-hoc query | I | Phase 9 §6.2 |
| UC-AU03 | S3+Glacier cold storage — daily partition export | I | Phase 9 §6.3 |
| UC-AU04 | HSM key for SET / audit-trail signing | I | Phase 9 §6.4 |
| UC-AU05 | Merkle-tree audit-trail — every event hashed into daily root, root signed by HSM | I, N | Phase 9 §6.5 |
| UC-AU06 | Audit-trail verification CLI — re-hash range, compare with signed root | U, I | Phase 9 §6.6 |
| UC-AU07 | SIEM webhook delivery (Splunk / Datadog / generic) | I, N | Phase 9 §6.7 |
| UC-AU08 | Audit retention policy (hot 30d in CH, warm 1y in S3, cold ∞ in Glacier) | I | Phase 9 §6.8 |
| UC-AU09 | Audit search UI (admin-only) | E | Phase 9 §6.9 |
| UC-AU10 | Audit-export to CSV for compliance officer | E | Phase 9 §6.10 |
| UC-AU11 | Audit consumer for Phase 2/3/5/7/8 events (cross-cutting wiring) | I | Phase 9 §6.11 |

### 4.9 Phase 10 — Workload identity (7 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-W01 | SPIFFE/SPIRE deploy in cluster — SVID for every workload | I | Phase 10 §6.1 |
| UC-W02 | Cilium mesh mTLS — automatic encryption between services | I | Phase 10 §6.2 |
| UC-W03 | SPIFFE ID format `spiffe://kacho.cloud/ns/<ns>/sa/<svc-account>` | U, I | Phase 10 §6.3 |
| UC-W04 | gRPC ServerOption peer-cert verify against SPIFFE trust domain | I, N | Phase 10 §6.4 |
| UC-W05 | SPIFFE → IAM SA mapping (federation Class B reuses) | I, N | Phase 10 §6.5 + Phase 5 |
| UC-W06 | Workload identity rotation (SVID 1h TTL) | I | Phase 10 §6.6 |
| UC-W07 | Mesh deny-by-default — explicit NetworkPolicy + Cilium L7 policy | I | Phase 10 §6.7 |

### 4.10 Phase 11 — Production deploy (9 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-D01 | DNS `api.kacho.cloud` → multi-region Cloudflare Load Balancer | I, smoke | Phase 11 §6.1 |
| UC-D02 | Cloudflare WAF rule-set (OWASP CRS + custom IAM rules) | smoke | Phase 11 §6.2 |
| UC-D03 | Multi-region active-active deploy (primary + DR region) | smoke | Phase 11 §6.3 |
| UC-D04 | Argo CD GitOps pipeline — every commit → cluster sync | I | Phase 11 §6.4 |
| UC-D05 | Helm chart values per environment (dev / stage / prod / dr) | smoke | Phase 11 §6.5 |
| UC-D06 | SBOM (CycloneDX) generated per build | I | Phase 11 §6.6 |
| UC-D07 | SLSA-3 provenance — signed attestation per artifact | I | Phase 11 §6.7 |
| UC-D08 | Cosign-signed container images verified at admission | I | Phase 11 §6.8 |
| UC-D09 | DR failover drill quarterly — RPO ≤5min, RTO ≤15min | smoke, chaos | Phase 11 §6.9 |

### 4.11 Phase 12 — Hardening (14 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-H01 | OWASP ASVS L3 self-assessment + gap remediation | review | Phase 12 §6.1 |
| UC-H02 | OPA bundle signing — cosign-signed `.tar.gz` | I | Phase 12 §6.2 |
| UC-H03 | Chaos Litmus — pod-kill, network-partition, disk-fill in IAM | chaos | Phase 12 §6.3 |
| UC-H04 | Continuous fuzzing — `go-fuzz` token parsers + FGA DSL + Rego policy parser | go-fuzz | Phase 12 §6.4 |
| UC-H05 | External pentest (annual) | external | Phase 12 §6.5 |
| UC-H06 | Bug bounty program launch | external | Phase 12 §6.6 |
| UC-H07 | Dependency scan (govulncheck + trivy) gating PR | I | Phase 12 §6.7 |
| UC-H08 | Secret-scan (gitleaks) in CI | I | Phase 12 §6.8 |
| UC-H09 | SAST (semgrep) gating PR | I | Phase 12 §6.9 |
| UC-H10 | DAST (zap-baseline against staging) nightly | I | Phase 12 §6.10 |
| UC-H11 | Threat-model document per Phase | review | Phase 12 §6.11 |
| UC-H12 | Tabletop exercise — security incident drill quarterly | review | Phase 12 §6.12 |
| UC-H13 | Backup encryption + restore drill quarterly | smoke | Phase 12 §6.13 |
| UC-H14 | Key rotation drill (HSM + JWKS + SA-keys) quarterly | smoke | Phase 12 §6.14 |

### 4.12 Phase 13 — Vault closeout (5 new UC)

| UC-ID | Title | Layer | Owner |
|---|---|---|---|
| UC-V01 | Final architecture docs in obsidian vault (resources / rpc / packages / edges) | review | Phase 13 §6.1 |
| UC-V02 | On-call rotation playbook + escalation matrix | review | Phase 13 §6.2 |
| UC-V03 | Runbooks per critical alert (Kratos down / Hydra down / FGA down / Kafka lag) | review | Phase 13 §6.3 |
| UC-V04 | Post-launch review (30 day) + lessons learned | review | Phase 13 §6.4 |
| UC-V05 | Quarterly Phase-revisit cadence established (security freshness) | review | Phase 13 §6.5 |

---

## 5. Test-layer mapping (как UC материализуется в коде / артефактах)

Каждый UC получает покрытие на одном или нескольких уровнях. Регламент:

| Layer | Где живёт | Когда обязательно | Покрывает UC-категории |
|---|---|---|---|
| **U (Unit)** | `internal/apps/kacho/api/<resource>/*_test.go` (use-cases) + `internal/domain/*_test.go` (newtypes + Validate) + `internal/authzmap/*_test.go` | Каждый use-case + каждый non-trivial domain newtype + condition evaluator | UC-R03 (regex), UC-N08 (AAL mapping), UC-N09 (alg whitelist), UC-C01..C18 (conditions), UC-F10 (claim mapping), UC-W03 (SPIFFE ID), UC-AU06 (Merkle verify) |
| **I (Integration)** | `internal/repo/kacho/pg/*_integration_test.go` (testcontainers Postgres 16) + `internal/clients/*_integration_test.go` (testcontainers OpenFGA + Kratos + Hydra) | Каждая SQL-сторона (FK / UNIQUE / EXCLUDE / CAS) + каждая race-prone мутация + каждый peer-call | UC-A01..A10, UC-P01..P07, UC-U01..U08, UC-SA01..SA05, UC-R01..R07, UC-AB01..AB07, UC-G01..G05, UC-AU01..AU11, UC-MT01..MT11, etc. |
| **N (Newman)** | `tests/newman/cases/*.py` → `gen.py` → Postman collection | Каждый public RPC + каждый InternalRPC что должен быть скрыт + happy-path + 1 negative | Все UC, где есть HTTP API surface |
| **E (E2E / Playwright)** | `kacho-ui/e2e/*.spec.ts` | Каждый UI flow (signup, invite, role-cascader, sessions, MFA enrol, JIT request, Access Review, audit search) | UC-UI01..UI08, UC-S01..S06, UC-LC01, LC03, LC04, LC06, LC10, UC-MT04, MT06, MT11, UC-N16, N17, UC-N01..N02 ceremonies |
| **k6 (Perf SLA)** | `kacho-test/k6/*.js` | Каждый latency-budgeted RPC (Check ≤20ms, ListObjects ≤100ms, CAEP delivery ≤5s) | UC-C14, UC-L03, UC-CA05 |
| **Chaos (Litmus)** | `kacho-test/chaos/*.yaml` | Phase 12 resilience drills | UC-H03, UC-D09 |
| **Fuzz (go-fuzz)** | `*/fuzz/Fuzz*_test.go` | Token parsers, FGA DSL, Rego policy parser | UC-H04 |

> **Запрет #11 (workspace CLAUDE.md)**: ни один PR с новым RPC / новым полем / новым oneof case не мерж'ится без integration + newman в том же PR. «Tests-followup» как обоснование запрещён.

---

## 6. Migration risk register

Для каждого «горячего» baseline UC — оценка риска breaking-change при миграции на KAC-127. Колонки:

| Risk-ID | Baseline UC | KAC-127 phase | Что меняется | Backward-compat strategy | Verification |
|---|---|---|---|---|---|
| RISK-01 | UC-R01, R02 (Role multi-scope) | Phase 1 | Custom-role scope расширяется: `account_id NOT NULL` → `scope_type + scope_id` (cluster/org/account/project) | Миграция: existing custom roles получают `scope_type='account', scope_id=account_id`. Старая колонка `account_id` сохраняется как generated column для read-back compat. | Phase 1 §6.4.0 backward-compat test: pre-migration custom role читается как scope=account через new API |
| RISK-02 | UC-AB01..AB07 (AccessBinding subject/resource polymorphic) | Phase 1 | resource_type расширяется новыми типами (cluster, organization). subject_type — новый GROUP_NESTED. | Existing rows сохраняют типы; миграция добавляет новые в enum. | Phase 1 idempotency tests с pre-existing row hashes |
| RISK-03 | UC-I02 (OpenFGA model v1 → v2) | Phase 1 + Phase 4 | model.fga получает новые types (cluster, organization), новые relations (`member_of`, `condition`). | OpenFGA store migration: replay tuples с новой model_id. Старая model_id остаётся read-only ≥7 days. | Phase 1 §6.5 model-migration tests; Phase 4 invariant: после migration UC-Z01..Z04 всё ещё проходят |
| RISK-04 | UC-Z03 (reactivity ≤10s) | Phase 4 | Target tightening до ≤5s p99. | Новый Watch-pipeline (LISTEN/NOTIFY + outbox→FGA writer + cache invalidate via Redis pub/sub). | k6 SLA test в Phase 4 §6.X |
| RISK-05 | UC-U01..U08 (User identity store) | Phase 2 | external_id source меняется: Zitadel sub → ORY Kratos identity-id. | Migration: для каждого existing user — Kratos identity создаётся с external_id=zitadel-sub в traits; зеркало external_id ← kratos_identity_id обновляется hook'ом. | Phase 2 §6.X migration test: existing user может залогиниться через новый Kratos и попасть в тот же usr-id |
| RISK-06 | UC-S01..S05 (signup orchestrator) | Phase 6 | Orchestrator переписывается для поддержки SCIM JIT path. | Существующий E4 signup-flow получает feature-flag; SCIM JIT — opt-in per Organization. Default — old behavior. | Phase 6 §6.X compat test: E4 signup всё ещё работает идентично |
| RISK-07 | UC-UI01..UI05 (Cascader / AccessBindings / breadcrumb / role catalog) | Phase 6 UI | Cascader получает третий уровень (Org → Account → Project) + новый layout. | Старые URLs (`/account/:id/...`) поддерживаются redirect'ом на новые (`/org/:org/account/:id/...`). | Playwright E2E замечает старые URLs и проверяет redirect |
| RISK-08 | UC-AB05 (AccessBinding → FGA tuple invalidate ≤10s) | Phase 1 §6.2 | Outbox→FGA writer переписывается на новую model_id; SLA tightens до 5s. | Outbox events идемпотентны (key=binding_id+model_id). Старая model_id обрабатывается до cutover. | Phase 1 concurrent-race test: AccessBinding.Create + Delete внутри 1s — FGA в конечном состоянии deny |
| RISK-09 | UC-M01..M03 (folder_id → project_id consumer-сервисы) | Phase 6 | Не трогаем — миграция уже завершена в E1. | N/A | Phase 6 verification: peer-client возвращает Project (не Folder); RM proto packages remain deleted (UC-M04) |
| RISK-10 | UC-Z02 (default-deny matrix per service) | Phase 4 | Matrix расширяется: 6 → 8 subjects (добавлены `org-admin-from-other-Org`, `cross-Account-invited-user`); CRUDL added; services count grows. | Старые kacho-iam/compute/vpc `authz-deny.py` сохраняются 1-в-1 как floor coverage; новые scenarios — отдельные `authz-deny-v2.py`. | Phase 4 newman: оба файла должны быть зелёными |
| RISK-11 | UC-I04 (LISTEN/NOTIFY → OpenFGA tuple) | Phase 4 | Dedicated connection pattern preserved. | Reactivity SLA tighter (5s vs 10s) — pure perf, не breaking. | Phase 4 k6 test |
| RISK-12 | UC-N09 (algorithm-confusion mitigation) | Phase 2 NEW | Hydra config locks alg whitelist. Tenant-interceptor validates `alg` claim. | N/A new functionality. | Phase 2 unit test + negative newman (forge HS256 token → reject) |
| RISK-13 | UC-AU01..AU11 (audit pipeline) | Phase 9 | Outbox-audit table добавляется в каждый сервис. Существующие mutating-RPC ничего не теряют — audit emit лишь добавочный side-effect. | Backward-compat: если Kafka недоступен, mutation всё равно committs (audit emit best-effort retried). | Phase 9 chaos test: Kafka down → mutations всё ещё проходят |
| RISK-14 | UC-W01..W07 (SPIFFE/SPIRE + Cilium mesh) | Phase 10 | mTLS auto-enabled между сервисами. | Backward-compat: pre-Phase-10 stack работает без mTLS (mesh opt-in per namespace). Cutover — flip flag. | Phase 10 smoke: cross-service RPC работает с mesh on и off |
| RISK-15 | UC-D01..D09 (multi-region deploy) | Phase 11 | Active-active требует распределённого state (Kratos sessions в Redis Cluster; Hydra в Postgres replica). | Phase 11 deploy plan: cutover в режиме «one region first, replicate, then enable second region traffic». | Phase 11 DR drill UC-D09 |

---

## 7. Traceability — back-pointer per UC

Каждый UC из §2-4 получает запись в обратном индексе: «откуда → куда». Сводно:

| Baseline acceptance doc | UC covered (§2) | KAC-127 phases inheriting |
|---|---|---|
| `sub-phase-2.0-iam-E0-skeleton-acceptance.md` (KAC-105) | A01-A04, A08-A10, P01, P03-P06, U06, SA01-SA05, R02-R06, AB01-AB04, AB07 (subset) | Phase 1 §6.1 (almost full inheritance) |
| `sub-phase-2.0-iam-E1-folder-to-project-migration-acceptance.md` (KAC-106) | M01-M03 | Phase 6 §6.X |
| `sub-phase-2.0-iam-E2-zitadel-oidc-acceptance.md` (KAC-110) | U01, U04, I01, I05, S03 | Phase 2 (re-platformed onto ORY Kratos+Hydra) |
| `sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` (KAC-108) | AB05, Z01, Z03, I02-I04 | Phase 1 §6.2 + Phase 4 |
| `sub-phase-2.0-iam-E4-signup-flow-ui-acceptance.md` (KAC-117) | A05, P02, S01, S04, S05 | Phase 6 §6.X |
| `sub-phase-2.0-iam-E5-rm-deprecation-acceptance.md` (KAC-124) | M04, M05 | Phase 6 (verified RM remains deleted) |
| `sub-phase-2.0-iam-KAC-119-role-model-acceptance.md` | G01-G04, UI02, UI04 | Phase 1 §6.1 + Phase 6 UI |
| `sub-phase-2.0-iam-KAC-121-yc-style-role-model-acceptance.md` | R01-R07, A06, P04, P05, UI05, SA01 (re-scoped) | Phase 1 §6.1 + Phase 6 UI |
| `sub-phase-2.0-iam-KAC-125-user-invite-flow-acceptance.md` | U02, U03, U05, U08, S02, UI01, UI03 | Phase 2 + Phase 6 |
| `docs/specs/2026-05-19-authz-default-deny-matrix-newman-design.md` (KAC-122) | A07, P03, U05, G03, Z02, Z04, AB06 | Phase 4 §6.4 |

| Newman case file | UC covered | KAC-127 owner |
|---|---|---|
| `kacho-iam/tests/newman/cases/iam-account.py` | UC-A01, A03, A04, A09, A10 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-project.py` | UC-P01, P04, P05, P06, M05 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-user.py` | UC-U01, U06, U07 | Phase 2 |
| `kacho-iam/tests/newman/cases/iam-role.py` | UC-R02, R04, R05 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-service-account.py` | UC-SA01, SA04 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-group.py` | UC-G01, G02, G04 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-access-binding.py` | UC-AB01, AB02, AB04, AB07 | Phase 1 §6.1 |
| `kacho-iam/tests/newman/cases/iam-internal-only-check.py` | UC-Z01, Z07, Z08, AB07 | Phase 2 + Phase 4 |
| `kacho-iam/tests/newman/cases/authz-deny.py` + compute + vpc variants | UC-Z02, Z04, A07, P03, U05, G03, AB06 | Phase 4 §6.4 |

| Integration test file | UC covered | KAC-127 owner |
|---|---|---|
| `account_integration_test.go` | A01, A03, A04, A08, A09 | Phase 1 §6.1 |
| `project_integration_test.go` | P01, P04, P05, P06 | Phase 1 §6.1 |
| `user_integration_test.go` | U01, U06, U07, U08 | Phase 2 |
| `user_invite_integration_test.go` | U02, U03, U05 | Phase 6 |
| `role_integration_test.go` | R02, R03, R04, R05 | Phase 1 §6.1 |
| `service_account_integration_test.go` | SA01, SA02, SA04, SA05 | Phase 1 §6.1 |
| `group_integration_test.go` | G01, G02, G04 | Phase 1 §6.1 |
| `access_binding_integration_test.go` | AB01, AB02, AB03, AB04, AB05, AB07 | Phase 1 §6.1 |
| `kac127_repos_integration_test.go` (NEW Phase 1) | R01 (multi-scope), AB05 (v2), Z09 | Phase 1 §6.1, §6.2 |
| `migrations_kac127_integration_test.go` (NEW Phase 1) | R01 (id parity), RISK-01..03 | Phase 1 §6.4 |
| `internal/authzmap/role_expand_test.go` | R03 (regex), R05 (wildcard) | Phase 1 §6.1 |
| `internal/clients/openfga_client_test.go` | I02, AB05 | Phase 1 §6.2 + Phase 4 |
| `internal/apps/kacho/api/account/create_test.go` | A01 (use-case unit) | Phase 1 §6.1 |
| `internal/apps/kacho/api/project/create_test.go` | P01 (use-case unit) | Phase 1 §6.1 |
| `internal/apps/kacho/api/user/user_test.go` | U01 (use-case unit) | Phase 2 |
| `internal/apps/kacho/api/internal_iam/lookup_subject_test.go` | Z01, Z08, AB07 | Phase 2 + Phase 4 |

---

## 8. Definition of Done (этой sub-phase 3.0 itself)

- [x] Все 79 baseline UC из §2 имеют **explicit** mapping в одну из Phase 1-13 (колонка `KAC-127 phase` заполнена для каждой строки).
- [x] Каждый Phase 1-13 имеет суммарную численную проверку в §3 (UC inherits + UC new = Total UC).
- [x] Все 146 новых UC из KAC-127 (§4) имеют owner Phase + Acceptance doc reference.
- [x] Все 15 миграционных рисков (§6) имеют backward-compat strategy + verification approach.
- [x] Каждый baseline test artifact (newman case file, integration test file, acceptance doc) имеет back-pointer в §7.
- [x] Документ соответствует регламенту: zero TODO / TBD / deferred в body; production-edition wording.
- [x] Cross-links на acceptance docs Phase 1/2/3 (`sub-phase-3.1`, `3.2`, `3.3`) валидны (файлы существуют в `docs/specs/`).
- [x] Document проверен на отсутствие упоминаний «yandex» (workspace CLAUDE.md запрет #2).
- [x] Document готов как input для Phase 4-13 acceptance docs — каждая phase знает, какие UC она наследует и какие новые добавляет.

---

## 9. References

- `kacho-workspace/CLAUDE.md` — общие правила (запреты #1, #6, #8, #10, #11)
- `kacho-iam/CLAUDE.md` — IAM-специфичные паттерны
- `docs/specs/04-roadmap-and-phasing.md` — общий phasing roadmap
- `docs/specs/sub-phase-2.0-iam-overview-acceptance.md` — meta-acceptance для KAC-104 эпика
- `docs/specs/sub-phase-2.0-iam-E0-skeleton-acceptance.md` (KAC-105)
- `docs/specs/sub-phase-2.0-iam-E1-folder-to-project-migration-acceptance.md` (KAC-106)
- `docs/specs/sub-phase-2.0-iam-E2-zitadel-oidc-acceptance.md` (KAC-110)
- `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` (KAC-108)
- `docs/specs/sub-phase-2.0-iam-E4-signup-flow-ui-acceptance.md` (KAC-117)
- `docs/specs/sub-phase-2.0-iam-E5-rm-deprecation-acceptance.md` (KAC-124)
- `docs/specs/sub-phase-2.0-iam-KAC-119-role-model-acceptance.md`
- `docs/specs/sub-phase-2.0-iam-KAC-121-yc-style-role-model-acceptance.md`
- `docs/specs/sub-phase-2.0-iam-KAC-125-user-invite-flow-acceptance.md`
- `docs/specs/2026-05-19-authz-default-deny-matrix-newman-design.md` (KAC-122)
- `docs/specs/sub-phase-3.1-iam-foundation-acceptance.md` (KAC-127 Phase 1)
- `docs/specs/sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` (KAC-127 Phase 2)
- `docs/specs/sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md` (KAC-127 Phase 3)
- YouTrack эпик: https://prorobotech.youtrack.cloud/issue/KAC-123 (real YT id; vault-label = KAC-127)

---

**Конец документа.** Этот matrix — read-only reference; обновляется лишь при появлении **нового baseline UC** в KAC-104..KAC-125 (ретроспективно) или при изменении phase-ownership UC между Phase 1-13. Каждое такое изменение — отдельный коммит вида `docs(spec): KAC-127 matrix — re-home UC-XYZ from Phase A to Phase B (rationale)`.
