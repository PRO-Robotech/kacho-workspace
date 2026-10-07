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
# НАБОР ОБЯЗАТЕЛЬНЫХ (пункт (г), skipped): у близнеца — все имена захвата,
# заглушка merge-readiness отдаёт его файлом MERGE_READINESS_REQUIRED_OUT, как
# настоящий. В «(д) настоящий» набор отдаёт сам merge-readiness из защиты случая,
# а его мутант без записи набора обязан оставить skipped причиной.
#
# УСЛОВИЕ IF (пункт (г), ws#947): skipped законен только по разобранному условию
# задания в файле workflow на голове. Вход — второй захват,
# `landing-precheck-fixtures/kaname-629/` (2026-10-06, kaname#629 @88c4e475):
# четыре настоящих skipped check-run (`…/commits/<sha>/check-runs`, поля name,
# status, conclusion, head_sha, check_suite.id), прогоны workflow головы
# (`…/actions/runs?head_sha=<sha>`) и три файла workflow на голове, обрезанные до
# `jobs.<ключ>.{name,if}` — значения `if` дословны. Он ПРИВИВАЕТСЯ к случаю
# kacho#3036 (addskip): head_sha и ветка push-прогона переписаны на голову
# случая, больше правок нет. Подменный gh отдаёт файл workflow ТОЛЬКО на ref,
# равный голове случая: чтение на другой ревизии — «не прочитан», то есть причина.
# Мутанты самой предпроверки («любой skipped законен», «список имён») обязаны
# провалить пробу (2) «skipped без такого if».
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
    */actions/runs\?*page=1)
        if [ -f "$FAKE/runs.json" ]; then cat "$FAKE/runs.json"; else echo '{"total_count":0,"workflow_runs":[]}'; fi ;;
    */actions/runs\?*)         echo '{"total_count":0,"workflow_runs":[]}' ;;
    */contents/*\?ref=*)
        p="${2#*/contents/}"; ref="${p##*\?ref=}"; p="${p%%\?ref=*}"
        [ "$ref" = "$(cat "$FAKE/head" 2>/dev/null)" ] || { echo "fake gh: файл $p на $ref — не голова случая" >&2; exit 1; }
        [ -f "$FAKE/wf/$p" ] || { echo "fake gh: Not Found $p" >&2; exit 1; }
        printf '{"encoding":"base64","content":"%s"}\n' "$(base64 -w0 < "$FAKE/wf/$p")" ;;
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
    echo "$HEAD_SHA" > "$W/case/head"
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
# Задание «только push main» (kaname ci.yml, docker-build.yml, e2e-newman.yml):
# на PR skipped по построению, в наборе обязательных его нет. Вход — захват
# kaname#629, привитый к случаю (шапка, «УСЛОВИЕ IF»).
TRUNKJOB='вердикт ствола — красное не остаётся без читателя'
K629="$FIX/kaname-629"
# shellcheck disable=SC2016  # $h, $b, $s — переменные jq
addskip() {
    local s b
    s="$(jq -r '.check_runs[0].head_sha' "$W/case/check-runs.json")"
    b="$(jq -r '.head.ref' "$W/case/pull.json")"
    jq --slurpfile k "$K629/skipped-check-runs.json" --arg h "$s" \
        '.check_runs += [$k[0][] | .head_sha = $h] | .total_count += ($k[0] | length)' \
        "$W/case/check-runs.json" > "$W/case/check-runs.new" && mv "$W/case/check-runs.new" "$W/case/check-runs.json"
    jq --arg h "$s" --arg b "$b" '.workflow_runs |= map(.head_sha = $h | .head_branch = $b)' "$K629/runs.json" > "$W/case/runs.json"
    rm -rf "$W/case/wf"; cp -r "$K629/wf" "$W/case/wf"
}
# setif <yq-выражение для значения if задания trunkverdict | del> — во всех трёх файлах.
setif() {
    local f
    for f in "$W"/case/wf/.github/workflows/*.yml; do
        if [ "$1" = del ]; then yq -i 'del(.jobs.trunkverdict.if)' "$f"
        else V="$1" yq -i '.jobs.trunkverdict.if = strenv(V)' "$f"; fi
    done
}
twin; addskip; run 0
expect 0 - "(1) skipped задания с if push-в-main ×4 на запросе — не причина"
if grep -q $'^CENSUS\tci: .*skipped по невыполнимому if 4; набор обязательных' "$W/out" \
    && [ "$(grep -c $'^CENSUS\tci: skipped не причина — условие if невыполнимо: '"$TRUNKJOB"' ×1 (.github/workflows/' "$W/out")" = 4 ]; then
    echo "  [OK]   снятый skipped назван в переписи поимённо, файлом и событием"; pass=$((pass + 1))
else echo "  [FAIL] перепись не называет снятый skipped:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
if grep -q $'^CENSUS\tci: .*docker-build.yml на push)$' "$W/out"; then
    echo "  [OK]   push-прогон ветки головы судится тем же условием"; pass=$((pass + 1))
else echo "  [FAIL] push-прогон не снят по условию:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
twin; addskip; setif del; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "(2) skipped без условия if — CI-NOT-SUCCESS"
if [ "$(grep -c $'^REASON\tCI-NOT-SUCCESS\t.*условия if нет' "$W/out")" = 4 ]; then
    echo "  [OK]   (2) все четыре названы причиной «условия if нет»"; pass=$((pass + 1))
else echo "  [FAIL] (2) не четыре причины «условия if нет»:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
twin; addskip; setif "\${{ always() }}"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "(2) skipped при if: always() — пропущен не условием"
twin; addskip; setif "\${{ !cancelled() && github.event_name == 'pull_request' }}"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "(3) if с event_name == pull_request — skipped на запросе провал"
if [ "$(grep -c '^REASON' "$W/out")" = 3 ]; then
    echo "  [OK]   (3) причин три — прогоны pull_request; push-прогон этим условием и правда невыполним"; pass=$((pass + 1))
else echo "  [FAIL] (3) ожидалось три причины:" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1)); fi
twin; addskip; setif "\${{ github.event_name == 'push' || github.event_name == 'pull_request' }}"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "(3) if push || pull_request — skipped провал"
twin; addskip; setif "\${{ github.event_name == 'pull_request' && github.base_ref == 'main' }}"; run 0
expect 0 - "близнец (3): if на pull_request только в main, база запроса 1266 — невыполним, не причина"
twin; addskip; setif "\${{ github.event_name == 'pull_request' && github.base_ref == '1266' }}"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "(3) if на pull_request в ЭТУ базу — skipped провал"
twin; addskip; setif "\${{ !cancelled() && github.event_name == 'PUSH' && github.ref == 'refs/heads/main' }}"; run 0
expect 0 - "близнец (1): строки сравниваются без регистра — 'PUSH' то же условие"
twin; addskip; setif "\${{ github.event_name == 'push' && (github.ref == 'refs/heads/main' || github.ref == 'refs/heads/2966') }}"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/docker-build.yml: условие выполнимо' "if push в main ИЛИ в ветку головы — push-прогон выполним, причина"
twin; addskip; setif "\${{ github.event_name == 'push' && github.ref == 'refs/heads/main'"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (.github/workflows/' "условие без закрытия }} — не разобрано, причина"
twin; addskip; jq '.workflow_runs = [] | .total_count = 0' "$W/case/runs.json" > "$W/case/runs.new" && mv "$W/case/runs.new" "$W/case/runs.json"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (прогон workflow набора' "прогон workflow check-run не найден — условие не прочитать, причина"
twin; addskip; rm "$W/case/wf/.github/workflows/ci.yml"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (файл .github/workflows/ci.yml на' "файл workflow на голове не прочитан — причина"
twin; addskip; echo "0000000000000000000000000000000000000000" > "$W/case/head"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (файл .github/workflows/' "файл есть только на другой ревизии — читается голова, причина"
twin; addskip; yq -i '.jobs.trunkverdict.name = "другое имя"' "$W/case/wf/.github/workflows/e2e-newman.yml"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (в .github/workflows/e2e-newman.yml нет задания' "задания с этим именем в файле нет — причина"
twin; addskip; jq '(.workflow_runs[] | select(.event == "push") | .event) |= "workflow_dispatch"' "$W/case/runs.json" > "$W/case/runs.new" && mv "$W/case/runs.new" "$W/case/runs.json"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (событие прогона '"'workflow_dispatch'" "событие прогона вне моделируемых — причина"
twin; addskip; jq '(.workflow_runs[] | select(.event == "push") | .head_branch) |= "main"' "$W/case/runs.json" > "$W/case/runs.new" && mv "$W/case/runs.new" "$W/case/runs.json"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (событие прогона '"'push'"' (ветка '"'main'" "push-прогон не ветки головы — не моделируется, причина"
# Мутанты самой предпроверки: обязаны провалить пробу (2) «skipped без такого if».
mkdir -p "$W/mut"; ln -sfn "$HERE/hooks" "$W/mut/hooks"
mutant() {  # mutant <имя> <строка, вставляемая первой в тело skip_lawful>
    local out="$W/mut/precheck-$1.sh"
    awk -v ins="$2" '{print} /^def skip_lawful\(r\):$/ {getline; print; print "    " ins}' "$TOOL" > "$out"
    if cmp -s "$TOOL" "$out"; then
        echo "  [FAIL] мутант «$1»: образец def skip_lawful не найден" >&2; fail=$((fail + 1)); return
    fi
    twin; addskip; setif del
    FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" LANDING_PRECHECK_MERGE_READINESS="$W/mr0" \
        bash "$out" PRO-Robotech/kacho 3036 > "$W/out" 2>&1
    local code=$?
    if [ "$code" = 0 ] && ! grep -q '^REASON' "$W/out"; then
        echo "  [OK]   мутант «$1» проваливает пробу (2): код 0 там, где skipped без if"; pass=$((pass + 1))
    else
        echo "  [FAIL] мутант «$1» не пойман пробой (2): код $code" >&2; sed 's/^/           /' "$W/out" >&2; fail=$((fail + 1))
    fi
}
mutant any-skipped 'return True, "мутант: любой skipped законен"'
mutant name-list 'return r.get("name") in {"вердикт ствола — красное не остаётся без читателя"}, "мутант: список имён"'
twin; addskip; echo "$TRUNKJOB" >> "$W/case/required"; run 0
expect 1 $'REASON\tCI-NOT-SUCCESS\t'"$TRUNKJOB"' — skipped (контекст обязательный)' "близнец: то же задание в наборе обязательных — skipped не зелёный и при невыполнимом if"
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
expect 0 - "настоящий merge-readiness отдал набор: skipped вне защиты с невыполнимым if ×4 — не причина"
nreq="$(jq '.required_status_checks.contexts | length' "$W/case/protection.json")"
if grep -q $'^CENSUS\tci: .*skipped по невыполнимому if 4; набор обязательных '"$nreq"'$' "$W/out"; then
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

echo "== запуск: рецепт шапки «ЗАПУСК» как он есть, при снятом TMPDIR"
# Близнец — ТЕКСТ рецепта, вырезанный из шапки предпроверки по меткам «рецепт
# ЗАПУСК», исполненный при СНЯТОМ TMPDIR: песочница-воркспейс несёт в origin/main
# весь каталог scripts/ этого дерева, origin — голый репозиторий рядом, так что
# `git fetch origin main` рецепта настоящий. Обязан: код 0, временный каталог —
# в tmp/ воркспейса и после прогона снят. Инъекции меняют по ОДНОМУ факту:
#   — origin недоступен: подготовка не состоялась — код 2 (вердикта нет), а не 1;
#   — рецепт, зависящий от TMPDIR (`"$TMPDIR/wsg.XXXX"`, дефект ревью #960):
#     при снятом TMPDIR вердикта нет — проба близнеца его бы поймала (код ≠ 0);
#   — из того же архива ОДИН файл предпроверки: соседей (`hooks/attribution-rule.sh`)
#     нет — код 2 с указанием на рецепт.
mrcase 1
rm -rf "$W/ws/scripts"; cp -r "$HERE" "$W/ws/scripts"
sandbox_git -C "$W/ws" add -A
sandbox_git -C "$W/ws" commit -qm whole-scripts
rm -rf "$W/origin.git"
sandbox_git init -q --bare "$W/origin.git"
sandbox_git -C "$W/ws" push -q "$W/origin.git" HEAD:refs/heads/main
sandbox_git -C "$W/ws" remote remove origin 2>/dev/null
sandbox_git -C "$W/ws" remote add origin "$W/origin.git"
sandbox_git -C "$W/ws" update-ref -d refs/remotes/origin/main
rm -rf "$W/ws/tmp"; mkdir -p "$W/ws/tmp"
RECIPE="$(sed -n '/^# >>> рецепт ЗАПУСК$/,/^# <<< рецепт ЗАПУСК$/{/рецепт ЗАПУСК$/d;s/^#//;p}' "$TOOL")"
RECIPE="${RECIPE//<аргументы>/PRO-Robotech/kacho 3036}"
# recipe <текст> — рецепт при снятом TMPDIR. HOME — вызывающего, как у прочих
# прогонов предпроверки в этой пробе: рецепт истории не пишет (fetch и archive),
# а подмена HOME меняет разрешение инструментов в PATH, не относящееся к рецепту.
recipe() {
    env -u TMPDIR WS="$W/ws" S=landing-precheck.sh \
        FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" PATH="$W:$PATH" \
        bash -c "$1" > "$W/out" 2>&1
    echo $? > "$W/code"
}
# shellcheck disable=SC2016  # образец — текст рецепта, подстановка не нужна
if [ -z "$RECIPE" ] || [[ "$RECIPE" != *'bash "$D/scripts/$S" PRO-Robotech/kacho 3036'* ]]; then
    echo "  [FAIL] рецепт по меткам «рецепт ЗАПУСК» из шапки не вырезан либо без <аргументы>" >&2; fail=$((fail + 1))
else
    recipe "$RECIPE"
    expect 0 - "рецепт шапки при снятом TMPDIR: архив scripts/ из origin/main — вердикт выносится (код 0)"
    if [ -z "$(ls -A "$W/ws/tmp")" ]; then echo "  [OK]   рецепт снял свой каталог в tmp/ воркспейса"; pass=$((pass + 1))
    else echo "  [FAIL] после рецепта в tmp/ воркспейса осталось: $(ls -A "$W/ws/tmp")" >&2; fail=$((fail + 1)); fi
    sandbox_git -C "$W/ws" remote set-url origin "$W/no-such-origin.git"
    recipe "$RECIPE"
    sandbox_git -C "$W/ws" remote set-url origin "$W/origin.git"
    expect 2 'ЗАПУСК: подготовка архива scripts/ из origin/main' "инъекция: origin недоступен — подготовка не состоялась, код 2, а не 1"
    # shellcheck disable=SC2016  # замена текста рецепта, подстановка не нужна
    MUT="${RECIPE//'${TMPDIR:-$WS/tmp}'/'$TMPDIR'}"
    if [ "$MUT" = "$RECIPE" ]; then
        echo "  [FAIL] инъекция «рецепт от TMPDIR»: образец \${TMPDIR:-\$WS/tmp} в рецепте не найден" >&2; fail=$((fail + 1))
    else
        recipe "$MUT"
        if [ "$(cat "$W/code")" != 0 ]; then echo "  [OK]   инъекция: рецепт от TMPDIR при снятом TMPDIR вердикта не выносит (код $(cat "$W/code")) — близнец это ловит"; pass=$((pass + 1))
        else echo "  [FAIL] инъекция: рецепт от TMPDIR дал код 0 при снятом TMPDIR — проба близнеца слепа" >&2; fail=$((fail + 1)); fi
    fi
fi
rm -rf "$W/arch" "$W/single"; mkdir -p "$W/arch" "$W/single"
git -C "$W/ws" archive HEAD scripts | tar -x -C "$W/arch"
cp "$W/arch/scripts/landing-precheck.sh" "$W/single/"
FAKE="$W/case" LANDING_PRECHECK_GH="$W/gh" LANDING_PRECHECK_WS="$W/ws" PATH="$W:$PATH" \
    bash "$W/single/landing-precheck.sh" PRO-Robotech/kacho 3036 > "$W/out" 2>&1
echo $? > "$W/code"
expect 2 $'VOID\tпредиката атрибуции нет: '"$W"'/single/hooks/attribution-rule.sh — скрипт запущен не из каталога scripts/ целиком (рецепт — шапка, «ЗАПУСК»)' "инъекция: предпроверка скопирована одним файлом — код 2 с указанием на рецепт"

echo "== предпосылка"
twin; echo '<html>' > "$W/case/pull.json"; run 0
expect 2 $'VOID\tответ о PR' "ответ площадки не разбирается — код 2"
twin; edit pull.json '.commits += 1'; run 0
expect 2 $'VOID\tплощадка объявила коммитов' "коммитов объявлено больше прочитанного — код 2"

echo
echo "landing-precheck-inject: перепись — рассмотрено проб $((pass + fail)); сошлось $pass, не сошлось $fail"
[ $((pass + fail)) -gt 0 ] || { echo "landing-precheck-inject: не исполнено ни одной пробы — это не зелёное" >&2; exit 2; }
[ "$fail" -eq 0 ]
