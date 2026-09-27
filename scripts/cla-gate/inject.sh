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
        if [ -n "${2:-}" ]; then printf '%s\n' "$2"; fi
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

# ── E5: судится ВСЯ история области, а не её упрощение ──────────────────────
#
# `git log -- <область>` упрощает историю: снимает пустые коммиты, слияние,
# совпавшее деревом с одним из родителей, и ветку, влитую `-s ours`. При области
# `.` каждая из этих форм — вклад в дерево, и суждение, прошедшее мимо него,
# выносит «подтверждено» о коммите, которого не читало. Сверх упрощения — `.mailmap`
# дерева: `git log` по умолчанию подменяет им адрес, и суждение читало бы
# ОБЪЯВЛЕНИЕ о личности вместо записанной в коммите.
fresh() {  # <имя> — репозиторий с ведомостью владельца, печатает путь
    local d; d="$(repo "$1")" || return 1
    ledger "$d"; git -C "$d" add -A; git -C "$d" commit -q -m "ведомость"
    printf '%s\n' "$d"
}
d="$(fresh e5d)"
GIT_AUTHOR_EMAIL=empty-evil@cla-inject.invalid GIT_AUTHOR_NAME=e git -C "$d" commit -q --allow-empty -m "пустой коммит чужого"
probe 1 "E5d пустой коммит чужого автора — находка, а не пропуск упрощением" "$d" "empty-evil@cla-inject.invalid"
d="$(fresh e5h)"
git -C "$d" commit -q --allow-empty -m "пустой с соавтором" -m "Co-authored-by: Hidden <hidden@cla-inject.invalid>"
probe 1 "E5h трейлер соавтора на пустом коммите — находка" "$d" "hidden@cla-inject.invalid"
d="$(fresh e5i)"
git -C "$d" checkout -q -b side; echo side >> "$d/f.txt"; git -C "$d" commit -qam "сторона"
git -C "$d" checkout -q main
GIT_AUTHOR_EMAIL=merger@cla-inject.invalid GIT_AUTHOR_NAME=m git -C "$d" merge -q --no-ff --no-edit side
probe 1 "E5i слияние с деревом второго родителя, автор чужой — находка" "$d" "merger@cla-inject.invalid"
d="$(fresh e5j)"
git -C "$d" checkout -q -b side
GIT_AUTHOR_EMAIL=ours-evil@cla-inject.invalid GIT_AUTHOR_NAME=o git -C "$d" commit -q -m "сторона чужого" --allow-empty
echo s >> "$d/f.txt"; GIT_AUTHOR_EMAIL=ours-evil@cla-inject.invalid GIT_AUTHOR_NAME=o git -C "$d" commit -qam "правка чужого"
git -C "$d" checkout -q main; git -C "$d" merge -q -s ours --no-edit side
probe 1 "E5j ветка, влитая -s ours, — её чужие коммиты судятся" "$d" "ours-evil@cla-inject.invalid"
n_e5j="$(git -C "$d" rev-list --count HEAD)"
probe 1 "E5j перепись называет ВСЕ коммиты истории ($n_e5j), а не упрощение" "$d" "коммитов $n_e5j"
d="$(fresh e5m)"
echo m >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=masked@cla-inject.invalid GIT_AUTHOR_NAME=x git -C "$d" commit -q -m "чужой вклад"
printf 'owner <%s> <masked@cla-inject.invalid>\n' "$OWNER" > "$d/.mailmap"
git -C "$d" add .mailmap; git -C "$d" commit -q -m "подмена личности объявлением"
probe 1 "E5m .mailmap дерева не подменяет записанный в коммите адрес" "$d" "masked@cla-inject.invalid"
d="$(fresh e5t)"
git -C "$d" commit -q --allow-empty -m "пустой коммит владельца"
probe 0 "E5 близнец: пустой коммит СВОЕЙ личности — молчание" "$d"

# ── граница истории и «только история» ──────────────────────────────────────
#
# Запись history_only покрывает вклад ТОЛЬКО в коммитах, достижимых из границы;
# после неё тот же адрес — находка. Судится вся история.
d="$(repo k)"
commit_as "$d" old@cla-inject.invalid "старый вклад до ведомости"
floor="$(git -C "$d" rev-parse HEAD)"
HO="history_floor:
  commit: $floor
  note: граница фикстуры
history_only:
  - email: old@cla-inject.invalid
    note: только история по решению владельца фикстуры"
ledger "$d" "$HO"
git -C "$d" add -A; git -C "$d" commit -q -m "ведомость с границей"
probe 0 "H1 адрес «только история» до границы — покрыт, число его вкладов напечатано" "$d" "history_only old@cla-inject.invalid — вкладов до границы 1"
commit_as "$d" old@cla-inject.invalid "тот же адрес ПОСЛЕ границы"
probe 1 "H2 адрес «только история» после границы — находка «вперёд запрет»" "$d" "old@cla-inject.invalid" "вперёд запрет"
git -C "$d" reset -q --hard HEAD~1
commit_as "$d" never@cla-inject.invalid "чужой вклад после границы"
probe 1 "H3 чужой адрес после границы — находка" "$d" "never@cla-inject.invalid" "личности нет в ведомости"
git -C "$d" reset -q --hard HEAD~1
ledger "$d" "history_floor:
  commit: $floor
  note: граница фикстуры"
probe 1 "H4 до границы адрес без записи — находка: судится ВСЯ история" "$d" "old@cla-inject.invalid" "личности нет в ведомости"
probe 1 "H5 граница без единой записи history_only — находка (ничего не разделяет)" "$d" "ничего не"
ledger "$d" "$HO
  - email: ghost-history@cla-inject.invalid
    note: запись без вклада до границы"
probe 1 "H6 запись history_only без вклада до границы — находка (самоистечение)" "$d" "ghost-history@cla-inject.invalid" "нечего покрывать"
ledger "$d" "history_only:
  - email: old@cla-inject.invalid
    note: без границы"
probe 1 "H7 history_only без history_floor — ведомость негодна" "$d" "без history_floor"
ledger "$d" "history_floor:
  commit: 0123456789abcdef0123456789abcdef01234567
  note: граница, которой в истории нет
history_only:
  - email: old@cla-inject.invalid
    note: только история"
probe 2 "H8 граница не в истории (срез глубины) — без предмета, не зелёное" "$d" "условие не создано"
ledger "$d" "$HO"
hk="$d"   # фикстура границы — её же судит проба отправки HP1 ниже

# ── E2: суждение ОТПРАВКИ (`cla.py push-range`) ─────────────────────────────
#
# Вход — строки, которые git подаёт хуку pre-push («<лок. ссылка> <sha> <удал.
# ссылка> <sha на сервере>»), и `$1` хука — имя remote отправки.
probe_push() {  # <ожидаемый код> <метка> <репо> <remote> <строки> [<подстрока>…]
    local want="$1" label="$2" d="$3" remote="$4" lines="$5"; shift 5
    local out rc ok=1 n
    out="$(printf '%s\n' "$lines" | python3 "$CLA" push-range --root "$d" --remote "$remote" 2>&1)"; rc=$?
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
Z=0000000000000000000000000000000000000000

d="$(fresh e2k)"
git init -q --bare "$TMP/e2k-origin.git"; git init -q --bare "$TMP/e2k-other.git"
git -C "$d" remote add origin "$TMP/e2k-origin.git"; git -C "$d" remote add other "$TMP/e2k-other.git"
git -C "$d" push -q origin main
echo k >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=known-elsewhere@cla-inject.invalid GIT_AUTHOR_NAME=k git -C "$d" commit -q -m "чужой, известный через другой remote"
git -C "$d" push -q other main; git -C "$d" fetch -q other
head="$(git -C "$d" rev-parse HEAD)"; base="$(git -C "$d" rev-parse origin/main)"
probe_push 1 "E2k чужой коммит, известный через ссылку ДРУГОГО remote, судится при отправке в origin" \
    "$d" origin "refs/heads/main $head refs/heads/main $base" "known-elsewhere@cla-inject.invalid" "публикуемых коммитов 1"
git -C "$d" push -q --no-verify origin main; git -C "$d" fetch -q origin
probe_push 0 "E2k близнец: тот же коммит уже на ЭТОМ remote — не судится повторно" \
    "$d" origin "refs/heads/main $head refs/heads/topic $Z" "публикуемых коммитов 0"
probe_push 1 "E2k отправка по URL, а не имени remote: известное чужим remote не вычитается" \
    "$d" "$TMP/e2k-new.git" "refs/heads/main $head refs/heads/main $Z" "known-elsewhere@cla-inject.invalid"

# ── «только история» при отправке ────────────────────────────────────────────
dh="$hk"
git init -q --bare "$TMP/h-new.git"
commit_as "$dh" old@cla-inject.invalid "новый коммит адресом «только история»"
nh="$(git -C "$dh" rev-parse HEAD)"
probe_push 1 "HP1 отправка НОВОГО коммита адресом «только история» — отказ «вперёд запрет»" \
    "$dh" "$TMP/h-new.git" "refs/heads/main $nh refs/heads/main $Z" "old@cla-inject.invalid" "вперёд запрет"
probe_push 0 "HP1 близнец: отправка ИСТОРИИ (до границы) в новый remote — история покрыта" \
    "$dh" "$TMP/h-new.git" "refs/heads/main $floor refs/heads/main $Z" "история до границы 2"

echo "[CENSUS] cla-gate inject: проб исполнено $probes, провалено $failed; фикстур-репозиториев $(find "$TMP" -mindepth 2 -maxdepth 2 -name .git | wc -l)"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] cla-gate inject — провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] cla-gate inject — суждение краснеет на выдуманном адресе, записи без предмета и пустом обходе и молчит на законных близнецах"
