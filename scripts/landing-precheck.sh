#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# landing-precheck.sh — детерминированная предпроверка посадки запроса.
#
# ЗАЧЕМ. Решение владельца 2026-10-06 («да» на «перенести условия посадки и плана
# из текста диспетчера в код»): классы ошибок оркестровки этой линии все одного
# рода — сценарий НЕ ПРОВЕРЯЛ условие, которое знал. Тело PR не по составу
# (дважды), вердикт ревью на старой голове после правки (дважды), заголовок
# «[#77]» вместо «#77 », посадка при идущем CI, разбор вердикта регуляркой по
# тексту. Здесь каждое такое условие — код, а не фраза базы: посадка идёт только
# при коде 0 (`.claude/agents/dispatcher.md` §8а).
#
# ИСПОЛЬЗОВАНИЕ
#   landing-precheck.sh <владелец/репозиторий> <номер PR> [--reviews <файл JSON>]
#
# --reviews — массив структурных вердиктов ревью: [{"role": "...", "sha": "<40 hex>",
# "verdict": "accept"|"return"|"void", "blocking": [...] (необязательно)}].
# Вердикт без поля verdict — не «принят» (REVIEW-NOT-ACCEPTED).
# Ровно та форма, которую возвращают роли шаблона `.claude/workflows/wave.js`;
# текст ответа роли не разбирается нигде (класс 7).
#
# ЧТО СУДИТСЯ — по пункту на причину; каждая причина — ОДНА строка
#   REASON<TAB><код><TAB><пояснение>
#   (а) REVIEW-STALE        — sha вердикта роли ≠ headRefOid PR: правка после
#                             ревью, роль смотрела не ту голову;
#       REVIEW-NOT-ACCEPTED — у роли verdict ≠ accept (в том числе нет поля)
#                             либо непустой blocking;
#       REVIEW-MALFORMED    — файл не массив объектов {role, sha} либо массив пуст
#                             (пустой набор вердиктов — не «все приняли»);
#   (б) TITLE-FORM          — заголовок не формы `^#<N> <не пробел>`. Канон — общий
#                             у двух стволов, где правило запроса есть:
#                             corelib `scripts/hooks/git-rule.sh` git_rule_subject_task
#                             `^#([0-9]+)\ [^[:space:]]` и kaname
#                             `scripts/hooks/branch-rule.sh` branch_rule_subject_task
#                             `^#([0-9]+)\ ` (форма corelib строже и влечёт форму
#                             kaname). У kacho на origin/main проверки запроса нет
#                             (`git ls-tree -r origin/main | grep pr-rule` пуст,
#                             2026-10-06) — канон берётся тот же;
#       TITLE-HEAD-NUMBER   — голова `<N>` или `<N>-<суть>`, а заголовок несёт
#                             другой номер (оба ствола: «заголовок — акт ветки»);
#   (в) BODY-MISSING-COMMIT — не-слияние из base..head (список площадки
#                             `pulls/<N>/commits`) не названо в теле. ПРИЗНАК:
#                             тело содержит короткий sha коммита (≥7 знаков) ЛИБО
#                             номер задачи `#<M>` из его первой строки. Слияния
#                             (родителей ≥2) из требования выведены: их первая
#                             строка — акт сборки, а не предмет;
#       BODY-FOREIGN-TASK   — тело называет `#<M>`, которого нет ни в одной первой
#                             строке коммитов диапазона и который не номер головы
#                             или базы (`#<M>` после буквы, цифры или `/` —
#                             `kaname#505` — ссылка в чужой репозиторий и не
#                             судится). Это признак §8а п.4: «задача в теле без
#                             коммита в диапазоне»;
#       Обратной сверки ПО SHA нет намеренно: тело законно называет sha базы,
#       пина в чужом репозитории и прежней головы — замер 2026-10-06 на kacho#3036
#       и #3041: шесть sha-жетонов вне диапазона, все шесть законны.
#   (г) CI-EMPTY            — на headSha нет ни одного check-run: «проверок 0» —
#                             не зелёное;
#       CI-PENDING          — check-run на headSha не завершён;
#       CI-NOT-SUCCESS      — завершён не success (neutral, cancelled, failure —
#                             всегда; skipped — см. ниже).
#       ИСКЛЮЧЕНИЕ ОДНО — skipped НЕОБЯЗАТЕЛЬНОГО задания. Задание, чьё условие
#                             на событии pull_request ложно по построению
#                             (`if: github.event_name == 'push' && github.ref ==
#                             'refs/heads/main'`), на PR кончается skipped всегда:
#                             kaname `.github/workflows/ci.yml` и `e2e-newman.yml`,
#                             задание «вердикт ствола — красное не остаётся без
#                             читателя» — замер 2026-10-06: kaname#621/#622/#623/#624
#                             несут 7/4/4/4 таких skipped при 46/23/24/23 check-runs.
#                             Признак — conclusion=skipped И имени нет в наборе
#                             обязательных контекстов, которым судит ЭТОТ PR
#                             `merge-readiness.sh` (набор отдаёт он сам файлом
#                             MERGE_READINESS_REQUIRED_OUT — выбор «база или ствол
#                             для ветки линии» второй копии здесь не имеет).
#                             Текст условия `if` не разбирается: он в YAML другого
#                             репозитория, а набор защиты — ответ площадки.
#                             skipped ОБЯЗАТЕЛЬНОГО — CI-NOT-SUCCESS; набор не
#                             получен (merge-readiness вышел раньше, путь ручного
#                             прогона воркспейса) — любой skipped CI-NOT-SUCCESS.
#                             Снятые skipped печатаются строкой CENSUS поимённо;
#   (д) MERGE-READINESS     — `scripts/merge-readiness.sh` из origin/main
#                             воркспейса дал не 0 (1 — нельзя; 2 — вердикта нет;
#                             оба — не «можно»).
#   (е) ATTRIBUTION         — строка атрибуции в сообщении коммита диапазона
#                             либо в теле. Предикат — ОДИН на дерево:
#                             `scripts/hooks/attribution-rule.sh`
#                             (attribution_line), своей копии здесь нет;
#   (ж) CLOSES-WITHOUT-PROOF — тело закрывает задачу (`Closes|Fixes|Resolves`
#                             `#<N>` либо `<владелец/репо>#<N>`), а в задаче нет
#                             комментария `DoD-proof @<sha>`, чей sha — коммит
#                             диапазона запроса: закрытие без доказательства —
#                             класс «преждевременный Closes» замера 2026-10-06;
#                             исход один — `Refs` вместо `Closes`.
#   PR-NOT-OPEN             — PR не открыт.
#
# Перепись печатается всегда, строками CENSUS<TAB>…, отдельно от причин:
# «причин 0» отличимо от «не прочитано ничего».
#
# ИСХОДЫ (код возврата — вердикт):
#   0 — причин нет, все семь пунктов осуждены (без --reviews пункт (а) печатается
#       строкой CENSUS «не судился» — посадка шаблоном волны --reviews передаёт);
#   1 — причины есть, перечислены строками REASON;
#   2 — судить не смог: строка VOID<TAB><почему> (нет gh/jq/python3, ответ
#       площадки не разбирается, коммитов в запросе больше, чем отдаёт площадка,
#       merge-readiness из origin/main не извлечь, предиката атрибуции нет,
#       комментарии закрываемой задачи не прочитаны). Это НЕ «сажать можно».
#
# ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/landing-precheck-inject.sh):
#   LANDING_PRECHECK_GH                — вместо `gh` (только `gh api <путь>`;
#                                        комментарии задач — тем же путём);
#   LANDING_PRECHECK_MERGE_READINESS   — путь к скрипту вместо merge-readiness из
#                                        origin/main; подмена печатается в CENSUS;
#   LANDING_PRECHECK_WS                — репозиторий, чей origin/main даёт
#                                        merge-readiness и scripts/lib (песочница
#                                        пробы настоящего пути (д)); по умолчанию —
#                                        этот воркспейс.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${LANDING_PRECHECK_WS:-$(cd "$HERE/.." && pwd)}"
GH="${LANDING_PRECHECK_GH:-gh}"

void() { printf 'VOID\t%s\n' "$1"; exit 2; }

REPO="${1:-}"; PR="${2:-}"
shift 2 2>/dev/null || true
REVIEWS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --reviews) REVIEWS="${2:-}"; [ -n "$REVIEWS" ] || void "--reviews без файла"; shift 2 ;;
        *) void "неизвестный довод «$1»" ;;
    esac
done
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || void "репозиторий «$REPO» не формы <владелец>/<имя>"
[[ "$PR" =~ ^[0-9]+$ ]] || void "номер PR «$PR» не число"
[ -z "$REVIEWS" ] || [ -r "$REVIEWS" ] || void "файл ревью «$REVIEWS» не читается"
for t in jq python3 git; do command -v "$t" >/dev/null 2>&1 || void "нет $t в PATH"; done
[ -n "${LANDING_PRECHECK_GH:-}" ] || command -v gh >/dev/null 2>&1 || void "нет gh в PATH"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

api() { "$GH" api "$1" 2>"$W/api.err"; }

api "repos/$REPO/pulls/$PR" > "$W/pull.json" || void "площадка не отдала PR $REPO#$PR: $(head -c 300 "$W/api.err")"
jq -e 'type == "object" and (.head.sha | type == "string") and (.title | type == "string")' "$W/pull.json" >/dev/null 2>&1 \
    || void "ответ о PR $REPO#$PR не разбирается (нет head.sha или title)"
HEAD_SHA="$(jq -r '.head.sha' "$W/pull.json")"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || void "head.sha «$HEAD_SHA» не 40 hex"

# Коммиты запроса: площадка отдаёт не больше 250 (контракт pulls/<N>/commits).
: > "$W/commits.ndjson"
page=1
while :; do
    api "repos/$REPO/pulls/$PR/commits?per_page=100&page=$page" > "$W/page.json" \
        || void "площадка не отдала коммиты PR (страница $page): $(head -c 300 "$W/api.err")"
    jq -e 'type == "array"' "$W/page.json" >/dev/null 2>&1 || void "коммиты PR (страница $page) — не массив"
    n="$(jq 'length' "$W/page.json")"
    jq -c '.[]' "$W/page.json" >> "$W/commits.ndjson"
    [ "$n" -eq 100 ] || break
    page=$((page + 1))
    [ "$page" -le 3 ] || break
done

# Check-runs головы, все страницы; total_count сверяется с прочитанным.
: > "$W/runs.ndjson"
page=1
total=""
while :; do
    api "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100&filter=latest&page=$page" > "$W/page.json" \
        || void "площадка не отдала check-runs $HEAD_SHA (страница $page): $(head -c 300 "$W/api.err")"
    jq -e 'type == "object" and (.check_runs | type == "array")' "$W/page.json" >/dev/null 2>&1 \
        || void "check-runs (страница $page) не объект со списком check_runs"
    [ -n "$total" ] || total="$(jq '.total_count // -1' "$W/page.json")"
    n="$(jq '.check_runs | length' "$W/page.json")"
    jq -c '.check_runs[]' "$W/page.json" >> "$W/runs.ndjson"
    [ "$n" -eq 100 ] || break
    page=$((page + 1))
done

# (е) атрибуция — предикатом дерева, по каждому сообщению коммита и по телу.
[ -r "$HERE/hooks/attribution-rule.sh" ] || void "предиката атрибуции нет: $HERE/hooks/attribution-rule.sh"
# shellcheck source=hooks/attribution-rule.sh
. "$HERE/hooks/attribution-rule.sh"
declare -F attribution_line >/dev/null || void "в hooks/attribution-rule.sh нет attribution_line"
: > "$W/attr"
n_attr_seen=0
while IFS= read -r c; do
    [ -n "$c" ] || continue
    s="$(jq -r '.sha // ""' <<< "$c")"
    m="$(jq -r '.commit.message // ""' <<< "$c")"
    n_attr_seen=$((n_attr_seen + 1))
    if a="$(attribution_line "$m")"; then
        printf '%s\t%s\n' "коммит ${s:0:12}" "$a" >> "$W/attr"
    fi
done < "$W/commits.ndjson"
if a="$(attribution_line "$(jq -r '.body // ""' "$W/pull.json")")"; then
    printf '%s\t%s\n' "тело" "$a" >> "$W/attr"
fi

# (д) merge-readiness из origin/main воркспейса — не из рабочей копии: рабочая
# копия может нести непринятую правку инструмента.
MR_SRC=""
if [ -n "${LANDING_PRECHECK_MERGE_READINESS:-}" ]; then
    MR="$LANDING_PRECHECK_MERGE_READINESS"
    MR_SRC="подмена из окружения: $MR"
else
    # Извлекается не один файл, а всё, что инструмент подключает рядом с собой:
    # `scripts/lib/` (распознаватель DoD `lib/dod_proof.jq`). Без него
    # merge-readiness выходил кодом 2 «распознавателя нет» на КАЖДОЙ посадке
    # (ws#935, найдено на kacho#3043) — пункт (д) не судился ни разу.
    mkdir -p "$W/mr"
    git -C "$WS" archive --format=tar -o "$W/mr.tar" origin/main scripts/merge-readiness.sh scripts/lib 2>"$W/api.err" \
        || void "merge-readiness.sh и scripts/lib из origin/main воркспейса не извлекаются: $(head -c 300 "$W/api.err")"
    tar -xf "$W/mr.tar" -C "$W/mr" || void "архив merge-readiness из origin/main не распаковался"
    MR="$W/mr/scripts/merge-readiness.sh"
    MR_SRC="origin/main@$(git -C "$WS" rev-parse --short=12 origin/main)"
fi
rm -f "$W/required"
MERGE_READINESS_REQUIRED_OUT="$W/required" bash "$MR" "$REPO" "$PR" > "$W/mr.out" 2>&1
MR_CODE=$?

export W REPO PR HEAD_SHA REVIEWS MR_CODE MR_SRC TOTAL_RUNS="$total" GH N_ATTR_SEEN="$n_attr_seen"
python3 - <<'PY'
import json, os, re, sys

W = os.environ["W"]
head = os.environ["HEAD_SHA"]
pull = json.load(open(f"{W}/pull.json"))
commits = [json.loads(l) for l in open(f"{W}/commits.ndjson") if l.strip()]
runs = [json.loads(l) for l in open(f"{W}/runs.ndjson") if l.strip()]
reasons, census = [], []

def reason(code, text):
    reasons.append((code, " ".join(str(text).split())))

def void(text):
    print(f"VOID\t{text}")
    sys.exit(2)

if pull.get("state") != "open":
    reason("PR-NOT-OPEN", f"PR в состоянии {pull.get('state')!r}")

# (а) вердикты ревью
rev_path = os.environ.get("REVIEWS", "")
if rev_path:
    try:
        reviews = json.load(open(rev_path))
    except Exception as e:  # noqa: BLE001 — любой отказ разбора одинаково «не массив»
        reviews = None
        reason("REVIEW-MALFORMED", f"файл ревью не разбирается как JSON: {e}")
    if reviews is not None:
        if not isinstance(reviews, list) or not reviews:
            reason("REVIEW-MALFORMED", "файл ревью — не непустой массив: пустой набор вердиктов не «все приняли»")
        else:
            for i, r in enumerate(reviews):
                if not (isinstance(r, dict) and isinstance(r.get("role"), str) and r["role"]
                        and isinstance(r.get("sha"), str)):
                    reason("REVIEW-MALFORMED", f"вердикт [{i}] не объект {{role, sha}}")
                    continue
                if r["sha"] != head:
                    reason("REVIEW-STALE", f"роль {r['role']}: вердикт на {r['sha'][:12] or '<пусто>'}, голова PR {head[:12]} — смотреть дельту на новой голове")
                v, b = r.get("verdict"), r.get("blocking")
                if v != "accept" or (b not in (None, [])):
                    reason("REVIEW-NOT-ACCEPTED", f"роль {r['role']}: verdict={v!r}, blocking={len(b) if isinstance(b, list) else b!r}")
            census.append(f"ревью: вердиктов {len(reviews)}")
else:
    census.append("ревью: --reviews не передан — пункт (а) НЕ СУДИЛСЯ")

# (б) заголовок
title = pull.get("title") or ""
head_ref = (pull.get("head") or {}).get("ref") or ""
base_ref = (pull.get("base") or {}).get("ref") or ""
m = re.match(r"#([0-9]+) \S", title)
if not m:
    reason("TITLE-FORM", f"заголовок не формы «#<N> …»: {title!r}")
else:
    hm = re.match(r"([0-9]+)(?:-|$)", head_ref)
    if hm and hm.group(1) != m.group(1):
        reason("TITLE-HEAD-NUMBER", f"заголовок #{m.group(1)} у головы {head_ref!r}: номер заголовка — номер ветки (#{hm.group(1)})")

# (в) тело = состав
body = pull.get("body") or ""
declared = pull.get("commits")
if isinstance(declared, int) and declared != len(commits):
    void(f"площадка объявила коммитов {declared}, отдала {len(commits)} — диапазон неполон")
if not commits:
    void("в запросе ноль коммитов — состава нет")
NUM = re.compile(r"(?<![\w/#])#([0-9]+)\b")
range_numbers = set()
nonmerge = 0
for c in commits:
    sha = c.get("sha", "")
    subj = ((c.get("commit") or {}).get("message") or "").split("\n", 1)[0]
    nums = set(NUM.findall(subj))
    range_numbers |= nums
    if len(c.get("parents") or []) >= 2:
        continue
    nonmerge += 1
    named_sha = bool(sha) and re.search(r"(?<![0-9A-Za-z])" + re.escape(sha[:7]), body) is not None
    named_num = any(re.search(r"(?<![\w/#])#" + n + r"\b", body) for n in nums)
    if not (named_sha or named_num):
        reason("BODY-MISSING-COMMIT", f"{sha[:12]} «{subj[:80]}» — в теле нет ни его sha, ни номера {', '.join('#'+n for n in sorted(nums)) or '(номера в первой строке нет)'}")
own = set(range_numbers)
for ref in (head_ref, base_ref):
    mm = re.match(r"([0-9]+)(?:-|$)", ref)
    if mm:
        own.add(mm.group(1))
for n in sorted(set(NUM.findall(body)) - own, key=int):
    reason("BODY-FOREIGN-TASK", f"тело называет #{n}, а коммита с этим номером в диапазоне нет (и это не номер головы или базы)")
census.append(f"состав: коммитов {len(commits)}, из них не-слияний {nonmerge}, номеров в первых строках {len(range_numbers)}, тело {len(body)} знаков")

# (г) CI на голове
total = int(os.environ.get("TOTAL_RUNS") or -1)
if total >= 0 and total != len(runs):
    void(f"check-runs: объявлено {total}, прочитано {len(runs)} — непрочитанная страница могла нести красное")
own_runs = [r for r in runs if r.get("head_sha", head) == head]
if not own_runs:
    reason("CI-EMPTY", f"на {head[:12]} ни одного check-run — «проверок 0» не зелёное")
pending = [r for r in own_runs if r.get("status") != "completed"]
bad = [r for r in own_runs if r.get("status") == "completed" and r.get("conclusion") != "success"]
# Набор обязательных — тот, которым судит этот PR merge-readiness (файл пишет он).
required = None
if os.path.exists(f"{W}/required"):
    required = {l.rstrip("\n") for l in open(f"{W}/required", encoding="utf-8") if l.strip()}
    if not required:
        required = None  # пустой набор — не «все необязательны»
skipped_free = [r for r in bad if r.get("conclusion") == "skipped"
                and required is not None and r.get("name") not in required]
for r in pending:
    reason("CI-PENDING", f"{r.get('name')} — {r.get('status')}")
for r in bad:
    if r in skipped_free:
        continue
    why = ""
    if r.get("conclusion") == "skipped":
        why = (" (контекст обязательный)" if required is not None
               else " (набор обязательных от merge-readiness не получен — необязательность не установлена)")
    reason("CI-NOT-SUCCESS", f"{r.get('name')} — {r.get('conclusion')}{why}")
census.append(f"ci: check-runs на голове {len(own_runs)}, success {len(own_runs) - len(pending) - len(bad)}, идут {len(pending)}, не-success {len(bad) - len(skipped_free)}, skipped необязательных {len(skipped_free)}; набор обязательных {len(required) if required is not None else 'НЕ ПОЛУЧЕН'}")
for nm in sorted({r.get("name") for r in skipped_free}):
    census.append(f"ci: skipped необязательного не причина — {nm} ×{sum(1 for r in skipped_free if r.get('name') == nm)}")

# (д) merge-readiness
mr = int(os.environ["MR_CODE"])
if mr != 0:
    tail = [l for l in open(f"{W}/mr.out").read().splitlines() if l.strip()][-1:] or ["(вывода нет)"]
    reason("MERGE-READINESS", f"код {mr}: {tail[0]}")
census.append(f"merge-readiness: код {mr}, источник {os.environ['MR_SRC']}")

# (е) атрибуция — строки собраны предикатом дерева до этого места
attr = [l.rstrip("\n").split("\t", 1) for l in open(f"{W}/attr", encoding="utf-8") if l.strip()]
for where, line in attr:
    reason("ATTRIBUTION", f"{where}: «{line[:120]}» — строк атрибуции в коммитах и теле ноль")
census.append(f"атрибуция: сообщений {os.environ['N_ATTR_SEEN']} и тело, строк {len(attr)}")

# (ж) Closes только с доказательством DoD на коммите диапазона
import subprocess
CLOSE = re.compile(r"(?i)(?<![\w-])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+((?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+)\b")
PROOF = re.compile(r"(?:^|\n)DoD-proof @([0-9a-f]{7,40})")
range_shas = [c.get("sha", "") for c in commits if c.get("sha")]
closes = []
for ref in CLOSE.findall(body):
    r, n = ref.split("#")
    r = r or os.environ["REPO"]
    if (r, n) not in closes:
        closes.append((r, n))
proven = 0
for r, n in closes:
    shas, page = [], 1
    while True:
        p = subprocess.run([os.environ.get("GH") or "gh", "api", f"repos/{r}/issues/{n}/comments?per_page=100&page={page}"],
                           capture_output=True, text=True)
        if p.returncode != 0:
            void(f"комментарии {r}#{n} не прочитаны: {p.stderr.strip()[:200]}")
        try:
            items = json.loads(p.stdout)
        except ValueError:
            void(f"комментарии {r}#{n} не разбираются")
        if not isinstance(items, list):
            void(f"комментарии {r}#{n} — не массив")
        for it in items:
            shas += PROOF.findall((it or {}).get("body") or "")
        if len(items) < 100:
            break
        page += 1
    if any(any(full.startswith(s) for full in range_shas) for s in shas):
        proven += 1
    elif shas:
        reason("CLOSES-WITHOUT-PROOF", f"{r}#{n}: DoD-proof есть ({', '.join(s[:12] for s in shas)}), но ни один sha не коммит запроса — Refs, а не Closes")
    else:
        reason("CLOSES-WITHOUT-PROOF", f"{r}#{n}: комментария «DoD-proof @<sha>» нет — Refs, а не Closes")
census.append(f"закрытие: Closes {len(closes)}, с доказательством {proven}")

print(f"CENSUS\t{os.environ['REPO']}#{os.environ['PR']} голова {head[:12]} ({head_ref} → {base_ref})")
for c in census:
    print(f"CENSUS\t{c}")
for code, text in reasons:
    print(f"REASON\t{code}\t{text}")
print(f"VERDICT\t{'land' if not reasons else 'stop'}\tпричин {len(reasons)}")
sys.exit(1 if reasons else 0)
PY
