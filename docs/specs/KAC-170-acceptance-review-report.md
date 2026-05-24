# KAC-170 Acceptance Review Report

> **Date**: 2026-05-24
> **Triggered**: completion of KAC-170 (W2/W3 acceptance docs bundle, 8 docs / 7816 lines)
> **Method**: 8 parallel `acceptance-reviewer` subagents, one per acceptance doc
> **Gate purpose**: workspace `CLAUDE.md` §Запреты #1 — APPROVED acceptance doc is the gate to start impl

## Summary

**6 APPROVED, 2 CHANGES REQUESTED** (which means **75% ready to start impl**, two require revision per reviewer findings).

| Doc | Verdict | Reviewer summary |
|---|---|---|
| W2.A — gateway-catalog + spec-drift | ✅ APPROVED | 10 OQ defaults ratified, 7 non-blocking notes (paths `usecases/` → `api/` drift; line-numbers ±3; ListPermissions helper aggregator visibility; `dbLookup` peer-call needs proto-api-review later) |
| W2.B — Enterprise B.1-B.10 | ❌ CHANGES REQUESTED | 4 critical: cross-doc scope conflict с W3.1; migration 0026 collision; Запрет #9 false 100% claim for REST endpoints; `saml_request_state` migration meaningless without signature verify |
| W2.C — Block F API tokens | ✅ APPROVED | 12 OQ defaults set, 7 notes (**important**: migration 0026 must `ALTER subject_change_outbox` extend CHECK with `'api_token_revoke'`; gateway `FailOpen` wording vs doc's `mode == production`) |
| W2.D — Newman 49→100% coverage | ✅ APPROVED | 5 non-blocking notes (services count typo «22+22=22»; federation JWT fixture realism; sa-key #11 regression visibility; branch naming; docs-files verify) |
| W3.1 — Federation/SSO internals | ❌ CHANGES REQUESTED | 3 critical: #42 direction misread (ingress vs egress); duplicate `jwks_keys` vs existing `oidc_jwks_keys`; #40/#41 scope overlap с W2.B |
| W3.2 — Observability customisation | ✅ APPROVED | 10 OQ + 7 minor notes (Loki-datasource shim; otel-collector tail_sampling enable; parameterized expected-edges; alert trigger choice) |
| W3.3 — SPIRE+Cilium mTLS | ✅ APPROVED | 10 OQ + 6 notes (`kacho.cloud` trust domain ratified — chart verified; staged dual-accept-window properly delivered as config-flag NOT TODO per §11; hubble-emitted metric naming) |
| W3.4 — Freeze checklist | ✅ APPROVED | 7 non-blocking notes (proto file naming verify before impl; CI green script flapping; coverage % parsing; runbook freshness git-based; YT API project filter; orchestrator output capture) |

## Critical: Cross-doc scope conflict W2.B ↔ W3.1

Both reviewers independently caught the same root issue from different angles:

- **W2.B reviewer**: «B.1/B.2/B.8 описаны как полные реализации; W3.1 #40/#41/#42 тоже claim full impl — collision»
- **W3.1 reviewer**: «#42 direction misread (egress sign = W2.B B.8 territory); #40/#41 scope overlap; migration numbers collide»

### Resolution options (per W2.B reviewer Critical #1)

| Option | W2.B scope | W3.1 scope | Pros | Cons |
|---|---|---|---|---|
| **X** | B.1/B.2/B.8 deliver full verify/auth/sign | W3.1 hardening only (OPA/RegoTest/ReloadModel) | matches W2.B current text | requires master plan §W3 row edit (remove #40/#42); W3.1 substantially shrinks; conflicts с user prompt («W2.B guards, W3.1 verify») |
| **Y** | B.1/B.2/B.8 scaffolding only (endpoints wired, guards/stubs in place); B.2 keeps full SCIM CRUD + Basic-auth | W3.1 implements full XML-DSig verify (#40), JWS sign (#42 — but direction TBD), drops #41 (lives in W2.B B.2) | matches master plan §W3 row; matches user prompt; preserves W3.1 substantive value | requires W2.B doc rewrite (3-4 GWT scenarios removed per feature, scope tables updated) |

**Recommendation**: **Option Y** — master plan §W3 row («#21/#23/#25/#26/#40/#42» — note: #41 NOT in W3) is the source-of-truth per workspace `CLAUDE.md` §«Документооборот». #41 SCIM Basic-auth lives in W2.B B.2 (where SCIM endpoints are wired).

### #42 direction (W3.1 reviewer Critical #1)

Per `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` lines 90, 186:
- file: `internal/handler/iamhooks/caep_ingress_handler.go::parseSETBody`
- symptom: «base64-декодит JWT без проверки подписи»
- fix: «проверять подпись SET-JWT по JWKS доверенного IdP»

**#42 = INGRESS verify** (kacho-iam receives SET from external CAEP-emitting IdP, verifies signature against THAT IdP's JWKS endpoint).

**W2.B B.8 = EGRESS sign** (kacho-iam emits its own SETs signed by our key, exposes /jwks.json for subscribers).

These are two different code paths. No conflict if separated correctly:
- W2.B B.8: drainer → `signSET` (our private key from `oidc_jwks_keys`) → POST to subscriber → expose `/jwks.json` (our public keys)
- W3.1 #42: `caep_ingress_handler::parseSETBody` → fetch external IdP JWKS → verify signature → reject if invalid

### Migration number coordination (W2.B reviewer Critical #2)

Last applied = `0025_nlb_operator_target_manager_roles.sql`. Three docs all claim `0026`:
- W2.A: `0026_service_account_project_scoped.sql`
- W2.B: `0026_w2b_saml_request_state.sql`
- W3.1: `0026_jwks_keys.sql` (also: should drop, extend existing `oidc_jwks_keys` from 0014)

**Resolution**: реальные числа assign-ятся в порядке merge. Acceptance docs обновляются на impl-start чтобы reference актуальный next-available number. Coordination meta-doc:

```
W2.A merges first: 0026 (service_accounts project_scoped)
W2.C (api_tokens, KAC-170 W2.C reviewer Critical #1):
  - 0027 (ALTER subject_change_outbox CHECK extend +'api_token_revoke')
  - 0028 (api_tokens table + indexes)
W2.B (Option Y; saml_request_state moves to W3.1; B.2 SCIM keeps):
  - 0029 (scim_per_org_auth — for B.2 #41)
  - 0030 (compliance_report_download_token — B.6)
  - 0031 (cluster_break_glass_grants + approver-distinct CHECK — B.4)
  - 0032 (erasure_requests + erasure_audit — B.7)
  - 0033 (subject_change_outbox CHECK extend +'erasure' — B.7)
  - 0034 (caep_subscribers — B.8 egress)
  - 0035 (caep_event_log — B.8)
W3.1:
  - 0036 (saml_request_state — moved from W2.B per scope Y)
  - 0037 (iam_trusted_idp_jwks_cache — #42 ingress JWKS cache)
  - (oidc_jwks_keys — extend existing 0014 additively if missing columns)
W3.3 (SPIRE+Cilium): no migrations (cilium policies are YAML, not SQL)
```

This is **non-binding sketch** — final assignment at impl-start time (PR merge order determines actual sequence).

## Follow-up tickets created

| Ticket | Title | Status |
|---|---|---|
| [KAC-172](https://prorobotech.youtrack.cloud/issue/KAC-172) | W2.B revision per acceptance-reviewer findings | Open |
| [KAC-173](https://prorobotech.youtrack.cloud/issue/KAC-173) | W3.1 revision per acceptance-reviewer findings | Open |

Both subtasks of [KAC-170](https://prorobotech.youtrack.cloud/issue/KAC-170), in current sprint.

## Why this was NOT autonomously revised

Per memory rule `feedback-acceptance-tests-only-not-code` + autonomous loop discipline («for irreversible ones, keep waiting»):

1. **Scope-split decision is design-level** (Option X vs Y). Reviewer presented both options + recommendation; user/master-plan-owner should ratify before doc revision.
2. **Cross-doc coordination required** — W2.B revision и W3.1 revision must agree on final scope split; revising one without the other = collision.
3. **#41 placement decision** — master plan §W3 row не lists #41, but remediation plan §1.3 has it as Chunk 5 item; reviewer presented 3 sub-options (W2.B B.2 / W3.1 / drop as wontfix per P3 marker).

Memory rule limits autonomous work to **acceptance docs + test plans** (not design decisions); revising acceptance under unresolved scope-split would either pre-empt design decision OR introduce new tech debt («revise to match preferred option, hope it's right»).

## What autonomous session DID complete

- ✅ 8 acceptance docs written (5 background subagents + 3 inline) + 4 retroactive W1.* docs — merged via KAC-170 PR #40
- ✅ KAC-169 opsproxy production fix — merged via kacho-api-gateway PR #31 + workspace PR #39
- ✅ Vault hygiene — merged via workspace PR #41 (3 retroactive untracked artifacts)
- ✅ 8 acceptance-reviewer reviews (parallel subagents) — 6 APPROVED, 2 CHANGES REQUESTED
- ✅ 2 follow-up KAC tickets created (KAC-172, KAC-173) with full reviewer context + scope-split options
- ✅ This review report doc (workspace PR pending)

## Next steps (require user / future session)

1. **Ratify scope split**: Option X vs Y for W2.B↔W3.1 (recommend Y per master plan source-of-truth)
2. **Decide #41 placement**: W2.B B.2 (default) vs W3.1 vs drop-as-wontfix
3. **Verify #42 direction**: ingress (per remediation plan source) — confirm
4. **Execute KAC-172 + KAC-173**: revise W2.B + W3.1 acceptance docs; re-submit to acceptance-reviewer
5. **For 6 APPROVED docs**: ready to create impl-subtasks (one per doc) and dispatch `rpc-implementer` per workspace flow

## Full reviewer transcripts

Preserved in YouTrack KAC-170 comments (8 individual reviews, ~600 lines each).
