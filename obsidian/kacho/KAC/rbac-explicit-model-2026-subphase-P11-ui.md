---
title: "RBAC explicit-model 2026 — sub-phase P11 (owner/deletion_protection UX + org-removal + 403 content-access) ui"
aliases:
  - rbac-p11-ui-owner-selector
  - rbac-explicit-2026-P11
ticket_id: "(epic — acceptance-anchored, MCP youtrack unavail)"
category: kac
status: test
type: feature
repos:
  - kacho-ui
tags:
  - kac
  - feature
  - kacho-ui
  - security
---

# RBAC explicit-model 2026 — sub-phase P11 (kacho-ui)

> [!note] Anchor
> Epic: [[rbac-explicit-model-2026]]. Acceptance: `docs/specs/rbac-explicit-model-2026-acceptance.md` §0 D-10/D-12, §3 B-01/B-02, §10 P11.
> PR: https://github.com/PRO-Robotech/kacho-ui/pull/114 (ветка `rbac-2026-ui-org-removal-selector`).

**Status**: 🧪 test — код-комплит на ветке; vitest (+18) + CI playwright (35) зелёные; typecheck + build зелёные. НЕ смёржено (на проверке владельца).
**Type**: feature

## Что и зачем
- **owner / deletion_protection UX (D-10)**: `AccessBinding.deletion_protection` (proto field 20) добавлен в UI-тип; `iamApi.updateAccessBindingDeletionProtection` (PATCH `update_mask=deletion_protection`). Detail «Обзор» — индикатор «Owner (системная)» + строка «Защита от удаления»; список — колонка «Защита» (тег Owner). `DeleteDialog.isProtected` блокирует «Отозвать» + alert + «Снять защиту» (Update→Delete двухслойно, образец `vpc.address`). Проброс через `DetailOverviewActions`/`RowActionsMenu`/`ResourceShell` (новый `DetailExtension.deleteProtection`).
- **selector-without-contents (B-01/B-02)**: `ErrorResult` на 403 → дружелюбная «Нет доступа к содержимому» вместо сырого PERMISSION_DENIED. Account/Project виден в switcher'е (object-only v_list), переход в контент → backend DENY → не краш (ResourceShell/ResourceListPage уже маршрутят ошибку в ErrorResult).
- **org-removal (D-12)**: удалены мёртвые legacy backend-e2e (`full-flow`/`dashboard`/`sidebar`/`list`/`create-form`/`_helpers`) на снятой Org/Cloud/Folder resource-manager модели (не в CI, dead routes); зачищены stale org-комментарии (types/resources/iam/AccessBindingsPage/ResourceDetailPage/extensions/vite.config/CLAUDE.md). Сохранены negative-assert тесты (`RESOURCE_TYPES` без organization).
- **scope/selector**: scope = account/project/cluster (на проводе `CLUSTER` = концептуальный GLOBAL, `cluster_kacho_root`); селекция в `role.rules` — уже соответствует контракту main. A-05 (`GLOBAL+all` обычной роли) отсекается backend `listAssignableRoles` + create INVALID_ARGUMENT (форма показывает inline-error). Роли рендерят rules (arm anchor/names/labels) — без изменений.

## Ground-truth
- Wire-enum scope в main = **CLUSTER** (не GLOBAL): `kacho-proto access_binding.proto` `enum Scope { SCOPE_UNSPECIFIED, CLUSTER=1, ACCOUNT=2, PROJECT=3 }`. UI «cluster» уже корректен — acceptance «GLOBAL» концептуален.
- `organization` в proto/iam — full-removed (reserved tombstones, Contract-B #86). UI имел только мёртвые комментарии + dead e2e — зачищены.

## Затронутые сущности vault
- [[iam-access-binding]] — UI-сторона `deletion_protection`/owner-индикатора.
- [[iam-access-binding-service]] — UI зовёт Update (deletion_protection clear).

## DoD
- [x] owner/deletion_protection в detail + список + protected-revoke UX
- [x] 403 «Нет доступа к содержимому»
- [x] org-следы зачищены (dead e2e + комментарии)
- [x] TDD: vitest + e2e/ci RED→GREEN
- [x] typecheck + build + CI playwright зелёные
- [ ] merge после проверки владельца
