#!/usr/bin/env bash
# Freeze gate check #12 — observability artefacts present (W3.2 outputs).
#
# Verifies that:
#   - kacho-deploy ships at least one Grafana dashboard JSON
#   - kacho-deploy ships at least one VMAlert / Prometheus alert rule file
#   - Workspace vault has at least one runbook under observability/
#
# Exit 0 = artefacts present, 1 = gaps, 2 = kacho-deploy missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

WS="$(freeze_gate_workspace_root)"
NAME="12-observability-ready"

if ! freeze_gate_repo_cloned "$WS" kacho-deploy; then
    freeze_gate_skip "$NAME" "kacho-deploy not cloned"
    exit 2
fi

DEPLOY="$WS/project/kacho-deploy"
gaps=0

# Grafana dashboards
dashboards=$(find "$DEPLOY" -type f \( -name '*dashboard*.json' -o -path '*/dashboards/*.json' \) 2>/dev/null | wc -l)
if [ "$dashboards" -eq 0 ]; then
    echo "[gap] no Grafana dashboard JSON files under $DEPLOY"
    gaps=$((gaps + 1))
else
    echo "[ok]   $dashboards dashboard file(s)"
fi

# Alert rules — VMAlert / PrometheusRule manifests, or .yaml under rules/
rules=$(find "$DEPLOY" -type f \( -name '*alert*.yaml' -o -name '*rules*.yaml' -o -path '*/vmalert/*' -o -path '*/prometheusrules/*' \) 2>/dev/null | wc -l)
if [ "$rules" -eq 0 ]; then
    echo "[gap] no VMAlert / PrometheusRule files under $DEPLOY"
    gaps=$((gaps + 1))
else
    echo "[ok]   $rules alert rule file(s)"
fi

# Runbooks in vault
if [ -d "$WS/obsidian/kacho" ]; then
    runbooks=$(find "$WS/obsidian/kacho" -type f \( -name 'runbook*.md' -o -path '*/runbooks/*.md' -o -path '*/observability/*.md' \) 2>/dev/null | wc -l)
    if [ "$runbooks" -eq 0 ]; then
        echo "[gap] no runbook entries under $WS/obsidian/kacho"
        gaps=$((gaps + 1))
    else
        echo "[ok]   $runbooks vault runbook entry/entries"
    fi
fi

if [ "$gaps" -gt 0 ]; then
    freeze_gate_fail "$NAME" "$gaps observability artefact(s) missing"
    exit 1
fi

freeze_gate_pass "$NAME" "dashboards + alert rules + runbooks present"
exit 0
