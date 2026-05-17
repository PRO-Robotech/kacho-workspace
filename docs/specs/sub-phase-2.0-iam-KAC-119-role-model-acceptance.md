# KAC-119: Role-model evolution — default-deny + Keto Check + bootstrap admin

> Status: DRAFT v1 — sync с user 2026-05-18.
> Parent: [[KAC-104]] (IAM epic). Predecessor: [[KAC-118]] (interim by-owner filter — отменяется).

## 0. Цель

Заменить anti-pattern «by-owner filter в коде» (KAC-118) на полноценный REBAC через Keto. Default-deny: новый user без явной роли получает **403 на все RPC** (включая `/iam/v1/accounts`). Роли описываются в spec'е (не в коде) и связываются с principal через `AccessBindings` → Keto tuples.

## 1. Identity model

- **Bootstrap admin**: env `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL=admin@prorobotech.ru`. При первой регистрации user'а с этим email — `UpsertFromIdentityUseCase` пишет в Keto:
  - `kacho_system:root#admin@user:<usr_id>` (system-wide admin).
- **Regular user**: при первой регистрации (любой другой email):
  - Auto-create personal Account + default Project (как было в KAC-117).
  - Self-grant: write Keto tuple `account:<acc_id>#admin@user:<usr_id>`.
  - **НЕ** получает access к чужим Accounts, не может видеть/создавать вне своего Account.

## 2. Keto namespaces (для Read API)

```
kacho_system   # root marker для system-wide admin
account
project
vpc_network
vpc_subnet
vpc_address
vpc_security_group
vpc_route_table
vpc_gateway
compute_instance
compute_disk
compute_image
compute_snapshot
```

Relations: `owner`, `admin`, `editor`, `viewer`.

**Cascade** (через computed relations в Keto namespace-config):
- `vpc_network:N#admin@(project:P#admin)` — admin на Project → admin на все Network внутри.
- `vpc_subnet:S#admin@(vpc_network:N#admin)` — cascade аналогично.
- `kacho_system:root#admin` — wildcard, видит всё.

## 3. RPC → Keto Check mapping (per-RPC enforcement)

**Default-deny принцип**: kacho-iam Check-interceptor выполняет Keto Read API на каждый public RPC. Без matching tuple — 403.

| RPC | namespace | object | relation |
|---|---|---|---|
| `iam.AccountService.Get(id)` | `account` | `<id>` | `viewer` |
| `iam.AccountService.List` | `kacho_system` или `account:*` | — | `admin` либо `lookup` via list_subjects |
| `iam.AccountService.Create` | `kacho_system` | `root` | `admin` (только system-admin) |
| `iam.AccountService.Update/Delete` | `account` | `<id>` | `admin` |
| `iam.ProjectService.Get(id)` | `project` | `<id>` | `viewer` |
| `iam.ProjectService.List(?accountId)` | `account` (если accountId задан) | `<acc>` | `viewer` (видит все project в acc) |
| `iam.ProjectService.Create(accountId)` | `account` | `<acc>` | `editor` |
| `iam.ProjectService.Update/Delete` | `project` | `<id>` | `admin` |
| `iam.RoleService.List` | `kacho_system` или public if `is_system` | — | viewer/public |
| `iam.AccessBindingService.Create` | `account` или `project` (target scope) | `<id>` | `admin` |
| `vpc.NetworkService.Create(projectId)` | `project` | `<id>` | `editor` |
| `vpc.NetworkService.List(projectId)` | `project` | `<id>` | `viewer` |
| `vpc.NetworkService.{Get,Update,Delete}(id)` | `vpc_network` | `<id>` | viewer/editor/admin |
| `compute.InstanceService.Create(projectId)` | `project` | `<id>` | `editor` |
| ... (compute mirror) | | | |

System-principal (Type=system) и InternalService RPC bypass'ят Check (это admin tooling / peer-validation).

## 4. Default role catalog (seed)

В `kacho_iam.roles` (миграция-аddon к 0001_initial.sql):

| role.id | role.name | scope | permissions (FGA relations) |
|---|---|---|---|
| `rol000000kachoadmin01` | `kacho.admin` | system-wide | `kacho_system:root#admin` |
| `rol000000iamaccadmin1` | `iam.account.admin` | per-Account | `account:<id>#admin` (binding subject) |
| `rol000000iamaccview01` | `iam.account.viewer` | per-Account | `account:<id>#viewer` |
| `rol000000vpcadmin0001` | `vpc.admin` | per-Project | `project:<id>#admin` (cascade в vpc_*) |
| `rol000000vpceditor001` | `vpc.editor` | per-Project | `project:<id>#editor` |
| `rol000000vpcviewer001` | `vpc.viewer` | per-Project | `project:<id>#viewer` |
| `rol000000computeadmn1` | `compute.admin` | per-Project | `project:<id>#admin` |
| `rol000000computeedt01` | `compute.editor` | per-Project | `project:<id>#editor` |
| `rol000000computeview1` | `compute.viewer` | per-Project | `project:<id>#viewer` |

«AccessBinding Create» = «write Keto tuple per role.permissions с scope из binding.resource_id».

## 5. Acceptance scenarios (Given-When-Then)

### G1 — Bootstrap admin grant
- **Given** kacho-iam env `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL=admin@prorobotech.ru`, Keto empty.
- **When** новый user регистрируется с email=admin@prorobotech.ru через Kratos.
- **Then** в Keto появляется tuple `kacho_system:root#admin@user:<usr_id>`.
- **And** этот user видит ВСЕ Account через `/iam/v1/accounts` (включая чужие).
- **And** может создать Account через `/iam/v1/accounts`.

### G2 — Regular user self-grant
- **Given** Keto empty (или содержит только bootstrap).
- **When** user@example.com регистрируется.
- **Then** auto-create personal Account `user-acc-<hash>` + Project `default`.
- **And** Keto tuple `account:<acc_id>#admin@user:<usr_id>` записан.
- **And** этот user через `/iam/v1/accounts` видит ТОЛЬКО свой Account (другие = filtered).
- **And** через `/iam/v1/projects?accountId=<his>` видит свой Project; чужой accountId → 403.
- **And** `/vpc/v1/networks?projectId=<his>` → 200 пустой список.
- **And** `/vpc/v1/networks?projectId=<foreign>` → 403.

### G3 — Default-deny на чужой ресурс
- **Given** user A зарегистрирован (Account A); user B зарегистрирован (Account B).
- **When** user B пытается `GET /iam/v1/accounts/<A_id>`.
- **Then** 403 (НЕ 200, НЕ 404 — `PermissionDenied` явно).

### G4 — Admin grants role to user
- **Given** bootstrap admin login'нулся; user X имеет свой Account; есть Project Y у admin.
- **When** admin создаёт AccessBinding {subject: user:X, role: vpc.editor, resource: project:Y}.
- **Then** через ≤10s user X через `GET /iam/v1/projects/<Y>` → 200 (viewer/editor visibility).
- **And** user X может `POST /vpc/v1/networks` в project Y.

### G5 — Revoke role
- **Given** user X имеет vpc.editor на project Y.
- **When** admin удаляет AccessBinding.
- **Then** через ≤10s `GET /iam/v1/projects/<Y>` от user X → 403.

### G6 — Without Check: backward-compat
- **Given** principal.Type=system (internal service-to-service).
- **When** Check-interceptor видит system principal.
- **Then** bypass Check, разрешает все RPC.

## 6. Реализация (этапность)

### Этап 1 (этот sub-эпик) — Spec + Playwright red
- [x] Acceptance-doc (этот файл).
- [ ] Playwright `role-model.spec.ts` — все 6 scenarios (G1-G6); должны FAIL до этапа 2 (red phase).

### Этап 2 — Backend Check-interceptor (KAC-119 main)
- [ ] Удалить by-owner filter из `account/handler.go::List+Get` и `project/handler.go::List` (KAC-118 anti-pattern).
- [ ] kacho-corelib: pkg `authz/keto/` — Check-builder (для inline-Check в use-case'ах).
- [ ] kacho-iam: per-RPC Check (Get/List/Create/Update/Delete) через Keto-client (уже есть `keto_client.go`).
- [ ] kacho-iam: bootstrap admin env + auto-grant on UpsertFromIdentity (если email matches).
- [ ] kacho-iam: self-grant `account:<id>#admin@user:<usr_id>` для нового User'а в той же DB-TX где auto-create Account (KAC-117 расширение).

### Этап 3 — VPC/Compute Check-interceptor
- [ ] kacho-vpc / kacho-compute: per-RPC Check через `InternalIAMService.Check`.
- [ ] List через KetoLookupSubjects/Objects scope filter.

### Этап 4 — UI 403 page + AccessBindingPage
- [ ] `<Error code="403">` rendered ResourceListPage на 403 response.
- [ ] AccessBindingPage позволяет admin создать grant.

### Этап 5 — Playwright green
- [ ] role-model.spec.ts все 6 G-сценариев pass.

## 7. Acceptance gate

- Playwright `role-model.spec.ts` — все G1-G6 pass на cluster e2c825.
- Existing `iam-userflow.spec.ts` 13/13 продолжает pass (не сломали базовый flow).
- Manual smoke: открыть UI как новый user → видишь только свой Account; открыть как `admin@prorobotech.ru` → видишь всё.

## 8. Decision Log

| ID | Decision | Rationale |
|---|---|---|
| D-1 | by-owner filter (KAC-118) — anti-pattern, удаляется | User explicit feedback: «это antipattern, а ролевой моделью REBAC» |
| D-2 | Default email admin = `admin@prorobotech.ru` | User explicit, hard-coded в helm env |
| D-3 | Self-grant `account:<id>#admin@user:<usr>` для regular user | Self-service cloud pattern (как YC/AWS); user может управлять только своим Account |
| D-4 | Check на каждый public RPC | Default-deny — security baseline |
| D-5 | System principals bypass Check | Internal service-to-service (peer validation, kacho-iam → vpc Get, etc) |
| D-6 | UI на 403 — простое сообщение «Доступ запрещён» | User explicit feedback |

Relates [[KAC-104]]. Supersedes [[KAC-118]] (interim).
