# authz-deny suite — shared fixtures (KAC-122)

Idempotent bootstrap для 6-субъектной authz-deny newman suite. Pre-creates
Account / Project / User / AccessBinding и активирует invitee через KAC-125
invite-flow.

## Quick start

```bash
# 1. Port-forward api-gateway → localhost:18080
kubectl port-forward -n kacho svc/api-gateway 18080:8080 &

# 2. Run setup (idempotent; re-run safe)
bash tests/authz-fixtures/setup.sh

# 3. Run newman per service
cd project/kacho-iam/tests/newman    && ./scripts/run.sh --service authz-deny
cd project/kacho-vpc/tests/newman    && ./scripts/run.sh --service authz-deny
cd project/kacho-compute/tests/newman && ./scripts/run.sh --service authz-deny
```

## Environment knobs

| Env-var | Default | Назначение |
|---|---|---|
| `BASE_URL` | `http://localhost:18080` | api-gateway dev-listener |
| `DEV_SECRET` | `kacho-dev-jwt-secret-2026` | HMAC-secret HS256 (`KACHO_API_GATEWAY_AUTHN_DEV_SECRET` на стенде) |
| `EXP_HOURS` | `24` | exp claim в JWT |
| `OUT_DIR` | `tests/authz-fixtures/out` | куда писать `authz-fixtures.json` + `jwts.json` |
| `PATCH_ENV` | `true` | патчить ли `environments/local.postman_environment.json` всех 3 newman-suite'ов |
| `VERBOSE` | `false` | echo каждый curl |

## Что создаётся (минимум)

- 6 users (bootstrap-admin + 5 test users + invitee) через `InternalUserService.UpsertFromIdentity`
- 2 accounts (`authz-test-A`, `authz-test-B`)
- 3 projects (`authz-test-A1`, `authz-test-A2` в account-A; `authz-test-B1` в account-B)
- 4 access bindings:
  - editor on project-A1 → user-PA1
  - admin on account-A → user-AAA
  - admin on account-B → user-AAB
  - owner on account-B → user-INV (его home)
- INV invite в account-A как editor on project-A1 (через `UserService.Invite`, потом активация через повторный UpsertFromIdentity)
- 2 seed networks (для GET-проб): `authz-seed-net-a1` в project-A1, `authz-seed-net-b1` в project-B1

## Идемпотентность

- `UpsertFromIdentity` — by design KAC-125 (ON CONFLICT external_id+account)
- `AccessBinding.Create` — 5-tuple dedup (KAC-112 §13.4)
- `Account/Project.Create` — find-by-name + skip если уже есть
- `UserService.Invite` — KAC-125 ON CONFLICT (PENDING-row reuse по email)

Re-run setup безопасен; ID'ы стабильны между запусками.

## Что НЕ делает

- НЕ удаляет фикстуры после прогона newman (для скорости re-runs)
- НЕ trash'ит существующие данные другого назначения

См. design: [`docs/superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md`](../../docs/superpowers/specs/2026-05-19-authz-default-deny-matrix-newman-design.md).
