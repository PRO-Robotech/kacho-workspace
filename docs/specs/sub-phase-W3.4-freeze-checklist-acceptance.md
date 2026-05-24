# Sub-phase W3.4 — Freeze Checklist (product-completion-freeze-plan Part 4) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: [KAC-170](https://prorobotech.youtrack.cloud/issue/KAC-170) (parent bundle); subtask of master epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134).
> **Author agent**: inline (`claude` main session)
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-workspace` —
>     - `docs/specs/sub-phase-W3.4-freeze-checklist-acceptance.md` (this file — declarative checklist)
>     - `docs/superpowers/plans/2026-05-21-product-completion-freeze-plan.md` Part 4 (source — synced)
>     - `obsidian/kacho/freeze/freeze-status.md` (NEW — live dashboard of checklist state)
>   - **Verification scripts** (NEW) in `kacho-deploy/` repo — automated gate runner:
>     - `kacho-deploy/scripts/freeze-gate.sh` (master gate: runs all 13 sub-gates, exits 0 iff all pass)
>     - `kacho-deploy/scripts/freeze-checks/00-no-stubs.sh` через `12-docs-synced.sh` (one script per checklist item)
>   - **NO product code changes** — этот sub-phase **verifies completion**, не реализует фичи. Любая обнаруженная gap → finding-issue в соответствующем product repo (kacho-iam / kacho-vpc / kacho-compute / kacho-api-gateway / kacho-deploy / etc.), не fix в этом PR.
> **Branch (kacho-workspace)**: `KAC-XXX-freeze-checklist` (placeholder).
> **Source-of-truth checklist**: `docs/superpowers/plans/2026-05-21-product-completion-freeze-plan.md` §«Часть 4 — Freeze checklist» (13 пунктов + 1 рекомендация).
> **Predecessors (must be `main`-merged before W3.4 evaluation can pass)**:
> - **All of W1, W2, W3.1-W3.3** — W3.4 = **последняя** sub-фаза epic'а KAC-134. Verifies completion того, что предыдущие sub-фазы delivered.
> - В частности: W2.A (catalog unified), W2.B (Enterprise B.1-B.10 wired), W2.C (API tokens), W2.D (newman 100% coverage), W3.1 (federation internals), W3.2 (observability), W3.3 (SPIRE+Cilium).

---

## 0. Преамбула — что эта sub-итерация (précis)

W3.4 — **gate-итерация**: не реализует фичи, **проверяет** что вся product-completion работа W1–W3.3 завершена и продукт готов к переводу в **maintenance-only** состояние («законсервирован»). Поставляет:
1. **Декларативный чек-лист** (этот файл) — 13 пунктов из freeze-plan §«Часть 4» с per-item acceptance criteria и verification command.
2. **Automated gate runner** (`kacho-deploy/scripts/freeze-gate.sh`) — exit 0 iff все 13 pass; exit 1 + per-failed-item diagnostic если что-то open.
3. **Vault live-dashboard** (`obsidian/kacho/freeze/freeze-status.md`) — обновляется automated runner после каждого прогона; shows per-item ✅/❌/⏳ state + ссылка на gap-finding если ❌.

Запуск freeze-gate — еженедельно в CI (cron workflow) + ручной trigger перед declared «consume freeze» date. Когда runner возвращает exit 0 на main для 2 последовательных недель — продукт переводится в `maintenance-only`.

### 0.1 W3.4 НЕ включает

- **Реализация любого open item** — если #X из checklist failed, W3.4 не fix'ит. Open finding-issue в нужный product repo; W3.4 PR не блокируется этим (но и в Done state не переходит, остаётся `gate-monitoring`).
- **Pentest** (recommended-only, не required) — `(рекомендуется) внешний pentest пройден` — отдельная activity, не часть scope; см. master plan §«scope decision».
- **Backup automation product** — Postgres backups уже presumed-в-помощь kacho-deploy (см. master OQ — out of CLAUDE; verify в W3.4-item-9).
- **Disaster recovery rehearsal** — отдельная maintenance-mode activity post-freeze.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl сам — это `freeze-gate.sh` scripts; стартует только после APPROVED. |
| **Запрет #2** | `grep -ri yandex kacho-deploy/scripts/freeze-checks/` должен быть empty в run-time output. |
| **Запрет #6** | gate-runner не expose Internal*-info наружу; работает в cluster-internal (запускается из CI job, не public endpoint). |
| **Запрет #11** (no TODO / no tech debt — root rule) | freeze-gate scripts — production-ready, без `# TODO: implement check`. Если какой-то item проверяется semi-manual (cannot fully automate) — `manual-check.md` со чёткой last-verified-date, не TODO. |
| **Запрет #12** (test-first STRICT) | scripts pass-условие тестируется на **обоих** сторонах: synthetic-broken state → expected FAIL; synthetic-good state → expected PASS. Pair RED→GREEN per script в PR description. |
| **Запрет #13** (test-only PR discipline) | W3.4 — meta-проверка. Сами scripts — verification tooling, не newman cases. Product-code изменения **в этом PR категорически запрещены**; обнаруженные gaps → отдельный finding-issue. |

---

## 2. Глоссарий

- **Freeze** — формальное завершение feature-development; продукт переводится в `maintenance-only` (security-fix + regression-fix only).
- **Maintenance-only** — режим: новых фич не добавляется; bug-fix есть; security-update есть; performance tweaks — case-by-case.
- **Gate** — automated boolean check; exit 0 = pass, ≠ 0 = fail.
- **freeze-gate runner** — top-level shell script orchestrating 13 sub-gate scripts.
- **Sub-gate** — single check (e.g. `00-no-stubs.sh`).
- **Live dashboard** — Vault entry auto-regenerated после runner; markdown table с per-item state.
- **«Известный gap»** — item failed → finding-issue в соответствующем product repo (labels: `bug` либо `enhancement` + `freeze-blocker`).

---

## 3. Decisions (приняты)

| ID | Решение |
|---|---|
| W3.4-D1 | Чек-лист hosted as code в shell scripts, не в Confluence / Notion / etc. Source of truth = repo. |
| W3.4-D2 | Runner запускается еженедельно через GitHub Actions cron workflow (`freeze-gate-weekly.yaml`) + ручной trigger через `gh workflow run`. |
| W3.4-D3 | Pentest — recommended, не required для freeze. Можно freeze без него; пометить в `freeze-status.md` как «pentest pending». Decision per master plan KAC-127 («БЕЗ внешнего pentest»). |
| W3.4-D4 | На каждый failed item — gate runner создаёт (или обновляет existing) GitHub Issue в нужном repo с label `freeze-blocker`. Idempotent: same gap не плодит дублей. |
| W3.4-D5 | Gate runner exit code: 0 = all 13 pass, 1 = ≥1 fail (continue showing all), 2 = ≥1 sub-script crashed (infrastructure issue, not product gap). |
| W3.4-D6 | Vault dashboard generation: `freeze-gate.sh` дописывает в `obsidian/kacho/freeze/freeze-status.md` markdown table; коммитит автоматически (через GitHub Actions bot) в PR на review. Не push'ит в main. |

---

## 4. Open questions

| ID | Вопрос | Рекомендация |
|---|---|---|
| OQ-W3.4-1 | Item #5 «Блок C: Compute Internal admin Lists готовы» — kacho-compute has internal Hypervisor list? Per master plan «kacho-loadbalancer вне scope» — confirmed. | Verify proto файлы in `kacho-proto/proto/kacho/cloud/compute/v1/internal_*` exist + have List RPC. |
| OQ-W3.4-2 | Item #9 «Postgres+бэкапы» — backup automation product (pgbackrest? wal-g? CronJob+pg_dump?) уже в kacho-deploy? | Verify `kacho-deploy/helm/postgres-backup/` chart; если нет — это finding на отдельный KAC-deploy ticket, blocks freeze. |
| OQ-W3.4-3 | Item #11 «Observability: metrics/logs/traces/alerts/dashboards/runbooks» — runbooks где живут? Vault `observability/runbooks-iam.md`? | Recommend per-service runbook: `obsidian/kacho/observability/runbook-<svc>.md`. Gate проверяет existence per-service + last-edited не >90 days. |
| OQ-W3.4-4 | Item #13 «(рекомендуется) внешний pentest пройден» — gate-state? | По решению W3.4-D3: pending — informational, не блокирует freeze. Vault dashboard показывает «pentest pending — not required». |

---

## 5. Implementation steps

### 5.1 Bootstrap

1. Создать `kacho-deploy/scripts/freeze-checks/` directory.
2. На каждый item — sub-gate script (см. §6 ниже за per-item spec).
3. Создать orchestrator `kacho-deploy/scripts/freeze-gate.sh`:
   ```bash
   #!/usr/bin/env bash
   set -uo pipefail  # NO -e — мы хотим собрать все failures
   declare -a FAILED=()
   declare -a CRASHED=()
   for script in scripts/freeze-checks/*.sh; do
       name=$(basename "$script" .sh)
       echo "=== Running $name ==="
       if ! output=$("$script" 2>&1); then
           rc=$?
           echo "$output"
           if [ $rc -eq 2 ]; then
               CRASHED+=("$name")
           else
               FAILED+=("$name")
           fi
       fi
   done
   # Generate vault dashboard
   ./scripts/freeze-checks/_render-vault.sh "${FAILED[@]}" "${CRASHED[@]}"
   if [ ${#CRASHED[@]} -gt 0 ]; then exit 2; fi
   if [ ${#FAILED[@]} -gt 0 ]; then exit 1; fi
   echo "FREEZE GATE: ✅ all 13 items pass"
   exit 0
   ```
4. Создать GitHub Actions workflow `freeze-gate-weekly.yaml` (cron `0 9 * * 1` — каждый понедельник 09:00 UTC).
5. Per-item: см. §6.

### 5.2 Per-item gate scripts (13 + 1 informational)

См. §6 для полной спецификации каждого.

### 5.3 Vault dashboard

`obsidian/kacho/freeze/freeze-status.md` — template:

```markdown
---
title: "Freeze Status"
date_generated: 2026-05-24T09:00:00Z
---
# Freeze Status (last run: <ts>)

| # | Item | Status | Last verified | Finding |
|---|---|---|---|---|
| 00 | 0 stubs / Unimplemented | ✅ | <ts> | — |
| 01 | All 55 findings closed | ❌ | <ts> | [issue link] |
| ... |
| 12 | Docs synced | ✅ | <ts> | — |
| 13 | (rec.) Pentest passed | ⏳ informational | n/a | — |

## Summary
- **Freeze-ready**: ❌ NO — 1 blocker open
- **Open blockers**: 1 (item #01)
- **Open recommendations**: 1 (item #13 pentest)
```

### 5.4 Auto-finding-issue creation

When item fails:
1. Determine target repo (per-item — coded into gate script: `TARGET_REPO=kacho-iam` etc.)
2. `gh issue list --repo $TARGET_REPO --label freeze-blocker --label "$ITEM_NAME"` — if existing → comment update with timestamp + diagnostic; if none → `gh issue create` with title `[freeze-blocker] <item-name>: <short-diagnostic>`, body = full diagnostic, labels `freeze-blocker, bug`.
3. Idempotent: same gap state → no duplicate creation, only timestamp comment.

---

## 6. Per-item GWT scenarios + verification scripts

### Item 00: «0 stub / `Unimplemented` / disabled-by-config на surface»

**Given** все service binaries built from `main`-merged code.
**When** запускается `scripts/freeze-checks/00-no-stubs.sh`.
**Then**:
- `grep -rn "codes.Unimplemented" project/kacho-*/internal/ project/kacho-*/cmd/ | grep -v _test.go` — пусто
- `grep -rn "TODO\|FIXME\|XXX" project/kacho-*/internal/ project/kacho-*/cmd/ | grep -v _test.go` — пусто (per workspace §Запреты #11)
- `grep -rn "disabled-by-config\|disabled=true\|feature_enabled.*false" project/*/deploy/values.yaml` — пусто на prod-mode

Exit 0 на success; exit 1 с list of found.

### Item 01: «Все 55 находок закрыты или wontfix с обоснованием»

**Given** remediation plan `2026-05-21-iam-authz-review-remediation-plan.md` lists 55 findings; W1.5/W1.6/W2.A/W3.1 chunks closed subsets.
**When** `scripts/freeze-checks/01-findings-closed.sh`.
**Then**:
- Parse `2026-05-21-iam-authz-review-remediation-plan.md` for `#N`-findings (regex `^| \*\*\#(\d+)\*\*`)
- For each: lookup in vault `obsidian/kacho/KAC/*.md` — what KAC closed it? Status?
- Pass if 100% closed (state=Done) ИЛИ documented `wontfix` в `docs/architecture/known-divergences.md`
- Fail если any `In Progress`/`Test`/unaccounted-for

### Item 02: «Все Enterprise-фичи (Блок B) подключены к gateway, работают, имеют newman»

**Given** W2.B.1–B.10 acceptance docs APPROVED; each B.X impl PR merged.
**When** `scripts/freeze-checks/02-enterprise-b-wired.sh`.
**Then**:
- For each B.X (1..10) — verify in `kacho-api-gateway/internal/middleware/rest_route_table_gen.go` presence of corresponding RPC entry
- For each — verify в `kacho-iam/tests/newman/cases/` есть case-file (e.g. SAML→`iam-federation-exchange.py`, AccessReview→`iam-access-review.py`, etc.)
- Run `./scripts/run.sh iam-<svc>` — assert 0 FAILED для В-stream suites

### Item 03: «Блок F: API-токены реализованы (resource + RPC + authn-путь на gateway + newman)»

**When** `scripts/freeze-checks/03-block-f-api-tokens.sh`.
**Then**:
- Verify `kacho-proto/proto/kacho/cloud/iam/v1/api_token.proto` exists
- Verify `kacho-iam/migrations/*api_tokens*.sql` exists
- Verify `kacho-iam/internal/apps/kacho/api/api_token/` package exists
- Verify `kacho-api-gateway/internal/middleware/auth.go` handles `kat_` prefix Bearer
- Verify `kacho-iam/tests/newman/cases/iam-api-token.py` exists, ./run.sh iam-api-token green

### Item 04: «Блок C: Compute Internal admin Lists готовы (loadbalancer — вне скоупа, зафиксировано)»

**When** `scripts/freeze-checks/04-block-c-compute-internal.sh`.
**Then**:
- Verify `kacho-proto/proto/kacho/cloud/compute/v1/internal_*` имеет `Hypervisor`, `InternalInstance`, `InternalDisk` services с List RPC
- Verify `kacho-compute/internal/apps/.../internal_*/` implementations exist
- Verify `kacho-workspace/CLAUDE.md` mentions «kacho-loadbalancer вне scope» (already does — verify still present)

### Item 05: «AuthZ-инфра (Блок D) развёрнута и работает»

**When** `scripts/freeze-checks/05-authz-infra-deployed.sh`.
**Then**:
- `kubectl get po -n kacho -l app.kubernetes.io/name=openfga -o json | jq '.items | length >= 2'` — HA-mini ≥2 replicas
- Drainer log: `kubectl logs <iam-pod> | grep "fga_outbox drainer started"` — emitted
- `kubectl get cm -n kacho gateway-authz-config -o json | jq '.data."authz.enabled" == "true"'`
- `psql` (через kubectl exec to iam-postgres): `SELECT COUNT(*) FROM subject_change_outbox` — column exists (W1.2 migration)

### Item 06: «100% newman-покрытие: матрица RPC→case полная»

**When** `scripts/freeze-checks/06-newman-100pct.sh`.
**Then**:
- `cd project/kacho-iam && ./tests/newman/scripts/coverage.py --min 100` exit 0
- Same для kacho-vpc, kacho-compute, kacho-api-gateway (если applicable)

### Item 07: «Все newman-сюиты в run.sh, генерируются gen.py, зелёные в CI»

**When** `scripts/freeze-checks/07-newman-suites-green.sh`.
**Then**:
- For each repo: latest `main` newman-e2e CI run = success
- Local: `./scripts/run.sh --all` exit 0 (либо acceptable known-failing per W2.D-D4)

### Item 08: «Integration-покрытие ≥80% на новом коде»

**When** `scripts/freeze-checks/08-integration-coverage.sh`.
**Then**:
- Run `go test -coverprofile=cover.out ./internal/...` per kacho-* service
- `go tool cover -func=cover.out | tail -1 | awk '{print $3}'` ≥ 80%
- (Pragma: 80% target overall; 100% on critical paths like authz/handler)

### Item 09: «Весь CI зелёный во всех 9 репо»

**When** `scripts/freeze-checks/09-ci-green-all-repos.sh`.
**Then**:
- For each repo `kacho-proto, kacho-corelib, kacho-api-gateway, kacho-iam, kacho-vpc, kacho-compute, kacho-deploy, kacho-ui, kacho-workspace`:
  - `gh run list --repo PRO-Robotech/<repo> --branch main --limit 1 --json conclusion` → conclusion == "success"

### Item 10: «Инфра развёрнута: OpenFGA HA, drainer, Postgres+бэкапы, gateway authz fail-closed, TLS»

**When** `scripts/freeze-checks/10-infra-ready.sh`.
**Then**:
- OpenFGA replicas ≥2 (item 05 sub-check, distinct context here = production deployment readiness)
- Drainer pod ready + last-emit-timestamp ≤5min ago
- Postgres backup CronJob exists + last-run successful ≤24h ago
- gateway-config `authz.enabled=true` + `authz.failOpen=false` (per W1.3)
- Cluster-ingress TLS cert valid + ≥30 days to expiry

### Item 11: «Observability: metrics/logs/traces/alerts/dashboards/runbooks»

**When** `scripts/freeze-checks/11-observability-ready.sh`.
**Then**:
- VictoriaMetrics: scrape-targets для kacho-iam UP в last 5min
- VictoriaLogs: ingestion rate > 0 last 5min для kacho-iam
- VictoriaTraces: spans от kacho-iam в last 5min
- VMAlert rules deployed (kacho-iam fga-backlog rule exists)
- Grafana dashboards deployed (kacho-iam dashboard exists, panels render)
- Runbooks: `obsidian/kacho/observability/runbook-iam.md` last-edited ≤90 days

### Item 12: «Документация синхронизирована (CLAUDE.md / vault / спеки / KAC-trail)»

**When** `scripts/freeze-checks/12-docs-synced.sh`.
**Then**:
- Each KAC-ticket in YT (state=Done) — has corresponding `obsidian/kacho/KAC/KAC-N.md` (verify via curl YT API + ls vault)
- vault `obsidian/kacho/INDEX.md` last-update ≤7 days from last vault-merge in workspace repo
- `docs/specs/*-acceptance.md` for sub-phases — all APPROVED (header check)

### Item 13 (informational): «(рекомендуется) внешний pentest пройден»

**When** `scripts/freeze-checks/13-pentest.sh`.
**Then**:
- Check vault `obsidian/kacho/security/pentest-status.md` для `last_pentest:` date
- If absent OR > 12 months → output: «pentest pending», exit 0 (informational — не блокирует)
- If present + recent → output: «pentest passed <date>», exit 0

Always exit 0 (informational).

---

## 7. Test plan

### 7.1 Per-script synthetic-broken/-good pair

For each of 13 gate scripts, write a test:
- `tests/freeze-gate/test-00-no-stubs.sh`:
  - Setup: temporary fixture repo with a `// TODO` comment in a Go file → run `00-no-stubs.sh` → assert exit 1
  - Cleanup, no TODOs → assert exit 0
- Repeat for each.

### 7.2 Integration test for orchestrator

- Bring up synthetic state where item 01 fails (mock vault missing KAC-N) → `freeze-gate.sh` exit 1; vault dashboard updated with ❌ for item 01; finding-issue created in kacho-iam.

### 7.3 GitHub Actions workflow test

- PR includes workflow change → trigger `freeze-gate-weekly.yaml` manual run → verify executes end-to-end on current main → check Issue created/updated.

---

## 8. Definition of Done

- [ ] 13 sub-gate scripts created in `kacho-deploy/scripts/freeze-checks/`
- [ ] `freeze-gate.sh` orchestrator created в `kacho-deploy/scripts/`
- [ ] `_render-vault.sh` дополнение to generate `obsidian/kacho/freeze/freeze-status.md`
- [ ] GitHub Actions cron workflow `freeze-gate-weekly.yaml` deployed (kacho-workspace)
- [ ] Per-script synthetic test (good + broken) in `tests/freeze-gate/` (RED→GREEN per script)
- [ ] First synthetic full-run completes — exit code reasonable (whatever current state actually is); diagnostic clear для каждого ❌
- [ ] Vault `obsidian/kacho/freeze/freeze-status.md` generated and committed
- [ ] **НИ ОДНОГО** TODO / FIXME / skip в scripts или test fixtures
- [ ] **НИ ОДНОГО** product-code изменения (verified `git diff --stat` в W3.4 PR)
- [ ] Any open blocker — finding-issue в нужный repo, labels `freeze-blocker`
- [ ] PR description содержит per-script RED→GREEN evidence
- [ ] PR merged → main
- [ ] First scheduled cron run executes (manual trigger first, then weekly auto)
- [ ] When all 13 pass — declare freeze, master epic KAC-134 → Done

---

## 9. Vault discipline

| Что | Файл (1-3KB) |
|---|---|
| **NEW** `obsidian/kacho/freeze/freeze-status.md` | Auto-generated dashboard (см. §5.3) |
| **NEW** `obsidian/kacho/freeze/freeze-process.md` | Описание process (cron schedule, escalation, who acts on blockers) |
| **NEW** `obsidian/kacho/KAC/KAC-XXX.md` | trail на impl-ticket |
| **UPDATE** `obsidian/kacho/architecture.md` | mention freeze-gate как часть CI surface |
| **UPDATE** `obsidian/kacho/security/pentest-status.md` | if exists; иначе NEW с pending state |

---

## 10. Sign-off

- **acceptance-reviewer**: ⏳ pending — оценивает: completeness of 13 checklist items (matches freeze-plan Part 4); per-item GWT scenarios actionable; gate scripts achievable in shell+gh+kubectl+psql; no overlap with product-impl scope (test-only PR discipline §13)
- **system-design-reviewer**: ⏳ pending — оценивает orchestrator design (idempotent finding-issue management; exit-code semantics; vault auto-update without push-to-main); cross-repo coordination (gh CLI auth needed for 9 repos)
- **rpc-implementer** (impl) — после APPROVED; assigns KAC-XXX in workspace, creates branch

Status: DRAFT → REVIEW → APPROVED → IMPL ASSIGNED → IN PROGRESS → TEST → DONE (= freeze possible).
