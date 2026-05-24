#!/usr/bin/env bash
# Freeze gate orchestrator — runs all 13 check scripts and reports a summary.
#
# Exit codes:
#   0 — all 13 checks pass
#   1 — at least one check failed (skipped checks do not block)
#   2 — at least one check crashed (infra issue, not a product gap)
#
# Reads each check-NN-*.sh script in lexical order, captures rc and output,
# and prints a table. If KACHO_FREEZE_OUTPUT_JSON is set to a path, also
# writes a JSON report there for downstream consumption (vault dashboard,
# GH Actions issue creator).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
checks=("$SCRIPT_DIR"/check-*.sh)
shopt -u nullglob

if [ ${#checks[@]} -eq 0 ]; then
    echo "no check scripts found in $SCRIPT_DIR" >&2
    exit 2
fi

declare -a names
declare -a statuses
declare -a details

failed=0
crashed=0
passed=0
skipped=0

for c in "${checks[@]}"; do
    name=$(basename "$c" .sh)
    name=${name#check-}
    echo
    echo "=== $name ==="
    out_file="$(mktemp)"
    "$c" >"$out_file" 2>&1
    rc=$?
    out=$(cat "$out_file")
    rm -f "$out_file"

    # Echo output for visibility
    [ -n "$out" ] && echo "$out"

    names+=("$name")
    case "$rc" in
        0)
            statuses+=("PASS")
            passed=$((passed + 1))
            details+=("$(echo "$out" | grep '^\[PASS\]' | head -1 || true)")
            ;;
        1)
            statuses+=("FAIL")
            failed=$((failed + 1))
            details+=("$(echo "$out" | grep '^\[FAIL\]' | head -1 || true)")
            ;;
        2)
            statuses+=("SKIP")
            skipped=$((skipped + 1))
            details+=("$(echo "$out" | grep '^\[SKIP\]' | head -1 || true)")
            ;;
        *)
            statuses+=("CRASH")
            crashed=$((crashed + 1))
            details+=("script exited with rc=$rc")
            ;;
    esac
done

echo
echo "=== Freeze gate summary ==="
printf '%-32s  %s\n' "CHECK" "STATUS"
printf '%-32s  %s\n' "--------------------------------" "------"
for i in "${!names[@]}"; do
    printf '%-32s  %s\n' "${names[$i]}" "${statuses[$i]}"
done

echo
echo "Totals: PASS=$passed FAIL=$failed SKIP=$skipped CRASH=$crashed (of ${#checks[@]})"

# Optional JSON report.
if [ -n "${KACHO_FREEZE_OUTPUT_JSON:-}" ]; then
    json="${KACHO_FREEZE_OUTPUT_JSON}"
    {
        printf '{\n'
        printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  "totals": {"pass": %d, "fail": %d, "skip": %d, "crash": %d, "total": %d},\n' \
            "$passed" "$failed" "$skipped" "$crashed" "${#checks[@]}"
        printf '  "checks": [\n'
        last=$(( ${#names[@]} - 1 ))
        for i in "${!names[@]}"; do
            sep=","
            [ "$i" -eq "$last" ] && sep=""
            d=${details[$i]//\"/\\\"}
            printf '    {"name": "%s", "status": "%s", "detail": "%s"}%s\n' \
                "${names[$i]}" "${statuses[$i]}" "$d" "$sep"
        done
        printf '  ]\n'
        printf '}\n'
    } > "$json"
    echo "JSON report written to $json"
fi

if [ "$crashed" -gt 0 ]; then exit 2; fi
if [ "$failed" -gt 0 ]; then exit 1; fi

echo
echo "FREEZE GATE: all ${#checks[@]} checks pass — freeze is possible"
exit 0
