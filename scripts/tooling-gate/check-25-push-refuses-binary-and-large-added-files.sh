#!/usr/bin/env bash
# check-25 — хук отправки отвергает БИНАРЬ и файл БОЛЬШЕ 1 МБ среди файлов,
# добавленных новыми коммитами, и называет файл (ws#1189).
#
# Признак: в kacho#3284 коммит ветки нёс собранный ELF края на 39 МБ; поймало
# его ревью, а не хук. Держатель — scripts/hooks/prepush-added-files.sh, который
# scripts/hooks/pre-push зовёт вторым, до обхода KACHO_SKIP_PREPUSH и до пропуска
# черновиков. Без поведенческой пробы детектор бинаря, порог или перепись
# истории ослабляются молча, и отправка продолжает проходить.
#
# ПОВЕДЕНЧЕСКАЯ, как check-18: песочница — настоящий репозиторий с голым
# удалённым, на который опубликован `main`; в её дереве — копии хука, стража
# атрибуции, стража добавленных файлов и прогонщик-заглушка, печатающий метку.
# Перечень исключений — СВОЙ у песочницы (строка коллекций newman с доводом):
# в перечне воркспейса строк нет, а исключение «про запас» истекло бы.
#
# ЧТО ТРЕБУЕТСЯ:
#   отказ (код 1, файл назван, наборы НЕ запускались):
#     настоящий исполняемый файл (копия `true`); бинарь без режима исполнения;
#     текст больше 1 МБ вне перечня; бинарь, добавленный и снятый следующим
#     коммитом; бинарь, внесённый руками в слияние; бинарь под строкой
#     `*.bin diff` в `.gitattributes`; бинарь в черновике `wip/*`; бинарь при
#     KACHO_SKIP_PREPUSH=1; законный файл рядом с бинарём (антимаска);
#     строка перечня без предмета; строка перечня без довода;
#   молчание (код 0): коллекция newman больше 1 МБ по строке перечня (законный
#     близнец); исполняемый текстовый скрипт; текст ровно 1 МБ; бинарь, уже
#     опубликованный на удалённом; снятие ветки;
#   не судимо: ссылка удалённого битая — страж выходит 2, хук — 1; стража нет
#     рядом с хуком — хук 1 с названной причиной.
#
# ПРЕДПОСЫЛКА (VOID): законная отправка текстового файла проходит. Хук, красный
# и на ней, к остальным пробам непригоден: отказ на бинаре прошёл бы
# тождественно и не доказал бы ничего.
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/sandbox-git-home.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/sandbox-git-home.sh"

WS="$(tooling_gate_workspace_root)"
NAME="check-25-push-refuses-binary-and-large-added-files"
KIT=(pre-push prepush-attribution.sh attribution-rule.sh prepush-added-files.sh)

missing=()
for f in "${KIT[@]}"; do
    [ -n "$(tooling_gate_files "$WS" "scripts/hooks/$f")" ] || missing+=("scripts/hooks/$f")
done
if [ "${#missing[@]}" -gt 0 ]; then
    tooling_gate_void "$NAME" "в дереве нет ${missing[*]} — проверять нечего"
    exit 2
fi
ELF="$(type -P true || true)"
[ -z "$ELF" ] || ELF="$(readlink -f "$ELF")"
if ! file -b "$ELF" 2>/dev/null | grep -q '^ELF'; then
    tooling_gate_void "$NAME" "настоящего исполняемого файла для инъекции нет ($ELF не ELF либо нет file)"
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! sandbox_git_home "$TMP/home"; then
    tooling_gate_void "$NAME" "корневой подписи нет — вершина песочницы не родится, судить хук не на чем"
    exit 2
fi
pgit() { sandbox_git -c core.hooksPath=/dev/null "$@"; }

ZERO=0000000000000000000000000000000000000000
MARK="stub-run-all-исполнен"
COLL="services/x/tests/newman/collections"
box="$TMP/box"
mkdir -p "$box/scripts/hooks" "$box/scripts/stub" "$box/$COLL"
for f in "${KIT[@]}"; do cp "$WS/scripts/hooks/$f" "$box/scripts/hooks/"; done
chmod +x "$box/scripts/hooks/"*
printf 'size services/*/tests/newman/collections/*.postman_collection.json коллекция newman — текст, порождаемый gen.py\n' \
    > "$box/scripts/hooks/prepush-added-files.allow"
printf '{"info":{}}\n' > "$box/$COLL/a.postman_collection.json"
printf '#!/usr/bin/env bash\necho "%s"\nexit 0\n' "$MARK" > "$box/scripts/stub/run-all.sh"
chmod +x "$box/scripts/stub/run-all.sh"
pgit -C "$box" init -q -b main
pgit -C "$box" add -A
pgit -C "$box" commit -q -m "#1 песочница check-25"
pgit init -q --bare "$box.git"
pgit -C "$box" remote add origin "$box.git"
pgit -C "$box" push -q origin main
BASE="$(pgit -C "$box" rev-parse HEAD)"

# branch <имя> — ветка от опубликованного main; commit <сообщение> <файл…> — коммит
# названных файлов (уже лежащих в дереве).
branch() { pgit -C "$box" checkout -q -f -B "$1" "$BASE"; }
commit() { local m="$1"; shift; pgit -C "$box" add -- "$@"; pgit -C "$box" commit -q -m "$m"; }
text() { head -c "$2" /dev/zero | tr '\0' 'a' > "$box/$1"; }
head_sha() { pgit -C "$box" rev-parse HEAD; }

# push <вход git> [env…] — «<код>» первой строкой и вывод хука следом.
push() {
    local input="$1" out code
    shift
    out="$(
        cd "$box" || exit 111
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
              KACHO_MONOREPO KACHO_SKIP_PREPUSH
        printf '%s\n' "$input" | env "$@" HOME="$SANDBOX_GIT_HOME" bash ./scripts/hooks/pre-push origin "$box.git" 2>&1
    )" && code=0 || code=$?
    printf '%s\n%s\n' "$code" "$out"
}
create() { printf 'refs/heads/%s %s refs/heads/%s %s' "$1" "$(head_sha)" "$1" "$ZERO"; }

findings=0 examined=0 lawful=0 unlawful=0
fail() { tooling_gate_fail "$NAME" "$1"; findings=$((findings + 1)); }

expect_pass() {  # <описание> <вход> [env…]
    local d="$1" in="$2" res
    shift 2
    examined=$((examined + 1)); lawful=$((lawful + 1))
    res="$(push "$in" "$@")"
    [ "$(head -1 <<< "$res")" -eq 0 ] ||
        fail "$d — отвергнуто (код $(head -1 <<< "$res")), а отправка законна: $(grep -m2 'ОТКАЗ\|  ' <<< "$res" | tr '\n' ' ')"
}
expect_refuse() {  # <что обязан назвать> <описание> <вход> [env…]
    local name="$1" d="$2" in="$3" res body
    shift 3
    examined=$((examined + 1)); unlawful=$((unlawful + 1))
    res="$(push "$in" "$@")"; body="$(tail -n +2 <<< "$res")"
    if [ "$(head -1 <<< "$res")" -ne 1 ]; then
        fail "$d — хук вышел $(head -1 <<< "$res") вместо 1: файл уехал бы в публичную историю"
    elif ! grep -qF -- "$name" <<< "$body"; then
        fail "$d — отказ не называет «$name»"
    elif grep -qF -- "$MARK" <<< "$body"; then
        fail "$d — отказ пришёл ПОСЛЕ прогона наборов, а не до него"
    fi
}

# Предпосылка.
branch 1189-lawful; printf 'текст\n' > "$box/note.md"; commit "#1189 текст" note.md
res="$(push "$(create 1189-lawful)")"
if [ "$(head -1 <<< "$res")" -ne 0 ]; then
    tooling_gate_void "$NAME" "законная отправка текста вернула $(head -1 <<< "$res"); остальные пробы на ней недоказательны: $(tail -n +2 <<< "$res" | tr '\n' ' ' | head -c 400)"
    exit 2
fi

# ── Отказы ───────────────────────────────────────────────────────────────────
branch 1189-elf; cp "$ELF" "$box/edge"; chmod +x "$box/edge"; commit "#1189 бинарь" edge
expect_refuse edge "настоящий исполняемый файл (ELF) среди добавленных" "$(create 1189-elf)"
expect_refuse "исполняемый бинарь" "отказ называет вид: исполняемый бинарь" "$(create 1189-elf)"

branch 1189-blob; head -c 4096 "$ELF" > "$box/blob.dat"; commit "#1189 бинарь" blob.dat
expect_refuse blob.dat "бинарь без режима исполнения" "$(create 1189-blob)"

branch 1189-big; text big.txt 1048577; commit "#1189 крупное" big.txt
expect_refuse big.txt "текст больше 1 МБ вне перечня" "$(create 1189-big)"

branch 1189-gone; cp "$ELF" "$box/gone"; commit "#1189 бинарь" gone
pgit -C "$box" rm -q gone; pgit -C "$box" commit -q -m "#1189 снят"
expect_refuse gone "бинарь добавлен и снят следующим коммитом — в истории он есть" "$(create 1189-gone)"

branch 1189-side; printf 's\n' > "$box/side.md"; commit "#1189 бок" side.md
branch 1189-evil; printf 'm\n' > "$box/main.md"; commit "#1189 ствол" main.md
pgit -C "$box" merge -q --no-commit --no-ff 1189-side > /dev/null 2>&1
cp "$ELF" "$box/evil"; pgit -C "$box" add evil; pgit -C "$box" commit -q -m "#1189 слияние"
expect_refuse evil "бинарь, внесённый руками в слияние" "$(create 1189-evil)"

branch 1189-attr; printf '*.bin diff\n' > "$box/.gitattributes"; cp "$ELF" "$box/x.bin"
commit "#1189 маска" .gitattributes x.bin
expect_refuse x.bin "бинарь под строкой «*.bin diff» в .gitattributes" "$(create 1189-attr)"

branch 1189-elf2; cp "$ELF" "$box/edge"; commit "#1189 бинарь" edge
expect_refuse edge "черновик wip/* с бинарём" \
    "refs/heads/wip/x $(head_sha) refs/heads/wip/x $ZERO"
expect_refuse edge "бинарь при KACHO_SKIP_PREPUSH=1" "$(create 1189-elf2)" KACHO_SKIP_PREPUSH=1
expect_refuse edge "законная ветка рядом с бинарём (антимаска)" \
    "refs/heads/1189-lawful $(pgit -C "$box" rev-parse 1189-lawful) refs/heads/1189-lawful $ZERO
$(create 1189-elf2)"

ALLOW="$box/scripts/hooks/prepush-added-files.allow"
cp "$ALLOW" "$TMP/allow"
branch 1189-lawful2; printf 'т\n' > "$box/n2.md"; commit "#1189 текст" n2.md
printf 'binary deploy/*.tgz архив чарта\n' >> "$ALLOW"
expect_refuse "deploy/*.tgz" "строка перечня без предмета" "$(create 1189-lawful2)"
cp "$TMP/allow" "$ALLOW"; printf 'size %s/*.json\n' "$COLL" >> "$ALLOW"
expect_refuse "без довода" "строка перечня без довода" "$(create 1189-lawful2)"
cp "$TMP/allow" "$ALLOW"

# ── Законные близнецы ────────────────────────────────────────────────────────
branch 1189-newman; text "$COLL/b.postman_collection.json" 1500000; commit "#1189 коллекция" "$COLL/b.postman_collection.json"
expect_pass "коллекция newman больше 1 МБ по строке перечня — законный близнец" "$(create 1189-newman)"
branch 1189-newman2; text "$COLL/b.json" 1500000; commit "#1189 не коллекция" "$COLL/b.json"
expect_refuse "$COLL/b.json" "тот же текст мимо шаблона перечня — отказ (перечень, а не каталог)" "$(create 1189-newman2)"

branch 1189-script; printf '#!/usr/bin/env bash\necho ok\n' > "$box/run.sh"; chmod +x "$box/run.sh"; commit "#1189 скрипт" run.sh
expect_pass "исполняемый текстовый скрипт" "$(create 1189-script)"

branch 1189-edge; text exact.txt 1048576; commit "#1189 ровно 1 МБ" exact.txt
expect_pass "текст ровно 1 МБ — граница порога" "$(create 1189-edge)"

branch 1189-pub; cp "$ELF" "$box/pub"; commit "#1189 бинарь" pub
pgit -C "$box" push -q --no-verify origin 1189-pub
printf 'п\n' > "$box/after.md"; commit "#1189 дальше" after.md
expect_pass "бинарь уже опубликован на удалённом — уезжает лишь текст" \
    "refs/heads/1189-pub $(head_sha) refs/heads/1189-pub $(pgit -C "$box" rev-parse HEAD~1)"

expect_pass "снятие ветки" "(delete) $ZERO refs/heads/1189-pub $(pgit -C "$box" rev-parse HEAD~1)"

# ── Не судимо ────────────────────────────────────────────────────────────────
branch 1189-void; printf 'в\n' > "$box/v.md"; commit "#1189 текст" v.md
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$box/.git/refs/remotes/origin/broken"
examined=$((examined + 1)); unlawful=$((unlawful + 1))
code=0
(cd "$box" && HOME="$SANDBOX_GIT_HOME" bash scripts/hooks/prepush-added-files.sh origin < /dev/null > "$TMP/void.out" 2>&1) || code=$?
{ [ "$code" -eq 2 ] && grep -qF 'НЕ СУДИМО' "$TMP/void.out"; } ||
    fail "битая ссылка удалённого: страж вышел $code вместо 2 — пустой обход прошёл бы зелёным: $(tr '\n' ' ' < "$TMP/void.out")"
res="$(push "$(create 1189-void)")"
[ "$(head -1 <<< "$res")" -eq 1 ] || fail "битая ссылка удалённого: хук вышел $(head -1 <<< "$res") вместо 1"
rm -f "$box/.git/refs/remotes/origin/broken"

mv "$box/scripts/hooks/prepush-added-files.sh" "$TMP/guard.away"
expect_refuse "стража добавленных файлов нет" "стража нет рядом с хуком" "$(create 1189-void)"
mv "$TMP/guard.away" "$box/scripts/hooks/prepush-added-files.sh"

tooling_gate_census "$NAME: хук и страж осмотрены, проб по входу git $examined (законных $lawful, отвергаемых и не судимых $unlawful)"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "хук отвергает бинарь и файл больше 1 МБ среди добавленных новыми коммитами до наборов и называет файл; перечень с доводом и без предмета судится; законные близнецы проходят; пустой обход — не зелёный"
