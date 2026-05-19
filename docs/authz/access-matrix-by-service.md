# Kachō access matrix — по сервисам, ресурсам, CRUD, субъектам

**Тикет**: KAC-122 (YouTrack) / [`obsidian/kacho/KAC/KAC-122.md`](../../obsidian/kacho/KAC/KAC-122.md)
**Дизайн**: [`docs/superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md`](../superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md)
**Newman**: `project/kacho-{vpc,iam,compute}/tests/newman/cases/authz-deny.py` — 846 кейсов
**Bootstrap**: [`tests/authz-fixtures/setup.sh`](../../tests/authz-fixtures/setup.sh)

## 0. Шесть субъектов

| Code | Описание | external_id / `sub` JWT | Bindings (setup'ятся скриптом) |
|---|---|---|---|
| **ANON** | без `Authorization` | — | — |
| **NOB**  | authenticated, без role-bindings | `auth-test-no-bindings@example.com` | — |
| **PA1**  | project-admin (editor) на project-A1 | `auth-test-proj-admin-a1@example.com` | `vpc.editor`, `compute.editor`, `loadbalancer.editor` на project-A1 |
| **AAA**  | account-admin на account-A | `auth-test-account-admin-a@example.com` | `iam.admin` + `vpc.admin` + `compute.admin` + `lb.admin` на account-A |
| **AAB**  | account-admin на account-B | `auth-test-account-admin-b@example.com` | `iam.admin` + `vpc.admin` + `compute.admin` + `lb.admin` на account-B |
| **INV**  | invitee (owner-of-B, editor-на-project-A1 через `UserService.Invite`) | `auth-test-invitee@example.com` | All admin roles на account-B (его home) + editor на project-A1 (через invite) |

## 1. Семантика клеток

```
DENY    → HTTP 403 + grpc-code 7 (PERMISSION_DENIED) + body содержит "permission denied"
ALLOW   → HTTP != 403 (200/400/404 — приемлемо; нас интересует отсутствие PermissionDenied)
EMPTY   → HTTP 200 + body.users = [] (KAC-125 D-4: User.List scope-filter возвращает пустой
                                       список вместо 403 для users без membership)
N/A     → RPC не существует на этом сервисе / для этого ресурса
```

## 2. Общая матрица (resource-уровень)

```
Scope                         | ANON | NOB   | PA1   | AAA   | AAB   | INV
------------------------------+------+-------+-------+-------+-------+-------
project-A1 (account A)        | DENY | DENY  | ALLOW | ALLOW | DENY  | ALLOW
project-A2 (account A)        | DENY | DENY  | DENY  | ALLOW | DENY  | DENY
project-B1 (account B)        | DENY | DENY  | DENY  | DENY  | ALLOW | ALLOW
account-A (Account-level)     | DENY | DENY  | DENY  | ALLOW | DENY  | DENY
account-B (Account-level)     | DENY | DENY  | DENY  | DENY  | ALLOW | ALLOW
catalog-read (Zone/Region/…)  | DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW
catalog-mutate                | DENY | DENY  | DENY  | DENY  | DENY  | DENY
cluster-role-mutate           | DENY | DENY  | DENY  | DENY  | DENY  | DENY
addresspool-mutate            | DENY | DENY  | DENY  | DENY  | DENY  | DENY
```

## 3. Per-service / per-resource breakdown

### 3.1 kacho-vpc

`Project-scoped` ресурсы (`NetworkService`, `SubnetService`, `AddressService`, `RouteTableService`, `SecurityGroupService`, `GatewayService`, `PrivateEndpointService`, `NetworkInterfaceService`):

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `Create` в project-A1 | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `Create` в project-B1 | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `List?projectId=A1` | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `List?projectId=B1` | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `Get <id>` (в A1) | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `Update <id>` (в A1) | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `Delete <id>` (в A1) | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |

`AddressPool` (cluster-admin only через internal listener):

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `Create` | DENY | DENY | DENY | DENY | DENY | DENY |
| `Update` | DENY | DENY | DENY | DENY | DENY | DENY |
| `Delete` | DENY | DENY | DENY | DENY | DENY | DENY |

### 3.2 kacho-compute

Project-scoped ресурсы (`InstanceService`, `DiskService`, `ImageService`, `SnapshotService`) — та же таблица, что для VPC project-scoped.

Catalog ресурсы (`ZoneService`, `RegionService`, `DiskTypeService`) — read-only публично:

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `List` | DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW |
| `Get <id>` | DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW |
| `Create` (только на Internal/admin listener) | DENY | DENY | DENY | DENY | DENY | DENY |

### 3.3 kacho-iam

`AccountService`:

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `Get account-A` | DENY | DENY | DENY | ALLOW | DENY | DENY |
| `Get account-B` | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `Update account-A` | DENY | DENY | DENY | ALLOW | DENY | DENY |
| `List` | (scope-filter, как User.List) | | | | | |

`ProjectService`:

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `Create` в account-A | DENY | DENY | DENY | ALLOW | DENY | DENY |
| `Create` в account-B | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `Get project-A1` | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `Get project-B1` | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `Update project-A1` | DENY | DENY | ALLOW | ALLOW | DENY | ALLOW |
| `List ?accountId=A` | DENY | DENY | DENY | ALLOW | DENY | DENY |
| `List ?accountId=B` | DENY | DENY | DENY | DENY | ALLOW | ALLOW |

`GroupService`, `ServiceAccountService`, `AccessBindingService` — account-scoped, как `AccountService`.

`UserService`:

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `Get` user в account-A | DENY | DENY | DENY | ALLOW | DENY | ALLOW (INV — member of A) |
| `Get` user в account-B | DENY | DENY | DENY | DENY | ALLOW | ALLOW |
| `Update` user (own account) | DENY | DENY | DENY | ALLOW | ALLOW | ALLOW (для своей User-row) |
| **`List ?accountId=A`** | DENY | **EMPTY** | **EMPTY** | ALLOW | DENY | ALLOW |
| **`List ?accountId=B`** | DENY | **EMPTY** | **EMPTY** | DENY | ALLOW | ALLOW |
| **`Invite` в account-A** | DENY | DENY | DENY (project-level only) | **ALLOW** | DENY | DENY |
| **`Invite` в account-B** | DENY | DENY | DENY | DENY | **ALLOW** | **ALLOW** (owner of B) |

`RoleService`:

| RPC ↓ \ Subject → | ANON | NOB | PA1 | AAA | AAB | INV |
|---|---|---|---|---|---|---|
| `List` (catalog) | DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW |
| `Get` (system role) | DENY | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW |
| `Create`/`Update`/`Delete` | DENY | DENY | DENY | DENY | DENY | DENY |

## 4. Реальные результаты прогона (snapshot 2026-05-19)

### Условия

- Стенд: kind cluster, namespace `kacho`, `kacho-umbrella` chart.
- Все 6 субъектов создаются по `tests/authz-fixtures/setup.sh` через `InternalUserService.UpsertFromIdentity` (grpcurl), `AccountService.Create`, `ProjectService.Create`, `AccessBindingService.Create`.
- VPC + Compute authz-interceptor включён (`KACHO_VPC_AUTHZ__IAM_ENDPOINT=10.96.187.125:9091`).
- API-gateway патчен на ClusterIP-эндпоинты (in-cluster DNS на стенде нестабильно).

### Newman прогон (newman run authz-deny.postman_collection.json)

| Сервис | Кейсов | Assertions | Pass | Fail | Pass% |
|---|---|---|---|---|---|
| kacho-vpc | 354 | 910 | 304 | 606 | 33% |
| kacho-iam | 270 | 736 | 144 | 592 | 20% |
| kacho-compute | 222 | 560 | 212 | 348 | 38% |
| **Итого** | **846** | **2206** | **660** | **1546** | **30%** |

### Финдинги (root cause failures)

| # | Finding | Severity | Affected matrix cells |
|---|---|---|---|
| **F-1** | `InternalIAMService.Check` RPC **не реализован** на текущем образе kacho-iam (`ttl.sh/kac125d-1779140845/kacho-iam:24h`) — gRPC отвечает `Unimplemented method Check`. Это блокирует ВЕСЬ Keto-based authz: vpc/compute fail-closed → все запросы 403 при `breakglass=false`. С `breakglass=true` (применено сейчас) — bypass → все запросы 200 → DENY-кейсы краснеют. | Blocker | Все DENY-cells (~70% suite) |
| **F-2** | api-gateway dial via DNS таймаутит (CoreDNS upstream на стенде нестабильно). Workaround — патч deploy на ClusterIP-эндпоинты. | High | Setup, smoke |
| **F-3** | `KACHO_VPC_AUTHZ__IAM_ENDPOINT` не подставляется helm-chart'ом из `values.dev.yaml` `authz.iamEndpoint` — нужно вручную через `kubectl set env`. | Medium | Setup |
| **F-4** | `UserService.Invite` REST endpoint (`POST /iam/v1/users:invite`) возвращает 404 на api-gateway — KAC-125 proto не имеет `google.api.http` annotation либо restmux не зарегистрировал. | High | Все `invite-*` кейсы |
| **F-5** | Без working Check + cascade `owner > admin > editor`, реальную матрицу нельзя verify'нуть на этом стенде — нужен deploy kacho-iam c implemented `Check` + Keto-namespaces-config + outbox-drainer работает. | Blocker для DoD#2 (зелёный pipeline) | — |

### Что показал прогон

✅ **Инфраструктура тестов корректна** — 846 кейсов генерятся, выполняются, дают детерминированные результаты.
✅ **Setup идемпотентен** — re-run setup проходит без ошибок.
✅ **Anonymous request → правильное поведение в setup-фазе** (api-gateway инжектит `system:anonymous` principal).
✅ **JWT-flow работает** — bootstrap-admin token принимается, SubjectLookuper резолвит external_id `admin@prorobotech.ru` → User-row с `KACHO_IAM_BOOTSTRAP_ADMIN_EMAIL=@prorobotech.ru` matcher даёт админ-tuples.
❌ **Default-deny не enforce'ится** — текущий стенд НЕ соответствует ожидаемой матрице из-за F-1.

### Что нужно для зелёного pipeline (DoD #2)

1. Deploy kacho-iam image с реально implemented `InternalIAMService.Check` (или подтвердить, что KAC-125 закрытие включает это).
2. Очистить authz-config в helm chart (F-3) — env-var'ы должны рендериться из `values.yaml`.
3. Зарегистрировать `UserService.Invite` REST handler в `kacho-api-gateway/internal/restmux/` (F-4).
4. Verify Keto cascade `owner > admin > editor > viewer` работает (KAC-119 `relationsImplying` helper).
5. После того — `breakglass=false` + re-run suite → ожидаем ≥ 95% pass.

## 5. CI/CD integration

В каждом из трёх репо добавлен job `authz-deny-suite` в `.github/workflows/ci.yaml`:

```yaml
authz-deny-suite:
  name: authz-deny suite — generate + validate (KAC-122)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-python@v6
      with: { python-version: '3.12' }
    - name: generate authz-deny collection
      run: python3 tests/newman/scripts/gen.py authz-deny
    - name: assert collection non-empty (>= 200 cases)
      run: |
        n=$(python3 -c "import json; print(len(json.load(open('tests/newman/collections/authz-deny.postman_collection.json'))['item']))")
        echo "authz-deny cases: $n"
        test "$n" -ge 200
    - uses: actions/upload-artifact@v7
      with:
        name: authz-deny-collection
        path: tests/newman/collections/authz-deny.postman_collection.json
```

В `kacho-workspace/.github/workflows/ci.yaml` добавлен `authz-fixtures-lint`:
smoke-test JWT minter (HS256), patch-env validator, shellcheck setup.sh.

**Реальный newman прогон против стенда** — отдельный manual job (не on:push), запускается из `make authz-test-run` после `make authz-test-setup`. Включается в CI после фикса F-1 / F-3.

## 6. Run commands

```bash
# 1. Поднять port-forward'ы
kubectl port-forward -n kacho svc/api-gateway 18080:8080 &
kubectl port-forward -n kacho svc/kacho-iam-internal 19091:9091 &

# 2. Seed фикстуры
bash tests/authz-fixtures/setup.sh

# 3. Generate коллекции
python3 project/kacho-vpc/tests/newman/scripts/gen.py authz-deny
python3 project/kacho-iam/tests/newman/scripts/gen.py authz-deny
python3 project/kacho-compute/tests/newman/scripts/gen.py authz-deny

# 4. Run newman per service
for svc in kacho-vpc kacho-iam kacho-compute; do
  cd project/$svc/tests/newman
  newman run collections/authz-deny.postman_collection.json \
    -e environments/local.postman_environment.json \
    --reporters cli,json \
    --reporter-json-export out/authz-deny.json
  cd -
done
```

## 7. См. также

- Дизайн: [`docs/superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md`](../superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md)
- KAC-122 trail: [`obsidian/kacho/KAC/KAC-122.md`](../../obsidian/kacho/KAC/KAC-122.md)
- Vault edges: [`obsidian/kacho/edges/vpc-to-iam-check.md`](../../obsidian/kacho/edges/vpc-to-iam-check.md), [`compute-to-iam-check.md`](../../obsidian/kacho/edges/compute-to-iam-check.md), [`iam-to-openfga-check.md`](../../obsidian/kacho/edges/iam-to-openfga-check.md)
- KAC-104 IAM epic (родитель), KAC-108 per-RPC Check, KAC-119 cascade, KAC-120 vpc/compute Check active, KAC-123 default-deny scope-filter, KAC-125 Invite-flow
