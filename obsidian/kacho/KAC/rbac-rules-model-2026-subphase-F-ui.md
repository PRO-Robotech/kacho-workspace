---
title: RBAC rules-model 2026 — sub-phase F (UI — F-22 rules-editor + thin grant-form)
ticket_id: rbac-rules-model-2026-F-ui
status: test
type: feature
repos:
  - kacho-ui
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-ui
opened: 2026-06-21
tags:
  - kac
  - kacho-ui
  - feature
---

# RBAC rules-model 2026 — sub-phase F (UI — F-22)

**Status**: test (code-complete на ветке `rbac-rules-f-cleancut`, НЕ закоммичено)
**Type**: feature (эпик «RBAC rules-model 2026», sub-phase F — clean-cut UI)
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` §«ПОД-ФАЗА F» F-22 (APPROVED)

## Что и зачем

Перевод UI ролей/биндингов на rules-модель (clean-cut F). Роль теперь рендерится и
авторится из `role.rules[]` (источник истины), НЕ из `permissions[]` (внутренняя
compiled-форма, в API-ответе пустая). AccessBinding стал thin: `subjects[]` +
`roleId` + `scopeRef` + `condition` — без `target`/`selector` (селекция объектов
целиком в `role.rules`).

## Затронутые сущности vault

- [[iam-role]] — публичная поверхность роли = `rules[]`; `permissions[]` не рендерится
- [[iam-access-binding]] — thin: `subjects[]`, без `target`/`selector`
- [[iam-role-service]] — UI читает `rules[]` из `Role.Get`/`List`

## Реализация (kacho-ui)

**Новое:**
- `src/components/iam/RulesEditor.tsx` — per-rule editor (modules/resources/verbs +
  resourceNames XOR matchLabels); verb-`*` разрешён (R-3), module/resource-`*`
  disabled в custom (system-only); арм выводится из формы правила.
- `src/lib/iam-target-types.ts` `parseSubjects()` — read-парсер subjects[] +
  legacy single fallback.

**Изменено:**
- `src/api/iam.ts` — `Role.rules[]` + `Rule`/`ruleArm()`; `CreateAccessBindingBody`
  = `{ subjects[], roleId, scopeRef, conditionId? }` (без target_ref); `Subject`;
  `listAccessBindingsByResource` → `listAccessBindingsByScope` (F-50 rename).
- `InlineRoleCreateForm` / `InlineRoleEditForm` / `RolesPage` модалки — RulesEditor
  вместо PermissionsEditor; шлют `rules`, не `permissions`.
- `AccessBindingCreateForm` — multi-subject (`subjects[]`, 1..32); удалены
  target/selector-режимы; шлёт `subjects[]`, не шлёт `target`/`selector`/`permissions`.
- `resource-detail-extensions` — роль рендерит `rulesView(rules[])` (3 арма),
  permissions-панель удалена; binding — `subjects[]`, «Цель» удалена.
- `resource-registry` AccessBindings list — «Цель»-колонка удалена.
- `AccessPage` — `listAccessBindingsByScope`.

**Удалено (legacy UI):** `PermissionsEditor.tsx`, `SelectorTargetPanel.tsx`(+test),
`TargetResourcesPanel.tsx`; API-хелперы `addTargetResources`/`removeTargetResources`/
`replaceTargetSelector`/`listGrantableResources`; типы `GrantableResource*`;
target object-type picker-metadata из `iam-target-types`.

## Тесты F-22 (RED→GREEN, vitest)

- `RulesEditor.test.tsx` (12) — 3 арма из rules[]; verb-`*` ок; module/resource-`*`
  отфильтрованы (system-only); arm-toggle XOR; pure `ruleInvalid`.
- `role-detail-rules.test.tsx` (4) — detail рендерит 3 арма; permissions-панель
  ОТСУТСТВУЕТ в DOM.
- `AccessBindingCreateForm.test.tsx` (14) — submit шлёт `subjects[]` и НЕ шлёт
  `target`/`target_ref`/`selector`/`permissions`; multi-subject; target-UI
  отсутствует; back-compat (assignable roles, reconcile, partial-fail).
- `iam-target-types.test.ts` — переписан на `parseScope` + `parseSubjects`.

## DoD

- [x] RulesEditor + role-форма/detail рендерят роль из `rules[]`
- [x] verb-`*` разрешён (custom), module/resource-`*` disabled
- [x] grant-форма шлёт `subjects[]`, не шлёт target/selector/permissions
- [x] legacy UI (target/selector панели, permissions-editor, target-мутатор-RPC) удалены
- [x] `ListByResource` → `ListByScope`
- [x] F-22 component-тесты RED→GREEN; `tsc -b` зелёный; `npm run build` зелёный
- [ ] commit/push (оставлено в working tree по запросу)

## Остаточные риски / заметки

- proto на ветке `rbac-rules-f-cleancut` ещё несёт legacy δ-поля
  (`target`/`target_ref`/`selector`/`permissions`) — UI их игнорирует на входе и
  устойчиво (graceful) читает на выходе; полное удаление полей из proto — F-iam/F-proto.
- pre-existing flaky `src/lib/theme-context.test.tsx` (jsdom `localStorage`
  undefined) падает и на чистой ветке — не регрессия F-22.
