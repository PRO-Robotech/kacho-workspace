#!/usr/bin/env bash
# check-10 — СТРАЖ МОНИТОРА ФЛОУ заговаривает на своих признаках и молчит на
# законных близнецах.
#
# ЧТО УТВЕРЖДАЕТ. `.claude/hooks/wave-monitor.sh` — страж, а не проза: он обязан
# печатать сигнал ровно тогда, когда предмет открыт, и молчать, когда закрыт.
# Проверяется ПОВЕДЕНИЕ: рядом с хуком кладутся ведомость волн, база модели
# исполнения и транскрипт с ЗАДАННЫМ содержимым, и читается то, что хук напечатал
# и каким кодом вышел.
#
# ПОЧЕМУ ПОВЕДЕНЧЕСКАЯ, А НЕ ТЕКСТОВАЯ. Искать в исходнике `if [ "$monitor" =` —
# значит ловить форму: хук волен считать строки awk'ом, вынести разбор в функцию,
# переименовать переменную. Текст сигнала тоже не закрепляется дословно: он
# переписывается вместе с нормой, и проверка на фразу покраснела бы на исправном
# страже — такую отключают первой. Закрепляются ДВА РАЗЛИЧИМЫХ ИСХОДА: «находка»
# и «осмотреть было нечем», и то, что второй не выдаётся за первый.
#
# ОСИ — ТРИ, И У КАЖДОЙ СВОЙ ЗАКОННЫЙ БЛИЗНЕЦ (`testing.md` §«Гейт на класс», п.2):
#
#   ось 1  строка ведомости открыта (поле «монитор» = «—»)     → сигнал
#          та же строка закрыта                                 → молчание
#   ось 2  посадок после курсора ≥ 4 при закрытой ведомости      → сигнал
#          посадок 1 — одна посадка самой полосы монитора        → молчание
#   ось 3  базовая модель ≠ модели транскрипта                   → сигнал
#          моделей в транскрипте больше одной                    → сигнал
#          базовая модель не записана                            → сигнал
#          базовая совпала, модель одна                          → молчание
#
# КАЖДАЯ ИНЪЕКЦИЯ МЕНЯЕТ РОВНО ОДИН ФАКТ против контрольной фикстуры — иначе
# неизвестно, который из двух дал сигнал, и вердикт недействителен, оставаясь на
# вид зелёным (`change-graph.md` §6).
#
# ТРЕТЬЯ КАТЕГОРИЯ ПРОВЕРЯЕТСЯ ОТДЕЛЬНО. Нет транскрипта, нет ведомости — это
# «не проверяли», а не «чисто» и не находка. Хук обязан сказать это ДРУГОЙ
# строкой; совпади они, молчание монитора читалось бы как отработавший монитор.
#
# ХУК НЕ РОНЯЕТ СЕССИЮ. Код выхода 0 требуется в КАЖДОЙ пробе, включая те, где
# сигнал печатается: это указатель, а не гейт, и ненулевой код оборвал бы
# обращение к сессии.
#
# ПРЕДПОСЫЛКА (исход VOID, а не успех): хук есть в дереве, есть python3 (без него
# третья ось не разбирается вовсе), и на контрольной фикстуре хук МОЛЧИТ. Страж,
# кричащий на закрытом предмете, к остальным пробам непригоден — они прошли бы на
# нём тождественно и не доказали бы ничего.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-10-wave-monitor-fires-on-its-triggers"
HOOK_REL=".claude/hooks/wave-monitor.sh"

mapfile -t HOOKS < <(tooling_gate_files "$WS" "$HOOK_REL")
if [ "${#HOOKS[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "стража $HOOK_REL в дереве нет — проверять нечего"
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    tooling_gate_void "$NAME" "python3 нет — ось модели исполнения не разбирается, вердикта по ней не будет"
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MARK_FIND="МОНИТОР ФЛОУ: предмет открыт"
MARK_UNEX="осмотреть удалось НЕ ВСЁ"

# Транскрипты фикстуры: одна модель и две. Форма записи снята с настоящего
# транскрипта (`message.model` у ассистентской записи главного потока), а не
# придумана: хук читает ровно её.
printf '%s\n' \
    '{"type":"assistant","isSidechain":false,"message":{"model":"model-alpha"}}' \
    > "$TMP/one.jsonl"
printf '%s\n' \
    '{"type":"assistant","isSidechain":false,"message":{"model":"model-beta"}}' \
    '{"type":"assistant","isSidechain":false,"message":{"model":"model-alpha"}}' \
    > "$TMP/two.jsonl"
# Посторонние записи, которые хук обязан пропускать: побочная ветвь и отметка,
# сочинённая харнессом. Без них «одна модель» доказывалось бы на входе, где
# второй модели и не предлагали.
printf '%s\n' \
    '{"type":"assistant","isSidechain":true,"message":{"model":"model-sidechain"}}' \
    '{"type":"assistant","isSidechain":false,"message":{"model":"<synthetic>"}}' \
    '{"type":"assistant","isSidechain":false,"message":{"model":"model-alpha"}}' \
    > "$TMP/noise.jsonl"

# state <каталог> <строка ведомости> <строка базы> — кладёт состояние монитора.
state() {
    local dir="$1" row="$2" base="$3"
    mkdir -p "$dir"
    # «НЕТ» — ведомости не существует вовсе: это проба третьей категории, и она
    # обязана давать ДРУГУЮ строку, а не молчание.
    rm -f "$dir/ledger.tsv"
    if [ "$row" != "НЕТ" ]; then
        {
            printf '# волна\tсведена\tствол\tполос\tмонитор\tисход\n'
            printf '%s\n' "$row"
        } > "$dir/ledger.tsv"
    fi
    {
        printf '# модель\tзамерено\tориентиры\n'
        printf '%s\n' "$base"
    } > "$dir/model-baseline.tsv"
}

# repo <каталог> <сколько коммитов> — печатает ревизию ПЕРВОГО коммита `main`.
#
# Личность задаётся ключами вызова, а не настройкой машины: на ранере её может
# не быть вовсе, и коммит бы не состоялся, оставив ось 2 без предмета молча.
# Переменные окружения git снимаются: унаследованный GIT_DIR сильнее рабочего
# каталога и увёл бы запись в ЭТУ рабочую копию.
repo() {
    local dir="$1" n="$2" i
    mkdir -p "$dir"
    (
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX
        git -C "$dir" init -q -b main
        for ((i = 0; i < n; i++)); do
            git -C "$dir" -c user.name=fixture -c user.email=fixture@invalid \
                commit -q --allow-empty -m "c$i"
        done
    ) >/dev/null 2>&1
    git -C "$dir" rev-list --max-parents=0 main
}

# probe <имя> <ждём: FIND|UNEX|SILENT> <каталог состояния> <корень> <транскрипт>
findings=0
probes=0
probe() {
    local name="$1" want="$2" st="$3" root="$4" tr="$5" out code has_find has_unex
    probes=$((probes + 1))
    out="$(
        printf '{"hook_event_name":"UserPromptSubmit","transcript_path":"%s"}' "$tr" |
        KACHO_WAVE_MONITOR_DIR="$st" CLAUDE_PROJECT_DIR="$root" \
            bash "$WS/$HOOK_REL" 2>&1
    )" && code=0 || code=$?

    if [ "$code" -ne 0 ]; then
        tooling_gate_fail "$NAME" "$name — страж вышел кодом $code: указатель обязан выходить нулём, иначе он роняет обращение к сессии"
        findings=$((findings + 1))
        return 0
    fi

    has_find=0; case "$out" in *"$MARK_FIND"*) has_find=1 ;; esac
    has_unex=0; case "$out" in *"$MARK_UNEX"*) has_unex=1 ;; esac

    case "$want" in
        FIND)
            if [ "$has_find" -ne 1 ]; then
                tooling_gate_fail "$NAME" "$name — предмет открыт, а сигнала НЕТ: страж молчит там, где обязан звать"
                findings=$((findings + 1))
            fi
            ;;
        UNEX)
            if [ "$has_unex" -ne 1 ]; then
                tooling_gate_fail "$NAME" "$name — осматривать было нечем, а строки об этом НЕТ: «не проверяли» неотличимо от «чисто»"
                findings=$((findings + 1))
            elif [ "$has_find" -eq 1 ]; then
                tooling_gate_fail "$NAME" "$name — отсутствие предмета подано как НАХОДКА: третья категория не отличена от находки"
                findings=$((findings + 1))
            fi
            ;;
        SILENT)
            if [ "$has_find" -eq 1 ] || [ "$has_unex" -eq 1 ]; then
                tooling_gate_fail "$NAME" "$name — законный близнец ЗАГОВОРИЛ: страж ловит форму, а не предмет. Напечатано: ${out%%$'\n'*}"
                findings=$((findings + 1))
            fi
            ;;
    esac
}

# ── Общий корень фикстур: репозиторий с пятью посадками на `main` ────────────
ROOT="$TMP/root"
FIRST="$(repo "$ROOT" 5 2>/dev/null || true)"
if [ -z "$FIRST" ]; then
    tooling_gate_void "$NAME" "репозиторий фикстуры не собрался — ось «строки о волне нет» осталась без предмета"
    exit 2
fi
NEAR="$(git -C "$ROOT" rev-parse 'main~1')"

ROW_CLOSED="$(printf 'w1\t2026-09-19\t%s\t6\t2026-09-19\t.claude/rules/multi-agent-flow.md §«Седьмой шаг»' "$NEAR")"
ROW_OPEN="$(printf 'w1\t2026-09-19\t%s\t6\t—\t—' "$NEAR")"
BASE_SAME="$(printf 'model-alpha\t2026-09-19\tориентиры')"
BASE_OTHER="$(printf 'model-beta\t2026-09-01\tориентиры')"
BASE_NONE="$(printf 'не-записана\t—\tориентиры')"

# ── ПРЕДПОСЫЛКА: на закрытом предмете страж молчит ───────────────────────────
state "$TMP/s0" "$ROW_CLOSED" "$BASE_SAME"
control="$(
    printf '{"hook_event_name":"UserPromptSubmit","transcript_path":"%s"}' "$TMP/one.jsonl" |
    KACHO_WAVE_MONITOR_DIR="$TMP/s0" CLAUDE_PROJECT_DIR="$ROOT" bash "$WS/$HOOK_REL" 2>&1
)" || true
if [ -n "$control" ]; then
    tooling_gate_void "$NAME" "на контрольной фикстуре страж ЗАГОВОРИЛ — остальные пробы на нём недоказательны; напечатано: ${control%%$'\n'*}"
    exit 2
fi
probes=$((probes + 1))

# ── ОСЬ 1: открытая строка ведомости ─────────────────────────────────────────
state "$TMP/s1" "$ROW_OPEN" "$BASE_SAME"
probe "ось 1: строка волны открыта (поле «монитор» = «—»)" FIND "$TMP/s1" "$ROOT" "$TMP/one.jsonl"

# ── ОСЬ 2: строки о волне нет вовсе ──────────────────────────────────────────
#
# Курсор на ПЕРВОМ коммите — после него четыре посадки, ровно нижняя граница
# вилки волны. Близнец той же формы: курсор на предпоследнем, посадка одна —
# столько даёт сама полоса монитора, и кричать на ней значит перестать читаться.
state "$TMP/s2" "$(printf 'w1\t2026-09-01\t%s\t6\t2026-09-01\tкоордината' "$FIRST")" "$BASE_SAME"
probe "ось 2: посадок после курсора 4 при закрытой ведомости" FIND "$TMP/s2" "$ROOT" "$TMP/one.jsonl"

state "$TMP/s2b" "$ROW_CLOSED" "$BASE_SAME"
probe "ось 2, близнец: посадка ОДНА — молчит" SILENT "$TMP/s2b" "$ROOT" "$TMP/one.jsonl"

# ── ОСЬ 3: модель исполнения ─────────────────────────────────────────────────
state "$TMP/s3" "$ROW_CLOSED" "$BASE_OTHER"
probe "ось 3: базовая модель ≠ модели транскрипта" FIND "$TMP/s3" "$ROOT" "$TMP/one.jsonl"

state "$TMP/s3b" "$ROW_CLOSED" "$BASE_SAME"
probe "ось 3: в одном транскрипте две модели" FIND "$TMP/s3b" "$ROOT" "$TMP/two.jsonl"

state "$TMP/s3c" "$ROW_CLOSED" "$BASE_NONE"
probe "ось 3: базовая модель не записана" FIND "$TMP/s3c" "$ROOT" "$TMP/one.jsonl"

state "$TMP/s3d" "$ROW_CLOSED" "$BASE_SAME"
probe "ось 3, близнец: побочная ветвь и синтетическая запись не считаются моделями" \
    SILENT "$TMP/s3d" "$ROOT" "$TMP/noise.jsonl"

# ── ТРЕТЬЯ КАТЕГОРИЯ: осматривать нечем ──────────────────────────────────────
state "$TMP/s4" "$ROW_CLOSED" "$BASE_SAME"
probe "нет транскрипта — «не проверяли», а не находка" UNEX "$TMP/s4" "$ROOT" "$TMP/нет-такого.jsonl"

state "$TMP/s5" "НЕТ" "$BASE_SAME"
probe "нет ведомости — «не проверяли», а не находка" UNEX "$TMP/s5" "$ROOT" "$TMP/one.jsonl"

tooling_gate_census "$NAME: стражей осмотрено ${#HOOKS[@]}; проб исполнено $probes (контроль · 3 оси · 3 законных близнеца · 2 пробы третьей категории)"

if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi

tooling_gate_pass "$NAME" "страж зовёт на каждом из своих признаков, молчит на законных близнецах и не выдаёт «не проверяли» за находку"
