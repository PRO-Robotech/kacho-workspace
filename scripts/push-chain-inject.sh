#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# push-chain-inject.sh — доказательство `scripts/push-chain.sh` ИСПОЛНЕНИЕМ (ws#1185).
#
# Подменены лишь слот (двойник читает коды попыток из файла и на коде 0 исполняет
# настоящий `git push` в голый репозиторий), gh и autoland; git, ls-remote и сам
# скрипт — настоящие. Каждое свойство — пара: дефект (код слота, отстающая голова PR,
# грязная копия) краснит цепочку названным исходом, близнец той же формы молчит.
# Двойник различает МАРШРУТ попытки (локально по --local либо внешний: слово argv,
# --enqueue) и в отсоединённом прогоне — расположение сигналов у себя (/proc SigIgn и
# kill -HUP самому себе): повтор локально и унаследованный игнор HUP — исход, а не текст.
# Затем мутанты push-chain.sh — каждый обязан покраснеть хоть одну пробу; число
# исполненных проб сверяется с числом объявленных в suite (снятая проба — расхождение).
#
# Исходы: 0 — все пробы сошлись и все мутанты убиты; 1 — расхождение; 2 — не выполнилось.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN="$HERE/push-chain.sh"
[ -r "$CHAIN" ] || { echo "push-chain-inject: VOID — прибора нет: $CHAIN" >&2; exit 2; }
command -v git >/dev/null || { echo "push-chain-inject: VOID — нет git" >&2; exit 2; }
W="$(mktemp -d)" || { echo "push-chain-inject: VOID — mktemp" >&2; exit 2; }
trap '_rc=$?; rm -rf "$W" 2>/dev/null || rm -rf "$W" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $W не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
pass=0 fail=0
assert() { if [ "$1" = "$2" ]; then pass=$((pass + 1)); echo "  [ok] $3"; else fail=$((fail + 1)); echo "  [РАСХОЖДЕНИЕ] $3: ждали «$1», получили «$2»"; fi; }

# ── двойники ─────────────────────────────────────────────────────────────────
mkdir -p "$W/bin" "$W/out"
cat > "$W/bin/slot.sh" <<'SLOT'
#!/usr/bin/env bash
# Двойник heavy-slot.sh: --status — строка занятости; иначе — код попытки из $FK/codes.
if [ "${1:-}" = --status ]; then
    echo "потолок 70,0 ГиБ · занято машиной 30 ГиБ · свободно 50 ГиБ (вход от 15,0 ГиБ) · слотов, Σ бюджетов: 2 из 3, 30,0 ГиБ"
    echo "  ci-local    бюджет 10,0 ГиБ  сейчас 1 ГиБ  pid 1  с 10:00:00  чужая@копия"
    exit 0
fi
printf '%s\n' "$*" >> "$FK/slot.argv"
env | grep -c '^KACHO_HOME_KANAME=/fake/kaname$' >> "$FK/slot.homes"
sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$$/status" >> "$FK/slot.sigign"
enq="" route=external
while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    case "$1" in --enqueue) enq="$2"; shift ;; --local) route=local; shift ;; esac; shift
done; shift
echo "$route" >> "$FK/slot.route"
code="$(head -n 1 "$FK/codes")"; [ "$(wc -l < "$FK/codes")" -gt 1 ] && sed -i 1d "$FK/codes"
if [ -n "$enq" ]; then
    # --enqueue: билет «исполняется» сразу, исход — в .rc каталога; hang — .rc не появится.
    b="$enq/hs-ci-local-probe-$$"
    printf 'ENQUEUED\tlog=%s\trc=%s\tpid=%s\tdeadline=00:00\n' "$b.log" "$b.rc" "$b.pid"
    [ "$code" = hang ] && exit 0
    if [ "$code" = 0 ]; then "$@" > "$b.log" 2>&1; echo "$?" > "$b.rc"; else echo "$code" > "$b.rc"; fi
    exit 0
fi
case "$code" in
    hup) kill -HUP $$; exit 0 ;;
    0|141) "$@" || exit $?; exit "$code" ;;
    nopush) exit 0 ;;
    74|75) echo "heavy-slot: слот занят, очередь 2"; echo "heavy-slot: повтор — ОДИН коротким шагом: heavy-slot.sh --resume 42 [--wait N] ci-local -- … в течение 120 с держит место (билет 42)"; exit "$code" ;;
    77) echo "heavy-slot: во внешний кластер: нагрузка за обёрткой не опознана"; exit 77 ;;
    *) echo "pre-push: отказ набора"; exit "$code" ;;
esac
SLOT
cat > "$W/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
    "pr view") echo x >> "$FK/pr.calls"; h="$(head -n 1 "$FK/heads")"; [ "$(wc -l < "$FK/heads")" -gt 1 ] && sed -i 1d "$FK/heads"; echo "$h" ;;
    "issue comment") n="$3"; shift 3; r=""; f=""
        while [ "$#" -gt 0 ]; do case "$1" in -R) r="$2"; shift 2 ;; --body-file) f="$2"; shift 2 ;; *) shift ;; esac; done
        { echo "== comment $r#$n"; cat "$f"; } >> "$FK/comments" ;;
    *) exit 9 ;;
esac
GH
cat > "$W/bin/go" <<'GO'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FK/go.argv"; exit "${GO_RC:-0}"
GO
cat > "$W/bin/autoland.sh" <<'AL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FK/land"; echo "pid 1"; echo "журнал x"; echo "state y"
AL
chmod +x "$W/bin/"*

# Подпись коммитов песочницы — из корневого gitconfig в её HOME (tooling-gate check-16).
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/ghome" || { echo "push-chain-inject: VOID — корневой подписи нет" >&2; exit 2; }
G=(sandbox_git)
git init -q --bare "$W/origin.git"
git init -q -b 1185-x "$W/copy"
git -C "$W/copy" remote add origin "$W/origin.git"
echo a > "$W/copy/f"; git -C "$W/copy" add f; "${G[@]}" -C "$W/copy" commit -q -m one
OLD="$(git -C "$W/copy" rev-parse HEAD)"
"${G[@]}" -C "$W/copy" push -q origin HEAD:refs/heads/1185-x
echo b >> "$W/copy/f"; "${G[@]}" -C "$W/copy" commit -q -am two
SHA="$(git -C "$W/copy" rev-parse HEAD)"
# Голый каталог как origin даёт репозиторий «origin.git» без владельца — origin-URL формы площадки
# подставляется через insteadOf: ls-remote и push идут в тот же голый каталог.
git -C "$W/copy" config url."$W/origin.git".insteadOf "git@github.com:PRO-Robotech/probe.git"
git -C "$W/copy" remote set-url origin "git@github.com:PRO-Robotech/probe.git"
# Копия формы kacho (есть internal/repohygiene/) с правкой deploy/ — для статики (о).
git clone -q "$W/copy" "$W/copyk"
git -C "$W/copyk" config url."$W/origin.git".insteadOf "git@github.com:PRO-Robotech/probe.git"
git -C "$W/copyk" remote set-url origin "git@github.com:PRO-Robotech/probe.git"
mkdir -p "$W/copyk/internal/repohygiene" "$W/copyk/deploy"; echo k > "$W/copyk/internal/repohygiene/k.go"; echo d > "$W/copyk/deploy/x"
git -C "$W/copyk" add -A; "${G[@]}" -C "$W/copyk" commit -q -m kacho-form
SHAK="$(git -C "$W/copyk" rev-parse HEAD)"
# Копия kacho с правкой ЛИШЬ ci.yaml (вторая форма (о)) и копия с правкой deploy/ на большом
# диффе: имён после deploy/ больше буфера трубы — ранний выход grep -q даёт git SIGPIPE.
git clone -q "$W/copyk" "$W/copyc"; git -C "$W/copyc" config url."$W/origin.git".insteadOf "git@github.com:PRO-Robotech/probe.git"
mkdir -p "$W/copyc/.github/workflows"; echo y > "$W/copyc/.github/workflows/ci.yaml"
git -C "$W/copyc" add -A; "${G[@]}" -C "$W/copyc" commit -q -m ci-only
SHAKC="$(git -C "$W/copyc" rev-parse HEAD)"
git clone -q "$W/copyk" "$W/copyb"; git -C "$W/copyb" config url."$W/origin.git".insteadOf "git@github.com:PRO-Robotech/probe.git"
echo e > "$W/copyb/deploy/a"; mkdir -p "$W/copyb/zz"
( cd "$W/copyb/zz" && for i in $(seq 1 4000); do : > "имя-достаточно-длинное-чтобы-переполнить-буфер-трубы-$i"; done )
git -C "$W/copyb" add -A; "${G[@]}" -C "$W/copyb" commit -q -m big
SHAKB="$(git -C "$W/copyb" rev-parse HEAD)"

# run <метка> <коды попыток> <головы PR> [доводы…] — прогон цепочки в переднем плане, в ТЕКУЩЕЙ
# оболочке: код — в RC, каталог двойников — в FK.
run() {
    local tag="$1" codes="$2" heads="$3"; shift 3
    FK="$W/k-$tag"; rm -rf "$FK"; mkdir -p "$FK"; rm -f "$W"/out/*.rc
    printf '%s\n' "$codes" | tr ' ' '\n' > "$FK/codes"
    printf '%s\n' "$heads" | tr ' ' '\n' > "$FK/heads"
    git -C "$W/origin.git" update-ref refs/heads/1185-x "$OLD"
    (cd "$W" && env FK="$FK" KACHO_HOME_KANAME=/fake/kaname PUSH_CHAIN_SLOT="$W/bin/slot.sh" PUSH_CHAIN_GH="$W/bin/gh" \
        PUSH_CHAIN_AUTOLAND="$W/bin/autoland.sh" PUSH_CHAIN_POLL_S=0 PUSH_CHAIN_GO="$W/bin/go" GO_RC="${GO_RC:-0}" PUSH_CHAIN_ENQ_WAIT_S="${ENQ_WAIT:-30}" \
        bash "${CHAIN_OVR:-$CHAIN}" --copy "$W/copy" --branch 1185-x --sha "$SHA" --out "$W/out" "$@" > "$FK/out" 2> "$FK/err")
    RC=$?
}
cnt() { if [ -f "$1" ]; then grep -c -e "$2" "$1"; else echo 0; fi; }
rcf() { local f; for f in "$W"/out/push-chain-1185-x-*.rc; do [ -e "$f" ] && { echo "$f"; return; }; done; }

# detach <метка> <коды> [ловушка] — отсоединённый прогон; ловушка — команда оболочки
# ВЫЗЫВАЮЩЕГО перед запуском (`trap '' HUP`). Вывод — в D, код — в DRC, .rc — по исходу.
detach() {
    local tag="$1" codes="$2" pre="${3:-:}"
    FK="$W/k-$tag"; rm -rf "$FK"; mkdir -p "$FK"; rm -f "$W"/out/*.rc
    printf '%s\n' "$codes" | tr ' ' '\n' > "$FK/codes"; echo "$SHA" > "$FK/heads"
    git -C "$W/origin.git" update-ref refs/heads/1185-x "$OLD"
    # shellcheck disable=SC2016  # строка дочерней оболочки, $0 и $@ раскрывает она
    D="$(cd "$W" && env FK="$FK" PUSH_CHAIN_SLOT="$W/bin/slot.sh" PUSH_CHAIN_GH="$W/bin/gh" PUSH_CHAIN_AUTOLAND="$W/bin/autoland.sh" \
        bash -c "$pre"'; exec bash "$0" "$@"' "${CHAIN_OVR:-$CHAIN}" --copy "$W/copy" --branch 1185-x --sha "$SHA" --out "$W/out" --detach 2>&1)"; DRC=$?
    for _ in $(seq 1 50); do [ -s "$(rcf)" ] && break; sleep 0.2; done
}
# hup_ignored <файл SigIgn> — 1, если у двойника слота бит SIGHUP (1) стоял в игноре.
hup_ignored() { local v; v="$(head -n 1 "$1" 2>/dev/null)"; [ -n "$v" ] || { echo "нет"; return; }; echo $(( 0x$v & 1 )); }

suite() {
echo "── отправка с первой попытки (близнец: повторов нет), DoD-proof и демон после головы PR"
run green 0 "$SHA" --issue 7 --pr 5 --subject '#7 merge #5: x'
assert "0 1 1 1 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" "^DoD-proof @$SHA") $(cnt "$FK/land" "--head $SHA") $(cnt "$FK/slot.homes" '^1$')" \
    "код 0 → одна отправка, DoD-proof @sha, autoland start с той же головой, KACHO_HOME_* донесены до слота"
assert "1 1" "$(cnt "$FK/comments" '== comment PRO-Robotech/probe#7') $(sed -n 2p "$(rcf)" | grep -c 'slots=2/3')" "задача без репозитория — репозиторий origin; занятость слотов (--status) — в .rc"
assert "0 external 1 0" "$(cnt "$FK/slot.argv" '--local') $(head -n 1 "$FK/slot.route") $(cnt "$FK/err" '--status: потолок') $(cnt "$FK/go.argv" .)" "близнец: без довода --local маршрут внешний; первая строка --status — в журнале; копия без internal/repohygiene — статики нет"

echo "── (к) 74/75 — ОДИН повтор --enqueue по внешнему маршруту с билетом; локально — никогда"
run r75 '75 0' "$SHA" --issue 7
assert "0 2 1 0 external,external 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/slot.argv" "^--enqueue $W/out/push-chain-1185-x-[^ ]*\.enq --resume 42 ci-local") $(cnt "$FK/slot.argv" '--local') $(paste -sd, "$FK/slot.route") $(cnt "$FK/comments" '^DoD-proof @')" \
    "75, затем 0 → повтор ровно один: --enqueue в каталог журналов вне копии с --resume 42, без --local, оба маршрута внешние; DoD-proof опубликован"
run r75x '75 75' "$SHA" --issue 7 --pr 5 --subject s
assert "2 2 0 0 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" 'DoD-proof') $(cnt "$FK/land" .) $(head -n 1 "$(rcf)" | grep -c '^2$')" "(в) билет --enqueue кончился 75 → код 2, повторов один, DoD-proof и демона нет, в .rc код 2"
assert "1" "$(cnt "$FK/err" 'не выполнилось: отправка — код 75')" "(в) текст «не выполнилось» с кодом"
ENQ_WAIT=0 run rhang '74 hang' "$SHA" --issue 7
assert "2 2 0 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" 'DoD-proof') $(cat "$W"/out/push-chain-1185-x-*.push.log 2>/dev/null | grep -c '\.rc билета нет за 0 с')" "билет --enqueue без .rc за предел → код 2, итога нет, причина в журнале"
run r74 '74 0' "$SHA"
assert "0 2 1 0" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/slot.argv" '^--enqueue ') $(cnt "$FK/slot.argv" '--local')" "74, затем 0 → один повтор --enqueue, без --local"

echo "── (м) 77 и 69 — не красное: один повтор словами argv по внешнему маршруту; код 1 — без повтора"
run r77 '77 0' "$SHA" --issue 7
assert "0 2 0 0 external,external 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/slot.argv" '--local') $(cnt "$FK/slot.argv" '--enqueue') $(paste -sd, "$FK/slot.route") $(cnt "$FK/comments" '^DoD-proof @')" "77, затем 0 → повтор argv, без --local и --enqueue, маршрут внешний, сдано"
run r69 '69 0' "$SHA"
assert "0 2 0 external,external" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/slot.argv" '--local') $(paste -sd, "$FK/slot.route")" "69, затем 0 → повтор argv по внешнему маршруту, сдано"
run r77x '77 77 0' "$SHA" --issue 7
assert "2 2 0" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" 'DoD-proof')" "77 дважды → код 2: повтор ровно один, итога нет"
run lx 0 "$SHA" --local 'Job не несёт соседний клон kacho (ws#1196)'
assert "0 1 local" "$RC $(cnt "$FK/slot.argv" '^--local Job не несёт соседний клон kacho (ws#1196) ci-local -- git push') $(head -n 1 "$FK/slot.route")" "довод вызывающего --local «причина» → слоту дословно, маршрут локальный"
run lxr '75 0' "$SHA" --local 'Job не несёт соседний клон kacho (ws#1196)'
assert "0 2" "$RC $(cnt "$FK/slot.argv" '--local Job не несёт')" "довод --local держится и в повторе --enqueue"
run red 1 "$SHA" --issue 7
assert "1 1 0 1" "$RC $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" 'DoD-proof') $(cnt "$FK/err" 'красное: хук отправки отказал')" "близнец: код 1 → красное, повтора нет, DoD-proof нет"
run r141 141 "$SHA" --issue 7
assert "0 1" "$RC $(cnt "$FK/comments" '^DoD-proof @')" "141 после хука и голова на origin совпала → сдано"
run nopush nopush "$SHA" --issue 7
assert "2 0" "$RC $(cnt "$FK/comments" 'DoD-proof')" "код 0 без отправки (origin ≠ sha) → «не выполнилось», DoD-proof нет"

echo "── (н) демон — лишь после того, как headRefOid запроса стал sha"
run lag 0 "$OLD $OLD $SHA" --pr 5 --subject s
assert "0 3 1" "$RC $(cnt "$FK/pr.calls" x) $(cnt "$FK/land" "--head $SHA")" "голова PR отстаёт два чтения → цепочка ждёт и зовёт демона после совпадения"
run stale 0 "$OLD" --issue 7 --pr 5 --subject s --head-wait 0
assert "2 0 0 1" "$RC $(cnt "$FK/land" .) $(cnt "$FK/comments" 'DoD-proof') $(sed -n 2p "$(rcf)" | grep -c 'pr_head=не совпало')" "голова PR не совпала за предел → код 2, ни демона (head-moved не наступил), ни DoD-proof"

echo "── (о) копия kacho: правка deploy/ либо ci.yaml — repohygiene до хука"
GO_RC=1 run kred 0 "$SHAK" --copy "$W/copyk" --sha "$SHAK" --lane-base "$OLD" --issue 7
assert "1 1 0 0" "$RC $(cnt "$FK/go.argv" 'test -short -count=1 ./internal/repohygiene/') $(cnt "$FK/slot.argv" 'git push') $(cnt "$FK/comments" 'DoD-proof')" "repohygiene красный → код 1 до отправки: слот не звался, DoD-proof нет"
run kgreen 0 "$SHAK" --copy "$W/copyk" --sha "$SHAK" --lane-base "$OLD"
assert "0 1 1 1" "$RC $(cnt "$FK/go.argv" 'repohygiene') $(cnt "$FK/slot.argv" 'git push') $(sed -n 2p "$(rcf)" | grep -c 'static=repohygiene:0')" "repohygiene зелёный → отправка, static=repohygiene:0 в .rc"
GO_RC=1 run kci 0 "$SHAKC" --copy "$W/copyc" --sha "$SHAKC" --lane-base "$SHAK"
assert "1 1 0" "$RC $(cnt "$FK/go.argv" 'repohygiene') $(cnt "$FK/slot.argv" 'git push')" "вторая форма: дифф трогает лишь .github/workflows/ci.yaml → repohygiene до хука, красный — код 1"
GO_RC=1 run kbig 0 "$SHAKB" --copy "$W/copyb" --sha "$SHAKB" --lane-base "$SHAK"
assert "1 1 0" "$RC $(cnt "$FK/go.argv" 'repohygiene') $(cnt "$FK/slot.argv" 'git push')" "deploy/ и 4000 имён за ним (больше буфера трубы) → статика судится, а не skip от SIGPIPE"
run ktwin 0 "$SHAK" --copy "$W/copyk" --sha "$SHAK" --lane-base "$SHAK"
assert "0 0 1" "$RC $(cnt "$FK/go.argv" .) $(sed -n 2p "$(rcf)" | grep -c 'static=skip')" "близнец: дифф от базы без deploy/ и ci.yaml — статики нет, skip в .rc"

echo "── предусловия: голова и чистота копии"
run moved 0 "$SHA" --issue 7 --sha "$OLD"
assert "64 0" "$RC $(cnt "$FK/slot.argv" .)" "--sha не голова копии → 64, слот не звался"
echo c >> "$W/copy/f"
run dirty 0 "$SHA"
assert "64 0" "$RC $(cnt "$FK/slot.argv" .)" "правлен отслеживаемый файл → 64, слот не звался"
git -C "$W/copy" checkout -q -- f
run forms 0 "$SHA" --issue 7 --issue other/repo#9
assert "0 1 1" "$RC $(cnt "$FK/comments" 'comment PRO-Robotech/probe#7') $(cnt "$FK/comments" 'comment other/repo#9')" "--issue N и --issue владелец/имя#N → по комментарию в каждую"

echo "── отсоединённый запуск: сразу «идёт», .rc — по исходу; сигналы у ребёнка — по умолчанию"
detach det 0
assert "0 1 0 0" "$DRC $(printf '%s' "$D" | grep -c '^идёт: pid [0-9]*, журнал .*\.log, \.rc .*\.rc, срок') $(head -n 1 "$(rcf)" 2>/dev/null) $(hup_ignored "$FK/slot.sigign")" "--detach → код 0 и строка «идёт: pid, журнал, .rc, срок»; .rc отсоединённого — 0; HUP у ребёнка не в игноре"
detach dhup hup "trap '' HUP"
assert "0 1" "$(hup_ignored "$FK/slot.sigign") $(sed -n 2p "$(rcf)" 2>/dev/null | grep -c ' push=129 ')" "вызывающий с trap '' HUP: у ребёнка цепочки HUP не в игноре (SigIgn), kill -HUP себе — 129"
assert "0" "$(grep -v '^[[:space:]]*#' "${CHAIN_OVR:-$CHAIN}" | grep -c 'nohup')" "в коде цепочки нет nohup"
}
# Объявлено проб — вызовов assert в теле suite (выводится из текста прибора, а не пишется числом).
DECLARED="$(sed -n '/^suite() {$/,/^}$/p' "${BASH_SOURCE[0]}" | grep -c '^assert ')"

echo "== push-chain.sh"
suite
base_pass=$pass base_fail=$fail

echo "── мутанты push-chain.sh: каждый обязан покраснеть"
mutant() {
    local name="$1" m="$W/mut-$1.sh"; shift
    python3 - "$CHAIN" "$m" "$@" <<'PYM' || { echo "  [РАСХОЖДЕНИЕ] мутант $name: образец не найден"; fail=$((fail + 1)); return; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
pairs = sys.argv[3:]
for a, b in zip(pairs[::2], pairs[1::2]):
    if a not in s:
        sys.exit(1)
    s = s.replace(a, b)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PYM
    local p0=$pass f0=$fail
    CHAIN_OVR="$m" suite > "$W/mut-$name.log" 2>&1
    local killed=$(( fail - f0 ))
    pass=$p0 fail=$f0
    assert "убит" "$([ "$killed" -gt 0 ] && echo убит || echo выжил)" "мутант «$name» краснит пробы ($killed)"
}
# shellcheck disable=SC2016  # образцы мутантов — текст прибора, не подстановка
mutant no-retry '    74|75)' '    never1)' '    77|69)' '    never2)'
# shellcheck disable=SC2016
mutant no-static-gate '[ "$src" = 0 ] || {' 'true || {'
mutant red-retried '    77|69)' '    1|77|69)'
# shellcheck disable=SC2016
mutant no-head-wait '        [ "$got" = "$SHA" ] && break' '        break'
# shellcheck disable=SC2016
mutant no-remote-check '[ "$remote" != "$SHA" ]; then' '[ -z "$SHA" ]; then'
# (в) держателей три: исход отправки, сверка origin, страж тела. Снятие всех трёх
# публикует итог на 75; каждый по отдельности избыточен — так задумано.
# shellcheck disable=SC2016
mutant dod-on-any-code '    *) F_WHY="отправка — код $prc после $F_TRIES попыток (журнал $PUSH_LOG)"; finish 2 ;;' '    *) ;;' \
    '[ "$remote" != "$SHA" ]; then' '[ -z "$SHA" ]; then' \
    'if [ "$1" != 0 ] && [ "$1" != "141→ok" ]; then' 'if false; then'
# Повтор локально — обход внешнего кластера (приёмка ws#1185, п.1): форма редакции 9ce6e6b8c.
# shellcheck disable=SC2016
mutant enqueue-to-local 'enqueue_once ${tk:+--resume "$tk"}; prc=$?' 'push_once --wait 300 ${tk:+--resume "$tk"} --local "цепочка: повтор после занятого слота"; prc=$?'
# shellcheck disable=SC2016
mutant argv-retry-local '        push_once; prc=$?' '        push_once --local "цепочка: повтор после кода 77 или 69"; prc=$?'
# shellcheck disable=SC2016
mutant enqueue-no-ticket 'enqueue_once ${tk:+--resume "$tk"}; prc=$?' 'enqueue_once; prc=$?'
# Сигналы (п.2): игнор HUP в строке отсоединения и сброс одного PIPE — оба обязаны краснеть.
mutant hup-trap "setsid -f env --default-signal bash -c '" "setsid -f env --default-signal bash -c 'trap \"\" HUP; "
mutant pipe-only 'setsid -f env --default-signal bash' 'setsid -f env --default-signal=PIPE bash'
# Статика (о), п.3: ci.yaml снят с образца; дифф — трубой в grep -q под pipefail.
# shellcheck disable=SC2016
mutant ci-dropped '-- deploy/ .github/workflows/ci.yaml; drc=$?' '-- deploy/; drc=$?'
# shellcheck disable=SC2016
mutant grep-pipe 'git -C "$COPY" diff --quiet "$mb" HEAD -- deploy/ .github/workflows/ci.yaml; drc=$?' \
    'if git -C "$COPY" diff --name-only "$mb" HEAD | grep -m1 -E "^(deploy/|\.github/workflows/ci\.yaml$)" >/dev/null; then drc=1; else drc=0; fi'
echo "push-chain-inject: проб объявлено $DECLARED, исполнено $((base_pass + base_fail)), сошлось $base_pass, разошлось $base_fail; мутантов — в строках выше; итог расхождений $fail"
[ "$DECLARED" -gt 0 ] || { echo "push-chain-inject: VOID — в suite не найдено ни одной пробы" >&2; exit 2; }
[ "$((base_pass + base_fail))" -eq "$DECLARED" ] || { echo "push-chain-inject: РАСХОЖДЕНИЕ — исполнено проб $((base_pass + base_fail)) из объявленных $DECLARED"; exit 1; }
[ "$fail" -eq 0 ] && exit 0
exit 1
