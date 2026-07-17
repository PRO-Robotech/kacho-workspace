# RBAC selector-seeding — keystone fix (owner-tuple e2e blocker)

Decision-record. Полное расследование — транскрипт агента a8903cc95c4aa5689.

## Диагноз (единый корень для двух e2e-блокеров)
Модель OpenFGA — **RBAC-2026 Contract-A «FLAT INDEX»**: ReBAC-каскад `<rel> from project|account`
намеренно удалён; доступ материализуется **per-object** реконсайлером iam из AccessBinding'ов.
Discovery (forward fast-path `SelectorBindingsMatchingObject` + sweep `ListSelectorBindingIDs`)
JOIN'ит `kacho_iam.role_rule_selectors`. **Строки селекторов засеяны ТОЛЬКО для owner/registry-owner/
custom ролей** (миграции 0038/0039/0043 + boot-backfill `syncOwnerRoleSelectorsTx`). Generic
system-роли (`admin`/`edit`/`view`) и per-domain (`vpc.network.admin`…) имеют `rules[]`, но БЕЗ
проекции селекторов → их binding'и невидимы discovery → project-scoped grantee (`edit`@PROJECT)
никогда не материализует `v_*` на свежесозданном объекте.
- cluster-admin → Go D-9 short-circuit (без материализации). account-owner → owner-роль имеет селекторы.
  project-admin (`edit`) → селекторов нет → 403 навсегда на своём же ресурсе.
- **Inv-1** = forward-путь (свежие объекты); **Inv-2** (catalog-flip 11056/22300) = агрегатный backfill того же
  дефекта. verify-gate `VerifyRelationSatisfiesAction` — **observational** (logger.Info, НЕ гейтит authz).
  Каталоги iam↔gateway **byte-identical**. `/operations/{id}` 403 = stale gateway image (source корректен).
- Pre-migration «работало» = каскад, который Contract-A удалил. Intended (`explicit-rbac-model.md`,
  нормативно): project-editor CRUD над контентом проекта — **first-class**; newman projadmin-автор корректен.

## Решение (option-5, decisive)
Обобщить owner-only селектор-сидинг на **ВСЕ materializing system-роли**:
1. Boot-backfill `syncOwnerRoleSelectorsTx` → `syncAllSystemRoleSelectorsTx` (idempotent UPSERT self-heal,
   проекция `domain.Rules.MaterializingSelectors()` arm-aware anchor/names/labels; edit→anchor над 16
   materializable-типами, `vpc.network.admin`→anchor над `[vpc_network]`).
2. Миграция проекции всех system-role rules → `role_rule_selectors` (детерминированно, без ожидания boot).
3. Scope-narrowing JOIN в discovery (`object.parent_project_id/parent_account_id ∈ binding.scope`) —
   correctness уже safe (containment re-verify), это bound fan-out (wildcard `*.*` owner иначе фанится на все
   типы; вероятная причина ~30s latency account-admin create в P6).
4. Lockstep guard `domain/rule_wildcard_scope_test.go` + verify/drift-гейты расширить.
5. Doc-truthfulness (security.md #5): stale «cascade»-комменты — `vpc/.../check/owner_confirm.go:62-65`,
   `vpc/.../fgaregister/fgaregister.go:7,150`, `compute/.../fgaintent/fgaintent.go:83`,
   `storage/.../fgaregister/fgaregister.go:10,133`.
6. (Отдельно, operational) пересобрать gateway-образ (operations-403); restore canonical
   `kacho-proto/.../fga_model.fga` ИЛИ починить drift-gate (сейчас silently SKIP — файла нет на диске).

Отвергнуты: (a) FGA-каскад — реверсит flat, over-grant, не аудируется; (b) probe-owner — PATCH всё равно 403;
(c) sync direct creator-tuple — orphan вне ledger, не отзывается; (d) сменить тест-автора — маскирует дефект
(допустимо лишь как временный stopgap с сохранением projadmin-регресс-лока).

## Security
Не over-грантит: реконсайлер re-verify `o.IsContainedIn(bs.Scope)` per-object (project-A editor не
материализуется на project-B), verbs bounded ролью. Scope-narrowing JOIN — bound fan-out.

## Ключевые файлы
- reconcile: `services/iam/internal/apps/kacho/api/access_binding/reconcile/reconcile.go`
- adapter (gap): `services/iam/internal/repo/kacho/pg/reconcile_adapter.go` (LoadBinding:131,
  SelectorBindingsMatchingObject:471, ListSelectorBindingIDs:871)
- owner-only seeds (обобщить): migrations `0038_owner_role_rule_selectors.sql`,`0039`,`0043`;
  boot-backfill `services/iam/internal/apps/kacho/seed/migrate_backfill.go:182 syncOwnerRoleSelectorsTx`
- system-role rules (без проекции): migrations `0031_reseed_system_roles_rules.sql`, `0001_initial.sql:2023`
- domain helpers (reuse): `domain/rule_fingerprint.go:155 MaterializingSelectors`,
  `domain/feed_registry.go:112 AllMaterializableTypes`, `domain/constants_extended.go:57 OwnerRoleRules`
- register/op-gate: `internal_iam/register_resource.go` (sync ReconcileObject); confirm-probe
  `services/vpc/internal/apps/kacho/check/owner_confirm.go`
- verify-gate: `seed/verify_gate.go:212`, `cmd/kacho-iam/serve.go:939`
- fixtures: `tests/authz-fixtures/setup.sh` (PA1→edit@PROJECT:428), vpc author `jwtProjectAdminA1`
