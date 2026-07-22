---
title: "[trail] RG-1 — Registry Repository config-overlay + visibility + referrers"
aliases:
  - sub-phase-RG-1
  - RG-1-repository-overlay
ticket_id: RG-1-registry-repository-overlay
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
  - kacho-registry
  - kacho-iam
  - kacho-api-gateway
prs:
  - "PRO-Robotech/kacho-registry#43 (persistence + use-case/handler slice)"
  - "PRO-Robotech/kacho-proto#8 (proto: Repository overlay + Visibility + Referrer + 6 RPC)"
yt_url: ""
opened: 2026-07-15
closed: ""
tags:
  - kac
  - feature
  - kacho-registry
  - kacho-proto
---

# RG-1 — Registry Repository config-overlay

Эпик: kacho-workspace#132. Acceptance: `docs/specs/sub-phase-RG-1-registry-repository-overlay-acceptance.md`
(✅ APPROVED r2). Cross-repo порядок: proto → iam → registry → api-gateway → deploy → docs.

## Что и зачем

Вводит **config-overlay первого класса** над OCI-репозиторием (DB-owned строка
`repository_configs`, натуральный ключ `(registry_id, name)`), переживающую пустой repo, +
явные lifecycle-мутации (Create/Update/Delete/Rename), `visibility{PRIVATE|PUBLIC}` с
anonymous-pull, и read-проекцию `ListReferrers`. Overlay ⟂ projection, не ломает
register-on-first-push / unregister-on-last-tag.

## Срезы (status)

- **proto** (kacho-proto#8) — Repository overlay-поля + Visibility enum + Referrer + 6 RPC +
  `Registry.default_visibility`. **done** (feat-ветка, consumed via go.work).
- **registry persistence** (#43 slice 1) — migration 0005 + domain + `RepositoryConfigRepo` pgx. **done**.
- **registry use-case/handler** (#43 slice 2, commit `830a2c7`) — 6 RPC end-to-end + ACTIVE-guard
  tx + outbox owner/public-grant + admin-gate + existence-hiding + rename fail-closed + List union +
  zot adapter (projection/empty/rename/referrers) + tests (unit+integration+newman). **done (this slice)**.
- **iam anon-path (issuance)** — anon-token issuance (B13/B14) + FGA `user:*` v_get governance +
  permission-catalog. **done** (kacho-iam #325 `ExecuteAnonymous`/`user:*`; kacho-deploy #172 FGA model).
- **registry data-plane anon (consumption)** (#43 slice 3, commit `be7e1c9`) — VALID anon Bearer
  (sub == configured `AnonymousSubjectID`) → FGA `user:*` (`domain.FGASubjectForPrincipalID` +
  `Handler.WithAnonymousSubject`); PUBLIC pull 200 (B03), PRIVATE/absent uniform 404 byte-identical
  (B04/B05, no existence-oracle), no-token push 401 (B07a), anon-token push 403 DENIED (B07b/B14).
  Verb-per-route model unchanged. Config `KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID` (default "" = disabled).
  Tests: domain rule table + handler-level (subject-aware authz). **done (this slice)**.
- **api-gateway** — регистрация 6 public RPC (public-mux). **DEFER (api-gateway-registrar-срез)**.
- **deploy/docs** — anon-token config; docs-site + flip acceptance. **pending**.

## Затронутые сущности vault

- [[resources/registry-repository]] — новый ресурс (overlay⟂projection, natural-key, visibility, lifecycle).
- rpc/registry-registry-service — 6 новых RPC (создать при docs-срезе).
- [[edges/registry-to-iam-anon-public]] — anon-token issuance + data-plane `user:*` consumption.

## DoD-чеклист

- [x] proto stubs (kacho-proto#8) consumed via go.work.
- [x] use-case + thin handler для 6 RPC (RED→GREEN).
- [x] ACTIVE-guard (A24) + transactional-outbox (adopt-owner + user:* public-grant, X03).
- [x] admin-gate any-path-to-PUBLIC (B02/B08/B10/B11), existence-hiding (A08/C02/A15), X04.
- [x] reject-if-tags (A14) + rename fail-closed (A21) + ephemeral auto-promote (A23).
- [x] List overlay ⊔ projection union (A20); INTERNAL-no-leak (X02); payload-bounds (A22).
- [x] tests: use-case unit + handler unit + integration (guard/outbox/races) + newman (13 cases).
- [x] iam anon-token issuance (B13/B14) — kacho-iam #325; FGA `user:*` model — kacho-deploy #172.
- [x] registry data-plane anon consumption (B03/B04/B05/B07/B14) — #43 slice 3 (`be7e1c9`), existence-oracle-safe.
- [ ] **DEFER** api-gateway public-mux registration — api-gateway-registrar срез.
- [ ] vault edges/rpc notes при docs-срезе; flip тикета Test→Done после merge всех срезов.

## Связанные

- Эпик [[kacho-workspace#132]] · acceptance sub-phase-RG-1.

#kac #feature #kacho-registry #kacho-proto
