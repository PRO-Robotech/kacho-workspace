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
      GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
      KACHO_CLA_FIRST_LANDING
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Шаг фикстуры с пустым путём (`git -C ""`) исполняется в рабочем каталоге. Им
# становится временный корень, а выше него git не поднимается: иначе пустой путь
# нашёл бы ЭТУ рабочую копию (временный корень бывает внутри неё) и писал бы в неё.
cd "$TMP" || exit 2
GIT_CEILING_DIRECTORIES="$(dirname "$TMP")"
export GIT_CEILING_DIRECTORIES

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
# fixture_ok <каталог> — фикстура собрана и лежит ВНУТРИ временного корня. Пустой
# путь (помощник не определён, фикстура не собралась) превращал `git -C ""` в
# рабочий каталог — то есть в ЭТУ рабочую копию: проба судила бы настоящее
# дерево, а шаги фикстуры писали бы в него.
fixture_ok() { [ -n "$1" ] && [[ "$1" == "$TMP"/* ]] && [ -d "$1/.git" ]; }

probe() {
    local want="$1" label="$2" d="$3"; shift 3
    local out rc ok=1 n
    if ! fixture_ok "$d"; then
        probes=$((probes + 1)); failed=$((failed + 1))
        echo "[FAIL] $label — фикстура не собрана («$d»): судить нечего, и это не проход" >&2
        return
    fi
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

# ── E: Signed-off-by подтверждает вклад ТОЛЬКО в истории (до границы) ─────────
#
# Подпись `Signed-off-by` — строка сообщения, дописать её может кто угодно. У
# соседа она — форма принятия соглашения; здесь вперёд действует решение владельца
# «только своя личность» (закрытый перечень ведомости, ws#729 п.1), поэтому после
# границы подпись не подтверждает НИЧЕГО — ни адрес «только история», ни чужой. В
# истории (до границы) подтверждает, как у соседа: история не переписывается.
# floor_repo <имя> <автор>|<подпись>… — репозиторий: вклад «только история»
# (old@), затем коммиты «<автор>|<строка Signed-off-by>», граница на последнем из
# них, ведомость с этой границей закоммичена. Печатает путь.
floor_repo() {
    local d spec a s fl; d="$(repo "$1")" || return 1; shift
    commit_as "$d" old@cla-inject.invalid "вклад «только история»" >/dev/null
    for spec in "$@"; do
        a="${spec%%|*}"; s="${spec#*|}"
        echo "$RANDOM$RANDOM" >> "$d/f.txt"; git -C "$d" add -A
        git -C "$d" commit -q --author="$a" -m "вклад до границы" -m "$s"
    done
    fl="$(git -C "$d" rev-parse HEAD)"
    ledger "$d" "history_floor:
  commit: $fl
  note: граница пробы
history_only:
  - email: old@cla-inject.invalid
    note: только история по решению владельца фикстуры"
    git -C "$d" add -A; git -C "$d" commit -q -m "ведомость с границей"
    printf '%s\n' "$d"
}
d="$(floor_repo e-hist "ext <ext@cla-inject.invalid>|Signed-off-by: ext <ext@cla-inject.invalid>")"
probe 0 "E подпись Signed-off-by СВОЕЙ личностью ДО границы — история, подтверждает" "$d" "подписью 1"
d="$(floor_repo e-hist2 "ext2 <ext2@cla-inject.invalid>|Signed-off-by: ext <ext@cla-inject.invalid>")"
probe 1 "E близнец: подпись ДРУГОЙ личности не подтверждает и в истории" "$d" "ext2@cla-inject.invalid"
d="$(floor_repo e-fwd)"; e_fwd="$d"
echo z >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=ext3@cla-inject.invalid GIT_AUTHOR_NAME=ext3 git -C "$d" commit -q -m "чужой со своей подписью" -m "Signed-off-by: ext3 <ext3@cla-inject.invalid>"
probe 1 "E1 после границы Signed-off-by чужого адреса НЕ подтверждает — перечень закрыт" "$d" "ext3@cla-inject.invalid" "личности нет в ведомости"
git -C "$d" reset -q --hard HEAD~1
echo w >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=old@cla-inject.invalid GIT_AUTHOR_NAME=old git -C "$d" commit -q -m "адрес «только история» со своей подписью" -m "Signed-off-by: old <old@cla-inject.invalid>"
probe 1 "E2 после границы Signed-off-by адреса «только история» не снимает «вперёд запрет»" "$d" "old@cla-inject.invalid" "вперёд запрет"
git -C "$d" reset -q --hard HEAD~1

# ── E7: пустой обход области — отказ, а не «подтверждено» ─────────────────────
d="$(repo e7)"
mkdir -p "$d/sub"; echo u > "$d/sub/untracked.txt"
printf 'scope: [sub]\nowners:\n  - email: %s\n    note: владелец фикстуры\n' "$OWNER" > "$d/contribution-ledger.yaml"
git -C "$d" add contribution-ledger.yaml; git -C "$d" commit -q -m "ведомость"
probe 1 "E7 область есть на диске, коммитов в ней нет — «гейт слеп», а не зелёное" "$d" "гейт слеп"
git -C "$d" add sub; git -C "$d" commit -q -m "первый коммит в области"
probe 0 "E7 близнец: в области есть коммит — судится и подтверждён" "$d" "коммитов 1"

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

# ── E6: вклад без разборного адреса — находка; подпись без адреса его не покрывает ─
#
# Пустой адрес автора (`--author="Mallory <>"`) и пустой адрес из неразборной
# строки `Signed-off-by: Mallory` — одна и та же пустая строка; совпадение двух
# «ничего» подтверждением не является ни в истории, ни после неё.
d="$(fresh e6)"
echo x >> "$d/f.txt"; git -C "$d" add -A
git -C "$d" commit -q --author="Mallory <>" -m "автор без адреса" -m "Signed-off-by: Mallory"
probe 1 "E6 автор без адреса + Signed-off-by без адреса — находка «не разобран»" "$d" "не разобран" "автор"
e6="$d"
d="$(floor_repo e6h "Mallory <>|Signed-off-by: Mallory")"
probe 1 "E6h то же ДО границы (там подпись действует) — всё равно находка «не разобран»" "$d" "не разобран"
d="$(fresh e6t)"
echo x >> "$d/f.txt"; git -C "$d" add -A
git -C "$d" commit -q -m "свой коммит" -m "Signed-off-by: Mallory"
probe 0 "E6 близнец: свой коммит с неразборной строкой Signed-off-by — молчание" "$d"

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

# ── E8: ключ атрибуции после границы судит и ГЕЙТ ДЕРЕВА ─────────────────────
#
# Ствол судится этим режимом (`cla.py tree`): коммит с ключом атрибуции, влитый
# схлопыванием мимо хука отправки, обязан покраснеть здесь. Автор — своя
# личность, поэтому краснеть нечему, кроме ключа. Близнец — тот же ключ ДО
# границы (проба «трейлер атрибуции ДО границы» ниже): история не судится.
d="$(floor_repo e8)"
echo x >> "$d/f.txt"; git -C "$d" add -A
git -C "$d" commit -q -m "свой коммит после границы" -m "Claude-Session: https://claude.ai/code/session_inject"
probe 1 "E8 tree: ключ атрибуции после границы — находка по имени ключа при своём авторе" "$d" "Claude-Session" "ключ атрибуции"

# ── E2: суждение ОТПРАВКИ (`cla.py push-range`) ─────────────────────────────
#
# Вход — строки, которые git подаёт хуку pre-push («<лок. ссылка> <sha> <удал.
# ссылка> <sha на сервере>»), и `$1` хука — имя remote либо URL отправки.
# ПОЛНОМОЧИЯ — У СТВОЛА: судит ведомость ветки, на которую указывает HEAD сервера
# отправки. Поэтому у каждого «сервера» пробы есть ствол `main`, посаженный БЕЗ
# суждения (посадка — шаг сервера, а не отправка разработчика); сервер без ствола —
# отдельная проба первой посадки (FL).
last_out=""
probe_push() {  # <ожидаемый код> <метка> <репо> <remote> <строки> [<подстрока>…]; FIRST=1 — флаг
    local want="$1" label="$2" d="$3" remote="$4" lines="$5"; shift 5
    local out rc ok=1 n
    if ! fixture_ok "$d"; then
        probes=$((probes + 1)); failed=$((failed + 1))
        echo "[FAIL] $label — фикстура не собрана («$d»): судить нечего, и это не проход" >&2
        return
    fi
    out="$(printf '%s\n' "$lines" | KACHO_CLA_FIRST_LANDING="${FIRST:-}" python3 "$CLA" push-range --root "$d" --remote "$remote" 2>&1)"; rc=$?
    last_out="$out"
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
check() {  # <да|нет> <метка> [<пояснение>] — проба-утверждение о состоянии фикстуры
    probes=$((probes + 1))
    if [ "$1" = да ]; then echo "[PASS] $2"; else failed=$((failed + 1)); echo "[FAIL] $2${3:+ — $3}" >&2; fi
}
Z=0000000000000000000000000000000000000000
# srv <имя> [<репо> <ревизия ствола>] — bare-«сервер», HEAD → main; с ревизией —
# ствол main посажен ею. Печатает путь.
srv() {
    local s="$TMP/$1.git"
    git init -q --bare -b main "$s" || return 1
    if [ -n "${2:-}" ]; then git -C "$2" push -q "$s" "$3:refs/heads/main" || return 1; fi
    printf '%s\n' "$s"
}
# cures — исполнимые строки лечения ПОСЛЕДНЕГО отказа («лечение$ <команда>»), по одной.
cures() { printf '%s\n' "$last_out" | sed -n 's/^  лечение\$ //p'; }
# rewrites — те из них, что ПЕРЕПИСЫВАЮТ (всё, кроме отправки).
rewrites() { cures | grep -vE '^(KACHO_CLA_FIRST_LANDING=1 )?git push ' || true; }
# run_cures <репо> — исполняет ДОСЛОВНО каждую напечатанную команду лечения, кроме
# отправки (её судит проба `push_printed` тем же суждением, которое позвал бы хук).
# Число исполненных — в `cured_n`: у находки ЛИЧНОСТИ исполнимой переписи нет, и ноль
# там — ожидаемое, а у находки ключа — провал («лечение, которого нет, не лечит»);
# решает проба, а не этот помощник.
cured_n=0
run_cures() {
    local d="$1" cmd
    cured_n=0
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        ( cd "$d" && bash -c "$cmd" ) >/dev/null 2>&1 || { echo "    лечение не исполнилось: $cmd" >&2; return 1; }
        cured_n=$((cured_n + 1))
    done < <(rewrites)
    return 0
}
# work_of <репо> <ревизия> <файл> — «автор коммиттер» коммита, который ВНЁС файл в
# историю ревизии. Работа чужого адреса опознаётся по содержимому, а не по подписи:
# переподпись меняет подпись, и сверка одних `%ae/%ce` после лечения ничего не видит.
work_of() { git -C "$1" log --format='%ae %ce' --diff-filter=A "$2" -- "$3" | tail -1; }
# push_printed <ожидаемый код> <метка> <репо> [<подстрока>…] — напечатанная отказом
# отправка («git push <remote> <лок>:<удал>…», с флагом или без) как строки pre-push,
# которые git подал бы хуку на эту команду, — и суждение по ним.
push_printed() {
    local want="$1" label="$2" d="$3"; shift 3
    local cmd rest lines="" spec l r rs first=""
    cmd="$(cures | grep -E '^(KACHO_CLA_FIRST_LANDING=1 )?git push ' | tail -1)"
    if [ -z "$cmd" ]; then
        probes=$((probes + 1)); failed=$((failed + 1))
        echo "[FAIL] $label — отказ не напечатал исполнимую отправку («лечение\$ git push …»)" >&2
        return
    fi
    [[ "$cmd" == KACHO_CLA_FIRST_LANDING=1\ * ]] && first=1
    rest="${cmd#*git push }"
    local -a w
    eval "w=($rest)"
    for spec in "${w[@]:1}"; do
        l="${spec%%:*}"; r="${spec#*:}"
        rs="$(git -C "$d" ls-remote -- "${w[0]}" "$r" | cut -f1)"
        lines+="$l $(git -C "$d" rev-parse "$l") $r ${rs:-$Z}"$'\n'
    done
    FIRST="$first" probe_push "$want" "$label" "$d" "${w[0]}" "${lines%$'\n'}" "$@"
}
# idents <репо> <диапазон…> — адреса авторов и коммиттеров диапазона, по одному.
idents() { local d="$1"; shift; git -C "$d" log --format='%ae%n%ce' "$@" | sort -u; }

d="$(fresh e2k)"
git init -q --bare -b main "$TMP/e2k-origin.git"; git init -q --bare -b main "$TMP/e2k-other.git"
git -C "$d" remote add origin "$TMP/e2k-origin.git"; git -C "$d" remote add other "$TMP/e2k-other.git"
git -C "$d" push -q origin main
echo k >> "$d/f.txt"; git -C "$d" add -A
GIT_AUTHOR_EMAIL=known-elsewhere@cla-inject.invalid GIT_AUTHOR_NAME=k git -C "$d" commit -q -m "чужой, известный через другой remote"
git -C "$d" push -q other main; git -C "$d" fetch -q other
head="$(git -C "$d" rev-parse HEAD)"; base="$(git -C "$d" rev-parse origin/main)"
probe_push 1 "E2k чужой коммит, известный через ссылку ДРУГОГО remote, судится при отправке в origin" \
    "$d" origin "refs/heads/main $head refs/heads/main $base" "known-elsewhere@cla-inject.invalid" "публикуемых коммитов 1"
git -C "$d" push -q --no-verify origin main:refs/heads/landed; git -C "$d" fetch -q origin
probe_push 0 "E2k близнец: тот же коммит уже на ЭТОМ remote — не судится повторно" \
    "$d" origin "refs/heads/main $head refs/heads/topic $Z" "публикуемых коммитов 0"
s="$(srv e2k-new "$d" "$base")"
probe_push 1 "E2k отправка по URL, а не имени remote: известное чужим remote не вычитается" \
    "$d" "$s" "refs/heads/main $head refs/heads/main $base" "known-elsewhere@cla-inject.invalid"
probe_push 2 "E2k сервер отправки не отвечает — опубликованное не вычесть: исход 2, не проход" \
    "$d" "$TMP/e2k-absent.git" "refs/heads/main $head refs/heads/main $Z" "не ответил на ls-remote"

# ── «только история» при отправке ────────────────────────────────────────────
#
# Ствол «сервера» h-new — ревизия без родителей, чья ведомость называет границу $floor
# чужой ветки: история до границы на сервере НЕ лежит, и её коммиты судятся как
# история (history_only действует), а новое — как новое.
dh="$hk"
h_led="$(git -C "$dh" rev-parse HEAD)"
h_orphan="$(git -C "$dh" commit-tree -m "ствол без истории, ведомость с границей" "$h_led^{tree}")"
s="$(srv h-new "$dh" "$h_orphan")"
probe_push 0 "HP1 история до границы, которой на сервере нет, судится историей — адрес «только история» покрыт" \
    "$dh" "$s" "refs/heads/hist $floor refs/heads/hist $Z" "история до границы 2"
commit_as "$dh" old@cla-inject.invalid "новый коммит адресом «только история»"
nh="$(git -C "$dh" rev-parse HEAD)"
probe_push 1 "HP1 отправка НОВОГО коммита адресом «только история» — отказ «вперёд запрет»" \
    "$dh" "$s" "refs/heads/main2 $nh refs/heads/main2 $Z" "old@cla-inject.invalid" "вперёд запрет"
git -C "$dh" reset -q --hard "$h_led"

# Подпись Signed-off-by после границы не подтверждает НИЧЕГО и при отправке:
# роль автора закрыта перечнем ведомости (ws#729 п.1).
s="$(srv e-fwd "$e_fwd" "$(git -C "$e_fwd" rev-parse HEAD)")"
echo a >> "$e_fwd/f.txt"; git -C "$e_fwd" add -A
GIT_AUTHOR_EMAIL=old@cla-inject.invalid GIT_AUTHOR_NAME=old git -C "$e_fwd" commit -q -m "old со своей подписью" -m "Signed-off-by: old <old@cla-inject.invalid>"
probe_push 1 "HP2 отправка: Signed-off-by адреса «только история» не снимает «вперёд запрет»" \
    "$e_fwd" "$s" "refs/heads/f $(git -C "$e_fwd" rev-parse HEAD) refs/heads/f $Z" "old@cla-inject.invalid" "вперёд запрет"
git -C "$e_fwd" reset -q --hard HEAD~1
echo b >> "$e_fwd/f.txt"; git -C "$e_fwd" add -A
GIT_AUTHOR_EMAIL=stranger@cla-inject.invalid GIT_AUTHOR_NAME=stranger git -C "$e_fwd" commit -q -m "чужой со своей подписью" -m "Signed-off-by: stranger <stranger@cla-inject.invalid>"
probe_push 1 "HP3 отправка: адрес вне ведомости со своим Signed-off-by — отказ" \
    "$e_fwd" "$s" "refs/heads/f $(git -C "$e_fwd" rev-parse HEAD) refs/heads/f $Z" "stranger@cla-inject.invalid" "личности нет в ведомости"
git -C "$e_fwd" reset -q --hard HEAD~1
s="$(srv e6 "$e6" "$(git -C "$e6" rev-parse HEAD~1)")"
probe_push 1 "E6p отправка: автор без адреса + Signed-off-by без адреса — отказ «не разобран»" \
    "$e6" "$s" "refs/heads/main $(git -C "$e6" rev-parse HEAD) refs/heads/main $(git -C "$e6" rev-parse HEAD~1)" "не разобран"

# ── ключ атрибуции — отказ НЕЗАВИСИМО от ведомости (gi-no-attribution-trailers) ─
#
# Трейлер атрибуции ловился лишь потому, что его адреса нет в ведомости:
# освобождение адреса (waivers) его пропускало, ключ без адреса не судился
# вовсе, значение без угловых скобок молча отбрасывалось. Ключ судится по имени —
# строка сообщения, НАЧИНАЮЩАЯСЯ ключом, — в коммитах после границы. Упоминание
# ключа внутри строки прозы — законный близнец; история до границы не судится.
da="$(repo attr)"
ledger "$da" "waivers:
  - email: noreply@anthropic.com
    note: освобождение пробы E2g — подпись под вкладом не нужна"
git -C "$da" add -A; git -C "$da" commit -q -m "ведомость с освобождением"
base_a="$(git -C "$da" rev-parse HEAD)"
s_attr="$(srv attr "$da" "$base_a")"
attr_push() {  # <ожидаемый код> <метка> <сообщение: абзацы через |> [<подстрока>…]
    local want="$1" label="$2" msg="$3"; shift 3
    local args=() part
    IFS='|' read -r -a parts <<<"$msg"
    for part in "${parts[@]}"; do args+=(-m "$part"); done
    echo "$RANDOM$RANDOM" >> "$da/f.txt"; git -C "$da" add -A
    git -C "$da" commit -q "${args[@]}"
    probe_push "$want" "$label" "$da" "$s_attr" \
        "refs/heads/main $(git -C "$da" rev-parse HEAD) refs/heads/main $base_a" "$@"
    git -C "$da" reset -q --hard "$base_a"
}
attr_push 1 "E2g трейлер атрибуции с ОСВОБОЖДЁННЫМ адресом — отказ по ключу" \
    "правка|Co-authored-by: Claude <noreply@anthropic.com>" "Co-authored-by" "ключ атрибуции"
attr_push 1 "E2f Claude-Session без адреса — отказ по ключу" \
    "правка|Claude-Session: https://claude.ai/code/session_inject" "Claude-Session" "ключ атрибуции"
attr_push 1 "E2j Co-authored-by без угловых скобок — не тихий пропуск" \
    "правка|Co-authored-by: Someone someone@cla-inject.invalid" "Co-authored-by"
attr_push 1 "E2t ключ в последнем абзаце вперемешку с прозой (git блоком не считает) — отказ" \
    "правка|Co-Authored-By: Claude <noreply@anthropic.com>|и ещё строка прозы" "Co-Authored-By"
attr_push 0 "E2 близнец: ключ внутри строки прозы — не трейлер, проходит" \
    "правка|Правило запрещает строку Co-authored-by: X <x@y> и строку Claude-Session: url в сообщении."
attr_push 0 "E2 близнец: обычный коммит владельца — проходит"  "правка"
dj="$(repo attrh)"
echo x >> "$dj/f.txt"; git -C "$dj" add -A
git -C "$dj" commit -q -m "история" -m "Co-authored-by: Legacy legacy@cla-inject.invalid"
fl="$(git -C "$dj" rev-parse HEAD)"
ledger "$dj" "history_floor:
  commit: $fl
  note: граница пробы
history_only:
  - email: legacy@cla-inject.invalid
    note: только история"
git -C "$dj" add -A; git -C "$dj" commit -q -m "ведомость"
probe 1 "E2j история: соавтор без разборного адреса до границы — находка, а не пропуск" "$dj" "не разобран"
dh2="$(repo attrh2)"
echo x >> "$dh2/f.txt"; git -C "$dh2" add -A
git -C "$dh2" commit -q -m "история" -m "Co-authored-by: Legacy <legacy@cla-inject.invalid>"
fl="$(git -C "$dh2" rev-parse HEAD)"
ledger "$dh2" "history_floor:
  commit: $fl
  note: граница пробы
history_only:
  - email: legacy@cla-inject.invalid
    note: только история"
git -C "$dh2" add -A; git -C "$dh2" commit -q -m "ведомость"
probe 0 "E2 близнец: трейлер атрибуции ДО границы — история, не судится" "$dh2"

# ── committers: личность, допустимая ТОЛЬКО коммиттером (посадка сервером) ─────
#
# ws#700: «committer noreply@github.com у схлопывающих слияний … находкой НЕ
# является». Запись действует, когда она — в ведомости СТВОЛА: та же запись в
# отправляемой ревизии поверх ствола без неё круг не расширяет.
dc="$(fresh cmt)"
c_plain="$(git -C "$dc" rev-parse HEAD)"
CM="committers:
  - email: server@cla-inject.invalid
    note: сервер подписывает посадку коммиттером (ws#700)"
ledger "$dc" "$CM"; git -C "$dc" add -A; git -C "$dc" commit -q -m "ведомость: committers"
c_cm="$(git -C "$dc" rev-parse HEAD)"
echo c >> "$dc/f.txt"; git -C "$dc" add -A
GIT_COMMITTER_EMAIL=server@cla-inject.invalid GIT_COMMITTER_NAME=server git -C "$dc" commit -q -m "посадка сервером"
c_land="$(git -C "$dc" rev-parse HEAD)"
s_bare="$(srv cmt-plain "$dc" "$c_plain")"
probe_push 1 "C1 ствол без записи committers: коммиттер-сервер — отказ; та же запись в ведомости ВЕТКИ круг не расширяет" \
    "$dc" "$s_bare" "refs/heads/main $c_land refs/heads/main $c_plain" "коммиттер" "server@cla-inject.invalid" "НЕ действует"
s_cm="$(srv cmt "$dc" "$c_cm")"
probe_push 0 "C1 близнец: запись committers в ведомости СТВОЛА — проходит" \
    "$dc" "$s_cm" "refs/heads/main $c_land refs/heads/main $c_cm" "публикуемых коммитов 1"
probe 0 "C2 tree: запись committers с предметом — молчание, число коммитов названо" "$dc" "committers server@cla-inject.invalid — коммитов коммиттером 1"
echo a >> "$dc/f.txt"; git -C "$dc" add -A
GIT_AUTHOR_EMAIL=server@cla-inject.invalid GIT_AUTHOR_NAME=server git -C "$dc" commit -q -m "сервер автором"
probe 1 "C3 tree: личность из committers автором — находка «раздел committers этой роли не покрывает»" "$dc" "server@cla-inject.invalid" "раздел committers"
probe_push 1 "C3 отправка: личность из committers автором — отказ" \
    "$dc" "$s_cm" "refs/heads/main $(git -C "$dc" rev-parse HEAD) refs/heads/main $c_cm" "автор" "раздел committers"
git -C "$dc" reset -q --hard HEAD~1
ledger "$dc" "$CM
  - email: ghost-server@cla-inject.invalid
    note: запись без единого коммита"
probe 1 "C4 tree: запись committers без коммита с этим коммиттером — находка (самоистечение)" "$dc" "ghost-server@cla-inject.invalid" "нечего покрывать"
ledger "$dc" "$CM"

# ── N: ОТПРАВКА, КОТОРАЯ НИЧЕГО НЕ ПУБЛИКУЕТ, ВЕДОМОСТИ НЕ ТРЕБУЕТ (круг 2) ──────
#
# Ведомость читается ПОСЛЕ вычитания опубликованного: тег на уже опубликованный
# коммит не требует её ни в стволе, ни в дереве коммита — публиковать нечего.
dn="$(floor_repo np)"
n_floor="$(git -C "$dn" rev-parse HEAD~1)"; n_led="$(git -C "$dn" rev-parse HEAD)"
s_np="$(srv np-srv "$dn" "$n_led")"
probe_push 0 "N1 тег на коммит истории без ведомости, уже опубликованный, — публиковать нечего: проходит" \
    "$dn" "$s_np" "refs/tags/v0 $n_floor refs/tags/v0 $Z" "публикуемых коммитов 0" "ссылок без нового 1"
probe_push 0 "N1 близнец: тег на коммит ведомости, уже опубликованный, — публиковать нечего: проходит" \
    "$dn" "$s_np" "refs/tags/v1 $n_led refs/tags/v1 $Z" "публикуемых коммитов 0"
git -C "$dn" checkout -q -b oldledger "$n_led"
printf 'scope: [.]\nowners:\n  - email: %s\n    note: n\nretired_section: []\n' "$OWNER" > "$dn/contribution-ledger.yaml"
git -C "$dn" commit -qam "ведомость прежней формы"
n_bad="$(git -C "$dn" rev-parse HEAD)"
git -C "$dn" push -q "$s_np" "$n_bad:refs/heads/oldledger"
git -C "$dn" checkout -q main
probe_push 0 "N1b тег на опубликованный коммит с ведомостью, негодной по нынешнему разбору, — публиковать нечего: проходит" \
    "$dn" "$s_np" "refs/tags/v2 $n_bad refs/tags/v2 $Z" "публикуемых коммитов 0"
probe_push 0 "N1b новый свой коммит поверх негодной ведомости ВЕТКИ — судит ствол, отличие названо и не действует" \
    "$dn" "$s_np" "refs/heads/oldledger2 $(git -C "$dn" commit-tree -p "$n_bad" -m 'новый поверх' "$n_bad^{tree}") refs/heads/oldledger2 $Z" \
    "публикуемых коммитов 1" "НЕ действует"

# ── W: ПОЛНОМОЧИЯ БЕРУТСЯ ИЗ СТВОЛА, А НЕ ИЗ ПРОВЕРЯЕМОГО ИЗМЕНЕНИЯ (круг 3) ────
#
# Находка приёмки круга 3: отказ ветке без ведомости печатал лечение «git
# cherry-pick <первый коммит ведомости>». Самая ранняя редакция — самая широкая
# (прежний адрес владельца ещё в owners), и после исполнения лечения дословно коммит
# адреса «только история» уходил на сервер с кодом 0. Проба прежде сверяла
# подстроку «git cherry-pick» и переносила СВОЙ sha, а редакция ведомости в
# фикстуре была одна.
#
# Здесь редакций две, и ранняя ШИРЕ: old@ в owners и stranger@ в signatories; поздняя
# (ствол) переводит old@ в history_only и stranger@ не знает. Каждая команда лечения
# исполняется ДОСЛОВНО из текста отказа, и после неё на сервер не уходит ни одного
# коммита чужой подписи или адреса «только история».
dw="$(repo w)"
commit_as "$dw" old@cla-inject.invalid "вклад old до ведомостей"
w_pre="$(git -C "$dw" rev-parse HEAD)"
ledger "$dw" "  - email: old@cla-inject.invalid
    note: ранняя редакция — прежний адрес владельца ещё свой
signatories:
  - email: stranger@cla-inject.invalid
    note: ранняя редакция — принял соглашение"
git -C "$dw" add -A; git -C "$dw" commit -q -m "ведомость: ранняя, широкая"
w_wide="$(git -C "$dw" rev-parse HEAD)"
ledger "$dw" "history_floor:
  commit: $w_wide
  note: граница поздней редакции
history_only:
  - email: old@cla-inject.invalid
    note: поздняя редакция — прежний адрес только в истории"
git -C "$dw" add -A; git -C "$dw" commit -q -m "ведомость: поздняя, узкая"
w_narrow="$(git -C "$dw" rev-parse HEAD)"
s_w="$(srv w-srv "$dw" "$w_narrow")"
check "$( [ "$(git -C "$dw" log --format=%h -- contribution-ledger.yaml | wc -l)" -ge 2 ] && git -C "$dw" show "$w_wide:contribution-ledger.yaml" | grep -q 'old@' && echo да || echo нет)" \
    "W предпосылка: редакций ведомости две и больше, ранняя шире (old@ в её owners)"
# w_branch <имя> <от> <адрес автора и коммиттера> — ветка с одним новым коммитом; его
# работа — отдельный файл `work-<имя>.txt`, по которому её опознаёт `work_of`.
w_branch() {
    git -C "$dw" checkout -q -b "$1" "$2"
    echo "work of $3 on $1" > "$dw/work-$1.txt"; git -C "$dw" add -A
    GIT_AUTHOR_EMAIL="$3" GIT_AUTHOR_NAME=x GIT_COMMITTER_EMAIL="$3" GIT_COMMITTER_NAME=x git -C "$dw" commit -q -m "коммит $3"
}
# w_cured <метка> <репо> <ветка> <запретный адрес> <файл его работы>
# — каждая напечатанная команда лечения исполнена ДОСЛОВНО; переписи для находки
# личности не напечатано; напечатанная отправка после лечения — СНОВА отказ (ни одно
# лечение не открывает адрес вне ведомости ствола); работа запретного адреса по-прежнему
# записана за ним (переподписи нет). Находка приёмки круга 1: лечение переподписывало
# весь диапазон, отправка после него проходила, а сверка `%ae/%ce` диапазона — ровно
# то, что переподпись переписывает, — была слепа к этому по устройству.
w_cured() {
    local label="$1" d="$2" b="$3" who="$4" file="$5" ok=да
    run_cures "$d" || ok=нет
    check "$( [ "$ok" = да ] && [ "$cured_n" = 0 ] && echo да || echo нет)" \
        "$label: переписи для находки личности не напечатано — исполнено строк переписи $cured_n" "$(rewrites | head -3)"
    push_printed 1 "$label: напечатанная отправка после лечения — снова отказ, адрес $who не открыт" "$d" "$who"
    check "$( [ "$(work_of "$d" "$b" "$file")" = "$who $who" ] && echo да || echo нет)" \
        "$label: работа $who ($file) после лечения по-прежнему записана за $who — переподписи нет" \
        "внёс: $(work_of "$d" "$b" "$file")"
}
w_branch wl "$w_wide" old@cla-inject.invalid
probe_push 1 "W1 ветка от РАННЕЙ широкой редакции, коммит адреса «только история» — отказ: судит ствол, а не ведомость ветки" \
    "$dw" "$s_w" "refs/heads/wl $(git -C "$dw" rev-parse wl) refs/heads/wl $Z" "old@cla-inject.invalid" "вперёд запрет" "ствол main@"
check "$( [[ "$last_out" != *"cherry-pick"* ]] && [[ "$last_out" == *"влейте ствол"* ]] && echo да || echo нет)" \
    "W1 лечение называет «влейте ствол» и не переносит в ветку ни одной редакции ведомости (нет cherry-pick)"
w_cured "W1" "$dw" wl old@cla-inject.invalid work-wl.txt
git -C "$dw" checkout -q main
w_branch ws "$w_wide" stranger@cla-inject.invalid
probe_push 1 "W2 ветка от ранней редакции, где stranger@ подписавший, — отказ: в стволе его нет" \
    "$dw" "$s_w" "refs/heads/ws $(git -C "$dw" rev-parse ws) refs/heads/ws $Z" "stranger@cla-inject.invalid" "личности нет в ведомости" "сначала сесть в ствол"
w_cured "W2" "$dw" ws stranger@cla-inject.invalid work-ws.txt
git -C "$dw" checkout -q main
w_branch wo "$w_pre" "$OWNER"
probe_push 0 "W3 близнец: ветка, отрезанная ДО ведомости, со своим коммитом — судит ствол, проходит без лечения" \
    "$dw" "$s_w" "refs/heads/wo $(git -C "$dw" rev-parse wo) refs/heads/wo $Z" "публикуемых коммитов 1" "ствол main@"
git -C "$dw" checkout -q main
w_branch wp "$w_pre" old@cla-inject.invalid
probe_push 1 "W4 ветка до ведомости, коммит адреса «только история» — отказ ведомостью ствола" \
    "$dw" "$s_w" "refs/heads/wp $(git -C "$dw" rev-parse wp) refs/heads/wp $Z" "old@cla-inject.invalid" "вперёд запрет"
w_cured "W4" "$dw" wp old@cla-inject.invalid work-wp.txt
git -C "$dw" checkout -q main
# W6: чужой коммит (его работа — отдельный файл), за ним свой коммит с соавтором вне
# ведомости. Строку этого соавтора лечение не снимает: снятие скрыло бы его вклад.
git -C "$dw" checkout -q -b lw "$w_narrow"
echo "work of stranger" > "$dw/work-lw.txt"; git -C "$dw" add -A
GIT_AUTHOR_EMAIL=stranger@cla-inject.invalid GIT_AUTHOR_NAME=stranger GIT_COMMITTER_EMAIL=stranger@cla-inject.invalid GIT_COMMITTER_NAME=stranger git -C "$dw" commit -q -m "работа stranger"
echo own >> "$dw/f.txt"; git -C "$dw" add -A
git -C "$dw" commit -q -m "свой с соавтором" -m "Co-authored-by: Human <human@cla-inject.invalid>"
probe_push 1 "W6 чужой коммит и свой с соавтором вне ведомости — отказ называет обоих" \
    "$dw" "$s_w" "refs/heads/lw $(git -C "$dw" rev-parse lw) refs/heads/lw $Z" "stranger@cla-inject.invalid" "human@cla-inject.invalid" "соавтор"
w_cured "W6" "$dw" lw stranger@cla-inject.invalid work-lw.txt
check "$(git -C "$dw" log -1 --format=%B lw | grep -q '^Co-authored-by: Human <human@cla-inject.invalid>$' && echo да || echo нет)" \
    "W6 строка соавтора вне ведомости после лечения на месте — его вклад не скрыт"
git -C "$dw" checkout -q main
# W7: та же работа чужого адреса в форме слияния: боковой коммит и само слияние — stranger@.
git -C "$dw" checkout -q -b lm-side "$w_narrow"
echo "work of stranger, side" > "$dw/work-lm.txt"; git -C "$dw" add -A
GIT_AUTHOR_EMAIL=stranger@cla-inject.invalid GIT_AUTHOR_NAME=stranger GIT_COMMITTER_EMAIL=stranger@cla-inject.invalid GIT_COMMITTER_NAME=stranger git -C "$dw" commit -q -m "боковой stranger"
git -C "$dw" checkout -q -b lm "$w_narrow"
echo own >> "$dw/f.txt"; git -C "$dw" commit -qam "свой до слияния"
GIT_AUTHOR_EMAIL=stranger@cla-inject.invalid GIT_AUTHOR_NAME=stranger GIT_COMMITTER_EMAIL=stranger@cla-inject.invalid GIT_COMMITTER_NAME=stranger git -C "$dw" merge -q --no-ff --no-edit lm-side
probe_push 1 "W7 слияние и боковой коммит адреса вне ведомости — отказ" \
    "$dw" "$s_w" "refs/heads/lm $(git -C "$dw" rev-parse lm) refs/heads/lm $Z" "stranger@cla-inject.invalid"
w_cured "W7" "$dw" lm stranger@cla-inject.invalid work-lm.txt
check "$( [ "$(git -C "$dw" log -1 --format='%ae %ce' lm)" = "stranger@cla-inject.invalid stranger@cla-inject.invalid" ] && echo да || echo нет)" \
    "W7 слияние после лечения по-прежнему записано за stranger@" "$(git -C "$dw" log -1 --format='%ae %ce' lm)"
git -C "$dw" checkout -q main
# W5: ветка РАСШИРЯЕТ свою ведомость и тут же пользуется записью.
git -C "$dw" checkout -q -b wx "$w_narrow"
ledger "$dw" "  - email: evil@cla-inject.invalid
    note: запись, внесённая самой проверяемой веткой
history_floor:
  commit: $w_wide
  note: граница поздней редакции
history_only:
  - email: old@cla-inject.invalid
    note: поздняя редакция — прежний адрес только в истории"
git -C "$dw" add -A; git -C "$dw" commit -q -m "ведомость ветки: evil в owners"
w_xled="$(git -C "$dw" rev-parse HEAD)"
echo x >> "$dw/f.txt"; git -C "$dw" add -A
GIT_AUTHOR_EMAIL=evil@cla-inject.invalid GIT_AUTHOR_NAME=evil GIT_COMMITTER_EMAIL=evil@cla-inject.invalid GIT_COMMITTER_NAME=evil git -C "$dw" commit -q -m "вклад evil"
w_x="$(git -C "$dw" rev-parse HEAD)"
probe_push 1 "W5 ведомость ВЕТКИ вносит адрес и тут же им пользуется — отказ: изменение круг допущенных не расширяет" \
    "$dw" "$s_w" "refs/heads/wx $w_x refs/heads/wx $Z" "evil@cla-inject.invalid" "НЕ действует" "сначала сесть в ствол"
git -C "$dw" push -q "$s_w" "$w_xled:refs/heads/main"
probe_push 0 "W5 близнец: та же запись СНАЧАЛА села в ствол — та же отправка проходит" \
    "$dw" "$s_w" "refs/heads/wx $w_x refs/heads/wx $Z" "публикуемых коммитов 1"
git -C "$dw" checkout -q main

# ── S: второе лечение личности — посадка записи в ствол; лечение ключа авторства не трогает ─
#
# Сервер w-srv2: его ствол — поздняя редакция плюс stranger@ в signatories, то есть
# «ведомость адреса СНАЧАЛА села в ствол». Та же ветка ws, отказанная выше, проходит
# с работой stranger@, записанной за stranger@ (W2 близнец). Лечение ключа
# атрибуции снимает строку ключа и больше ничего: коммит подписавшего и его работа
# остаются теми же объектами, у своего коммита автор, коммиттер и даты — прежние
# (находка приёмки круга 1, вариант 7: законный коммит подписавшего переписывался на
# отправителя).
git -C "$dw" checkout -q -b wsig "$w_narrow"
ledger "$dw" "signatories:
  - email: stranger@cla-inject.invalid
    note: запись села в ствол отдельной посадкой
history_floor:
  commit: $w_wide
  note: граница поздней редакции
history_only:
  - email: old@cla-inject.invalid
    note: поздняя редакция — прежний адрес только в истории"
git -C "$dw" add -A; git -C "$dw" commit -q -m "ведомость ствола: stranger@ подписавший"
w_sig="$(git -C "$dw" rev-parse HEAD)"
s_w2="$(srv w-srv2 "$dw" "$w_sig")"
git -C "$dw" checkout -q main
probe_push 0 "W2 близнец: ведомость адреса СНАЧАЛА села в ствол — та же ветка ws проходит" \
    "$dw" "$s_w2" "refs/heads/ws $(git -C "$dw" rev-parse ws) refs/heads/ws $Z" "публикуемых коммитов 1"
check "$( [ "$(work_of "$dw" ws work-ws.txt)" = "stranger@cla-inject.invalid stranger@cla-inject.invalid" ] && echo да || echo нет)" \
    "W2 близнец: работа stranger@ опубликована под его адресом, а не под адресом отправителя"
# commit_msg <репо> <автор и коммиттер|-> <файл работы> <абзацы через |>
commit_msg() {
    local d="$1" who="$2" f="$3" part; local -a a=()
    IFS='|' read -r -a parts <<<"$4"
    for part in "${parts[@]}"; do a+=(-m "$part"); done
    echo "$RANDOM $f" > "$d/$f"; git -C "$d" add -A
    if [ "$who" = - ]; then git -C "$d" commit -q "${a[@]}"
    else GIT_AUTHOR_EMAIL="$who" GIT_AUTHOR_NAME=x GIT_COMMITTER_EMAIL="$who" GIT_COMMITTER_NAME=x git -C "$d" commit -q "${a[@]}"; fi
}
# W8: свой коммит с ключами, ЗА НИМ законный коммит подписавшего — он внутри
# переписываемого диапазона, и родитель у него после лечения новый. Всё остальное —
# автор, коммиттер, даты, дерево, сообщение — обязано остаться прежним.
ids_of() { git -C "$1" log -1 --format='%an|%ae|%ad|%cn|%ce|%cd|%T|%B' "$2"; }
git -C "$dw" checkout -q -b lk "$w_sig"
GIT_AUTHOR_DATE="1700000000 +0300" GIT_COMMITTER_DATE="1700000100 +0300" \
    commit_msg "$dw" - own-lk.txt "свой с ключами|Claude-Session: https://claude.ai/code/session_inject|Co-authored-by: Signed <stranger@cla-inject.invalid>"
k_ids="$(ids_of "$dw" lk | sed '/^Claude-Session/d; /^Co-authored-by/d')"
GIT_AUTHOR_DATE="1700000200 +0300" GIT_COMMITTER_DATE="1700000300 +0300" \
    commit_msg "$dw" stranger@cla-inject.invalid work-lk.txt "работа подписавшего"
s_ids="$(ids_of "$dw" lk)"
probe_push 1 "W8 свой коммит с ключами атрибуции (соавтор — подписавший), за ним коммит подписавшего — отказ по ключу" \
    "$dw" "$s_w2" "refs/heads/lk $(git -C "$dw" rev-parse lk) refs/heads/lk $Z" "ключ атрибуции" "Claude-Session"
run_cures "$dw"; k_rc=$?
check "$( [ "$k_rc" = 0 ] && [ "$cured_n" = 1 ] && [[ "$(rewrites)" == *"filter-branch"* ]] && echo да || echo нет)" \
    "W8 лечение ключа напечатано и исполнено дословно (строк переписи $cured_n)" "$(rewrites)"
push_printed 0 "W8 напечатанная отправка после лечения ключа проходит" "$dw" "публикуемых коммитов 2"
check "$( [ "$(ids_of "$dw" lk)" = "$s_ids" ] && echo да || echo нет)" \
    "W8 коммит подписавшего внутри диапазона: автор, коммиттер, даты, дерево и сообщение прежние" "было «$s_ids», стало «$(ids_of "$dw" lk)»"
check "$( [ "$(ids_of "$dw" lk~1)" = "$k_ids" ] && ! git -C "$dw" log -1 --format=%B lk~1 | grep -qiE '^(co-authored-by|claude-session)' && echo да || echo нет)" \
    "W8 у своего коммита автор, коммиттер, даты и дерево прежние, строк ключа нет" "было «$k_ids», стало «$(ids_of "$dw" lk~1)»"
git -C "$dw" checkout -q main
# W9: строка ключа без адреса снимается, строка соавтора вне ведомости — нет.
git -C "$dw" checkout -q -b lh "$w_sig"
commit_msg "$dw" - own-lh.txt "свой с двумя ключами|Claude-Session: https://claude.ai/code/session_inject|Co-authored-by: Human <human@cla-inject.invalid>"
probe_push 1 "W9 ключ без адреса и соавтор вне ведомости — отказ называет соавтора" \
    "$dw" "$s_w2" "refs/heads/lh $(git -C "$dw" rev-parse lh) refs/heads/lh $Z" "human@cla-inject.invalid"
run_cures "$dw"; h_rc=$?
push_printed 1 "W9 после лечения — снова отказ: соавтор вне ведомости не скрыт" "$dw" "human@cla-inject.invalid"
check "$( [ "$h_rc" = 0 ] && git -C "$dw" log -1 --format=%B lh | grep -q '^Co-authored-by: Human <human@cla-inject.invalid>$' && ! git -C "$dw" log -1 --format=%B lh | grep -qi '^claude-session' && echo да || echo нет)" \
    "W9 лечение сняло строку Claude-Session и оставило строку соавтора вне ведомости" "$(git -C "$dw" log -1 --format=%B lh | tr '\n' '/')"
git -C "$dw" checkout -q main

# ── T: объект АННОТИРОВАННОГО тега судится, как коммит ─────────────────────────
#
# Находка приёмки круга 3: тег с чужим автором тега и трейлером атрибуции в
# сообщении уходил на сервер с кодом 0 — суждение снимало тег до коммита, а коммит
# уже был опубликован. Автор тега — как автор коммита; трейлеры его сообщения — как
# трейлеры коммита; объект тега, уже названный сервером, вычитается.
dt="$(fresh tg)"
s_t="$(srv tg "$dt" "$(git -C "$dt" rev-parse HEAD)")"
tag_push() {  # <ожидаемый код> <метка> <тег> [<подстрока>…]
    local want="$1" label="$2" t="$3"; shift 3
    probe_push "$want" "$label" "$dt" "$s_t" "refs/tags/$t $(git -C "$dt" rev-parse "refs/tags/$t") refs/tags/$t $Z" "$@"
}
GIT_COMMITTER_EMAIL=stray@cla-inject.invalid GIT_COMMITTER_NAME=stray git -C "$dt" tag -a t1 -m "выпуск" HEAD
tag_push 1 "T1 аннотированный тег на опубликованный коммит, автор тега чужой — отказ, роль «автор тега»" t1 \
    "stray@cla-inject.invalid" "автор тега" "объектов тегов 1"
run_cures "$dt"; t_cure=$?
check "$( [ "$t_cure" = 0 ] && [ "$cured_n" = 0 ] && [ "$(git -C "$dt" for-each-ref --format='%(taggeremail)' refs/tags/t1)" = "<stray@cla-inject.invalid>" ] && echo да || echo нет)" \
    "T1 переписи для чужого автора тега нет: тег не пересоздан своей личностью (строк переписи $cured_n)" "$(rewrites)"
push_printed 1 "T1 напечатанная отправка тега после лечения — снова отказ" "$dt" "stray@cla-inject.invalid"
git -C "$dt" tag -a t2 -m "выпуск" -m "Co-authored-by: Claude <noreply@anthropic.com>" HEAD
tag_push 1 "T2 тег своей личности с ключом атрибуции в сообщении — отказ по ключу" t2 "Co-authored-by" "ключ атрибуции"
check "$( [ -z "$(rewrites)" ] && echo да || echo нет)" \
    "T2 строку соавтора вне ведомости лечение тега не снимает — команды нет" "$(rewrites)"
git -C "$dt" tag -a t3 -m "выпуск" -m "Правило запрещает строку Co-authored-by: X <x@y> в сообщении тега." HEAD
tag_push 0 "T близнец: тег своей личности, ключ только в прозе — проходит, объект тега судим" t3 "объектов тегов 1"
GIT_COMMITTER_EMAIL=stray@cla-inject.invalid GIT_COMMITTER_NAME=stray git -C "$dt" tag -a t4in -m "внутренний" HEAD
git -C "$dt" tag -a t4 -m "внешний" t4in
tag_push 1 "T4 тег на чужой тег — внутренний объект тоже судится" t4 "stray@cla-inject.invalid" "объектов тегов 2"
GIT_COMMITTER_EMAIL=stray@cla-inject.invalid GIT_COMMITTER_NAME=stray git -C "$dt" tag -a t5 -m "опубликован обходом" HEAD
git -C "$dt" push -q "$s_t" refs/tags/t5
probe_push 0 "T5 объект тега, уже названный сервером, вычитается — повторная ссылка на него проходит" \
    "$dt" "$s_t" "refs/tags/t5 $(git -C "$dt" rev-parse refs/tags/t5) refs/tags/t5-copy $Z" "публикуемых коммитов 0, объектов тегов 0"

# ── FL: ПЕРВАЯ ПОСАДКА — ствол сервера ведомости не несёт ───────────────────────
#
# Полномочий в стволе нет — «условие не создано» (исход 2), и отказ называет флаг.
# Флаг допускает лишь ревизию, которая САМА несёт ведомость, и судит её самая узкая
# форма: owners ∩ user.email копии, прочие разделы и граница не действуют.
df="$(repo fl)"
f_base="$(git -C "$df" rev-parse HEAD)"
s_f="$(srv fl "$df" "$f_base")"
ledger "$df"; git -C "$df" add -A; git -C "$df" commit -q -m "ведомость вводится"
f_led="$(git -C "$df" rev-parse HEAD)"
probe_push 2 "FL1 ствол без ведомости — условие не создано, флаг первой посадки назван" \
    "$df" "$s_f" "refs/heads/main $f_led refs/heads/main $f_base" "условие не создано" "KACHO_CLA_FIRST_LANDING=1 git push"
push_printed 0 "FL1 напечатанная отправка с флагом — ревизия вводит ведомость, всё своё: проходит в узкой форме" "$df" "узкой форме"
git -C "$df" checkout -q -b flw "$f_led"
ledger "$df" "  - email: evil@cla-inject.invalid
    note: расширение в ревизии первой посадки
signatories:
  - email: stranger@cla-inject.invalid
    note: расширение в ревизии первой посадки"
git -C "$df" add -A; git -C "$df" commit -q -m "ведомость шире"
commit_msg "$df" evil@cla-inject.invalid work-fl-evil.txt "вклад evil"
commit_msg "$df" stranger@cla-inject.invalid work-fl-stranger.txt "вклад stranger"
commit_msg "$df" old@cla-inject.invalid work-fl-old.txt "вклад old"
FIRST=1 probe_push 1 "FL2 флаг: owners шире user.email, signatories, чужой адрес — узкая форма их не допускает" \
    "$df" "$s_f" "refs/heads/flw $(git -C "$df" rev-parse HEAD) refs/heads/flw $Z" "evil@cla-inject.invalid" "stranger@cla-inject.invalid" "old@cla-inject.invalid" "узкую форму"
check "$(cures | grep -q '^KACHO_CLA_FIRST_LANDING=1 git push ' && echo да || echo нет)" \
    "FL2 повторная отправка напечатана С ФЛАГОМ (ствол всё ещё без ведомости)" "$(cures | tail -1)"
w_cured "FL2" "$df" flw evil@cla-inject.invalid work-fl-evil.txt
check "$( [ "$(work_of "$df" flw work-fl-stranger.txt)" = "stranger@cla-inject.invalid stranger@cla-inject.invalid" ] && [ "$(work_of "$df" flw work-fl-old.txt)" = "old@cla-inject.invalid old@cla-inject.invalid" ] && echo да || echo нет)" \
    "FL2 работа stranger@ и old@ после лечения по-прежнему записана за ними" "$(work_of "$df" flw work-fl-stranger.txt); $(work_of "$df" flw work-fl-old.txt)"
git -C "$df" checkout -q -b flh "$f_led"
commit_as "$df" old@cla-inject.invalid "вклад old"
f_mv="$(git -C "$df" rev-parse HEAD)"
ledger "$df" "history_floor:
  commit: $f_mv
  note: граница, сдвинутая самой ревизией
history_only:
  - email: old@cla-inject.invalid
    note: объявлено самой ревизией"
git -C "$df" add -A; git -C "$df" commit -q -m "граница вперёд"
FIRST=1 probe_push 1 "FL3 флаг: граница, сдвинутая ревизией на свой же коммит, «только история» не открывает" \
    "$df" "$s_f" "refs/heads/flh $(git -C "$df" rev-parse HEAD) refs/heads/flh $Z" "old@cla-inject.invalid" "узкую форму"
git -C "$df" checkout -q -b flb "$f_base"
commit_as "$df" "$OWNER" "свой, ведомости нет"
FIRST=1 probe_push 1 "FL4 флаг на ревизии БЕЗ ведомости — отказ: флаг допускает лишь ревизию, вводящую её" \
    "$df" "$s_f" "refs/heads/flb $(git -C "$df" rev-parse HEAD) refs/heads/flb $Z" "лишь ревизию, которая сама вводит ведомость"
git -C "$df" checkout -q main
git -C "$df" config user.email other@cla-inject.invalid
FIRST=1 probe_push 1 "FL5 флаг: user.email копии не совпал с owners — своей личности нет, отказ" \
    "$df" "$s_f" "refs/heads/main $f_led refs/heads/main $f_base" "$OWNER" "узкую форму"
git -C "$df" config user.email "$OWNER"
s_e="$(srv fl-empty)"
probe_push 2 "FL6 пустой сервер (HEAD не назван) — ствола нет: условие не создано, не проход" \
    "$df" "$s_e" "refs/heads/main $f_led refs/heads/main $Z" "ствола не называет" "KACHO_CLA_FIRST_LANDING"

# ── CN: перепись по диапазону судит ТА ЖЕ ведомость ствола, что и отправка ────
#
# Перепись прежде читала ведомость РАБОЧЕГО дерева копии: незакоммиченная запись
# о личности делала диапазон «подтверждённым». Теперь — ствол названного remote.
probe_census() {  # <ожидаемый код> <метка> <репо> <remote> <ревизии через пробел> [<подстрока>…]
    local want="$1" label="$2" d="$3" remote="$4" revs="$5"; shift 5
    local out rc ok=1 n
    # shellcheck disable=SC2086 # ревизии — слова намеренно
    out="$(python3 "$CLA" census --root "$d" --remote "$remote" -- $revs 2>&1)"; rc=$?
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
git -C "$dw" checkout -q -b cn "$w_pre"
commit_as "$dw" cn-stranger@cla-inject.invalid "чужой для переписи"
cn_sha="$(git -C "$dw" rev-parse HEAD)"
git -C "$dw" checkout -q main
cp "$dw/contribution-ledger.yaml" "$TMP/cn-ledger.bak"
ledger "$dw" "  - email: cn-stranger@cla-inject.invalid
    note: незакоммиченная запись копии
history_floor:
  commit: $w_wide
  note: граница поздней редакции
history_only:
  - email: old@cla-inject.invalid
    note: поздняя редакция — прежний адрес только в истории"
check "$(git -C "$dw" diff --quiet HEAD -- contribution-ledger.yaml && echo нет || echo да)" \
    "CN предпосылка: ведомость рабочего дерева копии шире ствола (незакоммиченная запись cn-stranger@)"
probe_census 1 "CN1 перепись судит ведомостью СТВОЛА: незакоммиченная запись копии чужого не подтверждает" \
    "$dw" "$s_w" "$cn_sha ^$w_pre" "cn-stranger@cla-inject.invalid" "ведомость ствола main@"
cp "$TMP/cn-ledger.bak" "$dw/contribution-ledger.yaml"
probe_census 0 "CN близнец: свой коммит диапазона — подтверждён стволом, объём назван" \
    "$dw" "$s_w" "$w_narrow ^$w_wide" "коммитов 1" "находок 0"
probe_census 2 "CN2 ствол без ведомости — переписи судить нечем, не зелёное" \
    "$dw" "$s_f" "$cn_sha ^$w_pre" "ведомости contribution-ledger.yaml нет"
probe_census 2 "CN3 пустой диапазон — обход пуст, не «находок 0»" \
    "$dw" "$s_w" "$w_narrow ^$w_narrow" "судить нечего"

echo "[CENSUS] cla-gate inject: проб исполнено $probes, провалено $failed; фикстур-репозиториев $(find "$TMP" -mindepth 2 -maxdepth 2 -name .git | wc -l)"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] cla-gate inject — провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] cla-gate inject — суждение краснеет на выдуманном адресе, записи без предмета и пустом обходе и молчит на законных близнецах"
