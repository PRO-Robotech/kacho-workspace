---
title: RBAC rules-model 2026 — sub-phase D (iam-core)
ticket_id: rbac-rules-model-2026-D-iam
status: done
verified_against: "предмет сверен с PRO-Robotech/kacho@58913d0e (2026-08-05); текст записки построчно не пересматривался"
type: feature
repos:
  - kacho-iam
  - kacho-proto
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-iam/issues/185
opened: 2026-06-21
tags:
  - kac
  - kacho-iam
  - kacho-proto
  - feature
  - usecase
  - repo
  - proto
category: kac
---

# RBAC rules-model 2026 — sub-phase D (iam-core)

> [!note] Сверено по дереву продукта 2026-08-05 (`PRO-Robotech/kacho@58913d0e`): `role_rule_selectors` — 13 вхождений в миграциях iam, начиная с `0026_role_rule_selectors.sql`.
> Правило закрытия и что именно проверяется вместо пунктов «PR смёржен» — [[KAC/README]].

**Состояние на момент записи**: test (code-complete on branches `rbac-rules-d-iam` / `rbac-rules-d-proto`, NOT committed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase D — per-object filtered `List`, §11, КРИТИЧНО)
**Repos**: kacho-iam (this) + kacho-proto (`ListRolesRequest.account_id=4`, append-only)
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` (APPROVED раунд 2) — D-40..D-47 (LST-1..6), design §11
**Issues**: #185 (Role.List accountId scope), #184 (pageSize reject)

## Что и зачем

`List<Resource>` returns ONLY objects the caller can access (NOT K8s all-or-nothing).
Mechanism = FGA `ListObjects(subject, "v_list", "<type>")` over the materialized per-object
tuples + `scope_grant` from sub-phase B/C — the SAME tuple base as Check → **read==enforce**.
This is the **iam-core** track: iam own-resource Lists + shared #184/#185. The consumer
vpc/compute/nlb List-filter enable is a separate track.

## Сделано (D, iam-core)

- **kacho-proto** (`role_service.proto`): `ListRolesRequest.account_id = 4` (append-only, `<=20`);
  `filter` comment narrowed to is_system/name. `buf lint`/`buf breaking`/`buf generate` зелёные.
- **#188 per-object Role.List** (`role/list.go`, `role/handler.go`, `cmd/.../wiring.go`):
  `ListRolesUseCase.WithRelationStore(RelationQueries)`; resolves `ListObjects(subject,"v_list",
  "iam_role")` → `ListFilter.VisibleIDs`; system roles bypass (catalog floor), custom filtered
  per-object; fail-closed `UNAVAILABLE` on nil-port/FGA-error (D-47). Wired with `relationStore`.
- **#185 accountId scope** (`role_repo.go`, `role/iface.go`, `role/handler.go`): repo `WHERE
  (is_system OR account_id=$acc)`; handler maps `req.AccountId` → `ListFilter.AccountID`.
- **D-46 pagination-after-filter** (`role_repo.go`): `ListFilter.VisibleIDs` push-down
  `WHERE (is_system OR id = ANY($visible))` → keyset `(created_at,id)` dense over filtered set
  (fixes the account/project post-filter leaky-page weakness for roles).
- **#184 pageSize reject** (`pg/helpers.go effectivePageSize` + all repo Lists: role/account/
  project/group/service_account/user + role ListAssignable): `page_size>1000` → `ErrInvalidArg`
  → `INVALID_ARGUMENT`, no silent clamp. Parity with kacho-vpc `corevalidate.PageSize`.
- **CI**: `kacho-proto` pinned `main`→`rbac-rules-d-proto` in all iam workflows (TEMP-PIN, revert after proto merge).

## Затронутые сущности vault

- [[../rpc/iam-role-service]] — List scope-filtered per-object + account_id + pageSize reject
- [[../resources/iam-role]] — List visibility (system floor ∪ FGA v_list custom), #185 scope
- [[rbac-rules-model-2026-subphase-B-iam]] (scope_grant/v_*), [[rbac-rules-model-2026-subphase-C-iam]] (matchLabels materialization) — supply the tuple base read by ListObjects

## RED → GREEN proof

- **unit** (`role/list_authz_test.go`, `role/handler_rules_test.go`): RED `WithRelationStore`
  undefined → GREEN. D-45 (v_list/iam_role relation), D-40 (system floor), D-41/43 (byName/union),
  D-44 (no-leak), #185 (foreign custom hidden), D-47 (nil/error fail-closed), #184 (handler reject).
- **integration** (`pg/role_list_filter_integration_test.go`, testcontainers, NOT -short): RED
  `ListFilter.VisibleIDs` undefined → GREEN. #185 account scope (foreign custom absent), #184
  (page_size>1000 → ErrInvalidArg, MapRepoErr→INVALID_ARGUMENT), D-46 (keyset dense over filtered
  set, hidden custom never paginated in).
- **real OpenFGA** (`access_binding/list_objects_role_fga_integration_test.go`): byName
  `ListObjects(v_list,iam_role)` returns exactly granted (LST-2) + ungranted absent (LST-5) +
  Check parity (D-45); all_in_scope anchor → every in-scope role visible, foreign account excluded (LST-3/D-42).
- **newman** (`iam-role.py`, `iam-user.py`): #185 account-scoped List (system + crudRoleId) +
  no-foreign-custom; #184 `pageSize=1001`→400 (was KNOWN-RED, now GREEN); iam-user clamp-200 case
  flipped to 400.

## DoD

- [x] kacho-proto `ListRolesRequest.account_id=4` (append-only, buf green)
- [x] per-object Role.List (FGA v_list ListObjects, system floor bypass, fail-closed)
- [x] #185 accountId scope (handler+repo SQL)
- [x] D-46 pagination-after-filter (VisibleIDs push-down, dense keyset)
- [x] #184 pageSize reject across iam List RPCs (effectivePageSize)
- [x] RED→GREEN unit + integration (-p 1, non-short, colima) + real-OpenFGA + newman gen
- [x] CI pin kacho-proto→rbac-rules-d-proto (revert after merge)
- [ ] commit/push (НЕ делалось по инструкции)
- [ ] reviews: system-design (read==enforce/fail-closed/replica-isolation), security (no-leak), go-style, proto-api, db-architect
- [ ] **load-testing-coach gate (O-5)** — ListObjects latency/cardinality on large sets BEFORE prod-flip

## Остаточные риски / follow-up

- **consumer track separate**: vpc/compute/nlb public List per-object filter via `InternalIAMService`
  ListObjects-analog (D-47 fail-closed) is NOT in this iam-core task — separate per-service track.
- **iam Group/User/SA List**: Group.List unfiltered; User/SA filter by membership scope (not FGA
  v_list). #184 applies; per-object v_list parity for these is a follow-up (Role.List is the §11 reference).
- **O-5 load gate ОБЯЗАТЕЛЕН перед prod-flip**: FGA `ListObjects` cardinality on thousands of
  objects/type/scope — latency + cursor stability after filter. Not run here (no load stand).
- **`make audit-list-filter`**: that CI gate lives in kacho-vpc/kacho-deploy (consumer track),
  not kacho-iam — per-object enforcement here is gated by unit+real-FGA+newman instead.

#kac #kacho-iam #kacho-proto #feature
