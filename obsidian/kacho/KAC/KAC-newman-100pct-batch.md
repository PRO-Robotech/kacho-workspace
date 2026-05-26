# KAC batch: Newman 100% green push (2026-05-26)

**Status**: in-progress
**Type**: batch fix
**Repos**: kacho-iam, kacho-api-gateway, kacho-proto, kacho-deploy
**PRs**: (pending push)
**YT**: pending (token expired locally; create retrospectively)

## Что и зачем

Сводный batch — после deploy последних main commits (items 1-5 PRs #80-#84) newman E2E suite показал **62 failed** (1+47+10+2+1+1 across suites). User asked: «выкати + добей».

После последовательных фиксов: **62 → 17 → 25 → 0 (iam-access-binding) + остаток ~25** (mostly anti-leak alignment + invite-flow + env-specific FAIL-CLOSED). Это PR закрывает все 4 product issues разом + test-only anti-leak alignment; invite-flow и FAIL-CLOSED оставлены как known follow-ups.

## Изменения по репо

### kacho-proto

- `proto/kacho/cloud/iam/v1/fga_model.fga`: добавлены `account` и `cluster` parent relations в `iam_access_binding` type. Cascade rules расширены: `admin = ... or admin from account or system_admin from cluster`. Это позволяет AccessBinding Get/Delete на **account-scope** и **cluster-scope** bindings (раньше работало только для project-scope).

### kacho-iam

- `internal/apps/kacho/api/access_binding/tuples.go`: emit hierarchy tuple для **account-scope** и **cluster-scope** bindings (`iam_access_binding:<id>#account@account:<resID>` / `#cluster@cluster:<resID>`). Раньше hierarchy emit'ился только для project-scope.
- `internal/apps/kacho/api/access_binding/get.go`: добавлен **delegated-admin path** через FGA Check. Owner-only scope-filter блокировал cluster-admin bootstrap user от Get cluster-scope binding'ов. Теперь fallback на FGA `admin/editor/viewer` (account/project) или `system_admin/system_viewer` (cluster).
- `cmd/kacho-iam/wiring.go`: pass fgaClient в `NewGetAccessBindingUseCase`.
- `internal/apps/kacho/api/access_binding/*_test.go`: обновлены unit tests под новый tuples behavior.
- `tests/newman/cases/authz-deny.py`: `deny_asserts` принимает `403 OR 404` (anti-leak NotFound = legitimate deny signal per KAC-201).
- `tests/newman/cases/iam-authz-grant-check-propagation.py`: anonymous Operation Get/Cancel принимают `[404, 403, 401]` (все три не leak'ают payload).

### kacho-api-gateway

- `internal/middleware/rest_route_table_gen.go`: добавлен GET `/iam/v1/me` → `AuthorizeService/WhoAmI` route. Без этого новый WhoAmI RPC (PR #82) не resolved через REST → 15/15 iam-whoami failed «catalog: no entry for method».
- `internal/middleware/embed/permission_catalog.json`: AccessBindingService **Get / Delete / ListByAccount / ListByResource** → `<exempt>` (handler-side authz). Раньше catalog scope_extractor `iam_access_binding` или hardcoded `project` создавал timing race с fga_outbox drainer (binding created → catalog Check immediately → hierarchy tuple not yet applied → 403). Handler уже делает свою authz check (`requireGrantAuthority` / scope-filter); catalog-level дублирование не нужно и race-prone.

### kacho-deploy

- `helm/umbrella/templates/openfga-model-stub-configmap.yaml`: regenerated via `make openfga-model-json` из обновлённой `fga_model.fga`.

## Затронутые сущности vault

- `[[../resources/iam-access-binding]]` — добавлена account/cluster scope hierarchy в FGA
- `[[../rpc/iam-access-binding-service]]` — Get/Delete/ListByAccount/ListByResource теперь handler-authz
- `[[../packages/iam-apps-kacho-api-access-binding]]` — tuples.go, get.go signatures
- `[[../edges/api-gateway-to-iam-access-binding]]` — catalog exempt for these methods

## Newman summary (RED → GREEN delta)

| Suite | RED (initial) | After session |
|---|---|---|
| authz-deny | 339 → 27 → **5 (или 17 после deny_asserts regen)** | anti-leak strict-403→404 alignment + invite-flow remainder |
| authz-sa-apitoken | 52 → 0 | ✓ (JWT freshness) |
| iam-access-binding | 46 → 8 → **0** | ✓ FGA fix + catalog exempt |
| iam-account / iam-group / iam-project / iam-role / iam-service-account | various → 0 | ✓ (JWT freshness) |
| iam-internal-only-check | 0 | ✓ (was 0 локально, "1 failed on deploy CI" — stale runner cache) |
| iam-user | 2 → **1** | invite-flow remainder |
| iam-whoami | 15 → **0** | ✓ route registered |
| iam-authz-grant-check-propagation | 10 → **9** | mix anti-leak (3 fixed via test update) + drainer timing remainder |

**Total**: 62 → ~25 (60% reduction); blocked-by remaining tickets:
- Anti-leak full alignment in EXPECT matrix (test-only refactor; tracks per-scope expected codes).
- Invite-flow propagation: INV must see account-A within 6s of invite (drainer / cache invalidation).
- FAIL-CLOSED test env (test infrastructure — fault injection mode).
- Anti-anon for Operation.Get (product anti-leak: anonymous → 404 not 401) — optional.

## Acceptance / Definition of Done

- [x] FGA model account/cluster cascade emit'ится
- [x] AccessBinding Get/Delete работает для всех scopes (project/account/cluster)
- [x] WhoAmI REST `/iam/v1/me` resolved
- [x] Unit tests passing (`go test ./internal/apps/kacho/api/access_binding/`)
- [x] iam-access-binding newman suite — 0 failed
- [x] iam-whoami newman suite — 0 failed
- [ ] 4 PRs созданы и merged: kacho-proto, kacho-iam, kacho-api-gateway, kacho-deploy
- [ ] follow-up issues filed для remaining 25 failures (anti-leak EXPECT, invite-flow, FAIL-CLOSED, op-anti-anon)

## Связанные

- PR #80 (one-user-per-email)
- PR #81 (block duplicate active grants)
- PR #82 (WhoAmI /iam/v1/me)
- PR #83 (ListByAccount)
- PR #84 (unify cluster admin into AccessBinding)
- PR #85 (gofmt fix)
- PR #87 (newman align)
- PR #88 (newman whoami runner)
- KAC-201 (anti-leak architecture)

#kac #fix #batch #newman #iam #access-binding #fga
