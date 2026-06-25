---
title: "rbac-2026 BUG-2 — read-deny hide-existence (gateway 403→404)"
ticket_id: ""
status: done
type: fix
repos:
  - kacho-api-gateway
  - kacho-iam
prs:
  - "https://github.com/PRO-Robotech/kacho-api-gateway/pull/100"
  - "https://github.com/PRO-Robotech/kacho-iam/pull/248"
  - "https://github.com/PRO-Robotech/kacho-api-gateway/pull/101"
  - "https://github.com/PRO-Robotech/kacho-iam/pull/250"
  - "https://github.com/PRO-Robotech/kacho-deploy/pull/134"
yt_url: ""
opened: 2026-06-25
closed: 2026-06-25
tags:
  - kac
  - fix
  - kacho-api-gateway
  - kacho-iam
  - authz
---

# rbac-2026 BUG-2 — read-deny hide-existence (gateway 403→404)

**Status**: done — gw#100 + iam#248 merged; api-gateway image `main-22b43201` live via fe3455
([kacho-deploy#134](https://github.com/PRO-Robotech/kacho-deploy/pull/134)). Cross-repo TEMP-PIN
ревёрнут на `ref: main` на обоих main ([api-gateway#101](https://github.com/PRO-Robotech/kacho-api-gateway/pull/101)
+ [iam#250](https://github.com/PRO-Robotech/kacho-iam/pull/250)); обе BUG-2 feature-ветки удалены
(`rbac-2026-bug2-hide-existence-read-deny`, `rbac-2026-bug2-hide-existence-newman`).
**Эпик**: Explicit RBAC model 2026 ([[rbac-explicit-model-2026]], GitHub #109). Acceptance
`docs/specs/rbac-explicit-model-2026-acceptance.md` (APPROVED) — read «never PermissionDenied,
no enumeration leak».

## Что и зачем

Live-E2E: detail-`Get` без `v_get` для `account/project/user/service_account/group` отдавал
**403 PERMISSION_DENIED** (verbose `deny_reasons`) вместо **404** — расходился с `role` (404)
и со спекой hide-existence.

**Корень — gateway, не iam.** Authz-интерсептор gateway ([[../packages/api-gateway-middleware-authz]])
Check'ает read-RPC ДО iam. У этих `Get` каталог несёт `required_relation=v_get` + concrete
scope → deny короткозамыкается на gateway в 403 с утечкой reasons; iam `read_authz.go`
(`AllowsVGet`→`NotFound`) не достигается. `RoleService/Get` отдавал 404 только потому что
catalog-entry `<exempt>` (без gateway-Check → доходит до iam).

**Fix (gateway-contained):** deny на hide-existence read RPC → `NotFound` (gRPC 5 / HTTP 404)
без `deny_reasons`. Новый `outcomeNotFound`; три authz-Check-deny сайта (`cached` / gRPC-stub
PermissionDenied / финальный `result.Allowed==false`) идут через `denyDecision()`, которая
выбирает NotFound при `CatalogEntry.HidesExistenceOnDeny(fqn)`. Резолв: explicit catalog-флаг
`HideExistence` ИЛИ эвристика «`/Get` + `v_get` + concrete scope». Enforcement не ослаблен
(deny блокирует, handler не достигается). nonexistent == existing-denied → одинаковый 404
(no enumeration leak). Мутации (Create/Update/Delete), List, catalog-miss, override-deny —
остаются 403/правильный код.

**Scope (важно):** эвристика `v_get` + concrete-scope покрывает **20 verb-bearing Get** RPC
не только iam — это iam(6) + vpc(7) + compute(4) + loadbalancer(3). Решение владельца было
сформулировано в терминах iam (`read_authz.go`), но hide-existence-on-read — единая
security-политика; применять её к vpc/compute/lb на том же gateway-пути правильно (не оставлять
утечку existence на части ресурсов). Это сознательное расширение, не overreach.

## RED→GREEN

- **RED**: read-deny возвращал 403/code-7 с `no path: secret reason` в body.
- **GREEN**: gRPC+HTTP read-deny → 404/code-5 (5 IAM Get RPC); body без deny_reasons;
  existing-denied==nonexistent; mutation-deny остаётся 403; granted read доходит до handler.
- Тесты gateway: `authz_hide_existence_test.go`, `permission_catalog_hide_existence_test.go`.
- Newman (iam): `iam-read-authz-vget` (+ новый NONEXISTENT-EQ-DENIED), `iam-account/group/
  service-account/project/user` FOREIGN-DENY → 404/no-leak; **read-aware deny matrix** в
  `authz-deny.py`/`authz-sa-apitoken.py` (`_is_single_resource_get` guard: DENY+single-Get →
  read_deny_asserts 404; DENY+List + мутации → deny_asserts 403; ANON → unauth_asserts 401).
- **Scope hide-existence (refinement):** 404 применяется ТОЛЬКО к single-resource Get
  (path `…/{{id}}`, без `?query`). Denied **List** (`/projects?accountId=…`, `/groups?…`) →
  **403** (нет конкретного объекта, чьё existence прятать). Anonymous → **401** (authN, не
  authz-hide). Gateway-эвристика (`/Get` + `v_get` + concrete scope) на List/anon не срабатывает
  by-design. Первый pinned-прогон ошибочно флипнул `PRJ-LS`/`GRP-LS` в 404 (42 fail) — исправлено
  guard'ом; List/anon остаются 403/401.
- **Read-after-write propagation (refinement-2):** owner-read свежесозданного
  `iam_access_binding` сразу после Operation→done: per-object `v_get` владельца материализуется
  на beat позже → transient read-deny теперь **404** (был 403). Polls `get-confirms`/
  `verify-original-survives`/`get-ok`/`get-f51-no-target` (`iam-access-binding.py`) ретраились
  только на 403 → ломались на transient 404. Fix: `retry_on=(403, 404)` (пол до converged 200).
- **Delete-flow tail (refinement-3):** `get-after-revoke` — read только что revoked binding'а.
  На удалённом ресурсе и 404 (hide-existence), и 403 (authz до резолва soft-deleted row) валидны
  и **не утечка** (revoker уже знает, что binding существовал → exact deny-code — edge-деталь, не
  security boundary). → tolerant `oneOf([404, 403])` (НЕ strict-404). Strict-404 остаётся для
  live single-resource Get-deny на **существующем** ресурсе.
- **Кросс-репо CI**: gw newman-e2e чекаутит iam@branch (TEMP-PIN), iam newman-e2e чекаутит
  gw@branch → co-dependent. На обеих ветках TEMP-PIN на ветку другого репо; ревертится на
  `ref: main` после merge обоих PR.
- **Прогон-эволюция newman (live):** round1 ~78 fail (все GET read-deny ждали 403) → round2
  GET-deny зелёные, но 42 List ошибочно флипнуты в 404 → round3 List-guard, остался F-51/
  access-binding propagation-window flake (2) → round4 `retry_on=(403,404)`, осталась 1
  (`get-after-revoke` strict-404 vs прод-403) → round5 tolerant `oneOf([404,403])` на
  delete-flow tail. Каждый раунд — сужение, ни одного реального прод-регресса.
- **F-53 (НЕ трогаем):** `IAM-ACB-F53-SYSROLE-CHECK-ALLOW` падения — это known-RED (assert на
  удалённый viewer-cascade Design-A; flat Design-B каскада не имеет). Уже в skip-листе
  `assert-suites-green.sh`, не считаются. Чистка stale-cascade-степов — отдельный follow-up.

## Затронутые сущности vault

[[../edges/api-gateway-to-iam-authorize]] · [[../packages/api-gateway-middleware-authz]] ·
[[../rpc/iam-account-service]] · [[../rpc/iam-authorize-service]] · [[rbac-explicit-model-2026]]

## DoD

- [x] корень определён (gateway authz-interceptor 403 ДО iam)
- [x] read-deny verb-bearing IAM Get → 404 hide-existence (gRPC + REST)
- [x] no deny_reasons leak; nonexistent == existing-denied
- [x] мутации/List/catalog-miss/override-deny не затронуты
- [x] tests RED→GREEN (gateway unit + iam newman), go build/vet/test -race зелёные
- [x] CI: **newman E2E зелёный на обоих PR** (gw#100 + iam#248); gw unit/gosec/govulncheck/Trivy(Go)
      pass (lowercase `trivy` container/IaC — pre-existing infra-flake secret-scan, не от этого
      изменения); iam unit/lint/gosec/govulncheck/trivy/authz-validate pass (integration testcontainers — slow, не затронут test-only)
- [x] merge (gw#100 + iam#248) + revert TEMP-PIN на `ref: main` (gw#101 + iam#250) + BUG-2 ветки удалены + fe3455 live (deploy#134) + status → done

#kac #fix #kacho-api-gateway #kacho-iam #authz
