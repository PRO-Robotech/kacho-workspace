#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# Инъекция признака хука отправки (scripts/push-hook.sh) и лёгкой отправки слота (ws#1335).
#
# Решение диспетчера 2026-10-22, вариант б: `git push` в клоне без хука отправки — лёгкая
# команда; с хуком — только слотом класса ci-local. Предмет здесь — слот: страж судит тот же
# признак, его доказательство — .claude/hooks/heavy-guard/prove.sh.
#
# Настоящие репозитории git и голый приёмник в TMPDIR; кластер — двойник run.sh, который лишь
# пишет свой argv: настоящий Job отправка без хука звать не вправе.
#   · клон без хука: `heavy-slot.sh ci-local -- git push …` исполняет отправку (ветка в приёмнике),
#     слота машины не берёт, кластер не спрашивает, журнал — строка light; --route — local
#     с основанием «хука отправки нет»;
#   · клон с хуком (дерево, установленный, core.hooksPath, `-c core.hooksPath=`): лёгкого пути
#     нет — хук не исполнен, ветки в приёмнике нет, кластер спрошен;
#   · обёртка перед git — лишь присваивания, env, setsid, nohup, timeout: `make git push` — не
#     отправка, слот её судит как прежде.
# Коды: 0 — всё сошлось; 1 — нет; 2 — не построено (нет git).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT="$HERE/heavy-slot.sh"
PH="$HERE/push-hook.sh"
W="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
pass=0; fail=0
assert() {
    if [ "$1" = "$2" ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else echo "  [FAIL] $3 — ожидалось «$1», получено «$2»" >&2; fail=$((fail + 1)); fi
}
command -v git > /dev/null || { echo "[VOID] git нет — ничего не построено" >&2; exit 2; }
# Подпись песочницы — из корневого gitconfig (scripts/lib/sandbox-git-home.sh, tooling-gate check-16).
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/ghome" || { echo "[VOID] корневой подписи нет — клоны не построены" >&2; exit 2; }

gx() { sandbox_git -c init.defaultBranch=main "$@" > /dev/null 2>&1; }
gx init -q --bare "$W/recv.git"
for r in none tree inst hpath; do
    gx init -q "$W/$r"; gx -C "$W/$r" commit -q --allow-empty -m "$r"
    git -C "$W/$r" remote add origin "$W/recv.git"
done
mkdir -p "$W/tree/scripts/hooks" "$W/hookdir"
printf '#!/bin/sh\ntouch "%s/ran.tree"\n' "$W" > "$W/tree/scripts/hooks/pre-push"
printf '#!/bin/sh\ntouch "%s/ran.inst"\n' "$W" > "$W/inst/.git/hooks/pre-push"; chmod +x "$W/inst/.git/hooks/pre-push"
printf '#!/bin/sh\ntouch "%s/ran.hpath"\n' "$W" > "$W/hookdir/pre-push"; chmod +x "$W/hookdir/pre-push"
git -C "$W/hpath" config core.hooksPath "$W/hookdir"

cat > "$W/fake-run.sh" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = --request ] && { echo "1000 1000"; exit 0; }
printf '%s\n' "$@" >> "$FAKE_ARGV"
[ "${1:-}" = --available ] && exit 0
exit 17
FAKE
chmod +x "$W/fake-run.sh"
printf 'MemTotal: %d kB\nMemAvailable: %d kB\n' $((98304 * 1024)) $((97000 * 1024)) > "$W/meminfo"
export HEAVY_SLOT_DIR="$W/slots" HEAVY_SLOT_MEMINFO="$W/meminfo" HEAVY_SLOT_LIMIT_MIB=100000 \
       HEAVY_SLOT_POLL_S=1 HEAVY_SLOT_WAIT_S=2 HEAVY_SLOT_BUDGET_MIB=64 \
       HEAVY_SLOT_REMOTE_RUN="$W/fake-run.sh" FAKE_ARGV="$W/argv"

# hs <каталог> <аргументы слота…> — код слота; вывод в $W/out, $W/err.
hs() { local d="$1"; shift; (cd "$d" && bash "$SLOT" "$@" > "$W/out" 2> "$W/err"); echo $?; }
ref() { git -C "$W/recv.git" rev-parse -q --verify "refs/heads/$1" > /dev/null 2>&1 && echo есть || echo нет; }
asked() { [ -s "$W/argv" ] && echo да || echo нет; }
slots() { local n=0 f; for f in "$HEAVY_SLOT_DIR"/active/*.slot; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }

echo "── признак: push-hook.sh отвечает по виду хука"
for r in none tree inst hpath; do
    (cd "$W/$r" && bash "$PH" > "$W/ph.$r"); echo "$?" > "$W/ph.$r.rc"
done
assert "1 0 0 0" "$(cat "$W/ph.none.rc") $(cat "$W/ph.tree.rc") $(cat "$W/ph.inst.rc") $(cat "$W/ph.hpath.rc")" "коды: без хука 1; дерево, установленный, core.hooksPath — 0"
assert "absent present present present" "$(for r in none tree inst hpath; do cut -f2 "$W/ph.$r"; done | tr '\n' ' ' | sed 's/ $//')" "строка PUSH-HOOK называет вид"
assert "0" "$(cd "$W/none" && bash "$PH" -c "core.hooksPath=$W/hookdir" > /dev/null; echo $?)" "-c core.hooksPath= перед push — хук есть"
assert "1" "$(cd "$W/none" && bash "$PH" -c color.ui=never -c advice.pushUpdateRejected=false -c http.lowSpeedLimit=1 > /dev/null; echo $?)" "близнец: ключи закрытого перечня безвредных признака не меняют (и git не подаются)"
printf '[core]\n\thooksPath = %s\n' "$W/hookdir" > "$W/inc"; printf '[color]\n\tui = never\n' > "$W/inc-none"
assert "0 0 0 0 0 0" "$(for f in "-c include.path=$W/inc" "-c includeIf.gitdir:$W/.path=$W/inc" "--config-env=core.hooksPath=HP" "--config-env core.hooksPath=HP" "-c include.path=$W/inc-none" "-c core.fsmonitor=true"; do (cd "$W/none" && HP="$W/hookdir" bash "$PH" $f > /dev/null; printf '%s ' "$?"); done | sed 's/ $//')" "признак: include.path, includeIf.*.path, --config-env (обе записи), include без hooksPath, ключ вне перечня — хук есть"
assert "0" "$(cd "$W/none" && bash "$PH" --git-dir="$W/inst/.git" > /dev/null; echo $?)" "--git-dir — судится отправляемый клон, а не каталог"
assert "2" "$(cd "$W" && bash "$PH" > /dev/null; echo $?)" "не репозиторий — 2"
chmod -x "$W/inst/.git/hooks/pre-push"
assert "1" "$(cd "$W/inst" && bash "$PH" > /dev/null; echo $?)" "неисполняемый .git/hooks/pre-push git не зовёт — хука нет"
chmod +x "$W/inst/.git/hooks/pre-push"

echo "── слот: клон без хука — отправка сразу, без слота и кластера"
rm -f "$W/argv"
assert "0 есть нет 0" "$(hs "$W/none" ci-local -- git push -q origin HEAD:refs/heads/lane-a) $(ref lane-a) $(asked) $(slots)" "ci-local -- git push: код 0, ветка в приёмнике, кластер не спрошен, слотов 0"
assert "да" "$(grep -q 'light class=ci-local route=push-no-hook' "$HEAVY_SLOT_DIR/journal.log" 2> /dev/null && echo да || echo нет)" "журнал — строка light route=push-no-hook"
assert "да" "$(grep -qF 'хука отправки нет' "$W/err" && echo да || echo нет)" "слот называет основание: «хука отправки нет»"
assert "0 есть" "$(hs "$W/none" ci-local -- env GIT_TERMINAL_PROMPT=0 git -C "$W/none" push -q origin HEAD:refs/heads/lane-b) $(ref lane-b)" "обёртка env и -C — та же лёгкая отправка"
rc="$(hs "$W/none" --route ci-local -- git push origin HEAD:refs/heads/lane-c)"
assert "0 local да" "$rc $(cut -f2 "$W/out" | head -n 1) $(grep -qF 'хука отправки нет' "$W/out" && echo да || echo нет)" "--route: local, основание названо"
assert "нет" "$(ref lane-c)" "--route отправку не исполнил"

echo "── слот: клон с хуком — лёгкого пути нет (хук не исполнен, ветки нет, кластер спрошен)"
for r in tree inst hpath; do
    rm -f "$W/argv"
    rc="$(hs "$W/$r" ci-local -- git push -q origin "HEAD:refs/heads/hook-$r")"
    assert "не0 нет нет да" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(ref "hook-$r") $([ -e "$W/ran.$r" ] && echo да || echo нет) $(asked)" "хук «$r»: код $rc ≠ 0, ветки нет, хук локально не исполнен, кластер спрошен"
done
rm -f "$W/argv"
rc="$(hs "$W/none" ci-local -- git -c "core.hooksPath=$W/hookdir" push -q origin HEAD:refs/heads/hook-cli)"
assert "не0 нет да" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(ref hook-cli) $(asked)" "-c core.hooksPath= в команде: код $rc ≠ 0, ветки нет, кластер спрошен"
rm -f "$W/argv"
rc="$(hs "$W/none" ci-local -- make -C "$W/none" git push)"
assert "не0 да" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(asked)" "make git push — не отправка: лёгкого пути нет (код $rc), кластер спрошен"
echo "── слот: окружение, -C и --git-dir перед git — лёгкий путь лишь по признаку целевого клона (возврат приёмки)"
printf '[core]\n\thooksPath = %s\n' "$W/hookdir" > "$W/gcfg"
mkdir -p "$W/h"; cp "$W/gcfg" "$W/h/.gitconfig"
# heavyform <имя> <слова команды…> — из клона без хука: лёгкого пути нет (код ≠ 0, ветки нет,
# хук локально не исполнен, кластер спрошен).
heavyform() {
    local id="$1" rc; shift
    rm -f "$W/argv" "$W"/ran.*
    rc="$(hs "$W/none" ci-local -- "$@" push -q origin "HEAD:refs/heads/e-$id")"
    assert "не0 нет нет да" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(ref "e-$id") $(ls "$W"/ran.* > /dev/null 2>&1 && echo да || echo нет) $(asked)" "«$id»: код $rc ≠ 0, ветки нет, хук не исполнен, кластер спрошен"
}
heavyform git-dir-env env "GIT_DIR=$W/inst/.git" git
heavyform work-tree-env env "GIT_WORK_TREE=$W/tree" git
heavyform config-count env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath "GIT_CONFIG_VALUE_0=$W/hookdir" git
heavyform config-params env "GIT_CONFIG_PARAMETERS='core.hooksPath'='$W/hookdir'" git
heavyform config-global env "GIT_CONFIG_GLOBAL=$W/gcfg" git
heavyform home env "HOME=$W/h" git
heavyform dash-C git -C "$W/inst"
heavyform git-dir-opt git "--git-dir=$W/inst/.git"
heavyform env-chdir env -C "$W/inst" git
# Контроль: настоящий git исполняет хук по include.path, includeIf и --config-env (без слота).
for f in "include.path=$W/inc" "includeIf.gitdir:$W/.path=$W/inc"; do
    rm -f "$W"/ran.*; (cd "$W/none" && git -c "$f" push -q origin "HEAD:refs/heads/ctl-$RANDOM" > /dev/null 2>&1)
    assert "да" "$([ -e "$W/ran.hpath" ] && echo да || echo нет)" "контроль: git -c $f… исполняет хук сам"
done
rm -f "$W"/ran.*; (cd "$W/none" && HP="$W/hookdir" git --config-env=core.hooksPath=HP push -q origin "HEAD:refs/heads/ctl-env" > /dev/null 2>&1)
assert "да" "$([ -e "$W/ran.hpath" ] && echo да || echo нет)" "контроль: git --config-env=core.hooksPath=HP исполняет хук сам"
heavyform include-path git -c "include.path=$W/inc"
heavyform include-if git -c "includeIf.gitdir:$W/.path=$W/inc"
heavyform config-env env "HP=$W/hookdir" git --config-env=core.hooksPath=HP
heavyform config-env-2 env "HP=$W/hookdir" git --config-env core.hooksPath=HP
heavyform include-none git -c "include.path=$W/inc-none"
for f in "-c include.path=$W/inc" "-c includeIf.gitdir:$W/.path=$W/inc" "--config-env=core.hooksPath=HP"; do
    rc="$(hs "$W/none" --route ci-local -- env "HP=$W/hookdir" git $f push origin HEAD:refs/heads/r-x)"
    assert "0 не-local" "$rc $([ "$(cut -f2 "$W/out" | head -n 1)" = local ] && echo local || echo не-local)" "--route: $f — не лёгкая"
done
rm -f "$W/argv"
assert "0 есть нет" "$(hs "$W/none" ci-local -- git -c color.ui=never -c advice.pushUpdateRejected=false -c http.lowSpeedLimit=1 push -q origin HEAD:refs/heads/e-safe-cfg) $(ref e-safe-cfg) $(asked)" "близнец: -c ключей закрытого перечня — лёгкая, ветка в приёмнике, кластер не спрошен"
rm -f "$W/argv"
assert "0 есть нет" "$(hs "$W/tree" ci-local -- env -C "$W/none" git push -q origin HEAD:refs/heads/e-chdir-light) $(ref e-chdir-light) $(asked)" "близнец: env -C <клон без хука> из клона с хуком — лёгкая, ветка в приёмнике, кластер не спрошен"
rm -f "$W/argv" "$W"/ran.*
rc="$( (cd "$W/none" && GIT_CONFIG_GLOBAL="$W/gcfg" bash "$SLOT" ci-local -- git push -q origin HEAD:refs/heads/e-global > "$W/out" 2> "$W/err"); echo $?)"
assert "не0 нет да" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(ref e-global) $(asked)" "глобальный слой core.hooksPath в окружении слота: код $rc ≠ 0, ветки нет, кластер спрошен"
for brk in 'exit 1' 'exit 2' 'if then'; do
    k="brk-${brk// /_}"; mkdir -p "$W/m-$k"; cp "$SLOT" "$W/m-$k/heavy-slot.sh"; printf '%s\n' "$brk" > "$W/m-$k/push-hook.sh"
    rm -f "$W/argv" "$W"/ran.*
    rc="$( (cd "$W/inst" && bash "$W/m-$k/heavy-slot.sh" ci-local -- git push -q origin "HEAD:refs/heads/$k" > /dev/null 2>&1); echo $?)"
    assert "не0 нет нет" "$([ "$rc" != 0 ] && echo не0 || echo 0) $(ref "$k") $([ -e "$W/ran.inst" ] && echo да || echo нет)" "сломанный признак («$brk») в клоне с хуком: код $rc ≠ 0, ветки нет, хук не исполнен — лёгкой отправка не стала"
done
assert "0" "$(slots)" "после всех проб слотов машины 0"

echo "── мутанты слота: каждое утверждение выше читает свой предмет"
# smut <имя> <фрагмент> <замена> — копия слота с порчей рядом с настоящим признаком.
smut() {
    mkdir -p "$W/m-$1"; cp "$PH" "$W/m-$1/push-hook.sh"
    python3 -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[3]) != 1:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))' "$SLOT" "$W/m-$1/heavy-slot.sh" "$2" "$3"
}
if smut always-light '    [ "$rc" = 1 ] && [[' '    true || [['; then
    (cd "$W/tree" && bash "$W/m-always-light/heavy-slot.sh" ci-local -- git push -q origin HEAD:refs/heads/mut-a > /dev/null 2>&1)
    assert "есть" "$(ref mut-a)" "мутант «всякая отправка лёгкая»: клон с хуком отправил без слота — утверждение «хук tree: ветки нет» его ловит"
else assert "построен" "не построен" "мутант always-light: фрагмент не единствен"; fi
if smut no-light 'if [ "$CLASS" = ci-local ] && push_light; then
    journal_early' 'if false; then
    journal_early'; then
    rm -f "$W/argv"; (cd "$W/none" && bash "$W/m-no-light/heavy-slot.sh" ci-local -- git push -q origin HEAD:refs/heads/mut-b > /dev/null 2>&1)
    assert "нет да" "$(ref mut-b) $(asked)" "мутант «лёгкого пути нет»: клон без хука идёт к кластеру — утверждение «ветка в приёмнике, кластер не спрошен» его ловит"
else assert "построен" "не построен" "мутант no-light: фрагмент не единствен"; fi
if smut wrapper-any '            *) return 1 ;;
        esac
    done
    i=$(( i + 1 ))' '            *) i=$(( i + 1 )) ;;
        esac
    done
    i=$(( i + 1 ))'; then
    rm -f "$W/argv"; (cd "$W/none" && bash "$W/m-wrapper-any/heavy-slot.sh" ci-local -- make -C "$W/none" git push > /dev/null 2>&1)
    assert "нет" "$(asked)" "мутант «любое слово перед git — обёртка»: make git push исполнен лёгким — утверждение «make git push: кластер спрошен» его ловит"
else assert "построен" "не построен" "мутант wrapper-any: фрагмент не единствен"; fi
if smut no-dash-C '            -C|-c|--git-dir|--work-tree|--namespace) o+=("$w" "${CMD_R[$(( i + 1 ))]:-}"); i=$(( i + 2 )) ;;' '            -C|-c|--git-dir|--work-tree|--namespace) i=$(( i + 2 )) ;;'; then
    (cd "$W/none" && bash "$W/m-no-dash-C/heavy-slot.sh" ci-local -- git -C "$W/inst" push -q origin HEAD:refs/heads/mut-c > /dev/null 2>&1)
    assert "есть" "$(ref mut-c)" "мутант «-C признаку не передан»: клон с хуком отправил лёгким — утверждение «dash-C» его ловит"
else assert "построен" "не построен" "мутант no-dash-C: фрагмент не единствен"; fi
if smut env-transparent '                *=*) [ -n "$ev" ] || return 1; o=("$w" "${o[@]}"); i=$(( i + 1 )); continue ;;' '                *=*) i=$(( i + 1 )); continue ;;'; then
    rm -f "$W"/ran.*; (cd "$W/none" && bash "$W/m-env-transparent/heavy-slot.sh" ci-local -- env "GIT_DIR=$W/inst/.git" git push -q origin HEAD:refs/heads/mut-d > /dev/null 2>&1)
    assert "есть" "$(ref mut-d)" "мутант «присваивания признаку не переданы»: env GIT_DIR=<клон с хуком> отправил лёгким — утверждение «git-dir-env» его ловит"
else assert "построен" "не построен" "мутант env-transparent: фрагмент не единствен"; fi

echo "[CENSUS] push-hook-inject: утверждений $((pass + fail)), сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ]
