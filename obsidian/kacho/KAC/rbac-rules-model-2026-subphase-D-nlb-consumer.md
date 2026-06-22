---
title: RBAC rules-model 2026 — sub-phase D (nlb consumer list-filter)
ticket_id: rbac-rules-model-2026-D-nlb-consumer
status: test
type: feature
repos:
  - kacho-nlb
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-workspace/issues/111
opened: 2026-06-21
tags:
  - kac
  - kacho-nlb
  - feature
  - authz
  - fga
  - usecase
  - repo
  - config
---

# RBAC rules-model 2026 — sub-phase D (nlb consumer list-filter)

**Status**: test (code-complete on branch `rbac-rules-d-consumer`, NOT committed/pushed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase D consumer-side — per-object filtered `List`, §11)
**Repos**: kacho-nlb (consumer). iam-core track = [[rbac-rules-model-2026-subphase-D-iam]].
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` (APPROVED раунд 2) — D-40..D-47 (LST-1..6), design §11
**Issue**: GitHub workspace [#111](https://github.com/PRO-Robotech/kacho-workspace/issues/111) (D-consumer; ≠ YouTrack KAC-111 vpc-squash)

## Что и зачем

nlb List-filter был **отсутствующим**: per-RPC interceptor помечал List RPCs `ScopeFiltered:true`
(только пропускал single Check), но НИКАКОГО per-object фильтра не было. Эта задача добавляет
parity (как compute): каждый публичный `List<Resource>` (networkLoadBalancers/listeners/targetGroups)
прогоняет id-set через `iam.AuthorizeService.ListObjects(subject, "loadbalancer.<res>.list", "lb_*")`
и отдаёт пересечение → видны ТОЛЬКО доступные объекты. read==enforce (та же relation, что Get-Check),
fail-closed (iam down → UNAVAILABLE), pagination ПОСЛЕ фильтра.

## Сделано (D, nlb consumer)

- **`internal/authzfilter/`** (новый пакет, зеркало `kacho-compute/internal/authzfilter`):
  `Filter` port + `FGAFilter` (TTL-cache 5s, fail-closed/open, `wildcard_grant`→bypass) +
  `BypassFilter` + `Config` + `iam_authorize_client.go` (`auth.PropagateOutgoing`) +
  `actions.go` (object-types `lb_*` + actions `loadbalancer.<res>.list`) + `subject.go`
  (`SubjectFromCtx` via `operations.PrincipalFromContext`+`domain.FGASubjectFromPrincipal`;
  `Resolve` — единый bypass/empty/fail-closed entry-point для всех 3 use-case'ов).
- **3 List use-cases** (`loadbalancer/list.go`, `targetgroup/list.go`, `listener/list.go`):
  принимают `authzfilter.Filter`, зовут `authzfilter.Resolve` → `filter.AllowedIDs`; empty grant
  → пустой response (no-leak); fail-closed Unavailable. Handlers threading `listFilter`.
- **repo per-object push-down** (`load_balancer_repo.go` / `target_group_repo.go` /
  `listener_repo.go` + 3 `entity_*.go` `AllowedIDs []string`): `WHERE id = ANY($::text[])`
  ВНУТРИ SQL ДО LIMIT → keyset плотный по отфильтрованному набору (D-46/LST-6); nil→bypass,
  len==0→0 rows (no-leak).
- **Get no-leak** (D-44): обеспечивается СУЩЕСТВУЮЩИМ per-RPC Check ([[../edges/nlb-to-iam-check]],
  relation viewer, `no-path`→404) — Get use-cases НЕ меняются (read==enforce — одна tuple-база).
- **config** (`authz.list-filter.{enabled,timeout,cache-ttl,cache-max-entries,fail-open}`,
  default enabled=true, fail-closed) + main.go `buildListFilter(cfg, iamPublicConn, …)` (reuse
  iam public conn — там AuthorizeService; mTLS via mtls.iam-project) → `peers.ListFilter`.
- **CI-гейт** `make audit-list-filter` (`tools/audit-list-filter.sh`) — каждый `<res>/list.go`
  обязан нести `authzfilter.Filter` + `authzfilter.Resolve(`.
- **deploy** (`deploy/templates/configmap.yaml` + `values.yaml` + `configmap-sample.yaml`):
  `authz.list-filter` block, helm-lint + render-guard зелёные.

## Затронутые сущности vault

- [[../edges/nlb-to-iam-listobjects]] — НОВОЕ ребро (по существующему iamPublicConn, не цикл)
- [[../rpc/nlb-network-load-balancer-service]] / [[../rpc/nlb-listener-service]] / [[../rpc/nlb-target-group-service]] — List теперь per-object filtered
- [[rbac-rules-model-2026-subphase-D-iam]] — iam-core поставляет ListObjects backend
- [[../edges/compute-to-iam-listobjects]] — паттерн-эталон consumer-side

## RED → GREEN proof

- **unit** (`{loadbalancer,targetgroup,listener}/list_filter_test.go`): RED — `internal/authzfilter`
  + 2-арг конструктор отсутствуют → GREEN. LST-3 global (only accessible), LST-2 byName,
  LST-5 empty-grant→[], D-47 fail-closed→Unavailable, bypass (admin/wildcard/nil/system).
- **integration** (`repo/kacho/pg/list_filter_integration_test.go`, testcontainers PG16, NOT -short,
  -p 1): RED — `AllowedIDs` field отсутствует → GREEN. LST-2 subset, empty→0 rows (no-leak),
  D-46 pagination-after-filter (3 dense pages of accessible, не raw), TG + Listener subset. (76s)
- **newman** (`tests/newman/cases/list-filter.py`, 4 D-cases): D-40/D-45 owner sees own NLB/TG in
  filtered List, D-44 Get absent→404-not-403 (no-leak), D-44 stranger→NLB not leaked. gen.py →
  `collections/list-filter.postman_collection.json` (4 cases); CASES-INDEX + validate-cases OK.

## DoD

- [x] `internal/authzfilter/` пакет (Filter/FGAFilter/BypassFilter/iam-client/actions/subject/Resolve)
- [x] 3 List use-cases per-object filter + repo `id=ANY` push-down (pagination-after-filter)
- [x] config `authz.list-filter.enabled` default true + main.go wiring (iamPublicConn) + deploy values
- [x] Get no-leak via existing per-RPC Check (read==enforce)
- [x] `make audit-list-filter` gate + Makefile target
- [x] RED→GREEN unit + integration (-p 1, non-short, colima) + newman gen
- [x] `go build ./...` + `go vet ./...` + gofmt + full unit (-short) green
- [ ] commit/push (НЕ делалось по инструкции)
- [ ] reviews: system-design (read==enforce/fail-closed), security (no-leak), go-style, db-architect
- [ ] **load-testing-coach gate (O-5)** перед prod-flip (общий с iam-core)

## Остаточные риски / follow-up

- **load gate O-5** — ListObjects cardinality на крупных наборах; общий с iam-core, не прогонялся.
- **AuthorizeService endpoint** — на iam PUBLIC listener (:9090); nlb reuse iamPublicConn. Если iam
  вынесет ListObjects на internal :9091 — поменять conn в `buildListFilter`.
- **ListOperations** — per-resource history, НЕ фильтруется per-object (op-id scope) — out of D scope.

#kac #kacho-nlb #feature #authz #fga
