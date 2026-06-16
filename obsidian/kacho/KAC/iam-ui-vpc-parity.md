---
title: "IAM UI ↔ VPC parity (sub-phase 2.1) — UI-only epic"
aliases:
  - iam-ui-vpc-parity
  - sub-phase-2.1
vault_label: iam-ui-vpc-parity
ticket_id: "(none — owner-waived)"
category: kac
status: in-progress
type: feature
repos:
  - kacho-ui
  - kacho-workspace
prs: []
yt_url: "(none — ticket waived by owner 2026-06-17)"
opened: 2026-06-17
tags:
  - kac
  - feature
  - kacho-ui
  - kacho-workspace
---

# IAM UI ↔ VPC parity (sub-phase 2.1)

> [!note] UI-only, backend неизменен
> Задача: раздел **IAM** в `kacho-ui` визуально и механически = разделу **VPC**
> (registry-driven движок). Backend/proto **не трогаются** (ban-scope). Тикет
> YouTrack по решению владельца не заводился; ветка во всех затронутых репо =
> `feature/iam-ui-vpc-parity`.

**Status**: in-progress
**Acceptance (APPROVED)**: [[../../../docs/specs/sub-phase-2.1-iam-ui-vpc-parity-acceptance|sub-phase-2.1-iam-ui-vpc-parity-acceptance]] (73 сценария §A–§J, `acceptance-reviewer` round 3).
**Дизайн-источник**: [[../../../docs/specs/sub-phase-1.x-ui-yc-redesign-plan|YC-redesign 1.x]] (VPC облик).

## Что и зачем

8 IAM-поверхностей (Account / Project / User / ServiceAccount / Group / Role /
AccessBinding / Access page) приводятся к VPC-движку: `ResourceListPage` (фильтр +
CTA + kebab + 3s-polling) · `ResourceShell` (path-табы Обзор/Операции/JSON) ·
`REGISTRY`-спеки + `DETAIL_EXTENSIONS` · modal-flow `?modal=<spec>-create|edit` ·
`PanelHeader`/`CopyableId`/`StatusBadge`. Решения D-1..D-5: полный паритет;
Access-страница bespoke+косметика; AccessBinding registry-detail + bespoke
3-view list; Project — лёгкая ResourceShell-деталь.

## Фазы / прогресс

| # | Фаза | Status | Коммит (kacho-ui) |
|---|---|---|---|
| 1 | Acceptance APPROVED | ✅ | workspace `f1e4be9` |
| 2 | Registry specs (groups/roles/access-bindings + users/SA) | ✅ | `e0fa307` |
| 3 | StatusBadge IAM tones + reorder | ✅ | `e0fa307` |
| 4 | List pages → ResourceListPage | ✅ | `53a3ed9` |
| 5 | Detail → ResourceShell + DETAIL_EXTENSIONS | ✅ | `b79f571` |
| 6 | Forms → roles permissions-editor + modal | in-progress | — |
| 7 | Nav / breadcrumbs / Access cosmetics | in-progress | — |
| — | Tests (vitest + e2e:ci RED→GREEN) + verify | in-progress | — |

> [!note] Верификация Phase 4+5 (мной)
> `tsc --noEmit` 0 ошибок · `npm run build` OK · vitest 180 pass / 6 fail
> (pre-existing `theme-context` localStorage — НЕ в CI). `e2e:ci` (CI-гейт) — 7
> устаревших IAM-спеков (roles-tabs, iam-walkthrough) чинятся под новый UI
> (Segmented-фильтр ролей, IamScopedListShell, generic CTA).
>
> Находки Phase 4/5: `GlobalResourceFormModal` уже покрывает `/iam/*` (IamLayout
> вложен в Layout) — отдельный mount не нужен; `projects.childRoute` удалён (drill
> → `/iam/projects/:uid`, VPC-дашборд через «Открыть в VPC»); фикс header-slot
> loop (мемоизация breadcrumb/CTA-нод). Регресс: roles-create через generic-модалку
> терял permissions → Phase 6 добавляет permissions-editor (4-сегментный).

## Затронутые сущности vault (read-only ссылки; backend неизменен)

IAM-ресурсы, чьи UI-поверхности мигрируют (записки backend-модели не менялись):
[[../resources/iam-account]] · [[../resources/iam-project]] · [[../resources/iam-user]] ·
[[../resources/iam-service-account]] · [[../resources/iam-group]] · [[../resources/iam-role]] ·
[[../resources/iam-access-binding]].

## Найдено при реализации (proto-сверка)

- **ServiceAccount.enabled** — output-only (нет в Create/Update/verb) + у SA **нет
  labels**. Acceptance §C поправлен: edit SA = `name`/`description`; `enabled`
  read-only. (Аналогично ранее: `AccessBinding.status` не был объявлен в TS-клиенте.)
- **ListRoles** не требует account_id (filter is_system/account_id/name) → roles
  list **global**; **ListGroups** требует account_id → groups list account-scoped.

## DoD (см. acceptance §6)

- [x] Registry specs (#1)
- [x] StatusBadge / cells (#2)
- [x] List pages (#3) — `53a3ed9`
- [x] Detail + DETAIL_EXTENSIONS (#4) — `b79f571`
- [ ] Forms (#5) — roles permissions-editor in-progress
- [ ] Nav / breadcrumbs (#6) — Access cosmetics in-progress
- [ ] Tests RED→GREEN + `tsc`/build/`e2e:ci` зелёные (#7)
- [ ] Trail обновлён (этот файл) + статус (#8)

## Связанные тикеты

- [[KAC-127]] — Production-Ready IAM (backend baseline; этот UI поверх него)
- [[KAC-124]] — resource-manager → IAM Account/Project (prerequisite)
- [[KAC-125]] — User per-Account + Invite (invite-flow, переиспользуется)
- [[KAC-121]] — YC-style role model (permissions-грамматика)

#kac #feature #kacho-ui #kacho-workspace
