# AuthZ default-deny matrix — newman tests

**Date:** 2026-05-19
**Author:** brainstorm session (Kacho Workspace)
**Status:** APPROVED — ready for plan
**Scope:** cross-repo (kacho-vpc / kacho-iam / kacho-compute + kacho-workspace shared fixtures)
**Predecessors:** [[KAC-104]] (IAM/AuthZ epic), [[KAC-108]] (per-RPC Check), [[KAC-120]] (vpc/compute Check active), [[KAC-119]] (bootstrap admin matcher), [[KAC-125]] (User-per-Account + Invite — picks up "Newman cases for Invite (deferred)" DoD item)

---

## 1. Goal

Newman-suite, гарантирующий что **по дефолту нет CRUD-доступа** к ресурсам Kachō control plane для **шести** классов субъектов:

| Subject | Описание | Auth |
|---|---|---|
| `ANON` | без Authorization-header'а → `system:anonymous` | (no Bearer) |
| `NOB` | authenticated user без role-bindings | HS256 JWT, `sub=auth-test-no-bindings` |
| `PA1` | project-admin на project-A1 (editor on project) | HS256 JWT, `sub=auth-test-proj-admin-a1` |
| `AAA` | account-admin на account-A | HS256 JWT, `sub=auth-test-account-admin-a` |
| `AAB` | account-admin на account-B | HS256 JWT, `sub=auth-test-account-admin-b` |
| `INV` | owner-of-account-B (home), приглашён `UserService.Invite`'ом из account-A как `editor` на project-A1; status=ACTIVE | HS256 JWT, `sub=auth-test-invitee` |

Покрытие — **full matrix** (каждый публичный CRUD каждого сервиса × каждый субъект). Дополнительно — позитивная подтверждающая выборка: catalog-read (Zone/Region/DiskType) разрешён всем authenticated, root-infra mutations требуют cluster-admin (которого в нашей шестёрке нет). Subject `INV` покрывает cross-account invite-flow (KAC-125): один Kratos-identity → две User-row (по одной per Account).

## 2. Permission matrix (источник истины для assert'ов)

### 2.1 Базовые scope-классы (resource CRUD)

```
Scope                     | ANON | NOB   | PA1   | AAA   | AAB   | INV   | Комментарий
--------------------------+------+-------+-------+-------+-------+-------+----------------------------------------------------------
project-A1 (in account-A) | DENY | DENY  | ALLOW | ALLOW | DENY  | ALLOW | INV: editor via invite (KAC-125)
project-A2 (in account-A) | DENY | DENY  | DENY  | ALLOW | DENY  | DENY  | INV: not invited to A2
project-B1 (in account-B) | DENY | DENY  | DENY  | DENY  | ALLOW | ALLOW | INV: owner-of-B cascade (owner > admin > editor)
account-A own (vs AAA)    | DENY | DENY  | DENY  | ALLOW | DENY  | DENY  | INV has only project-level invite, no account-level binding
account-B own (vs AAB)    | DENY | DENY  | DENY  | DENY  | ALLOW | ALLOW | INV: owner of B
catalog-read (Zone/Region)| DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW | system:catalog viewer to all authenticated (compute edge §catalog)
catalog-mutate            | DENY | DENY  | DENY  | DENY  | DENY  | DENY  | cluster-admin only (нет в нашей шестёрке)
cluster-role-mutate       | DENY | DENY  | DENY  | DENY  | DENY  | DENY  | cluster-admin only
addresspool-mutate        | DENY | DENY  | DENY  | DENY  | DENY  | DENY  | cluster-admin / internal-listener only
```

### 2.2 IAM-специфичные scope-классы (Invite + User.List)

```
Scope                     | ANON | NOB   | PA1   | AAA   | AAB   | INV   | Комментарий
--------------------------+------+-------+-------+-------+-------+-------+----------------------------------------------------------
invite-to-account-A       | DENY | DENY  | DENY* | ALLOW | DENY  | DENY* | * KAC-125 D-9: CanInviteUsers = Check(editor on account).
                          |      |       |       |       |       |       |   PA1 / INV — editor только на project, не на account → DENY
invite-to-account-B       | DENY | DENY  | DENY  | DENY  | ALLOW | ALLOW | INV owner-of-B → editor cascade на account-B
user-list ?accountId=A    | DENY | empty | empty | ALLOW | DENY  | ALLOW | KAC-125 D-4: scope = accounts where principal is member.
                          |      | (ALW) | (ALW) |       |       |       |   INV — ACTIVE member of A через invite.
                          |      |       |       |       |       |       |   NOB/PA1: ALLOW status, но response — empty list (нет membership)
user-list ?accountId=B    | DENY | empty | empty | DENY  | ALLOW | ALLOW | INV — owner-of-B (member)
```

Замечание про `user-list`: `KAC-125` строит default-deny не через PermissionDenied, а через **scope-filter** — RPC возвращает 200 с пустым списком, если principal не member ни одного из запрошенных Account'ов. Соответствующие кейсы assert'ят `200 + items.length === 0`, а не `403`.

### 2.3 Assert правила

- `DENY` → newman assert: HTTP 403 + grpc-code `PERMISSION_DENIED` + body contains `"permission denied"`.
- `ALLOW` → newman assert: `pm.response.code !== 403`. Любой другой код (200/400/404) — приемлем; нас интересует отсутствие именно PermissionDenied (валидацию happy-path делают существующие тесты).
- `empty` (для `user-list`) → assert: `pm.response.code === 200 && body.users.length === 0`. Отдельный assert-вариант.

## 3. Архитектура

Три параллельные расширения существующих newman-suite (по одному на сервис) + один shared bootstrap для фикстур.

```
kacho-workspace/
├── tests/authz-fixtures/                       ← НОВОЕ (shared bootstrap)
│   ├── setup.sh                                — idempotent fixture seeder
│   ├── setup-jwt.py                            — HS256 JWT minter (pyjwt)
│   ├── README.md                               — как запустить + переменные
│   └── out/authz-fixtures.json                 — IDs + JWTs (gitignored)
├── docs/superpowers/specs/
│   └── 2026-05-19-authz-default-deny-matrix-newman-design.md  ← этот файл
project/kacho-vpc/tests/newman/cases/
│   └── authz-deny.py                           ← НОВОЕ (~180 кейсов, 6 субъектов)
project/kacho-iam/tests/newman/cases/
│   └── authz-deny.py                           ← НОВОЕ (~180 кейсов: account/project/group/sa/role/user/invite + user-list-scoping)
project/kacho-compute/tests/newman/cases/
│   └── authz-deny.py                           ← НОВОЕ (~180 кейсов)
project/kacho-{vpc,iam,compute}/tests/newman/scripts/gen.py
    └── (расширение ~20 строк: поддержка step["auth"] ключа)
```

Итого **~540 newman-кейсов**.

## 4. Фикстуры (shared bootstrap)

### Что создаётся

`setup.sh` — идемпотентен (re-run safe), полагается на:

- `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL=@prorobotech.ru` (на стенде, см. `clusters/e2c825/overrides.yaml`) — bootstrap-admin
- `KACHO_API_GATEWAY_AUTHN_DEV_SECRET=kacho-dev-jwt-secret-2026` (на стенде)
- port-forward на `localhost:18080` (api-gateway internal listener)

| # | Endpoint | Что | Идемпотентность |
|---|---|---|---|
| 1 | `setup-jwt.py` (local) | mints 5× HS256 JWT с `sub=<external_id>`, exp=24h (NOB / PA1 / AAA / AAB / INV) | детерминистично |
| 2 | `POST /iam/v1/internal/users:upsertFromIdentity` × 5 | bootstrap-admin (`@prorobotech.ru`) + 4 base test-users (NOB/PA1/AAA/AAB); deterministic `external_id`. Каждый non-bootstrap upsert auto-create'ит свой bootstrap-Account (KAC-117) — это **намеренный side-effect**, эти accounts не используются в матрице | UpsertFromIdentity by design (KAC-125) |
| 3 | `POST /iam/v1/accounts` × 2 | account-A, account-B (созданы под bootstrap-admin'ом — гарантия фиксированных name) | by name dedup (KAC-124 §13.4) |
| 4 | `POST /iam/v1/projects` × 3 | project-A1, project-A2 (в account-A), project-B1 (в account-B) | by name+accountId dedup |
| 5 | `POST /iam/v1/accessBindings` × 3 | editor@projectA1 → user-PA1; admin@accountA → user-AAA; admin@accountB → user-AAB | 5-tuple dedup (KAC-112 §13.4) |
| 6 | **INV setup (KAC-125 invite-flow)** | (а) `UpsertFromIdentity` для invitee → создаётся User-row в его bootstrap-Account как owner; вручную через `accountServ.Update` переименовываем bootstrap-Account в `account-INV-home` для ясности (либо просто запомнить его id как `accountInvHomeId`). (б) `POST /iam/v1/users:invite` под AAA-токеном: `{accountId: accountAId, email: invitee@..., roleId: editor, projectId: projectA1Id}` → создаётся вторая User-row для invitee в account-A со status=PENDING. (в) повторный `UpsertFromIdentity` для invitee (с тем же external_id) активирует PENDING-row (KAC-125 D-7) → status=ACTIVE | UpsertFromIdentity / Invite оба idempotent |
| 7 | `POST /vpc/v1/networks` × 2 (admin token) | seed-network в project-A1 + seed-network в project-B1 (для GET-проб) | by name dedup |
| 8 | патч env-файлов | append `jwtNoBindings`, `jwtProjectAdminA1`, `jwtAccountAdminA`, `jwtAccountAdminB`, `jwtInvitee`; IDs (`accountAId`, `accountBId`, `accountInvHomeId`, `projectA1Id`, `projectA2Id`, `projectB1Id`, `seedNetworkA1Id`, `seedNetworkB1Id`, `inviteeUserAccountAId` (PENDING→ACTIVE), `inviteeUserAccountInvId` (bootstrap), `userPA1Id`, `userAAAId`, `userAABId`, `userNOBId`) | patch-by-key |

### Как setup получает admin-доступ

`setup-jwt.py` создаёт **ещё один** JWT с `sub=admin@prorobotech.ru` — этот subject auto-grant'ит admin-tuples через `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL` matcher в kacho-iam. Этот токен использует setup для шагов 2-6.

### Что НЕ удаляется после прогона

Фикстуры (accounts/projects/users/bindings/seed-network) **остаются** между прогонами — это снижает шум и стоимость setup'а. Они идемпотентны.

## 5. Расширение gen.py

В каждый `scripts/gen.py` добавляется блок ~20 строк: чтение опционального `auth=`-ключа из step.

В collection-level Pre-request script (общий на все запросы):

```javascript
// AuthZ-test header injection.
// step может иметь "auth"=<env-var-name> (использовать как Bearer)
//          либо "auth"="anonymous" (снять Authorization)
//          либо отсутствие ключа — header не трогается (для legacy-кейсов)
const auth = pm.variables.get("__stepAuth");  // set by step pre-request
if (auth === "anonymous") {
    pm.request.headers.remove("Authorization");
} else if (auth) {
    const token = pm.environment.get(auth);
    if (token) pm.request.headers.upsert({key: "Authorization", value: "Bearer " + token});
}
```

В step-pre-script (генерируется per-case):
```javascript
pm.variables.set("__stepAuth", "<auth-value-or-empty>");
```

Default behavior (existing cases без `auth`) — без изменений: `__stepAuth` пустой → header не трогается.

## 6. Декларативный кейс-формат

Каждый `authz-deny.py` определяет SUBJECTS + RESOURCES + EXPECT, генератор разворачивает в кейсы:

```python
SUBJECTS = [
    ("ANON",  "anonymous",                          None),
    ("NOB",   "no-bindings",                        "jwtNoBindings"),
    ("PA1",   "project-admin-a1",                   "jwtProjectAdminA1"),
    ("AAA",   "account-admin-a",                    "jwtAccountAdminA"),
    ("AAB",   "account-admin-b",                    "jwtAccountAdminB"),
    ("INV",   "invitee-owner-B-editor-projectA1",   "jwtInvitee"),
]

# Resource описывает один ресурс в одной координате (own/cross-project/cross-account).
RESOURCES = [
    dict(
        name="network-own-A1", scope="project-own",
        create=("POST",   "/vpc/v1/networks",            {"projectId":"{{projectA1Id}}","name":"authz-x-{{runId}}"}),
        get   =("GET",    "/vpc/v1/networks/{{seedNetworkA1Id}}"),
        list  =("GET",    "/vpc/v1/networks?projectId={{projectA1Id}}"),
        update=("PATCH",  "/vpc/v1/networks/{{seedNetworkA1Id}}", {"name":"y"}),
        delete=("DELETE", "/vpc/v1/networks/{{seedNetworkA1Id}}"),
    ),
    dict(name="network-cross-A2",    scope="project-cross-same-account", ...),
    dict(name="network-cross-B1",    scope="project-cross-account",     ...),
    # … остальные 7 VPC-ресурсов в трёх координатах + AddressPool (internal-listener) + Region/Zone (catalog)
]

EXPECT = {  # scope → subject → decision
    # Resource-CRUD scope-классы
    "project-A1":                 {"ANON":"DENY","NOB":"DENY","PA1":"ALLOW","AAA":"ALLOW","AAB":"DENY","INV":"ALLOW"},
    "project-A2":                 {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"ALLOW","AAB":"DENY","INV":"DENY"},
    "project-B1":                 {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"ALLOW","INV":"ALLOW"},
    "account-A":                  {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"ALLOW","AAB":"DENY","INV":"DENY"},
    "account-B":                  {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"ALLOW","INV":"ALLOW"},
    "catalog-read":               {"ANON":"DENY","NOB":"ALLOW","PA1":"ALLOW","AAA":"ALLOW","AAB":"ALLOW","INV":"ALLOW"},
    "catalog-mutate":             {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"DENY","INV":"DENY"},
    "cluster-role-mutate":        {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"DENY","INV":"DENY"},
    "addresspool-mutate":         {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"DENY","INV":"DENY"},
    # IAM-специфичные (Invite + User.List)
    "invite-to-account-A":        {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"ALLOW","AAB":"DENY","INV":"DENY"},
    "invite-to-account-B":        {"ANON":"DENY","NOB":"DENY","PA1":"DENY", "AAA":"DENY", "AAB":"ALLOW","INV":"ALLOW"},
    "user-list-account-A":        {"ANON":"DENY","NOB":"EMPTY","PA1":"EMPTY","AAA":"ALLOW","AAB":"DENY","INV":"ALLOW"},
    "user-list-account-B":        {"ANON":"DENY","NOB":"EMPTY","PA1":"EMPTY","AAA":"DENY","AAB":"ALLOW","INV":"ALLOW"},
}
# Где EMPTY → assert 200 + body.users.length === 0 (KAC-125 default-deny через scope-filter, не через PermissionDenied).
```

Генератор разворачивает `RESOURCES × CRUD × SUBJECTS` → `CASES`:

```python
CASES.append(dict(
    id=f"AUTHZ-{resource.name.upper()}-{op.upper()}-{subj_code}",
    title=f"{resource.name} {op} as {subj_label} → {decision}",
    classes=["AUTHZ", "NEG" if decision=="DENY" else "POS"],
    priority="P1",
    verifies=f"authz-{resource.scope}-{subj_code}-{op}",
    steps=[dict(name=op, method=method, path=path, body=body,
                auth=auth_env_var or "anonymous",
                test_script=[deny_assert if decision=="DENY" else allow_assert])],
))
```

`deny_assert`:
```python
[
    "pm.test('status 403', () => pm.expect(pm.response.code).to.equal(403));",
    "const j = pm.response.json && pm.response.json();",
    "pm.test('grpc code PERMISSION_DENIED', () => pm.expect(j && j.code).to.equal(7));",  # codes.PermissionDenied
    "pm.test('message includes \"permission denied\"', () => pm.expect((j && j.message || '').toLowerCase()).to.include('permission denied'));",
]
```

`allow_assert`:
```python
[
    "pm.test('not PermissionDenied', () => pm.expect(pm.response.code).to.not.equal(403));",
    "if (pm.response.code === 200 || pm.response.code === 400 || pm.response.code === 404 || pm.response.code === 409) { return; }",
    "pm.test('unexpected status code', () => pm.expect.fail('got HTTP ' + pm.response.code));",
]
```

`empty_assert` (для `user-list-*` со scope-filter):
```python
[
    "pm.test('status 200', () => pm.expect(pm.response.code).to.equal(200));",
    "const body = pm.response.json && pm.response.json();",
    "pm.test('empty users list (scope-filter default-deny)', () => pm.expect((body && body.users || []).length).to.equal(0));",
]
```

## 7. Карта ресурсов

### kacho-vpc

| Resource | Scope | Координаты в матрице |
|---|---|---|
| Network, Subnet, Address, RouteTable, SecurityGroup, Gateway, PrivateEndpoint, NetworkInterface | project | own A1 / cross A2 / cross B1 |
| AddressPool | admin/cluster-write | global (DENY все 5) |

### kacho-compute

| Resource | Scope | Координаты |
|---|---|---|
| Instance, Disk, Image, Snapshot | project | own A1 / cross A2 / cross B1 |
| Zone, Region, DiskType | catalog-read | global; mutate (если есть на public mux) → catalog-mutate (DENY) |

### kacho-iam

| Resource / RPC | Scope-class | Координаты |
|---|---|---|
| Account (CRUD) | account | account-A (own AAA) / account-B (own AAB) |
| Project (CRUD) | project (через project.accountId) | project-A1 / project-A2 / project-B1 |
| Group (CRUD) | account | account-A / account-B |
| ServiceAccount (CRUD) | account | account-A / account-B |
| AccessBinding (CRUD) | account (через resourceId — на account-level) | account-A / account-B |
| User.Get / User.Update / User.Delete | account (per-account, KAC-125) | по userId внутри account-A / account-B |
| **User.List?accountId=** | scope-filter (NOT 403, but empty-list) | account-A / account-B (user-list-account-A / user-list-account-B) |
| **UserService.Invite** | account (CanInviteUsers = Check editor on account, KAC-125 D-9) | invite-to-account-A / invite-to-account-B |
| Role.Get / List (catalog) | catalog-read | global (cluster catalog) |
| Role.Create / Update / Delete | cluster-role-mutate | global (cluster-admin only) |

## 8. Run integration

Существующий `scripts/run.sh` (в каждом сервисе) автоматически подхватит `cases/authz-deny.py` (генерирует `collections/authz-deny.postman_collection.json` и запускает newman).

Дополнительная команда в `kacho-workspace/Makefile`:
```make
authz-test-setup:
	bash tests/authz-fixtures/setup.sh

authz-test-run:
	cd project/kacho-vpc/tests/newman    && ./scripts/run.sh --service authz-deny
	cd project/kacho-iam/tests/newman    && ./scripts/run.sh --service authz-deny
	cd project/kacho-compute/tests/newman && ./scripts/run.sh --service authz-deny
```

## 9. Risk / Edge cases

1. **api-gateway dev mode**: тесты ходят на dev-listener (`localhost:18080`). На production-strict-mode anonymous → `Unauthenticated` (401), не `PermissionDenied` (403). Assert'ы пишем под dev-mode (текущий стенд). Если стенд поднимется в production-strict — отдельный suite-variant.
2. **JWT exp**: 24h токены. Если прогон занимает > 24h (маловероятно) — re-run setup. Setup минтит свежие.
3. **catalog Get/List для no-bindings**: edge `compute-to-iam-check.md` говорит что E3 выдаёт всем authenticated `viewer on system:catalog`. Если этот grant не wired'ен — NOB-кейсы по catalog-read покраснеют → fix permission_map (отдельный KAC-bug), а не правка тестов.
4. **cluster-admin** в матрице **отсутствует** — root-infra mutations всеми шестью субъектами DENIED. Это by-design: тесты проверяют что обычный account-admin / invitee не может мутировать catalog/cluster-role/addresspool. Позитивный сценарий "cluster-admin может" не покрываем (отсутствие cluster-admin в нашей шестёрке).
5. **vpc Region/Zone** до KAC-15 close ещё доступны под `/vpc/v1/regions` / `/vpc/v1/zones`. Поскольку они internal-admin, попадают в `addresspool-mutate` категорию (DENY все 6). После KAC-15 — убрать.
6. **Newman cases bloat**: ~540 кейсов на 3 suite добавит ~40% к времени прогона. Mitigate: cases короткие (один step), без resource creation в DENY (PermissionDenied раньше repo) — реальная стоимость ~7 минут.
7. **INV invite-activation race**: setup шаг 6 делает Invite → second User-row PENDING; следом UpsertFromIdentity активирует PENDING. Если KAC-125 D-7 PENDING-aware flow flaky — INV-тесты будут красные «no membership». Mitigate: setup проверяет финальный `User.Get(inviteeUserAccountAId)` → assert `invite_status=ACTIVE` перед патчем env. Если не ACTIVE — setup падает с понятной ошибкой.
8. **INV cascade through owner-of-B**: тест полагается на cascade `owner > admin > editor` в `KetoClient.relationsImplying` (KAC-119 helper). Если cascade не настроен для owner→editor на projects within account-B — `project-B1 INV ALLOW` сломается. Это уже behaviour KAC-119/125, в нашем PR не правим. Если упадёт — fix-PR на kacho-iam.
9. **User.List default-deny scope-filter**: KAC-125 D-4 говорит scope = «accounts where principal is member». Если RPC возвращает 403 вместо 200+empty — assert'ы покраснеют. Это поведение должно быть consistent с KAC-125 integration-tests. Если нет — fix-PR на kacho-iam.

## 10. Definition of Done

- [ ] `kacho-workspace/tests/authz-fixtures/setup.sh` + `setup-jwt.py` + `README.md` — идемпотентен, проходит на чистом стенде; включает invite-flow setup (KAC-125 шаг 6)
- [ ] `project/kacho-vpc/tests/newman/cases/authz-deny.py` — сгенерирован, ~180 кейсов (6 субъектов × 8 ресурсов × CRUD)
- [ ] `project/kacho-iam/tests/newman/cases/authz-deny.py` — сгенерирован, ~180 кейсов (Account/Project/Group/SA/AB/Role + UserList scope-filter + Invite)
- [ ] `project/kacho-compute/tests/newman/cases/authz-deny.py` — сгенерирован, ~180 кейсов
- [ ] `gen.py` каждого сервиса понимает `auth=`-ключ; существующие кейсы не сломаны (regression-run зелёный)
- [ ] `make authz-test-setup && make authz-test-run` — зелёным на стенде
- [ ] KAC-тикет заведён в YouTrack + `obsidian/kacho/KAC/KAC-N.md` (status, repos, PRs, acceptance checklist)
- [ ] KAC-125 DoD item "Newman cases for Invite (deferred)" — закрыт (cross-reference в KAC-125.md vault)
- [ ] Vault обновлён: `obsidian/kacho/edges/vpc-to-iam-check.md` + `compute-to-iam-check.md` + `iam-to-openfga-check.md` — добавить ссылку на authz-deny suite в "See also"
- [ ] 3 PR (vpc / iam / compute) + 1 PR (workspace) ссылаются на тикет

## 11. Out of scope

- Изменение `permission_map` в коде сервисов (если тест падает — отдельный KAC-bug, не правим в этом PR)
- CI-workflow для запуска (тесты должны просто работать на `./scripts/run.sh`)
- Тесты на NFR cache-invalidation / revoke ≤10s (E3 [[KAC-108]])
- production-strict mode тесты (Unauthenticated vs PermissionDenied) — отдельный variant
- positive happy-path для cluster-admin (нет такого subject в шестёрке)
- **PENDING-invitee flow** (User-row создан, но invitee ещё не активирован): subject не имеет JWT (external_id=''), поэтому тестировать его в матрице как самостоятельный subject бессмысленно. PENDING-state косвенно покрывается setup'ом (шаг 6б создаёт PENDING-row, который активируется на шаге 6в). Тест на «Invite → PENDING-row создан → возвращён magicLink» лежит в kacho-iam integration-tests (KAC-125 S-* сценарии), не дублируем в newman.
- **Invite-revoke / resend / cancel** (KAC-125 out-of-scope §0.2 — отложено) — нет API, нечего тестировать.
- **Cross-account invite где invitee уже active в другом Account** как separate scenario — частный случай уже покрыт INV (owner-of-B приглашён в A).
- **Bulk-invite** — нет API (KAC-125 §0.2).

## 12. Связанные сущности vault

- [[../../obsidian/kacho/edges/vpc-to-iam-check]] — vpc Check edge
- [[../../obsidian/kacho/edges/compute-to-iam-check]] — compute Check edge
- [[../../obsidian/kacho/edges/iam-to-openfga-check]] — iam → Keto/OpenFGA edge
- [[../../obsidian/kacho/rpc/iam-access-binding-service]] — AccessBinding RPC (setup использует)
- [[../../obsidian/kacho/rpc/iam-internal-user-service]] — InternalUserService.UpsertFromIdentity (setup использует)
- [[../../obsidian/kacho/resources/iam-access-binding]] — 5-tuple идемпотентность
- [[../../obsidian/kacho/KAC/KAC-108]] — per-RPC Check epic
- [[../../obsidian/kacho/KAC/KAC-119]] — bootstrap-admin matcher + cascade helper relationsImplying
- [[../../obsidian/kacho/KAC/KAC-120]] — vpc/compute Check active
- [[../../obsidian/kacho/KAC/KAC-123]] — Group default-deny + scope-filter pattern (reused for User.List)
- [[../../obsidian/kacho/KAC/KAC-125]] — User-per-Account + Invite-flow (этот PR закрывает её "Newman cases for Invite (deferred)" DoD-item)

#design #cross-repo #newman #authz #kacho-vpc #kacho-iam #kacho-compute
