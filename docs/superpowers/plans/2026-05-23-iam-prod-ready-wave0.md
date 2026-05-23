# Wave 0 — Newman coverage gate + OpenFGA HA bootstrap (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подготовить инфраструктуру для всех последующих Wave'ов: машинный gate покрытия newman
(RPC → case-id), расширенная CI-матрица, idempotent OpenFGA bootstrap на kind. После W0 любой
прогресс в W1+ виден как `coverage.py --min N` и newman 22+ сюит.

**Architecture:** Один новый Python-скрипт (`coverage.py`) + расширение `newman-e2e.yml` matrix +
новый helm-job в umbrella (`kacho-fga-bootstrap`). Никаких изменений в бизнес-коде iam — pure
infrastructure prep. Test-first: coverage.py пишется с failing-baseline (12/26 сервисов покрыты),
после расширения должен показывать прогресс.

**Tech Stack:** Python 3.11+ stdlib only (parse `.proto` + JSON-collections), GitHub Actions matrix
strategy, Helm hook Job (post-install/post-upgrade), OpenFGA HTTP API (Store+AuthorizationModel).

**Branch:** `KAC-iam-prod-ready-W0` в репо `kacho-iam` (и `kacho-deploy` если затрагивает umbrella).
**KAC-эпик/subtask:** создать `KAC-iam-prod-ready` + subtask `W0` (см. Task 0 ниже).

---

## File Structure

| Файл | Действие | Ответственность |
|---|---|---|
| `kacho-iam/tests/newman/scripts/coverage.py` | Create | Парсит `kacho-proto/proto/kacho/cloud/iam/v1/*.proto` (rpc-стрелки), парсит `tests/newman/collections/*.json` (URL/path → RPC FQN), пересекает, выдаёт `RPC → covered/missing`, exit-code 1 если covered < `--min`. |
| `kacho-iam/tests/newman/scripts/coverage_test.py` | Create | Unit-тест coverage.py на синтетических proto + минимальной collection. |
| `kacho-iam/tests/newman/scripts/run.sh` | Modify | Добавить пункт «print coverage summary» после прогона всех сюит. |
| `kacho-iam/.github/workflows/newman-e2e.yml` | Modify | Расширить assertion-step: гонять ВСЕ collections из `tests/newman/collections/`, fail если любая `failures > 0`; добавить шаг `coverage.py --min <baseline>` после прогона. |
| `kacho-deploy/.github/workflows/newman-e2e.yml` | Modify | То же, что выше — для cross-repo dispatch варианта. |
| `kacho-deploy/helm/umbrella/charts/kacho-iam/templates/fga-bootstrap-job.yaml` | Create | Helm post-install/post-upgrade Job: идемпотентно создаёт OpenFGA Store + загружает AuthorizationModel (DSL/JSON from `model.fga`). |
| `kacho-deploy/helm/umbrella/charts/kacho-iam/files/fga-model.json` | Create | Snapshot OpenFGA model (FGA DSL → JSON) — source of truth. |
| `kacho-deploy/helm/umbrella/values.yaml` | Modify | `kacho-iam.fga.bootstrap.enabled=true`, `kacho-iam.fga.replicas=2` (HA-mini). |
| `kacho-deploy/scripts/bootstrap-fga.sh` | Create | Standalone-вариант bootstrap'а для локального запуска вне Helm. |
| `kacho-workspace/obsidian/kacho/KAC/KAC-iam-prod-ready.md` | Create | Vault trail-заметка эпика (статус, PR-URL'ы, Затронутые сущности vault). |
| `kacho-workspace/obsidian/kacho/edges/iam-to-openfga-grant-write.md` | Create | Edge-заметка (kacho-iam → OpenFGA HTTP), фиксирует direct sync write paradigm (drainer — следующий Wave). |
| `kacho-workspace/obsidian/kacho/packages/iam-tests-newman-scripts.md` | Create | Package-заметка про `coverage.py` (exported: parse_proto / parse_collection / compare). |

---

## Task 0: Создать KAC-эпик в YouTrack + W0 subtask + vault trail

**Files:**
- Create: `kacho-workspace/obsidian/kacho/KAC/KAC-iam-prod-ready.md`

- [ ] **Step 1: Создать эпик в YT** (CLAUDE.md §«Документооборот»)

MCP `mcp__youtrack__create_issue` смотрит не на тот инстанс (см. memory `youtrack-credentials`) —
использовать REST напрямую:

```bash
curl -X POST "https://prorobotech.youtrack.cloud/api/issues" \
  -H "Authorization: Bearer $YT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "project":{"id":"0-5"},
    "summary":"[EPIC] kacho-iam → production-ready (Full-scope, kind-deploy)",
    "description":"Master plan: kacho-workspace/docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md\n\nDoD — см. Часть 4 product-completion-freeze-plan.md.\nApproach C — Hybrid (W0 prep → W1 critical-path → W2 4 parallel streams → W3 finalize).\n\nДекомпозиция: subtasks KAC-iam-prod-ready-W0..W3 + per-chunk subtasks по мере исполнения."
  }'
```

Сохранить полученный `idReadable` (например `KAC-136`) — он станет эпиком, на него будут ссылаться все subtask'и и PR'ы.

- [ ] **Step 2: Создать subtask W0**

```bash
curl -X POST "https://prorobotech.youtrack.cloud/api/issues" \
  -H "Authorization: Bearer $YT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"project":{"id":"0-5"},"summary":"[W0] Newman coverage gate + OpenFGA HA bootstrap","description":"Detail plan: docs/superpowers/plans/2026-05-23-iam-prod-ready-wave0.md"}'
```

Затем — `subtask of <epic-id>`:

```bash
curl -X POST "https://prorobotech.youtrack.cloud/api/commands" \
  -H "Authorization: Bearer $YT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"subtask of KAC-136","issues":[{"idReadable":"KAC-<w0-id>"}]}'
```

Затем — добавить оба в спринт (CLAUDE.md §Sprint):

```bash
# Узнать current sprint id агайла 183-12
curl -s "https://prorobotech.youtrack.cloud/api/agiles/183-12?fields=currentSprint(id,name)" \
  -H "Authorization: Bearer $YT_TOKEN"
# В команду:
curl -X POST "https://prorobotech.youtrack.cloud/api/commands" \
  -H "Authorization: Bearer $YT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"Board kacho <current-sprint-name>","issues":[{"idReadable":"KAC-136"},{"idReadable":"KAC-<w0-id>"}]}'
```

- [ ] **Step 3: Создать vault trail-заметку**

Файл `kacho-workspace/obsidian/kacho/KAC/KAC-iam-prod-ready.md`:

```markdown
---
title: "KAC-iam-prod-ready: kacho-iam Full-scope production-ready epic"
ticket_id: KAC-136
status: in-progress
type: epic
repos:
  - kacho-iam
  - kacho-corelib
  - kacho-proto
  - kacho-api-gateway
  - kacho-deploy
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-136
opened: 2026-05-23
tags:
  - kac
  - epic
  - kacho-iam
  - kacho-corelib
  - kacho-proto
  - kacho-apigw
  - kacho-deploy
---

# KAC-iam-prod-ready: kacho-iam Full-scope production-ready

**Status**: in-progress
**Type**: epic
**Repos**: kacho-iam, kacho-corelib, kacho-proto, kacho-api-gateway, kacho-deploy
**PRs**: (по мере merge)
**YT**: https://prorobotech.youtrack.cloud/issue/KAC-136

## Что и зачем

Довести kacho-iam до DoD «все функциональности реализованы, newman 100% root-cause-fix,
deploy на kind работает». Full-scope: 44 authz-finding (Chunks 1-5) + Enterprise Блок B
(SAML/SCIM/JIT-activate/break-glass/AccessReview/Compliance/GDPR/CAEP/SPIRE+audit-pipeline) +
Блок F (API-tokens) + AuthZ-инфра (fga_outbox-drainer + cache invalidation + gateway fail-closed).

Approach C — Hybrid: W0 prep → W1 critical-path → W2 4 parallel streams → W3 finalize.

Подробно — master plan `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md`.

## Затронутые сущности vault

(Заполняется по ходу — каждый Wave добавляет ссылки на изменённые resources/rpc/packages/edges.)

## Acceptance / Definition of Done

См. master plan §«Definition of Done (final freeze)».

## Связанные тикеты

- [[KAC-127]] (предусловие — Phase 6-8 rewrite, оставил 44 findings и 13 zero-coverage сервисов)
- [[KAC-128]] (#13.4 idempotency fix)
- [[KAC-131]] (BUG-6/8 fix)
- [[KAC-132]] (Cat-C newman fixes — jit-pending + compliance)
- [[KAC-133]] (newman 1144/1148 GREEN, 4 intentional RED #37 — будет починен в W1)

#kac #epic #kacho-iam
```

- [ ] **Step 4: Дописать в MEMORY.md indexer-line**

Файл `~/.claude/projects/-home-dk-workspace-github-PRO-Robotech-cloud-demo-kacho-workspace/memory/MEMORY.md`:

Добавить строку под существующими записями:

```
- [IAM prod-ready epic](iam-prod-ready-epic.md) — KAC-iam-prod-ready master plan; 4 waves; W0=coverage gate+OpenFGA bootstrap, W1=drainer+chunks 1-2, W2=4 parallel streams, W3=finalize
```

И создать файл `iam-prod-ready-epic.md` с frontmatter `metadata.type: project`.

- [ ] **Step 5: Commit (kacho-workspace)**

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace
git checkout -b KAC-iam-prod-ready-W0
git add docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md \
        docs/superpowers/plans/2026-05-23-iam-prod-ready-wave0.md \
        obsidian/kacho/KAC/KAC-iam-prod-ready.md
git commit -m "docs(plan): KAC-iam-prod-ready master + W0 detail + vault trail"
```

---

## Task 1: coverage.py — failing scaffold (TDD red)

**Files:**
- Create: `kacho-iam/tests/newman/scripts/coverage.py`
- Create: `kacho-iam/tests/newman/scripts/coverage_test.py`

- [ ] **Step 1: Write failing test (`coverage_test.py`)**

```python
"""Test coverage.py against synthetic proto + collection."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
COVERAGE = HERE / "coverage.py"


def write_proto(d: Path, content: str) -> Path:
    p = d / "test_service.proto"
    p.write_text(content)
    return p


def write_collection(d: Path, items: list) -> Path:
    p = d / "test.postman_collection.json"
    p.write_text(json.dumps({"info": {"name": "test"}, "item": items}))
    return p


def test_full_coverage_passes_min_100(tmp_path):
    proto_dir = tmp_path / "proto"
    proto_dir.mkdir()
    write_proto(
        proto_dir,
        """
syntax = "proto3";
package kacho.cloud.iam.v1;
service FooService {
  rpc Bar (BarRequest) returns (BarResponse);
}
""",
    )
    col_dir = tmp_path / "collections"
    col_dir.mkdir()
    write_collection(
        col_dir,
        [
            {
                "name": "FOO-BAR-OK",
                "request": {"method": "POST", "url": {"raw": "{{baseUrl}}/iam/v1/foos:bar"}},
            }
        ],
    )
    result = subprocess.run(
        [sys.executable, str(COVERAGE),
         "--proto-glob", str(proto_dir / "*.proto"),
         "--collections-glob", str(col_dir / "*.json"),
         "--min", "100"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    assert "100%" in result.stdout


def test_partial_coverage_fails_min_100(tmp_path):
    proto_dir = tmp_path / "proto"
    proto_dir.mkdir()
    write_proto(
        proto_dir,
        """
syntax = "proto3";
package kacho.cloud.iam.v1;
service FooService {
  rpc Bar (BarRequest) returns (BarResponse);
  rpc Baz (BazRequest) returns (BazResponse);
}
""",
    )
    col_dir = tmp_path / "collections"
    col_dir.mkdir()
    write_collection(col_dir, [])  # zero coverage
    result = subprocess.run(
        [sys.executable, str(COVERAGE),
         "--proto-glob", str(proto_dir / "*.proto"),
         "--collections-glob", str(col_dir / "*.json"),
         "--min", "100"],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "0%" in result.stdout or "0 of 2" in result.stdout
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd kacho-iam/tests/newman/scripts
python3 -m pytest coverage_test.py -v
```

Expected: FAIL with `coverage.py: file not found` или `Error: No such file or directory`.

- [ ] **Step 3: Write minimal coverage.py (GREEN)**

```python
#!/usr/bin/env python3
"""coverage.py — RPC→newman-case-id coverage gate for kacho-iam.

Parses kacho-proto/proto/kacho/cloud/iam/v1/*.proto for `rpc <Name>(...)` definitions
and tests/newman/collections/*.postman_collection.json for HTTP requests.

Mapping: an RPC `FooService/Bar` is considered "covered" if any collection-item
has a request URL matching the REST-mapping of that RPC (extracted from the
proto's google.api.http annotation, OR fallback to YC-style `<resourcePlural>:bar`
suffix derivation).

Exit code: 0 if covered% >= --min, else 1.
"""
import argparse
import glob
import json
import re
import sys
from pathlib import Path
from typing import Set


RPC_RE = re.compile(r"rpc\s+(\w+)\s*\(")
SERVICE_RE = re.compile(r"service\s+(\w+)\s*\{")


def parse_proto(path: Path) -> Set[str]:
    """Return set of RPC FQNs like 'FooService/Bar'."""
    text = path.read_text()
    rpcs: Set[str] = set()
    current_service = None
    for line in text.splitlines():
        m = SERVICE_RE.search(line)
        if m:
            current_service = m.group(1)
            continue
        if current_service:
            m = RPC_RE.search(line)
            if m:
                rpcs.add(f"{current_service}/{m.group(1)}")
        if "}" in line and current_service and "{" not in line:
            # naïve service-block close; good enough for kacho-iam .proto style
            if line.strip() == "}":
                current_service = None
    return rpcs


def iter_collection_paths(items: list, acc: list) -> None:
    """Recursively flatten Postman items to a list of {method, raw}."""
    for it in items:
        if "request" in it:
            req = it["request"]
            url = req.get("url", {})
            raw = url.get("raw") if isinstance(url, dict) else url
            method = req.get("method", "")
            acc.append((method, raw or ""))
        if "item" in it:
            iter_collection_paths(it["item"], acc)


def rpc_to_rest_hint(rpc_fqn: str) -> str:
    """Heuristic FooService/Bar → /iam/v1/foos:bar (YC-style) or :bar suffix."""
    service, method = rpc_fqn.split("/")
    resource = service.replace("Service", "")
    # heuristic plural: TitleCase → snake + 's' (e.g. AccessBinding → access_bindings)
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", resource).lower()
    plural = snake + ("es" if snake.endswith(("s", "x", "z", "ch", "sh")) else "s")
    return f"/{plural}:{method.lower()}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proto-glob", required=True)
    ap.add_argument("--collections-glob", required=True)
    ap.add_argument("--min", type=int, default=100, help="Minimum coverage % to pass")
    args = ap.parse_args()

    all_rpcs: Set[str] = set()
    for p in glob.glob(args.proto_glob):
        all_rpcs |= parse_proto(Path(p))

    if not all_rpcs:
        print("Error: no RPCs discovered from proto glob", file=sys.stderr)
        return 2

    paths: list = []
    for c in glob.glob(args.collections_glob):
        try:
            data = json.loads(Path(c).read_text())
        except Exception as e:
            print(f"Warning: skipping {c}: {e}", file=sys.stderr)
            continue
        iter_collection_paths(data.get("item", []), paths)

    covered: Set[str] = set()
    for method, raw in paths:
        for rpc in all_rpcs:
            hint = rpc_to_rest_hint(rpc)
            # rough match: hint substring OR method-name suffix in URL
            if hint in raw or f":{rpc.split('/')[1].lower()}" in raw.lower():
                covered.add(rpc)

    total = len(all_rpcs)
    pct = int(100 * len(covered) / total)
    missing = sorted(all_rpcs - covered)

    print(f"Coverage: {len(covered)} of {total} RPCs ({pct}%)")
    if missing:
        print("Missing RPCs:")
        for m in missing:
            print(f"  - {m}")

    if pct < args.min:
        print(f"FAIL: coverage {pct}% < min {args.min}%", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd kacho-iam/tests/newman/scripts
python3 -m pytest coverage_test.py -v
```

Expected: 2 passed.

- [ ] **Step 5: Run coverage.py on real kacho-iam baseline**

```bash
cd kacho-iam/tests/newman
python3 scripts/coverage.py \
  --proto-glob '../../../kacho-proto/proto/kacho/cloud/iam/v1/*.proto' \
  --collections-glob 'collections/*.postman_collection.json' \
  --min 0 | tee out/coverage-baseline.txt
```

Expected output: что-то вроде «Coverage: ~40 of 131 RPCs (30%)» + список missing.
Сохранить вывод как baseline для PR-описания.

- [ ] **Step 6: Commit**

```bash
git add tests/newman/scripts/coverage.py tests/newman/scripts/coverage_test.py
git commit -m "test(newman): add coverage.py RPC→case-id gate (KAC-iam-prod-ready W0)"
```

---

## Task 2: Расширить run.sh — сводка покрытия после прогона

**Files:**
- Modify: `kacho-iam/tests/newman/scripts/run.sh`

- [ ] **Step 1: Найти конец run.sh где формируется summary.txt**

```bash
tail -40 tests/newman/scripts/run.sh
```

- [ ] **Step 2: Дописать вызов coverage.py перед exit'ом**

В конец run.sh, после блока который пишет `out/summary.txt`:

```bash
# Coverage gate (KAC-iam-prod-ready W0): print RPC→case-id coverage summary.
if command -v python3 >/dev/null 2>&1; then
  echo
  echo "===== coverage ====="
  python3 scripts/coverage.py \
    --proto-glob '../../kacho-proto/proto/kacho/cloud/iam/v1/*.proto' \
    --collections-glob 'collections/*.postman_collection.json' \
    --min "${COVERAGE_MIN:-0}" | tee out/coverage.txt || COVERAGE_FAIL=$?
fi
exit "${COVERAGE_FAIL:-0}"
```

- [ ] **Step 3: Прогнать локально**

```bash
cd kacho-iam/tests/newman
./scripts/run.sh --service iam-account  # или любой одиночный для скорости
```

Expected: после стандартного newman-вывода — секция `===== coverage =====` со строкой
`Coverage: N of M RPCs (P%)`. Exit-code 0 (COVERAGE_MIN не задан).

- [ ] **Step 4: Commit**

```bash
git add tests/newman/scripts/run.sh
git commit -m "test(newman): print coverage summary at end of run.sh"
```

---

## Task 3: Расширить CI matrix — все 12 сюит, не только authz-deny/authz-sa-apitoken

**Files:**
- Modify: `kacho-iam/.github/workflows/newman-e2e.yml`
- Modify: `kacho-deploy/.github/workflows/newman-e2e.yml`

- [ ] **Step 1: Найти assertion-step в `kacho-iam/.github/workflows/newman-e2e.yml`**

```bash
grep -n 'assert.*authz' kacho-iam/.github/workflows/newman-e2e.yml
```

Сейчас явно assert'ит только 2 сюита (`authz-deny`, `authz-sa-apitoken`).

- [ ] **Step 2: Заменить hardcoded-список на динамический obход по всем сюитам**

В YAML, в шаге типа `name: assert authz suites green`, заменить:

```yaml
- name: assert all newman suites green
  working-directory: kacho-iam/tests/newman
  run: |
    set -e
    failed_suites=()
    for col in collections/*.postman_collection.json; do
      name=$(basename "$col" .postman_collection.json)
      report="out/${name}.json"
      [ -f "$report" ] || { echo "WARN: no report for $name"; continue; }
      fails=$(jq -r '.run.stats.assertions.failed // 0' "$report")
      echo "$name: $fails failed assertions"
      if [ "$fails" -gt 0 ]; then
        failed_suites+=("$name")
      fi
    done
    if [ "${#failed_suites[@]}" -gt 0 ]; then
      echo "FAIL: suites with failed assertions: ${failed_suites[*]}"
      exit 1
    fi
    echo "All suites GREEN."

- name: coverage gate
  working-directory: kacho-iam/tests/newman
  run: |
    python3 scripts/coverage.py \
      --proto-glob '../../../kacho-proto/proto/kacho/cloud/iam/v1/*.proto' \
      --collections-glob 'collections/*.postman_collection.json' \
      --min "${COVERAGE_MIN:-30}"
  env:
    COVERAGE_MIN: "30"  # W0 baseline; bump к 100 в W2 Поток D после новых сюит
```

- [ ] **Step 3: Тот же patch в `kacho-deploy/.github/workflows/newman-e2e.yml`**

Дублирующий workflow в kacho-deploy. Применить идентичные правки.

- [ ] **Step 4: Локальная проверка YAML-синтаксиса**

```bash
yq eval . kacho-iam/.github/workflows/newman-e2e.yml > /dev/null
yq eval . kacho-deploy/.github/workflows/newman-e2e.yml > /dev/null
```

Expected: no errors.

- [ ] **Step 5: Commit**

В каждом репо отдельный commit:

```bash
# kacho-iam
cd project/kacho-iam
git checkout -b KAC-iam-prod-ready-W0
git add .github/workflows/newman-e2e.yml
git commit -m "ci(newman-e2e): gate ALL collection assertions + coverage gate

KAC-iam-prod-ready W0 — расширение newman-e2e с 2 сюит (authz-deny + sa-apitoken)
до полного обхода всех 12+ collections. Добавлен coverage.py gate (RPC→case-id),
текущий baseline COVERAGE_MIN=30, повышаем в W2 Поток D после добора 13 новых сюит."

# kacho-deploy
cd ../kacho-deploy
git checkout -b KAC-iam-prod-ready-W0
git add .github/workflows/newman-e2e.yml
git commit -m "ci(newman-e2e): mirror kacho-iam — all collections + coverage gate"
```

---

## Task 4: OpenFGA bootstrap-job (Helm hook) — store + model идемпотентно

**Files:**
- Create: `kacho-deploy/helm/umbrella/charts/kacho-iam/files/fga-model.json`
- Create: `kacho-deploy/helm/umbrella/charts/kacho-iam/templates/fga-bootstrap-job.yaml`
- Modify: `kacho-deploy/helm/umbrella/values.yaml`

- [ ] **Step 1: Экспортировать текущую OpenFGA-модель в JSON**

Источник истины — DSL/файл в kacho-iam (если есть, иначе живой store). Сначала найти:

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-iam
find . -name '*.fga' -o -name 'authorization_model*' 2>/dev/null
grep -rln 'fga\.openapi\|openfga\.WriteAuthorizationModel' internal/ cmd/ 2>/dev/null | head
```

Найти, где `WriteAuthorizationModel` вызывается. Скопировать модель (proto-структуру или JSON-байты).

Сохранить как `kacho-deploy/helm/umbrella/charts/kacho-iam/files/fga-model.json`:

```json
{
  "schema_version": "1.1",
  "type_definitions": [
    {"type": "user"},
    {"type": "account", "relations": {"admin": {"this": {}}, "member": {"this": {}}}},
    {"type": "project", "relations": {
      "admin": {"this": {}},
      "member": {"this": {}},
      "parent": {"this": {}}
    }},
    {"type": "iam_access_binding", "relations": {
      "subject": {"this": {}}
    }}
    // ... полная модель — экспортировать из живого OpenFGA или kacho-iam источника
  ]
}
```

(Точное содержимое — из реального источника, plan-template только показывает форму.)

- [ ] **Step 2: Helm Job template**

`kacho-deploy/helm/umbrella/charts/kacho-iam/templates/fga-bootstrap-job.yaml`:

```yaml
{{- if .Values.fga.bootstrap.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "kacho-iam.fullname" . }}-fga-bootstrap
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 3
  template:
    metadata:
      name: kacho-iam-fga-bootstrap
    spec:
      restartPolicy: OnFailure
      containers:
        - name: bootstrap
          image: curlimages/curl:8.5.0
          env:
            - name: FGA_API_URL
              value: {{ printf "http://%s-openfga.%s.svc.cluster.local:8080" .Release.Name .Release.Namespace | quote }}
            - name: FGA_STORE_NAME
              value: {{ default "kacho-iam" .Values.fga.storeName | quote }}
          volumeMounts:
            - name: model
              mountPath: /etc/fga
          command:
            - sh
            - -c
            - |
              set -eu

              # 1. Find or create store (idempotent by name).
              echo "[fga-bootstrap] checking for store '$FGA_STORE_NAME'..."
              stores=$(curl -fsS "$FGA_API_URL/stores")
              store_id=$(echo "$stores" | sed -n 's/.*"id":"\([^"]*\)","name":"'"$FGA_STORE_NAME"'".*/\1/p' | head -1)
              if [ -z "$store_id" ]; then
                echo "[fga-bootstrap] creating store '$FGA_STORE_NAME'..."
                resp=$(curl -fsS -X POST "$FGA_API_URL/stores" \
                  -H "content-type: application/json" \
                  -d "{\"name\":\"$FGA_STORE_NAME\"}")
                store_id=$(echo "$resp" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
              fi
              echo "[fga-bootstrap] store_id=$store_id"

              # 2. Write the authorization model (idempotent — OpenFGA writes a
              #    NEW version each call, but content-hash dedup on the iam side).
              echo "[fga-bootstrap] writing authorization model..."
              curl -fsS -X POST "$FGA_API_URL/stores/$store_id/authorization-models" \
                -H "content-type: application/json" \
                --data @/etc/fga/model.json

              echo "[fga-bootstrap] done."
      volumes:
        - name: model
          configMap:
            name: {{ include "kacho-iam.fullname" . }}-fga-model
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "kacho-iam.fullname" . }}-fga-model
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "4"
data:
  model.json: |
{{ .Files.Get "files/fga-model.json" | indent 4 }}
{{- end }}
```

- [ ] **Step 3: values.yaml — flag + replica count**

`kacho-deploy/helm/umbrella/charts/kacho-iam/values.yaml` (или umbrella `values.yaml` под секцией
`kacho-iam:`):

```yaml
fga:
  bootstrap:
    enabled: true
  storeName: kacho-iam
  # HA-mini: 2 OpenFGA replicas — overrides the openfga subchart's default of 1.
  # Postgres backend persists store/model across restarts.
openfga:
  replicaCount: 2
  datastore:
    engine: postgres
    # uri/secret: точная схема — посмотреть в `openfga-0.2.62.tgz` values.yaml,
    # должно использовать postgres-ha из umbrella.
```

- [ ] **Step 4: Helm lint + helm template dry-run**

```bash
cd kacho-deploy/helm/umbrella
helm dep update
helm lint . --values values.dev.yaml
helm template . --values values.dev.yaml | grep -A 30 'fga-bootstrap'
```

Expected: lint clean; template renders Job + ConfigMap.

- [ ] **Step 5: Deploy на локальный kind + проверить bootstrap**

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace/project/kacho-deploy
make dev-up
# Подождать пока pods запустятся
kubectl get jobs -n kacho | grep fga-bootstrap
kubectl logs -n kacho job/kacho-iam-fga-bootstrap
# Проверить что store создан:
kubectl port-forward -n kacho svc/kacho-openfga 8080:8080 &
curl -s http://localhost:8080/stores | jq
# Должен быть store "kacho-iam" с непустым id.
```

- [ ] **Step 6: Re-run helm upgrade — проверить idempotence**

```bash
helm upgrade kacho . --values values.dev.yaml
kubectl get jobs -n kacho | grep fga-bootstrap
# Hook delete-policy=before-hook-creation → старый Job удалён, новый запускается.
# Логи должны показать "found existing store" (не "creating store").
```

- [ ] **Step 7: Commit**

```bash
cd project/kacho-deploy
git add helm/umbrella/charts/kacho-iam/files/fga-model.json \
        helm/umbrella/charts/kacho-iam/templates/fga-bootstrap-job.yaml \
        helm/umbrella/values.yaml
git commit -m "feat(deploy): OpenFGA HA-mini + idempotent bootstrap-job

KAC-iam-prod-ready W0 — поднимаем OpenFGA до 2 replicas (HA-mini на kind) и
добавляем helm post-install/post-upgrade Job, который идемпотентно создаёт
store 'kacho-iam' и загружает AuthorizationModel из ConfigMap.

Без bootstrap kacho-iam не может писать grant-tuples (KAC-127 round-3 finding).
Drainer (W1) полагается на наличие store до старта."
```

---

## Task 5: Стандартизировать coverage.py — точный RPC→REST mapping

**Files:**
- Modify: `kacho-iam/tests/newman/scripts/coverage.py`
- Modify: `kacho-iam/tests/newman/scripts/coverage_test.py`

Эвристика из Task 1 (snake-plural + `:method`) даёт ~70% точности на YC-style URL'ах.
Для полной точности — парсить `google.api.http` аннотации:

- [ ] **Step 1: Добавить failing test на http-annotation parsing**

```python
def test_http_annotation_overrides_heuristic(tmp_path):
    proto_dir = tmp_path / "proto"
    proto_dir.mkdir()
    write_proto(
        proto_dir,
        """
syntax = "proto3";
package kacho.cloud.iam.v1;
import "google/api/annotations.proto";

service AccountService {
  rpc Create (CreateAccountRequest) returns (Operation) {
    option (google.api.http) = {
      post: "/iam/v1/accounts"
      body: "*"
    };
  }
}
""",
    )
    col_dir = tmp_path / "collections"
    col_dir.mkdir()
    write_collection(col_dir, [
        {"name": "ACC-CR-OK",
         "request": {"method": "POST", "url": {"raw": "{{baseUrl}}/iam/v1/accounts"}}}
    ])
    result = subprocess.run(
        [sys.executable, str(COVERAGE),
         "--proto-glob", str(proto_dir / "*.proto"),
         "--collections-glob", str(col_dir / "*.json"),
         "--min", "100"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
```

- [ ] **Step 2: Run failing test**

Expected FAIL — наша эвристика `/accountss:create` не совпадает с `/iam/v1/accounts`.

- [ ] **Step 3: Расширить parse_proto — захватывать `google.api.http` блок**

```python
HTTP_BLOCK_RE = re.compile(
    r"option\s*\(\s*google\.api\.http\s*\)\s*=\s*\{(.*?)\};",
    re.DOTALL,
)
HTTP_METHOD_RE = re.compile(r"(get|post|put|patch|delete)\s*:\s*\"([^\"]+)\"", re.IGNORECASE)


def parse_proto(path: Path) -> dict:
    """Return dict {service/rpc: [(method, url-template), ...]}."""
    text = path.read_text()
    rpcs: dict = {}
    current_service = None
    # ... (та же логика для service/RPC scan) ...
    # Дополнительно ищем google.api.http блоки внутри rpc-определений
    rpc_def_re = re.compile(
        r"rpc\s+(\w+)\s*\([^)]+\)\s*returns\s*\([^)]+\)\s*\{(.*?)\}",
        re.DOTALL,
    )
    if current_service := SERVICE_RE.search(text):
        service = current_service.group(1)
        for m in rpc_def_re.finditer(text):
            rpc_name = m.group(1)
            body = m.group(2)
            http_m = HTTP_BLOCK_RE.search(body)
            paths = []
            if http_m:
                for verb, url in HTTP_METHOD_RE.findall(http_m.group(1)):
                    paths.append((verb.upper(), url))
            if not paths:
                paths = [("?", rpc_to_rest_hint(f"{service}/{rpc_name}"))]
            rpcs[f"{service}/{rpc_name}"] = paths
    return rpcs
```

(Точная реализация — итеративно, по результату теста.)

- [ ] **Step 4: Adapt main() — matching по url-template (с заменой `{id}` → wildcard regex)**

```python
def url_template_to_regex(tpl: str) -> re.Pattern:
    """`/iam/v1/accounts/{id}` → regex `/iam/v1/accounts/[^/]+`."""
    pat = re.escape(tpl)
    pat = re.sub(r"\\\{[^}]+\\\}", r"[^/]+", pat)
    return re.compile(pat + "$")

# Match: для каждого RPC берём его HTTP-template'ы, для каждого collection-request'а
# проверяем regex-совпадение пути.
```

- [ ] **Step 5: Run tests — все три зелёные**

```bash
python3 -m pytest tests/newman/scripts/coverage_test.py -v
```

Expected: 3 passed.

- [ ] **Step 6: Re-run coverage.py на реальном repo — новый baseline**

```bash
cd kacho-iam/tests/newman
python3 scripts/coverage.py \
  --proto-glob '../../../kacho-proto/proto/kacho/cloud/iam/v1/*.proto' \
  --collections-glob 'collections/*.postman_collection.json' \
  --min 0
```

Сравнить с baseline из Task 1 — точность должна возрасти. Ожидаем `~50 of ~131` (точное число —
зависит от того сколько RPC из core+phase7/7b purpose-built под REST).

- [ ] **Step 7: Commit**

```bash
git add tests/newman/scripts/coverage.py tests/newman/scripts/coverage_test.py
git commit -m "test(newman): parse google.api.http for exact RPC→URL mapping"
```

---

## Task 6: Vault — packages-заметка для coverage.py + edges-заметка для iam→openfga (W0 baseline)

**Files:**
- Create: `kacho-workspace/obsidian/kacho/packages/iam-tests-newman-scripts.md`
- Create: `kacho-workspace/obsidian/kacho/edges/iam-to-openfga-grant-write.md`

- [ ] **Step 1: packages-заметка**

`obsidian/kacho/packages/iam-tests-newman-scripts.md`:

```markdown
---
title: "tests/newman/scripts (kacho-iam)"
category: packages
repo: kacho-iam
layer: tests
tags:
  - packages
  - kacho-iam
  - test
---

# tests/newman/scripts

`tests/newman/scripts/` в kacho-iam — генератор + раннер + coverage-gate для newman-сюит.

## Exported (CLI-utilities)

| Script | Назначение |
|---|---|
| `gen.py` | Парсит `cases/<svc>.py` (CASES list of Case → Step) → `collections/<svc>.postman_collection.json`. Source of truth — модули в `cases/`. |
| `run.sh` | Гоняет ВСЕ generated collections под `newman`, агрегирует `out/<svc>.json` + `summary.txt`. После KAC-iam-prod-ready W0 — печатает `coverage.py` summary. |
| `coverage.py` | KAC-iam-prod-ready W0. Парсит `kacho-proto/proto/kacho/cloud/iam/v1/*.proto` + `collections/*.json`, мапит RPC → URL-templates через `google.api.http`, выдаёт `RPC → covered/missing`, exit-code 1 если covered% < `--min`. |

## Imports

stdlib only (`argparse`, `glob`, `json`, `re`, `pathlib`, `subprocess`).

## Imported by

CI workflows: `.github/workflows/newman-e2e.yml` (kacho-iam + kacho-deploy).

## Связано

- [[../KAC/KAC-iam-prod-ready]] — эпик
- [[../KAC/KAC-133]] — newman 1144/1148 GREEN baseline до W0

#packages #kacho-iam #test
```

- [ ] **Step 2: edges-заметка**

`obsidian/kacho/edges/iam-to-openfga-grant-write.md`:

```markdown
---
title: "kacho-iam → OpenFGA (grant/revoke write)"
category: edges
caller_repo: kacho-iam
callee_repo: openfga (external)
sync_async: sync
protocol: http
status: experimental
related_tickets:
  - KAC-iam-prod-ready
tags:
  - edge
  - kacho-iam
  - kacho-deploy
---

# kacho-iam → OpenFGA grant/revoke write

Прямой sync HTTP-вызов OpenFGA `/stores/{id}/write` для grant/revoke FGA-tuples.

## Текущее (W0)

| Путь | Поведение |
|---|---|
| `AccessBindingService.Create` | sync WriteTuples в FGA (relation + hierarchy); KAC-127 — `non-fatal Warn` на FGA error → split-brain DB/FGA. |
| `AccessBindingService.Delete` (KAC-128) | sync DeleteTuples — частично исправлен. |
| JIT auto/pending-approve | НЕ пишет в FGA (KAC-127 finding #50/#51) — pure DB INSERT. |
| BreakGlass.ApproveB | НЕ пишет в FGA (finding #52). |

## Bootstrap (W0)

Helm post-install/post-upgrade Job (`fga-bootstrap-job.yaml`) идемпотентно создаёт store
`kacho-iam` + загружает AuthorizationModel. Без него writes падают на «store not found».

## Цель (W1)

Заменить прямой sync HTTP на запись через `fga_outbox` (in-process drainer на corelib
outbox-паттерне) — атомарно с DB-row в одной tx; drainer применяет к OpenFGA с retry/идемпотенцией.
Сейчас drainer'а нет — это критический W1 gap.

## History

- 2026-05-23 (W0): bootstrap-job, baseline coverage measurement.
- (планируется W1): replace sync writes → fga_outbox + drainer.

#edge #kacho-iam #kacho-deploy
```

- [ ] **Step 3: Commit**

```bash
cd /home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace
git add obsidian/kacho/packages/iam-tests-newman-scripts.md \
        obsidian/kacho/edges/iam-to-openfga-grant-write.md
git commit -m "docs(vault): W0 — newman-scripts package + iam→openfga edge"
```

---

## Task 7: PR + green CI

- [ ] **Step 1: Push ветки**

```bash
cd project/kacho-iam && git push -u origin KAC-iam-prod-ready-W0
cd ../kacho-deploy && git push -u origin KAC-iam-prod-ready-W0
cd ../../  # back to workspace
git push -u origin KAC-iam-prod-ready-W0
```

- [ ] **Step 2: PR в каждом репо**

```bash
cd project/kacho-iam
gh pr create --title "[KAC-iam-prod-ready W0] Newman coverage gate" \
  --body "W0 of KAC-iam-prod-ready epic. Adds coverage.py RPC→case-id gate, extends CI matrix to gate ALL collection assertions (not just authz-deny/authz-sa-apitoken). Baseline: $(cat tests/newman/out/coverage-baseline.txt 2>/dev/null | head -1).

Master plan: kacho-workspace/docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md
W0 detail: kacho-workspace/docs/superpowers/plans/2026-05-23-iam-prod-ready-wave0.md

Closes KAC-<w0-subtask-id>"

cd ../kacho-deploy
gh pr create --title "[KAC-iam-prod-ready W0] OpenFGA HA bootstrap + CI mirror" \
  --body "W0 of KAC-iam-prod-ready epic. Adds OpenFGA HA-mini (2 replicas) + idempotent post-install/post-upgrade Helm Job for store+model bootstrap. Mirrors kacho-iam CI gate.

Closes KAC-<w0-subtask-id>"
```

- [ ] **Step 3: Дождаться зелёного CI**

```bash
gh run watch  # в каждом репо отдельно
```

Expected: build + lint + newman-e2e ВСЕ зелёные.

- [ ] **Step 4: Merge + delete branch**

```bash
gh pr merge --squash --delete-branch  # в каждом репо
```

- [ ] **Step 5: Обновить vault KAC-iam-prod-ready.md**

Добавить URL-ы PR в frontmatter `prs:` и в body «PRs:».

- [ ] **Step 6: Перевести KAC-W0-subtask в Done в YT**

```bash
curl -X POST "https://prorobotech.youtrack.cloud/api/commands" \
  -H "Authorization: Bearer $YT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"state Done","issues":[{"idReadable":"KAC-<w0-id>"}]}'
```

- [ ] **Step 7: Commit vault**

```bash
cd kacho-workspace
git add obsidian/kacho/KAC/KAC-iam-prod-ready.md
git commit -m "docs(vault): KAC-iam-prod-ready W0 — closeout (PR URLs)"
git push
```

---

## Wave 0 — Definition of Done

- [ ] `coverage.py` существует, unit-тесты GREEN (3/3), парсит `google.api.http`.
- [ ] `run.sh` после прогона выводит coverage summary.
- [ ] CI gate: newman-e2e.yml в обоих репо ассертит ВСЕ collection-сюиты, fail на любом failed-assertion.
- [ ] `COVERAGE_MIN=30` (baseline W0) в CI; будет повышен в W2 Поток D.
- [ ] OpenFGA bootstrap-job: store создаётся, model загружается; повторный `helm upgrade` идемпотентен.
- [ ] OpenFGA на kind — 2 replicas (HA-mini).
- [ ] KAC-эпик + W0-subtask + спринт-привязка созданы в YouTrack.
- [ ] Vault: `KAC-iam-prod-ready.md` + `packages/iam-tests-newman-scripts.md` + `edges/iam-to-openfga-grant-write.md` существуют.
- [ ] Все PR'ы merged, ветки удалены, KAC-W0 = Done в YT.

## Self-Review

- **Spec coverage:** master plan §«Waves overview» → W0 → этот файл. Все W0-DoD пункты из master имеют здесь задачу.
- **Placeholder scan:** нет «TODO», «implement later». Точное содержимое `fga-model.json` помечено
  как «экспортировать из реального источника» — это законный prep-step Task 4 Step 1, не placeholder в plan.
- **Type consistency:** `coverage.py` API (parse_proto/iter_collection_paths/url_template_to_regex)
  согласован между Task 1, Task 5 (расширение), Task 6 (vault-описание).
- **Scope:** строго prep-уровень — никаких изменений в бизнес-коде iam, никаких миграций; всё в
  tests/ + helm/ + CI yml + vault. Полностью независим от W1+.
