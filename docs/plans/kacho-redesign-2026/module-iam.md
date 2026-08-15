# kacho-iam — целевой tenant-facing дизайн (2026, эталон-форма compute)

IAM — **платформенная identity+authz-плоскость** одного продукта Kachō. Форма resource'ов, async-модель, reference-law, two-projection и тон ошибок — **те же**, что у compute; отличается только домен. IAM — единственный владелец дерева аренды (`Account→Project`) и единственный источник грантов (`AccessBinding`); authz-решение он **материализует**, а не хранит-и-опрашивает. Bootstrap-цепочка «с нуля до первого пользователя» **не покидает контракт Kachō** — OIDC-вход, приглашения и обмен SA-credential на Bearer выставлены как IAM-фасады (внешний IdP/authorization-server работает под капотом, а не на поверхности).

## Ментальная модель

Пять опор, у каждой ровно один источник истины.

1. **Дерево аренды: `Account → Project → ресурсы` (строго два уровня, без вложенности).** Источник истины — `kacho_iam` (Account/Project — own-table, same-DB FK). Project — **leaf-workspace под Account, не folder** (иерархия не углубляется). Все прочие домены ссылаются на `projectId`/`accountId` как на **scope-координату** (class-B, peer-validate `ProjectService.Get`, hard-fail). Account — top-level (personal или под optional org-обёрткой B2B — **вне текущего scope**, tier не вводится). IAM **не** placement-scoped: identity-плоскость глобальна, `placementType`/`zoneId`/`regionId` к её ресурсам неприменимы by construction (осознанное исключение из coherence-инварианта).

2. **Субъекты ≠ гранты.** Субъект (`User` | `ServiceAccount` | `Group`) — «кто»; грант (`Role` ⨝ `AccessBinding`) — «что можно». Источник истины гранта — **`AccessBinding` (единственная grant-запись)**; `Role` — переиспользуемый allow-only verb-bundle (`rules[]`), сам по себе доступа не даёт. Разведены by design: роль не знает о target'е, binding не знает о verb'ах. **`AccessBinding` читается как RBAC-сужение**: `scopeType`≈namespace (где грант живёт), `target`≈resourceNames-within-scope (какие объекты под anchor'ом получают verb'ы). Слово **«scope» зарезервировано за ОДНИМ смыслом** — anchor у `AccessBinding` (`scopeType`/`scopeId`); tier определения роли называется **`definitionTier` (`tierType`/`tierId`)** — слово «scope» на роли не появляется даже во внутренних полях; третьего «scope» (discovery-`scopeGroup`) больше нет.

3. **Authz материализуется, не резолвится на request-path.** OpenFGA **flat Contract-A**: CRUD-relations — DIRECT usersets per-object, без каскада `from project|account`. Источник истины — `AccessBinding` → reconciler → FGA-tuples. Модель **eventually-consistent**: `Operation.done` = binding DURABLE, owner/grant-tuple виден в ограниченном окне. `«создал грант → сразу проверяю доступ»` — через **bounded client-retry** (first-class SDK-helper `retry_until_authorized`, стабильный `Retry-After`-hint отличает transient-окно от genuine deny — copy-paste snippet в quickstart-рецептах), НЕ серверный confirm-барьер (ban #9, phantom). EC-видимость downstream-эффекта — свойство **shared Operation-envelope всех модулей**, не IAM-only поле на конверте.

4. **User — зеркало внешнего IdP; ServiceAccount — IAM-native; и вход, и приглашение — на поверхности.** Источник истины идентити user'а — внешний IdP (`external_id`=`sub`); локально это output-mirror (нет публичного `Create`, IdP-поля read-only). **User глобален — у него НЕТ `accountId` by design** (членство выводится структурно через `Group`/`AccessBinding`/`UserInvitation`, отдаётся `AccountService.ListMembers`). **Субъект обязан завершить OIDC-login (материализоваться как `User`) ПРЕЖДЕ чем его грант активируется** — но day-one-админ начинает **с контракта Kachō**: `AuthService` (`:login`→`:callback`→`:tokenExchange`) — IAM-фасад входа (внешний IdP под капотом), а команду можно **пред-провижнить `UserInvitation` по email ДО первого входа**. `ServiceAccount` — своя запись (полный CRUD), Bearer выдаётся **IAM-фасадом** `OAuthClient:token` **синхронно** (external authorization-server под капотом), путь к пригодному токену — один round-trip.

5. **Two-projection.** Public-поверхность = намерение + результат (id/name/labels/scope/status). **Internal\* :9091** = authz-топология и инфра-чувствительное: FGA-tuples, compiled `permissions`, `external_id`↔subject-mapping, JWKS-signing-status, `RegisterResource`/`Check`. Скомпрометированный public API не должен раскрыть «кто на что имеет доступ» и физику подписи. **`ForceLogout` (hard-cutoff SA)** — НЕ инфра-топология, поэтому выставлен и на public (object-scoped на владельца SA), и не нарушает two-projection.

**Reference-law в IAM** (единообразие закона по СЕМАНТИЧЕСКОМУ КЛАССУ, не по wire-форме):
- **A. within-service** (цель в `kacho_iam`) → flat `<x>Id` + **DB FK**: `Project.accountId`(RESTRICT), `ServiceAccount.accountId`(RESTRICT), `Role.definitionTier`(типизированные nullable FK `accountId`/`projectId`/`clusterId` + CHECK-XOR внутри БД), `AccessBinding.roleId`(RESTRICT).
- **B. scope-координата** → flat dotted-type + id, кормит authz-scope: `AccessBinding.scopeType`/`scopeId` (якорь `iam.account|iam.project|iam.cluster`), `subjects[].id` (полиморфный within-DB soft-ref на user/sa/group — FK невозможен через alternation, страхуется триггером existence).
- **C. dependency-указатель на чужой owned-ресурс** (graceful-dangling, polymorphic) → `Referrer{type,id,name°}`: `AccessBinding.target.resources[]` (compute/vpc/registry-объект — opaque soft-ref, IAM владельца НЕ зовёт: ребро `iam→compute` = цикл). **`ServiceAccount.defaultProjectId` — А (within-DB FK, informational-контекст, НЕ authz).** **`Instance.serviceAccountId` (compute→iam) — класс C, НЕ B**: SA — identity-ЗАВИСИМОСТЬ (чужой owned-ресурс), а не tenancy/placement-ось; Instance держит его как `Referrer{type:"iam.service_account",id,name°}` graceful-dangling (при удалении SA инстанс деградирует, не hard-fail; IAM синхронно не зовётся — ацикличность усилена). Dangling переживается (binding виден, tuple снят reconciler'ом).

**Type-registry (единый, dotted).** `scopeType`, `definitionTier.tierType`, `target.resources[].type`, `ListGrantableResources.type`, `PermissionCatalog.modules[].resources[]` используют **один** dotted-namespaced реестр (`iam.project`, `compute.instance`, `registry.repository`). **Инвариант:** любой inline-фрагмент, отданный discovery-каталогом (роль **вместе** с полной grant-координатой `scopeType`+`scopeId` и suggested-target), byte-paste-совместим в поле-цель. **id-prefix кодирует тип** (`prj-`⇒`iam.project`, `acc-`⇒`iam.account`) → для iam-anchor'ов `scopeType` выводим из `scopeId`, задавать необязательно.

---

## Account

Top-level арендатор. `acc`-prefix. Owner-table `kacho_iam.accounts`. UNIQUE(name) **глобально**.

```jsonc
{
  "id": "acc-7fq2m8k3rd0xw",        // ° id (acc + crockford-base32)
  "ownerUserId": "usr-9kd4b1",      // ° DERIVED из аутентифицированного caller при Create; °-mirror субъекта owner-AccessBinding (единый источник ownership). НЕ принимается в Create body
  "name": "acme-prod",              // ^[a-z][-a-z0-9]{2,62}$; UNIQUE globally; LIVE-mutable
  "description": "Acme production tenant",   // <=256; LIVE-mutable
  "labels": { "tier": "gold", "cost-center": "eng" },  // <=64 pairs; LIVE-mutable; делает Account label-selectable
  "status": "ACTIVE",               // ° single-state {ACTIVE:"Active"} — нет provisioning
  "createdAt": "2026-07-19T10:22:04Z"   // ° truncate-to-seconds
}
```

**Bootstrap ownership.** Первый админ материализуется как `User` через **`AuthService`-вход (OIDC под капотом) ДО** `Account.Create` (публичного User.Create нет by design). `Account.Create` делает **этого аутентифицированного caller'а** владельцем автоматически — `ownerUserId` НЕ задаётся клиентом; передача его в body → `InvalidArgument "Illegal argument ownerUserId (derived from caller)"` первым стейтментом. Значение `ownerUserId` — output-only зеркало субъекта owner-AccessBinding (ownership живёт в binding'е, не дублируется).

**One-shot Create-сага** (одна `Operation`): `Account.Create` в одной writer-tx co-commit'ит (a) default `Project` (name `"default"`), (b) **owner-`AccessBinding`** (subject=caller, role=`owner`, scope=`iam.account`, `deletionProtection=true`). `Operation.metadata` несёт **и `accountId`, и `defaultProjectId`** сразу (не заставляем List'ить дефолт-проект); per-object owner-доступ материализуется forward-reconciler'ом (bounded-retry на клиенте покрывает окно).

**`AccountService.ListMembers`** (sync people-roster) — **канонический ответ «кто в моём аккаунте?»** (см. quickstart): derived-проекция субъектов, имеющих binding/membership под аккаунтом (`User` под капотом остаётся tenancy-agnostic — roster собирается по binding/group-membership, а не по account-FK на User). Поддерживает фильтр `type=`/`via=`:
```jsonc
{ "members": [
  { "type": "USER", "id": "usr-9kd4b1", "name": "ann@acme.io", "via": "GROUP:grp-platform-eng", "lastSeenAt": "2026-07-19T12:00:00Z" },
  { "type": "SERVICE_ACCOUNT", "id": "sva-ci-deployer", "name": "ci-deployer", "via": "ACCESS_BINDING:acb-5k2m9x", "lastSeenAt": null },
  { "type": "USER", "id": "", "name": "bob@acme.io", "via": "INVITATION:inv-7k2m9", "lastSeenAt": null }  // pending-invite виден как заготовка
]}
```

**Delete** — async; RESTRICT-набор непуст (`projects`/`serviceAccounts`/`groups`/custom `roles`) → `FailedPrecondition "Account acc-7fq2m8k3rd0xw contains projects"`.

---

## Project

Leaf-workspace внутри Account (**один уровень, без вложенности**). `prj`-prefix. UNIQUE(accountId, name).

```jsonc
{
  "id": "prj-prod",                 // ° id
  "accountId": "acc-7fq2m8k3rd0xw", // A: FK → Account (RESTRICT); immutable after Create (Move удалён)
  "name": "prod",                   // ^[a-z][-a-z0-9]{2,62}$; UNIQUE(accountId,name); LIVE-mutable
  "description": "Production workloads",   // <=256; LIVE-mutable
  "labels": { "env": "prod" },      // LIVE-mutable; label-selectable
  "status": "ACTIVE",               // ° single-state
  "createdAt": "2026-07-19T10:22:05Z"   // °
}
```

`accountId` immutable — cross-account перенос запрещён (нет hierarchy-down в scope-модели). Downstream (`vpc`/`compute`/`nlb`/`storage`) держат `projectId` как class-B координату и валидируют `ProjectService.Get` fail-closed.

---

## User

Output-mirror внешнего IdP. `usr`-prefix. **Нет публичного Create** (только `AuthService`-callback / `InternalUserService.UpsertFromIdentity`). **User НЕ несёт `accountId` — это by design: он глобальное IdP-зеркало (человек может состоять в N аккаунтах). Членство в аренде выводится структурно (`Group`-membership / `AccessBinding` / `UserInvitation`) и перечисляется `AccountService.ListMembers`** — не ищи «пользователей аккаунта» на самом User'е.

```jsonc
{
  "id": "usr-9kd4b1",               // ° id
  "externalId": "z9c-8f2a-1d",      // ° UNIQUE — IdP `sub`; read-only (mirror)
  "email": "ann@acme.io",           // ° IdP-mirror; indexed lower(email); read-only; резолвится в Resolve / List?filter=email=
  "displayName": "Ann Rand",        // ° IdP-mirror; read-only
  "labels": { "team": "platform" }, // ЕДИНСТВЕННОЕ tenant-mutable поле; LIVE-mutable → label-selectable
  "accounts": [                     // ° DERIVED read-only: аккаунты, где субъект имеет binding/membership (сигнпост «где живёт человек»); output-only, не вход
    { "accountId": "acc-7fq2m8k3rd0xw", "via": "GROUP:grp-platform-eng" }
  ],
  "createdAt": "2026-07-19T10:20:00Z"   // ° (первый успешный OIDC-login)
}
```

**Tenancy выводится структурно** (поле `tenancy` упразднено — оно несло 0 бит per-instance: User всегда «глобален», SA/Group всегда account-scoped). «Глобальность» User = отсутствие `accountId`, факт самоописательный; принадлежность к аккаунтам видна в derived `accounts°` и через `ListMembers`.

**Update** — только `labels` через `updateMask`. Любое IdP-mirror поле в маске → `InvalidArgument "externalId is read-only (User is an external identity-provider mirror)"` (mirror-специфичный **человекочитаемый** тон — публичного `User.Create` нет, шаблон `"… after User.Create"` цитировал бы недоступный verb). **gRPC-код тот же** (`INVALID_ARGUMENT`) и `status.details` несёт **стабильный** `{reason:"FIELD_IMMUTABLE", field:"externalId"}` идентичной формы с универсальным immutable-кейсом — cross-module matcher'ы кеятся на программную форму, не на строку (declared-exception, см. Правило 12). Immutable-switch — ДО `UpdateMask`.

**Резолв коллеги — `UserService.Resolve(email)`** (sync, три исхода, различимо): залогинен → `User`; есть `UserInvitation` (PENDING) → `FAILED_PRECONDITION "user bob@acme.io has not completed login"`; ни того ни другого → `NOT_FOUND "user bob@acme.io not found"`. Это устраняет двусмысленность «пустой List ≡ опечатка vs ещё-не-вошёл». **List = `viewer ∪ v_list`** с whitelist-фильтром `name=`/`email=`: anonymous→empty, FGA error→`Unavailable` (fail-closed, никогда unfiltered-leak), self-floor (видит себя через self-tuple), admin/owner — через viewer-tier. `Get == List`-resolver (no existence-oracle).

---

## UserInvitation

Пред-провижн субъекта по email **до** его первого входа (recognizable invite-primitive; НЕ добавляет публичный `User.Create` — mirror цел). `inv`-prefix. Материализуется в реальный `usr-*` и **активирует вложенный грант** при первом OIDC-login приглашённого. **Часто чеканится прозрачно** grant-by-email фасадом (см. AccessBinding) — оператору не обязательно знать login-state коллеги заранее.

```jsonc
{
  "id": "inv-7k2m9",                // ° id
  "accountId": "acc-7fq2m8k3rd0xw", // A: FK → Account (RESTRICT); immutable
  "email": "bob@acme.io",           // lower(email); UNIQUE(accountId, lower(email)) WHERE status='PENDING'
  "grant": {                        // OPTIONAL вложенный AccessBinding-spec — активируется атомарно при accept
    "roleId": "rol-editor",         //   (subject подставляется = материализованный usr-*)
    "scopeId": "prj-prod",          //   scopeType выводится из prefix (prj-⇒iam.project); задавать необязательно
    "target": { "allInScope": {} }
  },
  "status": "PENDING",              // ° PENDING → ACCEPTED(terminal) | EXPIRED | REVOKED
  "invitedByUserId": "usr-9kd4b1",  // ° audit
  "materializedUserId": "",         // ° set на accept (id созданного User)
  "expiresAt": "2026-08-19T00:00:00Z",  // TTL приглашения (invite-lifetime, НЕ grant-TTL); set at Create, immutable
  "createdAt": "2026-07-19T10:30:00Z"   // °
}
```

**Accept — не публичный RPC, а side-effect входа.** Первый успешный OIDC-login с `email`, совпавшим с PENDING-инвайтом, в одной writer-tx: (a) upsert `User` (mirror), (b) `status→ACCEPTED` + `materializedUserId`, (c) если `grant` задан — co-commit реальный `AccessBinding` (subject = новый `usr-*`) + intent FGA-tuple. Правило «грант активен только после материализации User» соблюдено by construction. **Create/Delete/List** — публичны; повторный invite на тот же email при PENDING → `AlreadyExists`.

---

## ServiceAccount

IAM-native machine-identity, account-scoped + informational `defaultProjectId`. `sva`-prefix.

```jsonc
{
  "id": "sva-ci-deployer",          // ° id
  "accountId": "acc-7fq2m8k3rd0xw", // A: FK → Account (RESTRICT); immutable
  "defaultProjectId": "prj-prod",   // A: FK → Project (RESTRICT); optional; must ∈ accountId.
                                    //   DEFAULT UI/CLI CONTEXT ONLY — НЕ ограничивает доступ. Доступ SA определяется ЦЕЛИКОМ его AccessBinding'ами.
                                    //   (Переименовано из projectId: имя projectId на identity-ресурсе ложно предсказывало scoping — здесь это НЕ scope-координата.)
  "name": "ci-deployer",            // ^[a-z][-a-z0-9]{2,62}$; UNIQUE(accountId,name)
  "description": "GitHub Actions deploy identity",
  "labels": { "system": "ci" },     // LIVE-mutable; label-selectable
  "status": "ACTIVE",               // ° ЕДИНАЯ liveness-ось {ACTIVE:"Active", DISABLED:"Disabled"}
  "createdAt": "2026-07-19T11:00:00Z"   // °
}
```

**`defaultProjectId` — informational default-context**, НЕ authz-констрейнт: задаёт дефолтный проект для UI/CLI-удобства, не сужает и не расширяет права (наивный «scoped робот» через это поле не защищён — узость даётся ролью/target'ом гранта, а не именем поля).

**Единая liveness-ось — `status`** (булев `enabled` упразднён; дискриминатор `tenancy` упразднён — SA всегда account-scoped by construction). `status=DISABLED` **отклоняет новые токен-обмены**; уже выданные Bearer'ы живут до `exp`. Disable — это `Update status→DISABLED` (**STATE-toggle**, не Delete).

**Bootstrap-сага робота (опционально, одна Operation).** `ServiceAccount.Create` может в одной writer-tx co-commit'ить (a) сам SA, (b) `OAuthClient` (credentials, `createOAuthClient:true`), (c) опционально initial `AccessBinding` — зеркалит `Account.Create`/`Group.Create`-саги. **Grant в саге принимает ЛИБО `roleId` существующей роли, ЛИБО inline `rules[]`-spec** (least-priv роль со-авторится + назначается в той же writer-tx, НЕ обязана pre-существовать) — самый частый флоу «завести least-priv робота» (напр. registry-pull) не схлопывается в отдельный Role.Create+poll:
```jsonc
// один вызов → least-priv registry-puller робот с пригодным Bearer:
POST /iam/v1/serviceAccounts {
  "name": "ci-puller", "createOAuthClient": true,
  "grant": { "scopeId": "prj-prod", "target": { "allInScope": {} },
             "roleId": "rol-registry-puller" }        // canned narrow system-role (см. system-catalog) …
             // …ИЛИ inline: "rules": [{ "module":"registry", "resources":["repository"], "verbs":["get","list"] }]
}
```
`Operation.metadata` несёт `serviceAccountId`+`oauthClientId` сразу; one-time `clientSecret°` едет в `Operation.response` терминального полла. Гранулярные RPC (`OAuthClientService.Create` и т.д.) остаются для advanced-кейсов.

**Два рычага отзыва** (оба tenant-facing): (1) `status→DISABLED` — мягкий (блокирует НОВЫЙ токен-обмен; живые Bearer'ы доживают до `exp` + JWKS-cache TTL); (2) **`ServiceAccountService:forceLogout`** — **hard-cutoff** (public, object-scoped authz на владельца SA), немедленно инвалидирует активные Bearer'ы. Скомпрометированный CI-secret отзывается **со своей поверхности сразу**, не только через Internal\*.

---

## Group

Account-scoped коллекция субъектов для пакетной раздачи прав. `grp`-prefix. Membership — полиморфная (user/service_account), без FK, страхуется триггером existence.

```jsonc
{
  "id": "grp-platform-eng",         // ° id
  "accountId": "acc-7fq2m8k3rd0xw", // A: FK → Account (RESTRICT); immutable (tenancy account-scoped by construction — дискриминатор-поля нет)
  "name": "platform-eng",           // UNIQUE(accountId,name)
  "description": "Platform engineering",
  "labels": { "dept": "eng" },      // LIVE-mutable; label-selectable
  "memberCount": 12,                // ° derived
  "status": "ACTIVE",               // °
  "createdAt": "2026-07-19T09:00:00Z"   // °
}
```

**Member** (sub-запись; discovery через `ListMembers`):
```jsonc
{ "type": "USER", "id": "usr-9kd4b1", "name°": "ann@acme.io", "addedAt°": "2026-07-19T09:05:00Z" }
```

**One-shot Create** принимает `memberSpecs[]` — группа с начальным составом одной `Operation`. `AddMember`/`RemoveMember` идемпотентны (PK на `(group,type,id)`), **co-commit'ят FGA member-tuple** `group:<gid>#member@<user|service_account>:<id>` в той же writer-tx (иначе group-subject binding не резолвит членов). Тип объекта FGA-tuple = `group` (userset-тип, на который ссылается binding), не `iam_group` (hierarchy-тип). Verb-эквивалент `:addMember`/`:removeMember` в role-политике сворачивается в `update` (см. PermissionCatalog collapse-mapping).

---

## Role

Переиспользуемый allow-only verb-bundle. `rol`-prefix. **`definitionTier`** — dotted-tier, где роль определена/назначаема (XOR: ровно один валидный anchor), тем же словарём, что `AccessBinding.scope` (byte-paste tier-значений), **но под своим noun'ом `tierType`/`tierId` — «scope» на роли не появляется ни в прозе, ни в полях** (инвариант «scope = ровно anchor binding'а» держится). **Публичная поверхность — `rules[]`**; compiled-проекция (`permissions[]`, форма `M.R.rn.V`) на public API **не выставляется** — только Internal\* `GetRoleCompiled` (:9091, two-projection).

```jsonc
{
  "id": "rol-3m2k9c",               // ° id (system-роли — детерминированный id, напр. rol-editor)
  "definitionTier": {               // A(wire-проекция): dotted tier определения роли; словарь значений общий с AccessBinding.scope
    "tierType": "iam.account",      //   {iam.cluster|iam.account|iam.project}; репо хранит типизированные nullable FK accountId/projectId/clusterId + CHECK-XOR
    "tierId": "acc-7fq2m8k3rd0xw"   //   (iam.cluster-роли: tierId = кластер-id). Поля НЕ называются scope* — «scope» зарезервирован за anchor'ом binding'а
  },
  "name": "app-deployer",           // custom: ^[a-z][-a-z0-9]*(\.[a-z][a-z0-9_]*){0,2}$; UNIQUE per definitionTier
  "description": "Deploy + read compute/vpc in prod",
  "rules": [                        // AUTHORED policy (единственная public-surface); <=64 rules
    {
      "module": "compute",          // ровно ОДИН модуль на правило (несколько модулей = несколько rules)
      "resources": ["instance", "disk"],   // 1..16 из type-registry
      "verbs": ["get", "list", "create", "update"],  // closed-set {get,list,create,update,delete} (+ promoted first-class verbs каталога, напр. compute "start"/"stop")
      "selector": { "matchLabels": { "env": "prod" } }  // XOR resourceNames[]; label-driven object-selector (reconciler). Имя selector — НЕ коллизит с Role.labels
    },
    { "module": "vpc", "resources": ["subnet"], "verbs": ["get", "list"] },
    { "module": "registry", "resources": ["repository"], "verbs": ["get", "list", "create", "update"] }
    // registry docker-семантика: pull ≡ {get}(blob) / {get,list}(с tag-enum), push ≡ {create,update} — см. PermissionCatalog collapse-mapping
  ],
  "isSystem": false,                // ° DERIVED = (definitionTier.tierType == "iam.cluster"); не хранимый provenance-флаг
  "labels": { "catalog": "app" },   // own-resource labels (≠ rules[].selector.matchLabels); LIVE-mutable
  "createdByUserId": "usr-9kd4b1",  // °
  "createdAt": "2026-07-19T11:10:00Z",  // °
  "updatedAt": "2026-07-19T11:10:00Z"   // °
}
```

**`isSystem` — производное** (`definitionTier.tierType=='iam.cluster'`), не хранимый флаг: cluster-tier ⇔ system. Seed-роли неизменяемы (`Update`/`Delete` → `FailedPrecondition`).

### Канонический system-role catalog (фиксированный, tenant-wide, first-class)

Cluster-scoped (`definitionTier.tierType='iam.cluster'`, `isSystem:true`) роли — **опубликованный набор**, из которого арендатор выбирает (не читая `rules[]` вручную). Возвращаются **первыми и в этом порядке** из `RoleService.List`, назначаемы на любой совместимый anchor. **`effectiveVerbs[]` отражает co-материализованный набор** (не только authored — иначе least-privilege-прогноз врал бы):

```jsonc
{ "systemRoles": [
  { "roleId": "rol-viewer", "name": "viewer", "displayName": "Viewer",
    "purpose": "Read-only across all modules in scope",
    "authoredVerbs": ["get","list"], "effectiveVerbs": ["get","list"] },
  { "roleId": "rol-editor", "name": "editor", "displayName": "Editor",
    "purpose": "Read + create/update + co-materialized delete on in-scope leaf objects",
    "authoredVerbs": ["get","list","create","update"],
    // ЧЕСТНЫЙ эффективный набор: delete* со-материализуется на leaf-объектах scope'а (НЕ на account/project-anchor'е):
    "effectiveVerbs": ["get","list","create","update","delete*"],
    "verbNotes": { "delete*": "co-materialized on in-scope leaf objects, NOT on the account/project anchor itself" } },
  { "roleId": "rol-admin",  "name": "admin",  "displayName": "Admin",
    "purpose": "Full CRUD + manage access bindings in scope",
    "authoredVerbs": ["get","list","create","update","delete"], "effectiveVerbs": ["get","list","create","update","delete"] },
  { "roleId": "rol-owner",  "name": "owner",  "displayName": "Owner",
    "purpose": "Admin + deletion-protected tenancy ownership (bootstrap-assigned)",
    "authoredVerbs": ["get","list","create","update","delete","manage-bindings"],
    "effectiveVerbs": ["get","list","create","update","delete","manage-bindings"] }
], "narrowRoles": [
  // Canned per-module NARROW system-роли — first-class рядом с четвёркой, чтобы least-priv one-shot НЕ требовал авторинга роли:
  { "roleId": "rol-registry-puller", "name": "registry.puller", "displayName": "Registry Puller", "isSystem": true,
    "purpose": "Pull images (get/list on repositories) — no push",
    "authoredVerbs": ["get","list"], "effectiveVerbs": ["get","list"],
    "rulesPreview": [{ "module": "registry", "resources": ["repository","image"], "verbs": ["get","list"] }] },
  { "roleId": "rol-registry-pusher", "name": "registry.pusher", "displayName": "Registry Pusher", "isSystem": true,
    "purpose": "Push + pull (create/update/get/list on repositories)",
    "authoredVerbs": ["get","list","create","update"], "effectiveVerbs": ["get","list","create","update"],
    "rulesPreview": [{ "module": "registry", "resources": ["repository","image"], "verbs": ["get","list","create","update"] }] },
  { "roleId": "rol-compute-operator", "name": "compute.operator", "displayName": "Compute Operator", "isSystem": true,
    "purpose": "Operate instances (start/stop/restart) + read — no create/delete",
    "authoredVerbs": ["get","list","start","stop","restart"], "effectiveVerbs": ["get","list","start","stop","restart"],
    "rulesPreview": [{ "module": "compute", "resources": ["instance"], "verbs": ["get","list","start","stop","restart"] }] },
  { "roleId": "rol-vpc-viewer", "name": "vpc.viewer", "displayName": "VPC Viewer", "isSystem": true,
    "purpose": "Read-only VPC (network/subnet/security-group)",
    "authoredVerbs": ["get","list"], "effectiveVerbs": ["get","list"],
    "rulesPreview": [{ "module": "vpc", "resources": ["network","subnet","securityGroup"], "verbs": ["get","list"] }] }
]}
// «дай edit на этот проект» = lookup rol-editor; «least-priv pull-робот» = lookup rol-registry-puller — НЕ инспекция rules[], НЕ Role.Create.
```

**Verb-словарь — closed CRUD `{get,list,create,update,delete}` + promoted first-class verbs.** Data-plane/action-семантика сворачивается в CRUD по **опубликованному в PermissionCatalog collapse-mapping** (`pull→get[+list]`, `push→create+update`, каждый несёт готовый `rules`-фрагмент). Где модуль УЖЕ различает истинно-раздельное действие (compute `start`/`stop`/`restart`, key `rotate`) — каталог **промотирует** его в first-class closed-verb (симметрия collapse ↔ promote: не только action→CRUD, сужающий выразимость), с готовым `rules`-фрагментом. Эмуляция через CRUD не требуется.

**Wildcard-политика**: verb-`*` допустим в custom; module-`*`/resource-`*` — **system-only** (`InvalidArgument "wildcard '*' is system-only"`). **Update**: `rules`(+name/description/labels) mutable под **server-side OCC на `xmin`** (токен версии НЕ на wire — обычный read-modify-write; конкурент детектится внутри writer-tx) → `FailedPrecondition "role was modified concurrently, retry"`; смена `rules` реконсайлит FGA-tuples активных биндингов в той же writer-tx (ledger-diff, снимает orphan). `isSystem`-роль (derived cluster-tier) на Update/Delete → `FailedPrecondition`. **Delete** custom с активным binding → `FailedPrecondition "role is in use by active access bindings"` (FK RESTRICT, не TOCTOU).

---

## AccessBinding

Единственная grant-запись — **RBAC-сужение `resourceNames`-within-scope**: `subjects[] ↔ role ↔ scope-anchor (≈namespace) ↔ target (≈resourceNames)`. `acb`-prefix. UNIQUE(subject-set, role, scopeType+scopeId, target) **WHERE status='ACTIVE'** — идемпотентность Create + корректный re-grant после revoke. Ядро = **subjects+role+scope+target** (inline-`condition` CEL и grant-`expiresAt` вынесены в follow-up — не тянем самый тяжёлый ресурс до появления живого JIT/conditional-consumer'а).

```jsonc
{
  "id": "acb-5k2m9x",               // ° id
  "subjects": [                     // 1..32; multi-subject; per-subject НЕЗАВИСИМЫЙ tuple-set. type: {USER, SERVICE_ACCOUNT, GROUP, EMAIL}
    { "type": "USER",            "id": "usr-9kd4b1",       "name": "ann@acme.io" },       // ° name — Referrer echo
    { "type": "SERVICE_ACCOUNT", "id": "sva-ci-deployer",  "name": "ci-deployer" },       // робот-грант завязан на SA-токен
    { "type": "GROUP",           "id": "grp-platform-eng", "name": "platform-eng" },       // polymorphic subject (within-DB soft-ref)
    { "type": "EMAIL",           "email": "bob@acme.io" }  // grant-by-email: есть User → биндит usr-*; нет → прозрачно чеканит PENDING UserInvitation, несущий этот grant
  ],
  "roleId": "rol-editor",           // A: FK → Role (RESTRICT); immutable
  "scopeType": "iam.project",       // B: dotted anchor-тип (≈namespace) {iam.cluster|iam.account|iam.project}; OPTIONAL — выводится из scopeId prefix (prj-⇒iam.project); задаётся лишь для non-iam/дизамбигуации; immutable. ЕДИНСТВЕННЫЙ источник tier ("scope" = именно ЭТО)
  "scopeId": "prj-prod",            // B: anchor id (within-DB soft-ref в iam-иерархию); immutable
  "target": {                       // ОБЯЗАТЕЛЕН (oneof) — какие объекты под anchor'ом (≈resourceNames-within-scope) получают verb'ы роли
    "resources": [                  // C: per-object polymorphic Referrer, graceful-dangling
      { "type": "compute.instance", "id": "ins-abc", "name": "web-01" }   // name° — echo; id opaque soft-ref
    ]
    // "allInScope": {}             // ЯВНЫЙ opt-in: ВСЕ объекты под anchor'ом, включая будущие (нет sentinel-по-умолчанию); suggested-target у grantFragment = именно этот фрагмент
    // "selector": { "matchLabels": { "env": "prod" } }   // label-driven, reconciler-materialized (mutable арм)
  },
  "deletionProtection": false,      // LIVE-mutable guard (owner-auto-binding ставит true)
  "status": "ACTIVE",               // ° PENDING → ACTIVE → REVOKED(terminal via :revoke). Delete = ФИЗИЧЕСКОЕ удаление (Get→404); :revoke = soft-revoke с retention
  "grantedByUserId": "usr-9kd4b1",  // ° audit — кто выдал
  "revokedAt": null,                // ° set только при :revoke (не при Delete); при :revoke row удерживается для аудита
  "labels": { "ticket": "kac-812" },// LIVE-mutable; label-selectable
  "createdAt": "2026-07-19T11:20:00Z"   // °
}
```

**`target` ОБЯЗАТЕЛЕН** — least-privilege по умолчанию (SPINE). Create без `target` → sync `InvalidArgument "target is required; use target.allInScope{} to grant all objects under the anchor"`. Самый широкий грант (`allInScope`) достижим **только явным opt-in**. **Штатный путь собрать binding — grantFragment из `RoleService.List(assignableOn=...)`** (несёт готовые `{roleId, scopeType, scopeId, target.allInScope}` byte-paste-полно); raw hand-authored путь — исключение. Трение «две координаты (scope + target)» снято тремя рычагами: (1) grantFragment paste-полон; (2) `validateOnly` ВСЕГДА эхает blast-radius-строку (honest iam-vs-cross-module split, см. Rule 6) — взаимодействие anchor↔target наблюдаемо ДО commit; (3) `target` = узнаваемое RBAC-сужение (`scopeType`≈namespace, `target`≈resourceNames).

**Grant-by-email (`subject.type=EMAIL`, либо тонкий фасад `:grantToEmail`)** — намерение «дать `bob@acme.io` editor на prod» едино независимо от login-state: есть `User` → биндит `usr-*` напрямую; нет → прозрачно чеканит PENDING `UserInvitation`, несущий этот grant (активируется при первом входе Bob). Оператору **не нужно знать login-state коллеги заранее** — invitation становится implementation-detail.

**Три детерминированных структурных гейта — SYNC, ПЕРВЫМИ стейтментами RPC (как malformed-id), ДО минта Operation** (в pre-check без TOCTOU): (1) **scope-XOR/well-formedness** — `scopeId` резолвится в anchor, `scopeType` (если задан или выведен) — валидный tier; (2) **IsRoleAssignable** — `definitionTier` роли совместим с anchor'ом; (3) **RoleCoversType** — `target.resources[].type` покрыт `role.rules`. Mis → sync `FailedPrecondition` с **actionable-хвостом**: `"role rol-editor (definitionTier iam.account) is not assignable on iam.project:prj-prod; assign at iam.project or iam.account tier of this account"` **первым стейтментом** (не POST→poll). `Operation.error` зарезервирован **только для истинно async-фейлов** (FGA per-object tuple-эмиссия: 0 tuples после гейтов → `INTERNAL` fail-closed; downstream).

**Mutable-set = `{deletionProtection, labels}` + `selector`-арм** (через `ReplaceTargetSelector`, atomic full-replace, server-side OCC на `xmin`); любой иной путь (`roleId`/subject/`scopeType`/`scopeId`) → `InvalidArgument "<field> is immutable after AccessBinding.Create"`.

**Два исхода отзыва — различимая семантика (product-wide parity):**
- **`Delete` = ФИЗИЧЕСКОЕ удаление**, `Get→404` — **тот же смысл, что в compute/vpc/nlb/registry** (никакого IAM-специфичного soft-delete под именем Delete). `deletionProtection=true` → `FailedPrecondition "access binding acb-5k2m9x has deletion_protection enabled; clear it via Update before Delete"` + CAS-backstop.
- **`:revoke` (action-verb → Operation)** = soft-revoke с audit-retention: `status ACTIVE→REVOKED` (terminal), row + `revokedAt` + `grantedByUserId` **удерживаются**, реплеит persisted emitted-tuple-ledger (не ре-деривит из текущей роли → нет orphan при Role.Update между grant и revoke).
- **Re-grant после revoke** (задокументировано): UNIQUE — **partial `WHERE status='ACTIVE'`**, поэтому повторный идентичный `Create` после `:revoke` даёт **новую ACTIVE-строку** (REVOKED-строка слот не занимает) — НЕ `AlreadyExists`. Идентичный Create при уже-ACTIVE → `AlreadyExists` (идемпотентность).

---

## Quickstart-рецепты (from zero, на контракте Kachō)

**A. From zero → first User → first Account** (day-one админ, не покидая поверхность):
```
1. GET  /iam/v1/auth:login            → 302 к внешнему IdP (IAM-фасад; IdP под капотом)
2. GET  /iam/v1/auth:callback?code=…  → IAM обменивает code, upsert User (mirror), ставит session
3. POST /iam/v1/auth:tokenExchange    → Bearer Kachō (кладём в Authorization)
4. POST /iam/v1/accounts {name}       → Operation; metadata.accountId + metadata.defaultProjectId сразу
                                         (caller стал owner автоматически; owner-AccessBinding co-committed)
5. AccountService.ListMembers          → канонический «кто в моём аккаунте?» (people-roster)
```

**B. Пред-провижн команды до входа (grant-by-email, login-state-agnostic):**
```
POST /iam/v1/accessBindings { subjects:[{type:"EMAIL",email:"bob@acme.io"}], roleId:"rol-editor",
                              scopeId:"prj-prod", target:{allInScope:{}} }
→ есть User(bob) → биндит usr-* сразу; нет → прозрачно PENDING UserInvitation, несущий grant.
→ Bob делает auth:login впервые → User материализуется + грант активируется атомарно.
```

**C. From zero → least-priv CI-робот с пригодным Bearer** (одна сага + sync-обмен):
```
1. POST /iam/v1/serviceAccounts { name:"ci-puller", createOAuthClient:true,
     grant:{ roleId:"rol-registry-puller", scopeId:"prj-prod", target:{allInScope:{}} } }   // canned narrow role — без Role.Create
   → Operation; metadata.serviceAccountId + metadata.oauthClientId; response.clientSecret° (one-time)
2. POST /iam/v1/serviceAccounts/{svaId}/oauthClients/{id}:token  { }   // SYNC IAM-фасад обмена
   → 200 { accessToken°, expiresIn }   (external authorization-server под капотом; ОДИН round-trip, без poll)
3. docker login <registry-host> -u <clientId> -p <accessToken>        // токен пригоден как есть
```

**D. Read-your-writes (EC-окно) — first-class `retry_until_authorized`** (bounded client-retry, не серверный барьер; общий для всех модулей):
```
op = poll(create.operationId)                 // done ⇒ ресурс DURABLE
retry_until_authorized(                        // SDK-helper: budget ≈ 6–10s, stable Retry-After hint
  step  = () => GET /iam/v1/<res>/{op.metadata.id},
  until = r => r.status not in (403,404),      // owner-tuple ещё материализуется — НЕ genuine deny
  onBudgetExceeded = () => assert(false)       // fail-open по budget → реальный assert падает
)
```

---

## RPC surface

Все `Create/Update/Delete` и бо́льшая часть `:verb`-действий → `operation.Operation` (poll `GET /iam/v1/operations/{id}`); `Get/List/Get*Output/Resolve`/каталоги/**token-обмены** — sync. `id` доступен в `Operation.metadata` сразу (до `done`); EC-видимость downstream-эффекта покрывается **bounded client-retry** (свойство shared Operation-envelope — **никаких IAM-only полей на конверте**, `readReady`/`retryAfterMs` сняты; transient отличается стабильным `Retry-After`-hint на транспорте). Каждый RPC обоих листенеров несёт per-RPC authz (`InternalIAMService.Check` → FGA), object-scoped `scope_extractor` (target→project, anti-BOLA), fail-closed; транспорт mTLS (service→service) / TLS+JWT (user→edge). `validateOnly:true` — sync dry-run на любом мутирующем RPC.

**Public (`:9090`, external mux):**

| Service | Методы | Sync/Async | REST |
|---|---|---|---|
| `AuthService` | Login, Callback, TokenExchange | sync (redirect/exchange) | `GET /iam/v1/auth:login`, `GET /iam/v1/auth:callback`, `POST /iam/v1/auth:tokenExchange` — IAM-фасад OIDC (внешний IdP под капотом; **локального user-store нет**) |
| `AccountService` | Get, List, **ListMembers** (`type=`/`via=` filter) | sync | `GET /iam/v1/accounts[/{id}]`, `…/{id}:listMembers` |
| | Create, Update, Delete | async | `POST`/`PATCH`/`DELETE /iam/v1/accounts[/{id}]` |
| | ListOperations, ListAllOperations | sync | `GET …/{id}/operations`, `…:all` |
| `ProjectService` | Get, List / Create, Update, Delete | sync / async | `/iam/v1/projects…` (Move удалён — `accountId` immutable) |
| `UserService` | Get, List (`filter name=`,`email=`,label), **Resolve** / Update (labels-only), Delete | sync / async | `/iam/v1/users…`, `…:resolve` (нет Create — вход через AuthService) |
| `UserInvitationService` | Get, List / Create, Delete | sync / async | `/iam/v1/userInvitations…` (accept — side-effect первого входа, не RPC) |
| `ServiceAccountService` | Get, List / Create(+createOAuthClient,+grant `roleId`\|inline `rules[]` сага), Update (incl. `status→DISABLED`), Delete, **ForceLogout** | sync / async | `/iam/v1/serviceAccounts…`, `…/{id}:forceLogout` (public hard-cutoff, object-scoped) |
| `OAuthClientService` | Get, List / Create, Rotate, Update, Revoke | sync / async | `/iam/v1/serviceAccounts/{svaId}/oauthClients…` (`client_secret°` в `Operation.response` Create/Rotate, one-time) |
| | **Token** | **sync** | `POST …/oauthClients/{id}:token` → **`200 {accessToken°, expiresIn}` напрямую** (derivation, read-shaped; IAM-фасад `client_credentials`; форма `AuthService.TokenExchange`; НЕ Operation) |
| `GroupService` | Get, List, ListMembers / Create(+memberSpecs), Update, Delete, AddMember, RemoveMember | sync / async | `/iam/v1/groups…`, `…/{id}:addMember` |
| `RoleService` | Get, **List(`assignableOn?={scopeType,scopeId}`)** (system-роли first-class first-in-order; с `assignableOn` → assignable-set + `grantFragment`) / Create, Update, Delete | sync / async | `/iam/v1/roles[:list]` |
| `AccessBindingService` | Get, List (`filter subject=`,`role=`,`scope=`,`scopeId=`), ListOperations, ListGrantableResources | sync | `GET /iam/v1/accessBindings[:verb]` |
| | Create(+target, subject `EMAIL`-ok), Update, **Delete (=hard, Get→404)**, **:revoke (=soft-revoke)**, :grantToEmail, AddTargetResources, RemoveTargetResources, ReplaceTargetSelector | async | `POST`/`PATCH`/`DELETE /iam/v1/accessBindings…`, `…/{id}:revoke`, `…:grantToEmail` |
| `AuthorizeService` | Check, BatchCheck, ListObjects, ListSubjects, **ExpandAccess** | sync | `POST /iam/v1/authorize:{check,batchCheck,listObjects,listSubjects,expandAccess}` |
| `PermissionCatalogService` | ListPermissionCatalog | sync | `GET /iam/v1/permissionCatalog` |
| `OperationService` | Get, List | sync | `GET /iam/v1/operations/{id}` |

> **Единая introspection-поверхность.** «Кто-что-может» отвечает **только `AuthorizeService`**: `Check`/`BatchCheck` (predicate), `ListObjects` (subject→объекты, поглощает прежний `ListSubjectPrivileges`), `ListSubjects` (объект→субъекты), `ExpandAccess` (userset-разворот; public-поверхность говорит intent-языком, не ReBAC-жаргоном). `AccessBindingService` — чистый CRUD + `:revoke` + plain `List` (`ListByScope`/`ListBySubject`/`ListByRole` свёрнуты в фильтр-whitelist). **`ListAssignableRoles` слит в `RoleService.List(assignableOn=…)`** — одна параметризованная discovery-RPC (без параметра — каталог ролей; с параметром — assignable-set + paste-ready `grantFragment`, list⇔create parity).

**Internal (`:9091`, internal mux only — ban #6, two-projection):**

| Service | Методы | Назначение |
|---|---|---|
| `InternalIAMService` | Check | per-RPC authz-gate (все домены зовут перед мутацией) |
| | RegisterResource, UnregisterResource | FGA-proxy owner-tuple (идемпотентно, at-least-once outbox; least-priv `fga_writer@iam_fgaproxy:system`) |
| | GetRoleCompiled | compiled `permissions[]` (`M.R.rn.V`) — только internal-проекция роли |
| | LookupSubject | JWT `sub`/email/id → Principal (auth-interceptor) |
| | PollSubjectChanges | курсорный дренаж `subject_change_outbox` → инвалидация authz-кэша gateway |
| | WriteCreatorTuple, ForceLogoutCrossTenant, GetJWKSStatus | creator-tuple / cross-tenant admin hard-cutoff / signing-status (tenant-path `ForceLogout` — public выше) |
| JWKS-route | `GET /.well-known/jwks.json` (`:9097`) | **documented exception**: unauthenticated-by-design, server-TLS one-way, только публичный ключ-материал (short-TTL зеркало Hydra JWKS; issuer/подписант — Hydra) |

> **Cross-module edges (reference-law).** `kacho-compute → kacho-iam` — **class C**: Instance держит `Referrer{type:"iam.service_account", id, name°}` (graceful-dangling; IAM синхронно НЕ зовётся на request-path — удаление SA деградирует инстанс, не hard-fail; ацикличность усилена — нет ребра `compute→iam ServiceAccountService.Get`). Class-B `projectId`-ребро (`*→iam ProjectService.Get`) остаётся. Публичный hard-cutoff SA — `ServiceAccountService:forceLogout` (object-scoped); мягкий — `status→DISABLED`.

---

## Discovery-каталоги (рядом с мутацией — «что я могу выбрать», не гадать id)

Каждый item несёт **готовый inline-фрагмент**, byte-paste-совместимый с полем-целью. Все sync, authenticated-floor / grant-authority, fail-closed.

**1. `PermissionCatalogService.ListPermissionCatalog`** — грантуемая таксономия для авторинга роли (единый dotted type-registry) + **runtime-source-of-truth для collapse/promote** (data-plane модуль ОБЯЗАН фетчить mapping отсюда в рантайме, а не хардкодить — drift невозможен). `GET /iam/v1/permissionCatalog`.
```jsonc
{
  "modules": [
    { "module": "compute", "resources": [
      { "resource": "instance", "hasVerbRelations": true, "hasListEndpoint": true,
        "collapses": [],
        // PROMOTE: истинно-раздельные data-plane действия выставлены как first-class closed-verbs (симметрия collapse↔promote):
        "promotes": [
          { "verb": "start",   "fragment": { "module": "compute", "resources": ["instance"], "verbs": ["start"] } },
          { "verb": "stop",    "fragment": { "module": "compute", "resources": ["instance"], "verbs": ["stop"] } },
          { "verb": "restart", "fragment": { "module": "compute", "resources": ["instance"], "verbs": ["restart"] } } ] },
      { "resource": "disk", "hasVerbRelations": true, "hasListEndpoint": true, "collapses": [], "promotes": [] } ] },
    { "module": "registry", "resources": [
      { "resource": "repository", "hasVerbRelations": true, "hasListEndpoint": true,
        "collapses": [
          // pull РАЗНЕСЁН: чистый blob-pull НЕ бандлит tag-enumeration (least-priv pull-робот не получает v_list):
          { "action": "pull",          "foldsTo": ["get"],
            "fragment": { "module": "registry", "resources": ["repository"], "verbs": ["get"] } },
          { "action": "pull+listTags", "foldsTo": ["get","list"],
            "fragment": { "module": "registry", "resources": ["repository"], "verbs": ["get","list"] } },
          { "action": "push",          "foldsTo": ["create","update"],
            "fragment": { "module": "registry", "resources": ["repository"], "verbs": ["create","update"] } } ],
        "promotes": [] },
      { "resource": "image", "hasVerbRelations": true, "hasListEndpoint": true, "collapses": [], "promotes": [] } ] },
    { "module": "iam", "resources": [
      { "resource": "group", "hasVerbRelations": true, "hasListEndpoint": true,
        "collapses": [ { "action": "addMember/removeMember", "foldsTo": ["update"],
          "fragment": { "module": "iam", "resources": ["group"], "verbs": ["update"] } } ], "promotes": [] },
      { "resource": "oauthClient", "hasVerbRelations": true, "hasListEndpoint": true,
        "collapses": [ { "action": "rotate", "foldsTo": ["update"],
          "fragment": { "module": "iam", "resources": ["oauthClient"], "verbs": ["update"] } } ], "promotes": [] } ] }
  ],
  "closedVerbs": ["get","list","create","update","delete"],
  "tierAssignability": {   // ПУБЛИКАЦИЯ правила definitionTier↔anchor (иначе узнаётся только на Create-фейле):
    "iam.cluster": "assignable on ANY anchor (iam.cluster|iam.account|iam.project)",
    "iam.account": "assignable on its iam.account anchor AND nested iam.project of the same account",
    "iam.project": "assignable ONLY on its own iam.project anchor"
  },
  "wildcardPolicy": { "verbWildcardAllowedCustom": true, "moduleResourceWildcardSystemOnly": true }
  // collapse.fragment/promote.fragment — готовы к вставке в role.rules[]; data-plane action = именованный fold ЛИБО promoted first-class verb
}
```

**2. `RoleService.List(assignableOn={scopeType,scopeId})`** — роли, ВАЛИДНЫЕ для привязки на этом anchor'е (list⇔create parity — Create принимает ровно этот набор; **единственный advertised способ выбрать роль**). Канонические system-роли — **первыми, viewer→editor→admin→owner**, затем canned narrow, затем custom. `GET /iam/v1/roles:list?assignableOn.scopeId=prj-prod`.
```jsonc
{ "roles": [
  { "roleId": "rol-editor", "name": "editor", "displayName": "Editor", "isSystem": true,
    "purpose": "Read + create/update + co-materialized delete on in-scope leaf objects",
    "authoredVerbs": ["get","list","create","update"], "effectiveVerbs": ["get","list","create","update","delete*"],
    // READY fragment — ПОЛНАЯ grant-координата + suggested-target (scopeType выводим из scopeId, включён для явности):
    "grantFragment": { "roleId": "rol-editor", "scopeType": "iam.project", "scopeId": "prj-prod",
                       "target": { "allInScope": {} } } },
  { "roleId": "rol-viewer", "name": "viewer", "displayName": "Viewer", "isSystem": true,
    "purpose": "Read-only across all modules in scope",
    "authoredVerbs": ["get","list"], "effectiveVerbs": ["get","list"],
    "grantFragment": { "roleId": "rol-viewer", "scopeId": "prj-prod", "target": { "allInScope": {} } } },
  { "roleId": "rol-registry-puller", "name": "registry.puller", "displayName": "Registry Puller", "isSystem": true,
    "purpose": "Pull images — no push", "authoredVerbs": ["get","list"], "effectiveVerbs": ["get","list"],
    "grantFragment": { "roleId": "rol-registry-puller", "scopeId": "prj-prod", "target": { "allInScope": {} } } },
  { "roleId": "rol-3m2k9c", "name": "app-deployer", "displayName": "app-deployer", "isSystem": false,
    "purpose": "Deploy + read compute/vpc in prod",
    "authoredVerbs": ["get","list","create","update"], "effectiveVerbs": ["get","list","create","update","delete*"],
    "grantFragment": { "roleId": "rol-3m2k9c", "scopeId": "prj-prod", "target": { "allInScope": {} } } }
]}
// grantFragment paste-совместим прямо в CreateAccessBinding. Без assignableOn — тот же список БЕЗ grantFragment (каталог ролей).
```

**3. `AccessBindingService.ListGrantableResources(scopeType, scopeId, objectType)`** — объекты под scope для object-picker'а target'а. `GET /iam/v1/accessBindings:listGrantableResources`.
```jsonc
{ "grantableResources": [
  // iam-owned типы — реальные строки same-DB:
  { "type": "iam.project", "resolvable": true, "id": "prj-prod", "name": "prod" }
], "unresolvableTypes": [
  // non-iam (compute.*/vpc.*/registry.*) — НЕ пустой []: явный descriptor (iam НЕ зовёт owner — это цикл).
  // resolveHint — ПОЛНОСТЬЮ сформированный запрос (scope.projectId подставлен); fragmentTemplate — copy-run-paste:
  { "type": "compute.instance", "resolvable": false,
    "resolveHint": "GET /compute/v1/instances?projectId=prj-prod",
    "fragmentTemplate": { "type": "compute.instance", "id": "<id-from-resolveHint>" } }
]}
// «нет объектов» (resolvable:true, пустой список) ≠ «резолвится client-side» (resolvable:false + готовый hint + template).
// Combined cross-module target-picker (fan-out resolveHints, заполнение fragmentTemplate) вымощен на gateway/SDK — НЕ в iam (ацикличность холдится).
```

---

## Правила (нормативно)

1. **Flat resource, `°` = output-only.** Domain-поля на верхнем уровне; никакого `spec`/`status`/`metadata`/`resourceVersion`-envelope (**`resourceVersion` на wire отсутствует у ВСЕХ ресурсов** — OCC чисто server-side). `id`/`createdAt`/`status`/`ownerUserId`/`memberCount`/`grantedByUserId`/`revokedAt`/`isSystem`/subject-`name`/`accounts`/compiled `permissions`/`materializedUserId` — output-only (`°`). Дискриминатор `tenancy` упразднён (выводится структурно из наличия `accountId`).

2. **Read sync, мутации async — с двумя declared-исключениями.** `Get/List/Get*Output/Resolve`/каталоги — sync. `Create/Update/Delete` и бо́льшая часть `:verb` → `Operation`; `metadata.<res>Id` доступен ДО `done`. **Declared sync-исключения (derivation, read-shaped, не мутация durable-ресурса):** `OAuthClient:token` (`client_credentials`-обмен → `{accessToken°,expiresIn}` за один round-trip; durable-credential чеканит только `OAuthClient.Create`/`Rotate` — они async) и `AuthService.TokenExchange`. Watch RPC нет.

3. **`Operation.done` = durability, НЕ downstream-видимость.** binding закоммичен ⇏ FGA-tuple виден. `«создал grant → сразу Check/Get своего»` → **first-class `retry_until_authorized`** (bounded client-retry, 6-10s, стабильный `Retry-After`-hint отличает transient от genuine deny — quickstart-рецепт D; НИКАКИХ IAM-only полей `readReady`/`retryAfterMs` на shared Operation-конверте); серверный confirm-gate запрещён (ban #9, phantom). Fixture обязан проверять `!op.error` перед извлечением id из `metadata`.

4. **One-shot Create-саги.** `Account.Create` → default-Project (`"default"`) + owner-AccessBinding (`metadata`: `accountId`+`defaultProjectId`); `Group.Create` → `memberSpecs[]`; `AccessBinding.Create` → `subjects[]`(1..32, incl. `EMAIL`)+`target`; **`ServiceAccount.Create` → опц. `OAuthClient`(+initial `AccessBinding` с `roleId` ЛИБО inline `rules[]`)** одной Operation (`metadata`: `serviceAccountId`+`oauthClientId`, `clientSecret°` в `response`) — least-priv робот не требует отдельного Role-lifecycle. Гранулярные RPC остаются для advanced.

5. **Discovery рядом с мутацией, byte-paste-инвариант (grant-координата целиком).** `RoleService.List(assignableOn)`/`ListGrantableResources`/`ListPermissionCatalog` возвращают item с готовым inline-фрагментом; **любой отданный фрагмент byte-paste-совместим с полем-целью** — включая **полную grant-координату** `{roleId, scopeType, scopeId, target}`. **`grantFragment` из `RoleService.List(assignableOn)` — ЕДИНСТВЕННЫЙ advertised штатный способ собрать binding** (raw hand-authored — исключение). Единый dotted type/tier-registry (`iam.project`/`compute.instance`) — те же строки во всех grant-поверхностях. **`scopeGroup` удалён.** Non-iam target-типы — не пустой `[]`, а `{resolvable:false, resolveHint (полностью сформирован), fragmentTemplate}`.

6. **`validateOnly:true`** — sync dry-run полной валидации (3 sync-гейта AccessBinding, rules-compile, scope-XOR) БЕЗ мутации/Operation и state-gate; **ВСЕГДА** эхает **честную по iam-vs-cross-module split** blast-radius-строку: `"grants {effectiveVerbs, incl. co-materialized delete*} on {N} iam-objects + {M} unresolved cross-module referents under {scopeType}:{scopeId}"` (M = число `Referrer`'ов — не резолвится by design, iam→owner цикл; `allInScope` на non-iam типах помечается `resolvable-indeterminate`) + `warnings[]` + echo выведенных значений (нормализованный tier, resolved subject-`name`, compiled-permissions-count). Co-материализованный `delete*` обязателен в строке (не только authored-verbs — иначе least-priv-прогноз врёт).

7. **Reference-law по СЕМАНТИЧЕСКОМУ КЛАССУ, не по wire-форме.** within-service → flat `<x>Id` + FK (`roleId`/`accountId`; `ServiceAccount.defaultProjectId` — informational-A, НЕ authz; `Role.definitionTier` = типизированные FK + CHECK-XOR, dotted-проекция `tierType`/`tierId` на wire); scope-координата (`scopeType`+`scopeId`) → flat dotted-type + within-DB soft-ref; **dependency на чужой owned-ресурс → `Referrer{type,id,name°}` polymorphic graceful-dangling — включая `Instance.serviceAccountId` (класс C, НЕ B: SA — identity-зависимость, деградирует при удалении, IAM синхронно не зовётся)** и `target.resources[]`. FK/scope в `Referrer` НЕ заворачивать. Inline-`condition` (CEL) и grant-`expiresAt` **вынесены в follow-up**.

8. **Two-projection.** Public = намерение+результат. Compiled `permissions[]`, FGA-tuples, `external_id`↔subject-mapping, JWKS-signing-status, `RegisterResource`/`Check`/`PollSubjectChanges`/cross-tenant hard-cutoff — только `Internal*` :9091 (`GetRoleCompiled` для compiled-роли). Tenant-path `ForceLogout` (SA hard-cutoff) — **public** (object-scoped): operational-действие, не инфра-топология.

9. **AuthN+AuthZ на КАЖДОМ RPC обоих листенеров.** mTLS/JWT транспорт; per-RPC `Check`; object-scoped `scope_extractor` (target→project) для RPC над caller-supplied id (anti-BOLA/impersonation); permission-catalog полон (нет записи → `AUTHZ_DENIED` fail-closed). Задокументированные исключения: JWKS-route (public-key-only, server-TLS) и `AuthService.Login`/`Callback` (pre-auth OIDC-handshake by design).

10. **Update — mutability-классы единообразно.** **LIVE-mutable**: `name`/`description`/`labels`/`deletionProtection`. **Immutable** (reject ДО `UpdateMask`, тон `"<field> is immutable after <R>.Create"`; **declared-exception mirror-ресурса** — User IdP-поля отдают `"<field> is read-only (User is an external identity-provider mirror)"` при том же коде `INVALID_ARGUMENT` и стабильном `status.details{reason,field}`): `Account.ownerUserId`, `Project.accountId`, User IdP-mirror-поля, `ServiceAccount.accountId`, `Role.definitionTier`/`isSystem`, `AccessBinding.{subject,roleId,scopeType,scopeId}`, `UserInvitation.{accountId,email,expiresAt}`. **STATE-toggle** (не Delete): `ServiceAccount.status↔{ACTIVE,DISABLED}`. **OCC-gated (server-side `xmin`, БЕЗ wire-токена)**: `Role.rules` / `AccessBinding.selector` → `FailedPrecondition "… was modified concurrently, retry"`.

11. **Within-service инварианты — на DB-уровне** (ban #10): UNIQUE(name) per-scope/per-definitionTier, FK RESTRICT/CASCADE, CHECK `roles_definition_tier_xor`, partial UNIQUE(accountId,lower(email)) WHERE invitation PENDING, **partial UNIQUE(subject-set,role,scope,target) WHERE binding status='ACTIVE'** (корректный re-grant после revoke), atomic CAS status-transitions, триггер existence для полиморфного `member_id`/`subject_id`. Software check-then-act запрещён.

12. **Единый тон ошибок (часть контракта), с одной declared-exception.** `"<Resource> <id> not found"` · `"<field> is immutable after <R>.Create"` (**declared-exception:** User-mirror → `"<field> is read-only (User is an external identity-provider mirror)"`, тот же код + стабильный `status.details{reason:"FIELD_IMMUTABLE",field}`) · `"Illegal argument <thing>"` · `"user <email> has not completed login"` · **actionable tier-mis** `"role rol-x (definitionTier iam.account) is not assignable on iam.project:prj-prod; assign at iam.project or iam.account tier of this account"`. Коды: `INVALID_ARGUMENT` · `NOT_FOUND` · `FAILED_PRECONDITION`(состояние/mis-scope/in-use/OCC/not-yet-logged-in) · `ALREADY_EXISTS`(UNIQUE ACTIVE) · `UNAVAILABLE`(peer/FGA down — fail-closed) · `INTERNAL`(opaque, без pgx/SQL-leak). Malformed-id и структурные Create-гейты → sync первым стейтментом; `Operation.error` только для async. Hide-existence 404 байт-идентичен реальному miss.

13. **List/Get — format-validate ДО authz-short-circuit.** `page_size`(0→default50,max1000, вне диапазона→reject)/`page_token`(garbage→InvalidArgument)/id-формат/filter-whitelist — ДО listauthz empty-grant. `List = viewer ∪ v_list` (anonymous→empty; FGA error→`Unavailable`; self-floor; admin/owner через viewer-tier); `Get == List`-resolver. `AccessBindingService.List` — cursor-pagination + whitelist (`subject=`/`role=`/`scope=`/`scopeId=`). `RoleService.List` возвращает system-роли **первыми** (assignableOn-вариант — assignable-set + grantFragment).

14. **eventually-consistent authz-материализация.** flat Contract-A (DIRECT usersets per-object, без каскада); owner/grant-tuple эмитится intent'ом в writer-tx → sync-registrar (best-effort) + `fga_outbox` (at-least-once drainer) + reconciler. Group-membership зеркалится (`group:<gid>#member@…`) в той же tx. `UserInvitation`-accept (и grant-by-email) co-commit'ит User + грант при первом входе. **`Delete` = физическое удаление** (Get→404, product-parity); **`:revoke` = soft-revoke** (`status→REVOKED`, row+`revokedAt`+`grantedByUserId` удерживаются, реплеит emitted-ledger). Re-grant после `:revoke` = новая ACTIVE-строка (partial UNIQUE WHERE ACTIVE).

15. **JSON camelCase; id = 3-char prefix + crockford-base32; UNIQUE(scope,name) partial; timestamps truncate-to-seconds.** Единый dotted type/tier-registry для всех grant-поверхностей; **id-prefix кодирует тип → `scopeType` для iam-anchor'ов выводится из `scopeId` (`prj-`⇒`iam.project`, `acc-`⇒`iam.account`) и необязателен; задаётся лишь для non-iam/дизамбигуации** (bare `projectId` byte-paste-совместим с grant-полем). «scope» — ровно один смысл (anchor binding'а), tier роли — `definitionTier` (`tierType`/`tierId`, слово «scope» не появляется), discovery-`scopeGroup` удалён. Vendor-agnostic (ban #2): никаких имён чужих облаков **и third-party-product-noun'ов** (внешний IdP/authorization-server — родовым языком под IAM-фасадами) — узнаваемость знакомой ФОРМОЙ, не брендом.

16. **IAM — не placement-scoped и не org-многоуровневый.** identity/authz-плоскость глобальна; `placementType`/`zoneId`/`regionId`/coherence-CHECK неприменимы by construction. Дерево аренды — **строго два уровня** `Account→Project` (Project — leaf-workspace, без вложенности); над Account tier не вводится (B2B-org — вне scope). Осознанное исключение из placement-coherence.

17. **Credential-sub-ресурс — единый noun `OAuthClient`; путь к Bearer — sync, один round-trip.** `OAuthClientService` + REST `/serviceAccounts/{svaId}/oauthClients`. One-time `client_secret°` — в `Operation.response` терминального полла `Create`/`Rotate` (durable-credential, async). **Обмен на Bearer — SYNC IAM-фасад** `oauthClients/{id}:token` → `{accessToken°, expiresIn}` напрямую (derivation, не мутация; external authorization-server под капотом, `client_credentials`); токен пригоден как есть (`docker login -u <clientId> -p <accessToken>`) — без poll на hot-path, обе token-поверхности модуля (user `tokenExchange` / SA `:token`) когерентно sync.

18. **AuthService — вход на контракте, без локального user-store.** `Login`/`Callback`/`TokenExchange` — IAM-фасад OIDC; материализуют/обновляют `User`-mirror, но **публичного `User.Create` нет** — mirror-принцип цел. `UserInvitation` (и grant-by-email фасад) пред-провижнит субъект по email до входа; грант активируется атомарно при первом OIDC-login. `UserService.Resolve` различает залогинен/приглашён/неизвестен. **Членство человека в аренде выводится структурно** (User глобален, без `accountId`) и отдаётся `AccountService.ListMembers` + derived `User.accounts°` — не ищи «пользователей аккаунта» на самом ресурсе User.
