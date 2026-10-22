#!/usr/bin/env bash
# ЕДИНЫЙ ВХОД доказательств набора rituals: самопробы СПОСОБНЫ упасть (ws#930).
#
# Каждая инъекция — мутант НАСТОЯЩЕГО rituals.py в копии каталога, ровно в одном
# месте (`mutate` требует, чтобы якорь встретился один раз: иначе мутант молча не
# применился бы, и зелёное контроля читалось бы как доказательство). От самопробы
# своего ритуала требуется код 1. Контроль — та же копия без мутации — обязан дать 0
# по всем шести: иначе красное мутанта пришло бы от соседа, а не от предмета.
#
#   M1 pr-body: Closes без доказательства        → check-01 красная
#   M2 pr-body: предикат атрибуции ослеп          → check-01 красная
#   M3 close-wave: остаток закрыт без доказательства → check-02 красная
#   M4 approval-event: событие без правки блока   → check-03 красная
#   M5 approval-event: публикация до проверки записываемости → check-03 красная
#   M6 vault-trails: состояние закрытой задачи не done → check-04 красная
#   M7 vault-trails: исход vault-gate проглочен   → check-04 красная
#
# Возврат check-verifier к ws#930: мутанты, которые прежние пробы пропускали зелёными
# или красили соседним отказом. Самопробы судят отказ по коду И по причине, поэтому
# каждый из них краснеет своей пробой, а не чужой:
#   M8  approval-event: отпечаток документа не сверяется      → check-03
#   M9  approval-event: повтор события не запрещён            → check-03
#   M10 close-wave: перечитывание после действий слепо         → check-02
#   M11 pr-body: закрытая задача с доказательством — Closes    → check-01
#   M12 approval-event: документ записи не сверяется с названным → check-03
#   M13 vault-trails: код генератора указателя проглочен       → check-04
#   M14 approval-event: правка, задевшая другие поля, принята   → check-03
#   M15 approval-event: значение ответа трекера без кавычек     → check-03
#   M16 approval-event: тип отпечатка в записи не судится       → check-03
#   M17 approval-event: правка записи не проверена до публикации → check-03
#   M18 общий распознаватель DoD: маркер посреди прозы засчитан
#       (`scripts/lib/dod_proof.jq` — один на ритуалы, merge-readiness и cascade-census) → check-01
#
# Второй возврат check-verifier к ws#930 (B-r2): мутанты, выжившие при зелёных самопробах.
#   M19 approval-event: запись без verdict/reviewer_role не судится → check-03
#   M20 pr-body: атрибуция в собранном теле не судится (пришла из заголовка задачи) → check-01
#   M21 dod_proof.jq: ревизия любого вида, а не 7–40 шестнадцатеричных → check-01
#   M22 dod_proof: первое доказательство вместо последнего           → check-04
#       (до ws#1146 — check-01; у pr-body с тех пор свой отбор, по диапазону: M45)
#   M23–M25 gh_list: только первая страница списка трекера — двойник отдаёт
#       страницы по `per_page`, и каждая самопроба, чей ритуал читает список,
#       несёт предмет на второй странице                         → check-01, -02, -04
#       (`approval-event` списков трекера не читает: мутанту в check-03 предмета нет)
#
# Третий возврат check-verifier к ws#932 (932-r3): мутанты распознавателя, выжившие
# потому, что близнецы `@main`/`@abc12` отбивались длиной, а не алфавитом.
#   M26–M27 dod_proof.jq: ревизия из [0-9a-z] (длина прежняя) — `@develop`
#       засчитан доказательством                                  → check-01, -02
#   M28–M29 dod_proof.jq: маркер без `@` засчитан (`DoD-proof abc1234`) → check-01, -02
#
# ws#941: первая строка коммита approval-event — «#<N> », N из имени ветки.
#   M30 approval-event: префикс номера снят («review: …»)              → check-03
#   M31 approval-event: граница номера ветки снята (`896x`, `0526` — номер) → check-03
#   M32 approval-event: номер взят из задачи-держателя, а не из ветки  → check-03
#   M33 approval-event: отсоединённая голова не судится отдельно        → check-03
#   M34 approval-event: номер — последнее число имени ветки, а не число до
#       первого дефиса (`896-r8-526` → 526)                              → check-03
#   M35 approval-event: ветка читается из cwd, `RITUAL_REPO_DIR` пропущен  → check-03
#
# ws#1146: тело PR из git — `scripts/pr-body.sh <репо> <база> <голова>` (логика здесь, в
# rituals.py). Каждый мутант роняет одно правило, которым судят landing-precheck и
# merge-readiness, и краснит check-01 своей пробой:
#   M36 pr-body: доказательство вне диапазона засчитано (ревизия базы, ревизии нет) → check-01
#   M37 pr-body: держатель записи долга не судится                    → check-01
#   M38 pr-body: форма держателя ведомости снята — любое упоминание держит (близнец) → check-01
#   M39 pr-body: упомянутые вне первых строк — с `#`                    → check-01
#   M40 pr-body: заголовок задачи с `#N` — без замены                   → check-01
#   M41 pr-body: первая строка — первый абзац (`%s` git)                → check-01
#   M42 pr-body: Closes перед Refs (хвост не последний)                → check-01
#   M43 pr-body: снятая ведомость своего репозитория не судится        → check-01
#   M44 pr-body: вложенные полосы не раскрыты                         → check-01
#   M45 pr-body: названо первое доказательство диапазона, а не последнее → check-01
#   M46 pr-body: номера задач — из всего сообщения, а не из первой строки → check-01
#   M47 pr-body: задача первой строки в полной форме — голым `#N`       → check-01
#   M48 pr-body: задача первой строки в полной форме — не задача       → check-01
#   M49 правило ссылки (ws#1155, одно на `task_ref_re` и `issue_refs`): `/` перед краткой
#       формой снят — `otherorg/kaname#N` засчитан задачей своего репозитория → check-01
#   M64–M65 регистр владельца различается (адрес; полная форма)         → check-01
#   M66 голый номер — и в ведомости чужого репозитория                  → check-01
#   M67 хвост номера — только «не цифра» (`#5a` — задача 5)              → check-01
#   M68 issue_refs снова своим выражением, мимо общего правила           → check-01
#   близнец T3: граница краткой формы записана иным классом — зелен
#   M50 pr-body: догон базы не распознан — номера строки догона берутся задачами → check-01
#   M51 pr-body: строка догона в составе — с `#N` базы                   → check-01
#   M52 pr-body: доказательство засчитано лишь на голове — предок диапазона
#       с деревом головы, который судьи засчитывают, дал бы Refs          → check-01
# Приёмка check-verifier на 2975fdd18: догон — по СТРУКТУРЕ (сторонний родитель достижим из
# базы), словесный перечень снят; его мутанты A1, A5–A9, C1 предмета больше не имеют.
#   M53 pr-body: любое слияние — догон (аналог C1: любая ветка — ствол)   → check-01
#   M54 pr-body: достижимость сторонних родителей — от головы, не от базы  → check-01
#   M55 pr-body: префикс догона отброшен (B1: `head = ""`)                → check-01
#   M56 pr-body: префикс догона не идёт в задачи (B2)                     → check-01
#
# ws#1164: номер первой строки, которого нет в репозитории запроса (404 настоящей формы), —
# задача другого репозитория владельца из ведомости стволов либо номер без задачи.
#   M57 pr-body: 404 номера — снова отказ кодом 2 (не ловится)            → check-01
#   M58 pr-body: задача другого репозитория — голым #N                   → check-01
#   M59 pr-body: номер нескольких репозиториев — первым кандидатом       → check-01
#   M60 pr-body: отказ чтения кандидата (не 404) — «нет нигде»           → check-01
#   M61 pr-body: задача другого репозитория с доказательством — Closes   → check-01
#   M62 gh: 404 не отличён от отказа (признак слеп)                      → check-01
#   M63 gh: любой отказ — 404 (признак слеп к статусу)      → check-01
#   M63b pr-body: номер полной формы своего репозитория — ищется в других → check-01
#   близнец T1: статус 404 сверен иной записью — check-01 зелен
#
# ws#1162: привязка ревизии доказательства к диапазону — одна, `dod_proof_bound` общего
# `scripts/lib/dod_proof.jq`; три судьи (merge-readiness, landing-precheck (ж), генератор)
# обязаны на одном PR дать один исход — check-05 гонит их НАСТОЯЩИМИ скриптами копии.
#   M69 dod_proof.jq: привязка снята — любая ревизия привязана            → check-05, check-01
#   M70 merge-readiness: судит распознанное, а не привязанное (прежнее)   → check-05
#   M71 landing-precheck (ж): привязка не спрошена                       → check-05
#   M72 pr-body: флаг привязки не читается                               → check-05, check-01
#   M73 dod_proof.jq: привязка — по началу sha ГОЛОВЫ, а не диапазона     → check-05
#   близнец T2: привязка записана иначе (срез вместо startswith) — check-05 и check-01 зелены
#
# ws#1320: работа доказательства откачена в диапазоне (`Reverts`) — Refs, не Closes; раздел
# неисполненного в комментарии-доказательстве — частичное.
#   M74 pr-body: откат не судится                                        → check-01
#   M75 Reverts: откат без строки git не виден (patch-id снят)           → check-01
#   M76 Reverts: строка git `This reverts commit` не читается            → check-01
#   M77 Reverts: откат отката не снимает отката                          → check-01
#   M78 Reverts: внесение заново тем же диффом не снимает отката         → check-01
#   M79 Reverts: единица — лишь коммит доказательства, без слияния полосы → check-01
#   M80 dod_proof.jq: раздел неисполненного не судится                   → check-01, check-05
#   M81 Reverts: внесённое заново, но откаченное следом, снимает откат    → check-01
#   (M78 ловит случай #77: откат с правкой по строке git — внесённое заново откатом отката по
#   patch-id не видно; при откате тем же диффом внесение заново — и откат отката, M78 там слеп.)
# ws#1320 (в): решает ПОСЛЕДНЕЕ доказательство диапазона (`dod_proof_closes_in`) у троих судей Closes.
#   M82 pr-body: последнее частичное не судится                          → check-01, check-05
#   M83 dod_proof.jq: последнее — лишь из полных (прежнее «любое полное»)  → check-01, check-05
#   M84 merge-readiness: любое привязанное полное (прежнее)              → check-05
#   M85 landing-precheck (ж): любое привязанное полное (прежнее)         → check-05
# ws#1324: без диапазона решает последнее доказательство задачи (`dod_proof_last`) — close-wave, trail.
#   M86 close-wave: последнее — лишь из полных (прежнее)                 → check-02
#   M87 dod_proof.jq: `dod_proof_last` — лишь из полных                   → check-02
# ws#1320, возврат check-verifier: раздел неисполненного — по КЛАССУ начала строки и перечню
# слов-исходов, выведенному переписью (`_dod_unmet_line`); каждая часть краснит свой случай check-06,
# нумерованный пункт ws#1225 — и генератор тела конец в конец (check-01).
#   M88 нумерованный «N.» не допущен                                    → check-06, check-01
#   M89 нумерованный «N)» не допущен                                    → check-06
#   M90 флажок задачи «[ ]» не допущен                                  → check-06
#   M91 отступ перед маркером не допущен                                → check-06
#   M92 знак, заголовок и выделение перед словом — лишь `**` (прежнее)   → check-06
#   M93 выделение сразу после «Не» не допущено                          → check-06
#   M94 регистр не сводится (флаг снят)                                 → check-06
#   M95 слово-исход снято из перечня — мутант на каждое слово           → check-06
#   M96 цитата `>` — раздел                                             → check-06
#   M97 ячейка таблицы `|` — раздел                                     → check-06
#   M98 фрагмент кода в начале строки — раздел                          → check-06
#   M99 любое слово — исход (граница зелёного стала разделом)           → check-06
#   M100 «не требуется» не снимает раздела                              → check-06
#   близнец T4: перечень слов записан одной строкой — check-06 зелена
#
# Хранилище для check-04 берётся из HEAD настоящего воркспейса (`RITUALS_WS`):
# копия несёт только код ритуалов и их общие зависимости.
# Коды: 0 — все доказательства прошли и покрытие плана полное; 1 — хоть одно нет либо
# покрытие неполно; 2 — копию не завести.
# shellcheck source-path=SCRIPTDIR

# ИСПОЛНЕНИЕ (ws#1337): случаи (контроль, мутант, близнец) сначала ЗАПИСЫВАЮТСЯ планом —
# каталог на случай под номером, — затем гонятся параллельно, RITUALS_INJECT_JOBS
# исполнителей (по умолчанию nproc, не больше 8: память — каждая самопроба check-01 строит
# свои песочницы git). Каждый случай — своя копия каталога и свой mktemp пробы, общего
# состояния у случаев нет. Прежде случаи шли подряд: 125 случаев, 56 из 97 исполненных —
# check-01 по 18,2 с в среднем; задание `rituals` снято пределом 20 мин на 97-м (прогон
# 39777966207, задание 119821638471, ws#1337).
# ПОКРЫТИЕ — СУДОМ, А НЕ ДОВЕРИЕМ ИСПОЛНИТЕЛЮ: каждому номеру плана — ровно один исход, исхода
# вне плана нет, исход разборчив (`cover` ниже); неполное покрытие — код 1, даже если каждый
# прочитанный исход зелен. Судья покрытия доказан до прогона синтетикой в обе стороны.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)" || { echo "[VOID] rituals/inject — не завёлся каталог" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

# Унаследованный указатель корня (`GATE_ROOT`, `*_GATE_ROOT`) сильнее расположения
# копии: самопроба мутанта судила бы не мутанта. Снимается до первой пробы.
# shellcheck source=../lib/proofs.sh
. "$ws/scripts/lib/proofs.sh"
proof_own_environment

n_cpu="$(nproc 2>/dev/null || echo 4)"
[ "$n_cpu" -le 8 ] 2>/dev/null || n_cpu=8
jobs="${RITUALS_INJECT_JOBS:-$n_cpu}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "[VOID] rituals/inject — RITUALS_INJECT_JOBS «$jobs» не число" >&2; exit 2; }

copy() {
    local d="$tmp/$1"
    mkdir -p "$d/scripts/hooks" "$d/scripts/lib" || return 2
    cp -r "$here" "$d/scripts/rituals" || return 2
    cp "$ws/scripts/pr-body.sh" "$ws/scripts/ci-read-expected.tsv" "$ws/scripts/merge-readiness.sh" \
        "$ws/scripts/landing-precheck.sh" "$d/scripts/" || return 2
    cp "$ws/scripts/lib/ws-home.sh" "$d/scripts/lib/" || return 2
    cp "$ws/scripts/hooks/attribution-rule.sh" "$d/scripts/hooks/" || return 2
    cp "$ws/scripts/lib/sandbox-git-home.sh" "$ws/scripts/lib/gate_root.py" "$ws/scripts/lib/dod_proof.jq" \
        "$ws/scripts/lib/gh-rate.sh" "$d/scripts/lib/" || return 2
    printf '%s' "$d/scripts/rituals"
}

# mutate <файл> <файл якоря> <файл замены> — ровно одно вхождение якоря, иначе отказ.
# Якорь и замена читаются файлами плана байт в байт: подстановка `$(…)` сняла бы хвост.
mutate() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, oldf, newf = sys.argv[1:4]
old = open(oldf, encoding="utf-8").read()
new = open(newf, encoding="utf-8").read()
text = open(path, encoding="utf-8").read()
n = text.count(old)
if n != 1:
    print("якорь мутанта встречен %d раз(а), а не один: %r" % (n, old), file=sys.stderr)
    sys.exit(2)
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
}

run_check() {
    (cd "$tmp" && RITUALS_WS="$ws" python3 "$1/$2" 2>&1)
}

# План: plan_case <вид control|inject|twin> <метка> <самопроба> [<якорь> <замена> [<файл>]].
mkdir -p "$tmp/plan" "$tmp/res" || { echo "[VOID] rituals/inject — не завёлся каталог плана" >&2; exit 2; }
planned=0
plan_case() {
    local p="$tmp/plan/$planned"
    mkdir -p "$p" || { echo "[VOID] rituals/inject — не завёлся случай плана $planned" >&2; exit 2; }
    printf '%s' "$1" > "$p/kind"; printf '%s' "$2" > "$p/label"; printf '%s' "$3" > "$p/check"
    printf '%s' "${4-}" > "$p/old"; printf '%s' "${5-}" > "$p/new"; printf '%s' "${6:-rituals.py}" > "$p/file"
    planned=$((planned + 1))
}

# cell <номер> — исполнитель одного случая плана; исход — файл res/<номер>:
# первая строка «код TAB ожидаемый TAB мс TAB метка», дальше хвост вывода самопробы.
cell() {
    local i="$1" p="$tmp/plan/$1" kind label check file want d out rc t0 t1
    kind="$(cat "$p/kind")"; label="$(cat "$p/label")"; check="$(cat "$p/check")"; file="$(cat "$p/file")"
    case "$kind" in inject) want=1 ;; *) want=0 ;; esac
    t0="$(date +%s%N)"
    if ! d="$(copy "c$i")"; then
        rc=2; out=""; label="$label: копия"
    elif [ "$kind" != control ] && ! out="$(mutate "$d/$file" "$p/old" "$p/new" 2>&1)"; then
        rc=2
        if [ "$kind" = twin ]; then label="$label: близнец не применён"; else label="$label: мутант не применён"; fi
    else
        out="$(run_check "$d" "$check")"; rc=$?
    fi
    t1="$(date +%s%N)"
    rm -rf "$tmp/c$i"
    { printf '%s\t%s\t%s\t%s\n' "$rc" "$want" "$(( (t1 - t0) / 1000000 ))" "$label"
      printf '%s\n' "$out" | tail -n 15; } > "$tmp/res/$i.part" && mv "$tmp/res/$i.part" "$tmp/res/$i"
    # Ход — строкой по завершении случая, не в конце: задание, снятое пределом, оставляет
    # в журнале исполненное (одна строка короче PIPE_BUF пишется целиком).
    local v="OK]  "; [ "$rc" = "$want" ] || v="FAIL]"
    printf '[inject %s №%d %s (ожидали код %s, получили %s; %d с)\n' "$v" "$i" "$label" \
        "$want" "$rc" "$(( (t1 - t0) / 1000000000 ))"
}

# cover <каталог плана> <каталог исходов> — каждому номеру плана ровно один разборчивый
# исход, исходов вне плана нет. Печатает строку покрытия; код 0 — полное, 1 — нет.
cover() {
    local pl="$1" rs="$2" n=0 got=0 miss=() extra=() junk=() f k line
    for f in "$pl"/*; do [ -d "$f" ] && n=$((n + 1)); done
    for ((k = 0; k < n; k++)); do
        [ -d "$pl/$k" ] || { miss+=("план:$k"); continue; }
        if [ -f "$rs/$k" ]; then
            got=$((got + 1))
            # первая строка — в переменную: `head | grep -q` под pipefail дал бы 141 писателю
            IFS= read -r line < "$rs/$k" || line=""
            [[ "$line" =~ ^[0-9]+$'\t'[01]$'\t'[0-9]+$'\t' ]] || junk+=("$k")
        else
            miss+=("$k")
        fi
    done
    for f in "$rs"/*; do
        [ -e "$f" ] || continue
        k="${f##*/}"
        { [[ "$k" =~ ^[0-9]+$ ]] && [ "$k" -lt "$n" ] && [ -d "$pl/$k" ]; } || extra+=("$k")
    done
    echo "покрытие: исходов $got из $n случаев плана · без исхода ${#miss[@]} · вне плана ${#extra[@]} · неразборчивых ${#junk[@]}"
    [ "${#miss[@]}" -eq 0 ] || echo "    без исхода: ${miss[*]}"
    [ "${#extra[@]}" -eq 0 ] || echo "    вне плана: ${extra[*]}"
    [ "${#junk[@]}" -eq 0 ] || echo "    неразборчивы: ${junk[*]}"
    [ "$n" -gt 0 ] && [ "$got" -eq "$n" ] && [ "${#miss[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ] && [ "${#junk[@]}" -eq 0 ]
}

# Доказательство судьи покрытия — синтетикой, до прогона (обе стороны): полное покрытие
# молчит, пропуск, исход вне плана, неразборчивый исход и пустой план краснеют.
cover_case() {
    local label="$1" want="$2" n="$3" s="$tmp/cover-$4" k out rc
    mkdir -p "$s/plan" "$s/res"
    for ((k = 0; k < n; k++)); do mkdir -p "$s/plan/$k"; printf '0\t0\t1\tx\n' > "$s/res/$k"; done
    case "$4" in
        miss) rm -f "$s/res/1" ;;
        extra) printf '0\t0\t1\tx\n' > "$s/res/$n" ;;
        junk) printf 'не исход\n' > "$s/res/0" ;;
    esac
    out="$(cover "$s/plan" "$s/res")"; rc=$?
    if [ "$rc" = "$want" ]; then
        echo "[cover OK]    $label (ожидали код $want, получили $rc)"
    else
        echo "[cover FAIL]  $label (ожидали код $want, получили $rc): $out" >&2
        cover_bad=$((cover_bad + 1))
    fi
}
cover_bad=0
cover_case "покрытие полное — молчит" 0 3 full
cover_case "случай без исхода — красное" 1 3 miss
cover_case "исход вне плана — красное" 1 3 extra
cover_case "неразборчивый исход — красное" 1 3 junk
cover_case "пустой план — красное" 1 0 empty

# Предпосылка: копия заводится — иначе каждый случай краснел бы чужой причиной.
copy probe >/dev/null || { echo "[VOID] rituals/inject — копия не заведена" >&2; exit 2; }
rm -rf "$tmp/probe"

# контроль: копия без мутации зелена по всем самопробам
for c in check-01-pr-body.py check-02-close-wave.py check-03-approval-event.py check-04-vault-trails.py \
         check-05-dod-judges-agree.py check-06-dod-unmet-forms.py; do
    plan_case control "контроль $c" "$c"
done

# inject <метка> <самопроба> <якорь> <замена> [<файл относительно копии scripts/rituals>]
inject() { plan_case inject "$@"; }

# twin <метка> <самопроба> <якорь> <замена> [<файл>] — то же решение другой записью:
# самопроба обязана остаться зелёной (код 0), иначе она судит запись, а не решение.
twin() { plan_case twin "$@"; }

inject "M1 pr-body: Closes без доказательства" check-01-pr-body.py \
    '        inside = [(u, r) for u, r, bound in proofs if bound]' \
    '        inside = [(u, r) for u, r, _ in proofs] or [("(нет)", "0000000")]'
inject "M2 pr-body: атрибуция не видна" check-01-pr-body.py \
    'return p.stdout.strip() or "(пустая строка)"' \
    'return None'
inject "M3 close-wave: остаток закрыт без доказательства" check-02-close-wave.py \
    '(to_close if proof else remainder).append((c, proof))' \
    'to_close.append((c, proof or ("(нет)", "0000000")))'
inject "M4 approval-event: событие без правки блока" check-03-approval-event.py \
    '            fh.write(after)' \
    '            fh.write(before)'
inject "M5 approval-event: публикация до проверки записываемости" check-03-approval-event.py \
    'if not os.access(rec_path, os.W_OK):' \
    'if False:'
inject "M6 vault-trails: закрытая задача не done" check-04-vault-trails.py \
    'status = "wontfix" if it.get("state_reason") == "not_planned" else "done"' \
    'status = "test"'
inject "M7 vault-trails: исход vault-gate проглочен" check-04-vault-trails.py \
    'return gate.returncode if gate.returncode in (OK, REFUSED, UNMET) else REFUSED' \
    'return OK if gate.returncode == REFUSED else gate.returncode'
inject "M8 approval-event: отпечаток не сверяется" check-03-approval-event.py \
    '    if got != want:' \
    '    if False:'
inject "M9 approval-event: повтор не запрещён" check-03-approval-event.py \
    'if ev.get("status") == "performed" or ev.get("published") is True:' \
    'if False:'
inject "M10 close-wave: перечитывание слепо" check-02-close-wave.py \
    'still = [c for c in after if c.get("state") == "open"]' \
    'still = []'
inject "M11 pr-body: закрытая с доказательством — Closes" check-01-pr-body.py \
    '        if it.get("state") != "open":' \
    '        if False:'
inject "M12 approval-event: документ записи не сверяется" check-03-approval-event.py \
    'if subj.get("path") and subj["path"] != doc:' \
    'if False:'
inject "M13 vault-trails: код генератора проглочен" check-04-vault-trails.py \
    'if gen.returncode != 0:' \
    'if False:'
inject "M14 approval-event: задевшая другие поля правка принята" check-03-approval-event.py \
    'if drop(check) != drop(rec):' \
    'if False:'
inject "M15 approval-event: значение ответа трекера без кавычек" check-03-approval-event.py \
    '"  api_url: %s" % q(posted.get("url") or ""),' \
    '"  api_url: %s" % (posted.get("url") or ""),'
inject "M16 approval-event: тип отпечатка не судится" check-03-approval-event.py \
    'if not isinstance(want, str) or not SHA256_RE.match(want):' \
    'if False:'
inject "M17 approval-event: правка не проверена до публикации" check-03-approval-event.py \
    '        raise Refused("%s — событие не публикуется" % e)' \
    '        pass'
inject "M18 dod_proof.jq: маркер посреди прозы засчитан" check-01-pr-body.py \
    '_dod_mark_re: "^(' \
    '_dod_mark_re: "(' \
    ../lib/dod_proof.jq
inject "M19 approval-event: нет verdict/reviewer_role — не судится" check-03-approval-event.py \
    '    if not verdict or not role or want is None:' \
    '    if want is None:'
inject "M20 pr-body: атрибуция в собранном теле не судится" check-01-pr-body.py \
    '    line = attribution(body)
    if line:
        raise Refused("атрибуция в собранном теле' \
    '    line = None
    if line:
        raise Refused("атрибуция в собранном теле'
inject "M21 dod_proof.jq: ревизия любого вида" check-01-pr-body.py \
    '[0-9a-f]{7,40}' \
    '[0-9A-Za-z]{1,40}' \
    ../lib/dod_proof.jq
inject "M22 dod_proof: первое доказательство вместо последнего" check-04-vault-trails.py \
    'dod_proof_marks[] | .+{url: $u}] | last;' 'dod_proof_marks[] | .+{url: $u}] | first;' ../lib/dod_proof.jq
inject "M23 gh_list: только первая страница (pr-body)" check-01-pr-body.py \
    '        if len(chunk) < 100:' '        if True:'
inject "M24 gh_list: только первая страница (close-wave)" check-02-close-wave.py \
    '        if len(chunk) < 100:' '        if True:'
inject "M25 gh_list: только первая страница (vault-trails)" check-04-vault-trails.py \
    '        if len(chunk) < 100:' '        if True:'
inject "M30 approval-event: префикс номера ветки снят" check-03-approval-event.py \
    'head = "#%d " % task' 'head = ""'
inject "M31 approval-event: граница номера ветки снята" check-03-approval-event.py \
    'r"^([1-9][0-9]*)(?:-|$)"' 'r"^([0-9]+)"'
inject "M32 approval-event: номер из задачи-держателя" check-03-approval-event.py \
    'head = "#%d " % task' 'head = "#%d " % hnum'
inject "M33 approval-event: отсоединённая голова не судится" check-03-approval-event.py \
    'if p.returncode != 0 or not branch:' 'if False:'
inject "M34 approval-event: номер — последнее число ветки" check-03-approval-event.py \
    '    return int(m.group(1))' '    return int(re.findall(r"[0-9]+", branch)[-1])'
inject "M35 approval-event: ветка из cwd, RITUAL_REPO_DIR пропущен" check-03-approval-event.py \
    '["git", "-C", os.environ.get("RITUAL_REPO_DIR") or os.getcwd(), "symbolic-ref"' \
    '["git", "-C", os.getcwd(), "symbolic-ref"'
inject "M36 pr-body: доказательство вне диапазона засчитано" check-01-pr-body.py \
    '        inside = [(u, r) for u, r, bound in proofs if bound]' \
    '        inside = [(u, r) for u, r, bound in proofs]'
inject "M37 pr-body: держатель записи долга не судится" check-01-pr-body.py \
    '        holder = debt_holder(repo, n, ledgers)' \
    '        holder = None'
inject "M38 pr-body: форма держателя снята" check-01-pr-body.py \
    'rx = re.compile(form.replace("{ref}", task_ref_re(trepo, n, lrepo)).replace("{n}", str(n)))' \
    'rx = re.compile(task_ref_re(trepo, n, lrepo))'
inject "M39 pr-body: упомянутые — с #" check-01-pr-body.py \
    '", ".join(str(n) for n in sorted(mentioned))' \
    '", ".join("#%d" % n for n in sorted(mentioned))'
inject "M40 pr-body: заголовок задачи без замены #N" check-01-pr-body.py \
    '        title = no_hash(it.get("title") or "")' \
    '        title = it.get("title") or ""'
inject "M41 pr-body: первая строка — первый абзац" check-01-pr-body.py \
    '    return (msg.split("\n", 1)[0] if msg else "").rstrip("\r")' \
    '    return " ".join(msg.split("\n\n", 1)[0].splitlines()) if msg else ""'
inject "M42 pr-body: Closes перед Refs" check-01-pr-body.py \
    '    tail = ["Refs %s" % label(n) for n in refs] + ["Closes %s" % label(n) for n in closes]' \
    '    tail = ["Closes %s" % label(n) for n in closes] + ["Refs %s" % label(n) for n in refs]'
inject "M43 pr-body: снятая ведомость не судится" check-01-pr-body.py \
    '        if not files and lrepo == trepo:' \
    '        if False:'
inject "M44 pr-body: вложенные полосы не раскрыты" check-01-pr-body.py \
    '            subs.append(lanes(p, excl + seen, meta))' \
    '            subs.append([])'
inject "M45 pr-body: первое доказательство диапазона" check-01-pr-body.py \
    '            url, rev = inside[-1]' \
    '            url, rev = inside[0]'
inject "M46 pr-body: номера из всего сообщения" check-01-pr-body.py \
    'NUM_RE.findall(meta[h][2])}' \
    'NUM_RE.findall(msgs[h])}'
inject "M47 pr-body: полная форма — голым #N" check-01-pr-body.py \
    '        return "#%d" % n if n in first and n not in home else "%s#%d" % (home.get(n, repo), n)' \
    '        return "#%d" % n'
inject "M48 pr-body: полная форма — не задача" check-01-pr-body.py \
    '    for n in sorted(first | qual):' \
    '    for n in sorted(first):'
inject "M49 правило ссылки: «/» снят перед краткой формой — чужой владелец засчитан своим" check-01-pr-body.py \
    'r"(?<![\w./-])(?i:%s)#" % name' \
    'r"(?<![\w.-])(?i:%s)#" % name'
inject "M64 правило ссылки: регистр владельца в адресе различается" check-01-pr-body.py \
    'r"(?<![\w.-])(?i:github\.com/%s/%s)/issues/" % (owner, name)' \
    'r"(?<![\w.-])(?:github\.com/%s/%s)/issues/" % (owner, name)'
inject "M65 правило ссылки: регистр полной формы различается" check-01-pr-body.py \
    'r"(?<![\w.-])(?i:%s/%s)#" % (owner, name)' \
    'r"(?<![\w.-])(?:%s/%s)#" % (owner, name)'
inject "M66 правило ссылки: голый номер и в чужой ведомости" check-01-pr-body.py \
    'return task_ref_pattern(trepo, n, bare=trepo.lower() == lrepo.lower())' \
    'return task_ref_pattern(trepo, n)'
inject "M67 правило ссылки: хвост номера — только не цифра" check-01-pr-body.py \
    'r"(?:%s)(%s)(?!\w)"' 'r"(?:%s)(%s)(?![0-9])"'
inject "M68 правило ссылки: issue_refs своим выражением (прежнее)" check-01-pr-body.py \
    '    return {int(m.group(1)) for m in re.finditer(task_ref_pattern(repo), text)}' \
    '    return {int(m.group(1)) for m in re.finditer(r"(?<![\w/])#(\d+)\b|(?<![\w./-])%s#(\d+)\b" % re.escape(repo.split("/")[1]), text) if m.group(1)}'
twin "T3 правило ссылки: граница краткой формы — тот же класс иной записью" check-01-pr-body.py \
    'r"(?<![\w./-])(?i:%s)#" % name' \
    'r"(?<![\w/.\-])(?i:%s)#" % name'
inject "M50 pr-body: догон не распознан" check-01-pr-body.py \
    '    return bool(side) and all(is_ancestor(p, base) for p in side)' \
    '    return False'
inject "M53 pr-body: любое слияние — догон" check-01-pr-body.py \
    '    return bool(side) and all(is_ancestor(p, base) for p in side)' \
    '    return bool(side)'
inject "M54 pr-body: достижимость от головы" check-01-pr-body.py \
    'catch_up(parents, base_sha)' \
    'catch_up(parents, head_sha)'
inject "M55 pr-body: префикс догона отброшен" check-01-pr-body.py \
    '    head = m.group(0) if m else ""' \
    '    head = ""'
inject "M56 pr-body: префикс догона не в задачах" check-01-pr-body.py \
    '    return head + no_hash(line[len(head):]), head, head' \
    '    return head + no_hash(line[len(head):]), "", head'
inject "M51 pr-body: строка слияния ствола с #N" check-01-pr-body.py \
    '    return head + no_hash(line[len(head):]), head, head' \
    '    return line, head, head'
inject "M52 pr-body: доказательство лишь на голове" check-01-pr-body.py \
    '        proofs = dod_proofs(repo, n, range_shas)' \
    '        proofs = dod_proofs(repo, n, [head_sha])'
inject "M57 pr-body: 404 номера — снова отказ" check-01-pr-body.py \
    '            it = issue(repo, n)
        except NotFound:' \
    '            it = issue(repo, n)
        except ZeroDivisionError:'
inject "M58 pr-body: другой репозиторий — голым #N" check-01-pr-body.py \
    'return "#%d" % n if n in first and n not in home else' \
    'return "#%d" % n if n in first else'
inject "M59 pr-body: несколько репозиториев — первый" check-01-pr-body.py \
    '            if len(hits) == 1:' '            if hits:'
inject "M60 pr-body: отказ чтения кандидата — «нет нигде»" check-01-pr-body.py \
    '                except NotFound:
                    continue' \
    '                except Unmet:
                    continue'
inject "M61 pr-body: другой репозиторий с доказательством — Closes" check-01-pr-body.py \
    '                home[n], got = hits[0]
                refs.append(n)' \
    '                home[n], got = hits[0]
                closes.append(n)'
inject "M62 gh: 404 не отличён" check-01-pr-body.py \
    'if isinstance(got, dict) and got.get("message") == "Not Found" and str(got.get("status")) == "404":' \
    'if False:'
inject "M63 gh: любой отказ — 404" check-01-pr-body.py \
    'if isinstance(got, dict) and got.get("message") == "Not Found" and str(got.get("status")) == "404":' \
    'if isinstance(got, dict) or True:'
inject "M63b pr-body: полная форма своего — ищется в других" check-01-pr-body.py \
    '            if n in qual:
                orphans[n]' \
    '            if False:
                orphans[n]'
twin "T1 gh: статус 404 сверен иной записью" check-01-pr-body.py \
    'str(got.get("status")) == "404":' \
    'got.get("status") in ("404", 404):'
inject "M69 dod_proof.jq: привязка снята" check-05-dod-judges-agree.py \
    'def dod_proof_bound($range): . as $rev | any($range[]; startswith($rev));' \
    'def dod_proof_bound($range): true;' ../lib/dod_proof.jq
inject "M69 dod_proof.jq: привязка снята (генератор)" check-01-pr-body.py \
    'def dod_proof_bound($range): . as $rev | any($range[]; startswith($rev));' \
    'def dod_proof_bound($range): true;' ../lib/dod_proof.jq
inject "M70 merge-readiness: распознанное вместо привязанного" check-05-dod-judges-agree.py \
    "add // [] | dod_proof_closes_in(\$range)'" \
    "add // [] | any(.[]; (.body // \"\") | dod_proof)'" ../merge-readiness.sh
inject "M71 landing-precheck (ж): привязка не спрошена" check-05-dod-judges-agree.py \
    '(dod_proof_bound($range) | tostring)' '("true")' ../landing-precheck.sh
inject "M72 pr-body: флаг привязки не читается" check-05-dod-judges-agree.py \
    '        inside = [(u, r) for u, r, bound in proofs if bound]' \
    '        inside = [(u, r) for u, r, bound in proofs]'
inject "M73 dod_proof.jq: привязка по голове" check-05-dod-judges-agree.py \
    'def dod_proof_bound($range): . as $rev | any($range[]; startswith($rev));' \
    'def dod_proof_bound($range): . as $rev | ($range | last // "") | startswith($rev);' ../lib/dod_proof.jq
inject "M74 pr-body: откат не судится" check-01-pr-body.py \
    '            undone = reverts.undone(full)' '            undone = None'
inject "M75 Reverts: patch-id снят" check-01-pr-body.py \
    '            cands = set(by_fwd.get(rev.get(c, ""), []))' '            cands = set()'
inject "M76 Reverts: строка git не читается" check-01-pr-body.py \
    '            for m in REVERTS_RE.finditer(self.msgs[c]):' '            for m in []:'
inject "M77 Reverts: откат отката не снимает отката" check-01-pr-body.py \
    '            if self._stands(c) and not again:' '            if not again:'
inject "M78 Reverts: внесение заново не снимает отката" check-01-pr-body.py \
    '            if self._stands(c) and not again:' '            if self._stands(c):'
inject "M81 Reverts: внесённое заново не судится на откат" check-01-pr-body.py \
    'if d not in (x, c) and is_ancestor(c, d) and self._stands(d)]' 'if d not in (x, c) and is_ancestor(c, d)]'
inject "M79 Reverts: единица — лишь коммит доказательства" check-01-pr-body.py \
    '            if x == rev or (len(parents) > 1' '            if x == rev or (False'
for c in check-01-pr-body.py check-05-dod-judges-agree.py; do
    inject "M82 pr-body: последнее частичное не судится ($c)" "$c" \
        '        if inside and last and last.get("partial"):' '        if False:'
    inject "M83 dod_proof.jq: последнее — лишь из полных ($c)" "$c" \
        'dod_proof_marks[] | select(.rev | dod_proof_bound($range))] | last;' \
        'dod_proof_marks[] | select(.partial | not) | select(.rev | dod_proof_bound($range))] | last;' ../lib/dod_proof.jq
done
inject "M84 merge-readiness: любое привязанное полное" check-05-dod-judges-agree.py \
    "add // [] | dod_proof_closes_in(\$range)'" \
    "add // [] | any(.[]; (.body // \"\") | dod_proof_revisions_in(\$range) | length > 0)'" ../merge-readiness.sh
inject "M85 landing-precheck (ж): любое привязанное полное" check-05-dod-judges-agree.py \
    '    if bound and bound[-1][2] == "false":' \
    '    if any(m[1] == "true" for m in full):' ../landing-precheck.sh
inject "M86 close-wave: последнее — лишь из полных (прежнее «любое полное»)" check-02-close-wave.py \
    "head='include \"dod_proof\"; dod_proof_last'" \
    "head='include \"dod_proof\"; [.[] | (.html_url // \"\") as \$u | (.body // \"\") | dod_proof_marks[] | select(.partial | not) | .+{url: \$u}] | last'"
inject "M87 dod_proof.jq: последнее без диапазона — лишь из полных" check-02-close-wave.py \
    'dod_proof_marks[] | .+{url: $u}] | last;' 'dod_proof_marks[] | select(.partial | not) | .+{url: $u}] | last;' ../lib/dod_proof.jq
for c in check-01-pr-body.py check-05-dod-judges-agree.py; do
    inject "M80 dod_proof.jq: раздел неисполненного не судится ($c)" "$c" \
        '  | any($l[]; _dod_unmet_line) as $unmet' '  | false as $unmet' ../lib/dod_proof.jq
done
U='../lib/dod_proof.jq'
for c in check-06-dod-unmet-forms.py check-01-pr-body.py; do
    inject "M88 dod_proof.jq: нумерованный «N.» не допущен ($c)" "$c" '[.)]' '[)]' "$U"
done
inject "M89 dod_proof.jq: нумерованный «N)» не допущен" check-06-dod-unmet-forms.py '[.)]' '[.]' "$U"
inject "M90 dod_proof.jq: флажок задачи не допущен" check-06-dod-unmet-forms.py '(?:\\[[ x]\\][ \t]+)?' '' "$U"
inject "M91 dod_proof.jq: отступ перед маркером не допущен" check-06-dod-unmet-forms.py \
    '"^[ \t]*(?:(?:' '"^(?:(?:' "$U"
inject "M92 dod_proof.jq: перед словом лишь **" check-06-dod-unmet-forms.py \
    '[^\\p{L}\\p{N}\\s`|>\\\\]{1,6}' '[*]{2}' "$U"
inject "M93 dod_proof.jq: выделение после «Не» не допущено" check-06-dod-unmet-forms.py \
    'не(?:[*_]{1,2})?[ \t]+' 'не[ \t]+' "$U"
inject "M94 dod_proof.jq: регистр не сводится" check-06-dod-unmet-forms.py \
    '(_dod_unmet_stems | join("|")) + ")"; "i")' '(_dod_unmet_stems | join("|")) + ")")' "$U"
for s in сошл исполн выполн сдела доказа пройд покры закры почин; do
    inject "M95 dod_proof.jq: слово-исход «$s» снято" check-06-dod-unmet-forms.py "\"$s\"" '"(?!)"' "$U"
done
inject "M96 dod_proof.jq: цитата — раздел" check-06-dod-unmet-forms.py '`|>' '`|' "$U"
inject "M97 dod_proof.jq: ячейка таблицы — раздел" check-06-dod-unmet-forms.py '`|>' '`>' "$U"
inject "M98 dod_proof.jq: фрагмент кода в начале — раздел" check-06-dod-unmet-forms.py '`|>' '|>' "$U"
inject "M99 dod_proof.jq: любое слово — исход" check-06-dod-unmet-forms.py \
    '(_dod_unmet_stems | join("|"))' '"\\p{L}"' "$U"
inject "M100 dod_proof.jq: «не требуется» не снимает раздела" check-06-dod-unmet-forms.py \
    '  and (test("не требуется"; "i") | not);' '  ;' "$U"
twin "T4 dod_proof.jq: перечень слов одной строкой" check-06-dod-unmet-forms.py \
    '(_dod_unmet_stems | join("|"))' '"сошл|исполн|выполн|сдела|доказа|пройд|покры|закры|почин"' "$U"
for c in check-05-dod-judges-agree.py check-01-pr-body.py; do
    twin "T2 dod_proof.jq: привязка срезом ($c)" "$c" \
        'any($range[]; startswith($rev))' 'any($range[]; .[0:($rev | length)] == $rev)' ../lib/dod_proof.jq
done
for c in check-01-pr-body.py check-02-close-wave.py; do
    inject "M26–M27 dod_proof.jq: ревизия из [0-9a-z] ($c)" "$c" \
        '[0-9a-f]{7,40}' '[0-9a-z]{7,40}' ../lib/dod_proof.jq
    inject "M28–M29 dod_proof.jq: маркер без @ ($c)" "$c" \
        'DoD-proof @(?<rev>' 'DoD-proof ?@?(?<rev>' ../lib/dod_proof.jq
done

export -f copy mutate run_check cell
export here ws tmp
t_run0="$(date +%s)"
# Очередь — долгие первыми (check-01 — 18,2 с случай против 0,1–7,5 с прочих, прогон
# 39777966207): короткие добирают хвост, последний исполнитель не стоит один на долгом.
for ((i = 0; i < planned; i++)); do
    if [ "$(cat "$tmp/plan/$i/check")" = check-01-pr-body.py ]; then echo "$i"; fi
done > "$tmp/queue"
for ((i = 0; i < planned; i++)); do
    if [ "$(cat "$tmp/plan/$i/check")" != check-01-pr-body.py ]; then echo "$i"; fi
done >> "$tmp/queue"
xargs -P "$jobs" -I{} bash -c 'cell "$1"' _ {} < "$tmp/queue"
t_run1="$(date +%s)"

# Итог — по плану, в его порядке: строки хода выше идут в порядке завершения; провал
# повторяется здесь с хвостом вывода самопробы.
ok=0; bad=0
for ((i = 0; i < planned; i++)); do
    [ -f "$tmp/res/$i" ] || continue
    IFS=$'\t' read -r got want ms label < "$tmp/res/$i"
    if [ "$got" = "$want" ]; then
        ok=$((ok + 1))
    else
        echo "[inject FAIL] №$i $label (ожидали код $want, получили $got; $((ms / 1000)) с)" >&2
        tail -n +2 "$tmp/res/$i" | sed 's/^/    /' >&2
        bad=$((bad + 1))
    fi
done
covered=0; cover_out="$(cover "$tmp/plan" "$tmp/res")" && covered=1
echo
echo "$cover_out"
echo "rituals/inject: доказательств $planned, прошло $ok, провалено $bad; исполнителей $jobs, $((t_run1 - t_run0)) с; судья покрытия: провалено $cover_bad из 5"
[ "$bad" -eq 0 ] && [ "$covered" -eq 1 ] && [ "$cover_bad" -eq 0 ]
