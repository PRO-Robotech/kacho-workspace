# Freeze process (W3.4 / KAC-178)

Daily automated freeze-gate sweep, plus the human escalation flow when a check
goes red.

## Cron

- Workflow: `.github/workflows/freeze-gate.yml`
- Schedule: `0 8 * * *` (08:00 UTC daily)
- Also runs on push to `scripts/freeze-gate/**` and on `workflow_dispatch`

## Outputs

1. `scripts/freeze-gate/run-all.sh` writes:
   - stdout summary (PASS / FAIL / SKIP / CRASH per check)
   - JSON report at `$KACHO_FREEZE_OUTPUT_JSON` if set
2. `scripts/freeze-gate/update-vault.sh` regenerates
   [[../freeze-gate-status]] from the JSON report.
3. The workflow opens (or comments on) a tracking issue
   `[FREEZE-GATE] <date>: <N> failing checks` labelled `freeze-gate` in
   `PRO-Robotech/kacho-workspace`.
4. On a full pass the open tracking issue is closed automatically.

## Exit-code semantics

| rc | Meaning |
|----|---------|
| 0  | All 13 checks pass — freeze is possible. |
| 1  | At least one check failed (blocker). |
| 2  | At least one check crashed (infra/tooling issue, not a product gap). |

## Escalation

- A failing check is a **finding**, not a code TODO. If the product gap is
  novel, open a per-repo Issue with label `freeze-blocker` and link it from the
  workspace tracking issue comment.
- Skip vs Fail: a SKIP is benign — the check could not run (sibling repo
  unavailable, gh CLI absent in cron context, heavy go-test coverage
  intentionally skipped via `KACHO_FREEZE_COVERAGE_SKIP=1`).

## Local dry-run

```bash
cd kacho-workspace
KACHO_FREEZE_OUTPUT_JSON=/tmp/freeze.json ./scripts/freeze-gate/run-all.sh
./scripts/freeze-gate/update-vault.sh /tmp/freeze.json
```

## Freeze declaration

Freeze is declared after **two consecutive daily cron runs** report rc=0 on
main with no skipped checks (every check ran in CI and passed). At that point
master epic [[../KAC/KAC-134]] moves to Done and the product enters
`maintenance-only`.
