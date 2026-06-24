---
title: "Explicit RBAC model 2026 (epic)"
aliases:
  - rbac-explicit-model-2026
  - explicit-rbac-epic
ticket_id: "(epic — acceptance-anchored, MCP youtrack unavail)"
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-deploy
  - kacho-ui
tags:
  - kac
  - epic
  - feature
  - kacho-iam
  - kacho-proto
  - kacho-api-gateway
  - security
  - architecture
---

# Explicit RBAC model 2026 (epic)

> [!note] Anchor
> Design+acceptance: `docs/specs/rbac-explicit-model-2026-acceptance.md` (43 сценария, D-1..D-18, 12 под-фаз). Re-touch эпика #109 (RBAC-rules-model). KAC-номер не заводился (MCP youtrack недоступен) — док + этот trail = anchor.

**Status**: 🔧 in-progress — **acceptance ✅ APPROVED (round-2, 2026-06-24)**. Merged: P1 proto deletion_protection (`6171077`), P2 FGA v_* (proto `6171077` + deploy #121), P3 authzmap verb-bearing (`e4fa354f`, #218), **P4 unified reconciler — ядро (`0ab8d20f`, #219)** + **P5 cluster-admin short-circuit + A-05 (`4a466633`, #221)**: short-circuit в Check+write-authz (fail-closed), A-05 GLOBAL+all guard, мёртвая cluster-ветка удалена+guard-test; system-design+go-style ✅, integration+newman зелёные. **P6 owner (полностью merged: proto#84 Update RPC `eb39fabd`, iam#222 `3f0827df`, gateway#97 `27465ebc`, workspace#114)**: owner cluster-роль (`*.*.*`, 64-я system) + Account.Create co-commit owner-binding (deletion_protection=true) + Delete-CAS-guard + Update RPC. 3 ревью ✅; CI поймал 3 регрессии от широты owner (DP-newman cross-repo→whitelist, F53 63→64, propagation rows[0]→DELETABLE) — все test-expectation, прод корректен. **P7 (list-filter viewer ∪ v_list) — PR iam#223 open**: union-фильтр account/project.List (object-only v_list → видно в селекторе без контента, B-01/B-02); un-whitelist IAM-ACB-DP (iam#222+gateway#97 в main); P6 go-style cleanup; system-design+go-style ✅, merged (`b8beeb48`, newman IAM-ACB-DP зелёный без whitelist). **Исходная цель владельца достигнута в main: account/project видны в селекторе без доступа к контенту.** iam expand-ядро (P3-P7) полностью merged. **P8 (migrate/backfill) merged (`fa227b2f`, #225)**: mig 0036 owner-binding на существующие аккаунты + singleton boot-backfill + verify-gate; **newman поймал реальный owner-binding access-баг** (Account.Create/backfill не эмитили hierarchy parent-pointer → владелец не видел свой owner-binding, 403 — латентный с P6, исправлен mig 0037→boot-emit). db-architect+system-design ✅. **Contract-блокер #224**: owner `*.*` НЕ материализует CONTENT per-object (dottedTypes скипает wildcard) — verify-gate структурно это маскирует. **#224 merged (`a5c9ea24`, #226)**: owner `*.*` материализует per-object content (wildcard→AllMaterializableTypes в BOUNDED scope; mig 0038 owner-role-selectors DB-инвариант + lockstep-guard); verify-gate расширен на owner-content (КФ-БАГ-1 закрыт). **Contract разблокирован.** **CONTRACT-A (FGA-flat: выпил каскада+scope_grant) ✅ ЗАКРЫТ** (proto-flat + iam-flat-aware #230 + deploy flat-configmap #122 в main; flat-umbrella 22/22 2× стабильно зелёный; 4 system-design ✅; implicit over-grant устранён). **CONTRACT-B (organization full-removal) — merged proto#86 + iam#238, deploy#123 в финальном CI.** Дальше P9(gateway no-op для org)/P10(deploy fe3455 live)/P11(ui)/P12(docs).
**Type**: feature (foundational, cross-repo)

## Что и зачем
Переход kacho-iam authz с ReBAC-каскадной модели (FGA `<rel> from account/project/cluster` + scope_grant computed-usersets) на **явную RBAC с per-object материализацией**. Причина: implicit hierarchy-каскад = непредсказуемый over-grant (live-находки на fe3455) + тяжёлый аудит. Цель — топ-2026: явность, аудируемость, масштаб.

## Требования владельца (нормативно)
1. Семантика ролей сохраняется (rules: module/resources/verbs/selector).
2. Доступ выдаётся ЯВНО (per-object материализация, без implicit-каскада в семантике).
3. Селекторы сохраняются: all / names / labels.
4. Scope: GLOBAL / ACCOUNT / PROJECT (folder/organization — НЕТ, удалить).

## Ключевые design-решения
- **Грант = (subject, role, scope)**; scope = ГРАНИЦА материализации, не корень наследования.
- **Энфорс = единый reconciler-движок** (расширение T3.1) материализует прямые per-object FGA-tuple для all/names/labels × scope. `scope_grant`-эмиссия удаляется (КФ-3).
- **FGA = плоский индекс**: убрать `<rel> from …`-каскады + scope_grant.
- **account/project — verb-bearing** (v_get/v_list/…); tier только для membership-write-authz, без down-cascade доступа → «видно в селекторе без контента» выпадает само.
- **owner** = net-new системная cluster-роль `*.*.* selector=all @ ACCOUNT`, авто-binding на Account.Create (forward-материализация, пустой аккаунт на Create), **deletion_protection** (как vpc.address).
- **cluster super-admin** = единственное cluster-relation + Check short-circuit (исключение из per-object); применяется и к write-authz (КФ-2). Bootstrap — InternalClusterService (KAC-196); далее public binding@GLOBAL (requireGrantAuthority=cluster-admin).
- **GLOBAL+all** валиден только для cluster-admin; прочим на GLOBAL — names/labels обязательны (иначе InvalidArgument).
- **organization** — full-removal (proto OrganizationService + account/Role.organization_id + compliance/hooks/seed).
- **Миграция** = expand→migrate→contract, forward-only/idempotent, **singleton backfill под `pg_advisory_xact_lock`** (КФ-1), continuous forward-aware verify-gate (КФ-4), no-access-loss на проде fe3455. 63 system-роли re-seed.

## Декомпозиция (12 под-фаз, build-граф)
P1 proto (scope/deletion_protection, drop org) → P1b iam org-decommission → P2 FGA-модель flat (drop cascade+scope_grant+org) → P3 authzmap verb-bearing account/project → P4 reconciler all-selectors (drop scope_grant emit) → P5 Check flat + cluster-admin short-circuit (incl write-authz) → P6 owner + deletion_protection → P7 list-filter → P8 migration re-seed+backfill → P9 api-gateway → P10 deploy → P11 ui → P12 docs.

## Затронутые сущности vault
[[../resources/iam-role]] [[../resources/iam-access-binding]] [[../resources/iam-resource-mirror]] [[../rpc/iam-access-binding-service]] [[../rpc/iam-internal-iam-service]] [[sub-phase-T3.1-cross-service-label-revoke]] [[sub-phase-1.5-assignable-roles]]

## DoD (верхнеуровневый)
- [x] acceptance APPROVED (round-2 gate, оба ревьюера)
- [x] P1..P10 + Contract-A/B под-фазы merged (P11 ui PR open, P12 docs PR open)
- [x] migration backfill ролей + bindings + owner на существующие аккаунты (no-access-loss verify) — **live fe3455: backfill 90 bindings, verify-gate 100% no_access_loss, forward-smoke passed**
- [x] deploy fe3455 + live-верификация — **rev 45, iam main-cf76ad4b, OpenFGA flat (0 cascade, 0 organization), verify-gate 100% no-access-loss; umbrella 22/22 поведенчески**
- [ ] vault trail per-под-фаза + закрытие (P11 ui + P12 docs merge → close)

## P10 trail (deploy fe3455 + live cutover — §9 contract live)
- **Live cutover fe3455** (helm upgrade rev 45, 2026-06-25): `kacho-iam:main-cf76ad4b` (Contract-A flat + Contract-B org-removed) + flat OpenFGA-configmap. Команда: `helm upgrade --install kacho-umbrella ./helm/umbrella -n kacho -f values.dev.yaml -f values.fe3455.yaml --wait`. Механизм fe3455: ручной helm (нет GitOps); OpenFGA-модель через `openfga-bootstrap` post-upgrade hook.
- **Ordering materialize-then-swap**: `--wait` → new iam pod Ready + backfill на старой каскадной модели (доступ цел) → post-upgrade hook пишет flat-модель (доступ через свежематериализованные tuple). Owner выбрал single-step (краткое eventual-consistency окно приемлемо на dev-стенде).
- **Live-верификация**: OpenFGA-модель flat (non-comment 0 `from account/project/cluster/organization`, `type organization` не объявлен, 29 типов); iam-логи `backfill: reconcile-sweep complete bindings_reconciled=90` → `verify-gate: 100% no-access-loss — contract phase permitted (failures=0)` → `forward-smoke passed`. Все поды healthy на cf76ad4b.
- Source-of-truth: `values.fe3455.yaml` iam tag → main-cf76ad4b (deploy#125).
- **Достигнуто**: implicit over-grant (исходная жалоба, live-находки на fe3455) устранён на проде; explicit per-object flat активен.

## P3 trail (authzmap verb-bearing account/project — expand)
- PR [kacho-iam#218](https://github.com/PRO-Robotech/kacho-iam/pull/218), ветка `rbac-p3-authzmap-verb-bearing`.
- `authzmap.TypeHasVerbRelations(account|project)` → true (D-6); drift-gate сверяет с моделью (P2 `6171077`); catalog отдаёт `hasVerbRelations=true`.
- **Insulation (#177 guard)**: emitter `scope_grant_tuples.go` ветка scope_grant гейтится на `tierScopeTypes`, НЕ на verb-bearing флаге — иначе dangling-write `sg_account@account:…` (модель не имеет sg_account/sg_project carrier). Прямая per-object v_* материализация (B-01/B-02) отложена в P4; binding-time scope_grant путь удаляется в P4 (КФ-3). Виалидировано system-design-reviewer.
- Файлы: `internal/authzmap/fga_types.go`, `internal/authzmap/fga_model_drift_test.go`, `internal/authzmap/verb_bearing_account_project_test.go` (new), `internal/apps/kacho/api/access_binding/scope_grant_tuples.go` (insulation), `internal/apps/kacho/api/permission_catalog/usecase_test.go`.
- Каскад / viewer-tier-эмиссия / scope_grant — **НЕ тронуты** (P-contract / P4).

## P4 trail (unified reconciler — ядро / КФ-3, D-4)
- PR [kacho-iam#219](https://github.com/PRO-Robotech/kacho-iam/pull/219), ветка `rbac-p4-unified-reconciler`. **PR open** — ждёт db-architect + system-design ревью.
- **Единый материализатор**: reconciler материализует прямые per-object FGA-tuple (`<type>:<id> # v_*/tier @ subj`) для ВСЕХ селекторов — ARM_ANCHOR(all)+ARM_NAMES+ARM_LABELS × scope-границу. `desiredMembers` диспетчеризует по арму (all→`MatchAllInScope`, names→`MatchByIDs`, labels→`MatchSelector`); containment re-verify по scope.
- **scope_grant emit удалён ЦЕЛИКОМ** (D-4): `scope_grant_tuples.go` удалён; `buildBindingTuples` rules-ветка → только hierarchy parent-pointer (membership-write-authz, D-7). Obsolete scope_grant unit/FGA-тесты удалены, FGA-harness → `fga_test_helpers_test.go`. **FGA-модель-каскад НЕ тронут** (contract-фаза §9).
- **forward-materialization** (C-01b): `role_rule_selectors` (mig **0034** += `arm`+`resource_names`, arm-aware shape CHECK) хранит ВСЕ армы → fast-path `SelectorBindingsMatchingObject` arm-aware (anchor→type, names→type+id, labels→type+labels) → ресурс, созданный ПОСЛЕ гранта, материализуется на mirror-change event.
- **КФ-1**: `pg_advisory_xact_lock(hashtext(binding_id))` (xact-scoped) первым стейтментом reconcile-tx + SELECT FOR UPDATE + ledger PK backstop → exactly-once под N репликами (H-05).
- **ВЗ-3 co-commit**: материализация + ledger + outbox + advisory-lock — одна reconcile writer-tx.
- TDD: `reconcile_unified_p4_integration_test.go` (8 testcontainers: A-01/A-02/A-04/C-01b×2/E-03/H-05) RED→GREEN; unit anchor/names/labels+lock. Регрессия C-22..C-26/DB1/DB2 зелёные.
- Файлы: `internal/domain/rule_fingerprint.go` (`MaterializingSelectors`/`RuleSelector`), `internal/apps/kacho/api/access_binding/reconcile/reconcile.go`, `internal/repo/kacho/pg/reconcile_adapter.go`, `internal/repo/kacho/pg/resource_mirror/reader.go`, `internal/repo/kacho/pg/role_repo.go` (`ReplaceRuleSelectors([]RuleSelector)`), `internal/repo/kacho/role/iface.go`, `internal/migrations/0034_role_rule_selectors_all_arms.sql`, `internal/apps/kacho/api/{role,access_binding}/*.go`.
- **Отложено в follow-up**: A-05 GLOBAL+all sync INVALID_ARGUMENT (требует sync role-read в Create.Execute — отдельная request-path-поверхность). → **закрыто в P5**.

## P5 trail (Check flat + cluster-admin short-circuit + A-05 — D-9/D-06/D-07/КФ-2)
- Ветка `rbac-p5-check-shortcircuit` от `0ab8d20f`. PR open — ждёт system-design + go-style.
- **Плоский super-gate `authzguard.IsClusterAdmin`/`SubjectIsClusterAdmin`** (`internal/authzguard/cluster_admin_shortcircuit.go`): одна relation-Check `cluster:cluster_kacho_root#system_admin@subj` (НЕ `<rel> from cluster`-каскад). fail-closed (nil checker/anon/empty/Check-err → false). ctx-вариант (write-authz) + subject-string-вариант (Check).
- **Check + write-authz применение (КФ-2)**:
  - `authorize_service.Check` + `CheckRelation` → short-circuit ALLOW до per-object резолва (D-02); `AuthorizeServiceConfig.ClusterAdminChecker` (nil-safe, additive); wired `relationStore` в `cmd/kacho-iam/wiring.go`.
  - `requireGrantAuthority` (Path 0) + `fgaHoldsAdmin` (`helpers.go`) → cluster-admin проходит на чужой account (D-06) и над `iam_access_binding`-объектами (D-07). Additive РЯДОМ с owner/FGA-admin путями (каскад не тронут — expand §9).
- **A-05/A-05b/A-05c sync-валидация** (`CreateAccessBindingUseCase.validateGlobalAllSelector`, `create.go` request-path до Operation): GLOBAL(=cluster scope) + ARM_ANCHOR(selector all) + роль НЕ `*.*.*` → sync `INVALID_ARGUMENT` «GLOBAL scope requires names or labels selector for non-cluster-admin roles». GLOBAL+names/labels (A-05b) OK; GLOBAL+all для `*.*.*` cluster-admin роли (A-05c) OK. Domain-предикаты `Rules.HasAnchorRule()` + `Role.IsClusterAdminRole()` (`internal/domain/role_cluster_admin.go`, system-gated). NB: в proto/domain **нет GLOBAL-tier** — GLOBAL == cluster scope (`resource_type=="cluster"`, `cluster_kacho_root`).
- **Guard-test dead cluster scope-self** (scope item 5): `scopeSelfTuples` cluster-ветка была недостижима (gated на `iam.cluster` ∉ objectTypes) → ветка удалена с явным комментарием «cluster обслуживается D-9», добавлен guard-тест `scope_self_cluster_guard_test.go` (cluster scope-self не эмитит per-object — страхует Q-2/D-9 от регрессии при будущем `iam.cluster`).
- **Expand-дисциплина**: FGA-модель-каскад НЕ тронут (contract §9); short-circuit additive.
- TDD RED→GREEN: unit `role_cluster_admin_test.go`, `cluster_admin_shortcircuit_test.go` (authzguard + access_binding), `authorize_shortcircuit_test.go` (service), `create_global_all_validation_test.go` (A-05/A-05b/A-05c), guard-test reconcile. newman A-05 negative `IAM-ACB-CR-GLOBAL-ALL-NONADMIN-REJECT` (cluster GLOBAL+all с ROLE_VIEW `*.*.{get,list,read}` → 400); A-05c happy = существующий `IAM-ACB-CR-CLUSTER-OK` (ROLE_ADMIN `*.*.*`). build/vet/gofmt + `-race` зелёные; access_binding+cluster integration (testcontainers) зелёные.
- Файлы: `internal/domain/role_cluster_admin.go`(+test), `internal/authzguard/cluster_admin_shortcircuit.go`(+test), `internal/service/authorize_service.go`(+test), `internal/apps/kacho/api/access_binding/{helpers,create}.go`(+tests), `internal/apps/kacho/api/access_binding/reconcile/tuples.go`(+guard-test), `cmd/kacho-iam/wiring.go`, `tests/newman/cases/iam-access-binding.py`.

## P7 trail (list-filter viewer ∪ v_list — D-6/D-16, B-01/B-02)
- PR [kacho-iam#223](https://github.com/PRO-Robotech/kacho-iam/pull/223), ветка `rbac-p7-list-filter` от `3f0827df`.
- **Union list-filter**: `AccountService.List`/`ProjectService.List` visibility = `ListObjects(viewer) ∪ ListObjects(v_list)` (dedup, use-case-слой). На плоской модели account/project verb-bearing (D-6, P3) без `from account` каскада → object-only грант `iam.account|project.{get,list}` (names/labels) материализует только `<type>:<id> # v_list @ subj` → объект **виден в селекторе**, но Check на содержимое внутри → DENY. Это ИСХОДНАЯ цель владельца «видеть account/project без доступа к контенту».
- **SEC-L сохранён**: anon→empty до FGA (INV-3); operator-SA system_viewer floor видит ВСЁ через viewer-ветку (INV-2); FGA-ошибка на ЛЮБОЙ relation → fail-closed Unavailable, без degraded/partial (INV-7); owner-via-account ветка project.List сохранена.
- **TDD RED→GREEN**: unit `list_vlist_union_test.go` (account+project: v_list-only visible / viewer regression / union+dedup / foreign no-leak / operator-floor / fail-closed); integration real-OpenFGA `list_objects_account_project_vlist_fga_integration_test.go` (object-only v_list → v_list resolves, viewer НЕ resolves, contents DENY, foreign no-leak); обновлён canonical-scenario project test (assert обе relation queried).
- **Заодно (ban #11)**: un-whitelist `IAM-ACB-DP-*` в `tests/newman/scripts/assert-suites-green.sh` (iam#222 handler + gateway#97 route в main → кейс зелёный нативно); P6 go-style cleanup (dead helper `ownerBindingsSnapshot`, stale doc-ref `account_owner_binding_integration_test.go`, unused param `domainScopeToScopeRef`).
- Ревью: system-design ✅ APPROVE (fail-closed/dedup/no-cascade/operator-floor корректны; недонаполненные пост-фильтр страницы — pre-existing list-filter pattern, не регрессия). go-style ✅ после фикса (stale doc-ref → реальный `TestCreate_SECL_EmitsOwnerAndClusterTupleInTx`, `b958684`).
- Файлы: `internal/apps/kacho/api/account/list.go`, `internal/apps/kacho/api/project/list.go` (+ unit-тесты), `internal/apps/kacho/api/access_binding/list_objects_account_project_vlist_fga_integration_test.go`, `internal/apps/kacho/api/project/list_authz_test.go`, `internal/apps/kacho/api/account/create_test.go`, `internal/dto/toproto/access_binding.go`, `internal/repo/kacho/pg/account_owner_binding_integration_test.go`, `tests/newman/scripts/assert-suites-green.sh`.
- **NB**: iam list-filter gate = SEC-L/P7 unit+integration filter-тесты (`make audit-list-filter` — vpc/compute CI-гейт, в iam отсутствует).

## Связанные
- [[sub-phase-T3.1-cross-service-label-revoke]] — materialization-движок (фундамент)
- [[sub-phase-1.5-assignable-roles]] — assignability
- эпик #109 (RBAC-rules-model) — этот эпик его re-touch
- follow-up: api-gateway#96 (поглощается), kacho-iam#217, kacho-vpc#165

#kac #epic #feature #kacho-iam #security #architecture

## P8 trail (migrate-backfill + verify-gate — D-17 / КФ-1/КФ-4/КФ-5, §9 migrate)
- Ветка `rbac-p8-migrate-backfill` от `origin/main` (несёт P1-P7). PR open — ждёт db-architect + system-design ревью.
- **MIGRATE-фаза expand→migrate→contract**: каскад/scope_grant/org НЕ тронуты (это contract — следующая фаза). P8 только ДОБАВЛЯет explicit-материализацию (no-access-loss, H-01).
- **Owner-binding backfill на существующие аккаунты** (mig **0036**, idempotent data-migration): для каждого account без активного owner-binding → INSERT `AccessBinding(subject=owner_user_id, role=owner rol72122ce96bfec66e2, scope=ACCOUNT, deletion_protection=true)` + projected subject-row. Детерминированный id `'acb'||substr(md5('owner-binding:'||a.id),1,17)`. Idempotent через `WHERE NOT EXISTS` + partial-UNIQUE `access_bindings_active_grant_uniq` (H-02). Per-object tuples НЕ в миграции — forward через reconcile-sweep (D-8a). Тот же SQL экспортирован `seed.BackfillOwnerBindings` (для post-goose аккаунтов).
- **Singleton reconcile-backfill sweep** (`seed.BackfillRunner.RunOnce`, КФ-1): process-wide `pg_try_advisory_lock(0x50384246 "P8BF")` non-blocking → exactly ONE executor под N репликами (H-05); chunked keyset-pagination по active bindings (КФ-5, ChunkSize default 500); каждый binding → `reconcile.ReconcileBinding` (своя writer-tx + per-binding `pg_advisory_xact_lock`). Idempotent/commutative с live forward-mat (H-04, ledger partial-UNIQUE backstop).
- **Verify-gate** (`seed.VerifyGate`, КФ-4 forward-aware): `Verify` — no-access-loss: каждый binding с >=1 ACTIVE `access_binding_target_member` (вердикт самого reconciler, НЕ heuristic) обязан иметь непустой ledger; пустой ledger при ACTIVE member → failure. `ForwardSmoke(spec)` — создаёт свежий mirror-объект под REGULAR селектор-binding, гонит `ReconcileObject`, проверяет ledger, убирает synthetic-объект (H-06). Гейтит contract.
- **КФ-БАГ-1 (находка system-design)**: owner `*.*.*` НЕ forward-материализует CONTENT (`domain.dottedTypes` скипает wildcard для ВСЕХ scope, не только GLOBAL) — баг vs C-01b/D-8a, **contract-блокер**, отдельный issue kacho-iam#224. P8 verify-gate forward-smoke поэтому таргетит implemented REGULAR-селектор путь (H-06 «матчащим селектором»), НЕ owner — по ruling system-design-reviewer. Owner no-access-loss всё равно покрыт `Verify` (scope-self на `account:<A>` материализуется).
- **Wiring**: one-shot best-effort backfill task в `cmd/kacho-iam/serve.go` (BackfillOwnerBindings → RunOnce → Verify, логируется), non-fatal; steady-state reconciler-worker держит сходимость дальше.
- **TDD RED→GREEN**: `internal/repo/kacho/pg/migrate_backfill_p8_integration_test.go` (5 testcontainers: P8-01 owner-backfill idempotent, P8-02 sweep materializes scope-self, P8-03 singleton concurrent N=6 → ровно 1 executes + 0 dup ledger, P8-04 chunked >=3 chunks, P8-05 verify-gate no-access-loss + forward-smoke). RED: undefined symbols → роль-regex → over-flagging heuristic → GREEN. `-race` зелёный. build/vet/gofmt + short-tests зелёные. newman `IAM-ACB-OWNER-P8-NOACCESS-LOSS` (owner-binding present via listBySubject + deletion-protected Delete→sync 400/409).
- Файлы: `internal/migrations/0036_backfill_owner_bindings_existing_accounts.sql`, `internal/apps/kacho/seed/{migrate_backfill,verify_gate}.go`, `internal/repo/kacho/pg/backfill_adapter.go`, `cmd/kacho-iam/serve.go`, `internal/repo/kacho/pg/migrate_backfill_p8_integration_test.go`, `tests/newman/cases/iam-access-binding.py`.

## Contract-A trail (FGA-flat: снятие каскада+scope_grant — §9 contract) ✅ ЗАКРЫТ
- **Суть**: убрать implicit hierarchy-каскад (`<rel> from account/project/cluster`) + scope_grant из FGA-модели → доступ ТОЛЬКО через explicit per-object материализованные tuple. Это финальный шаг (expand→migrate→**contract**), снимающий over-grant.
- **proto**: `fga_model.fga` flat (cascade removed 1119→506) — merged proto-main.
- **iam #230** (`20db4b3d`): forward-mat owner/creator content под flat + **sync live FGA-write own-object на create-путях** (паттерн invite.go: `WithSyncFGA`/`NewSyncFGAWriter`/`applyAfterCommit` ПОСЛЕ commit, outbox durable backstop) + **batch-chunking** OpenFGA WriteTuples ≤100 + per-tuple retry (computed-only-tier sibling `iam_role#viewer` роняла весь batch #232) + **bootstrap signup → owner-binding + reconcile + self-tuple** (был admin-binding без reconcile) + **project.Create sync ReconcileObject** (единственный create без него) + newman harness-fix (gen.py globally-unique step names — un-mask false-green iam-access-binding) + poll-for-propagation на read-after-write e2e (flat eventually-consistent на grant→access).
- **deploy #122** (`f869c8e5`): flat configmap (openfga-model-stub из flat fga_model).
- **Корень всего хвоста** (5+ раундов): flat → доступ через материализованный per-object tuple, а запись в OpenFGA была async-drain → «create→сразу GET» гонка. Фикс — sync live-write + batch-chunking. flat-umbrella сошёлся 73→24→…→0 forward-mat-класс, **2× стабильно зелёный** (run 28121789889 ×2, 22/22).
- **system-design ✅** (drain-vs-done/sync-live-write): no-dual-write (live-write ПОСЛЕ commit, outbox co-committed→durable), идемпотентно (already_exists no-op + collector-dedup), fail-open-to-async (durability цела), нет реинтродукции каскада, граф ацикличен, ban#10/#5 соблюдены.
- **#235** revert TEMP-PIN (deploy ref→main, iam main newman здоров).
- Follow-up issues: iam#232 (закрыт в #230), #234 Account.Delete dangling owner-binding, #236 per-tuple-retry-cap, #237 double-tx-load.

## Contract-B trail (organization full-removal — D-12a/G-03, P1b)
- **proto #86** (`05d1904e`, merged): удалён `organization.proto` (OrganizationService never live-registered); `Account.organization_id`(tag 7)+`Role.organization_id`(tag 9) → reserved-tombstone (+`tombstone_enforce.sh` Case 3); `fga_model.fga` — удалён `type organization`+все `from organization` (модель flat cluster→account→project, `is_valid:true`); bonus — orphaned `compliance_report{,_service}.proto` (KAC-223 dead). buf-breaking осознан (5 expected, continue-on-error+tombstone).
- **iam #238** (`cf76ad4b`, merged): новая миграция НЕ нужна (DB-side org-decommission уже в применённой `0008_drop_organizations.sql` — DROP table+columns+roles_scope_xor; ban#5); удалён dead `"organization"` case из `DeriveFromResourceType`+table-test; comment cleanup.
- **deploy #123**: configmap regen (org из FGA ушёл) + dead OPA `deny_org_scim_mismatch.rego` removal — финальный CI.
- gateway — **no-op** (нет live OrganizationService-регистрации/org-route; org-mentions = retired resourcemanager/organizationmanager product + load-bearing security regression-test).
- Ревью: **proto-api ✅** (tombstone-гигиена, buf, FGA valid, grep-0, compliance orphaned), **db-architect ✅** (0008 канонична, новая миграция не нужна, data-integrity цела).
- **grep-0 (G-03)**: 0 live organization/OrganizationService в proto/iam/deploy (остаток = reserved-tombstone + removal-doc + immutable mig 0008).
- Follow-up: iam#239 (dead org-branch в PL/pgSQL `access_bindings_scope_default()` mig 0005, безвреден), deploy#124 (dead COMPLIANCE_REPORT_WORKER env).
- **Token-scope урок**: gh-OAuth-app не мержит PR, меняющие `.github/workflows/` → restore workflows из main (`git checkout origin/main -- .github/workflows/`) до merge (workflow-diff=0).
