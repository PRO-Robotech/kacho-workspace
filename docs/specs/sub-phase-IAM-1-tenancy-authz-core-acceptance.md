# Sub-phase IAM-1 (tenancy-tree + authz-binding core) — Acceptance

> Статус: **✅ APPROVED** (recorded by acceptance-reviewer verdict) (APPROVED-кандидат — на ревью acceptance-reviewer)
> Дата: 2026-07-20
> Ревьюер: acceptance-reviewer (ожидает review)
> Эпик/тикет: KAC-IAM-1 (Phase-1 leaf, redesign-2026; iam — leaf-владелец дерева аренды и грантов)
> Монорепо: `project/kacho` (`github.com/PRO-Robotech/kacho`) — легаси `project/kacho-*` **не затрагивается**.

## Обзор

IAM-1 — фундамент пересборки-2026 модуля **kacho-iam**. `kacho-iam` — единственный
владелец **дерева аренды** (`Account → Project`, строго два уровня) и единственный
источник **грантов** (`Role ⨝ AccessBinding`); от этих четырёх ресурсов зависят все
остальные под-фазы iam (ServiceAccount/User/Group/Auth) и все downstream-домены (vpc/
compute/nlb/registry/storage держат `projectId`/`accountId` как class-B scope-координату).
Под-фаза приводит **owner-side** проекции Account/Project/Role/AccessBinding к целевому
дизайну (`docs/plans/kacho-redesign-2026/module-iam.md`) и общему хребту
(`00-unified-system-design.md` §1/§5/§8): `Account.ownerUserId°` становится **output-only
derived-from-caller** (не принимается в Create-body); `Account.Create` — **one-shot сага**
(default `Project` + owner-`AccessBinding` в одной writer-tx, `metadata` несёт `accountId`
**и** `defaultProjectId`); `Project.accountId` — **immutable** (Move удалён, строго 2 уровня);
`Role` получает **`definitionTier`** (снятие путаницы «scope»/«tier»), compiled `permissions[]`
уходит в **Internal** (two-projection), появляется **канонический system-catalog** (viewer/
editor/admin/owner) с честным `effectiveVerbs°` (editor включает `delete*`); `AccessBinding`
переименовывает scope-anchor `resourceType/Id`→**`scopeType/scopeId`** (слово «resource»
резервируется за target'ом), **`target` становится REQUIRED** (least-priv) типа `ResourceRef{type,id}`,
а два исхода отзыва разводятся: **`Delete` = hard (Get→404)** / **`:revoke` = soft (status REVOKED,
retention)**.

Это **owner-side** под-фаза: сценарии описывают наблюдаемое поведение публичного
(`AccountService`/`ProjectService`/`RoleService`/`AccessBindingService`) и internal
(`InternalIAMService.GetRoleCompiled`/`Check`) API `kacho-iam` через api-gateway. Субъекты
(ServiceAccount/User/Group), вход (AuthService), полная introspection-поверхность
(AuthorizeService/PermissionCatalog) и discovery-каталоги — отдельные под-фазы (см. §Декомпозиция,
§Out-of-scope).

**Non-negotiables, действующие безусловно во всех сценариях:** flat resource (без
`spec`/`status`/`metadata`-envelope); мутации → `Operation` (async, `metadata.<res>Id` до `done`);
`Operation.done` = durability предмета мутации, **НЕ** downstream FGA-видимость (ban #9, EC via
bounded client-retry); two-projection (compiled `permissions`/FGA-tuples — только Internal :9091);
vendor-agnostic тон (ban #2 — никаких чужих облаков/third-party-product-noun'ов); within-service
инварианты — на DB-уровне (ban #10).

---

## Декомпозиция редизайна iam на под-фазы

iam — leaf, но самый крупный модуль (richest-suite: 20+ сервисов в текущем proto). Одним
acceptance-доком не покрыть → разбивка по кластерам ресурсов + зависимостям. Порядок —
топосортировка зависимостей (fundament → subjects → auth-plane).

| Под-фаза | Кластер ресурсов | Зависит от | Phase-0-блокеры |
|---|---|---|---|
| **IAM-1** (эта) | **Tenancy-tree** (`Account`/`Project`) + **authz-core** (`Role` `definitionTier` / `AccessBinding` scope-anchor+target+revoke) | — (фундамент; iam-leaf ни от какого сервиса не зависит) | **B1** (ResourceRef), **B3** (id-prefix), **B6** (roleId), by-lane тон (conv-11) |
| **IAM-2** | `ServiceAccount` (`defaultProjectId` informational, `status↔{ACTIVE,DISABLED}`) + `OAuthClient` (`:token` sync, credential-lifecycle) + `ServiceAccountService:forceLogout` | **IAM-1** (`SA.accountId` FK → Account; bootstrap-сага SA co-создаёт `AccessBinding` с `roleId`\|inline `rules[]` → нужны Role/AccessBinding) | **B11** (forceLogout = bounded-window, не hard-cutoff на stateless-JWKS) |
| **IAM-3** | `User` (output-mirror IdP, нет публичного Create) + `Group` (member-tuple **outbox**) + `UserInvitation` + grant-by-email reconciler + `AccountService.ListMembers` | **IAM-1** (Account для account-scoped Group/Invitation; AccessBinding для `subject.EMAIL` + `invitation.grant`), **IAM-2** (Group-member может быть ServiceAccount) | **B14** (Group `#member` outbox-emit+EC, не sync co-commit), **B15** (grant-by-email/invitation FGA-timing: intent→remap на login) |
| **IAM-4** | `AuthService` (login/callback/tokenExchange, OIDC-фасад) + `AuthorizeService` consolidation (Check/BatchCheck/ListObjects/ListSubjects/ExpandAccess) + `PermissionCatalog` (collapse/promote runtime-source) + discovery (`RoleService.List(assignableOn)` grantFragment, `ListGrantableResources`) | **IAM-1/2/3** (User-mirror для auth-materialize; Role.rules+AccessBinding для catalog+authorize; весь subject/grant-граф) | permission-catalog-gen (Фаза-0 corelib), byte-identical iam-seed↔gateway |

**Cross-cutting Фаза-0** (proto/corelib governance — блокирует IAM-1 merge): `kacho.cloud.common.v1`
с тремя ref-типами (`ResourceRef`/`Referrer`/`OciReferrer`, **B1**); `corevalidate` id-prefix
hyphen-форма (`acc-`/`prj-`/`rol-`/`acb-`, **B3**); by-lane error-token таблица в `api-conventions.md`;
`roleId` id-vs-dotted-name seam-решение (**B6**). Пока governance change-set не смёржен — conv-7/11/12
остаются **PROPOSED**; IAM-1 не мёржится (см. §Definition of Done merge-gate).

Зависимости иллюстративно: `IAM-1 → { IAM-2, IAM-3 } → IAM-4`. IAM-2 и IAM-3 частично параллельны
(IAM-3 Group-member-as-SA ждёт IAM-2); IAM-4 замыкает граф (нужны все три).

---

## Scope (что IAM-1 покрывает сценариями — positive + ≥1 negative + edge каждая)

| F | Фича | Traceability |
|---|---|---|
| F1 | `Account.ownerUserId°` — output-only **derived-from-caller**; передача в Create-body → sync `INVALID_ARGUMENT`; immutable в Update | module-iam Account/rule 1/10; unified §1 conv-1 |
| F2 | `Account.Create` **one-shot сага**: default `Project`("default") + owner-`AccessBinding` (role=owner, scope=iam.account, `deletionProtection=true`); `Operation.metadata` несёт `accountId` **+ `defaultProjectId`** | module-iam Account/rule 4; unified §1 conv-4 |
| F3 | `Project.accountId` **immutable** (Move удалён, строго 2 уровня); `UNIQUE(accountId,name)` | module-iam Project/rule 10/16; unified §5 |
| F4 | `Role.definitionTier{tierType,tierId}` (dotted, снятие «scope»/«tier»-путаницы); typed FK + CHECK-XOR внутри БД; `isSystem°` **derived** (`tierType==iam.cluster`) | module-iam Role/rule 7; unified §1 conv-7 |
| F5 | `Role.permissions[]` (compiled) убран из public (пусто) — только Internal `GetRoleCompiled` (two-projection) | module-iam Role/rule 8; unified §1 conv-8 |
| F6 | Канонический **system-role catalog** (viewer/editor/admin/owner) first-in-order + `effectiveVerbs°` (editor включает `delete*`); seed-роли immutable | module-iam Role catalog/rule 13; unified §1 conv-13 |
| F7 | `AccessBinding` scope-anchor rename `resourceType/Id`→**`scopeType/scopeId`** («resource» зарезервирован за target); `scopeType` dotted, OPTIONAL (выводится из `scopeId` prefix); immutable | module-iam AccessBinding/rule 7/10; unified §1 conv-7 |
| F8 | `AccessBinding.target` **REQUIRED** (least-priv, `allInScope{}` для all); `target=ResourceRef{type,id}` closed-table (без name) `[PHASE-0-GATED B1]` | module-iam AccessBinding/rule 7; unified §8 B1 |
| F9 | 3 sync структурных гейта Create (scope-XOR, `IsRoleAssignable`, `RoleCoversType`) — первыми стейтментами, actionable `FAILED_PRECONDITION` `[reason-token PHASE-0-GATED]` | module-iam AccessBinding/rule 12; unified §1 conv-11 |
| F10 | `Delete` = **hard** (Get→404, product-parity) / **`:revoke`** = soft (status→REVOKED, retention, replays emitted-ledger); re-grant после revoke = новая ACTIVE-строка (partial UNIQUE WHERE ACTIVE) | module-iam AccessBinding/rule 14; unified §5 |
| F11 | EC + mutability-классы: `Operation.done`=durability≠tuple-visibility (bounded-retry); List format-validate до authz-short-circuit; whitelist-filter | module-iam rule 3/10/13; unified §1 conv-11, §5 |

## Out-of-scope (явно НЕ в IAM-1)

- **IAM-2** — `ServiceAccount`/`OAuthClient`/`:token`/`:forceLogout`/credential-lifecycle (B11). `AccessBinding` subject `SERVICE_ACCOUNT` **принимается** в IAM-1 (тип в закрытом enum), но SA-ресурс и его bootstrap-сага (co-create OAuthClient+grant) — IAM-2.
- **IAM-3** — `User` (output-mirror, `Resolve`), `Group` (member-tuple outbox, `AddMember`/`RemoveMember`), `UserInvitation`, **grant-by-email** (`subject.EMAIL` материализация + `:grantToEmail` фасад), `AccountService.ListMembers`, derived `User.accounts°`. `SubjectType.EMAIL` и его invitation-mint reconciler (B15) — **не** в IAM-1: IAM-1 покрывает subjects `USER`/`SERVICE_ACCOUNT`/`GROUP` (by-id soft-ref).
- **IAM-4** — `AuthService` (login/callback/tokenExchange), `AuthorizeService` consolidation (`Check`/`BatchCheck`/`ListObjects`/`ListSubjects`/`ExpandAccess` — поглощает legacy `ListSubjectPrivileges`/`ExpandAccess`), `PermissionCatalogService` (collapse/promote runtime-source-of-truth), **discovery-каталоги** (`RoleService.List(assignableOn)` `grantFragment`, `AccessBindingService.ListGrantableResources`). IAM-1 фиксирует `AccessBindingService.List` **plain + whitelist-filter** (`subject=`/`role=`/`scope=`/`scopeId=`) как замену legacy `ListByScope`/`ListBySubject`/`ListByRole`/`ListByAccount`; introspection-merge — IAM-4.
- **`validateOnly:true` full blast-radius echo** (honest iam-vs-cross-module split, warnings[], normalized-tier echo — module-iam rule 6) — вынесен в follow-up. IAM-1 фиксирует **substance** (3 sync-гейта + actionable-текст, F9); полный dry-run echo — отдельная под-фаза.
- **Inline `condition` (CEL) + grant-`expiresAt`** — module-iam явно выносит в follow-up («не тянем самый тяжёлый ресурс до появления живого JIT/conditional-consumer'а»). AS-IS-поля `condition_id`/`expires_at`/`builtin_condition` остаются в proto (tombstone-дисциплина), но **вне IAM-1-контракта**.
- **Фаза-0 corelib/proto** — `common.v1` ResourceRef, `corevalidate` hyphen-prefix, permission-catalog-gen. IAM-1 **потребитель** этих governance-решений (merge-gate), но не их автор.
- **Legacy-ресурсы вне redesign-модели** (`Cluster`/`Organization`/`Condition`/federation/SCIM/SAML/JIT/CAEP) — не в целевом дизайне iam; их снос/тумбстоны — отдельная cleanup-под-фаза, не IAM-1.

## Traceability-легенда

`°` = output-only поле (server-derived, на вход не принимается → передача reject или ignore).
Каждый сценарий несёт `→ module-iam <секция>` / `→ unified §X` и, где меняется поведение, блок
**AS-IS** (реальное текущее состояние кода `project/kacho`). REST-пути: public `/iam/v1/…` (:9090,
external-safe); internal `InternalIAMService.*` (:9091, НИКОГДА на external — ban #6). JSON —
camelCase. `createdAt°` усечён до секунд на wire.

**id-форма:** iam-ресурсы = 3-char prefix + crockford-base32 (**НЕ** human-slug — slug только у geo).
Иллюстративные id в сценариях (`acc-…`/`prj-prod`/`rol-editor`/`acb-…`) показывают **hyphen-форму**
(`acc-`/`prj-`/`rol-`/`acb-`), которая landing'ится с **B3** `[PHASE-0-GATED]`; до Phase-0 действует
текущая non-hyphen crockford-форма (`acc…`/`prj…`). System-роли — детерминированный id.

**`[PHASE-0-GATED]`** помечает сценарий/поле, приземляющееся ТОЛЬКО после merge Phase-0 governance
change-set (B1 ResourceRef / B3 id-prefix / B6 roleId / by-lane reason-token). См. §Definition of Done
merge-gate.

---

## F1 — `Account.ownerUserId°` output-only derived-from-caller

> `→ module-iam` Account §Bootstrap-ownership, rule 1/10 · `→ unified §1 conv-1`
> **AS-IS** (`internal/apps/kacho/api/account/`): `owner_user_id` (tag 5) сейчас **ОБЯЗАТЕЛЕН** в
> Create-body — `create_test.go::TestCreate_Sync_RequireOwner` ждёт sync `InvalidArgument`
> «owner_user_id required» при отсутствии; плюс anti-hijack: `principal.ID` **обязан** == `OwnerUserId`.
> Redesign **инвертирует**: `ownerUserId` НЕ принимается в body (derive из caller), передача → reject.
> `Update` уже отвергает `owner_user_id` в mask (`update.go`) — этот тон сохраняется.

### Сценарий IAM-1-01 (positive): Account.Create БЕЗ ownerUserId → caller становится owner° автоматически

**ID:** IAM-1-01

**Given** аутентифицированный принципал (валидный JWT), `principal.id == "usr-9kd4b1"`
**And** `owner_user_id` **не** передаётся в теле запроса

**When** клиент вызывает `AccountService.Create` (`POST /iam/v1/accounts`) с payload:
  - `name` = `"acme-prod"`
  - `description` = `"Acme production tenant"`

**Then** ответ — `Operation`; `metadata` анмаршалится в `CreateAccountMetadata` с `accountId` (доступен до `done`)
**And** после `done` (bounded-retry на owner-tuple, см. IAM-1-30) `AccountService.Get(accountId)` возвращает `Account` с `ownerUserId° == "usr-9kd4b1"` (derived-from-caller — зеркало субъекта owner-`AccessBinding`)
**And** `status == "ACTIVE"`, `createdAt°` усечён до секунд

### Сценарий IAM-1-02 (negative): ownerUserId в Create-body → sync INVALID_ARGUMENT первым стейтментом

**ID:** IAM-1-02

**Given** аутентифицированный принципал `usr-9kd4b1`

**When** `AccountService.Create` (`POST /iam/v1/accounts`) с payload:
  - `name` = `"acme-prod"`
  - `ownerUserId` = `"usr-attacker"` (попытка задать владельца в body)

**Then** **синхронный** `INVALID_ARGUMENT` первым стейтментом RPC (до минта Operation) с текстом `"Illegal argument ownerUserId (derived from caller)"` — операция в таблицу не пишется
**And** тот же отказ на `ownerUserId == principal.id` (даже «правильное» значение недопустимо в body — поле output-only by construction; убирает и anti-hijack-branch, и required-branch AS-IS)

### Сценарий IAM-1-03 (edge): Update mask=["ownerUserId"] → INVALID_ARGUMENT immutable (до UpdateMask)

**ID:** IAM-1-03

**Given** аккаунт `acc-7fq2m8k3rd0xw` существует (owner `usr-9kd4b1`)

**When** `AccountService.Update` (`PATCH /iam/v1/accounts/acc-7fq2m8k3rd0xw`) с `updateMask=["ownerUserId"]`, `ownerUserId="usr-other"`

**Then** синхронный `INVALID_ARGUMENT` `"ownerUserId is immutable after Account.Create"` — immutable-switch срабатывает **до** `corevalidate.UpdateMask` (known-set маски не содержит immutable-поля, иначе оно упало бы как generic «unknown field»)

---

## F2 — `Account.Create` one-shot сага (default Project + owner-binding; metadata с двумя id)

> `→ module-iam` Account §One-shot Create-сага, rule 4 · `→ unified §1 conv-4`
> **AS-IS**: `CreateAccountMetadata` несёт **только** `account_id` (tag 1). AS-IS lazy-upsert personal
> Account (`InternalUserService.UpsertFromIdentity`, KAC-117) уже создаёт default `Project` +
> owner-binding, но публичный `Account.Create`-metadata **не** отдаёт `defaultProjectId` — клиент
> обязан List'ить. Redesign: **`defaultProjectId` в `metadata`** (не заставляем List'ить дефолт).

### Сценарий IAM-1-04 (positive): Create-сага co-commit'ит default Project + owner-AccessBinding; metadata несёт оба id

**ID:** IAM-1-04

**Given** аутентифицированный принципал `usr-9kd4b1`

**When** `AccountService.Create` с `name="acme-prod"` (как IAM-1-01)

**Then** `Operation.metadata` (`CreateAccountMetadata`) несёт **и** `accountId`, **и** `defaultProjectId` — оба доступны до `done` (клиент не List'ит дефолт-проект)
**And** после `done`: `ProjectService.Get(metadata.defaultProjectId)` возвращает `Project` с `name=="default"`, `accountId==metadata.accountId` (co-committed в одной writer-tx)
**And** `AccessBindingService.List(?scopeId=<accountId>)` (bounded-retry) содержит owner-`AccessBinding`: `subjects[0].id==usr-9kd4b1`, `roleId` = owner-роли, `scopeType=="iam.account"`, `scopeId==accountId`, `deletionProtection==true`
**And** одна writer-tx: partial-fail (owner-binding не закоммитился) НЕ оставляет phantom-Account — либо всё три row (Account+Project+binding), либо ничего

### Сценарий IAM-1-05 (edge): owner-AccessBinding защищён deletionProtection → Delete отклоняется

**ID:** IAM-1-05

**Given** аккаунт `acc-7fq2m8k3rd0xw` создан сагой; owner-`AccessBinding acb-owner` несёт `deletionProtection=true`

**When** `AccessBindingService.Delete` (`DELETE /iam/v1/accessBindings/acb-owner`)

**Then** синхронный `FAILED_PRECONDITION` `"access binding acb-owner has deletion_protection enabled; clear it via Update before Delete"` + atomic CAS-backstop (`DELETE … WHERE deletion_protection=false` → 0 rows против TOCTOU) — создатель не может случайно снести собственный owner-грант

### Сценарий IAM-1-06 (negative): Account.Delete с непустым RESTRICT-набором → op.error FAILED_PRECONDITION

**ID:** IAM-1-06

**Given** аккаунт `acc-7fq2m8k3rd0xw` содержит ≥1 `Project` (как минимум default)

**When** `AccountService.Delete` (`DELETE /iam/v1/accounts/acc-7fq2m8k3rd0xw`)

**Then** `Operation{done:true}` c `result.error`: `FAILED_PRECONDITION`, текст `"Account acc-7fq2m8k3rd0xw contains projects"` (within-service FK RESTRICT `projects.account_id`, ban #10 — DB-backstop, не software-precheck)

---

## F3 — `Project.accountId` immutable (Move удалён; строго 2 уровня); UNIQUE(accountId,name)

> `→ module-iam` Project, rule 10/16 · `→ unified §5`
> **AS-IS** (`project.proto`): message-doc гласит «Project можно Move в другой Account (см.
> ProjectService.Move) — DB-level атомарный CAS», НО `project_service.proto` **не содержит `Move` RPC**
> (только Get/List/Create/Update/Delete/ListOperations) — stale-комментарий. `UNIQUE(account_id,name)`
> + FK RESTRICT существуют (vault `iam-project`). Redesign: `accountId` **hard-immutable**; implementer
> **обязан удалить** stale Move-упоминание из message-doc (иначе следующий контрибьютор восстановит Move).

### Сценарий IAM-1-07 (positive): Project.Create под аккаунтом; accountId заполнен, immutable

**ID:** IAM-1-07

**Given** аккаунт `acc-7fq2m8k3rd0xw` существует

**When** `ProjectService.Create` (`POST /iam/v1/projects`) с `accountId="acc-7fq2m8k3rd0xw"`, `name="staging"`

**Then** `Operation`; `metadata.projectId` доступен; после `done` `ProjectService.Get` возвращает `Project` с `accountId=="acc-7fq2m8k3rd0xw"`, `status=="ACTIVE"`
**And** Project — leaf-workspace (строго под Account, без вложенности: нет поля parent-project/folder — иерархия не углубляется)

### Сценарий IAM-1-08 (negative): Update mask=["accountId"] → INVALID_ARGUMENT immutable

**ID:** IAM-1-08

**Given** проект `prj-staging` (accountId=`acc-7fq2m8k3rd0xw`)

**When** `ProjectService.Update` (`PATCH /iam/v1/projects/prj-staging`) с `updateMask=["accountId"]`, `accountId="acc-other"`

**Then** синхронный `INVALID_ARGUMENT` `"accountId is immutable after Project.Create"` (immutable-switch до `UpdateMask`) — cross-account перенос запрещён (сломал бы scope-координату всех downstream-ресурсов, держащих `projectId`); **нет `Move` RPC** — единственный путь смены accountId отсутствует by construction

### Сценарий IAM-1-09 (negative+edge): duplicate name в аккаунте → ALREADY_EXISTS; то же имя в другом аккаунте → OK

**ID:** IAM-1-09

**Given** проект `prj-prod` с `name="prod"` под `acc-A`; аккаунт `acc-B` существует

**When** `ProjectService.Create` с `accountId="acc-A"`, `name="prod"` (дубль в том же аккаунте)

**Then** `Operation{done:true}` c `result.error`: `ALREADY_EXISTS` (partial `UNIQUE(account_id,name)`, SQLSTATE 23505 → DB-backstop)
**And** `ProjectService.Create` с `accountId="acc-B"`, `name="prod"` → успех (uniqueness — per-account, не глобально)

---

## F4 — `Role.definitionTier` (снятие «scope»/«tier»-путаницы); isSystem° derived

> `→ module-iam` Role, rule 7 · `→ unified §1 conv-7`
> **AS-IS** (`role.proto`): роль несёт **типизированные nullable FK** `cluster_id`(tag8)/`account_id`(tag2)/
> `project_id`(tag10) + DB-CHECK `roles_scope_xor` (ровно один non-NULL); `is_system` (tag6) — **хранимый
> bool**; отдельного `definitionTier`-message нет; концепт называется «scope» в CHECK-имени. Redesign:
> **wire-проекция `definitionTier{tierType,tierId}`** (dotted `{iam.cluster|iam.account|iam.project}` +
> anchor-id) над теми же типизированными FK+CHECK-XOR; `isSystem°` — **derived** (`tierType==iam.cluster`),
> не хранимый провенанс-флаг; слово «scope» на роли не появляется (зарезервировано за `AccessBinding`).

### Сценарий IAM-1-10 (positive): Role.Create с definitionTier; Get возвращает dotted-проекцию; isSystem° derived false

**ID:** IAM-1-10

**Given** аккаунт `acc-7fq2m8k3rd0xw` существует

**When** `RoleService.Create` (`POST /iam/v1/roles`) с payload:
  - `name` = `"app-deployer"`
  - `definitionTier` = `{ tierType: "iam.account", tierId: "acc-7fq2m8k3rd0xw" }`
  - `rules` = `[{ module:"compute", resources:["instance","disk"], verbs:["get","list","create","update"] }]`

**Then** `Operation`; после `done` `RoleService.Get` возвращает `Role` с `definitionTier.tierType=="iam.account"`, `definitionTier.tierId=="acc-7fq2m8k3rd0xw"`
**And** `isSystem° == false` (derived: `tierType != "iam.cluster"`)
**And** ответ **не** содержит поля с именем `scope`/`scopeType`/`scopeId` на роли (слово «scope» зарезервировано за `AccessBinding`-anchor'ом; assert field-absence)
**And** `rules[0].module=="compute"`, `resources==["instance","disk"]` (public-surface roundtrip)

### Сценарий IAM-1-11 (negative): definitionTier XOR нарушен → INVALID_ARGUMENT

**ID:** IAM-1-11

**Given** аккаунт `acc-A` и проект `prj-P` существуют

**When** `RoleService.Create` с `definitionTier` эквивалентным **двум** непустым anchor'ам (напр. и account, и project — репо получает и `account_id`, и `project_id` non-NULL)

**Then** `INVALID_ARGUMENT` `"Illegal argument definitionTier"` — ровно один валидный anchor (CHECK-XOR `roles_definition_tier_xor` на DB-уровне — DB-backstop; sync well-formedness-гейт при однозначно-битой форме)
**And** `definitionTier` без валидного anchor (пустой `tierType`) → тот же `INVALID_ARGUMENT`

### Сценарий IAM-1-12 (edge) `[PHASE-0-GATED B3/B6]`: tierType выводится из tierId prefix

**ID:** IAM-1-12

**Given** аккаунт `acc-7fq2m8k3rd0xw`; hyphen-prefix id-форма landing'нута (B3)

**When** `RoleService.Create` с `definitionTier={ tierId: "acc-7fq2m8k3rd0xw" }` (**`tierType` опущен**) и валидными `rules`

**Then** `tierType` выводится из prefix `acc-` ⇒ `"iam.account"`; `RoleService.Get.definitionTier.tierType=="iam.account"`
**And** `[PHASE-0-GATED]`: вывод-по-prefix зависит от B3 (hyphen-форма `acc-`/`prj-`/`rol-` в `corevalidate` prefix→type-router). До Phase-0 `tierType` **обязателен** (текущая non-hyphen форма не даёт однозначного router-lookup); merge-gate — §Definition of Done

---

## F5 — `Role.permissions[]` (compiled) только Internal (two-projection)

> `→ module-iam` Role, rule 8 · `→ unified §1 conv-8`
> **AS-IS** (`role.proto`): `permissions` (tag5) `[deprecated=true]` — INTERNAL compiled-форма
> (4-сегмент `M.R.rn.V`); в `Get`/`List` для rules-ролей **пусто**; client-sent на Create/Update →
> `INVALID_ARGUMENT` (ignored). Redesign **формализует**: compiled `permissions` физически **не на
> public поверхности вовсе**; читается ТОЛЬКО через Internal `InternalIAMService.GetRoleCompiled` (:9091).

### Сценарий IAM-1-13 (positive): public Role.Get НЕ несёт compiled permissions; Internal GetRoleCompiled несёт

**ID:** IAM-1-13

**Given** роль `rol-app-deployer` создана с `rules` (IAM-1-10)

**When** `RoleService.Get` (`GET /iam/v1/roles/rol-app-deployer`) на публичном листенере

**Then** ответ — `Role` с `rules[]` (authored, public-surface); поле `permissions` **пусто/отсутствует** (compiled не течёт на public — assert field-absence/empty)
**And** `InternalIAMService.GetRoleCompiled` (:9091, `system_admin`) возвращает compiled `permissions[]` в форме `M.R.rn.V` (напр. `"compute.instance.*.get"`) — two-projection: authz-топология только Internal
**And** `RoleService.List` item тоже несёт `rules[]` и НЕ несёт compiled `permissions`

### Сценарий IAM-1-14 (negative): client-sent permissions[] на Create → INVALID_ARGUMENT

**ID:** IAM-1-14

**When** `RoleService.Create` с непустым `permissions=["compute.instance.*.get"]` в теле (client пытается задать compiled-форму)

**Then** синхронный `INVALID_ARGUMENT` — `permissions` output-only compiled-проекция, на вход не принимается (authored-политика задаётся ТОЛЬКО через `rules[]`); AS-IS-тон сохраняется

---

## F6 — Канонический system-role catalog + effectiveVerbs° (editor delete*)

> `→ module-iam` Role §Канонический system-role catalog, rule 13 · `→ unified §1 conv-13`
> **AS-IS**: seed-роли — `rol000000000sysadmin`/`rol000000000sysviewe` (2 роли, opaque non-hyphen id);
> нет концепта `effectiveVerbs°`, нет canonical viewer/editor/admin/owner-четвёрки, нет
> «первыми-в-порядке». Redesign: опубликованный набор viewer→editor→admin→owner (+ canned narrow),
> возвращаемый **первыми** из `RoleService.List`; `effectiveVerbs°` — **честный** co-материализованный
> набор (editor: `[get,list,create,update,delete*]` — `delete*` на leaf-объектах scope'а, НЕ на anchor'е).
> Детерминированные human-id `rol-editor`… — **hyphen-форма PHASE-0-GATED B3**.

### Сценарий IAM-1-15 (positive): RoleService.List — system-роли первыми, viewer→editor→admin→owner; editor.effectiveVerbs включает delete*

**ID:** IAM-1-15

**Given** каталог seed'нут канонической четвёркой (viewer/editor/admin/owner, `definitionTier.tierType=="iam.cluster"`)

**When** `RoleService.List` (`GET /iam/v1/roles`)

**Then** массив `roles[]` начинается с system-ролей **в порядке** viewer → editor → admin → owner (first-class first-in-order), затем custom-роли
**And** каждая system-роль несёт `isSystem° == true` (derived, cluster-tier); `authoredVerbs°` и `effectiveVerbs°`
**And** `editor.authoredVerbs° == ["get","list","create","update"]`, но `editor.effectiveVerbs° == ["get","list","create","update","delete*"]` — **честный** co-материализованный набор; `verbNotes["delete*"]` дословно `"co-materialized on in-scope leaf objects, NOT on the account/project anchor itself"` (least-priv-прогноз не врёт)
**And** `viewer.effectiveVerbs°==["get","list"]`; `admin`/`owner` — full-CRUD (+`manage-bindings` у owner)

### Сценарий IAM-1-16 (negative): Update/Delete system-роли (cluster-tier) → FAILED_PRECONDITION

**ID:** IAM-1-16

**Given** system-роль `editor` (`isSystem°` derived true, `definitionTier.tierType=="iam.cluster"`)

**When** `RoleService.Update` (`PATCH …/rol-editor`, изменить `rules`) **или** `RoleService.Delete`

**Then** `FAILED_PRECONDITION` — seed/system-роль (derived cluster-tier) immutable; ни `rules`, ни `Delete` не применяются

### Сценарий IAM-1-17 (edge) `[PHASE-0-GATED B3]`: детерминированные hyphen-id system-ролей

**ID:** IAM-1-17

**Given** hyphen-prefix id-форма landing'нута (B3)

**When** `RoleService.List`

**Then** system-роли несут детерминированные human-читаемые id `rol-viewer`/`rol-editor`/`rol-admin`/`rol-owner`
**And** `[PHASE-0-GATED]`: hyphen-форма id зависит от B3 (`corevalidate` id-prefix). **AS-IS**: seed-id сейчас `rol000000000sysadmin`/`rol000000000sysviewe` (non-hyphen, 2 роли). До Phase-0 каталог использует текущую форму; merge-gate — §Definition of Done. `[PHASE-0-GATED B6]`: ссылка на роль в `grant.roleId` = `rol-`-id (не dotted-name `editor`) — seam-решение B6

---

## F7 — `AccessBinding` scope-anchor rename `resourceType/Id`→`scopeType/scopeId`

> `→ module-iam` AccessBinding, rule 7/10 · `→ unified §1 conv-7`
> **AS-IS** (`access_binding.proto`): binding несёт `resource_type`(tag5)/`resource_id`(tag6)
> `[DEPRECATED-in-favour-of scope_ref]` + nested `ScopeRef{tier: Scope enum CLUSTER/ACCOUNT/PROJECT, id}`
> (tag17). Redesign: **flatten** в `scopeType` (dotted `{iam.cluster|iam.account|iam.project}`) + `scopeId`;
> слово «resource» **зарезервировано за `target`**; `scopeType` OPTIONAL (выводится из `scopeId` prefix,
> `[PHASE-0-GATED B3]`); anchor immutable.

### Сценарий IAM-1-18 (positive): Create со scopeId (scopeType опущен → derived); Get несёт scopeType/scopeId

**ID:** IAM-1-18 `[scopeType-derivation PHASE-0-GATED B3]`

**Given** проект `prj-prod`, роль `rol-editor` (assignable на iam.project), target доступен (см. F8)

**When** `AccessBindingService.Create` (`POST /iam/v1/accessBindings`) с payload:
  - `subjects` = `[{ type:"USER", id:"usr-9kd4b1" }]`
  - `roleId` = `"rol-editor"`
  - `scopeId` = `"prj-prod"` (**`scopeType` опущен**)
  - `target` = `{ allInScope: {} }`

**Then** `Operation`; после `done` `AccessBindingService.Get` возвращает `AccessBinding` со `scopeType=="iam.project"` (derived из `prj-` prefix, `[PHASE-0-GATED B3]`), `scopeId=="prj-prod"`
**And** ответ **не** несёт полей `resourceType`/`resourceId` под этим смыслом (имя «resource» отдано target'у; assert `scopeType`/`scopeId` — единственная scope-проекция)
**And** до Phase-0 (B3): `scopeType` **обязателен** на входе (non-hyphen форма не даёт prefix-router) — сценарий требует явный `scopeType:"iam.project"`

### Сценарий IAM-1-19 (negative): scopeType/scopeId immutable через Update

**ID:** IAM-1-19

**Given** binding `acb-5k2m9x` (scopeType=iam.project, scopeId=prj-prod)

**When** `AccessBindingService.Update` (`PATCH …/acb-5k2m9x`) с `updateMask=["scopeId"]` (или `["scopeType"]`, `["roleId"]`, `["subjects"]`)

**Then** синхронный `INVALID_ARGUMENT` `"<field> is immutable after AccessBinding.Create"` (immutable-switch до `UpdateMask`) — mutable-set = только `{deletionProtection, labels}` (+ `selector`-арм через `ReplaceTargetSelector`, вне IAM-1)

### Сценарий IAM-1-20 (edge): явный scopeType для non-iam/дизамбигуации

**ID:** IAM-1-20

**Given** роль `rol-cluster-admin` (definitionTier iam.cluster), кластер-anchor

**When** `AccessBindingService.Create` со `scopeType="iam.cluster"`, `scopeId="cluster_kacho_root"` (явный — cluster-anchor id не самоописателен prefix'ом), валидный target

**Then** `Operation`; `Get.scopeType=="iam.cluster"`, `scopeId=="cluster_kacho_root"` — явный `scopeType` принимается для дизамбигуации (iam-anchor'ы с выводимым prefix — опциональны; cluster/non-iam — явный)

---

## F8 — `AccessBinding.target` REQUIRED + `ResourceRef{type,id}` closed-table

> `→ module-iam` AccessBinding §target, rule 7 · `→ unified §8 B1`
> **AS-IS** (`access_binding.proto`): `target`/`target_ref`/`selector` **TOMBSTONED** — tags 16/18
> `reserved`, комментарий: «object-selection now lives entirely in `role.rules` (ARM_ANCHOR/ARM_NAMES/
> ARM_LABELS)». Redesign **РЕИНТРОДУЦИРУЕТ** `target` как **REQUIRED** first-class oneof `{resources[] |
> allInScope{} | selector}` типа `ResourceRef{type,id}` (closed-table, без name) — **новыми tag'ами**
> (16/18 tombstone НЕ переиспользуются, append-only). `ResourceRef` приходит из `common.v1` governance
> (B1) → **вся target-proto-работа `[PHASE-0-GATED]`**.

### Сценарий IAM-1-21 (positive) `[PHASE-0-GATED B1]`: Create с target.allInScope{} и с target.resources[ResourceRef]

**ID:** IAM-1-21

**Given** проект `prj-prod`, роль `rol-editor` (assignable на iam.project)

**When** `AccessBindingService.Create` с `subjects=[{type:"USER",id:"usr-9kd4b1"}]`, `roleId="rol-editor"`, `scopeType="iam.project"`, `scopeId="prj-prod"`, `target={ allInScope: {} }` (явный opt-in: все объекты под anchor'ом, включая будущие)

**Then** `Operation`; после `done` `Get.target.allInScope` задан (грант на весь scope, materialized reconciler'ом)

**When** второй Create с `target={ resources: [{ type:"compute.instance", id:"ins-abc" }] }` (per-object)

**Then** `Get.target.resources[0]` — `ResourceRef{ type:"compute.instance", id:"ins-abc" }` (per-object polymorphic, graceful-dangling; `type` — dotted из закрытого type-registry)
**And** `[PHASE-0-GATED]`: `ResourceRef`-тип приходит из `kacho.cloud.common.v1` (B1 3-way ref-naming). До Phase-0 proto-работа над `target` **не начинается** (nested-message ещё не существует); merge-gate — §Definition of Done

### Сценарий IAM-1-22 (negative): Create БЕЗ target → sync INVALID_ARGUMENT (least-priv spine)

**ID:** IAM-1-22 `[PHASE-0-GATED B1]`

**Given** проект `prj-prod`, роль `rol-editor`

**When** `AccessBindingService.Create` с `subjects`/`roleId`/`scopeId`, но **без** `target` (ни `resources`, ни `allInScope`, ни `selector`)

**Then** **синхронный** `INVALID_ARGUMENT` первым стейтментом `"target is required; use target.allInScope{} to grant all objects under the anchor"` — least-privilege by default (самый широкий грант достижим ТОЛЬКО явным `allInScope{}` opt-in; нет sentinel-по-умолчанию)

### Сценарий IAM-1-23 (edge) `[PHASE-0-GATED B1]`: ResourceRef closed-table — без name-поля; unknown type → INVALID_ARGUMENT

**ID:** IAM-1-23

**Given** проект `prj-prod`, роль `rol-editor`

**When** `AccessBindingService.Create` с `target.resources=[{ type:"compute.instance", id:"ins-abc", name:"web-01" }]` (клиент шлёт `name`)

**Then** `name` в `ResourceRef` **не** принимается/игнорируется — `ResourceRef` = closed-table `{type,id}` (в отличие от generic `Referrer{type,id,name°}`; B1 3-way disambiguation: iam target = `ResourceRef` без name)
**And** `target.resources=[{ type:"unknown.thing", id:"x" }]` (тип вне закрытого type-registry) → sync `INVALID_ARGUMENT` `"Illegal argument target.resources[].type"` (closed-table валидируется)

### Сценарий IAM-1-24 (negative): RoleCoversType — target.type не покрыт role.rules → sync FAILED_PRECONDITION actionable

**ID:** IAM-1-24 `[reason-token PHASE-0-GATED]`

**Given** роль `rol-vpc-viewer` покрывает только `vpc.*` (rules без compute); проект `prj-prod`

**When** `AccessBindingService.Create` с `roleId="rol-vpc-viewer"`, `target.resources=[{ type:"compute.instance", id:"ins-abc" }]`

**Then** **синхронный** `FAILED_PRECONDITION` первым стейтментом (3-й sync-гейт `RoleCoversType`, до минта Operation) с actionable-хвостом `"role rol-vpc-viewer does not grant verbs on compute.instance; target type must be covered by role.rules"`
**And** `[PHASE-0-GATED]`: `reason`-token в `google.rpc.Status.details` (напр. `ROLE_DOES_NOT_COVER_TYPE`) приземляется после Phase-0 reason-token таблицы; **код и текст** — ungated

---

## F9 — 3 sync структурных гейта Create (scope-XOR / IsRoleAssignable / RoleCoversType) первыми стейтментами

> `→ module-iam` AccessBinding §Три детерминированных структурных гейта, rule 12 · `→ unified §1 conv-11`
> Гейты — SYNC, первыми стейтментами RPC (как malformed-id), **ДО** минта Operation, в pre-check без
> TOCTOU. `Operation.error` зарезервирован ТОЛЬКО за истинно-async фейлами (FGA per-object tuple-эмиссия).

### Сценарий IAM-1-25 (negative): IsRoleAssignable — definitionTier роли несовместим с anchor'ом → sync FAILED_PRECONDITION actionable

**ID:** IAM-1-25 `[reason-token PHASE-0-GATED]`

**Given** роль `rol-editor` с `definitionTier.tierType=="iam.account"` (account-tier); проект `prj-prod`

**When** `AccessBindingService.Create` с `roleId="rol-editor"`, `scopeType="iam.project"`, `scopeId="prj-prod"`, валидный target

**Then** **синхронный** `FAILED_PRECONDITION` первым стейтментом (2-й sync-гейт `IsRoleAssignable`) с текстом `"role rol-editor (definitionTier iam.account) is not assignable on iam.project:prj-prod; assign at iam.project or iam.account tier of this account"` (actionable-хвост — не POST→poll)
**And** обратное валидно: iam.account-роль assignable на **вложенном** iam.project того же аккаунта (tierAssignability: `iam.account` → own account anchor AND nested project of same account); `iam.cluster`-роль assignable на ЛЮБОМ anchor'е
**And** `[PHASE-0-GATED]`: `reason`-token (`ROLE_NOT_ASSIGNABLE_ON_TIER`) — после Phase-0 таблицы; код+текст ungated

### Сценарий IAM-1-26 (negative): scope-XOR/well-formedness — scopeId не резолвится в anchor → sync первым стейтментом

**ID:** IAM-1-26

**Given** аутентифицированный принципал

**When** `AccessBindingService.Create` с `scopeId="prj-nonexistent"` (well-formed id, но anchor не существует), либо malformed `scopeId="!!!"`

**Then** malformed `scopeId` → синхронный `INVALID_ARGUMENT` `"invalid access binding scope id '!!!'"` первым стейтментом (1-й sync-гейт scope-XOR/well-formedness, `corevalidate.ResourceID` до repo)
**And** well-formed-но-нет anchor → синхронный `NOT_FOUND "Project prj-nonexistent not found"` (within-service pre-flight resolve — anchor в `kacho_iam`; direct-read lane) — НЕ уходит в async op.error

---

## F10 — `Delete` = hard (Get→404) / `:revoke` = soft (REVOKED, retention); re-grant после revoke

> `→ module-iam` AccessBinding §Два исхода отзыва, rule 14 · `→ unified §5`
> **AS-IS** (`access_binding/delete.go`): `Delete` **уже физический hard-delete** (0 rows → NotFound;
> удаляет row + emitted FGA-tuples в той же writer-tx + sync RelationStore.DeleteTuples) — product-parity
> с compute/vpc **уже есть**. Enum `Status.REVOKED` существует, но публичного **`:revoke` action НЕТ**
> (service: Get/Create/Delete/Update/List*/ExpandAccess). AS-IS UNIQUE — **полный**
> `(subject_type,subject_id,role_id,resource_type,resource_id)` (не partial WHERE ACTIVE). Redesign:
> `Delete` остаётся hard; **добавляется `:revoke`** (soft, retention, replays persisted emitted-ledger);
> UNIQUE → **partial `WHERE status='ACTIVE'`** (корректный re-grant после revoke).

### Сценарий IAM-1-27 (positive): Delete = физическое удаление (Get→404), product-parity

**ID:** IAM-1-27

**Given** binding `acb-5k2m9x` (ACTIVE, `deletionProtection=false`)

**When** `AccessBindingService.Delete` (`DELETE /iam/v1/accessBindings/acb-5k2m9x`)

**Then** `Operation`; после `done` `AccessBindingService.Get(acb-5k2m9x)` → `NOT_FOUND "AccessBinding acb-5k2m9x not found"` (физическое удаление — тот же смысл, что compute/vpc/nlb/registry; никакого iam-специфичного soft-delete под именем Delete)
**And** emitted FGA-tuple-набор снят в той же writer-tx (deny наблюдается как только Operation `done`)

### Сценарий IAM-1-28 (positive): :revoke = soft-revoke (status→REVOKED, revokedAt set, row retained)

**ID:** IAM-1-28

**Given** binding `acb-5k2m9x` (ACTIVE)

**When** `AccessBindingService.Revoke` (`POST /iam/v1/accessBindings/acb-5k2m9x:revoke`) — **новый action-verb → Operation**

**Then** `Operation`; после `done` `AccessBindingService.Get(acb-5k2m9x)` **всё ещё возвращает row** со `status=="REVOKED"` (terminal), `revokedAt°` set, `grantedByUserId°` удержан (audit-retention — в отличие от Delete)
**And** снятый tuple-набор = **persisted emitted-ledger** (`access_binding_emitted_tuples`), не ре-деривится из текущей роли (нет orphan при Role.Update между grant и revoke)

### Сценарий IAM-1-29 (edge): re-grant после :revoke → новая ACTIVE-строка; идентичный Create при ACTIVE → ALREADY_EXISTS

**ID:** IAM-1-29

**Given** binding `acb-5k2m9x` **revoked** (status REVOKED) — тот же `(subjects, role, scope, target)`

**When** `AccessBindingService.Create` с идентичным `(subjects, roleId, scopeType, scopeId, target)`

**Then** `Operation{done:true}` — **новая ACTIVE-строка** (новый `acb-…` id); REVOKED-строка слот не занимает (partial `UNIQUE(subject-set,role,scope,target) WHERE status='ACTIVE'`) — НЕ `ALREADY_EXISTS`
**And** тот же идентичный Create при уже-**ACTIVE**-строке → `Operation{done:true}` c `result.error` `ALREADY_EXISTS` (идемпотентность grant — partial UNIQUE ловит ACTIVE-дубль)

### Сценарий IAM-1-30 (negative): Delete с deletionProtection=true → FAILED_PRECONDITION + CAS-backstop

**ID:** IAM-1-30

**Given** binding `acb-owner` с `deletionProtection=true` (owner-auto-binding)

**When** `AccessBindingService.Delete(acb-owner)`

**Then** синхронный `FAILED_PRECONDITION` `"access binding acb-owner has deletion_protection enabled; clear it via Update before Delete"` + atomic CAS-backstop (`DELETE … WHERE deletion_protection=false` → 0 rows) против TOCTOU; снять guard → `Update(updateMask=["deletionProtection"], deletionProtection=false)` → затем Delete

---

## F11 — EC (`Operation.done`=durability≠tuple-visibility) + List format-validate + mutability

> `→ module-iam` rule 3/10/13 · `→ unified §1 conv-11, §5`
> `Operation.done` = binding DURABLE, НЕ downstream FGA-видимость (ban #9). Серверный confirm-gate
> запрещён (phantom). AS-IS: legacy `ListByScope`/`ListBySubject`/`ListByRole`/`ListByAccount` — отдельные
> RPC; redesign сворачивает в `List` + whitelist-filter (introspection-merge — IAM-4).

### Сценарий IAM-1-31 (edge): Operation.done — binding durable; owner/grant tuple EC → bounded client-retry, не серверный барьер

**ID:** IAM-1-31

**Given** клиент только что создал `AccessBinding` (Operation `done:true`)

**When** ПЕРВЫЙ `Check`/`Get` доступа своего свежего гранта сразу после `done`

**Then** может кратко вернуть `403`/`404` (owner/grant-tuple ещё материализуется — EC, negative-cache TTL ≈5s) — это read-your-writes лаг, НЕ genuine deny
**And** чинится **на клиенте** `retry_until_authorized` (bounded, budget ≈6-10s, стабильный `Retry-After`-hint), НЕ серверным confirm-gate (ban #9 — гейтить `Operation.done` на видимость tuple рождает phantom-ресурс)
**And** fixture обязан проверять `!op.error` **перед** извлечением id из `metadata` (Kachō Operation несёт pre-allocated id даже на `done:true`+`error`)

### Сценарий IAM-1-32 (negative): AccessBindingService.List — garbage page_token → INVALID_ARGUMENT ДО authz-short-circuit; whitelist-filter

**ID:** IAM-1-32

**Given** аутентифицированный принципал

**When** `AccessBindingService.List` (`GET /iam/v1/accessBindings?pageToken=%%%not-base64%%%`)

**Then** `INVALID_ARGUMENT` (format-validate `pageToken`/`pageSize` **до** listauthz empty-grant short-circuit; `pageSize>1000` → `INVALID_ARGUMENT`, отвергается не clamp'ится) — единый порядок: format-validate → listauthz → repo
**And** `List` принимает whitelist-filter `subject=`/`role=`/`scope=`/`scopeId=` (замена legacy `ListByScope`/`ListBySubject`/`ListByRole`/`ListByAccount`); неизвестный filter-ключ → `INVALID_ARGUMENT`
**And** `List = viewer ∪ v_list` (anonymous→empty; FGA error→`Unavailable` fail-closed, никогда unfiltered-leak)

### Сценарий IAM-1-33 (edge): INTERNAL никогда не эхает pgx/SQL-текст

**ID:** IAM-1-33

**Given** некатегоризированная DB-ошибка на write-пути (симулируется в integration-слое)

**When** любая мутация (Account/Project/Role/AccessBinding Create) упирается в неё

**Then** `result.error` (или sync error) — фиксированный opaque-текст (`"internal error"`), **NotContains** driver/connection-текст (host/port/user/db); regression-lock проверяет **сообщение**, не только код (на **обоих** листенерах — Internal :9091 не освобождён)

---

## Definition of Done

IAM-1 готова к merge только при выполнении ВСЕГО чек-листа (`ai-tooling.md` §lifecycle gate 4-7;
`testing.md`):

**Traceability + тесты (1-to-1):**
- [ ] Каждый `IAM-1-NN` имеет зелёный **integration-тест** (testcontainers Postgres) — `Test<Resource>_IAM_1_NN`
  (напр. `TestAccount_IAM_1_01`, `TestAccessBinding_IAM_1_29`) — покрывающий SQL-сторону, включая CHECK-XOR/
  FK-RESTRICT/partial-UNIQUE(WHERE ACTIVE)/CAS/concurrent-race где применимо (re-grant-after-revoke race, saga-atomicity, deletion_protection CAS-backstop).
- [ ] Каждый `IAM-1-NN` (наблюдаемый через api-gateway) имеет зелёный **newman-кейс** `tests/newman/cases/*.py`
  с аннотацией `# verifies IAM-1-NN` — ≥1 happy + ≥1 negative per фича; трассировка `IAM-1-NN ↔ Test<R>_IAM_1_NN ↔ cases/*.py`.
- [ ] TDD-порядок соблюдён: RED (падает по нужной причине) ДО кода, пара RED→GREEN в PR.
- [ ] Concurrency-тесты под `-race`: (a) Account.Create-сага atomicity (partial-fail → 0 phantom-row); (b) re-grant-after-revoke — партиал-UNIQUE WHERE ACTIVE (concurrent identical Create ↔ Revoke); (c) deletion_protection CAS-backstop против TOCTOU.

**e2e-smoke (real gateway, construction-verified):**
- [ ] one-shot Account.Create: `metadata` несёт `accountId` **+ `defaultProjectId`**; default `Project`("default") + owner-`AccessBinding`(deletionProtection=true) реально существуют (IAM-1-04).
- [ ] two-projection field-absence на **реальном** gateway-ответе: public `Role.Get` НЕ содержит compiled `permissions` (IAM-1-13); public `AccessBinding` scope — `scopeType`/`scopeId`, не `resourceType`/`resourceId` (IAM-1-18).
- [ ] Delete=hard (Get→404) vs `:revoke`=soft (Get→REVOKED-row) наблюдаемо различимы (IAM-1-27/28).

**Deliverables редизайна (implementer обязан выполнить — иначе старый путь остаётся):**
- [ ] **Account**: `ownerUserId` **убран из Create-body** (derive из caller; передача → sync `INVALID_ARGUMENT`); удалены AS-IS required-branch + anti-hijack-branch (`create_test.go::TestCreate_Sync_RequireOwner` переписывается на reject-in-body); `CreateAccountMetadata` получает `default_project_id` (append-only tag).
- [ ] **Project**: `accountId` immutable (из mask known-set исключён, immutable-reject); **удалён stale Move-упоминание** из `project.proto` message-doc (Move RPC отсутствует — привести doc к реальности; doc-truthfulness).
- [ ] **Role**: wire-проекция `definitionTier{tierType,tierId}` над типизированными FK+CHECK (CHECK переименован `roles_scope_xor`→`roles_definition_tier_xor` новой миграцией); `isSystem°` — derived (не хранимый bool на wire); compiled `permissions` — только Internal `GetRoleCompiled`; canonical catalog viewer/editor/admin/owner + `effectiveVerbs°`/`verbNotes` (editor `delete*`); `resource_version` xmin-токен **снят с wire** (OCC чисто server-side).
- [ ] **AccessBinding**: `resource_type`/`resource_id` → `scopeType`(dotted)/`scopeId`; `target` **REINTRODUCED REQUIRED** (`ResourceRef{type,id}` — **новые tag'и**, tags 16/18 tombstone НЕ переиспользуются); **новый `:revoke` action** (soft, replays emitted-ledger); UNIQUE → **partial `WHERE status='ACTIVE'`** (новая миграция); 3 sync-гейта (scope-XOR/IsRoleAssignable/RoleCoversType) первыми стейтментами; legacy `ListByScope`/`ListBySubject`/`ListByRole`/`ListByAccount` → единый `List`+whitelist.
- [ ] **Не** редактировать применённые миграции — только новые (ban #5). Новые CHECK/partial-UNIQUE/FK — на DB-уровне (ban #10), не software check-then-act.

**Проектные гейты (финальная верификация):**
- [ ] `go test ./... -race` · `golangci-lint run` · `govulncheck` зелёные. Цели `audit-list-filter`
      у iam **нет** — гейт объявлен в `services/{compute,nlb,storage,vpc}`; iam-фильтр
      (`internal/authzfilter`) проверяется go-тестами.
- [ ] `make -C gateway permission-catalog-check` byte-identical (iam-seed ↔ gateway-middleware) после regen под новые Role-verbs/catalog; newman зелёные (все `IAM-1-NN`).
- [ ] Ревью ролями: `proto-api-reviewer` (target-reintroduce tags, definitionTier, scope-rename, buf breaking); `db-architect-reviewer` (partial-UNIQUE WHERE ACTIVE, CHECK-XOR, FK RESTRICT, saga writer-tx atomicity, CAS-backstop); `system-design-reviewer` (Create-сага dual-write, EC-материализация, ban #9).

**MERGE-GATE (`[PHASE-0-GATED]` — жёсткий блокер, единственная кросс-фазовая зависимость):**
- [ ] **IAM-1 НЕ мёржится, пока Phase-0 governance change-set не приземлит** (unified §9 MUST-close ДО Phase-0):
  - **B1** — `ResourceRef{type,id}` в `kacho.cloud.common.v1` (3-way ref-naming). Блокирует `AccessBinding.target` proto-работу (F8: IAM-1-21/22/23). До landing target-nested-message не существует.
  - **B3** — id-prefix hyphen-форма (`acc-`/`prj-`/`rol-`/`acb-`) в `corevalidate` prefix→type-router. Блокирует scopeType/tierType вывод-по-prefix (F4 IAM-1-12, F7 IAM-1-18) и hyphen-id system-ролей (F6 IAM-1-17). До landing — `scopeType`/`tierType` **обязательны** на входе, id — текущая non-hyphen форма.
  - **B6** — `roleId` id-vs-dotted-name seam. Влияет на форму ссылки на роль в grant/catalog (F6 IAM-1-17).
  - **by-lane reason-token таблица** в `api-conventions.md` (conv-11 PROPOSED). `reason`-детали в `google.rpc.Status.details` (F8 IAM-1-24, F9 IAM-1-25) приземляются после. **Коды и тексты** ошибок — ungated (строятся в IAM-1 без ожидания).
- [ ] Ungated части (derive-ownerUserId, Create-сага+defaultProjectId, accountId-immutable, definitionTier-rename с ОБЯЗАТЕЛЬНЫМ tierType, permissions-internal, canonical-catalog+effectiveVerbs, target-REQUIRED-семантика с явным scopeType, Delete-hard/`:revoke`-soft, partial-UNIQUE, 3 sync-гейта коды+тексты, INTERNAL-opaque) строятся в IAM-1 **без** ожидания Phase-0.

---

## Changelog — что этот док покрывает

- **F1** `ownerUserId°` derived-from-caller, reject-in-body (AS-IS: required+anti-hijack → inverted), immutable-в-Update (IAM-1-01..03).
- **F2** one-shot Create-сага: default Project + owner-binding(deletionProtection=true), `metadata` несёт `accountId`+`defaultProjectId` (AS-IS: metadata только account_id); Delete-non-empty RESTRICT (IAM-1-04..06).
- **F3** `Project.accountId` immutable (Move удалён — AS-IS: stale message-doc, нет Move RPC); UNIQUE(accountId,name) per-account (IAM-1-07..09).
- **F4** `definitionTier{tierType,tierId}` dotted (AS-IS: flat cluster/account/project FK + «scope»-CHECK); `isSystem°` derived; XOR-negative; prefix-derivation `[PHASE-0-GATED B3]` (IAM-1-10..12).
- **F5** compiled `permissions[]` только Internal `GetRoleCompiled`; public `Get`/`List` field-absence; input-reject (AS-IS: deprecated+empty+reject) (IAM-1-13..14).
- **F6** canonical system-catalog viewer→editor→admin→owner first-in-order + honest `effectiveVerbs°` (editor `delete*`); seed immutable; hyphen-id `[PHASE-0-GATED B3]` (AS-IS: 2 opaque-id роли) (IAM-1-15..17).
- **F7** scope-anchor rename `resourceType/Id`→`scopeType/scopeId` («resource» → target); dotted+immutable; scopeType-derivation `[PHASE-0-GATED B3]` (AS-IS: resource_type/id deprecated + scope_ref{tier enum,id}) (IAM-1-18..20).
- **F8** `target` **REQUIRED** `ResourceRef{type,id}` closed-table `[PHASE-0-GATED B1]` (AS-IS: target TOMBSTONED tags16/18 → reintroduced новыми tag'ами); no-target→INVALID_ARGUMENT; RoleCoversType-гейт (IAM-1-21..24).
- **F9** 3 sync структурных гейта (scope-XOR/IsRoleAssignable/RoleCoversType) первыми стейтментами, actionable-текст; `reason`-token `[PHASE-0-GATED]` (IAM-1-25..26).
- **F10** `Delete`=hard(Get→404, AS-IS уже hard) / **новый `:revoke`**=soft(REVOKED,retention,replay-ledger); re-grant→новая ACTIVE-строка (partial UNIQUE WHERE ACTIVE, AS-IS: полный UNIQUE); deletion_protection CAS (IAM-1-27..30).
- **F11** EC: `Operation.done`=durability≠tuple-visibility, bounded-retry, ban #9; List format-validate до authz + whitelist-filter (AS-IS: legacy ListBy* → List); INTERNAL-opaque (IAM-1-31..33).

Покрытие обязательного минимума (task): ownerUserId derive+reject ✓ (IAM-1-01/02) · Create-сага metadata два-id ✓ (IAM-1-04) · accountId immutable/Move-removed ✓ (IAM-1-08) · definitionTier ✓ (IAM-1-10) · permissions-internal ✓ (IAM-1-13) · canonical-catalog+delete* ✓ (IAM-1-15) · scope-anchor rename ✓ (IAM-1-18) · target REQUIRED+ResourceRef ✓ (IAM-1-21/22) · Delete-hard/`:revoke`-soft ✓ (IAM-1-27/28). Каждая фича — positive + ≥1 negative + edge.

## Open questions для reviewer

1. **`:revoke` семантика vs AS-IS hard-Delete.** AS-IS `Delete` уже физический (row-removal + tuple-снятие). Redesign добавляет `:revoke` (soft). Вопрос: нужен ли в IAM-1 **отдельный** `AccessBindingService.Revoke` RPC (`…:revoke` → Operation), или revoke можно отложить в follow-up, оставив в IAM-1 только rename/target/scope? Предлагаю **включить** (product-parity «Delete=hard / :revoke=soft» — spine всего продукта), но подтвердите приоритет.
2. **partial-UNIQUE `WHERE status='ACTIVE'` включает `target`.** Ключ UNIQUE = `(subject-set, role, scopeType+scopeId, target)`. `target` — oneof (`resources[]`/`allInScope`/`selector`). Как канонизировать `target` в UNIQUE-ключе (hash oneof? отдельная колонка `target_digest`)? Это DB-архитектурный вопрос (db-architect-reviewer), но контракт «идентичный Create при ACTIVE → ALREADY_EXISTS» (IAM-1-29) требует детерминированной канонизации. Достаточно ли зафиксировать контракт на уровне acceptance и оставить механику db-review?
3. **`SubjectType.EMAIL` в IAM-1.** Вынес материализацию grant-by-email (invitation-mint, B15) в IAM-3. Но `subjects[].type` — закрытый enum: включать ли `EMAIL` **значение** в enum уже в IAM-1 (proto), reject'ая его на use-case-уровне до IAM-3, или добавлять enum-значение позже? Предлагаю: enum-значение вводится в IAM-3 (append-only), IAM-1 покрывает USER/SERVICE_ACCOUNT/GROUP. Ок?
4. **`isSystem°` derived vs AS-IS хранимый bool.** Redesign делает `isSystem` derived (`tierType==iam.cluster`). AS-IS — хранимая колонка + seed. Делать derived-on-read (не хранить) или оставить хранимую колонку как denorm с CHECK-инвариантом `is_system == (tier==cluster)`? Влияет на миграцию (db-review). Контракт-наблюдаемо одинаков; предлагаю derived-on-read, но подтвердите.
5. **Область F9 sync-гейтов vs `validateOnly`.** Вынес полный `validateOnly` blast-radius echo в follow-up, оставив в IAM-1 3 sync-гейта (substance). Достаточно ли для IAM-1, или reviewer хочет минимальный `validateOnly:true` dry-run (без мутации, эхо резолвнутых значений) уже здесь?
