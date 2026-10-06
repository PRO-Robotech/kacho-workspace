#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# landing-precheck-inject.sh — доказательство того, что landing-precheck.sh
# СПОСОБЕН остановить посадку по каждому из семи пунктов, и что законный близнец
# той же формы проходит.
#
# ВХОД — НАСТОЯЩИЙ. `scripts/landing-precheck-fixtures/` — захват площадки по
# kacho#3036 (запрос волны-3 identity-own, влит 2026-10-05; захват 2026-10-06
# командами `gh api repos/PRO-Robotech/kacho/pulls/3036`, `…/pulls/3036/commits`,
# `…/commits/8bbdb4e5…/check-runs?filter=latest`), обрезанный до полей, которые
# читает предпроверка. Подмена `gh` (LANDING_PRECHECK_GH) отдаёт эти файлы;
# merge-readiness подменяется заглушкой с заданным кодом
# (LANDING_PRECHECK_MERGE_READINESS) — его собственное доказательство живёт в
# tooling-gate check-09.
# Исключение — раздел «(д) настоящий»: там merge-readiness НЕ подменяется, а
# извлекается предпроверкой из origin/main песочницы-воркспейса
# (LANDING_PRECHECK_WS) вместе с `scripts/lib/`, и судит случай с DoD-proof через
# подменный gh в PATH; инъекция — предпроверка, извлекающая один файл без `lib/`
# (дефект ws#935), обязана дать MERGE-READINESS код 2 «распознавателя нет».
#
# БЛИЗНЕЦ — захват с ДВУМЯ правками, обе названы: состояние `closed` → `open`
# (запрос уже влит) и в теле снято упоминание `#3028` (задача следующей волны,
# коммита в диапазоне нет); комментарии задач (`DoD-proof @<sha>` на коммите
# своего номера, у #3020 — на голове) собираются пробой — их захвата нет. Захват КАК ЕСТЬ — отдельная проба: на нём
# предпроверка обязана назвать обе причины, то есть настоящий влитой запрос этой
# линии нарушал §8а п.4, и это видно без синтетики.
#
# НАБОР ОБЯЗАТЕЛЬНЫХ (пункт (г), skipped необязательного): у близнеца — все имена
# захвата, заглушка merge-readiness отдаёт его файлом MERGE_READINESS_REQUIRED_OUT,
# как настоящий; задание «только push main» добавляется четырьмя skipped (форма
# kaname#624). В «(д) настоящий» набор отдаёт сам merge-readiness из защиты случая,
# а его мутант без записи набора обязан оставить skipped причиной.
#
# Каждая инъекция меняет ОДИН факт против близнеца и обязана дать код 1 и строку
# REASON со своим кодом причины; близнец — код 0 и ни одной строки REASON.
# Коды: 0 — все утверждения сошлись; 1 — хотя бы одно нет.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/landing-precheck.sh"
FIX="$HERE/landing-precheck-fixtures"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

HEAD_SHA="$(jq -r '.head.sha' "$FIX/pull.json")"
pass=0; fail=0

# Подмена gh: отвечает только на `gh api <путь>`; путь → файл песочницы пробы.
cat > "$W/gh" <<'GH'
#!/usr/bin/env bash
# `gh pr view` и чтения защиты, задачи головы и комментариев без `page=` зовёт
# НАСТОЯЩИЙ merge-readiness (раздел «(д) настоящий»): ответы — файлы того же случая.
if [ "$1" = pr ] && [ "$2" = view ]; then
    [ -f "$FAKE/prview.json" ] || { echo "fake gh: pr view без prview.json" >&2; exit 64; }
    cat "$FAKE/prview.json"; exit 0
fi
[ "$1" = api ] || { echo "fake gh: только api и pr view" >&2; exit 64; }
case "$2" in
    */branches/*/protection)
        [ -f "$FAKE/protection.json" ] || { echo "fake gh: защиты в случае нет" >&2; exit 64; }
        cat "$FAKE/protection.json" ;;
    */issues/*/comments\?per_page=100)
        n="${2#*/issues/}"; n="${n%%/*}"
        if [ -f "$FAKE/comments-$n.json" ]; then cat "$FAKE/comments-$n.json"; else echo '[]'; fi ;;
    */pulls/*/commits\?*page=1) cat "$FAKE/commits.json" ;;
    */pulls/*/commits\?*)       echo '[]' ;;
    */check-runs\?*page=1*)     cat "$FAKE/check-runs.json" ;;
    */check-runs\?*)            echo '{"total_count":0,"check_runs":[]}' ;;
    */pulls/[0-9]*)             cat "$FAKE/pull.json" ;;
    */issues/*/comments\?*page=1)
        n="${2#*/issues/}"; n="${n%%/*}"
        if [ -f "$FAKE/comments-$n.json" ]; then cat "$FAKE/comments-$n.json"; else echo '[]'; fi ;;
    */issues/*/comments\?*)     echo '[]' ;;
    */issues/[0-9]*)
        n="${2##*/}"; printf '{"number":%s,"labels":[],"sub_issues_summary":{"total":0,"completed":0}}\n' "$n" ;;
    *) echo "fake gh: путь $2 не известен" >&2; exit 64 ;;
esac
GH
chmod +x "$W/gh"
# Заглушка отдаёт набор обязательных так же, как настоящий merge-readiness: файлом
# MERGE_READINESS_REQUIRED_OUT; набор случая — $FAKE/required (нет файла — набора нет).
# shellcheck disable=SC2016  # тело заглушки — текст скрипта, подстановка — в нём
for c in 0 1 2; do printf '#!/usr/bin/env bash\n[ -z "${MERGE_READINESS_REQUIRED_OUT:-}" ] || [ ! -f "$FAKE/required" ] || cp "$FAKE/required" "$MERGE_READINESS_REQUIRED_OUT"\necho "merge-readiness stub: код %s"\nexit %s\n' "$c" "$c" > "$W/mr$c"; done

# twin — свежий близнец в $W/case: захват + две названные правки.
twin() {
    rm -rf "$W/case"; mkdir -p "$W/case"
    jq '.state = "open" | .body |= sub(" вместе с #3028"; "")' "$FIX/pull.json" > "$W/case/pull.json"
    cp "$FIX/commits.json" "$FIX/check-runs.json" "$W/case/"
    # Набор обязательных случая — все имена захвата (как защита в «(д) настоящий»).
    jq -r '.check_runs[].name' "$FIX/check-runs.json" | LC_ALL=C sort -u > "$W/case/required"
    printf '[{"role":"go-style-reviewer","sha":"%s","verdict":"accept","blocking":[]},{"role":"system-design-reviewer","sha":"%s","verdict":"accept"}]\n' \
        "$HEAD_SHA" "$HEAD_SHA" > "$W/case/reviews.json"
    # Доказательство DoD каждой закрываемой задачи — на коммите её номера в
    # диапазоне (так пишет его исполнитель); у #3020 — на голове сборки.
    local n s
    for n in 2878 2885 2690 2707; do
        s="$(jq -r --arg n "#$n" '[.[] | select(.commit.message | split("\n")[0] | contains($n))][0].sha' "$FIX/commits.json")"
        printf '[{"body":"сдача\\nDoD-proof @%s\\nпроверки: …"}]\n' "${s:0:12}" > "$W/case/comments-$n.json"
    done
    printf '[{"body":"обсуждение"},{"body":"DoD-proof @%s"}]\n' "$HEAD_SHA" > "$W/case/comments-3020.json"
}
# edit <файл> [--arg <имя> <значение>] <jq-выражение> — один факт против близнеца.
edit() { if [ "$2" = --arg ]; then jq --arg "$3" "$4" "$5" "$W/case/$1" > "$W/case/$1.new"; else jq "$2" "$W/case/$1" > "$W/case/$1.new"; fi && mv "$W/case/$1.new" "$W/case/$1"; }
# run <код заглушки merge-readiness> [доводы] — код в $W/code, вывод в $W/out.
run() {
    local mr="$1"; shift
    FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" LANDING_PRECHECK_MERGE_READINESS="$W/mr$mr" \
        bash "$TOOL" PRO-Robotech/kacho 3036 "$@" > "$W/out" 2>&1
    echo $? > "$W/code"
}
# expect <код> <ожидаемое начало строки REASON/VOID или «-»> <имя пробы> [many]
# Однофактная проба: КАЖДАЯ строка REASON обязана быть той же причины — красное
# от соседнего пункта пробу не засчитывает. «many» — только для захвата как есть.
expect() {
    local code; code="$(cat "$W/code")"
    local ok=1
    [ "$code" = "$1" ] || ok=0
    if [ "$2" = "-" ]; then
        ! grep -q '^REASON' "$W/out" || ok=0
    else
        grep -q "^$2" "$W/out" || ok=0
        if [ "${4:-}" != many ] && [[ "$2" == REASON* ]]; then
            local want; want="$(printf '%s' "$2" | cut -f1,2)"
            local got; got="$(grep '^REASON' "$W/out" | cut -f1,2)"
            ! grep -qvxF "$want" <<< "$got" || ok=0
        fi
    fi
    if [ "$ok" = 1 ]; then echo "  [OK]   $3"; pass=$((pass + 1))
    else
        echo "  [FAIL] $3 — ожидалось код $1 и «$2», получено код $code:" >&2
        sed 's/^/           /' "$W/out" >&2
        fail=$((fail + 1))
    fi
}
[ -x "$(command -v jq)" ] || { echo "VOID: нет jq" >&2; exit 2; }
# shellcheck source=lib/sandbox-git-home.sh
. "$HERE/lib/sandbox-git-home.sh"
sandbox_git_home "$W/home" || { echo "VOID: подписи песочницы нет — история песочницы-воркспейса не пишется" >&2; exit 2; }
[ -n "$HEAD_SHA" ] && [ "$HEAD_SHA" != null ] || { echo "VOID: фикстура без head.sha" >&2; exit 2; }

echo "== близнец и захват как есть"
twin; run 0 --reviews "$W/case/reviews.json"; expect 0 - "близнец с вердиктами ревью на голове — код 0, причин нет"
twin; run 0;                                  expect 0 - "близнец без --reviews — код 0"
if grep -q 'пункт (а) НЕ СУДИЛСЯ' "$W/out"; then echo "  [OK]   без --reviews пункт (а) назван несуждённым"; pass=$((pass + 1))
else echo "  [FAIL] без --reviews нет строки «НЕ СУДИЛСЯ»" >&2; fail=$((fail + 1)); fi
twin; cp "$FIX/pull.json" "$W/case/pull.json"; run 0
expect 1 $'REASON\tBODY-FOREIGN-TASK\tтело называет #3028' "захват как есть: #3028 без коммита в диапазоне" many
expect 1 $'REASON\tPR-NOT-OPEN' "захват как есть: запрос влит" many

echo "== (а) вердикты ревью"
twin; printf '[{"role":"go-style-reviewer","sha":"%s","verdict":"accept"}]\n' "${HEAD_SHA%?}0" > "$W/case/reviews.json"
[ "${HEAD_SHA%?}0" != "$HEAD_SHA" ] || printf '[{"role":"go-style-reviewer","sha":"%s","verdict":"accept"}]\n' "${HEAD_SHA%?}1" > "$W/case/reviews.json"
run 0 --reviews "$W/case/reviews.json"; expect 1 $'REASON\tREVIEW-STALE\tроль go-style-reviewer' "вердикт на прежней голове"
twin; echo '[]' > "$W/case/reviews.json"; run 0 --reviews "$W/case/reviews.json"
expect 1 $'REASON\tREVIEW-MALFORMED' "пустой набор вердиктов — не «все приняли»"
twin; edit reviews.json '.[0].verdict = "return"'; run 0 --reviews "$W/case/reviews.json"
expect 1 $'REASON\tREVIEW-NOT-ACCEPTED\tроль go-style-reviewer' "роль вернула"
twin; edit reviews.json '.[0].blocking = ["находка"]'; run 0 --reviews "$W/case/reviews.json"
expect 1 $'REASON\tREVIEW-NOT-ACCEPTED' "непустой blocking при verdict accept"
twin; edit reviews.json 'del(.[1].verdict)'; run 0 --reviews "$W/case/reviews.json"
expect 1 $'REASON\tREVIEW-NOT-ACCEPTED\tроль system-design-reviewer' "вердикт без verdict — не «принят»"
twin; edit reviews.json 'del(.[1].sha)'; run 0 --reviews "$W/case/reviews.json"
expect 1 $'REASON\tREVIEW-MALFORMED' "вердикт без sha"

echo "== (б) заголовок"
twin; edit pull.json '.title |= sub("^#2966 "; "[#2966] ")'; run 0
expect 1 $'REASON\tTITLE-FORM' "заголовок «[#2966] …»"
twin; edit pull.json '.title |= sub("^#2966 "; "#2966")'; run 0
expect 1 $'REASON\tTITLE-FORM' "заголовок без пробела после номера"
twin; edit pull.json '.title |= sub("^#2966 "; "#2967 ")'; run 0
expect 1 $'REASON\tTITLE-HEAD-NUMBER' "номер заголовка не номер головы 2966"

echo "== (в) тело = состав"
twin; edit pull.json '.body |= gsub("#2690"; "задача")'; run 0
expect 1 $'REASON\tBODY-MISSING-COMMIT\t67c6accf0' "коммит #2690 не назван в теле"
twin; edit pull.json '.body |= gsub("#2690"; "задача") + "\n\nкоммит 67c6accf0"'; run 0
expect 0 - "близнец: тот же коммит назван коротким sha"
twin; edit pull.json '.body += "\nRefs #9999"'; run 0
expect 1 $'REASON\tBODY-FOREIGN-TASK\tтело называет #9999' "задача в теле без коммита в диапазоне"
twin; edit pull.json '.body += "\nсм. kaname#9999"'; run 0
expect 0 - "близнец: ссылка в чужой репозиторий kaname#9999 не судится"

echo "== (г) CI на голове"
twin; edit check-runs.json '.check_runs[0].conclusion = "skipped"'; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\tсводный вердикт юнитов (все шарды) — skipped (контекст обязательный)' "skipped обязательного контекста — не зелёный"
# Задание «только push main» (kaname ci.yml, e2e-newman.yml): на PR skipped по
# построению и в наборе обязательных его нет. Форма — как на kaname#624: одно имя
# несколькими прогонами.
TRUNKJOB='вердикт ствола — красное не остаётся без читателя'
# shellcheck disable=SC2016  # $n и ${…} — переменные jq и текст образца, не оболочки
addskip() { edit check-runs.json --arg n "$TRUNKJOB" '.check_runs += [range(4) as $i | {name: $n, status: "completed", conclusion: "skipped", head_sha: .check_runs[0].head_sha}] | .total_count += 4'; }
twin; addskip; run 0
expect 0 - "skipped необязательного «только push main» ×4 — не причина"
if grep -qxF $'CENSUS\tci: skipped необязательного не причина — '"$TRUNKJOB"' ×4' "$W/out"; then
    echo "  [OK]   снятый skipped назван в переписи поимённо и счётом"; pass=$((pass + 1))
else echo "  [FAIL] перепись не называет снятый skipped:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
twin; addskip; echo "$TRUNKJOB" >> "$W/case/required"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (контекст обязательный)' "близнец: то же задание в наборе обязательных — skipped не зелёный"
twin; addskip; rm "$W/case/required"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (набор обязательных' "набор от merge-readiness не получен — skipped не снимается"
twin; addskip; : > "$W/case/required"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (набор обязательных' "пустой набор — не «всё необязательно»"
twin; addskip
# shellcheck disable=SC2016  # $n — переменная jq
edit check-runs.json --arg n "$TRUNKJOB" '(.check_runs[] | select(.name == $n) | .conclusion) |= "neutral"'; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — neutral' "необязательное neutral — снимается только skipped"
twin; addskip
# shellcheck disable=SC2016  # $n — переменная jq
edit check-runs.json --arg n "$TRUNKJOB" '(.check_runs[] | select(.name == $n) | .conclusion) |= "failure"'; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — failure' "необязательное failure — красное остаётся причиной"
twin; edit check-runs.json '.check_runs[0].status = "in_progress" | .check_runs[0].conclusion = null'; run 0
expect 1 $'REASON\tCI-PENDING' "один check-run идёт"
twin; edit check-runs.json '.check_runs = [] | .total_count = 0'; run 0
expect 1 $'REASON\tCI-EMPTY' "проверок 0 — не зелёное"
twin; edit check-runs.json '.total_count += 1'; run 0
expect 2 $'VOID\tcheck-runs: объявлено' "check-runs усечены — вердикта нет"

echo "== (д) merge-readiness"
twin; run 1; expect 1 $'REASON\tMERGE-READINESS\tкод 1' "merge-readiness 1"
twin; run 2; expect 1 $'REASON\tMERGE-READINESS\tкод 2' "merge-readiness 2 — тоже не «можно»"

echo "== (е) атрибуция — предикат дерева, сообщения и тело"
twin; edit commits.json '.[3].commit.message += "\n\nCo-Authored-By: someone <x@y>"'; run 0
expect 1 $'REASON\tATTRIBUTION\tкоммит 8cc8354bb5' "трейлер в сообщении коммита диапазона"
twin; edit pull.json '.body += "\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"'; run 0
expect 1 $'REASON\tATTRIBUTION\tтело' "строка «Generated with Claude Code» в теле"
twin; edit pull.json '.body += "\n\nтрейлер Co-Authored-By: в шаблоне снят"'; run 0
expect 0 - "близнец: ключ в середине строки прозы — упоминание, не трейлер"

echo "== (ж) Closes только с доказательством на коммите диапазона"
twin; rm "$W/case/comments-2690.json"; run 0
expect 1 $'REASON\tCLOSES-WITHOUT-PROOF\tPRO-Robotech/kacho#2690: комментария' "Closes #2690 без DoD-proof"
twin; printf '[{"body":"DoD-proof @9b14ae7f01c"}]\n' > "$W/case/comments-2690.json"; run 0
expect 1 $'REASON\tCLOSES-WITHOUT-PROOF\tPRO-Robotech/kacho#2690: DoD-proof есть' "DoD-proof на базе, а не на коммите запроса"
twin; edit pull.json '.body |= sub("Closes #2690"; "Refs #2690")'; rm "$W/case/comments-2690.json"; run 0
expect 0 - "близнец: та же задача без доказательства, но Refs — не судится"
twin; edit pull.json '.body |= sub("Closes #2707"; "fixes PRO-Robotech/kacho#2707")'; rm "$W/case/comments-2707.json"; run 0
expect 1 $'REASON\tCLOSES-WITHOUT-PROOF\tPRO-Robotech/kacho#2707' "форма fixes <репо>#N без доказательства"
twin
# shellcheck disable=SC2016  # тело подменного gh — текст скрипта, подстановка — в нём
printf '#!/usr/bin/env bash\ncase "$2" in */issues/*) echo boom >&2; exit 1 ;; esac\nexec "%s" "$@"\n' "$W/gh" > "$W/gh-broken"; chmod +x "$W/gh-broken"
FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh-broken" LANDING_PRECHECK_MERGE_READINESS="$W/mr0" bash "$TOOL" PRO-Robotech/kacho 3036 > "$W/out" 2>&1; echo $? > "$W/code"
expect 2 $'VOID\tкомментарии PRO-Robotech/kacho#' "комментарии задачи не прочитаны — вердикта нет, а не «доказано»"

echo "== (д) настоящий merge-readiness из origin/main — вместе с тем, что он подключает"
# Подмены merge-readiness здесь НЕТ: предпроверка извлекает его из origin/main
# песочницы-воркспейса (LANDING_PRECHECK_WS) так же, как из настоящего, и он судит
# тот же случай через подменный gh в PATH. Песочница несёт файлы ЭТОГО дерева:
# `scripts/merge-readiness.sh` и `scripts/lib/` — ровно то, что лежит в origin/main
# после вливания. Прежний дефект (ws#935, найден на kacho#3043): извлекался один
# файл, без `lib/`, и merge-readiness выходил кодом 2 «распознавателя нет» на
# КАЖДОЙ посадке — пункт (д) не судился ни разу, а пробы выше этого не видели:
# там merge-readiness — заглушка.
# mrcase <с lib: 1|0> — близнец + ответы `gh pr view` и защиты + песочница.
mrcase() {
    twin
    jq -n --slurpfile p "$W/case/pull.json" --slurpfile c "$W/case/check-runs.json" '
        $p[0] as $p | {state: "OPEN", baseRefName: $p.base.ref, headRefName: $p.head.ref,
          headRefOid: $p.head.sha, mergeStateStatus: "CLEAN", body: $p.body,
          closingIssuesReferences: [],
          statusCheckRollup: [$c[0].check_runs[] | {name, conclusion: (.conclusion | ascii_upcase)}]}' > "$W/case/prview.json"
    jq '{required_status_checks: {contexts: [.check_runs[].name] | unique}}' "$W/case/check-runs.json" > "$W/case/protection.json"
    rm -rf "$W/ws"; mkdir -p "$W/ws/scripts"
    cp "$HERE/merge-readiness.sh" "$W/ws/scripts/"
    [ "$1" = 0 ] || cp -r "$HERE/lib" "$W/ws/scripts/lib"
    # Подпись песочницы — её корневой gitconfig (scripts/lib/sandbox-git-home.sh).
    sandbox_git -C "$W/ws" init -q
    sandbox_git -C "$W/ws" add -A
    sandbox_git -C "$W/ws" commit -qm probe
    sandbox_git -C "$W/ws" update-ref refs/remotes/origin/main HEAD
}
# runreal — предпроверка без подмены merge-readiness; gh — тот же подменный, и в PATH.
runreal() {
    FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" LANDING_PRECHECK_WS="$W/ws" PATH="$W:$PATH" \
        bash "$TOOL" PRO-Robotech/kacho 3036 > "$W/out" 2>&1
    echo $? > "$W/code"
}
mrcase 1; runreal
expect 0 - "Closes с DoD-proof: настоящий merge-readiness выносит вердикт (код 0), а не код 2"
if grep -q $'^CENSUS\tmerge-readiness: код 0, источник origin/main@' "$W/out"; then
    echo "  [OK]   перепись называет код 0 и источник origin/main — заглушки нет"; pass=$((pass + 1))
else
    echo "  [FAIL] перепись не называет «merge-readiness: код 0, источник origin/main@»:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1))
fi
# Набор обязательных — от НАСТОЯЩЕГО merge-readiness (MERGE_READINESS_REQUIRED_OUT):
# skipped задания вне защиты снимается, а тот же merge-readiness без записи набора
# (инъекция в него) оставляет skipped причиной — снятие держится его набором, а не
# заглушкой.
mrskip() {
    mrcase 1
    addskip
    jq --arg n "$TRUNKJOB" '.statusCheckRollup += [range(4) | {name: $n, conclusion: "SKIPPED"}]' "$W/case/prview.json" > "$W/case/prview.new" && mv "$W/case/prview.new" "$W/case/prview.json"
}
mrskip; runreal
expect 0 - "настоящий merge-readiness отдал набор: skipped вне защиты ×4 — не причина"
nreq="$(jq '.required_status_checks.contexts | length' "$W/case/protection.json")"
if grep -q $'^CENSUS\tci: .*skipped необязательных 4; набор обязательных '"$nreq"'$' "$W/out"; then
    echo "  [OK]   перепись: набор обязательных $nreq — из защиты случая"; pass=$((pass + 1))
else echo "  [FAIL] перепись не называет набор $nreq:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
mrskip
# shellcheck disable=SC2016  # $n и ${…} — переменные jq и текст образца, не оболочки
sed -i 's|if \[ -n "${MERGE_READINESS_REQUIRED_OUT:-}" \]; then|if false; then|' "$W/ws/scripts/merge-readiness.sh"
if cmp -s "$HERE/merge-readiness.sh" "$W/ws/scripts/merge-readiness.sh"; then
    echo "  [FAIL] инъекция «merge-readiness не отдаёт набор»: образец не найден" >&2; fail=$((fail + 1))
else
    sandbox_git -C "$W/ws" commit -qam mutant; sandbox_git -C "$W/ws" update-ref refs/remotes/origin/main HEAD
    runreal
    expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (набор обязательных' "инъекция: merge-readiness не отдаёт набор — skipped остаётся причиной"
fi
mrcase 1; rm "$W/case/comments-2690.json"; runreal
expect 1 $'REASON\tMERGE-READINESS\tкод 1' "Closes #2690 без DoD-proof — merge-readiness судит по существу (код 1)" many
mrcase 0; runreal
expect 2 $'VOID\tmerge-readiness.sh и scripts/lib из origin/main' "origin/main без scripts/lib — вердикта нет (код 2), а не «можно»"
# Инъекция в САМУ предпроверку: извлечение одного файла без `lib/` (прежняя форма).
# На том же случае с DoD-proof она обязана дать MERGE-READINESS код 2
# «распознавателя нет» — иначе проба положительного случая выше слепа к дефекту.
# Мутант живёт в каталоге песочницы рядом со ссылкой на `hooks/` дерева: предикат
# атрибуции предпроверка берёт рядом с собой.
mkdir -p "$W/mut"; ln -sfn "$HERE/hooks" "$W/mut/hooks"
sed 's|origin/main scripts/merge-readiness.sh scripts/lib |origin/main scripts/merge-readiness.sh |' "$TOOL" > "$W/mut/precheck-nolib.sh"
if cmp -s "$TOOL" "$W/mut/precheck-nolib.sh"; then
    echo "  [FAIL] инъекция «извлечение без lib/»: образец не найден в предпроверке" >&2; fail=$((fail + 1))
else
    mrcase 1
    FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" LANDING_PRECHECK_WS="$W/ws" PATH="$W:$PATH" \
        bash "$W/mut/precheck-nolib.sh" PRO-Robotech/kacho 3036 > "$W/out" 2>&1
    echo $? > "$W/code"
    expect 1 $'REASON\tMERGE-READINESS\tкод 2: merge-readiness: распознавателя доказательства DoD нет' "инъекция: предпроверка извлекает merge-readiness без lib/ — код 2 «распознавателя нет»"
fi

echo "== предпосылка"
twin; echo '<html>' > "$W/case/pull.json"; run 0
expect 2 $'VOID\tответ о PR' "ответ площадки не разбирается — код 2"
twin; edit pull.json '.commits += 1'; run 0
expect 2 $'VOID\tплощадка объявила коммитов' "коммитов объявлено больше прочитанного — код 2"

echo
echo "landing-precheck-inject: перепись — рассмотрено проб $((pass + fail)); сошлось $pass, не сошлось $fail"
[ $((pass + fail)) -gt 0 ] || { echo "landing-precheck-inject: не исполнено ни одной пробы — это не зелёное" >&2; exit 2; }
[ "$fail" -eq 0 ]
