# KAC-121: YC-style role-model iteration 2 — SA→Project, Role-catalog seed, AccessBinding-as-source

> Status: DRAFT v1 — 2026-05-18 (sync с user).
> Parent: [[KAC-104]]. Predecessor: [[KAC-119]] (interim Keto Check + by-domain bootstrap).

## 0. Цель

Перевести IAM-модель на verbatim-YC иерархию + сделать AccessBinding единственным source-of-truth grants'ов (с outbox → Keto).

## 1. YC-style mapping

| YC | Kachō (current) | Scope | FK |
|---|---|---|---|
| Organization | (merged in Account) | — | — |
| Cloud | **Account** | cluster | `OwnerUserID` |
| Folder | **Project** | Account-scope | `AccountID` |
| User | **User** | cluster | mirror Kratos identity |
| ServiceAccount | **ServiceAccount** | **Project-scope** (was Account) | `ProjectID` |
| Group | **Group** | **Account-scope** (already so) | `AccountID` |
| Role | **Role** | cluster catalog (system) + per-Account custom | `AccountID?` (NULL = system) |
| AccessBinding | **AccessBinding** | resource-scope target | `resource_id+resource_type` (any) |

### 1.1 Изменения от текущей модели (KAC-105/KAC-112)

**Break**: `ServiceAccount.account_id → ServiceAccount.project_id` (greenfield reset DB).
- Migration: drop существующих SA + recreate.
- proto: `account_id` → `project_id`.
- handler: scope-list по projectId.

**Stay**: Group остаётся `account_id`. Role.account_id остаётся (NULL = system).

**AccessBinding** (текущий resource-scope) — сохраняется, но **расширяется как source-of-truth**:
- Текущая schema: `subject_type/subject_id` + `role_id` + `resource_type/resource_id`. Это уже OK.
- Источник истины: row в DB. Keto tuple = реплика через outbox-worker (`fga_outbox_drainer` уже существует — переименовать в `authz_outbox_drainer`).

## 2. Role catalog seed (миграция 0002)

3 wildcard + 39 narrow = 42 system-role. Все `is_system=true`, `account_id=NULL`.

```
-- 3 global wildcards
admin       — `kacho_system:root#admin`        (полный доступ ко всему)
editor      — то же что admin минус delete-account-level
viewer      — read-only по всем resources

-- IAM module (7 resources × 3 verbs = 21)
iam.account.{admin,editor,viewer}
iam.project.{admin,editor,viewer}
iam.user.{admin,editor,viewer}
iam.service-account.{admin,editor,viewer}
iam.group.{admin,editor,viewer}
iam.role.{admin,editor,viewer}
iam.access-binding.{admin,editor,viewer}

-- VPC module (8 resources × 3 verbs = 24, но 6 действующих ≈ 18)
vpc.network.{admin,editor,viewer}
vpc.subnet.{admin,editor,viewer}
vpc.address.{admin,editor,viewer}
vpc.security-group.{admin,editor,viewer}
vpc.route-table.{admin,editor,viewer}
vpc.gateway.{admin,editor,viewer}

-- Compute module (4 resources × 3 verbs = 12)
compute.instance.{admin,editor,viewer}
compute.disk.{admin,editor,viewer}
compute.image.{admin,editor,viewer}
compute.snapshot.{admin,editor,viewer}
```

Итого: 3 + 21 + 18 + 12 = **54 system-role**. Id формат: `rol00000000000000<5-char-tail>` (детерминированный, как KAC-105).

Каждая role хранит `permissions: jsonb[]` — список `<module>.<resource>.<verb>` строк.

`admin`: `["*"]` (wildcard).
`viewer`: `["*.*.read", "*.*.list", "*.*.get"]`.
`editor`: `["*.*.*"]` без `*.*.delete-account`.
`iam.account.admin`: `["iam.account.*"]`.
`vpc.network.editor`: `["vpc.network.create", "vpc.network.update"]`.
etc.

## 3. Self-grant flow (на signup)

При `UpsertFromIdentity` (новый user) после auto-create Account + Project:

1. INSERT `User` row.
2. INSERT `Account` row (`owner_user_id = user.id`).
3. INSERT `Project default` row (`account_id = account.id`).
4. INSERT `AccessBinding` row: `{subject: user:<id>, role: admin, resource: account:<id>}`.
5. **Outbox event** в той же DB-TX → `authz_outbox` table.
6. Drainer worker → Keto `WriteTuple(kacho_system:root#admin@user:<id>)` — bootstrap admin при `@prorobotech.ru`; иначе `account:<id>#admin@user:<id>` (mapping role → tuple).

Через ≤200ms (drainer tick) tuple появляется в Keto → пользователь видит свой Account + AccessBinding row в UI.

## 4. UserService.List default-deny

- Anonymous → empty.
- type=user → видит только себя (`WHERE id = principal.id`) — User mirror — это identity-data.
- type=system → видит всё (admin tooling).
- type=user с admin role (system-wide `kacho_system:root#admin`) → видит всё.

## 5. Roles listing — public

`/iam/v1/roles` — **public read для всех** (нужны для UI dropdown'а при создании AccessBinding). Включая anonymous.

`/iam/v1/roles?accountId=<acc>` — фильтр system + custom этого Account.

Без accountId — только system-role (cluster-wide catalog).

## 6. UI changes

### 6.1 AccountCrumb fix

Текущая проблема: при клике на Account в crumb selection не работает.
- `contextApi.setAccount({id, name})` — выставляется.
- `navigate('/accounts/<id>/projects')` — route не существует → `<Layout>` fallback → SPA index → /dashboard.

Fix: route `/accounts/:accountId/projects` → ResourceListPage с filter `accountId`. Либо просто переход на `/iam/projects?accountId=<id>` (существующий).

### 6.2 AccessBinding visibility

UI `/iam/access-bindings` — фильтр через `?subjectId=<my-user-id>` показывает **МОИ грants**. User видит row:
```
{
  id: acb-xxx,
  subject: user:<my-id>,
  role: admin,
  resource: account:<my-account-id>,
  createdAt: ...
}
```
— это «доказательство прав» которое user попросил.

### 6.3 IAM dashboard sub-resources

ServiceAccount/Group/Role/AccessBinding tabs в IAM blocking — show counts (3 stats), drill-down на list page.

## 7. Acceptance scenarios

### A1 — Greenfield: SA/Role/AB tables exist, scope migrated
- **Given** свежий DB.
- **Then** `service_accounts.project_id NOT NULL FK projects(id)`, `roles.account_id NULLABLE` (NULL = system), `access_bindings.resource_*` flexible.

### A2 — Role catalog seed (54 records)
- **Given** свежий DB после migration 0002.
- **When** `GET /iam/v1/roles` без auth.
- **Then** 200, ≥54 system roles, включая `admin`, `viewer`, `editor`, `iam.account.admin`, `vpc.network.editor`, ...

### A3 — Self-grant via AccessBinding
- **Given** user@example.com регистрируется.
- **When** UpsertFromIdentity → INSERT User + Account + Project + AccessBinding (single TX) + outbox row.
- **Then** через ≤2s в Keto есть tuple `account:<acc>#admin@user:<usr>`.
- **And** `GET /iam/v1/access-bindings?subjectId=<usr>` → 1 row {role: admin, resource: account:<acc>}.

### A4 — Bootstrap admin via @prorobotech.ru
- **Given** admin@prorobotech.ru регистрируется.
- **When** UpsertFromIdentity видит email matches `@prorobotech.ru`.
- **Then** дополнительно INSERT AccessBinding {subject:user:<admin>, role:admin, resource:kacho_system:root}.
- **And** через ≤2s Keto tuple записан → admin видит все Accounts.

### A5 — UserService.List default-deny
- **Given** userA, userB зарегистрированы.
- **When** userA → `GET /iam/v1/users`.
- **Then** 200 (1 row — userA only).
- **And** userB не виден.
- **And** admin → 200 (все users).

### A6 — AccountCrumb selection works
- **Given** user залогинен, имеет Account + Project.
- **When** клик на AccountCrumb dropdown → select Account.
- **Then** URL меняется на `/iam/projects?accountId=<id>` либо `/accounts/<id>/projects` ИЛИ context.account.id обновляется без navigation.
- **And** Playwright тест: state.account.id matches selected.

## 8. Этапы реализации

1. **Migration 0002**: drop+recreate SA + new role-catalog seed (54 rows) + AccessBinding self-grant for bootstrap.
2. **proto**: rename SA fields account_id→project_id.
3. **iam handlers**: SA-Project scope; User.List default-deny; AccessBinding outbox source-of-truth.
4. **Outbox worker**: rename + ensure AccessBinding insert → Keto tuple replication.
5. **UI**:
   - AccountCrumb fix.
   - IAM AccessBindings filter `subjectId=<me>`.
   - Sub-resource tabs in module-block.

## 9. Acceptance gate

- Playwright role-model.spec.ts расширен:
  - A2-A6 scenarios всё green.
- Manual: user видит «admin@<his-account>» в /iam/access-bindings.

Closes [[KAC-104]] DoD#3 (CRUD scope clarity) + DoD#4 (real principal — уже passed).

#kac #iam #role-model #yc-parity #refactor
