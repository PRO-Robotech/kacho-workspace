---
title: "IAM UI ↔ VPC parity (sub-phase 2.1) — UI-only epic"
aliases:
  - iam-ui-vpc-parity
  - sub-phase-2.1
vault_label: iam-ui-vpc-parity
ticket_id: "(none — owner-waived)"
category: kac
status: done
type: feature
repos:
  - kacho-ui
  - kacho-workspace
prs:
  - PRO-Robotech/kacho-ui@9059e3a (merge to main, no-PR per owner)
  - PRO-Robotech/kacho-workspace@760512a (merge to main)
yt_url: "(none — ticket waived by owner 2026-06-17)"
opened: 2026-06-17
closed: 2026-06-17
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

**Status**: ✅ done — merged to `main` (kacho-ui `9059e3a`, kacho-workspace `760512a`) + deployed to external cluster `fe3455-client` (UI `prorobotech/kacho-ui:main-9059e3ad`, rollout rev 3, pod Ready).
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
| 6 | Forms → roles permissions-editor (4-сегм) + modal | ✅ | `61eb351` |
| 7 | Access page chrome cosmetics | ✅ | `41c5260` |
| 8 | e2e:ci specs под новый UI (RED→GREEN) | ✅ | `b64a198` |
| 9 | Merge to main + push (CI собрал образ) | ✅ | ui `9059e3a` / ws `760512a` |
| 10 | Deploy на fe3455-client | ✅ | `main-9059e3ad` |

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
- [x] Forms (#5) — roles permissions-editor 4-сегм `61eb351`
- [x] Nav / breadcrumbs (#6) — Access cosmetics `41c5260`
- [x] Tests RED→GREEN + `tsc`/build/`e2e:ci` зелёные (#7) — e2e:ci 27 passed `b64a198`
- [x] Trail обновлён (этот файл) + статус → done (#8)

## Merge + deploy (2026-06-17)

- **Merge → main** (`--no-ff`, прямой merge по решению владельца, без PR/тикета):
  kacho-ui `377a187..9059e3a`, kacho-workspace `bfaee4a..760512a`.
- **CI**: push в main → `kacho-ui/docker-build.yml` (run 27652461514, success) собрал и
  запушил multiarch `docker.io/prorobotech/kacho-ui:main-9059e3ad`.
- **Deploy**: внешний кластер `fe3455-client` (ns `kacho`, helm `kacho-umbrella`).
  `kubectl set image deploy/ui ui=…:main-9059e3ad` → rollout rev 3, pod
  `ui-79fdc758c7` 1/1 Ready (readiness `GET /healthz`), Service endpoint
  `10.244.1.40:8080`. Backend-сервисы не трогались (остаются на текущем main).
- **Финальная верификация (локально перед merge)**: `tsc -b --noEmit` 0 ошибок ·
  `npm run build` OK · `e2e:ci` 27 passed / 0 failed · vitest 180 passed (6
  pre-existing `theme-context` localStorage-фейлов — НЕ в CI).

## Follow-up: chrome cleanup IamLayout (2026-06-17)

По запросу владельца («убери») — убрана верхняя шапка раздела IAM: заголовок
«Identity and Access Management» + описание, dev-баннер «Auth-flow не активирован
(E0)» и **горизонтальный таб-бар**. Навигация по 7 разделам IAM переехала в левый
сайдбар (`service-modules` module `iam` уже содержал все leaves) — паритет с VPC.
Account-селектор оставлен (scope account-scoped ресурсов). `IamLayout.tsx`
−114/+57; `e2e/ci/iam-walkthrough` обновлён (убраны ассерты title/tab-bar).
- **Merge → main**: kacho-ui `9059e3a..0c3456f`. CI docker-build (run 27653571576,
  success) → `prorobotech/kacho-ui:main-0c3456f7`.
- **Deploy**: `fe3455-client` `set image deploy/ui` → pod `ui-547894677c` 1/1 Ready.
- Верификация: `tsc -b` 0 · `e2e:ci` 27/0.

## Follow-up: detail parity — edit-in-panel + full-height + drop IamLayout (2026-06-17)

По запросу владельца ещё три правки «как в VPC»:
1. **Edit IAM-ресурсов → зона-3 ResourceShell** (`mode=edit` → `InlineResourceForm action=edit`), а не модалка — системно: `ResourceListPage.editAsPanel = panelForms || isIam`, `RelatedTable` editAsPanel для IAM-детей. (Кнопка на детали уже вела на панель; чинило list/child kebab, который слал `?modal=*-edit`.) CREATE у IAM остаётся модалкой.
2. **Убрана IamLayout-обёртка** целиком — IAM-роуты рендерятся напрямую под `Layout` (как VPC): убран дублирующий Account-`<Select>` (account уже в пилюле `ContextBreadcrumb` шапки → `context-store.account`); detail-фон растягивается на весь экран (`.kc-surface{minHeight:100%}` в `flex:1` content, не зажат `<Space>`). Нав по разделам — левый `ServiceSidebar` (module `iam`, уже содержал все leaves). `IamLayout.tsx` удалён.
3. `e2e/ci/iam-walkthrough` обновлён (нет таб-бара/in-content селектора).
- **Merge → main**: kacho-ui `0c3456f..83c6614`. CI docker-build (run 27654186773, success) → `prorobotech/kacho-ui:main-83c66146`.
- **Deploy**: `fe3455-client` → pod 1/1 Ready, live `main-83c66146`.
- Верификация: `tsc -b` 0 · `e2e:ci` 27/0.

## Follow-up: detail/list refinements (2026-06-17)

7 правок по запросу владельца (clarity & parity):
1. **account_id → `IamRefLink`** в таблицах projects/SA/groups/roles + новая «Аккаунт» колонка у users (кликабельная ссылка иконка+имя на `/iam/accounts/:id`, как `subnet→network`).
2. **ServiceAccount** — убран «статус»/`enabled` (колонка + строка обзора); proto не даёт сеттера, путал.
3. **ServiceAccount** — убран `project_id` из обзора (главный реф — account_id).
4. **Группы** — участники перенесены из extra-tab в `overviewBelow` (как `SubnetCidrPanel` у подсетей); добавление селекторами; участники — `IamRefLink`.
5. **Account** — убран `organization_id` из обзора (нерелевантен tenant-UI).
6. **AccessBindings → единая таблица** (`listByAccount`, account из context-пилюли шапки): субъект/роль/ресурс/статус/область одной таблицей. Убраны 3-view Segmented + «Мои AccessBinding'и». Create/Отозвать сохранены; пусто без account → Empty.
7. **Иконки IAM** были = VPC (Apartment/Cluster/NodeIndex/Safety/Api/Gateway) → даны отдельные: accounts=Bank, projects=Project, users=User, service-accounts=Robot, groups=Team, roles=SafetyCertificate, access-bindings=Key (синхронно `ResourceIcon` ↔ `service-modules`).
- **Merge → main**: kacho-ui `83c6614..a45eb6e` (3 коммита). CI docker-build (run 27655820143, success) → `prorobotech/kacho-ui:main-a45eb6e4`.
- **Deploy**: `fe3455-client` → pod 1/1 Ready, live `main-a45eb6e4`.
- Верификация: `tsc -b` 0 · `npm run build` OK · `e2e:ci` 27/0 · vitest 179 pass (6 pre-existing theme-context).

## Follow-up r3: group members + AccessBinding create/detail (2026-06-17)

- **Группы — участники в Обзоре в едином CIDR-стиле** (`SubnetCidrManager.CidrSection`-паттерн): `SectionHeader` «Участники (N)» + bordered `kc-grid-table` [Тип | Участник (`IamRefLink`) | Добавлен | ⌫] + add-row через `Space.Compact` (Type-Select + member-Select + dashed «Добавить»), spinner на изменяемой строке. `GroupMembersPanel` переписан.
- **AccessBinding create → full-page** (`/iam/access-bindings/create` → `AccessBindingCreatePage`, FormShell+FormFooter, как VPC-create) вместо bespoke AntD Modal («наш подход»). CTA + cluster-admin deep-link (`ClusterAdminsPage`) ведут на страницу; legacy `?modal=…` редиректят.
- **Роль — Cascader** module→resource→verb (хелперы вынесены в `src/components/iam/roleCascader.ts`, переиспользуются `AccessPage` + create-page; system/custom Segmented).
- **Ресурс — типизированный дропдаун** по `resource_type`: account→`listAccounts`, project→`listProjects(account)`, cluster→фикс `cluster_kacho_root`.
- **AccessBinding detail**: строки единой таблицы кликабельны → `/iam/access-bindings/:uid` (revoke/ссылки stopPropagation).
- **Merge → main**: kacho-ui `a45eb6e..2c54139` (5 коммитов). CI docker-build (run 27657040322, success) → `prorobotech/kacho-ui:main-2c541397`.
- **Deploy**: `fe3455-client` → pod 1/1 Ready, live `main-2c541397`.
- Верификация: `tsc -b` 0 · `npm run build` OK · `e2e:ci` 28/0 · vitest 181 pass (6 pre-existing theme-context; регресс group-members detail-теста починен).

## Связанные тикеты

- [[KAC-127]] — Production-Ready IAM (backend baseline; этот UI поверх него)
- [[KAC-124]] — resource-manager → IAM Account/Project (prerequisite)
- [[KAC-125]] — User per-Account + Invite (invite-flow, переиспользуется)
- [[KAC-121]] — YC-style role model (permissions-грамматика)

#kac #feature #kacho-ui #kacho-workspace
