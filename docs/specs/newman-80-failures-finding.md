# Finding — Newman E2E 80 assertion failures on KAC-177 branch

> **Status**: documented — production fix dispatched per Wave 2A triage; partial defer to dedicated 3.7b impl session
> **Date**: 2026-05-24
> **Branch**: KAC-181 (this doc); KAC-177 (failing CI)
> **Origin**: 4 PRs (api-gateway#34, vpc#113, compute#30, iam#38) on branch `KAC-177` (helm-umbrella newman-e2e wiring) — newman summary shows 80 FAILED assertions across 6 suites
> **CI run**: `gh run view 26358993224 --repo PRO-Robotech/kacho-api-gateway`

## Summary of failures

| Suite | FAILED | / total assertions | / total requests | Disposition |
|---|---:|---:|---:|---|
| `authz-deny` | 3 | 743 | 304 | **TBD** — pending Wave 1A triage agent return |
| `authz-sa-apitoken` | 4 | 74 | 30 | **TBD** — pending triage |
| `iam-compliance-report` | 6 | 65 | 36 | **EXPECTED RED — sub-phase 3.7b not yet implemented** |
| `iam-internal-only-check` | 10 | 23 | 14 | **TBD** — pending triage |
| `iam-jit-pending` | 33 | 46 | 32 | **EXPECTED RED — sub-phase 3.7b not yet implemented** |
| `iam-user` | 24 | 60 | 40 | **TBD** — pending triage |
| **Totals** | **80** | **1011** | **456** | 39 expected + 41 under triage |

## Expected RED group (39 of 80) — sub-phase 3.7b deferred impl

39 of the 80 failures hit on two suites that test functionality whose **service-layer foundation is intentionally stub-only on `main`**:

1. **`iam-jit-pending` (33 fails)** — `JITService.ApproveJIT` at `project/kacho-iam/internal/service/phase7_jit_service.go:343` is an explicit `return errors.New("ApproveJIT: bind to AccessBinding repo...")` stub. Documented as known-gap in `obsidian/kacho/KAC/KAC-127.md` («Phase 7 base intentionally deferred JitPending approve/deny + AccessBinding mint until 3.7b»).

2. **`iam-compliance-report` (6 fails)** — `ComplianceReportService.GenerateAccessReport` has no use-case on the service layer; the Phase 7 base introduced the governance data sources (AccessBindings, JIT activations, Break-glass usage, Access Review outcomes, GDPR erasure requests) but the aggregator was deferred.

Both are addressed in `docs/specs/sub-phase-3.7b-iam-compliance-report-jitpending-acceptance.md` (APPROVED by `acceptance-reviewer` on 2026-05-21, 30 GWT scenarios, retrieved from KAC-127 worktree and committed to main as part of this batch).

### Why these tests stay RED until 3.7b impl

Per workspace `CLAUDE.md` §«Запреты» #13:

> **TDD-red против реального бага продукта (тест корректен, но GREEN потребует фикса прода)** — это **finding**, не tech debt: (a) **сразу** заводим GitHub Issue в репо продукта (метка `bug` + `verified-by:test`); (b) в кейсе ставим `# verifies <issue-url>` (но **без** «TODO/skip-until»); (c) кейс ОСТАЁТСЯ красным до фикса прода — это допустимое исключение из «100% pass rate» с явной декларацией в `RESULTS.md` под заголовком «Known failing tests — product bugs» + KAC-trail.

The 39 expected-RED assertions match this pattern exactly (test correct, product feature deferred). The mapping:

- **GitHub issue**: PRO-Robotech/kacho-iam — to be opened with label `bug` + `verified-by:test`, body links to `docs/specs/sub-phase-3.7b-...-acceptance.md`. Title: `[Phase 7b stub] ComplianceReportService.GenerateAccessReport + JITService.ApproveJIT — newman regression locked-RED until impl`.
- **YouTrack**: existing KAC-123 (YT id; vault-label KAC-127) covers Phase 7b scope. Add comment with newman failure mapping.
- **Newman cases**: `project/kacho-iam/tests/newman/cases/iam-compliance-report.py` + `iam-jit-pending.py` — add `# verifies https://github.com/PRO-Robotech/kacho-iam/issues/<N>` annotation on the assertions that depend on 3.7b impl. **No `skip()`, no `TODO`**, per §13.
- **CI gate**: `assert authz suites green` step (newman-e2e workflow) currently fails the whole job on ANY suite with `FAILED > 0`. Per «known failing tests» allowance, this step is to be relaxed to **whitelist** the two 3.7b suites until impl:
  ```bash
  # in .github/workflows/newman-e2e.yml or the assert-step
  KNOWN_RED="iam-compliance-report iam-jit-pending"
  ```
  with the whitelist removed atomically when 3.7b impl PR merges. Whitelist additions require a finding doc reference and KAC-ticket comment trail.

## TBD group (41 of 80) — Wave 1A triage in flight

The remaining 41 failures across 4 suites (`authz-deny: 3`, `authz-sa-apitoken: 4`, `iam-internal-only-check: 10`, `iam-user: 24`) are being triaged by background agent `Wave 1A` (general-purpose, read-only). On return:

- Per-suite failure breakdown (assertion → http status → root cause group)
- Categorisation per failure: **real product bug** (→ Wave 2A fix PR per group with RED→GREEN proof, workspace §12) vs. **test-side bug** (→ Wave 2A fix newman case) vs. **deferred impl with finding** (→ same pattern as 3.7b above)
- Suggested fix sequencing

This document will be **updated** with the triage result; **not** superseded.

## Cross-references

- Acceptance doc behind RED group: `docs/specs/sub-phase-3.7b-iam-compliance-report-jitpending-acceptance.md`
- Workspace policy on findings vs TODO: `CLAUDE.md` §«Запреты» #11, #13
- Migration policy (relevant when 3.7b impl lands): `docs/specs/migration-coordination-policy.md`
- KAC-trail: `obsidian/kacho/KAC/KAC-127.md` (parent epic, done), `obsidian/kacho/KAC/KAC-181.md` (this doc batch)

## Action items emitted by this finding

1. ✅ Bring `sub-phase-3.7b-...-acceptance.md` from KAC-127 worktree into main (this PR — KAC-181).
2. ✅ Document expected-RED status of 39 assertions (this doc).
3. ⏭ **Defer**: 3.7b production implementation — needs dedicated work session (1-2 weeks estimate), outside Hybrid-mode autonomous scope per saved feedback `feedback-acceptance-tests-only-not-code` (multi-week production code via agents → no).
4. ⏭ **Wave 2A**: Triage 41 TBD failures, decide bug vs deferred-with-finding per assertion group, dispatch fix-implementer agents per real-bug group.
5. ⏭ **Whitelist CI step**: relax `assert authz suites green` to whitelist `iam-compliance-report` + `iam-jit-pending` (after Wave 1A confirms no other suite needs same treatment) — separate PR on `kacho-iam` once policy ratified.
