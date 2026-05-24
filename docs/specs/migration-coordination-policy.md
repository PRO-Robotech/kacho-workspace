# Migration Number Coordination Policy

> **Status**: ACTIVE
> **Origin**: KAC-170 acceptance review report §«Migration number coordination» (Critical #2 from W2.B reviewer)
> **Owner**: this workspace doc — source of truth; per-repo migration registries follow.
> **Scope**: any goose SQL migration in `project/kacho-<svc>/internal/migrations/`.
> **Branch**: KAC-181

## Problem this policy solves

Multiple in-flight acceptance docs claim the same next migration number (e.g. KAC-170 review caught three docs all claiming `0026`):

- W2.A `0026_service_account_project_scoped.sql`
- W2.B `0026_w2b_saml_request_state.sql`
- W3.1 `0026_jwks_keys.sql`

If two PRs merge in parallel without rebasing, goose loader sees duplicate numeric prefix → migration silently skipped or migration-history table conflict at deploy. Per workspace `CLAUDE.md` §«Запреты» #5 («НЕ редактировать применённую миграцию»), the fix is forced into a follow-up migration — tech debt that §11 forbids.

## Rule

**Migration numbers are NOT pre-assigned in acceptance docs.** They are assigned at **impl-start time**, immediately before the migration is written, based on the **actual last-applied number on the target service's `main` branch**.

Acceptance docs are allowed to **sketch** numbers as non-binding (e.g. «migration ~0029», «next-available»), but **CI rejects** any PR whose migration prefix matches an existing prefix on `main`.

## Procedure (per PR introducing a migration)

1. **Right before writing the migration**, rebase the feature branch on the latest `origin/main` of the target service repo:
   ```bash
   cd project/kacho-<svc>
   git fetch origin
   git rebase origin/main
   ```

2. List existing migrations on `main` to find the highest applied number:
   ```bash
   ls internal/migrations/*.sql | sort | tail -3
   ```

3. Pick `<highest>+1` as the new migration's numeric prefix. Name format: `NNNN_<kac-ticket>_<short-description>.sql`.

4. Write the migration. **Do not** copy a number from the acceptance doc verbatim — the doc is a sketch, the filesystem is the source of truth.

5. PR description **must** include a line:
   ```
   Migration: 0029_kac178_freeze_gate_status.sql (last on main: 0028)
   ```
   This makes the assignment auditable in PR review.

6. If, during PR review, `origin/main` of the target service gains a new migration that collides, **rebase + rename the migration file** (this is allowed because the migration has **not yet been applied to `main`**, so §«Запреты» #5 does not bite). Update PR description.

## CI enforcement

Every service repo's CI (`ci.yaml` → `migrations-lint` job) runs:

```bash
# scripts/lint-migrations.sh in each service repo
set -euo pipefail
cd internal/migrations
duplicates=$(ls *.sql | awk -F_ '{print $1}' | sort | uniq -d)
if [ -n "$duplicates" ]; then
  echo "FAIL: duplicate migration prefixes: $duplicates"
  exit 1
fi
# also: prefix must be strictly increasing (no gaps allowed)
prev=0
for f in $(ls *.sql | sort); do
  num=$(echo "$f" | awk -F_ '{print $1}' | sed 's/^0*//')
  if [ "$num" -le "$prev" ]; then
    echo "FAIL: $f prefix $num <= previous $prev"
    exit 1
  fi
  prev=$num
done
```

This script must exist in every service repo that ships migrations. Tracking: enforced by `scripts/freeze-gate/check-11-migrations-lint.sh` (W3.4 freeze gate).

## Sketch for in-flight W2/W3 docs (non-binding)

Per KAC-170 review §coordination, **current** sketch is (last-applied on `kacho-iam/main` = `0025_nlb_operator_target_manager_roles.sql`):

```
KAC-178 (W3.4 freeze + bats — workspace, no iam migrations)
KAC-179 (api-gateway unit fixes — no migrations)
KAC-181 (docs batch — no migrations)

W2.A merges first → claims 0026 (service_accounts.project_scoped)
W2.C next (api tokens, KAC-170 W2.C reviewer Critical #1):
  0027 (ALTER subject_change_outbox CHECK extend +'api_token_revoke')
  0028 (api_tokens table + indexes)
W2.B (Option Y per KAC-172):
  0029 (scim_per_org_auth — for B.2 #41)
  0030 (compliance_report_download_token — B.6)
  0031 (cluster_break_glass_grants + approver-distinct CHECK — B.4)
  0032 (erasure_requests + erasure_audit — B.7)
  0033 (subject_change_outbox CHECK extend +'erasure' — B.7)
  0034 (caep_subscribers — B.8 egress)
  0035 (caep_event_log — B.8)
W3.1 (per KAC-173):
  0036 (saml_request_state — moved from W2.B per scope Y)
  0037 (iam_trusted_idp_jwks_cache — #42 ingress JWKS cache)
  (oidc_jwks_keys — extend existing 0014 additively if missing columns)
W3.3 (SPIRE+Cilium): no migrations (cilium policies are YAML, not SQL)
3.7b (KAC-127 / YT KAC-123 known-gap):
  Will be 0026-0027 IF merged before W2.A; otherwise next-available at the
  time. 3.7b is currently deferred (out of Hybrid-mode scope) — see
  newman-80-failures-finding.md.
```

If the merge order changes (W2.B before W2.A, W3.1 before W2.B, etc.), the actual numbers shift — **the policy above (rebase → ls → pick highest+1) handles it transparently**.

## What to do if you discover a duplicate post-merge

If `migrations-lint` is bypassed and a duplicate prefix lands on `main`, the only safe fix is:

1. Write a **new migration** with the next-available prefix that semantically supersedes one of the duplicates (e.g. `0030_supersede_dup_0026.sql` with `DROP / CREATE` as appropriate).
2. **Never** edit the applied migration in place (§«Запреты» #5).
3. Document the incident in `obsidian/kacho/KAC/KAC-<incident>.md`.

This has not happened yet; the procedure exists to keep it that way.

## Related

- workspace `CLAUDE.md` §«Запреты» #5 (no edit applied migration)
- workspace `CLAUDE.md` §«Запреты» #11 (no TODO / tech-debt)
- `docs/specs/02-data-model-and-conventions.md` §11-§12 (migration conventions — JSONB, resource_version triggers, advisory locks)
- `docs/specs/KAC-170-acceptance-review-report.md` §«Migration number coordination» (origin doc)
- `scripts/freeze-gate/check-11-migrations-lint.sh` (W3.4 freeze gate enforcement)
