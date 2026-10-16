#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-14 «каждый скрипт, который зовёт
# хук, существует». Оси: S — команда хука в настройках ведёт в снятый файл;
# R — провязанный хук зовёт снятый скрипт (класс rag-freshness): жертва
# выводится из дерева; T — то же через промежуточный скрипт (транзитивно);
# близнецы — снятый скрипт назван лишь в комментарии, промежуточный зовёт живой;
# V — настроек нет либо команд хуков ноль — отказ.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции; запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i14_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i14_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: «$_i14_fn» не определена" >&2
    exit 2
done
unset -v _i14_fn

C14=check-14-hook-scripts-exist.sh

# i14_hook <каталог> <событие> <путь от корня> — провязать хук командой в настройках.
i14_hook() {
    python3 - "$1/.claude/settings.json" "$2" "$3" <<'PY'
import collections, json, sys
p, ev, rel = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
d.setdefault("hooks", {}).setdefault(ev, []).append(
    {"hooks": [{"type": "command", "command": 'bash "$CLAUDE_PROJECT_DIR/%s"' % rel}]})
open(p, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
PY
}

# Жертва оси R — провязанный хук, зовущий соседний файл через `$HOOK_DIR/…`: из дерева.
victim_hook=""; victim_callee=""; i14_seen=0
for _h in "$WS"/.claude/hooks/*.sh; do
    i14_seen=$((i14_seen + 1))
    _n="$(basename "$_h")"
    grep -qF ".claude/hooks/$_n" "$WS/.claude/settings.json" || continue
    # shellcheck disable=SC2016  # `$HOOK_DIR` — образец поиска, не подстановка.
    _c="$(grep -v '^[[:space:]]*#' "$_h" | grep -oE '\$HOOK_DIR/[A-Za-z0-9_./-]+\.(py|sh)' | head -1)"
    [ -n "$_c" ] || continue
    victim_hook="$_n"; victim_callee="${_c#\$HOOK_DIR/}"; break
done
unset -v _h _n _c
echo "жертва оси R выведена из дерева: осмотрено хуков $i14_seen; хук «${victim_hook:-нет}», вызываемый «${victim_callee:-нет}»"

echo
echo "== check-14 ось S: команда хука ведёт в снятый файл =="
d="$(sandbox i14_s)"
i14_hook "$d" Stop ".claude/hooks/inj14-retired.sh"
capture "$d" "$C14"
assert_code 1 "ДЕФЕКТ: в настройках провязан хук, файла которого нет"
assert_says "СКРИПТА ХУКА НЕТ" "  ...и вердикт назван своим именем"
assert_says ".claude/hooks/inj14-retired.sh" "  ...и координата названа"

d="$(sandbox i14_s_twin)"; b="$(sandbox_digest "$d")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.claude/hooks/inj14-live.sh"
i14_hook "$d" Stop ".claude/hooks/inj14-live.sh"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: провязан новый хук, файл есть"
capture "$d" "$C14"
assert_code 0 "БЛИЗНЕЦ: провязанный хук с файлом — молчит"

echo
echo "== check-14 ось R: провязанный хук зовёт снятый скрипт =="
if [ -z "$victim_hook" ]; then
    echo "  [FAIL] жертвы нет: ни один провязанный хук не зовёт соседний файл через \$HOOK_DIR — ось R недоказуема" >&2
    fail=$((fail + 1))
else
    d="$(sandbox i14_r)"
    rm -f "$d/.claude/hooks/$victim_callee"
    capture "$d" "$C14"
    assert_code 1 "ДЕФЕКТ: у хука $victim_hook снят скрипт $victim_callee, которого он зовёт"
    assert_says "СКРИПТА, КОТОРЫЙ ЗОВЁТ ХУК, НЕТ" "  ...и вердикт назван своим именем"
    assert_says ".claude/hooks/$victim_hook:" "  ...и названа строка зовущего"

    d="$(sandbox i14_r_twin)"; b="$(sandbox_digest "$d")"
    # shellcheck disable=SC2016  # вносится текст комментария хука, не подстановка.
    printf '\n# прежде звал "$HOOK_DIR/inj14-retired.sh" — снят\n' >> "$d/.claude/hooks/$victim_hook"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: снятый скрипт назван в комментарии хука"
    capture "$d" "$C14"
    assert_code 0 "БЛИЗНЕЦ: комментарий — не вызов, молчит"
fi

echo
echo "== check-14 ось T: снятый скрипт зовётся через промежуточный =="
d="$(sandbox i14_t)"
# shellcheck disable=SC2016  # `$(dirname …)` — текст вносимого скрипта, не подстановка здесь.
printf '#!/usr/bin/env bash\nexec bash "$(dirname "${BASH_SOURCE[0]}")/inj14-mid.sh"\n' > "$d/.claude/hooks/inj14-top.sh"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nhere="$(dirname "${BASH_SOURCE[0]}")"\nbash "$here/inj14-gone.sh"\n' > "$d/.claude/hooks/inj14-mid.sh"
i14_hook "$d" UserPromptSubmit ".claude/hooks/inj14-top.sh"
capture "$d" "$C14"
assert_code 1 "ДЕФЕКТ: хук → промежуточный скрипт → снятый"
assert_says ".claude/hooks/inj14-mid.sh:3" "  ...и названа строка промежуточного"

d="$(sandbox i14_t_twin)"; b="$(sandbox_digest "$d")"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec bash "$(dirname "${BASH_SOURCE[0]}")/inj14-mid.sh"\n' > "$d/.claude/hooks/inj14-top.sh"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nhere="$(dirname "${BASH_SOURCE[0]}")"\nbash "$here/inj14-gone.sh"\n' > "$d/.claude/hooks/inj14-mid.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.claude/hooks/inj14-gone.sh"
i14_hook "$d" UserPromptSubmit ".claude/hooks/inj14-top.sh"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: та же цепочка, конечный скрипт есть"
capture "$d" "$C14"
assert_code 0 "БЛИЗНЕЦ: цепочка до живого скрипта — молчит"

echo
echo "== check-14 ось V: предмета нет — отказ =="
d="$(sandbox i14_v)"
rm -f "$d/.claude/settings.json"
capture "$d" "$C14"
assert_code 2 "ОТКАЗ: настроек нет"

d="$(sandbox i14_v_empty)"
python3 - "$d/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["hooks"] = {}
open(p, "w").write(json.dumps(d))
PY
capture "$d" "$C14"
assert_code 2 "ОТКАЗ: команд хуков ноль — не «находок 0»"
