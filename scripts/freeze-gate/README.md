# Freeze Gate (KAC-178, W3.4)

Automated checklist runner verifying that product-completion work (W1–W3.3) is
complete and Kachō is ready for **maintenance-only freeze**.

Implements `docs/specs/sub-phase-W3.4-freeze-checklist-acceptance.md`.

## Usage

```bash
# Run all 13 checks from workspace root
./scripts/freeze-gate/run-all.sh

# Run a single check
./scripts/freeze-gate/check-01-no-stubs.sh

# CI cron — see .github/workflows/freeze-gate.yml
```

## Exit codes (per check + orchestrator)

| Code | Meaning |
|------|---------|
| 0    | ✅ pass |
| 1    | ❌ fail (blocker — freeze NOT possible) |
| 2    | ⏸ skipped (precondition missing, e.g. sibling repo not cloned) |

## Checks

| #  | Slug | What it verifies |
|----|------|---|
| 01 | no-stubs | 0 `codes.Unimplemented` / TODO / FIXME on surface |
| 02 | findings-closed | All 55 IAM authz findings closed or wontfix |
| 03 | enterprise-b-wired | Enterprise B.1–B.10 RPCs registered + newman cases exist |
| 04 | block-f-api-tokens | API-token resource + RPC + newman case |
| 05 | compute-internal-admin | Compute Internal admin List RPCs present |
| 06 | authz-infra-deployed | OpenFGA HA + drainer + gateway authz config |
| 07 | newman-coverage-100 | Newman RPC coverage = 100% per service |
| 08 | newman-suites-green | Latest newman-e2e CI runs = success per repo |
| 09 | integration-coverage | `go test -coverprofile` ≥ 80% per service |
| 10 | ci-green-all-repos | Latest `main` CI run = success in all 9 repos |
| 11 | infra-ready | Postgres backups + TLS + gateway fail-closed |
| 12 | observability-ready | W3.2 dashboards / rules / runbooks present |
| 13 | docs-synced | Vault & docs/specs synchronised |

## Wiring expectations

- Repo siblings cloned under `project/` (workspace `bootstrap.sh`).
- `gh` CLI authenticated (for cross-repo CI status checks).
- `kubectl` / `psql` only used by checks that need cluster state; those checks
  exit `2` (skipped) if tooling/cluster is unreachable rather than failing.
