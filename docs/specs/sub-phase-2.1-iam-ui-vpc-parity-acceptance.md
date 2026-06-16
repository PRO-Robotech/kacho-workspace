# Sub-phase 2.1 (IAM UI ↔ VPC parity) — Acceptance

> **Статус:** ✅ APPROVED (round 3; `acceptance-reviewer`, 2026-06-16)
> **Дата:** 2026-06-16
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — APPROVED (round 1/2 → CHANGES REQUESTED, замечания учтены)
> **Эпик/тикет:** KAC-TBD (epic «IAM UI — VPC parity»; per-repo subtask в `kacho-ui`). **Номер тикета проставляется до старта `writing-plans`** (фича → тикет СНАЧАЛА, `git-youtrack.md`); в финальном APPROVED-артефакте `KAC-TBD` не остаётся.
> **Scope:** **`kacho-ui` only.** Backend контракты (proto / RPC / IAM-сервис) **не меняются**. Любое отсутствующее поле/RPC, которого нет в текущем публичном API, — отдельный кросс-репо тикет, **вне этого скоупа** (см. §13 Out-of-scope).
> **Источник дизайна:** `docs/specs/sub-phase-1.x-ui-yc-redesign-plan.md` (APPROVED YC-console look, которому уже следует VPC); конвенции UI — `project/kacho-ui/CLAUDE.md`; образцы формата — `docs/specs/sub-phase-0.3-vpc-acceptance.md`, `sub-phase-2.0-iam-KAC-121/-KAC-125-*-acceptance.md`.

---

## Обзор

Раздел IAM в `kacho-ui` сегодня построен на смеси custom-страниц (`UsersPage`, `GroupsPage`, `RolesPage`, `AccessBindingsPage`, `AccessPage`) и частично — на generic-движке (`ResourceListPage` + legacy `ResourceDetailPage(?tab=)` для Account / ServiceAccount через `IamScopedListShell`). VPC-раздел давно мигрирован на единый registry-driven движок: `ResourceListPage` (список) + `ResourceShell` (детали с path-based табами `Обзор`/`Операции`/`JSON`) + `REGISTRY`-спеки + `DETAIL_EXTENSIONS` + `?modal=<spec.id>-create|edit` через единственный `GlobalResourceFormModal`. Визуальный язык VPC задан YC-redesign-планом (тёмная тема, узкий icon-сайдбар, список с фильтром-по-имени + CTA в правом углу + сортируемые колонки + per-row kebab, деталь с левым sub-nav `Обзор`/`Операции`/`JSON` + блок `Документация`, моноширинный copyable-id).

Цель под-фазы — привести **все 8 IAM-поверхностей** к тому же визуальному языку и к той же page-construction-механике, что у VPC: одинаковая шапка (`PanelHeader`/`ContextBadge`/`CopyableId`/`StatusBadge`), одинаковый список, одинаковая деталь с path-based табами, одинаковый modal-flow Create/Edit. Backend остаётся прежним; меняется только UI-слой. Особые поверхности (Access page как bespoke task-flow; AccessBinding list как bespoke 3-view-mode) сохраняют свою уникальную UX, но принимают общий chrome.

Документ — **только наблюдаемое поведение UI** (что видит/делает пользователь через браузер на стенде). Никакого кода. Сценарии трассируются в имена UI-тестов (component/e2e) и newman-проверок поведения api-gateway через ID `2.1-<LETTER><NN>`.

---

## 0. Фиксированные решения (одобрены заказчиком — НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| D-1 | Полный паритет по **всем 8** IAM-поверхностям: Account, Project, User, ServiceAccount, Group, Role, AccessBinding, Access page. | Раздел IAM визуально и механически должен быть неотличим от VPC. |
| D-2 | **Access page** (`/iam/access`, YC-style Cascader grant-or-invite) остаётся **bespoke**; только косметическое выравнивание chrome (`PanelHeader`/`ContextBadge`/`CopyableId`, modal — единая `FORM_WIDTH`). Логика task-flow (Cascader, invite-fallback, aggregated per-user view) **не меняется**. | Это специализированный task-flow, его UX осознанно отличается. |
| D-3 | **AccessBinding**: registry управляет деталью + колонками + `CopyableId` + `StatusBadge`; **список остаётся bespoke 3-view-mode** (byResource / bySubject / byAccount — у backend нет единого flat-List RPC), но принимает `PanelHeader`-chrome. | Backend RPC-форма (3 list-метода) диктует bespoke list; унифицируется только chrome. |
| D-4 | **IAM Project** получает лёгкую `ResourceShell`-деталь на `/iam/projects/:uid` (`Обзор`/`Операции`/`JSON`); существующий project-overview dashboard (`/projects/:id/...`) остаётся отдельным drill-target. | Деталь IAM-Project ≠ VPC project-context dashboard; нужны обе. |
| D-5 | Все мутации остаются async через `Operation` (polling до `done`), как сегодня и как у VPC. | Конвенция Kachō (ban #9). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `kacho-ui/CLAUDE.md` §3 modal-flow `?modal=<spec.id>-create\|edit` | §A (Account), §B (Project), §C (ServiceAccount), §E (Group), §F (Role), §G (AccessBinding create) |
| `kacho-ui/CLAUDE.md` §3.2 единый `GlobalResourceFormModal` mount в `Layout` | §H1 (cross-cutting): модалка должна работать на `/iam/*` |
| `kacho-ui/CLAUDE.md` §3.3 modal style (единая `FORM_WIDTH = 820` для всех resource-модалок, `maskClosable`, `destroyOnClose`, `title:null`) | все Create/Edit-сценарии IAM-ресурсов |
| `kacho-ui/CLAUDE.md` §3.5 mutation-error НЕ закрывает форму | §A6, §C5, §E6, §F7, §G6 |
| `kacho-ui/CLAUDE.md` §4 horizontal Form, `labelCol 200px`, `colon:false`, required ⭐ справа, info ⓘ-tooltip | все form-сценарии |
| `kacho-ui/CLAUDE.md` §4.4 «никаких скобочных пояснений в labels» | §F (Role permissions), §G (AccessBinding subject/role/resource) |
| `kacho-ui/CLAUDE.md` §5 единый `LabelsEditor` | §A, §B, §C (где labels), §E |
| `kacho-ui/CLAUDE.md` §11 registry-driven `ResourceSpec` | §A–§G (specs) |
| `kacho-ui/CLAUDE.md` §12.3 async-mutations (Operation envelope polling) | все мутации |
| `kacho-ui/CLAUDE.md` §12.4 Edit → `computeUpdateMask` (только изменённые mutable) | §A5, §C4, §E5, §F6 |
| `kacho-ui/CLAUDE.md` §13 «никаких inline-форм вместо Общее-блока; edit через `?modal=…-edit`» | §A4, §B3, §C4, §D2 |
| `sub-phase-1.x-ui-yc-redesign-plan.md` §A.1 палитра (`#1c1d22`/`#26272d`/`#3D8DF5`) | §H4 (cross-cutting chrome) |
| `sub-phase-1.x-ui-yc-redesign-plan.md` детали list/detail page (фильтр-по-имени, CTA-правый-угол, sub-nav `Обзор`/`Операции`/`Документация`) | §A–§G list/detail |
| `00-kacho-core.md` non-negotiable #1 (APPROVED acceptance перед кодом) | этот документ — гейт перед `integration-tester` |
| `security.md` Internal-vs-external | §H5 (cross-cutting): IAM list-views/scoping не светят internal-данные; никаких новых публичных RPC |

---

## 2. Глоссарий поверхностей и текущее состояние

| # | Поверхность | Route(ы) сегодня | Список сегодня | Деталь сегодня | Create/Edit сегодня | Целевой режим |
|---|---|---|---|---|---|---|
| A | **Account** | `/iam/accounts`, `/iam/accounts/:uid` | `ResourceListPage` (generic) | `ResourceDetailPage(?tab=)` (legacy) | `?modal=accounts-…` | pure-registry → `ResourceShell` |
| B | **Project** | `/iam/projects` (scoped, нет detail-route) | `IamScopedListShell`→`ResourceListPage` | **нет** (row → VPC dashboard) | `?modal=projects-…` | pure-registry + новый `ResourceShell` detail `/iam/projects/:uid` |
| C | **ServiceAccount** | `/iam/service-accounts`, `/iam/service-accounts/:uid` | `IamScopedListShell`→`ResourceListPage` | `ResourceDetailPage(?tab=)` (legacy) | `?modal=service-accounts-create` (нет edit) | pure-registry → `ResourceShell` + edit |
| D | **User** | `/iam/users` (нет detail-route) | custom `UsersPage` (flat) | **нет** | нет create/edit; custom invite-modal | read-only mirror: `ResourceListPage` + `ResourceShell` detail; invite — custom header-action |
| E | **Group** | `/iam/groups` (нет detail-route) | custom `GroupsPage` + `expandedRowRender` members | **нет** | custom modal | registry list+detail; членство — extra-tab `Участники` |
| F | **Role** | `/iam/roles` (нет detail-route) | custom `RolesPage` + tabs system/custom | **нет** | custom modal + PermissionsEditor | registry list+detail; system/custom — list-filter; permissions — custom InlineResourceForm-ветка; edit/delete gated `is_system=false` |
| G | **AccessBinding** | `/iam/access-bindings` (нет detail-route) | custom `AccessBindingsPage` 3-view-mode | **нет** | custom modal | registry detail/columns + bespoke 3-view list (D-3) + custom create-ветка + revoke header-action |
| Z | **Access page** | `/iam/access` | custom YC-style (Cascader) | n/a | custom invite-modal | косметика only (D-2) |

**IAM resource-модель (источник истины — `kacho-proto`/vault; для UI — поля и enum):**
- **Account** — id (`acc`-prefix), name, description, labels, `owner_user_id` (immutable после Create), `organization_id` (опц.), created_at. **Нет status-enum.** (Поля `cluster_id` в `account.proto` нет — не используем.)
- **Project** — id (`prj`), `account_id` (immutable), name, description, labels, created_at. Нет status.
- **User** — id (`usr`), `external_id`, email, `display_name`, `account_id`, `invite_status` (enum **PENDING / ACTIVE / BLOCKED**), `invited_by`, created_at.
- **ServiceAccount** — id (`sva`), `account_id`, name, description, `enabled` (bool), labels, created_at. Нет status-enum (`enabled` — bool).
- **Group** — id (`grp`), `account_id`, name, description, labels, created_at; членство — `group_members{member_type ∈ {user, service_account}, member_id, added_at}`.
- **Role** — id (`rol`), name, description, `permissions` (массив строк, **PERM-грамматика** `module.resource.name.verb`, wildcard `*` в любом сегменте), `is_system` (bool), `account_id`/`cluster_id`/`project_id` (scope), created_at. Нет status-enum.
- **AccessBinding** — id (`acb`), `subject_type` (`user`/`service_account`/`group`) + `subject_id`, `role_id`, `resource_type` (`account`/`project`/`cluster`) + `resource_id`, `status` (enum **PENDING / ACTIVE / REVOKED**), `scope` (output `CLUSTER`/`ACCOUNT`/`PROJECT`), `condition_id` / `builtin_condition` / `expires_at` (опц.), created_at.

**Async-мутации (Operation envelope, polling):** Account/Project/ServiceAccount/Group/Role Create+Update+Delete; User Invite+Delete; Group AddMember+RemoveMember; AccessBinding Create+Delete(revoke).
**Sync read:** все Get/List/ListMembers/ListBy*/ListOperations.

---

## 3. Кросс-сквозные требования (общие для всех поверхностей)

### Что переиспользуется из VPC-движка
- `ResourceListPage` (шапка + фильтр + сортировка + kebab + 3s-polling + empty-state).
- `ResourceShell` (3-зонная деталь; path-based табы `Обзор` + related/extra + `Операции` + `JSON`).
- `REGISTRY`-спеки (`id`/`route`/`apiPath`/`payloadKey`/`singular`/`plural`/`genitive`/`serviceTitle`/`columns`/`fields`/`template`/`sanitize`/`hydrate`/`scope`/`ops`/`related`/`childRoute`/`emptyState`/`docs`). Для IAM важны `genitive` (склонение в крошках/заголовках), `serviceTitle` («Identity and Access Management» в eyebrow/крошках), `emptyState`.
- `DETAIL_EXTENSIONS` (overviewExtra / overviewBelow / headerActions / extraTabs / hideOperations / title).
- `GlobalResourceFormModal` → `ResourceFormModal` → `InlineResourceForm` (generic create/edit) + кастом-ветки.
- `PanelHeader` / `ContextBadge` / `CopyableId` / `StatusBadge` / `RefNameLink` (`RefLink`).

### Что добавляется/меняется как cross-cutting (сценарии §H)
- `DETAIL_EXTENSIONS` получает IAM-ключи (сейчас 0 IAM-ключей).
- `StatusBadge` tone-map расширяется значениями IAM-enum-ов.
- `GlobalResourceFormModal` mountится внутри `IamLayout` так, что `?modal=` работает на `/iam/*` (containerId уже резолвится в `"iam"`).
- Хлебные крошки IAM: `Account › Resource › child`.
- Empty-state account-scoping ссылается на выбор Account вверху `/iam` (не на `/iam/projects`).

---

## §A. Account (pure-registry)

**Целевое:** список — `ResourceListPage` (scope `global`); деталь — `ResourceShell` (path-based), миграция с legacy `ResourceDetailPage(?tab=)`. `DETAIL_EXTENSIONS.accounts`: overview refs (`owner_user_id` — `RefLink` на user, `organization_id`), related child-табы (projects / service-accounts / groups). **Нет status-поля → `StatusBadge` не отображается.**

### 2.1-A1 (positive — список)
- **Given** на стенде есть ≥2 Account
- **When** пользователь открывает `/iam/accounts`
- **Then** видна `ResourceListPage`-шапка (`PanelHeader`): иконка ресурса + eyebrow `Список` + plural «Аккаунты» + тег-счётчик; колонки `Имя`, `ID` (моноширинный `CopyableId`), `Владелец` (`owner_user_id`), `Дата создания`, `Метки`; колонка `Имя` первая, `ID` вторая
- **And** в правом углу шапки — input «Фильтр по имени или идентификатору» и primary-CTA «Создать» (синий `#3D8DF5`)
- **And** колонки `Имя`/`ID`/`Дата создания` сортируемые (стрелки ↕); per-row kebab `…` с действиями (минимум `Редактировать`, `Удалить`)
- **And** **отсутствует** колонка/бейдж статуса (у Account нет status)

### 2.1-A2 (positive — 3s polling)
- **Given** список Account открыт
- **When** в фоне создаётся новый Account (через другой клиент)
- **Then** строка появляется в таблице не позднее ~3 c без ручного refresh (`refetchInterval: 3000`, `staleTime: 0`)

### 2.1-A3 (positive — деталь, path-based табы)
- **Given** существует Account `acc-X` с ≥1 project и ≥1 service-account
- **When** клик по строке → переход на `/iam/accounts/acc-X`
- **Then** рендерится `ResourceShell`: левый sub-nav с табами `Обзор` (по умолчанию активен), related-табы `Проекты` / `Сервисные аккаунты` / `Группы`, `Операции`, `JSON`; снизу блок `Документация`
- **And** таб `Обзор` показывает базовые поля (id `CopyableId`, name, description, created_at, labels) + overview-refs: `Владелец` как `RefLink` на user, `organization_id`
- **And** URL таба path-based: `/iam/accounts/acc-X/projects`, `/iam/accounts/acc-X/json`, `/iam/accounts/acc-X/operations` (НЕ `?tab=`)
- **And** хлебные крошки: `Identity and Access Management › Аккаунты › <name>`

### 2.1-A4 (positive — edit entry через modal)
- **Given** открыт `Обзор` Account `acc-X`
- **When** клик «Редактировать» (в `Обзор` или kebab)
- **Then** URL получает `?modal=accounts-edit&id=acc-X`; поверх детали открывается модалка (единая `FORM_WIDTH` = 820, `title:null`, форма рендерит `Редактирование: Аккаунт`); закрытие модалки оставляет nav-state на детали (`/iam/accounts/acc-X`)
- **And** на детали **не** появляется inline-форма вместо `Обзор`-блока

### 2.1-A5 (positive — edit form parity + update_mask)
- **Given** модалка `?modal=accounts-edit&id=acc-X` открыта
- **And** форма horizontal (`labelCol 200px`, `colon:false`); `owner_user_id` — immutable (`ImmutableField` 🔒, либо отсутствует в редактируемых полях); name/description/labels редактируемы (`LabelsEditor`)
- **When** изменено только `description` → submit
- **Then** PATCH несёт `update_mask` только с `description`; возвращается `Operation`; форма polling до `op.done && !op.error` → toast success, инвалидация, модалка закрывается, деталь обновлена

### 2.1-A6 (negative — duplicate name keeps form open)
- **Given** модалка `?modal=accounts-create` открыта (parent containerId `iam`)
- **When** введено `name`, уже занятое другим Account, → submit
- **Then** api-gateway → `Operation` с `error` (`ALREADY_EXISTS`) ИЛИ синхронный 409; UI показывает `toast.error`, **форма НЕ закрывается**, введённые данные сохранены

### 2.1-A7 (negative — invalid name)
- **Given** модалка create
- **When** `name` нарушает regex (например `UPPER_CASE`)
- **Then** клиентская валидация (или backend `INVALID_ARGUMENT`) подсвечивает поле; submit не проходит; форма открыта

### 2.1-A8 (positive — delete async)
- **Given** деталь/строка Account без дочерних ресурсов
- **When** kebab → `Удалить` → подтверждение
- **Then** DELETE → `Operation` polling; при `done && !error` строка исчезает из списка / переход назад на `/iam/accounts`

### 2.1-A9 (negative — delete with children → FAILED_PRECONDITION graceful)
- **Given** Account, у которого есть projects/SA/groups
- **When** `Удалить`
- **Then** `Operation.error` (`FAILED_PRECONDITION`); `toast.error` с сообщением backend; Account остаётся; UI не падает

### 2.1-A10 (edge — empty list)
- **Given** ни одного Account
- **When** открыт `/iam/accounts` без активного фильтра
- **Then** показан welcome/empty-state (`ResourceEmptyState`) с CTA «Создать»; при наличии текста в фильтре empty-state НЕ показывается (вместо него «не найдено»)

### 2.1-A11 (edge — URL-migration `?tab=` → path)
- **Given** старая закладка `/iam/accounts/acc-X?tab=operations`
- **When** переход по ней
- **Then** UI корректно открывает таб `Операции` (редирект/нормализация на path-based `/iam/accounts/acc-X/operations`), без 404 и без пустого экрана

---

## §B. Project (pure-registry + новый ResourceShell detail)

**Целевое:** список — engine-driven через `parentValue` (account-scoped, как сегодня); `account_id` — immutable `RefLink`; **новая** `ResourceShell`-деталь на `/iam/projects/:uid` (`Обзор`/`Операции`/`JSON`) — D-4. Существующий VPC-dashboard `/projects/:id/...` остаётся отдельным drill-target.

### 2.1-B1 (positive — account-scoped список)
- **Given** в шапке `/iam` выбран Account `acc-X` (Select), есть ≥1 project
- **When** открыт `/iam/projects`
- **Then** `ResourceListPage` фильтрует по `account_id=acc-X` (`parentValue`); колонки `Имя`, `ID` (`CopyableId`), `Аккаунт`, `Дата создания`, `Метки`; шапка `PanelHeader` + фильтр + CTA «Создать»

### 2.1-B2 (edge — no account selected)
- **Given** Account в шапке `/iam` НЕ выбран
- **When** открыт `/iam/projects` (в т.ч. deep-link)
- **Then** показан IAM-appropriate empty-state: текст указывает выбрать Account **вверху секции `/iam`** (НЕ ссылка на `/iam/projects`); список не запрашивается до выбора Account

### 2.1-B3 (positive — новая деталь)
- **Given** project `prj-Y` в выбранном Account
- **When** клик по строке → `/iam/projects/prj-Y`
- **Then** рендерится `ResourceShell` с табами `Обзор` / `Операции` / `JSON` + блок `Документация`
- **And** `Обзор`: id (`CopyableId`), name, description, created_at, labels, `Аккаунт` как immutable `RefLink` на `/iam/accounts/acc-X`
- **And** хлебные крошки `… › Проекты › <name>`; edit — через `?modal=projects-edit&id=prj-Y` (не inline)
- **And** **деталь IAM-Project ≠ VPC-dashboard**: с этой страницы есть отдельная ссылка/действие «Открыть в VPC» (drill в `/projects/prj-Y/...`), но `/iam/projects/prj-Y` остаётся IAM-деталью

### 2.1-B4 (positive — create с preset account_id)
- **Given** выбран Account `acc-X`, открыт `?modal=projects-create`
- **Then** `account_id` предзаполнен `acc-X` (preset, hidden/locked); submit → `Operation`; при успехе строка появляется в account-scoped списке

### 2.1-B5 (negative — account_id immutable on edit)
- **Given** открыта модалка `?modal=projects-edit&id=prj-Y`
- **When** пользователь просматривает редактируемые поля
- **Then** `account_id` не редактируется (immutable; Move-RPC отсутствует); попытка изменить отсутствует в UI; mask с `account_id` не отправляется

### 2.1-B6 (positive — delete async)
- **Given** project без блокеров
- **When** `Удалить` → poll → `done && !error`
- **Then** строка исчезает / возврат на `/iam/projects`

---

## §C. ServiceAccount (pure-registry + edit)

**Целевое:** список — engine-driven (account-scoped); деталь — `ResourceShell` (миграция с legacy `ResourceDetailPage(?tab=)`); **добавить Edit**; generic create+edit modal.

> **⚠️ Коррекция (proto-сверка, реализация sub-phase 2.1, 2026-06-17):** `kacho-proto/iam/v1/service_account_service.proto` — `UpdateServiceAccountRequest.update_mask` допускает **только `name`, `description`** (`account_id` immutable); поля **`enabled` нет** ни в `Create`, ни в `Update`, ни отдельного Enable/Disable RPC — `ServiceAccount.enabled` (proto field 7) **output-only**. Также у `ServiceAccount` **нет `labels`**. Поэтому Edit SA = **`name` + `description`** (оба mutable); `enabled` показывается **read-only** (колонка «Активен» + overview-тег), `labels` для SA отсутствует. Это приводит §C к ground-truth backend (контракт backend не меняется, ban #1/scope). Сценарий §C4 ниже читать с этой поправкой (редактируется `description`/`name`, не `enabled`).

### 2.1-C1 (positive — список)
- **Given** выбран Account `acc-X`, есть ≥1 SA
- **When** открыт `/iam/service-accounts`
- **Then** `ResourceListPage` фильтрует по `account_id`; колонки `Имя`, `ID` (`CopyableId`), `Аккаунт`, `Дата создания`; шапка + фильтр + CTA «Создать»
- **And** при наличии колонки/поля `enabled` оно отображается как бейдж/тег (Вкл/Выкл), но это **не** status-enum (`StatusBadge` для SA не применяется)

### 2.1-C2 (positive — деталь path-based)
- **Given** SA `sva-Z`
- **When** `/iam/service-accounts/sva-Z`
- **Then** `ResourceShell` `Обзор` / `Операции` / `JSON`; `Обзор`: id (`CopyableId`), name, description, created_at, `Аккаунт` `RefLink`, `enabled`; URL path-based табы; крошки `… › Сервисные аккаунты › <name>`

### 2.1-C3 (positive — create)
- **Given** выбран Account `acc-X`, открыт `?modal=service-accounts-create`
- **Then** `account_id` preset `acc-X` (hidden); поля name/description; submit → `Operation` → success → строка в списке

### 2.1-C4 (positive — edit добавлен) — *amended by proto-correction above*
- **Given** деталь SA `sva-Z`; клик kebab/Обзор → «Редактировать» открывает URL `?modal=service-accounts-edit&id=sva-Z`
- **And** модалка показывает редактируемые `name`, `description`; `account_id` immutable (hidden/preset). `enabled` — **read-only** (не в форме; виден в overview/списке как тег «Активен»); `labels` у SA нет
- **When** изменён `description` → submit
- **Then** PATCH `update_mask=[description]` (только изменённое mutable-поле); `Operation` polling → success; деталь обновлена

### 2.1-C5 (negative — error keeps form open)
- **Given** edit-модалка SA
- **When** backend вернул `Operation.error`
- **Then** `toast.error`, форма открыта, данные сохранены

---

## §D. User (read-only mirror + custom invite)

**Целевое:** **read-only** (НЕТ create/edit). `ResourceListPage` (global) + `ResourceShell` деталь (`external_id`/`email`/`display_name`/`invite_status`). Invite — custom header-action (как сегодня). `StatusBadge` tone для `invite_status` PENDING/ACTIVE/BLOCKED.

### 2.1-D1 (positive — read-only список)
- **Given** есть ≥1 User
- **When** открыт `/iam/users`
- **Then** `ResourceListPage` chrome; колонки `Эл. почта` (email), `Отображаемое имя`, `Статус` (`StatusBadge` invite_status), `ID` (`CopyableId`), `External ID` (`CopyableId`), `Создан`; per-row kebab содержит **только** `Удалить` (нет `Редактировать`); **нет** CTA «Создать»
- **And** вместо CTA «Создать» в правом углу — custom header-action «Пригласить пользователя»

### 2.1-D2 (positive — StatusBadge tone)
- **Given** в списке есть users со статусами PENDING, ACTIVE, BLOCKED
- **Then** `StatusBadge` рендерит: PENDING → info/warn-тон, ACTIVE → ok-тон (green), BLOCKED → error/muted-тон (расширение tone-map — §H2)

### 2.1-D3 (positive — деталь read-only)
- **Given** user `usr-W`
- **When** `/iam/users/usr-W`
- **Then** `ResourceShell` `Обзор` / `Операции` / `JSON`; `Обзор`: id (`CopyableId`), email, display_name, `external_id` (`CopyableId`), `invite_status` (`StatusBadge`), `account_id` (`RefLink`), created_at; **в `Обзор` НЕТ кнопки «Редактировать»** (read-only); крошки `… › Пользователи › <email>`

### 2.1-D4 (positive — invite custom action)
- **Given** в шапке `/iam` выбран Account `acc-X`, клик «Пригласить пользователя»
- **Then** открывается custom invite-modal (НЕ `?modal=users-…`): поля `Account` (read-only из контекста), `email` (required, email-валидация), `display_name` (опц.), `project_id` (опц. Select), `role_id` (опц. Select grouped system/custom)
- **When** submit с валидным email
- **Then** `POST /iam/v1/users:invite` → `Operation`; на success показывается `magic_link_url` (Alert + copy-button); список обновляется (новая PENDING-строка)

### 2.1-D5 (edge — invite disabled без Account)
- **Given** Account в шапке НЕ выбран
- **Then** кнопка «Пригласить пользователя» disabled (или клик показывает подсказку выбрать Account вверху `/iam`)

### 2.1-D6 (negative — no create surface)
- **Given** `/iam/users`
- **Then** **отсутствует** `?modal=users-create` entry-point; прямой переход на `?modal=users-create` НЕ открывает generic create-форму (User не имеет публичного Create — только Invite)

### 2.1-D7 (positive — delete async)
- **Given** user без owned Account
- **When** kebab → `Удалить` → poll
- **Then** `done && !error` → строка исчезает

### 2.1-D8 (negative — delete user owning account)
- **Given** user — владелец Account
- **When** `Удалить`
- **Then** `Operation.error` (`FAILED_PRECONDITION`); `toast.error`; user остаётся

---

## §E. Group (registry + custom branch)

**Целевое:** список+деталь через engine; членство `Участники` — `ResourceShell` extra-tab (`member_type`/`member_id`/`added_at` + Type/SA-picker + Add/Remove), **заменяет** текущий `expandedRowRender`; generic create/edit modal для name/description/labels.

### 2.1-E1 (positive — список)
- **Given** выбран Account `acc-X`, есть ≥1 Group
- **When** открыт `/iam/groups`
- **Then** `ResourceListPage` chrome (НЕ `expandedRowRender`); колонки `Имя`, `ID` (`CopyableId`), `Описание`, `Создан`, `Метки`; фильтр + CTA «Создать»; per-row kebab (`Редактировать`/`Удалить`)
- **And** строка раскрытие (expand) больше **не** показывает inline members-панель — членство теперь на детали

### 2.1-E2 (positive — деталь + Участники extra-tab)
- **Given** group `grp-G`
- **When** `/iam/groups/grp-G`
- **Then** `ResourceShell` табы `Обзор` / **`Участники`** / `Операции` / `JSON`; `Обзор`: id (`CopyableId`), name, description, created_at, labels, `Аккаунт` `RefLink`
- **And** URL path-based: `/iam/groups/grp-G/members`

### 2.1-E3 (positive — членство таб)
- **Given** таб `Участники` group `grp-G`
- **Then** таблица членов: `Тип` (member_type: user / service_account — тег), `ID` (`CopyableId`), `Добавлен` (added_at); per-row kebab/кнопка `Удалить`
- **And** над таблицей — Type-selector (`User` / `Service Account`) + member-picker (Select: users либо SA по типу) + кнопка «Добавить»

### 2.1-E4 (positive — add/remove member async)
- **Given** таб `Участники`, выбран тип `User` и member `usr-M`
- **When** «Добавить» → poll
- **Then** `AddMember` → `Operation` `done && !error`; член появляется в таблице (5s polling/инвалидация)
- **When** kebab → `Удалить` у члена → poll
- **Then** `RemoveMember` → `Operation` `done`; член исчезает

### 2.1-E5 (positive — create/edit modal)
- **Given** выбран Account, открыта `?modal=groups-create` с preset `account_id` (hidden), поля name/description/labels
- **When** заполнено name → submit
- **Then** `Operation` → success → строка в списке
- **And** edit через `?modal=groups-edit&id=grp-G`: `account_id` immutable; submit отправляет `update_mask` только с изменёнными полями

### 2.1-E6 (negative — error keeps form open)
- **Given** create/edit Group, backend error
- **Then** `toast.error`, форма открыта

### 2.1-E7 (edge — add idempotent)
- **Given** member `usr-M` уже в группе
- **When** повторно «Добавить» того же → poll
- **Then** UI грациозно обрабатывает `ALREADY_EXISTS`/no-op (`Operation` done без дубля строки или `toast` с пояснением); таблица не дублирует члена

---

## §F. Role (registry + custom branch)

**Целевое:** список+деталь через engine; различие system/custom — **list-filter**; custom `InlineResourceForm`-ветка для permissions-editor (PERM-грамматика, по образцу `SgRulesEditor`); edit/delete gated на `is_system=false`.

> **Важно (рассинхрон с текущим UI):** текущий `RolesPage` валидирует permissions устаревшим **3-сегментным** regex (`module.resource.verb`, `PERM_RE = /^[a-z_]+(\.[a-z_*]+){2}$/`). Backend (source of truth — `kacho-iam` `domain.Permissions.Validate` / DB-валидатор `iam_permissions_valid()`, RBAC v2) требует **4-сегментную** грамматику `module.resource.name.verb` (wildcard `*` допустим в любом сегменте). Целевой permissions-editor валидирует **4 сегмента** — это не косметический перенос, а приведение клиентской валидации к актуальному контракту backend (backend при этом не меняется). UI-ассерты §F5/§F7 проверяют 4-сегментную валидацию.

### 2.1-F1 (positive — список + filter system/custom)
- **Given** есть system- и custom-роли
- **When** открыт `/iam/roles`
- **Then** `ResourceListPage` chrome; колонки `Имя`, `Тип` (system/custom — тег), `ID` (`CopyableId`), `Аккаунт`, `Описание`, `Разрешения` (первые N как теги + «+M ещё»), `Создано`; фильтр-по-имени + **доп. фильтр system/custom** (Segmented/Select) + CTA «Создать пользовательскую роль»

### 2.1-F2 (positive — деталь)
- **Given** role `rol-R`
- **When** `/iam/roles/rol-R`
- **Then** `ResourceShell` `Обзор` / `Операции` / `JSON`; `Обзор`: id (`CopyableId`), name, description, `Тип` (system/custom), `permissions` (полный список — теги/моноширинный список), scope (`account_id`/`cluster_id`/`project_id`), created_at; крошки `… › Роли › <name>`

### 2.1-F3 (negative — system role no edit/delete affordance)
- **Given** деталь system-роли (`is_system=true`)
- **Then** в `Обзор` и kebab **отсутствуют** «Редактировать» и «Удалить» (disabled/скрыты); прямой `?modal=roles-edit&id=<system>` либо не открывается, либо открывается read-only без submit

### 2.1-F4 (positive — custom role editable)
- **Given** деталь custom-роли (`is_system=false`)
- **Then** «Редактировать» и «Удалить» доступны

### 2.1-F5 (positive — create custom role + permissions editor)
- **Given** `?modal=roles-create` (custom-ветка `InlineResourceForm`)
- **Then** форма horizontal; поля `account_id` (Select, required), `name` (regex custom-role), `description`, **`permissions`** через custom permissions-editor: строки **4-сегментной** PERM-грамматики `module.resource.name.verb` (wildcard `*` в любом сегменте), inline-валидация формата (подсветка невалидных строк, счётчик), как `SgRulesEditor` по UX-паритету
- **And** валидная строка — например `vpc.networks.*.get`, `iam.projects.prj-abc.update`, `*.*.*.admin`
- **When** все строки валидны (4 сегмента) → submit
- **Then** `Operation` → success → роль в custom-фильтре списка

### 2.1-F6 (positive — edit custom role)
- **Given** `?modal=roles-edit&id=rol-R` (custom)
- **Then** name read-only/immutable по контракту; description + permissions редактируемы; submit → PATCH `update_mask` только изменённые

### 2.1-F7 (negative — invalid permission keeps form open)
- **Given** create/edit, строка permission нарушает 4-сегментную грамматику — например **3-сегментная** `compute.instances.create` (нет 4-го сегмента) или `Compute.Networks.*.Get` (uppercase)
- **Then** клиентская валидация подсвечивает строку как невалидную и блокирует submit; если строка всё же ушла на backend → `Operation.error INVALID_ARGUMENT` (`iam_permissions_valid()`) → `toast.error`, форма открыта, данные сохранены

### 2.1-F8 (edge — dangling/unknown в permissions render)
- **Given** роль с permission-строкой неизвестного модуля
- **Then** деталь рендерит строку как есть (raw монострока), без падения UI (forward-compat)

---

## §G. AccessBinding (registry detail/columns + bespoke 3-view list + custom create + revoke)

**Целевое:** registry управляет деталью/колонками/`CopyableId`/`StatusBadge`; **список остаётся bespoke 3-view-mode** (byResource / bySubject / byAccount — D-3), но принимает `PanelHeader`-chrome; custom create-ветка (polymorphic subject/role/resource picker + condition/expiry + URL-preset из `ClusterAdminsPage`); revoke — header-action (НЕ generic delete). `StatusBadge` PENDING/ACTIVE/REVOKED.

### 2.1-G1 (positive — 3-view list с PanelHeader chrome)
- **Given** `/iam/access-bindings`
- **Then** шапка — `PanelHeader` (eyebrow + plural «Access Bindings» + CTA «Создать»); под ней — view-mode Segmented (`По ресурсу` / `По subject'у` / `По account'у (admin)`); список остаётся bespoke (3 list-RPC), но визуально chrome совпадает с VPC
- **And** колонки управляются registry-spec: `Субъект` (subject_type+subject_id, `CopyableId`), `Роль` (`role_id`→name, `RefLink`/lookup), `Ресурс` (resource_type+resource_id, `CopyableId`), `Статус` (`StatusBadge`), `Создано`; per-row action `Отозвать` (revoke)

### 2.1-G2 (positive — StatusBadge PENDING/ACTIVE/REVOKED)
- **Given** в списке есть binding'и со статусами
- **Then** `StatusBadge`: ACTIVE → ok, PENDING → info/warn, REVOKED → muted/error (§H2)

### 2.1-G3 (positive — byResource view)
- **Given** view `По ресурсу`, выбран resource_type `account` + resource_id `acc-X`
- **Then** список = `:listByResource`; строки фильтруются по ресурсу

### 2.1-G4 (positive — bySubject / byAccount views)
- **Given** view `По subject'у` (subject_type+id) → `:listBySubject`; view `По account'у` (admin: account + опц. subject-filter + include-revoked toggle) → ListByAccount
- **Then** соответствующие списки рендерятся с тем же chrome

### 2.1-G5 (positive — деталь через registry)
- **Given** binding `acb-B`
- **When** переход на деталь (`/iam/access-bindings/acb-B`)
- **Then** `ResourceShell` `Обзор` / `Операции` / `JSON`; `Обзор`: id (`CopyableId`), subject (type+`RefLink`), role (`RefLink`), resource (type+`CopyableId`), `Статус` (`StatusBadge`), scope, `condition_id`/`builtin_condition`/`expires_at` (если есть), created_at

### 2.1-G6 (positive — custom create polymorphic)
- **Given** `?modal=access-bindings-create` (custom-ветка)
- **Then** форма horizontal с polymorphic-пикерами: `subject_type` Select (user/service_account/group) → `subject_id` picker зависит от типа; `role_id` Select (grouped system/custom); `resource_type` Select (account/project/cluster) → `resource_id` picker/locked; опц. `condition_id`/`builtin_condition` + `expires_at`
- **When** submit валидной комбинации → poll
- **Then** `Operation` `done && !error` → binding появляется в списке; **error НЕ закрывает форму** (типичный `ALREADY_EXISTS` для дубля — `toast warning`, форма открыта)

### 2.1-G7 (positive — URL-preset из ClusterAdminsPage)
- **Given** deep-link `?modal=access-bindings-create&resource_type=cluster&role_id=<admin>&...` (preset из cluster-admin сценария)
- **Then** форма открывается с предзаполненными resource_type=cluster, role_id и т.п.; пользователь дозаполняет subject

### 2.1-G8 (positive — revoke header-action, не generic delete)
- **Given** ACTIVE binding в списке/детали
- **When** действие `Отозвать` → подтверждение → poll
- **Then** вызывается revoke-path (DELETE/revoke) → `Operation` `done`; статус строки → REVOKED (`StatusBadge` muted) или строка скрывается (если include-revoked off); **это revoke, не «удалить ресурс»** (формулировка действия — `Отозвать`)

### 2.1-G9 (edge — dangling role_id graceful render)
- **Given** binding ссылается на удалённый/неизвестный `role_id`
- **When** рендер списка/детали
- **Then** UI показывает fallback (raw id моноширинно / «роль недоступна»), без падения; остальные колонки рендерятся (cross-domain dangling-ref грациозно — `data-integrity.md` §4)

### 2.1-G10 (edge — empty per-view)
- **Given** view byResource без результатов для выбранного ресурса
- **Then** показан empty-state «нет привязок»; chrome (шапка + фильтры) остаётся

---

## §Z. Access page (косметика only — D-2)

**Целевое:** только chrome-выравнивание (`PanelHeader`/`ContextBadge`/`CopyableId`, modal — единая `FORM_WIDTH`). Логика Cascader / invite-fallback / aggregated per-user view **не меняется**.

### 2.1-Z1 (positive — chrome aligned)
- **Given** `/iam/access`
- **Then** шапка использует `PanelHeader`/`ContextBadge` (визуально как VPC); id-колонка пользователя — `CopyableId` (моноширинный); scope-табы `Облако`/`Каталог` сохранены

### 2.1-Z2 (positive — modal width = общий FORM_WIDTH)
- **Given** клик «Настроить доступ» / «Выдача доступа»
- **Then** invite-modal открывается с шириной, равной общему `FORM_WIDTH` (= `820`, та же, что у всех resource-модалок IAM/VPC — не отдельное значение)

### 2.1-Z3 (regression — task-flow unchanged)
- **Given** invite-modal Access page
- **Then** Cascader выбора ролей (3-уровневая module→resource→verb), invite-fallback по email, aggregated per-user view в таблице — работают **идентично** текущему поведению (никаких регрессий логики)

### 2.1-Z4 (edge — no resource selected)
- **Given** не выбран Account/Project для scope
- **Then** показан info-alert «выберите Account/Project» (текущее поведение сохранено)

---

## §H. Кросс-сквозные сценарии (shared machinery)

### 2.1-H1 (positive — GlobalResourceFormModal на /iam/*)
- **Given** любая `/iam/*` страница под `IamLayout`
- **When** в URL добавляется `?modal=<spec.id>-create|edit` (например `accounts-create`, `service-accounts-edit&id=…`)
- **Then** `GlobalResourceFormModal` (mount в `Layout`/`IamLayout`) резолвит containerId `"iam"` и открывает `ResourceFormModal`; модалка работает на IAM-маршрутах так же, как на VPC
- **And** дублирующего `<ResourceFormModal/>` per-page нет (единственный mount-point)

### 2.1-H2 (positive — StatusBadge tone-map расширен IAM-enum)
- **Given** `StatusBadge` рендерит IAM-статусы
- **Then** tone-map включает: User `invite_status` PENDING / ACTIVE / BLOCKED; AccessBinding `status` PENDING / ACTIVE / REVOKED; маппинг тонов согласован (ACTIVE→ok, PENDING→info/warn, BLOCKED/REVOKED→error/muted); неизвестное значение → нейтральный тон (forward-compat, без падения)

### 2.1-H3 (positive — DETAIL_EXTENSIONS получает IAM-ключи)
- **Given** деталь IAM-ресурса
- **Then** `DETAIL_EXTENSIONS` содержит ключи `accounts` (overview-refs + related projects/service-accounts/groups), `groups` (extra-tab `Участники`), и т.д.; сейчас IAM-ключей 0 — после миграции присутствуют

### 2.1-H4 (positive — палитра/визуальный язык)
- **Given** любой IAM-экран
- **Then** тёмная тема (`#1c1d22` фон / `#26272d` контейнер / `#3D8DF5` primary), узкий icon-сайдбар, list-layout (фильтр-по-имени + CTA-правый-угол + сортируемые колонки + per-row kebab), detail-layout (левый sub-nav `Обзор`/`Операции`/`JSON` + блок `Документация`, моноширинный copyable-id) — идентичны VPC

### 2.1-H5 (positive — breadcrumb chain IAM)
- **Given** деталь дочернего ресурса (например group в account-контексте)
- **Then** хлебные крошки выстраиваются `Account › Resource › child` (например `… › Аккаунты › <acc> › Группы › <grp>` где применимо), консистентно с VPC `Service › Resource › name`

### 2.1-H6 (positive — account-scoping empty-state copy)
- **Given** account-scoped поверхность (Project / ServiceAccount / Group) без выбранного Account
- **Then** empty-state указывает выбрать Account **вверху секции `/iam`** (НЕ ведёт на `/iam/projects`)

### 2.1-H7 (negative — no new public RPC / no internal leak)
- **Given** весь IAM-UI после миграции
- **Then** UI вызывает **только** существующие публичные REST-пути IAM (`/iam/v1/...`); не появляется ни одного нового RPC и ни одного internal-only поля на публичной поверхности (§Out-of-scope, `security.md`)

### 2.1-H8 (edge — deep-link `/iam/groups` без Account)
- **Given** прямой переход (закладка) на `/iam/groups` без выбранного Account
- **Then** IAM-appropriate empty-state (выбрать Account вверху), без падения, без запроса list

### 2.1-H9 (edge — URL-migration `?tab=` → path-based для всех IAM detail)
- **Given** старые закладки вида `/iam/accounts/:uid?tab=json`, `/iam/service-accounts/:uid?tab=operations`
- **Then** нормализуются на path-based (`/json`, `/operations`); корректный таб, без 404

---

## §I. Сводные негативные / edge инварианты (черезповерхностно)

### 2.1-I1 (negative — backend Unavailable во время мутации)
- **Given** любая Create/Edit/Delete-модалка IAM
- **When** api-gateway/IAM недоступен (`UNAVAILABLE`)
- **Then** `toast.error`; форма открыта; данные сохранены (fail-closed для мутаций; UI не теряет ввод)

### 2.1-I2 (negative — malformed id в URL детали)
- **Given** переход на `/iam/accounts/not-a-valid-id`
- **Then** backend `INVALID_ARGUMENT`/`NOT_FOUND` → UI рендерит `ErrorResult`-экран (не белый экран), с действием «назад к списку»

### 2.1-I3 (edge — async Operation, который не завершился)
- **Given** мутация вернула `Operation`, который долго `done=false`
- **Then** форма/кнопка в pending-состоянии (Doppler/спиннер), polling продолжается; пользователь видит, что операция в процессе; форма не закрывается раньше `done`

### 2.1-I4 (edge — список во время фоновой мутации)
- **Given** открыт IAM-список, в фоне идёт async-create другого клиента
- **Then** 3s-polling подхватывает изменение; список консистентен (без дублей/пропусков после `Operation.done`)

---

## §J. e2e smoke (через api-gateway, newman-проверяемое поведение контракта)

> UI-поведение проверяется component/e2e-тестами фронта; нижеследующее — smoke на то, что REST-контракт, на который опирается UI, отвечает ожидаемо (newman, без изменения backend).

### 2.1-J1 (smoke — IAM read-paths)
- **Given** стенд с seed IAM-данными
- **When** `GET /iam/v1/accounts`, `/iam/v1/projects?accountId=…`, `/iam/v1/users?accountId=…`, `/iam/v1/serviceAccounts?accountId=…`, `/iam/v1/groups?accountId=…`, `/iam/v1/roles`, `/iam/v1/accessBindings:listByResource?...`
- **Then** каждый — `200 OK`, JSON camelCase (`accountId`, `createdAt`, `inviteStatus`, `isSystem`), форма как ожидает UI

### 2.1-J2 (smoke — async-create Operation envelope)
- **Given** `POST /iam/v1/accounts {...}` / `/iam/v1/groups {...}`
- **Then** ответ — `Operation` (`id`, `done`); polling `GET /operations/{id}` → `done:true`, `response`; UI-flow паритетен VPC

### 2.1-J3 (smoke — Group member verbs)
- **Given** `POST /iam/v1/groups/{group_id}:addMember {memberType,memberId}` → poll; `GET /iam/v1/groups/{group_id}:listMembers` (path-param по proto-аннотации — `group_id`)
- **Then** addMember → `Operation` done; listMembers содержит члена; `:removeMember` → poll → член отсутствует

### 2.1-J4 (smoke — User invite)
- **Given** `POST /iam/v1/users:invite {accountId,email}` → poll
- **Then** `Operation` done; metadata содержит `magicLinkUrl`; `GET /iam/v1/users?accountId=…` показывает PENDING-строку

### 2.1-J5 (smoke — AccessBinding create+revoke)
- **Given** `POST /iam/v1/accessBindings {...}` → poll; затем revoke
- **Then** create → `Operation` done, binding `status:ACTIVE`; revoke → `Operation` done, binding `status:REVOKED` (или скрыт без include-revoked)

---

## 4. Матрица трассируемости (сценарий → поверхность → файл/компонент)

| Сценарии | Поверхность | Затрагиваемые файлы / компоненты | Registry / ext-ключ | Route(ы) |
|---|---|---|---|---|
| 2.1-A1..A11 | Account | `ResourceListPage`, `ResourceShell`, `resource-detail-extensions.tsx`, `resource-registry.tsx`, `ResourceFormModal`, `InlineResourceForm` | spec `accounts`; `DETAIL_EXTENSIONS.accounts` | `/iam/accounts`, `/iam/accounts/:uid[/json|/operations|/projects|/service-accounts|/groups]` |
| 2.1-B1..B6 | Project | `ResourceListPage`, `IamScopedListShell`, `ResourceShell`, `resource-registry.tsx` (новый detail-route) | spec `projects`; `DETAIL_EXTENSIONS.projects` | `/iam/projects`, **новый** `/iam/projects/:uid` |
| 2.1-C1..C5 | ServiceAccount | `ResourceListPage`, `IamScopedListShell`, `ResourceShell`, `InlineResourceForm` (generic edit) | spec `service-accounts` | `/iam/service-accounts`, `/iam/service-accounts/:uid` |
| 2.1-D1..D8 | User | `ResourceListPage`, `ResourceShell`, `UsersPage`→engine, custom invite-modal, `StatusBadge` | spec `users` (read-only ops); `DETAIL_EXTENSIONS.users` | `/iam/users`, **новый** `/iam/users/:uid` |
| 2.1-E1..E7 | Group | `ResourceListPage`, `ResourceShell`, `resource-detail-extensions.tsx` (extra-tab `Участники`), `InlineResourceForm`, `GroupsPage`→engine | spec `groups`; `DETAIL_EXTENSIONS.groups` (extraTabs) | `/iam/groups`, **новый** `/iam/groups/:uid[/members]` |
| 2.1-F1..F8 | Role | `ResourceListPage` (+system/custom filter), `ResourceShell`, `InlineResourceForm` (custom permissions-ветка), `RolesPage`→engine | spec `roles`; `DETAIL_EXTENSIONS.roles`; custom `InlineRolePermissions*` | `/iam/roles`, **новый** `/iam/roles/:uid` |
| 2.1-G1..G10 | AccessBinding | `AccessBindingsPage` (bespoke 3-view + `PanelHeader`), `ResourceShell` (detail), `resource-registry.tsx` (columns/spec), custom create-ветка, `StatusBadge`, revoke-action | spec `access-bindings` (detail/columns); `DETAIL_EXTENSIONS.access-bindings`; custom `InlineAccessBindingCreateForm` | `/iam/access-bindings`, **новый** `/iam/access-bindings/:uid` |
| 2.1-Z1..Z4 | Access page | `AccessPage` (chrome only: `PanelHeader`/`ContextBadge`/`CopyableId`, modal 820) | n/a (bespoke) | `/iam/access` |
| 2.1-H1 | cross — modal | `GlobalResourceFormModal`, `ResourceFormModal`, `IamLayout`, `Layout` | — | `/iam/*` |
| 2.1-H2 | cross — status | `StatusBadge` (TONE_BY_STATUS расширение) | — | все IAM |
| 2.1-H3 | cross — ext | `resource-detail-extensions.tsx` (IAM-ключи) | `DETAIL_EXTENSIONS.*` IAM | все IAM detail |
| 2.1-H4 | cross — palette | `index.css`, `App.tsx ConfigProvider`, `service-modules.tsx`, `ResourceIcon` | — | все IAM |
| 2.1-H5 | cross — breadcrumb | `ContextBreadcrumb`, `ResourceShell` | — | IAM detail |
| 2.1-H6/H8 | cross — empty-state | `IamScopedListShell`, `ResourceEmptyState`, `ProjectRequiredEmpty`-analog | — | account-scoped IAM |
| 2.1-H7 | cross — API surface | `src/api/iam.ts` (только существующие пути) | — | все IAM |
| 2.1-H9 | cross — URL-migration | `ResourceShell` (path-based tabs), router | — | IAM detail |
| 2.1-I1..I4 | cross — neg/edge | `InlineResourceForm`, `useOperation`, `ErrorResult`, `useResourceList` | — | все IAM |
| 2.1-J1..J5 | e2e smoke | newman cases (api-gateway REST) | — | `/iam/v1/*` |

---

## 5. Out-of-scope / Non-goals

- **Никаких backend/proto-изменений.** Ни новых IAM-RPC, ни новых полей, ни новых enum-значений. Если поверхность требует поля/метода, которого нет в текущем публичном API (например status-enum для Account/ServiceAccount, или единый flat-`ListAccessBindings`), — это **отдельный кросс-репо тикет** (proto → iam → api-gateway), вне этой под-фазы. UI работает с тем, что есть.
- **Access page Cascader-логика не меняется** (D-2): только chrome. 3-уровневый module→resource→verb Cascader, invite-fallback, aggregated per-user view — как есть.
- **AccessBinding 3-view-mode list остаётся bespoke** (D-3) — не переводим на единый `ResourceListPage` (у backend нет flat-List RPC). Меняем только chrome + columns/detail через registry.
- **Никаких изменений auth-flow / scoping-семантики backend** — account-selector в `/iam` остаётся UI-контекстом; реальный AuthN/AuthZ — отдельные фазы.
- **Никаких новых internal-данных на публичной поверхности** (`security.md`).
- **VPC/Compute-разделы не трогаются** — они уже на движке; задача только привести IAM к ним.
- **Не меняем визуальную тему/палитру** — она уже задана YC-redesign (`#1c1d22`/`#26272d`/`#3D8DF5`); IAM лишь начинает её использовать единообразно.

---

## 6. Definition of Done

Под-фаза 2.1 считается выполненной, когда (порядок — по migration-плану `1.x → IAM parity`):

1. **Registry specs** — `resource-registry.tsx` содержит/уточняет IAM-спеки `accounts`, `projects`, `users` (read-only ops), `service-accounts` (+edit), `groups`, `roles`, `access-bindings` (detail/columns): `id`/`route`/`apiPath`/`payloadKey`/`singular`/`plural`/`genitive`/`serviceTitle`/`columns`/`fields`/`template`/`sanitize`/`hydrate`/`scope`/`ops`/`related`/`childRoute`/`emptyState`/`docs`.
2. **StatusBadge / cells** — `TONE_BY_STATUS` расширен IAM-enum (invite_status PENDING/ACTIVE/BLOCKED; accessbinding PENDING/ACTIVE/REVOKED); unknown → нейтральный тон; spec-columns рендерят IAM-колонки (`CopyableId`, `StatusBadge`, `RefLink`).
3. **List pages** — все IAM-списки на VPC-chrome (`ResourceListPage` для A/B/C/D/E/F; `PanelHeader`-chrome для bespoke G/Z): фильтр-по-имени, CTA-правый-угол, сортируемые колонки, per-row kebab, 3s-polling, account-scoping + IAM empty-state; Role — доп. system/custom фильтр; AccessBinding — 3-view-mode сохранён.
4. **Detail + DETAIL_EXTENSIONS** — все IAM-детали на `ResourceShell` (path-based табы `Обзор`/`Операции`/`JSON` + блок `Документация`); `DETAIL_EXTENSIONS` получил IAM-ключи (accounts refs+related; groups `Участники`-tab; roles permissions render; access-bindings refs); legacy `ResourceDetailPage(?tab=)` для Account/SA удалён; `?tab=`→path-based миграция работает; новые detail-routes Project/User/Group/Role/AccessBinding добавлены.
5. **Forms** — `?modal=<spec.id>-create|edit` работает на `/iam/*` через единый `GlobalResourceFormModal`; ServiceAccount edit добавлен; Group/Role create/edit на движке (Role — custom permissions-ветка по образцу `SgRulesEditor`); AccessBinding custom create-ветка (polymorphic + URL-preset) + revoke header-action; User — без create/edit, invite custom header-action; horizontal-form/`labelCol 200px`/required ⭐/info ⓘ/`LabelsEditor`/error-keeps-form-open соблюдены; все мутации async-Operation polling.
6. **Nav / breadcrumbs** — хлебные крошки `Account › Resource › child`; account-scoping empty-state ведёт к выбору Account вверху `/iam`; иконки IAM-ресурсов синхронизированы (`service-modules.tsx` ↔ `ResourceIcon`).
7. **Tests RED→GREEN** — UI component/e2e-тесты по сценариям §A–§I (RED до миграции, GREEN после); newman smoke §J (≥1 happy + ≥1 negative на ключевые контракты, паритет с VPC) — RED до, GREEN после; финальная верификация `npx tsc --noEmit` + сборка + newman зелёные. Никаких backend-правок (ban #13: test-only-к-UI не трогает прод-контракт backend).
8. **Trail** — vault обновлён (новая запись `resources/`/`rpc/` не нужна — backend не менялся; обновить только UI-trail/`KAC/KAC-<N>.md` с «Затронутые сущности vault» + PR-URL); тикет переведён Test→Done с артефактами.

**Гейт:** этот документ должен получить `✅ APPROVED` от `acceptance-reviewer` до старта `superpowers:writing-plans` → `integration-tester` (RED-тесты) → реализации (`kacho-ui`).
