#!/usr/bin/env bash
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# inject.sh — суждение `cla.py tree` СПОСОБНО упасть и способно смолчать (ws#731).
#
# Вход — синтетический репозиторий во временном каталоге: ведомость той же формы,
# что в дереве, и коммиты, где дефект — ОДИН факт против законного близнеца
# (выдуманный адрес против адреса из ведомости; трейлер в завершающем блоке против
# того же трейлера в прозе; запись с предметом против записи без него). Личности
# фикстуры — из зоны `.invalid`: чужими они выглядят и никуда не доставляются.
#
# Три исхода: 0 — все пробы дали ожидаемое; 1 — нет; 2 — фикстуру не собрать.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLA="$HERE/cla.py"
[ -f "$CLA" ] || { echo "[VOID] inject — $CLA в дереве нет" >&2; exit 2; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
      GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OWNER=owner@cla-inject.invalid
probes=0; failed=0

# repo <имя> — репозиторий с одним коммитом владельца; печатает путь.
repo() {
    local d="$TMP/$1"
    git init -q -b main "$d" || return 1
    git -C "$d" config user.email "$OWNER"
    git -C "$d" config user.name owner
    echo base > "$d/f.txt"
    git -C "$d" add -A && git -C "$d" commit -q -m "база фикстуры" || return 1
    printf '%s\n' "$d"
}

# ledger <репо> [<доп. YAML>] — ведомость с владельцем и областью «.».
ledger() {
    {
        echo "scope: [.]"
        echo "owners:"
        echo "  - email: $OWNER"
        echo "    note: владелец фикстуры"
        [ -n "${2:-}" ] && printf '%s\n' "$2"
    } > "$1/contribution-ledger.yaml"
}

# commit_as <репо> <адрес автора> <сообщение> — коммит с заданным автором;
# коммиттер — владелец (подстановка автора окружением, как в ws#700).
commit_as() {
    echo "$RANDOM$RANDOM" >> "$1/f.txt"
    git -C "$1" add -A
    GIT_AUTHOR_EMAIL="$2" GIT_AUTHOR_NAME="${2%@*}" git -C "$1" commit -q -m "$3"
}

# probe <ожидаемый код> <метка> <репо> [<подстрока>…]
probe() {
    local want="$1" label="$2" d="$3"; shift 3
    local out rc ok=1 n
    out="$(python3 "$CLA" tree --root "$d" 2>&1)"; rc=$?
    probes=$((probes + 1))
    [ "$rc" = "$want" ] || ok=0
    for n in "$@"; do [[ "$out" == *"$n"* ]] || ok=0; done
    if [ "$ok" = 1 ]; then
        echo "[PASS] $label (код $rc)"
    else
        failed=$((failed + 1))
        echo "[FAIL] $label — ожидался код $want с «$*», получен $rc" >&2
        printf '%s\n' "$out" | sed 's/^/    | /' >&2
    fi
}

d="$(repo a)" || { echo "[VOID] фикстура не собралась" >&2; exit 2; }
ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
probe 0 "A близнец: история своих — зелено, объём назван" "$d" "коммитов 2" "вкладов 2"

commit_as "$d" evil@cla-inject.invalid "вклад чужого"
sha="$(git -C "$d" rev-parse HEAD)"
probe 1 "B выдуманный адрес — находка по имени и sha" "$d" "evil@cla-inject.invalid" "${sha:0:12}" "автор"

ledger "$d" "signatories:
  - email: evil@cla-inject.invalid
    note: принял соглашение письмом фикстуры"
probe 0 "B близнец: тот же адрес, названный ведомостью, — молчание" "$d"

ledger "$d" "signatories:
  - email: evil@cla-inject.invalid
    note: принял соглашение письмом фикстуры
waivers:
  - email: ghost@cla-inject.invalid
    note: машинная личность, которой в истории нет"
probe 1 "C самоистечение: запись без предмета в области — находка" "$d" "ghost@cla-inject.invalid" "нечего покрывать"

d="$(repo d)"; ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
echo x >> "$d/f.txt"; git -C "$d" add -A
git -C "$d" commit -q -m "правка с соавтором" -m "Co-authored-by: Mallory <mallory@cla-inject.invalid>"
probe 1 "D соавтор в завершающем блоке трейлеров — вкладчик, находка" "$d" "mallory@cla-inject.invalid" "соавтор"

d="$(repo e)"; ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
echo x >> "$d/f.txt"; git -C "$d" add -A
git -C "$d" commit -q -m "разбор чужого коммита" -m "В прозе: строку Co-authored-by: Mallory <mallory@cla-inject.invalid> правило запрещает." -m "Ещё абзац прозы, а не трейлер."
probe 0 "D близнец: то же упоминание в прозе тела — не трейлер, молчание" "$d"

d="$(repo f)"; ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
echo x >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=ext@cla-inject.invalid GIT_AUTHOR_NAME=ext git -C "$d" commit -q -m "вклад с подписью" -m "Signed-off-by: ext <ext@cla-inject.invalid>"
probe 0 "E подпись Signed-off-by СВОЕЙ личностью подтверждает вклад" "$d"
echo y >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=ext2@cla-inject.invalid GIT_AUTHOR_NAME=ext2 git -C "$d" commit -q -m "подписал другой" -m "Signed-off-by: ext <ext@cla-inject.invalid>"
probe 1 "E близнец: подпись другой личности не подтверждает" "$d" "ext2@cla-inject.invalid"

d="$(repo g)"; ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
echo x >> "$d/f.txt"; git -C "$d" add -A
GIT_COMMITTER_EMAIL=carrier@cla-inject.invalid git -C "$d" commit -q -m "перенёс владелец"
probe 0 "F коммиттер вкладчиком не считается (суждение дерева)" "$d"

d="$(repo h)"
printf 'scope: [.]\nowners:\n  - email: %s\n' "$OWNER" > "$d/contribution-ledger.yaml"
probe 1 "G запись без причины — ведомость негодна" "$d" "без названной причины"
printf 'scope: [.]\nowners:\n  - email: %s\n    note: n\nexemptions: []\n' "$OWNER" > "$d/contribution-ledger.yaml"
probe 1 "G неизвестный раздел — отказ, а не тишина" "$d" "неизвестные разделы"
rm -f "$d/contribution-ledger.yaml"
probe 1 "G ведомости нет — отказ" "$d" "ведомости contribution-ledger.yaml в дереве нет"
printf 'scope: [nowhere]\nowners:\n  - email: %s\n    note: n\n' "$OWNER" > "$d/contribution-ledger.yaml"
probe 1 "G область мимо дерева — отказ, а не пустой зелёный" "$d" "не разрешается"

# ── граница истории ──────────────────────────────────────────────────────────
d="$(repo k)"
commit_as "$d" old@cla-inject.invalid "старый вклад до ведомости"
floor="$(git -C "$d" rev-parse HEAD)"
ledger "$d" "history_floor:
  commit: $floor
  note: граница фикстуры"
git -C "$d" add -A; git -C "$d" commit -q -m "ведомость с границей"
probe 0 "H за границей адрес без записи назван числом, вердикт не выносится" "$d" "ЗА ГРАНИЦЕЙ" "old@cla-inject.invalid — вкладов 1" "личностей без записи 1"
commit_as "$d" new-evil@cla-inject.invalid "новый чужой вклад"
probe 1 "H после границы — строго: новый чужой вклад — находка" "$d" "new-evil@cla-inject.invalid"
git -C "$d" reset -q --hard HEAD~1
ledger "$d" "history_floor:
  commit: $floor
  note: граница фикстуры
signatories:
  - email: old@cla-inject.invalid
    note: классифицирован владельцем фикстуры"
git -C "$d" add -A; git -C "$d" commit -q -m "старый адрес классифицирован"
probe 1 "H граница без предмета — находка (самоистечение границы)" "$d" "больше ничего не прикрывает"
ledger "$d" "history_floor:
  commit: $(git -C "$d" rev-parse HEAD)
  note: граница на голове"
git -C "$d" add -A; git -C "$d" commit -q --amend --no-edit
ledger "$d" "history_floor:
  commit: $(git -C "$d" rev-parse HEAD)
  note: граница на голове"
probe 1 "H пустой обход: граница на голове — отказ, а не зелёное" "$d" "обход пуст"
ledger "$d" "history_floor:
  commit: 0123456789abcdef0123456789abcdef01234567
  note: граница, которой в истории нет"
probe 2 "H граница не в истории (срез глубины) — без предмета, не зелёное" "$d" "условие не создано"

echo "[CENSUS] cla-gate inject: проб исполнено $probes, провалено $failed; фикстур-репозиториев 7"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] cla-gate inject — провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] cla-gate inject — суждение краснеет на выдуманном адресе, записи без предмета и пустом обходе и молчит на законных близнецах"
