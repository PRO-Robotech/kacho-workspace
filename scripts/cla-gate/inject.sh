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
# Шаг фикстуры с пустым путём (`git -C ""`) исполняется в рабочем каталоге. Им
# становится временный корень, а выше него git не поднимается: иначе пустой путь
# нашёл бы ЭТУ рабочую копию (временный корень бывает внутри неё) и писал бы в неё.
cd "$TMP" || exit 2
export GIT_CEILING_DIRECTORIES="$(dirname "$TMP")"

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
# ссылка> <sha на сервере>»), и `$1` хука — имя remote отправки.
probe_push() {  # <ожидаемый код> <метка> <репо> <remote> <строки> [<подстрока>…]
    local want="$1" label="$2" d="$3" remote="$4" lines="$5"; shift 5
    local out rc ok=1 n
    if ! fixture_ok "$d"; then
        probes=$((probes + 1)); failed=$((failed + 1))
        echo "[FAIL] $label — фикстура не собрана («$d»): судить нечего, и это не проход" >&2
        return
    fi
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
git init -q --bare "$TMP/e2k-new.git"
probe_push 1 "E2k отправка по URL, а не имени remote: известное чужим remote не вычитается" \
    "$d" "$TMP/e2k-new.git" "refs/heads/main $head refs/heads/main $Z" "known-elsewhere@cla-inject.invalid"
probe_push 2 "E2k сервер отправки не отвечает — опубликованное не вычесть: исход 2, не проход" \
    "$d" "$TMP/e2k-absent.git" "refs/heads/main $head refs/heads/main $Z" "не ответил на ls-remote"

# ── «только история» при отправке ────────────────────────────────────────────
dh="$hk"
git init -q --bare "$TMP/h-new.git"
commit_as "$dh" old@cla-inject.invalid "новый коммит адресом «только история»"
nh="$(git -C "$dh" rev-parse HEAD)"
probe_push 1 "HP1 отправка НОВОГО коммита адресом «только история» — отказ «вперёд запрет»" \
    "$dh" "$TMP/h-new.git" "refs/heads/main $nh refs/heads/main $Z" "old@cla-inject.invalid" "вперёд запрет"
# Ведомость судьи — из ОТПРАВЛЯЕМОЙ ревизии: история отправляется вместе с
# коммитом, несущим ведомость (граница ведомости в нём и названа).
probe_push 0 "HP1 близнец: отправка ИСТОРИИ (до границы) с ведомостью в новый remote — история покрыта" \
    "$dh" "$TMP/h-new.git" "refs/heads/main $(git -C "$dh" rev-parse "$nh~1") refs/heads/main $Z" "история до границы 2"
probe_push 1 "HP1 отправка ревизии, в дереве которой ведомости нет, — отказ «судить нечем», а не проход" \
    "$dh" "$TMP/h-new.git" "refs/heads/main $floor refs/heads/main $Z" "ведомости contribution-ledger.yaml в дереве нет" "$(printf '%.12s' "$floor")"

# Подпись Signed-off-by после границы не подтверждает НИЧЕГО и при отправке:
# роль автора закрыта перечнем ведомости (ws#729 п.1).
git init -q --bare "$TMP/e-fwd.git"
echo a >> "$e_fwd/f.txt"; git -C "$e_fwd" add -A
GIT_AUTHOR_EMAIL=old@cla-inject.invalid GIT_AUTHOR_NAME=old git -C "$e_fwd" commit -q -m "old со своей подписью" -m "Signed-off-by: old <old@cla-inject.invalid>"
probe_push 1 "HP2 отправка: Signed-off-by адреса «только история» не снимает «вперёд запрет»" \
    "$e_fwd" "$TMP/e-fwd.git" "refs/heads/main $(git -C "$e_fwd" rev-parse HEAD) refs/heads/main $Z" "old@cla-inject.invalid" "вперёд запрет"
git -C "$e_fwd" reset -q --hard HEAD~1
echo b >> "$e_fwd/f.txt"; git -C "$e_fwd" add -A
GIT_AUTHOR_EMAIL=stranger@cla-inject.invalid GIT_AUTHOR_NAME=stranger git -C "$e_fwd" commit -q -m "чужой со своей подписью" -m "Signed-off-by: stranger <stranger@cla-inject.invalid>"
probe_push 1 "HP3 отправка: адрес вне ведомости со своим Signed-off-by — отказ" \
    "$e_fwd" "$TMP/e-fwd.git" "refs/heads/main $(git -C "$e_fwd" rev-parse HEAD) refs/heads/main $Z" "stranger@cla-inject.invalid" "личности нет в ведомости"
git -C "$e_fwd" reset -q --hard HEAD~1
git init -q --bare "$TMP/e6.git"
probe_push 1 "E6p отправка: автор без адреса + Signed-off-by без адреса — отказ «не разобран»" \
    "$e6" "$TMP/e6.git" "refs/heads/main $(git -C "$e6" rev-parse HEAD) refs/heads/main $Z" "не разобран"

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
git init -q --bare "$TMP/attr.git"
base_a="$(git -C "$da" rev-parse HEAD)"
attr_push() {  # <ожидаемый код> <метка> <сообщение: абзацы через |> [<подстрока>…]
    local want="$1" label="$2" msg="$3"; shift 3
    local args=() part
    IFS='|' read -r -a parts <<<"$msg"
    for part in "${parts[@]}"; do args+=(-m "$part"); done
    echo "$RANDOM$RANDOM" >> "$da/f.txt"; git -C "$da" add -A
    git -C "$da" commit -q "${args[@]}"
    probe_push "$want" "$label" "$da" "$TMP/attr.git" \
        "refs/heads/main $(git -C "$da" rev-parse HEAD) refs/heads/main $Z" "$@"
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
# является». Отправка в зеркало публикует посадки заново, и без записи законная
# отправка краснела бы навсегда; с записью личность покрывает ровно роль
# коммиттера — автором она вклад не подписывает, запись без коммита истекает.
dc="$(fresh cmt)"
echo c >> "$dc/f.txt"; git -C "$dc" add -A
GIT_COMMITTER_EMAIL=server@cla-inject.invalid GIT_COMMITTER_NAME=server git -C "$dc" commit -q -m "посадка сервером"
git init -q --bare "$TMP/cmt.git"
probe_push 1 "C1 отправка: коммиттер-сервер без записи committers — отказ, роль «коммиттер»" \
    "$dc" "$TMP/cmt.git" "refs/heads/main $(git -C "$dc" rev-parse HEAD) refs/heads/main $Z" "коммиттер" "server@cla-inject.invalid"
CM="committers:
  - email: server@cla-inject.invalid
    note: сервер подписывает посадку коммиттером (ws#700)"
ledger "$dc" "$CM"; git -C "$dc" add -A; git -C "$dc" commit -q -m "ведомость: committers"
probe_push 0 "C1 близнец: запись committers в ведомости отправляемой ревизии — проходит" \
    "$dc" "$TMP/cmt.git" "refs/heads/main $(git -C "$dc" rev-parse HEAD) refs/heads/main $Z" "публикуемых коммитов 4"
probe 0 "C2 tree: запись committers с предметом — молчание, число коммитов названо" "$dc" "committers server@cla-inject.invalid — коммитов коммиттером 1"
echo a >> "$dc/f.txt"; git -C "$dc" add -A
GIT_AUTHOR_EMAIL=server@cla-inject.invalid GIT_AUTHOR_NAME=server git -C "$dc" commit -q -m "сервер автором"
probe 1 "C3 tree: личность из committers автором — находка «раздел committers этой роли не покрывает»" "$dc" "server@cla-inject.invalid" "раздел committers"
probe_push 1 "C3 отправка: личность из committers автором — отказ" \
    "$dc" "$TMP/cmt.git" "refs/heads/main $(git -C "$dc" rev-parse HEAD) refs/heads/main $Z" "автор" "раздел committers"
git -C "$dc" reset -q --hard HEAD~1
ledger "$dc" "$CM
  - email: ghost-server@cla-inject.invalid
    note: запись без единого коммита"
probe 1 "C4 tree: запись committers без коммита с этим коммиттером — находка (самоистечение)" "$dc" "ghost-server@cla-inject.invalid" "нечего покрывать"
ledger "$dc" "$CM"

echo "[CENSUS] cla-gate inject: проб исполнено $probes, провалено $failed; фикстур-репозиториев $(find "$TMP" -mindepth 2 -maxdepth 2 -name .git | wc -l)"
if [ "$failed" -gt 0 ]; then
    echo "[FAIL] cla-gate inject — провалов $failed из $probes" >&2
    exit 1
fi
echo "[PASS] cla-gate inject — суждение краснеет на выдуманном адресе, записи без предмета и пустом обходе и молчит на законных близнецах"
