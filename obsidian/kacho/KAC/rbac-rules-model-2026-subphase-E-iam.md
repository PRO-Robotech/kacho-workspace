---
title: RBAC rules-model 2026 — sub-phase E (subjects[] + ExpandAccess + ListByRole)
ticket_id: rbac-rules-model-2026-E-iam
status: test
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-iam
opened: 2026-06-21
tags:
  - kac
  - kacho-iam
  - kacho-proto
  - kacho-api-gateway
  - feature
  - usecase
  - repo
  - proto
  - migrations
  - handler
---

# RBAC rules-model 2026 — sub-phase E (subjects[] + ExpandAccess + ListByRole)

**Status**: test (code-complete on branches `rbac-rules-e-proto` / `rbac-rules-e-iam` / `rbac-rules-e-gateway`, NOT committed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase E — multi-subject bindings + effective-principal/role audit)
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` §«ПОД-ФАЗА E» E-30..E-34 (APPROVED раунд 2)

## Что и зачем

Три добавления к `AccessBindingService`, реализующие governance-изоляцию субъектов и audit-readiness:

1. **`AccessBinding.subjects[]` (1..32, R-5)** — одна binding-строка грантит роль+scope нескольким субъектам; каждый — независимый tuple-set + lineage (per-subject revoke/audit, нет double-grant аномалии E-30). Хранение: child-table `access_binding_subjects` (migration 0028, FK CASCADE + UNIQUE). legacy single `subject_type`/`subject_id` = `subjects[0]` (anchor active-grant UNIQUE + E-34 проекция).
2. **`ExpandAccess` RPC (E-31/R-6)** — userset → concrete principals (group→members), audit «кто реально может X».
3. **`ListByRole` RPC (E-33)** — audit «кто несёт роль R».
+ group-amplification guard (E-32/Q#4) + двусторонняя read-projection subjects[]↔legacy (E-34).

## Реализация (по слоям)

- **proto** (`rbac-rules-e-proto`): `AccessBinding.subjects=19` (`repeated Subject`), `Subject{type,id}`, `SubjectType` enum (значения enum-prefixed `SUBJECT_TYPE_*` — bare USER/SA/GROUP коллизируют с `ClusterGrantSubjectType`/`Derivation`); `CreateAccessBindingRequest.subjects=12`; `ListByRole`/`ExpandAccess` RPC + req/resp + `Principal`. append-only, `buf lint`/`breaking`/`generate` зелёные; permission_catalog регенерён.
- **migration 0028** — `access_binding_subjects(binding_id FK CASCADE, subject_type CHECK, subject_id, ordinal) PK(binding_id,subject_type,subject_id)` + backfill 1 строка/legacy-binding.
- **domain** — `Subject{Type,ID}` + `Validate`/`IsGroup`; `NormalizeSubjects` (E-34: subjects[] каноничен, legacy single = one-element проекция, конфликт/пусто/>32/dup → ошибка); `AccessBinding.Subjects[]`.
- **repo** — Reader `ListByRole`/`ListSubjects`/`ListSubjectsForBindings`; Writer `InsertSubjects`(idempotent ON CONFLICT)/`DeleteSubject`(per-subject revoke).
- **use-case** — Create: normalize → InsertSubjects → per-subject tuple-emit (цикл `buildBindingTuples`, dedupe) → per-subject subject_change+audit; `ExpandAccessUseCase` (рекурсивный userset-walk, cycle-guard, FGA Read page=100 пагинация); `ListByRoleUseCase` (per-row scope-filter). Get/List/ListByAccount/ListByRole fill subjects[] (`projectSubjectsBatch` + `toPb domainSubjectsToProto` legacy-fallback).
- **handler+wiring** — `ListByRole`/`ExpandAccess` методы + `WithListByRole`/`WithExpandAccess`; wired в `cmd/kacho-iam/wiring.go` (ExpandAccess через concrete `relationStore.ListSubjects`).
- **gateway** (`rbac-rules-e-gateway`) — оба RPC на public mux (allowlist + REST route table + synced permission catalog); НЕ Internal.
- **embedded catalogs** — `internal_iam/embedded` + `seed/embedded` синканы из proto (новые perms present).

## TDD (RED→GREEN)

- domain `subject_test.go` (Subject/NormalizeSubjects) — RED(undefined)→GREEN.
- repo `access_binding_subjects_integration_test.go` (testcontainers PG16) — E-34 round-trip, E-30 CASCADE+per-subject-delete+RACE, batch, E-33 ListByRole — GREEN.
- use-case `create_subjects_test.go` (E-30 per-subject tuples, E-34 projection, E-32 conflict), `list_by_role_test.go` (E-33 authz), `expand_access_test.go` (E-31 group-expand/dedup/bounds) — RED→GREEN.
- real-OpenFGA `expand_access_fga_integration_test.go` (E-31 group→members) — RED(Internal: FGA Read page>100 + ListSubjects не разворачивает группу)→GREEN(рекурсивный walk + page=100).
- newman `iam-rbac-subjects.py` (RBACSUBJ-* E-30..E-34, 10 cases) — gated на gateway+deploy.

## Затронутые сущности vault

- [[../rpc/iam-access-binding-service]] (subjects[]/ExpandAccess/ListByRole)
- [[../resources/iam-access-binding]] (subjects child-table, migration 0028)
- [[rbac-rules-model-2026-subphase-D-iam]] (предыдущая под-фаза)

## DoD-чеклист

- [x] proto: subjects=19 + Subject + ExpandAccess/ListByRole, buf clean, generate
- [x] migration 0028 access_binding_subjects (FK CASCADE, UNIQUE, backfill)
- [x] iam: per-subject tuple-set/ledger/revoke + NormalizeSubjects + E-34 dual projection + group-amplification guard
- [x] iam: ExpandAccess (FGA userset walk) + ListByRole (scope-filter)
- [x] RED→GREEN: domain unit + repo integration (testcontainers) + use-case unit + real-OpenFGA ExpandAccess
- [x] gateway: ExpandAccess/ListByRole public mux (api-gateway-registrar)
- [x] newman E-cases authored (gated on deploy)
- [x] CI pin kacho-proto → rbac-rules-e-proto (iam + gateway workflows)
- [ ] commit/push + PR (НЕ выполнено — owner gate)
- [ ] UI multi-subject grant-форма (sub-phase E UI — отдельно)
- [ ] live newman green after gateway+deploy merge

## Security review follow-up (branch `rbac-rules-e-iam`, поверх 4a32141)

system-design/security review под-фазы E дал 4 находки по `ExpandAccess`/`ListByRole`. Фикс в коде — В2/В3/E-32b; В1/В4 — issues.

- **В3 (security MUST-FIX, исправлено):** `ExpandAccess` гейтил только anti-anon floor → любой authenticated мог развернуть «кто может X» на ЛЮБОМ (в т.ч. чужом) объекте — раскрытие authz-топологии/членства = under-authorized метод. **Fix:** per-object `requireGrantAuthority(ctx, repo, relations, objectType, objectID)` ДО userset-walk (read==enforce, паритет с `ListByResource`/`ListByRole`); чужой → `PERMISSION_DENIED`. `requireGrantAuthority` сделан nil-repo-safe (leaf FGA-объекты авторизуются чисто через FGA admin-path). Wired в `wiring.go` (`WithGrantAuthority(kachoRepo, relationStore, logger)`).
- **В2 (hardening, исправлено):** `relation` форвардился verbatim в FGA Read → probe произвольных relation-строк. **Fix:** `authzmap.IsExpandableRelation` closed-set (per-verb `v_get/v_list/v_create/v_update/v_delete` + tier `viewer/editor/admin` + `member`); unknown → `INVALID_ARGUMENT`.
- **E-32b (тест-долг, добавлено):** unit `TestCreate_E32b_GroupSubject_NoGrantAuthority_Denied` — GROUP-subject + editor-tier binding БЕЗ grant-authority → `PERMISSION_DENIED`, 0 tuple'ов (негативная ветка group-amplification guard; раньше покрыта только E-32a conflict).
- **В1 ([[197]] enhancement):** `maxExpandDepth` обрывает весь обход вместо пропуска одной over-deep ветки → деградация полноты аудита. Не фиксили (scope=security), issue заведён.
- **В4 ([[198]] tech-debt):** `ListByRole` pre-filter `next_page_token` → пустые/короткие страницы + O(page_size) FGA-Check амплификация. Issue заведён.

**TDD:** RED доказан — пакет не компилировался без `WithGrantAuthority`; дополнительно временно-отключённый gate → `TestExpandAccess_В3_ForeignObject_Denied` FAIL (foreign-object раскрывался), gate восстановлен → GREEN. Unit (`expand_access_authz_test.go` В3/В2 + E-32b) + real-OpenFGA integration (`TestExpandAccess_В3_ForeignObject_DeniedRealFGA`) + newman (`RBACSUBJ-EXPAND-FOREIGN-DENIED` 403 / `RBACSUBJ-EXPAND-VAL-RELATION` 400). go build + gofmt + vet + full short suite зелёные.

## Group-membership FGA mirror fix (branch `rbac-rules-e-iam`, поверх 1409e1e → 9e4f2e6)

E-31 `RBACSUBJ-EXPAND-GROUP-OK` вскрыл баг ШИРЕ ExpandAccess — вся group-based авторизация была сломана.

- **Баг:** `AddMember` писал ТОЛЬКО `kacho_iam.group_members` (iam DB) и НЕ эмитил FGA member-tuple. AccessBinding с group-субъектом эмитит userset-tuple `<obj>#<rel>@group:<gid>#member` (tuples.go `subjectRef`), но без `group:<gid>#member@user:<uid>` в FGA этот userset резолвился в ПУСТО → члены группы не получали реального доступа, `ExpandAccess` не находил членов (2 fail: concrete member userAAA/userAAB). `RemoveMember` — симметрично (не снимал).
- **Fix (co-commit через fga_outbox, SEC-D / запрет #10):**
  - `AddMember.doAdd` co-commit'ит `EmitFGARelationWrite{user|service_account:<id>, member, group:<gid>}` в той же writer-tx, что `INSERT group_members`.
  - `RemoveMember.doRemove` — симметричный `EmitFGARelationDelete`.
  - **Backfill migration `0029_backfill_group_member_fga_tuples`**: member-tuple intent для всех существующих `group_members` (идемпотентно `WHERE NOT EXISTS`; `member_type` = FGA user-prefix verbatim).
- **Тип-согласованность (подтверждено):** member-tuple на FGA-тип **`group`** (userset-тип binding'а), НЕ `iam_group` (object-scope hierarchy-тип group Create). real-FGA тест GM-3 доказывает: member-tuple на `iam_group` НЕ резолвит `group:#member` userset.
- **TDD RED→GREEN:** unit (`group/member_fga_emit_test.go`, doAdd/doRemove emit — RED без emit → GREEN); real-OpenFGA (`access_binding/group_member_fga_integration_test.go` GM-1..4: member на `group`→Check allow; без tuple→deny=баг; iam_group→deny; revoke→deny); pg co-commit (`pg/group_member_fga_outbox_integration_test.go` GM-O1..3: atomic + rollback discards + symmetric); backfill (`pg/group_member_backfill_integration_test.go` GM-BF1..2). newman: E-31 зелёный + новый happy `RBACSUBJ-GROUP-GRANTS-MEMBER-OK` (Check member→allowed via group binding). go build + vet + gofmt + full short suite + targeted integration (-p 1, colima+real-OpenFGA) зелёные.
- Затронуто vault: [[../resources/iam-group]] (FGA membership mirror section).

## Связанные

- Epic «RBAC rules-model 2026» (под-фазы A–F). Следующая: F (data migration + UI + legacy cleanup).
- Security follow-up issues: [[197]] (В1 enhancement), [[198]] (В4 tech-debt).

#kac #kacho-iam #kacho-proto #kacho-api-gateway #feature #usecase #repo #proto #migrations #handler
