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
        git -C "$TMP/root/project/$p" init -q
        git -C "$TMP/root/project/$p" add -A
        git -C "$TMP/root/project/$p" -c user.email=i@i -c user.name=i commit -qm base
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
    ledger 0 0 0
}

ledger() {
    cat > "$TMP/root/docs/comment-language.yaml" <<EOF
ceiling:
  files: $1
  blocks: $2
  lines: $3
EOF
}

# axis <ось> <ожидаемый код> <пояснение>
axis() {
    local name="$1" want="$2" why="$3"
    DOCS_GATE_ROOT="$(root)" python3 "$CHECK" > "$TMP/out" 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
        printf 'OK        %-38s код %s — %s\n' "$name" "$got" "$why"
    else
        fail=$((fail + 1))
        printf 'РАЗОШЛОСЬ %-38s ожидался %s, получен %s — %s\n' "$name" "$want" "$got" "$why"
        sed 's/^/          | /' "$TMP/out"
    fi
}

put() { printf '%s\n' "$2" > "$TMP/root/project/kacho/$1"; }

echo "── ОСИ КРАСНОТЫ: гейт обязан упасть ────────────────────────────────────"

reset_tree
put probe.go 'package probe

// The second branch is not wired yet and the caller must retry.
func f() {}'
ledger 0 0 0
axis "A дефект: английская проза" 1 "проза комментария не по-русски"

reset_tree
put probe.go 'package probe

//nolint:staticcheck // intentional nil for the defensive check below
func f() {}'
ledger 0 0 0
axis "B дефект: англ. обоснование директивы" 1 "токен латиницей, обоснование тоже"

reset_tree
put probe.go 'package probe

// the key comes from the context and otherwise the call is refused
func f() {}'
ledger 0 0 0
axis "C дефект: та же фраза без кириллицы" 1 "кириллицы в строке нет"

reset_tree
put probe.go 'package probe

// The upstream keeps this comment verbatim for the diff to stay empty.
func f() {}'
ledger 0 0 0
axis "D дефект: тот же текст ВНЕ поддерева" 1 "PROVENANCE.md рядом нет"

reset_tree
put probe.go 'package probe

// This table maps every REST route to its own gRPC method name.
func f() {}'
ledger 0 0 0
axis "E дефект: тот же файл без шапки" 1 "шапки Code generated нет"

reset_tree
put probe.go 'package probe

// go:generate mockgen -source=x.go -- the generator writes the mock for us
func f() {}'
ledger 0 0 0
axis "F дефект: та же строка КОММЕНТАРИЕМ" 1 "узел — комментарий, не литерал"

reset_tree
put probe.go 'package probe

// Copyright holders keep every notice of the upstream distribution.
func f() {}'
ledger 0 0 0
axis "G дефект: та же шапка ПРОЗОЙ" 1 "метки SPDX в строке нет"

reset_tree
ledger 1 1 1
axis "H просрочка ведомости" 1 "объявлено больше, чем замерено"

echo
echo "── ОСИ МОЛЧАНИЯ: гейт обязан промолчать ────────────────────────────────"

reset_tree
put probe.go 'package probe

// Вторая ветвь пока не привязана, и вызывающий обязан повторить.
func f() {}'
ledger 0 0 0
axis "A близнец: тот же текст по-русски" 0 "один факт разницы — язык"

reset_tree
put probe.go 'package probe

//nolint:staticcheck // намеренный nil ради защитной проверки ниже
func f() {}'
ledger 0 0 0
axis "B близнец: русское обоснование" 0 "директива та же, обоснование иное"

reset_tree
put probe.go 'package probe

//go:generate mockgen -source=x.go -destination=mock.go
func f() {}'
ledger 0 0 0
axis "B близнец: голая директива" 0 "аргументы директивы прозой не являются"

reset_tree
put probe.go 'package probe

// ключ берётся из ctx через TrustedPrincipalExtract, иначе fail-closed
func f() {}'
ledger 0 0 0
axis "C близнец: русский с лат. именами" 0 "смешанный комментарий — норма"

reset_tree
mkdir -p "$TMP/root/project/kacho/vendored"
printf 'Апстрим ory/fosite, сверяет .github/scripts/provenance.sh\n' \
    > "$TMP/root/project/kacho/vendored/PROVENANCE.md"
printf '%s\n' 'package vendored

// The upstream keeps this comment verbatim for the diff to stay empty.
func f() {}' > "$TMP/root/project/kacho/vendored/probe.go"
ledger 0 0 0
axis "D близнец: ввезённое поддерево" 0 "рядом PROVENANCE.md — И4"

reset_tree
put probe.go 'package probe

// Code generated by protoc-gen-go. DO NOT EDIT.

// This table maps every REST route to its own gRPC method name.
func f() {}'
ledger 0 0 0
axis "E близнец: порождённый файл" 0 "шапка Code generated — И3"

reset_tree
put probe.go 'package probe

const banner = "// go:generate mockgen -source=x.go -- the generator writes the mock"

// Шаблон шапки, которую пишет генератор.
var t = banner'
ledger 0 0 0
axis "F близнец: та же строка ЛИТЕРАЛОМ" 0 "узел — литерал, И6 by construction"

reset_tree
put probe.go 'package probe

// Copyright (c) PRO-Robotech
// SPDX-License-Identifier: Apache-2.0

// Счётчик попыток.
var n int'
ledger 0 0 0
axis "G близнец: метка лицензии" 0 "закрытый словарь OSI — И2"

reset_tree
put probe.go 'package probe

// ProbeFinding — координата находки.
func f() {}'
ledger 0 0 0
axis "И7 близнец: префикс имени сущности" 0 "латинский префикс плюс русская проза"

reset_tree
put probe.go 'package probe

// local | host | hostssl | hostnossl
func f() {}'
ledger 0 0 0
axis "И6 близнец: перечень значений" 0 "разделитель колонок — не изложение"

echo
echo "── ОСЬ БЕСПРЕДМЕТНОСТИ: «ноль находок» отличимо от «ноль прочитанного» ─"

reset_tree
find "$TMP/root" -name '*.go' -delete
for p in kacho kaname corelib; do
    git -C "$TMP/root/project/$p" -c user.email=i@i -c user.name=i \
        commit -aqm drop >/dev/null 2>&1
done
git -C "$TMP/root" -c user.email=i@i -c user.name=i commit -aqm drop >/dev/null 2>&1
ledger 0 0 0
axis 'I пустой обход' 2 'ни одного файла Go — это НЕ зелёное'

reset_tree
rm -f "$TMP/root/docs/comment-language.yaml"
axis "I ведомости нет" 2 "сверять число не с чем"

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
