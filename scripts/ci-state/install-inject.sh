#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# install-inject.sh — доказательство установщика службы ci-stated ИСПОЛНЕНИЕМ (ws#1151).
# Установщик — настоящий scripts/ci-state/install.sh на копии дерева (юнит, демон,
# scripts/lib/gh-rate.sh); подменены лишь команды машины: systemctl, systemd-analyze,
# journalctl и gh — двойниками, которые пишут вызовы в журнал. Двойник systemctl на
# restart пишет снимки так, как их пишет демон (имя <владелец>__<имя>__<PR>.json,
# поле checked_at), по перечню $SC_SNAP_REPOS и с возрастом $SC_SNAP_AGE; сам демон
# доказан scripts/ci-state/inject.sh. Строки systemd-analyze — дословные с машины, путь
# в них двойник печатает, как systemd 259: realpath -ms (замер 2026-10-17: абсолютный,
# без ./ и //, ссылки не раскрыты). Вызов установщика — под пределом 60 с.
#
# СЦЕНЫ (каждая меняет один факт против близнеца (1)):
#   (1) установка: код 0; настройки 0600 с KACHO_WS; юнит равен дереву; порядок
#       daemon-reload → enable → restart; «по репозиториям 3 из 3»; повтор поверх
#       ссылки прежней установки — код 0, на месте ссылки файл;
#   (2) --repos юнита и DEFAULT_REPOS демона разошлись → 2, правок нет;
#   (3) токен не из keyring | keyring не ответил → 4, правок нет;
#   (4) остаток лимита 50 < 1500 → 3 со временем сброса, правок нет;
#   (5) verify: код 0, но строка о нашем файле («…, ignoring») → 2 | код 1 → 2 |
#       строка о нашем файле при TMPDIR <abs>/./x, <abs>//x, ./x → 2; включения нет;
#       близнец — строка о ЧУЖОМ юните при коде 0 (и при TMPDIR=./x) → установка идёт;
#   (6) служба failed | inactive после restart | перезапускалась (NRestarts 1) → 1 и
#       disable --now;
#   (7) служба active, но у воркспейса снимков нет | снимки старше перезапуска → 3,
#       служба НЕ снята;
#   (8) --check: после (1) → 0; копия юнита правлена → 1; снимок старше 180 с → 1;
#       служба failed → 1; KACHO_WS без демона → 1;
#   (9) --ws без демона → 2;
#   (10) политика перезапуска юнита: RestartPreventExitStatus с 6 | без 4 | без 4 после
#       сброса пустым присваиванием, Restart=no → 2, правок нет; близнец — 2 и 4
#       двумя строками (перечень копится) → установка идёт;
#   (11) нет scripts/lib/gh-rate.sh → 2 с причиной, правок нет.
# Сверяется код И напечатанное, а не только «покраснел».
#
# МУТАНТЫ — копия install.sh либо юнита с одним дефектом обязана уронить сцену; в
# строке KILLED — код установщика и его последняя строка на убившей сцене. install.sh:
# repos-dropped, keyring-dropped, rate-dropped, rate-lib-unguarded, verify-line-dropped,
# verify-literal-unnormalized, failed-kept, restarts-dropped, I6c-inactive-dropped,
# fresh-dropped, check-drift-dropped, I8b-check-active-dropped, I8c-check-ws-dropped,
# restart-check-dropped, prevent4-check-dropped, prevent6-check-dropped; юнит:
# U1-prevent-has-6, U2-restart-no. Правка, не легшая в текст, — VOID.
#
# ИСХОДЫ: 0 — контроль зелёный, все мутанты убиты; 1 — сцена разошлась либо мутант
# выжил; 2 — судить нечем (нет jq, python3, дерева).
# shellcheck disable=SC2016  # условие chk — текст для eval
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCR="$(dirname "$HERE")"
command -v jq >/dev/null 2>&1 || { echo "VOID: нет jq" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "VOID: нет python3" >&2; exit 2; }
for f in "$HERE/install.sh" "$HERE/ci-stated.service" "$HERE/ci-stated.py" "$SCR/lib/gh-rate.sh"; do
    [ -r "$f" ] || { echo "VOID: нет $f" >&2; exit 2; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-stated-install-inject.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT
REPOS3="PRO-Robotech/kacho,PRO-Robotech/kaname,PRO-Robotech/kacho-workspace"
mkdir -p "$T/bin"

cat > "$T/bin/systemctl" <<'SC'
#!/usr/bin/env bash
echo "$*" >> "$SCLOG"
shift   # --user
case "$1" in
    is-active) echo "${SC_ACTIVE:-active}"; [ "${SC_ACTIVE:-active}" = active ] ;;
    show) case "$*" in *NRestarts*) echo "${SC_NRESTARTS:-0}" ;; *MainPID*) echo "${SC_PID:-0}" ;; esac ;;
    restart)
        mkdir -p "$CI_STATE_DIR/snap"; now=$(( $(date +%s) - ${SC_SNAP_AGE:-0} ))
        IFS=, read -r -a rs <<< "${SC_SNAP_REPOS-}"
        for r in "${rs[@]}"; do [ -n "$r" ] && printf '{"checked_at": %s, "code": 0}\n' "$now" > "$CI_STATE_DIR/snap/${r/\//__}__7.json"; done ;;
esac
exit 0
SC
cat > "$T/bin/systemd-analyze" <<'SA'
#!/usr/bin/env bash
f="$(realpath -ms -- "${@: -1}")"   # как systemd 259: абсолютный, без ./ и //, ссылки не раскрыты
case "${SA_MODE:-clean}" in
    clean) echo "/usr/lib/systemd/user/spice-vdagent.service:23: Unknown key 'StandardError' in section [Install], ignoring." >&2 ;;
    ignoring) echo "$f:42: Unknown key 'Restrat' in section [Service], ignoring." >&2 ;;
    nobin) echo "ci-stated.service: Command /usr/bin/python9 is not executable: Нет такого файла или каталога" >&2; exit 1 ;;
esac
exit 0
SA
cat > "$T/bin/journalctl" <<'JC'
#!/usr/bin/env bash
echo "журнал-двойник: ci-stated.py: ОТКАЗ СТАРТА"
JC
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status")
    [ "${AUTH_SRC:-keyring}" != down ] || { echo "error connecting to keyring" >&2; exit 1; }
    printf '{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"probe","tokenSource":"%s"}]}}\n' "${AUTH_SRC:-keyring}" ;;
  "api rate_limit")
    j="$(printf '{"resources":{"core":{"limit":5000,"remaining":%s,"reset":4102444800},"graphql":{"limit":5000,"remaining":4900,"reset":4102444800}}}' "${RATE_REM:-4900}")"
    if [ "${3:-}" = -q ]; then jq -r "$4" <<< "$j"; else echo "$j"; fi ;;
  *) echo "gh-двойник: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$T/bin/"*

# tree <каталог> <install.sh> <юнит> — копия дерева: юнит, демон, gh-rate.sh, установщик
tree() {
    mkdir -p "$1/scripts/ci-state" "$1/scripts/lib"
    cp "$3" "$1/scripts/ci-state/ci-stated.service"; cp "$HERE/ci-stated.py" "$1/scripts/ci-state/"
    cp "$SCR/lib/gh-rate.sh" "$1/scripts/lib/"; cp "$2" "$1/scripts/ci-state/install.sh"
}
fails=""; out=""; code=""
chk() { if eval "$2"; then echo "  [OK]   $1"; else echo "  [FAIL] $1 — код ${code:-?}"; fails="$fails; $1 [код ${code:-?}: $(tail -n1 <<<"$out" | cut -c1-140)]"
    [ -z "$out" ] || tail -4 <<<"$out" | sed 's/^/         /'; fi; }
# inst <каталог сцены> <доводы…> — install.sh копии дерева сцены; out, code
inst() {
    local w="$1"; shift
    out="$(cd "${INST_CWD:-.}" && PATH="$T/bin:$PATH" SCLOG="$w/sclog" CI_STATED_SYSTEMCTL="$T/bin/systemctl" \
        CI_STATED_ANALYZE="${INST_SA:-$T/bin/systemd-analyze}" CI_STATED_JOURNALCTL="$T/bin/journalctl" CI_STATED_GH="$T/bin/gh" \
        CI_STATED_UNIT_DIR="$w/unit" CI_STATED_ENV_DIR="$w/env" CI_STATE_DIR="$w/state" CI_STATED_STEP=1 TMPDIR="${INST_TMPDIR:-$w}" \
        timeout 60 bash "$w/tree/scripts/ci-state/install.sh" "$@" 2>&1)"; code=$?
}
# scene <каталог> <install.sh> <юнит> — чистое место: дерево, ws с демоном, журнал вызовов
scene() { rm -rf "$1"; mkdir -p "$1/ws/scripts/ci-state"; tree "$1/tree" "$2" "$3"
    cp "$HERE/ci-stated.py" "$1/ws/scripts/ci-state/"; : > "$1/sclog"; }
untouched() { [ ! -s "$1/sclog" ] && [ ! -e "$1/env/ci-stated.env" ] && [ ! -e "$1/unit/ci-stated.service" ]; }
ordered() { grep -oE '^--user (daemon-reload|enable|restart)' "$1/sclog" | cut -d' ' -f2 | paste -sd' '; }

scenes() {  # scenes <install.sh> <юнит> <корень> → печать; $fails
    local is="$1" un="$2" w="$3/w"
    fails=""
    export SC_SNAP_REPOS="$REPOS3" SC_SNAP_AGE=0 SC_ACTIVE=active SC_NRESTARTS=0 AUTH_SRC=keyring RATE_REM=4900 SA_MODE=clean

    echo "== (1) установка и повтор"
    scene "$w" "$is" "$un"; inst "$w" --ws "$w/ws" --wait 5
    chk "код 0, по репозиториям 3 из 3" '[ "$code" -eq 0 ] && grep -q "по репозиториям 3 из 3" <<<"$out"'
    chk "настройки 0600: KACHO_WS=<ws>" '[ "$(stat -c %a "$w/env/ci-stated.env")" = 600 ] && [ "$(cat "$w/env/ci-stated.env")" = "KACHO_WS=$w/ws" ]'
    chk "юнит — копия дерева, не ссылка" '[ -f "$w/unit/ci-stated.service" ] && [ ! -L "$w/unit/ci-stated.service" ] && cmp -s "$w/unit/ci-stated.service" "$un"'
    chk "порядок: daemon-reload → enable → restart" '[ "$(ordered "$w")" = "daemon-reload enable restart" ]'
    rm -f "$w/unit/ci-stated.service"; ln -s "$HERE/ci-stated.service" "$w/unit/ci-stated.service"
    inst "$w" --ws "$w/ws" --wait 5
    chk "повтор поверх ссылки: код 0, на месте ссылки файл" '[ "$code" -eq 0 ] && [ -f "$w/unit/ci-stated.service" ] && [ ! -L "$w/unit/ci-stated.service" ]'

    echo "== (2) перечни разошлись"
    scene "$w" "$is" "$un"; sed -i 's/^DEFAULT_REPOS = .*/DEFAULT_REPOS = "PRO-Robotech\/kacho,PRO-Robotech\/kaname"/' "$w/tree/scripts/ci-state/ci-stated.py"
    inst "$w" --ws "$w/ws" --wait 5
    chk "--repos юнита ≠ DEFAULT_REPOS: код 2, правок нет" '[ "$code" -eq 2 ] && grep -q "перечни разошлись" <<<"$out" && untouched "$w"'

    echo "== (3) токен не из keyring"
    local s
    for s in oauth_token down; do
        scene "$w" "$is" "$un"; AUTH_SRC="$s" inst "$w" --ws "$w/ws" --wait 5
        chk "источник $s: код 4, правок нет" '[ "$code" -eq 4 ] && grep -q keyring <<<"$out" && untouched "$w"'
    done

    echo "== (4) лимит ниже порога"
    scene "$w" "$is" "$un"; RATE_REM=50 inst "$w" --ws "$w/ws" --wait 5
    chk "остаток 50 < 1500: код 3, сброс назван, правок нет" '[ "$code" -eq 3 ] && grep -q "сброс в" <<<"$out" && untouched "$w"'

    echo "== (5) verify"
    scene "$w" "$is" "$un"; SA_MODE=ignoring inst "$w" --ws "$w/ws" --wait 5
    chk "код 0 и строка «ignoring» о нашем файле: код 2, правок нет" '[ "$code" -eq 2 ] && grep -q "ignoring" <<<"$out" && untouched "$w"'
    scene "$w" "$is" "$un"; SA_MODE=nobin inst "$w" --ws "$w/ws" --wait 5
    chk "verify код 1: код 2, правок нет" '[ "$code" -eq 2 ] && untouched "$w"'
    local tf
    for tf in "$w/./x" "$w//x" "./x"; do   # verify печатает путь нормализованным
        scene "$w" "$is" "$un"; mkdir -p "$w/x"
        SA_MODE=ignoring INST_CWD="$w" INST_TMPDIR="$tf" inst "$w" --ws "$w/ws" --wait 5
        chk "TMPDIR=${tf/#$w/<abs>}, строка «Restrat … ignoring»: код 2, правок нет" '[ "$code" -eq 2 ] && grep -q "Restrat" <<<"$out" && untouched "$w"'
    done
    scene "$w" "$is" "$un"; mkdir -p "$w/x"; INST_CWD="$w" INST_TMPDIR=./x inst "$w" --ws "$w/ws" --wait 5
    chk "близнец: TMPDIR=./x, строка лишь о чужом юните — установка, код 0" '[ "$code" -eq 0 ] && grep -q "по репозиториям 3 из 3" <<<"$out"'

    echo "== (6) служба не поднялась"
    scene "$w" "$is" "$un"; SC_ACTIVE=failed inst "$w" --ws "$w/ws" --wait 5
    chk "failed: код 1, disable --now, журнал напечатан" '[ "$code" -eq 1 ] && grep -q "^--user disable --now" "$w/sclog" && grep -q "журнал-двойник" <<<"$out"'
    scene "$w" "$is" "$un"; SC_NRESTARTS=1 inst "$w" --ws "$w/ws" --wait 5
    chk "перезапускалась (NRestarts 1): код 1, disable --now" '[ "$code" -eq 1 ] && grep -q "^--user disable --now" "$w/sclog"'
    scene "$w" "$is" "$un"; SC_ACTIVE=inactive inst "$w" --ws "$w/ws" --wait 5
    chk "inactive: код 1, disable --now" '[ "$code" -eq 1 ] && grep -q "^--user disable --now" "$w/sclog" && grep -q "не поднялась (inactive" <<<"$out"'

    echo "== (7) первый проход не подтверждён"
    scene "$w" "$is" "$un"; SC_SNAP_REPOS="PRO-Robotech/kacho,PRO-Robotech/kaname" inst "$w" --ws "$w/ws" --wait 2
    chk "у воркспейса снимков нет: код 3, служба не снята" '[ "$code" -eq 3 ] && grep -q "kacho-workspace: свежих снимков 0" <<<"$out" && ! grep -q "disable" "$w/sclog"'
    scene "$w" "$is" "$un"; SC_SNAP_AGE=600 inst "$w" --ws "$w/ws" --wait 2
    chk "снимки старше перезапуска: код 3" '[ "$code" -eq 3 ] && grep -q "kacho: свежих снимков 0" <<<"$out"'

    echo "== (8) --check"
    scene "$w" "$is" "$un"; inst "$w" --ws "$w/ws" --wait 5; inst "$w" --check
    chk "после установки: код 0, сверка прошла" '[ "$code" -eq 0 ] && grep -q "сверка прошла" <<<"$out"'
    echo "# правка" >> "$w/unit/ci-stated.service"; inst "$w" --check
    chk "копия юнита правлена: код 1, «разошёлся»" '[ "$code" -eq 1 ] && grep -q "разошёлся" <<<"$out"'
    scene "$w" "$is" "$un"; inst "$w" --ws "$w/ws" --wait 5
    for f in "$w/state/snap/"*.json; do printf '{"checked_at": %s}\n' $(( $(date +%s) - 200 )) > "$f"; done
    inst "$w" --check
    chk "снимки старше 180 с: код 1" '[ "$code" -eq 1 ] && grep -q "свежих снимков 0" <<<"$out"'

    scene "$w" "$is" "$un"; inst "$w" --ws "$w/ws" --wait 5; SC_ACTIVE=failed inst "$w" --check
    chk "служба failed: код 1, «служба: failed»" '[ "$code" -eq 1 ] && grep -q "служба: failed" <<<"$out"'
    scene "$w" "$is" "$un"; inst "$w" --ws "$w/ws" --wait 5; rm "$w/ws/scripts/ci-state/ci-stated.py"; inst "$w" --check
    chk "KACHO_WS без демона: код 1, «без демона»" '[ "$code" -eq 1 ] && grep -q "без демона" <<<"$out"'

    echo "== (9) --ws без демона"
    scene "$w" "$is" "$un"; rm "$w/ws/scripts/ci-state/ci-stated.py"; inst "$w" --ws "$w/ws" --wait 5
    chk "код 2, правок нет" '[ "$code" -eq 2 ] && untouched "$w"'

    echo "== (10) политика перезапуска юнита"
    local pol
    for pol in 's/^RestartPreventExitStatus=.*/RestartPreventExitStatus=2 4 6/:с 6' 's/^Restart=.*/Restart=no/:Restart=«no»' \
               's/^RestartPreventExitStatus=.*/RestartPreventExitStatus=2/:без 4' 's/^RestartPreventExitStatus=.*/&\nRestartPreventExitStatus=\nRestartPreventExitStatus=2/:без 4'; do
        scene "$w" "$is" "$un"; sed -i -e "${pol%:*}" "$w/tree/scripts/ci-state/ci-stated.service"
        inst "$w" --ws "$w/ws" --wait 5
        chk "юнит «${pol%:*}»: код 2 («${pol##*:}»), правок нет" '[ "$code" -eq 2 ] && grep -qF "${pol##*:}" <<<"$out" && untouched "$w"'
    done
    scene "$w" "$is" "$un"; sed -i -e 's/^RestartPreventExitStatus=.*/RestartPreventExitStatus=2\nRestartPreventExitStatus=4/' "$w/tree/scripts/ci-state/ci-stated.service"
    inst "$w" --ws "$w/ws" --wait 5
    chk "близнец: 2 и 4 двумя строками — перечень копится, установка, код 0" '[ "$code" -eq 0 ]'

    echo "== (11) нет scripts/lib/gh-rate.sh"
    scene "$w" "$is" "$un"; rm "$w/tree/scripts/lib/gh-rate.sh"; inst "$w" --ws "$w/ws" --wait 5
    chk "код 2, причина названа, правок нет" '[ "$code" -eq 2 ] && grep -q "gh-rate.sh — остаток лимита не проверить" <<<"$out" && untouched "$w"'
}

echo "### контроль"
scenes "$HERE/install.sh" "$HERE/ci-stated.service" "$T/control"
ctl_fails="$fails"
echo
[ -z "$ctl_fails" ] && echo "контроль: все сцены сошлись" || echo "контроль: разошлось —${ctl_fails#;}"

echo
echo "### мутанты — каждый обязан уронить сцену (install — установщик, unit — юнит дерева)"
killed=0; survived=0; void=0
while IFS=$'\t' read -r name file expr; do
    [ -n "$name" ] || continue
    m="$T/mut/$name"; mkdir -p "$m"
    cp "$HERE/install.sh" "$m/install.sh"; cp "$HERE/ci-stated.service" "$m/ci-stated.service"
    if [ "$file" = unit ]; then src="$HERE/ci-stated.service"; dst="$m/ci-stated.service"; else src="$HERE/install.sh"; dst="$m/install.sh"; fi
    sed -e "$expr" "$src" > "$dst"
    if cmp -s "$dst" "$src"; then void=$((void + 1)); echo "  MUTANT $name → RESULT VOID (правка не легла)"; continue; fi
    scenes "$m/install.sh" "$m/ci-stated.service" "$m" > "$m/out" 2>&1
    if [ -n "$fails" ]; then killed=$((killed + 1)); echo "  MUTANT $name → RESULT KILLED (${fails#; })"
    else survived=$((survived + 1)); echo "  MUTANT $name → RESULT SURVIVED"; fi
done <<'MUT'
repos-dropped	install	s/\[ "\$REPOS" = "\$DEF" \] ||/true ||/
keyring-dropped	install	s/\[ "\$src" = keyring \] ||/true ||/
rate-dropped	install	s/^if ! short="\$(gh_rate_short/if false \&\& short="$(gh_rate_short/
rate-lib-unguarded	install	/gh-rate.sh" ] || die 2 /d; s/ || die 2 "\$HERE\/\.\.\/lib\/gh-rate\.sh не подключилась[^"]*"$//; /^declare -F gh_rate_short/d
verify-line-dropped	install	s/ || grep -qF "\$T\/\$UNIT:" "\$T\/verify" || grep -qE "[^"]*" "\$T\/verify"//
verify-literal-unnormalized	install	/^T="\$(realpath -ms/d; s/ || grep -qE "[^"]*" "\$T\/verify"//
failed-kept	install	s/^        "\$SC" --user disable --now "\$UNIT" >\/dev\/null 2>&1$/        :/
restarts-dropped	install	s/\[ "\$nr" -gt 0 \]/false/
I6c-inactive-dropped	install	s/ || \[ "\$st" = inactive \]//
fresh-dropped	install	s/\.checked_at >= \$t'/true'/
check-drift-dropped	install	s/^    if ! cmp -s "\$SRC_UNIT"/    if false \&\& cmp -s "$SRC_UNIT"/
I8b-check-active-dropped	install	s/^    \[ "\$st" = active \] ||/    true ||/
I8c-check-ws-dropped	install	s/^    if \[ -z "\$ws" \] || \[ ! -r "\$ws\/scripts\/ci-state\/ci-stated\.py" \]; then/    if false; then/
restart-check-dropped	install	s/^\[ "\$RESTART" = on-failure \] ||/true ||/
prevent4-check-dropped	install	s/^\[\[ "\$PREVENT" == \*" 4 "\* \]\] ||/true ||/
prevent6-check-dropped	install	s/^\[\[ "\$PREVENT" != \*" 6 "\* \]\] ||/true ||/
U1-prevent-has-6	unit	s/^RestartPreventExitStatus=2 4$/RestartPreventExitStatus=2 4 6/
U2-restart-no	unit	s/^Restart=on-failure$/Restart=no/
MUT

echo
echo "ci-stated-install-inject: мутантов $((killed + survived + void)), убито $killed, выжило $survived, не легло $void"
[ -z "$ctl_fails" ] && [ "$survived" -eq 0 ] && [ "$void" -eq 0 ] && [ "$killed" -gt 0 ]
