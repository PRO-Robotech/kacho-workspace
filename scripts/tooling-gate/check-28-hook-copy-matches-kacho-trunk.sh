#!/usr/bin/env bash
# check-28 — файл хука, объявленный парой воркспейса и kacho, в стволе kacho
# побайтово равен копии воркспейса (ws#1288).
#
# Признак: у двух репозиториев общего кода нет, и предикат хука отправки
# (`scripts/hooks/prepush-new-commits.sh`) живёт двумя копиями — в каждом хуке
# своя. Одинаковость держалась вниманием: правка одной копии разошлась бы с другой
# молча, и хуки двух репозиториев отвечали бы на один вопрос по-разному.
#
# ПЕРЕЧЕНЬ ПАР — ИЗ ДЕРЕВА: файл воркспейса объявляет себя строкой
# «# Пара: воркспейс и PRO-Robotech/kacho, путь <путь> в обоих» (`git grep` по
# отслеживаемому). Ноль объявлений — VOID: сверять нечего, и снятие последней пары
# снимает и эту проверку.
#
# ГДЕ kacho: `scripts/lib/product_clone.py` (общий порядок наборов, сверяющих
# стволы); ревизия — `refs/remotes/origin/main` клона, `KACHO_PAIR_REF` её
# заменяет (сверка с веткой до посадки). Клона нет либо ревизия не резолвится —
# VOID.
#
# ИСХОДЫ ПО ПАРЕ:
#   в стволе kacho есть — blob равен blob'у воркспейса, иначе находка с обоими id;
#   в стволе нет, а `scripts/hooks/pre-push` ствола имя файла называет — находка
#     (хук kacho зовёт копию, которой нет);
#   в стволе нет и хук ствола о ней молчит — сторона kacho ещё не села: пара
#     считается отдельно («ждёт ствола») и в перепись идёт числом.
# ГРАНИЦА: судится только ствол kacho (не ветки), и только объявленные пары;
# копия без строки «Пара:» этой проверке не видна.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-28-hook-copy-matches-kacho-trunk"
MARK='^# Пара: воркспейс и PRO-Robotech/kacho, путь [^ ]+ в обоих'

mapfile -t declared < <(git -C "$WS" grep -l -E "$MARK" -- 'scripts/hooks/*' 2> /dev/null | sort -u)
if [ "${#declared[@]}" -eq 0 ]; then
    tooling_gate_void "$NAME" "в scripts/hooks нет ни одной строки «Пара: воркспейс и PRO-Robotech/kacho» — сверять нечего"
    exit 2
fi
clone="$(python3 "$WS/scripts/lib/product_clone.py" "$WS" kacho 2> /dev/null)" || clone=""
if [ -z "$clone" ]; then
    tooling_gate_void "$NAME" "клона kacho нет (KACHO_HOME_KACHO, KACHO_MONOREPO, project/kacho) — сверять не с чем"
    exit 2
fi
ref="${KACHO_PAIR_REF:-refs/remotes/origin/main}"
rev="$(git -C "$clone" rev-parse --verify -q "$ref^{commit}")" || {
    tooling_gate_void "$NAME" "ревизия «$ref» в клоне kacho не резолвится — сверять не с чем"
    exit 2
}

findings=0 equal=0 pending=0
for f in "${declared[@]}"; do
    path="$(grep -m1 -oE "$MARK" "$WS/$f" | sed -E 's/.*путь ([^ ]+) в обоих.*/\1/')"
    if [ "$path" != "$f" ]; then
        tooling_gate_fail "$NAME" "$f объявляет путь «$path» — пара обязана лежать по одному пути"
        findings=$((findings + 1))
        continue
    fi
    mine="$(git -C "$WS" hash-object -- "$f")"
    if theirs="$(git -C "$clone" rev-parse --verify -q "$rev:$path")"; then
        if [ "$mine" = "$theirs" ]; then
            equal=$((equal + 1))
        else
            tooling_gate_fail "$NAME" "$path расходится: воркспейс ${mine:0:12}, kacho@${rev:0:12} ${theirs:0:12} — правится одним изменением в обоих"
            findings=$((findings + 1))
        fi
    elif git -C "$clone" show "$rev:scripts/hooks/pre-push" 2> /dev/null | grep -qF -- "${path##*/}"; then
        tooling_gate_fail "$NAME" "$path: хук kacho@${rev:0:12} зовёт ${path##*/}, а файла в стволе нет"
        findings=$((findings + 1))
    else
        pending=$((pending + 1))
    fi
done

tooling_gate_census "$NAME: пар объявлено ${#declared[@]}, kacho@${rev:0:12} ($ref): равных $equal, расходится/без файла $findings, ждёт ствола $pending"
if [ "$findings" -gt 0 ]; then
    exit 1
fi
tooling_gate_pass "$NAME" "объявленные пары хука равны стволу kacho побайтово (ждёт ствола — $pending)"
