#!/usr/bin/env bash
# ИНЪЕКЦИЯ набора comment-language-gate: доказательство, что он СПОСОБЕН упасть
# и способен ПРОМОЛЧАТЬ.
#
# КАЖДАЯ ОСЬ — ПАРА ОДНОФАКТНАЯ. Дефект и законный близнец отличаются РОВНО
# ОДНИМ фактом: языком прозы, наличием разделителя, наличием шапки, узлом
# (литерал против комментария). Всё остальное — путь, форма блока, окружающий
# код — совпадает. Пара, отличающаяся двумя фактами, доказывает не тот предмет:
# красное может прийти от соседа.
#
# ПОЧЕМУ СИНТЕТИКА, А НЕ ЖИВАЯ ЗАПИСЬ ДЕРЕВА. Инъекция, построенная на живой
# координате, краснеет в день, когда координату приведут к виду, — и её чинят
# возвратом английского ради зелёного. Синтетика во временном дереве не имеет
# этого свойства (`testing.md` selfcheck-on-synthetic-not-live-entry).
#
# ДЕРЕВО ПРОДУКТА СУДИТСЯ ПО СТВОЛУ, А НЕ ПО РАБОЧЕЙ КОПИИ (ws#789). Поэтому
# проба ложится КОММИТОМ, и у каждого синтетического клона ствол `origin/main`
# выставлен явно: без этого проба лежала бы в рабочей копии, которую прибор
# больше не читает, и ось краснела бы от беспредметности, а не от своего факта.
# Ведомость закрепляет БАЗОВЫЕ ревизии, снятые в `reset_tree`, — рост и убыль
# судятся против них.
#
# ЛОЖНОЕ КРАСНОЕ ОПАСНЕЕ ЛОЖНОГО ЗЕЛЁНОГО, и осей молчания здесь поэтому
# больше, чем осей красноты: ложное красное заставляет ПЕРЕВОДИТЬ то, что
# переводить нельзя, — директиву, метку лицензии, порождённую шапку, пример
# формата, ввезённый текст.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF/check-01-comment-language-does-not-grow.py"
PREMISE="$SELF/check-02-instrument-premise-holds.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/comment-language-inject.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Клоны берутся ТОЛЬКО из синтетики: переменные окружения, указывающие на
# настоящие деревья, сделали бы вердикт функцией чужого дерева.
unset KACHO_HOME_KACHO KACHO_HOME_KANAME KACHO_HOME_CORELIB

pass=0; fail=0

root() { echo "$TMP/root"; }
g() { git -C "$TMP/root/project/$1" -c user.email=i@i -c user.name=i "${@:2}"; }
# Ствол синтетического клона — `origin/main`, выставленный на его HEAD.
advance() { g "$1" update-ref refs/remotes/origin/main HEAD; }
rev() { g "$1" rev-parse "${2:-HEAD}"; }

declare -A BASE=()

reset_tree() {
    rm -rf "$TMP/root"
    mkdir -p "$TMP/root/docs" "$TMP/root/project/kacho" \
             "$TMP/root/project/kaname" "$TMP/root/project/corelib"
    printf 'project/\n' > "$TMP/root/.gitignore"
    # Базовая линия: у каждого дерева есть `.go` с РУССКИМ комментарием. Обход
    # непуст, находок ноль — «ноль находок» отличимо от «ноль прочитанного».
    for p in kacho kaname corelib; do
        cat > "$TMP/root/project/$p/base.go" <<'EOF'
package base

// Счётчик попыток — сбрасывается на успешном ответе.
var attempts int
EOF
        g "$p" init -q
        g "$p" add -A
        g "$p" commit -qm base
        advance "$p"
        BASE[$p]="$(rev "$p")"
    done
    mkdir -p "$TMP/root/.claude/hooks"
    cat > "$TMP/root/.claude/hooks/tool.go" <<'EOF'
package hooks

// Разбор узла — по позициям, а не текстовой заменой.
func parse() {}
EOF
    git -C "$TMP/root" init -q
    git -C "$TMP/root" add -A
    git -C "$TMP/root" -c user.email=i@i -c user.name=i commit -qm base
    ledger
}

# ledger [kacho=<rev>:<f>:<b>:<l>] [workspace=<f>:<b>:<l>] … — по умолчанию у
# продукта базовая ревизия и нули, у воркспейса нули.
ledger() {
    local -A spec=()
    local a
    for a in "$@"; do spec["${a%%=*}"]="${a#*=}"; done
    {
        echo "ceiling:"
        for p in kacho kaname corelib; do
            IFS=: read -r r f b l <<< "${spec[$p]:-${BASE[$p]}:0:0:0}"
            printf '  %s:\n    rev: %s\n    files: %s\n    blocks: %s\n    lines: %s\n' \
                "$p" "$r" "$f" "$b" "$l"
        done
        IFS=: read -r f b l <<< "${spec[workspace]:-0:0:0}"
        printf '  workspace:\n    files: %s\n    blocks: %s\n    lines: %s\n' "$f" "$b" "$l"
    } > "$TMP/root/docs/comment-language.yaml"
}

# axis <ось> <ожидаемый код> <пояснение> [подстрока, обязанная быть в выводе]
# Подстрока — ПРИЧИНА, а не симптом: код 1 от соседнего факта засчитан не будет.
axis() {
    local name="$1" want="$2" why="$3" says="${4:-}"
    DOCS_GATE_ROOT="$(root)" python3 "$CHECK" > "$TMP/out" 2>&1
    local got=$?
    if [ "$got" = "$want" ] && { [ -z "$says" ] || grep -qF -- "$says" "$TMP/out"; }; then
        pass=$((pass + 1))
        printf 'OK        %-38s код %s — %s\n' "$name" "$got" "$why"
    else
        fail=$((fail + 1))
        printf 'РАЗОШЛОСЬ %-38s ожидался %s%s, получен %s — %s\n' "$name" "$want" \
            "${says:+ и «$says»}" "$got" "$why"
        sed 's/^/          | /' "$TMP/out"
    fi
}

# put <файл> <текст> — проба ложится КОММИТОМ в ствол kacho.
put() {
    printf '%s\n' "$2" > "$TMP/root/project/kacho/$1"
    g kacho add -A
    g kacho commit -qm probe
    advance kacho
}

echo "── ОСИ КРАСНОТЫ: гейт обязан упасть ────────────────────────────────────"

reset_tree
put probe.go 'package probe

// The second branch is not wired yet and the caller must retry.
func f() {}'
ledger
axis "A дефект: английская проза" 1 "проза комментария не по-русски"

reset_tree
put probe.go 'package probe

//nolint:staticcheck // intentional nil for the defensive check below
func f() {}'
ledger
axis "B дефект: англ. обоснование директивы" 1 "токен латиницей, обоснование тоже"

reset_tree
put probe.go 'package probe

// the key comes from the context and otherwise the call is refused
func f() {}'
ledger
axis "C дефект: та же фраза без кириллицы" 1 "кириллицы в строке нет"

reset_tree
put probe.go 'package probe

// The upstream keeps this comment verbatim for the diff to stay empty.
func f() {}'
ledger
axis "D дефект: тот же текст ВНЕ поддерева" 1 "PROVENANCE.md рядом нет"

reset_tree
put probe.go 'package probe

// This table maps every REST route to its own gRPC method name.
func f() {}'
ledger
axis "E дефект: тот же файл без шапки" 1 "шапки Code generated нет"

reset_tree
put probe.go 'package probe

// go:generate mockgen -source=x.go -- the generator writes the mock for us
func f() {}'
ledger
axis "F дефект: та же строка КОММЕНТАРИЕМ" 1 "узел — комментарий, не литерал"

reset_tree
put probe.go 'package probe

// Copyright holders keep every notice of the upstream distribution.
func f() {}'
ledger
axis "G дефект: та же шапка ПРОЗОЙ" 1 "метки SPDX в строке нет"

reset_tree
ledger "kacho=${BASE[kacho]}:1:1:1"
axis "H ведомость не воспроизводится" 1 "на закреплённой объявлено больше замера" "НЕ ВОСПРОИЗВОДИТСЯ"

echo
echo "── ОСИ МОЛЧАНИЯ: гейт обязан промолчать ────────────────────────────────"

reset_tree
put probe.go 'package probe

// Вторая ветвь пока не привязана, и вызывающий обязан повторить.
func f() {}'
ledger
axis "A близнец: тот же текст по-русски" 0 "один факт разницы — язык"

reset_tree
put probe.go 'package probe

//nolint:staticcheck // намеренный nil ради защитной проверки ниже
func f() {}'
ledger
axis "B близнец: русское обоснование" 0 "директива та же, обоснование иное"

reset_tree
put probe.go 'package probe

//go:generate mockgen -source=x.go -destination=mock.go
func f() {}'
ledger
axis "B близнец: голая директива" 0 "аргументы директивы прозой не являются"

reset_tree
put probe.go 'package probe

// ключ берётся из ctx через TrustedPrincipalExtract, иначе fail-closed
func f() {}'
ledger
axis "C близнец: русский с лат. именами" 0 "смешанный комментарий — норма"

reset_tree
mkdir -p "$TMP/root/project/kacho/vendored"
printf 'Апстрим ory/fosite, сверяет .github/scripts/provenance.sh\n' \
    > "$TMP/root/project/kacho/vendored/PROVENANCE.md"
put vendored/probe.go 'package vendored

// The upstream keeps this comment verbatim for the diff to stay empty.
func f() {}'
ledger
axis "D близнец: ввезённое поддерево" 0 "рядом PROVENANCE.md — И4"

reset_tree
put probe.go 'package probe

// Code generated by protoc-gen-go. DO NOT EDIT.

// This table maps every REST route to its own gRPC method name.
func f() {}'
ledger
axis "E близнец: порождённый файл" 0 "шапка Code generated — И3"

reset_tree
put probe.go 'package probe

const banner = "// go:generate mockgen -source=x.go -- the generator writes the mock"

// Шаблон шапки, которую пишет генератор.
var t = banner'
ledger
axis "F близнец: та же строка ЛИТЕРАЛОМ" 0 "узел — литерал, И6 by construction"

reset_tree
put probe.go 'package probe

// Copyright (c) PRO-Robotech
// SPDX-License-Identifier: Apache-2.0

// Счётчик попыток.
var n int'
ledger
axis "G близнец: метка лицензии" 0 "закрытый словарь OSI — И2"

reset_tree
put probe.go 'package probe

// ProbeFinding — координата находки.
func f() {}'
ledger
axis "И7 близнец: префикс имени сущности" 0 "латинский префикс плюс русская проза"

reset_tree
put probe.go 'package probe

// local | host | hostssl | hostnossl
func f() {}'
ledger
axis "И6 близнец: перечень значений" 0 "разделитель колонок — не изложение"

echo
echo "── ОСЬ БЕСПРЕДМЕТНОСТИ: «ноль находок» отличимо от «ноль прочитанного» ─"

reset_tree
find "$TMP/root" -name '*.go' -delete
for p in kacho kaname corelib; do
    g "$p" commit -aqm drop >/dev/null 2>&1
    advance "$p"
done
git -C "$TMP/root" -c user.email=i@i -c user.name=i commit -aqm drop >/dev/null 2>&1
ledger "kacho=$(rev kacho):0:0:0" "kaname=$(rev kaname):0:0:0" "corelib=$(rev corelib):0:0:0"
axis 'I пустой обход' 2 'ни одного файла Go — это НЕ зелёное'

reset_tree
rm -f "$TMP/root/docs/comment-language.yaml"
axis "I ведомости нет" 2 "сверять число не с чем"

echo
echo "── СТВОЛ ПРОДУКТА ПРОТИВ ЗАКРЕПЛЁННОЙ РЕВИЗИИ (ws#789) ──────────────────"
#
# Предикат снятия задачи дословно: коммит в ствол kacho, убирающий английскую
# строку комментария, при неизменном воркспейсе → 0; коммит, добавляющий её → 1;
# клон на ветке полосы и на `origin/main` дают один и тот же вердикт.

ENG='package probe

// The second branch is not wired yet and the caller must retry.
func f() {}'
RUS='package probe

// Вторая ветвь пока не привязана, и вызывающий обязан повторить.
func f() {}'

reset_tree
put probe.go "$ENG"
pin="$(rev kacho)"
put probe.go "$RUS"
ledger "kacho=$pin:1:1:1"
axis "J убыль в стволе, воркспейс не тронут" 0 "убывание в чужом стволе не краснит" "запас files=1, blocks=1, lines=1"

reset_tree
put probe.go "$ENG"
ledger
axis "K рост в стволе против закреплённого" 1 "рост в чужом стволе краснит" "РОСТ на 1"

reset_tree
g kacho checkout -qb lane
printf '%s\n' "$ENG" > "$TMP/root/project/kacho/lane.go"
g kacho add -A
g kacho commit -qm lane
printf '%s\n' "$ENG" > "$TMP/root/project/kacho/untracked.go"
printf '\n// The caller keeps the old handle and must not reuse it.\n' \
    >> "$TMP/root/project/kacho/base.go"
ledger
axis "L ветка полосы и грязная копия, ствол чист" 0 "рабочая копия клона не вход" "ствол origin/main"

reset_tree
put probe.go "$ENG"
g kacho checkout -q "${BASE[kacho]}"
ledger
axis "L' ствол с находкой, копия на чистой базе" 1 "вердикт идёт за стволом, а не за checkout" "РОСТ на 1"

reset_tree
g kacho checkout -qb lane
printf '%s\n' "$RUS" > "$TMP/root/project/kacho/lane.go"
g kacho add -A
g kacho commit -qm lane
lane="$(rev kacho)"
g kacho checkout -q -
put other.go "$RUS"
ledger "kacho=$lane:0:0:0"
axis "M закреплённая ревизия не на стволе" 1 "коммит боковой ветки точкой отсчёта не бывает" "НЕ НА СТВОЛЕ"

reset_tree
put probe.go "$RUS"
pin="$(rev kacho)"
g kacho update-ref refs/remotes/origin/main "${BASE[kacho]}"
ledger "kacho=$pin:0:0:0"
axis "N ствол клона позади закреплённой" 2 "ссылку не тянули — НЕ зелёное и не находка" "ПОЗАДИ"

reset_tree
ledger "kacho=0123456789abcdef0123456789abcdef01234567:0:0:0"
axis "N' закреплённой ревизии нет в клоне" 2 "сверять не с чем" "в клоне"

reset_tree
g kacho update-ref -d refs/remotes/origin/main
axis "N'' ствола у клона нет" 2 "рабочая копия подменой ствола не служит" "не резолвится"

reset_tree
ledger "kacho=${BASE[kacho]:0:11}:0:0:0"
axis "O сокращённая ревизия в ведомости" 1 "ревизия называется целиком" "не полная ревизия"

reset_tree
cat >> "$TMP/root/.claude/hooks/tool.go" <<'EOF'

// The hook keeps the old handle and must not reuse it.
var h int
EOF
ledger
axis "P воркспейс: рост" 1 "у воркспейса храповик точный" "workspace: files замерено 1, объявлено 0 — РОСТ"

reset_tree
ledger "workspace=1:1:1"
axis "P' воркспейс: просрочка" 1 "у воркспейса убыль затягивается тем же изменением" "ПРОСРОЧЕНА"

reset_tree
cat >> "$TMP/root/.claude/hooks/tool.go" <<'EOF'

// The hook keeps the old handle and must not reuse it.
var h int
EOF
ledger "workspace=1:1:1"
axis "P близнец: воркспейс объявлен точно" 0 "точное число молчит"

echo
echo "── ПРЕДПОСЫЛКА ПРИБОРА ─────────────────────────────────────────────────"
reset_tree
DOCS_GATE_ROOT="$(root)" python3 "$PREMISE" > "$TMP/out" 2>&1
if [ $? = 0 ]; then
    pass=$((pass + 1)); echo "OK        предпосылка на синтетике        код 0"
else
    fail=$((fail + 1)); echo "РАЗОШЛОСЬ предпосылка на синтетике"; sed 's/^/          | /' "$TMP/out"
fi

# ПЕРЕПИСЬ ОСМОТРЕННОГО ОТДЕЛЬНО ОТ ИСХОДА: «разошлось 0» засчитывается только
# вместе с числом ПРОГНАННЫХ осей. Инъекция, не прогнавшая ни одной оси, зелёной
# не является — она немая, и именно так выглядит перенос файла проверки.
total=$((pass + fail))
echo
echo "инъекция comment-language-gate: рассмотрено осей $total; сошлось $pass, разошлось $fail"
if [ "$total" -eq 0 ]; then
    echo "ОТКАЗ — осей 0: рассматривать оказалось нечего, и это НЕ зелёное" >&2
    exit 1
fi
[ "$fail" -eq 0 ] || exit 1
exit 0
