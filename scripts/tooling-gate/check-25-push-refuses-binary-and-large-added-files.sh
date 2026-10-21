#!/usr/bin/env bash
# check-25 — хук отправки отвергает БИНАРЬ и файл БОЛЬШЕ 1 МБ среди НОВЫХ blob'ов
# отправки (любой статус файла) и называет файл (ws#1189).
#
# Признак: в kacho#3284 коммит ветки нёс собранный ELF края на 39 МБ; поймало
# его ревью, а не хук. Держатель — scripts/hooks/prepush-added-files.sh, который
# scripts/hooks/pre-push зовёт вторым, до обхода KACHO_SKIP_PREPUSH и до пропуска
# черновиков. Без поведенческой пробы детектор бинаря, порог или перепись
# истории ослабляются молча, и отправка продолжает проходить.
#
# ПОВЕДЕНЧЕСКАЯ, как check-18: песочница — настоящий репозиторий с голым
# удалённым, на который опубликован `main`; в её дереве — копии хука, стража
# атрибуции, стража новых blob'ов и прогонщик-заглушка, печатающий метку.
# Перечень исключений — СВОЙ у песочницы (строка коллекций newman с доводом):
# в перечне воркспейса строк нет, а исключение «про запас» истекло бы.
#
# ЧТО ТРЕБУЕТСЯ:
#   отказ (код 1, файл назван, наборы НЕ запускались):
#     настоящий исполняемый файл (копия `true`); бинарь без режима исполнения;
#     текст больше 1 МБ вне перечня; бинарь, добавленный и снятый следующим
#     коммитом; бинарь, внесённый руками в слияние; бинарь под строкой
#     `*.bin diff` в `.gitattributes`; бинарь в черновике `wip/*`; бинарь при
#     KACHO_SKIP_PREPUSH=1; законный файл рядом с бинарём (антимаска) —
#     ELF первой и последней из двух ссылок, первой, средней и последней из
#     трёх; путь глубже шаблона перечня (`*` не пересекает `/`): бинарь в
#     подкаталоге под `cert-manager-*.tgz`, коллекция в подкаталогах под
#     `services/*/…`; строка, чей предмет лежит лишь глубже каталогом;
#     строка перечня без предмета; строка перечня без довода; ELF и крупный
#     текст, переименованные с правкой (и при `diff.renames=copies`);
#     опубликованный текст, перезаписанный ELF либо раздутый за порог; ELF в
#     первом коммите отправки при тексте во втором; ELF при «* diff» в
#     `.git/info/attributes` и в `core.attributesFile`; ELF в корневом коммите
#     при `log.showRoot=false` без ссылок удалённого;
#   молчание (код 0): коллекция newman больше 1 МБ по строке перечня (законный
#     близнец); исполняемый текстовый скрипт; текст ровно 1 МБ; бинарь, уже
#     опубликованный на удалённом; снятие ветки; `git mv` крупного текста без
#     правки и его копия (нового blob'а нет — при любой `diff.renames`); правка
#     текста меньше порога; запись строки перечня с предметом; законные
#     строки перечня (`*` в имени, `**` через каталоги);
#   не судимо: ссылка удалённого битая — страж выходит 2, хук — 1; стража нет
#     рядом с хуком — хук отказывает кодом 1 и называет причину.
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
KIT=(pre-push prepush-attribution.sh attribution-rule.sh prepush-added-files.sh branch-name-rule.sh)

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
# ELF — по сигнатуре первых четырёх байт (\177 E L F), а не по `file`: в образе Job профиля ws
# (golang:1.26.9) утилиты file нет, и предпосылка там выходила VOID (ws#1304).
elf_magic="$( [ -z "$ELF" ] || od -An -c -N4 -- "$ELF" 2>/dev/null | tr -d ' \n')"
if [ "$elf_magic" != '177ELF' ]; then
    tooling_gate_void "$NAME" "настоящего исполняемого файла для инъекции нет (${ELF:-true не найден} — сигнатура «$elf_magic», не ELF)"
    exit 2
fi

TMP="$(mktemp -d)"
# shellcheck disable=SC2154
trap '_rc=$?; rm -rf "$TMP" 2>/dev/null || rm -rf "$TMP" || echo "ПРЕДУПРЕЖДЕНИЕ: временный каталог $TMP не снят; код проверки $_rc сохранён" >&2; exit $_rc' EXIT
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
# Опубликованное в main: малый текст, крупный текст и ELF — предметы правки,
# переименования и копии (ws#1189, приёмка r1).
printf 'старый текст\n' > "$box/old.txt"
head -c 1200000 /dev/zero | tr '\0' 'b' > "$box/big1.txt"
cp "$ELF" "$box/pub.bin"
# Свой вариант ELF (байт 300): копии `true` в пробах ниже остаются НОВЫМИ blob'ами.
printf '\001' | dd of="$box/pub.bin" bs=1 seek=300 conv=notrunc status=none
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
# Вид без утилиты file (образ Job профиля ws её не несёт, ws#1304): file на пути молчит и
# отказывает — вид по сигнатуре байт, отказ называет файл, а не трассировку.
nofile="$TMP/nofile-bin"; mkdir -p "$nofile"; printf '#!/bin/sh\nexit 127\n' > "$nofile/file"; chmod +x "$nofile/file"
expect_refuse "edge — исполняемый бинарь (ELF)" "file молчит — вид по сигнатуре, файл назван" "$(create 1189-elf)" PATH="$nofile:$PATH"

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
# Антимаска: судится КАЖДАЯ ссылка отправки на любой позиции входа — мутант
# «лишь последняя ссылка» молчал, пока законная шла первой, а ELF последним (ws#1194).
branch 1189-lawful3; printf 'т3\n' > "$box/n3.md"; commit "#1189 текст" n3.md
pgit -C "$box" checkout -q -f 1189-elf2
LA="refs/heads/1189-lawful $(pgit -C "$box" rev-parse 1189-lawful) refs/heads/1189-lawful $ZERO"
LB="refs/heads/1189-lawful3 $(pgit -C "$box" rev-parse 1189-lawful3) refs/heads/1189-lawful3 $ZERO"
EL="$(create 1189-elf2)"
expect_refuse edge "законная ветка первой, бинарь последним (антимаска)" "$LA
$EL"
expect_refuse edge "бинарь первым, законная ветка второй (антимаска)" "$EL
$LA"
expect_refuse edge "три ссылки: бинарь первым (антимаска)" "$EL
$LA
$LB"
expect_refuse edge "три ссылки: бинарь посередине (антимаска)" "$LA
$EL
$LB"
expect_refuse edge "три ссылки: бинарь последним (антимаска)" "$LA
$LB
$EL"

# Предмет — новый blob при любом статусе (приёмка r1): правка, переименование с
# правкой, перезапись опубликованного файла ELF, рост за порог; ELF в первом
# коммите отправки, текст — во втором.
flip() { printf '\001' | dd of="$box/$1" bs=1 seek=200 conv=notrunc status=none; }
branch 1189-renelf; pgit -C "$box" mv pub.bin renamed2.bin; flip renamed2.bin; commit "#1189 переименован с правкой" renamed2.bin
expect_refuse renamed2.bin "ELF переименован с правкой байта (R) — новый blob" "$(create 1189-renelf)"
pgit -C "$box" config diff.renames copies
expect_refuse renamed2.bin "то же при diff.renames=copies — вердикт от настройки не зависит" "$(create 1189-renelf)"
pgit -C "$box" config --unset diff.renames
branch 1189-renbig; pgit -C "$box" mv big1.txt big2.txt; printf 'x' >> "$box/big2.txt"; commit "#1189 крупный переименован с правкой" big2.txt
expect_refuse big2.txt "текст 1,2 МБ переименован с правкой (R) — новый blob" "$(create 1189-renbig)"
branch 1189-overelf; cp "$ELF" "$box/old.txt"; commit "#1189 перезапись" old.txt
expect_refuse old.txt "опубликованный old.txt перезаписан ELF (M)" "$(create 1189-overelf)"
branch 1189-grow; text old.txt 2097152; commit "#1189 рост" old.txt
expect_refuse old.txt "опубликованный old.txt раздут до 2 МБ (M)" "$(create 1189-grow)"
branch 1189-first; cp "$ELF" "$box/first.bin"; commit "#1189 бинарь первым" first.bin
printf 'т\n' > "$box/second.md"; commit "#1189 текст вторым" second.md
expect_refuse first.bin "ELF в первом коммите отправки, текст во втором" "$(create 1189-first)"
# Настройки пользователя вердикт не меняют: атрибуты вне дерева.
pgit -C "$box" checkout -q -f 1189-elf
mkdir -p "$box/.git/info"; printf '* diff\n' > "$box/.git/info/attributes"
expect_refuse edge "ELF при «* diff» в .git/info/attributes" "$(create 1189-elf)"
rm -f "$box/.git/info/attributes"
printf '* diff\n' > "$TMP/attrs"; pgit -C "$box" config core.attributesFile "$TMP/attrs"
expect_refuse edge "ELF при «* diff» в core.attributesFile" "$(create 1189-elf)"
pgit -C "$box" config --unset core.attributesFile

ALLOW="$box/scripts/hooks/prepush-added-files.allow"
cp "$ALLOW" "$TMP/allow"
branch 1189-lawful2; printf 'т\n' > "$box/n2.md"; commit "#1189 текст" n2.md
printf 'binary deploy/*.tgz архив чарта\n' >> "$ALLOW"
expect_refuse "deploy/*.tgz" "строка перечня без предмета" "$(create 1189-lawful2)"
cp "$TMP/allow" "$ALLOW"; printf 'size %s/*.json\n' "$COLL" >> "$ALLOW"
expect_refuse "без довода" "строка перечня без довода" "$(create 1189-lawful2)"
cp "$TMP/allow" "$ALLOW"

# ── Законные близнецы ────────────────────────────────────────────────────────
branch 1189-mv; pgit -C "$box" mv big1.txt big4.txt; commit "#1189 переименован без правки" big4.txt
expect_pass "git mv крупного текста без правки — blob прежний, опубликован" "$(create 1189-mv)"
branch 1189-copy; cp "$box/big1.txt" "$box/big3.txt"; commit "#1189 копия" big3.txt
expect_pass "копия опубликованного крупного текста — нового blob'а нет" "$(create 1189-copy)"
pgit -C "$box" config diff.renames copies
expect_pass "та же копия при diff.renames=copies — тот же исход" "$(create 1189-copy)"
pgit -C "$box" config --unset diff.renames
branch 1189-small; printf 'ещё строка\n' >> "$box/old.txt"; commit "#1189 правка" old.txt
expect_pass "правка текстового файла меньше порога" "$(create 1189-small)"
branch 1189-allow; printf 'size big1.txt крупный текст песочницы — опубликован в main\n' >> "$box/scripts/hooks/prepush-added-files.allow"
commit "#1189 строка перечня" scripts/hooks/prepush-added-files.allow
expect_pass "запись строки перечня исключений с предметом" "$(create 1189-allow)"
pgit -C "$box" checkout -q -f "$BASE" -- scripts/hooks/prepush-added-files.allow
branch 1189-newman; text "$COLL/b.postman_collection.json" 1500000; commit "#1189 коллекция" "$COLL/b.postman_collection.json"
expect_pass "коллекция newman больше 1 МБ по строке перечня — законный близнец" "$(create 1189-newman)"
branch 1189-newman2; text "$COLL/b.json" 1500000; commit "#1189 не коллекция" "$COLL/b.json"
expect_refuse "$COLL/b.json" "тот же текст мимо шаблона перечня — отказ (перечень, а не каталог)" "$(create 1189-newman2)"

# Шаблон перечня — посегментно: `*` не пересекает `/`, `**` — любое число каталогов (ws#1194).
CH="deploy/helm/umbrella/charts"
chart() { mkdir -p "$(dirname "$box/$1")"; printf 'TGZ\0%s\n' "$1" > "$box/$1"; }
CHART_LINE="binary $CH/cert-manager-*.tgz вендоренный чарт песочницы"
branch 1189-globok; chart "$CH/cert-manager-v1.tgz"; commit "#1189 чарт" "$CH/cert-manager-v1.tgz"
printf '%s\n' "$CHART_LINE" >> "$ALLOW"
expect_pass "чарт cert-manager-v1.tgz под строкой cert-manager-*.tgz — законная строка перечня" "$(create 1189-globok)"
printf 'binary deploy/*.tgz архив чарта\n' >> "$ALLOW"
expect_refuse "deploy/*.tgz" "строка deploy/*.tgz, чей предмет лишь глубже каталогом, — без предмета" "$(create 1189-globok)"
branch 1189-globch; chart "$CH/cert-manager-v1.tgz"; chart "$CH/cert-manager-x/evil.tgz"
commit "#1189 чарт и подкаталог" "$CH/cert-manager-v1.tgz" "$CH/cert-manager-x/evil.tgz"
printf '%s\n' "$CHART_LINE" >> "$ALLOW"
expect_refuse "$CH/cert-manager-x/evil.tgz" "бинарь в подкаталоге cert-manager-x/ под cert-manager-*.tgz — «*» не пересекает «/»" "$(create 1189-globch)"
branch 1189-globnm; mkdir -p "$box/services/a/b/tests/newman/collections/c"; text "services/a/b/tests/newman/collections/c/d.postman_collection.json" 1500000
commit "#1189 коллекция в подкаталогах" services/a/b/tests/newman/collections/c/d.postman_collection.json
expect_refuse "services/a/b/tests/newman/collections/c/d.postman_collection.json" \
    "крупный текст в подкаталогах под services/*/…/collections/*.postman_collection.json — «*» не пересекает «/»" "$(create 1189-globnm)"
branch 1189-globdeep; mkdir -p "$box/docs/a/b"; text docs/a/b/c.big.txt 1500000; text docs/top.big.txt 1500000
commit "#1189 крупный текст под **" docs/a/b/c.big.txt docs/top.big.txt
printf 'size docs/**/*.big.txt крупный текст песочницы\n' >> "$ALLOW"
expect_pass "строка docs/**/*.big.txt: «**» — любое число каталогов, и ни одного" "$(create 1189-globdeep)"
cp "$TMP/allow" "$ALLOW"

branch 1189-script; printf '#!/usr/bin/env bash\necho ok\n' > "$box/run.sh"; chmod +x "$box/run.sh"; commit "#1189 скрипт" run.sh
expect_pass "исполняемый текстовый скрипт" "$(create 1189-script)"

branch 1189-edge; text exact.txt 1048576; commit "#1189 ровно 1 МБ" exact.txt
expect_pass "текст ровно 1 МБ — граница порога" "$(create 1189-edge)"

branch 1189-pub; cp "$ELF" "$box/pub"; flip pub; printf '\002' | dd of="$box/pub" bs=1 seek=400 conv=notrunc status=none; commit "#1189 бинарь" pub
pgit -C "$box" push -q --no-verify origin 1189-pub
printf 'п\n' > "$box/after.md"; commit "#1189 дальше" after.md
expect_pass "бинарь уже опубликован на удалённом — уезжает лишь текст" \
    "refs/heads/1189-pub $(head_sha) refs/heads/1189-pub $(pgit -C "$box" rev-parse HEAD~1)"

expect_pass "снятие ветки" "(delete) $ZERO refs/heads/1189-pub $(pgit -C "$box" rev-parse HEAD~1)"

# ── Не судимо ────────────────────────────────────────────────────────────────
branch 1189-void; printf 'в\n' > "$box/v.md"; commit "#1189 текст" v.md
# Битая ссылка ставится git'ом, а не файлом в refs/: ссылки могут лежать
# упакованными (каталога refs/remotes/origin нет), а хранилище reftable файлов
# ссылок не читает. Ссылка ведёт на настоящий коммит, затем его свободный
# объект снимается — условие не зависит от того, как хранятся ссылки.
bsha="$(pgit -C "$box" commit-tree "$(pgit -C "$box" rev-parse 'HEAD^{tree}')" -m "#1189 битая ссылка")" &&
    pgit -C "$box" update-ref refs/remotes/origin/broken "$bsha" &&
    rm -f "$box/.git/objects/${bsha:0:2}/${bsha:2}" || bsha=""
if [ -z "$bsha" ] || pgit -C "$box" cat-file -e "$bsha" 2>/dev/null ||
    [ "$(pgit -C "$box" rev-parse -q --verify refs/remotes/origin/broken)" != "$bsha" ]; then
    tooling_gate_void "$NAME" "битая ссылка удалённого не создана (объект $bsha жив либо ссылки нет)"
    exit 2
fi
examined=$((examined + 1)); unlawful=$((unlawful + 1))
code=0
(cd "$box" && HOME="$SANDBOX_GIT_HOME" bash scripts/hooks/prepush-added-files.sh origin < /dev/null > "$TMP/void.out" 2>&1) || code=$?
{ [ "$code" -eq 2 ] && grep -qF 'НЕ СУДИМО' "$TMP/void.out"; } ||
    fail "битая ссылка удалённого: страж вышел $code вместо 2 — пустой обход прошёл бы зелёным: $(tr '\n' ' ' < "$TMP/void.out")"
res="$(push "$(create 1189-void)")"
[ "$(head -1 <<< "$res")" -eq 1 ] || fail "битая ссылка удалённого: хук вышел $(head -1 <<< "$res") вместо 1"
pgit -C "$box" update-ref -d refs/remotes/origin/broken

mv "$box/scripts/hooks/prepush-added-files.sh" "$TMP/guard.away"
expect_refuse "стража добавленных файлов нет" "стража нет рядом с хуком" "$(create 1189-void)"
mv "$TMP/guard.away" "$box/scripts/hooks/prepush-added-files.sh"

# Много новых blob'ов (больше буфера трубы на входе и выходе cat-file): страж
# завершается сам, а не встаёт насмерть (приёмка r1, весь репозиторий без ссылок).
branch 1189-many; mkdir -p "$box/many"
for i in $(seq 1 3000); do printf 'f%s\n' "$i" > "$box/many/$i.txt"; done
commit "#1189 много файлов" many
examined=$((examined + 1)); lawful=$((lawful + 1)); code=0
(cd "$box" && printf '%s\n' "$(create 1189-many)" | HOME="$SANDBOX_GIT_HOME" timeout 30 bash scripts/hooks/prepush-added-files.sh origin > "$TMP/many.out" 2>&1) || code=$?
[ "$code" -eq 0 ] || fail "3000 новых blob'ов: страж вышел $code вместо 0 (124 — встал насмерть): $(tail -c 300 "$TMP/many.out")"

# Корневой коммит при log.showRoot=false и без ссылок удалённого: судится вся история.
solo="$TMP/solo"; mkdir -p "$solo/g"; cp "$WS/scripts/hooks/prepush-added-files.sh" "$solo/g/"
pgit init -q -b main "$solo/r"; cp "$ELF" "$solo/r/root.bin"; pgit -C "$solo/r" add root.bin
pgit -C "$solo/r" commit -q -m "#1 корень"; pgit -C "$solo/r" config log.showRoot false
examined=$((examined + 1)); unlawful=$((unlawful + 1)); code=0
(cd "$solo/r" && HOME="$SANDBOX_GIT_HOME" bash "$solo/g/prepush-added-files.sh" origin < /dev/null > "$TMP/solo.out" 2>&1) || code=$?
{ [ "$code" -eq 1 ] && grep -qF 'root.bin' "$TMP/solo.out"; } ||
    fail "ELF в корневом коммите при log.showRoot=false: страж вышел $code вместо 1 либо не назвал root.bin: $(tr '\n' ' ' < "$TMP/solo.out" | head -c 300)"

tooling_gate_census "$NAME: хук и страж осмотрены, проб по входу git $examined (законных $lawful, отвергаемых и не судимых $unlawful)"
if [ "$findings" -gt 0 ]; then
    tooling_gate_fail "$NAME" "проб с находкой: $findings"
    exit 1
fi
tooling_gate_pass "$NAME" "хук отвергает бинарь и файл больше 1 МБ среди добавленных новыми коммитами до наборов и называет файл; перечень с доводом и без предмета судится; законные близнецы проходят; пустой обход — не зелёный"
