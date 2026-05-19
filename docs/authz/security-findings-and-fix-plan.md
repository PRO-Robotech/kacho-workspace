# AuthZ Security Findings + Fix Plan (KAC-122 deep-dive)

**Дата**: 2026-05-19
**Тикет**: KAC-122 / [`obsidian/kacho/KAC/KAC-122.md`](../../obsidian/kacho/KAC/KAC-122.md)
**Связано**: [`access-matrix-by-service.md`](access-matrix-by-service.md) (исходная матрица), KAC-104 (IAM epic), KAC-108/119/120/125

> [!warning] tl;dr
> **Текущий dev-стенд Kachō фундаментально незащищён.** Anonymous user может: создать Account с
> произвольным owner, выдать себе iam.admin биндинг на чужой account, создавать VPC/Compute ресурсы
> в чужих project'ах, читать список ВСЕХ users системы. Полная авторизация отсутствует
> архитектурно в kacho-iam, выключена помехами в kacho-vpc/compute.

## 1. Что и где сломано — root causes

### RC-1 (kacho-iam): authz-interceptor АРХИТЕКТУРНО ОТСУТСТВУЕТ

`kacho-iam` НЕ имеет server-side authz-interceptor. Файл
`cmd/kacho-iam/main.go` подключает `OpenFGAStubClient` (`internal/clients/openfga_client.go`)
**только для одного use-case** — `UserService.Invite` (`internal/apps/kacho/api/user/invite.go:105`
зовёт `clients.CanInviteUsers`). **Остальные CRUD use-case'ы НЕ зовут Check вообще**.

```
                ┌─ Invite RPC ─────► CanInviteUsers (Keto cascade Check)
api-gateway ──► │
   (auth        ├─ Create Account ─► ❌ NO CHECK — anyone can create
    inject      ├─ Create Project ─► ❌ NO CHECK
    Principal)  ├─ Create Group   ─► ❌ NO CHECK
                ├─ Create SA      ─► ❌ NO CHECK
                ├─ Create AccessBinding ─► ❌ NO CHECK ← наиболее опасный: privilege escalation
                ├─ Create Role    ─► ❌ NO CHECK ← можно создать роль с любыми permissions
                ├─ Update/Delete всех ─► ❌ NO CHECK
                └─ List/Get       ─► partial scope-filter (см. RC-3)
```

**Где должен быть Check**: `internal/apps/kacho/api/*/create.go`, `update.go`, `delete.go` —
каждый use-case должен **в первом sync-шаге**, после извлечения `Principal` из ctx, вызывать
helper типа `CanXyz(ctx, principal, resource)` → `Check(subject, relation, object)` → fail-closed.

Аналогично compute/vpc (см. `internal/apps/kacho/check/factory.go` в vpc) — но там — interceptor;
тот же подход надо вынести в `kacho-iam`.

### RC-2 (kacho-vpc, kacho-compute): Check RPC не реализован в kacho-iam

В deployed kacho-iam image (`ttl.sh/kac125d-1779140845/kacho-iam:24h`) метод
`kacho.cloud.iam.v1.InternalIAMService/Check` **возвращает `Unimplemented`**:

```
err: rpc error: code = Unimplemented desc = method Check not implemented
```

vpc/compute interceptor (`internal/apps/kacho/check/check_client.go`) на этой ошибке делает
**fail-closed** → `PermissionDenied "authorization service unavailable"`. Что **выглядит**
правильно (все DENY), но это **side-effect** недоступности, а не реальное правило.

Поэтому на стенде сейчас включён `breakglass=true` → interceptor пропускает всё → `ALLOW
всё`. Это в точности **противоположно** требованию default-deny.

### RC-3 (kacho-iam reads): scope-filter частично работает

`Account.Get` / `Project.Get` / `Network.Get` / etc. возвращают `NotFound 404` для запросов
без membership. Это **корректное hide-existence** поведение, **но**:

- Bootstrap admin тоже получает 404 → значит `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL` matcher либо
  не настроен, либо tuples не записываются автоматически. Admin реально не может
  администрировать через REST.
- `Account.List` возвращает пустой массив всем (даже bootstrap-admin) — same root cause.
- `User.List` (БЕЗ `?accountId=`) — **возвращает СПИСОК ВСЕХ USERS** даже anonymous'у —
  фильтрация не применяется к unqualified List. **Data leak**.

### RC-4 (kacho-vpc admin endpoints): AddressPool публикован

`GET /vpc/v1/addressPools` отвечает **на dev port 18080 без Authorization** — anonymous видит
все AddressPool'ы с CIDR'ами. Per workspace CLAUDE.md §запрет 6 — это должно быть только на
internal listener. Текущая api-gateway конфигурация: один mux на оба listener'а (8080 plain
+ 8443 TLS), TLS не настроен → admin-paths exposed everywhere.

## 2. Confirmed CRITICAL findings (privilege escalation / data leak)

| # | Severity | Описание | Probe | Реальный response |
|---|---|---|---|---|
| **CRIT-1** | **CRITICAL** | Anonymous создаёт Account с произвольным `owner_user_id` | `POST /iam/v1/accounts` без `Authorization`, body содержит `ownerUserId: <any_user_id>` | `200 OK` + Operation + `accountId` |
| **CRIT-2** | **CRITICAL** | Anonymous выдаёт `iam.admin` биндинг на любой account → полное cluster admin без auth | `POST /iam/v1/accessBindings` без Authorization, body `{subjectType:user, subjectId:any, roleId:rol...iamad, resourceType:account, resourceId:any}` | `200 OK` + Operation. **Privilege escalation в один запрос** |
| **CRIT-3** | **CRITICAL** | Authenticated NOB user даёт себе `iam.admin` на чужой account | Same as above c `Authorization: Bearer <nob-jwt>` | `200 OK` |
| **CRIT-4** | **CRITICAL** | Anonymous создаёт Project в чужом Account | `POST /iam/v1/projects` без auth, body `{accountId: <victim>, name: hack-project}` | `200 OK` |
| **CRIT-5** | **CRITICAL** | Anonymous создаёт ServiceAccount в чужом Account → SA получает ключи через Token RPC → persistent backdoor | (не проверено, but extrapolation: same as CRIT-4) | (вероятно `200 OK`) |
| **CRIT-6** | **CRITICAL** | Anonymous создаёт VPC Network в чужом project (with `breakglass=true` на стенде) | `POST /vpc/v1/networks` без auth, body `{projectId: <victim>, name: x}` | `200 OK` + Operation |
| **CRIT-7** | **CRITICAL** | Anonymous создаёт Compute Disk/Instance/Image в чужом project (`breakglass=true`) | `POST /compute/v1/disks` без auth | `200 OK` |
| **HIGH-1** | **HIGH** | `GET /iam/v1/users` без `?accountId=` возвращает СПИСОК ВСЕХ users (email + external_id) даже anonymous'у | `curl /iam/v1/users` (no auth) | `200 OK` с массивом всех users |
| **HIGH-2** | **HIGH** | `GET /vpc/v1/addressPools` — admin-only ресурс открыт на public-listener | `curl /vpc/v1/addressPools` | `200 OK` с массивом AddressPool'ов |
| **HIGH-3** | **HIGH** | Anonymous может создать новую Role с произвольными permissions (например `["iam.*.*", "vpc.*.*"]`) → подкладка для CRIT-2 (использовать новую роль вместо встроенной) | (extrapolation; не проверено напрямую) | (вероятно `200 OK`) |
| **MED-1** | MEDIUM | Operation.principalType/Id/DisplayName в response пустые для anonymous → нет audit-trail кто создал. `createdBy: "anonymous"` — стандартный stub | `GET /operations/<op_id>` | `principalType:""`, `principalId:""` |
| **MED-2** | MEDIUM | Bootstrap-admin matcher `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL=@prorobotech.ru` не работает: bootstrap-admin не видит ни одного account даже через `GET /iam/v1/accounts`. Sign-up auto-create tuples скорее всего не пишутся в Keto/stub | `Authorization: Bearer <admin@prorobotech.ru-jwt>; GET /iam/v1/accounts` | `200 {"accounts": []}` |
| **MED-3** | MEDIUM | DNS resolution внутри cluster нестабилен — api-gateway/vpc/compute не могут дозваниваться по DNS-имени; ClusterIP workaround вручную через `kubectl set env` | `kubectl logs api-gateway`: `dns: A record lookup error: lookup kacho-iam.kacho.svc.cluster.local on 10.96.0.10:53: dial udp 10.96.0.10:53: i/o timeout` | — |
| **MED-4** | MEDIUM | helm chart `kacho-deploy` рендерит `authz.iamEndpoint` в `config.yaml`, но env-var'ы `KACHO_VPC_AUTHZ__IAM_ENDPOINT` не выставляются. В итоге config-file не подхватывается viper'ом из values, нужен ручной env-override | `kubectl exec vpc -- cat /etc/kacho-vpc/config.yaml` — нет блока authz | — |
| **LOW-1** | LOW | `POST /iam/v1/users:invite` возвращает `404 Not Found` на api-gateway — REST-маппинг не зарегистрирован для UserService.Invite (новый KAC-125 RPC) | `POST /iam/v1/users:invite` | `404` |

## 3. Реальная (observed) матрица доступов на стенде

С `breakglass=true` (текущее состояние стенда для unblock setup):

```
Resource RPC                  | ANON   | NOB    | PA1    | AAA    | AAB    | INV
==============================+========+========+========+========+========+========
[KACHO-IAM]
Account.Create                | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← должно DENY все кроме AAA/AAB (для своего)
Account.Get                   | 404    | 404    | 404    | 404    | 404    | 404     ← 404 для всех; bootstrap-admin тоже не видит
Account.List                  | empty  | empty  | empty  | empty  | empty  | empty   ← пустой для всех
Account.Update                | 404    | 404    | 404    | 404    | 404    | 404
Project.Create                | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← должно DENY кроме AAA/AAB/INV(для своего acct)
Project.Get                   | 404    | 404    | 404    | 404    | 404    | 404
Group.Create                  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← privilege escalation
ServiceAccount.Create         | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← persistent backdoor
AccessBinding.Create          | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← ПРИВИЛЕГИРОВАННАЯ ОПЕРАЦИЯ open
Role.Create (custom)          | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← создание ролей с произвольными permissions
User.List (unqualified)       | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← ВЫДАЁТ ВСЕХ USERS (data leak)
User.List ?accountId=         | empty  | empty  | empty  | empty  | empty  | empty   ← scope-filter работает только если accountId передан
User.Invite                   | 404    | 404    | 404    | 404    | 404    | 404     ← REST endpoint не зарегистрирован

[KACHO-VPC]
Network.Create (any project)  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← breakglass open
Network.Get                   | 404    | 404    | 404    | 404    | 404    | 404
AddressPool.List              | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← admin endpoint открыт публично

[KACHO-COMPUTE]
Disk.Create (any project)     | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW
Instance.Create               | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW
Zone.List (catalog)           | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW  | ALLOW   ← correct
```

С `breakglass=false` (proper config, RC-2 в действии):

```
Resource RPC                  | ANON   | NOB    | PA1    | AAA    | AAB    | INV
==============================+========+========+========+========+========+========
[KACHO-VPC, KACHO-COMPUTE]    | DENY   | DENY   | DENY   | DENY   | DENY   | DENY  ← все DENY из-за Check Unimplemented
[KACHO-IAM]                   | (same as above — нет interceptor; всё ALLOW)
```

## 4. Fix Plan — что починить и в каком порядке

### Phase 1 — Critical (CRIT-1..CRIT-7): authz enforce в kacho-iam

**Цель**: anonymous и unauthorized user'ы не могут писать в IAM-домен.

| Шаг | Действие | Файлы |
|---|---|---|
| 1.1 | Реализовать `authz.UnaryInterceptor` для kacho-iam analogous к `kacho-vpc/internal/apps/kacho/check/factory.go` — но с self-referential Check (kacho-iam.IAM.Check к самому себе) либо через локальный Keto-client | `kacho-iam/internal/check/`, `cmd/kacho-iam/main.go` |
| 1.2 | Добавить permission_map для всех 7 ресурсов: AccountService, ProjectService, GroupService, ServiceAccountService, UserService, RoleService, AccessBindingService (каждый RPC → relation+object_type+object_extractor) | `kacho-iam/internal/check/permission_map.go` |
| 1.3 | **CRIT-2 specific**: на `AccessBinding.Create` — добавить **дополнительную** проверку «выдающий не может выдать роль выше своей» (prevent escalation: editor не может grant'ить admin) | `kacho-iam/internal/apps/kacho/api/accessbinding/create.go` |
| 1.4 | **CRIT-1 specific**: на `Account.Create` — добавить проверку «sub claim в JWT === ownerUserId.external_id, либо principal=cluster-admin» (anti-hijacking) | `kacho-iam/internal/apps/kacho/api/account/create.go` |
| 1.5 | Интеграция-тест: testcontainers + concurrent goroutines пытающиеся CreateAccessBinding c admin-role без бэкграунд-прав | `kacho-iam/internal/apps/kacho/api/accessbinding/integration_test.go` |

### Phase 2 — High (CRIT-6/7, HIGH-1, HIGH-2, RC-2/3/4)

| Шаг | Действие | Файлы |
|---|---|---|
| 2.1 | Реализовать `InternalIAMService.Check` в kacho-iam (сейчас Unimplemented) — поверх Keto или openfga-stub | `kacho-iam/internal/apps/kacho/api/iaminternal/check.go` |
| 2.2 | На `User.List` (unqualified) — обязать `accountId` либо `IsClusterAdmin(principal)`; default-scope-filter | `kacho-iam/internal/apps/kacho/api/user/list.go` |
| 2.3 | API-gateway split listener'ов: external TLS `:8443` без admin-paths; cluster-internal `:8080` со всеми | `kacho-api-gateway/internal/restmux/admin_filter.go` (новый middleware) |
| 2.4 | `helm chart` — рендерить env-var'ы `KACHO_VPC_AUTHZ__IAM_ENDPOINT` из `values.yaml authz.iamEndpoint` | `kacho-deploy/helm/.../templates/vpc-deployment.yaml` |

### Phase 3 — Medium (MED-1..MED-4)

| Шаг | Действие | Файлы |
|---|---|---|
| 3.1 | MED-1: Operation.principal_* поля заполнять из ctx, даже для anonymous (тогда `principalType=system`, `principalId=anonymous`) | `kacho-corelib/operations/repo.go` |
| 3.2 | MED-2: bootstrap-admin matcher — записывать tuples при Keto-bootstrap либо writeIfNotExists на каждом Check pre-flight | `kacho-iam/internal/apps/kacho/jobs/keto_bootstrap_drainer.go` |
| 3.3 | MED-3: CoreDNS upstream timeout — debugging (отдельный ops-тикет, не блокер для authz) | k8s ops |
| 3.4 | MED-4: helm authz config rendering | `kacho-deploy/helm/...` |

### Phase 4 — Low (LOW-1)

| Шаг | Действие | Файлы |
|---|---|---|
| 4.1 | Зарегистрировать `UserService.Invite` REST-handler в `kacho-api-gateway/internal/restmux/mux.go` (KAC-125 proto добавила RPC, REST mapping забыт) | `kacho-api-gateway/internal/restmux/mux.go` |

### Phase 5 — Tests (на каждый fix)

После каждой фазы — пере-запустить authz-deny suite и сверять с матрицей. Цель: 95%+ pass-rate
с `breakglass=false`, без хаков.

## 5. Test gaps — что мы НЕ покрываем (predлагается дополнить)

Текущая suite (846 кейсов) покрывает 6 «классов субъектов» × CRUD × ресурсы. Не покрыты:

### 5.1 Привилегированные роли (subject-types)

| Класс | Описание | Что проверять | Тестов сейчас |
|---|---|---|---|
| **CLU-ADM** | Cluster-admin (sub claim — bootstrap-matcher email) | Может ВСЁ — global mutations, root infrastructure | 0 |
| **PV** | Project-viewer (только Get/List в одном project) | Read OK, write DENY | 0 (PA1 — editor, не viewer) |
| **PE** | Project-editor | Write в своих project, DENY на cross | частично PA1 |
| **AV** | Account-viewer | List projects в account, write DENY | 0 |
| **CA-EDIT** | Cloud-editor (synonym для account-editor; legacy term) | === AE | 0 |
| **SA** | ServiceAccount (key-auth, JWT signed с другим ключом) | Same as user, но Principal.type=service_account | 0 |
| **INV-PND** | Invitee в PENDING state (не активирован) | Не должен иметь права | 0 |
| **GROUP-MEM** | User добавлен в Group, у Group есть binding | Cascade subjectType=group | 0 |

### 5.2 Edge cases / privilege escalation

| Класс | Описание | Текст кейса |
|---|---|---|
| **ESC-1** | NOB grants himself admin via AccessBinding.Create | `POST /iam/v1/accessBindings` с subjectId=self, roleId=iamad → должно DENY |
| **ESC-2** | Project-editor создаёт custom Role с iam.\*.\* permissions → даёт себе бы → DENY на role create или DENY на permissions content |
| **ESC-3** | Виctim account-admin transfers Account.owner_user_id на attacker — должно immutable hard-reject; даже cluster-admin не делает silent transfer |
| **ESC-4** | Account.Update меняет owner_user_id (sneaky update) — проверить immutable enforcement |
| **ESC-5** | NOB creates Account с owner=attacker → захват tenant'а (CRIT-1) |
| **ESC-6** | NOB creates Project в чужом Account (CRIT-4) → tenant pollution |
| **ESC-7** | INV creates Project в его home-account-B без admin-роли (только editor на A1) → проверить что editor на project не cascade'ится в account-level write |

### 5.3 Information disclosure

| Класс | Описание | Проверка |
|---|---|---|
| **INFO-1** | Get-by-id чужого ресурса — DENY должен быть **NotFound 404** (не 403, чтобы не leak existence). Сейчас → 404 ✅. **Тест**: убедиться что timing 404 неотличим от настоящего 404 (anti-timing-attack) |
| **INFO-2** | Get/List with substring-filter — не должен leak'ать chunked-result count |
| **INFO-3** | Operation.metadata — не должно содержать инфо чужого ресурса |
| **INFO-4** | error-message — не leak'ает имя ресурса в чужом scope (`"Project foo-prj-victim already exists"` → leak о существовании foo-prj) |
| **INFO-5** | `User.List` без `accountId` → 403 / scope-filter, не 200+ALL (HIGH-1) |

### 5.4 Cross-domain runtime cascade

| Класс | Описание | Проверка |
|---|---|---|
| **CD-1** | Compute.Instance.Create с `subnet_id` из VPC чужого account → должен DENY (vpcClient.Subnet.Get → проверяет membership проверяющего, не subnet owner'а) |
| **CD-2** | NLB.TargetGroup с target=инстанс чужого project → DENY |
| **CD-3** | AccessBinding.resource_id = чужой Folder/Project — DENY на validation peer-call |

### 5.5 Token-level

| Класс | Описание | Проверка |
|---|---|---|
| **TOK-1** | Expired JWT (`exp < now`) → 401 Unauthenticated, не 403 |
| **TOK-2** | Malformed JWT → 401 |
| **TOK-3** | JWT signed wrong secret → 401 |
| **TOK-4** | JWT с sub несуществующего user'а → 401 (production-strict) / fallback anonymous (dev) |
| **TOK-5** | JWT с sub чужого user'а (forged) → нужно подпись + revocation check |
| **TOK-6** | ServiceAccount-key authentication (PEM-signed JWT, не HS256) — pending KAC после ServiceAccount.CreateKey RPC |

### 5.6 Internal-vs-external isolation (workspace CLAUDE.md §запрет 6)

| Класс | Описание | Проверка |
|---|---|---|
| **ISO-1** | `InternalIAMService.*` (Check, LookupSubject, UpsertFromIdentity) на external TLS endpoint → 404 |
| **ISO-2** | `InternalUserService.*` на external → 404 |
| **ISO-3** | `InternalAddressPoolService` / `InternalRegionService` / etc. на external → 404 |
| **ISO-4** | Inverse: same RPC на internal listener → 200 (positive control) |

### 5.7 Rate limiting / DoS

| Класс | Описание | Проверка |
|---|---|---|
| **RL-1** | Anonymous → rate-limited после N requests/sec (deny-storm protection — corelib `DenyRateLimitPerSec`) |
| **RL-2** | Same user N parallel concurrent requests — нет escalation race |

### 5.8 Concurrency / TOCTOU

| Класс | Описание | Проверка |
|---|---|---|
| **TOC-1** | 2 concurrent CreateAccessBinding для same 5-tuple → должны вернуть один и тот же id (idempotency KAC-112 §13.4) |
| **TOC-2** | Race: AAA revokes admin from NOB | NOB simultaneously создаёт ресурс — должен либо ALLOW (revoke не докатился), либо DENY (атомарно после revoke) |
| **TOC-3** | Project.Move + concurrent AccessBinding на старом resource_id (binding должен mu update'нуться либо stale-binding cleanup) |

## 6. Что планирую добавить в authz-deny.py (next iteration)

| Файл | Новые кейсы | Total cases новый |
|---|---|---|
| `kacho-iam/cases/authz-deny.py` | ESC-1..ESC-7 (privilege escalation), INFO-1/4/5, TOK-1..TOK-4, ISO-1..ISO-4 | 270 → ~400 |
| `kacho-vpc/cases/authz-deny.py` | ESC-2 (custom role), CD-1, INFO-3, ISO-3, RL-1 | 354 → ~430 |
| `kacho-compute/cases/authz-deny.py` | CD-1/2/3, INFO-3, TOK-1..TOK-4 (per-RPC) | 222 → ~330 |

## 7. Timeline

- **Phase 1** (authz-interceptor в kacho-iam) — ~2-3 PR в kacho-iam, ~2 недели dev. Это работа уровня KAC-126.
- **Phase 2** (`InternalIAMService.Check`, User.List scope-filter, api-gateway split, helm) — ~1 неделя.
- **Phase 3-5** — ~1 неделя.
- **Test extensions** (5.1-5.8) — ~3 дня после Phase 1-2 (без implemented authz тесты бессмысленны).

## 8. См. также

- [`access-matrix-by-service.md`](access-matrix-by-service.md) — original (intended) матрица
- [`docs/superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md`](../superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md) — дизайн
- [`obsidian/kacho/KAC/KAC-122.md`](../../obsidian/kacho/KAC/KAC-122.md) — trail
- Vault edges: [`vpc-to-iam-check.md`](../../obsidian/kacho/edges/vpc-to-iam-check.md), [`compute-to-iam-check.md`](../../obsidian/kacho/edges/compute-to-iam-check.md), [`iam-to-openfga-check.md`](../../obsidian/kacho/edges/iam-to-openfga-check.md)
