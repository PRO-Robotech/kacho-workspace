#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""branch-audit-mutants — СИСТЕМАТИЧЕСКАЯ мутация истории пути в переписи веток
(ws#995, круг 3).

Зачем: три круга приёмки подряд check-verifier находил выживший мутант одного
рода в одной и той же функции — сперва обход слияний, затем «только пост-образ
диффа» (mG) и «блобы не поднимаются к каталогам» (mH), — и каждый раз при
136/136 зелёных `branch-audit-inject.sh`. Точечные мутанты держат лишь то, о
чём автор догадался; здесь мутируется КАЖДАЯ строка кода трёх участков
`branch-audit.sh`, и полнота этого обхода проверяется, а не утверждается:

  RA  — `history_blobs_once` (обход истории всех стволов одним `git log`);
  RC  — набор стволов с индексом, предфильтр `hist.*` и вызов обхода;
  RB  — отступление: кандидаты, поштучный `git log --full-history` для путей
        без ответа и `--find-object` по стволам для ответа «?».

ПОРЧИ. Две формы:
  * авто — по каждой строке кода RA: простая инструкция → `pass` (снятие),
    заголовок `if/elif/while` → отрицание условия, заголовок `for` → пустой
    перебор; выводятся из исходника при каждом запуске, поэтому правка RA
    не оставляет новую строку без порчи;
  * ручные — подмена индекса, условия, множества, аргумента `git log`,
    снятие подъёма к каталогам и т.п. (MANUAL ниже), фрагмент ищется внутри
    своего участка и обязан встречаться в нём РОВНО один раз.

ПОЛНОТА. Строка кода участка, которую не меняет ни одна порча, — отказ
харнесса (код 1), а не «мутантов меньше». Не требуют порчи лишь строки чистого
синтаксиса (`fi`, `done`, `else`, `then`, скобки, `PY`, `try:`, `except …:`),
комментарии и пустые — их перечень STRUCTURAL.

ВЕРДИКТ ПОРЧИ. Каждая гонится через `branch-audit-inject.sh` против
испорченной копии (до первого красного — BRANCH_AUDIT_INJECT_FAILFAST=1;
`--full` — весь набор и все красные метки). УБИТА — набор вышел кодом 1
либо не завершился за предел BRANCH_AUDIT_MUTANTS_LIMIT (умолчание 1200 с;
исход назван отдельно — «зависание»: порча зациклила обход).
Убийство подтверждается ПОВТОРОМ набора: зелёный повтор — «НЕУСТОЙЧИВО»
(красное дала проба, зависящая от часов или нагрузки), и такая порча идёт к
доказательству эквивалентности как выжившая.
ВЫЖИЛА — код 0. Выжившая без доказательства эквивалентности — отказ (код 1).

ЭКВИВАЛЕНТНОСТЬ (--clone <путь>, можно несколько). Для клона снимается
замороженный снимок (ссылки heads/remotes/tags через alternates, origin —
недоступный путь, состояния PR — выдачей `gh pr list` в файл
BRANCH_AUDIT_PR_STATE_FILE; окно FRESH_MIN=0, NO_FETCH=1, ALL_FILES=1).
Эталон — НЕиспорченный `branch-audit.sh` с BRANCH_AUDIT_EXACT=1 на снимке.
Предпосылка: ускоренный режим НЕиспорченного скрипта даёт вывод, побайтово
равный эталону (иначе сверять порчу не с чем — отказ). Выжившая порча
эквивалентна, если её вывод на КАЖДОМ снимке `cmp`-равен эталону. Снимки и
эталон кэшируются в --work (ключ — отпечаток скрипта и ссылок снимка).

ИСХОДЫ: 0 — каждая порча убита либо доказанно эквивалентна; 1 — выжившая без
доказательства, расхождение с эталоном, отказ предпосылки или неполный обход;
2 — порч ноль.

Повтор с тем же эталоном: `--frozen <снимок>:<файл PR> --work <каталог>` —
снимок, снятый прежним --clone (каталог snap-<имя> и snap-<имя>.prs.tsv в
--work), эталон берётся из кэша --work.

Запуск (одной командой, из корня воркспейса):
  python3 scripts/branch-audit-mutants.py -j 4 \\
      --clone project/kacho --clone project/kaname
  python3 scripts/branch-audit-mutants.py --list     # перечень порч и покрытие
  python3 scripts/branch-audit-mutants.py RA12-del mG  # выбранные порчи
"""
import argparse
import concurrent.futures
import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "branch-audit.sh")
INJECT = os.path.join(HERE, "branch-audit-inject.sh")

# Участки: (имя, начало — строка целиком, конец — строка целиком, включительно).
REGIONS = [
    ("RA", "history_blobs_once() { # $1 = каталог ответов, далее — стволы → печатает число записанных ответов",
     "}"),
    ("RC", "IDXTR=()", '      : > "$BA_SHARED/fb.ok" &'),
    ("RB", '    : > "$BA_TMP/fo.cand"; : > "$BA_TMP/fo.hit"', '    REM=(${left[@]+"${left[@]}"})'),
]
# Строки RC, не относящиеся к истории пути (перечни стволов для других
# признаков): их держат свои пробы, полнота здесь их не требует.
RC_FOREIGN = re.compile(r'lst\.\$k|tl\.\$k|tr=\$\{TRUNKS\[\$k\]\}|for k in "\$\{!TRUNKS\[@\]\}"; do|^if \[ "\$EXACT" != 1 \]; then$')

STRUCTURAL = re.compile(
    r"^(fi|done|else|then|do|\(|\)|\) &|\{|\}|esac|PY|try:|else:|except OSError:|pass|"
    r"local -a need=\(\) needk=\(\) dirs=\(\)|local t key i|"
    r"history_blobs_once\(\) \{ .*|def run\(args\):|def printable\(p\):|import os, subprocess, sys|"
    r"while True:|done < <\($|while IFS= read -r line; do refuse.*)$")

# (id, участок, что портит, фрагмент, замена)
MANUAL = [
    # --- RA: обход истории одним git log
    ("mG", "RA", "блоб пути — только пост-образ диффа",
     "s.add(meta[2]); s.add(meta[3])", "s.add(meta[3])"),
    ("mG2", "RA", "блоб пути — только пре-образ диффа",
     "s.add(meta[2]); s.add(meta[3])", "s.add(meta[2])"),
    ("mG3", "RA", "пре-образ — поле режима вместо блоба",
     "s.add(meta[2]); s.add(meta[3])", "s.add(meta[0]); s.add(meta[3])"),
    ("mG4", "RA", "пост-образ — поле состояния вместо блоба",
     "s.add(meta[2]); s.add(meta[3])", "s.add(meta[2]); s.add(meta[4])"),
    ("mH", "RA", "блобы не поднимаются к каталогам",
     "            i = p.rfind(b'/')\n            if i <= 0:\n                break\n            p = p[:i]\n",
     "            break\n"),
    ("mH2", "RA", "подъём сразу к верхнему каталогу (find вместо rfind)",
     "            i = p.rfind(b'/')", "            i = p.find(b'/')"),
    ("mH3", "RA", "каталог с хвостовой косой",
     "            p = p[:i]", "            p = p[:i + 1]"),
    ("mH4", "RA", "граница подъёма: i < 0 вместо i <= 0",
     "            if i <= 0:", "            if i < 0:"),
    ("mH5", "RA", "подъём на один уровень, не выше",
     "            p = p[:i]\n        meta = None", "            p = p[:i]\n            s = blobs.setdefault(p, set()); s.add(meta[2]); s.add(meta[3]); break\n        meta = None"),
    ("mT1", "RA", "обход только первого ствола",
     "+ tips + ['--raw'", "+ tips[:1] + ['--raw'"),
    ("mT2", "RA", "обход только по первому родителю",
     "['git', 'log', '--no-show-signature']", "['git', 'log', '--no-show-signature', '--first-parent']"),
    ("mT3", "RA", "дифф слияния против каждого родителя (-m)",
     "'--diff-merges=off'", "'--diff-merges=separate'"),
    ("mT4", "RA", "--diff-merges=off снят (умолчание git log)",
     "'--diff-merges=off', ", ""),
    ("mT5", "RA", "поиск переименований включён",
     "'--no-renames', ", "'--find-renames', "),
    ("mT6", "RA", "--no-abbrev снят",
     "'--no-abbrev',\n", "\n"),
    ("mT7", "RA", "--no-show-signature снят",
     "'--no-show-signature'] + tips", "] + tips"),
    ("mT8", "RA", "запись коммита без метки C",
     "'--format=C%H'", "'--format=%H'"),
    ("mT9", "RA", "обход истории ограничен пустым образцом пути",
     "'--format=C%H', '--'])", "'--format=C%H', '--', ':(exclude)*'])"),
    ("mT10", "RA", "корень без диффа (log.showRoot=false)",
     "['git', 'log', '--no-show-signature']", "['git', '-c', 'log.showRoot=false', 'log', '--no-show-signature']"),
    ("mP1", "RA", "печатный путь: верхняя граница снята",
     "0x20 <= c <= 0x7e", "0x20 <= c"),
    ("mP2", "RA", "печатный путь: кавычка и обратная косая допущены",
     " and c not in (0x22, 0x5c)", ""),
    ("mP3", "RA", "печатный путь: пробел запрещён",
     "0x20 <= c <= 0x7e", "0x20 < c <= 0x7e"),
    ("mK1", "RA", "ключ: каталоги без префикса d",
     ".replace('/', '/d')", ".replace('/', '/')"),
    ("mK2", "RA", "ключ: файл в каталоге без префикса f",
     "+ '/f' +", "+ '/' +"),
    ("mK3", "RA", "ключ: файл в корне без префикса f",
     "else 'f' + s", "else s"),
    ("mK4", "RA", "ключ: первый каталог без префикса d",
     "key = ('d' + s[", "key = ('' + s["),
    ("mK5", "RA", "ключ: имя после первой косой, а не последней",
     "s[s.rfind('/') + 1:]", "s[s.find('/') + 1:]"),
    ("mW1", "RA", "нулевой блоб пишется в ответ",
     "                if b.strip('0'):", "                if True:"),
    ("mW2", "RA", "в ответе пост-образ — нулевой блоб",
     "% (b, b))", "% (b, '0' * 40))"),
    ("mW3", "RA", "в ответе пре-образ — нулевой блоб",
     "% (b, b))", "% ('0' * 40, b))"),
    ("mW4", "RA", "каталог ответа должен не существовать",
     "exist_ok=True", "exist_ok=False"),
    ("mW5", "RA", "ответ дописывается, а не пишется заново",
     "open(fn + '.once', 'w')", "open(fn + '.once', 'a')"),
    ("mW6", "RA", "блобы ответа без сортировки",
     "for b in sorted(bs):", "for b in bs:"),
    ("mW7", "RA", "ответ пишется лишь первому пути",
     "        written += 1\n", "        written += 1\n        break\n"),
    ("mW8", "RA", "ответ не публикуется переименованием (остаётся .once)",
     "os.replace(fn + '.once', fn)", "None"),
    ("mR1", "RA", "ведущий перевод строки записи не срезается",
     "        tok = tok[1:]", "        tok = tok"),
    ("mR2", "RA", "запись метаданных — по любой строке, а не по ':'",
     "    elif tok.startswith(b':'):", "    elif tok[:1] in (b':', b'C'):"),
    ("mR3", "RA", "нераспознанная запись пропускается молча",
     "        sys.exit('нераспознанная запись вывода git log')", "        continue"),
    ("mR4", "RA", "пустая запись — отказ",
     "    elif tok.startswith(b'C') or not tok:", "    elif tok.startswith(b'C'):"),
    ("mR5", "RA", "печатается число путей истории, а не записанных",
     "print(written)", "print(len(blobs))"),
    ("mE1", "RA", "отказ git log глушится — пустой обход",
     "check=True).stdout", "check=False).stdout"),
    # --- RC: стволы с индексом, предфильтр hist.*, вызов обхода
    ("cI1", "RC", "стволы без индекса тоже в обходе",
     '[ -z "${TRUNK_IDX[$tr]+x}" ] || IDXTR+=("$tr")', 'IDXTR+=("$tr")'),
    ("cI2", "RC", "в обходе лишь первый ствол",
     '[ -z "${TRUNK_IDX[$tr]+x}" ] || IDXTR+=("$tr"); done', '[ -z "${TRUNK_IDX[$tr]+x}" ] || IDXTR+=("$tr"); break; done'),
    ("cH1", "RC", "предфильтр: только пост-образ",
     "for (x = 3; x <= 4; x++)", "for (x = 4; x <= 4; x++)"),
    ("cH2", "RC", "предфильтр: только пре-образ",
     "for (x = 3; x <= 4; x++)", "for (x = 3; x <= 3; x++)"),
    ("cH3", "RC", "предфильтр: нулевой блоб не отсеивается",
     "if (a[x] !~ /^0+$/) {", "if (1) {"),
    ("cH4", "RC", "предфильтр: пары не пишутся",
     '                   if (!((p, a[x]) in pr)) { pr[p, a[x]] = 1; print p "\\t" a[x] > (d ".pairs") }\n',
     ""),
    ("cH5", "RC", "предфильтр: блобы истории не пишутся",
     '                   if (!(a[x] in oi)) { oi[a[x]] = 1; print a[x] > (d ".oids") } }\n',
     "                   }\n"),
    ("cH6", "RC", "предфильтр: каталоги не пишутся",
     'if (q in di) break; di[q] = 1; print q > (d ".dirs") }', 'if (q in di) break; di[q] = 1 }'),
    ("cH7", "RC", "предфильтр: каталоги не повторяются (снят отсев повтора)",
     "if (q in di) break; ", ""),
    ("cH8", "RC", "предфильтр: только ближайший каталог",
     'while ((i = cut(q)) > 0) { q = substr(q, 1, i - 1);', 'if ((i = cut(q)) > 0) { q = substr(q, 1, i - 1);'),
    ("cH9", "RC", "предфильтр: переименование читается одной строкой пути",
     'left = (a[5] ~ /^[RC]/) ? 2 : 1', 'left = 1'),
    ("cH10", "RC", "предфильтр: последняя косая — первая",
     "function cut(s,  i, j) { j = 0; while ((i = index(substr(s, j + 1), \"/\")) > 0) j += i; return j }",
     "function cut(s,  i, j) { return index(s, \"/\") }"),
    ("cH11", "RC", "предфильтр: путь не читается (left не взводится)",
     "/^:/ { split($0, a, \" \"); left = (a[5] ~ /^[RC]/) ? 2 : 1; next }", "/^:/ { split($0, a, \" \"); next }"),
    ("cH12", "RC", "предфильтр: файлы не создаются пустыми при пустой истории",
     '          END { printf "" > (d ".pairs"); printf "" > (d ".oids"); printf "" > (d ".dirs") }\' &&',
     "          END { }' &&"),
    ("cH13", "RC", "предфильтр: метка готовности не ставится",
     '        : > "$BA_SHARED/hist.ok"', '        :'),
    ("cH14", "RC", "предфильтр: без --no-renames",
     'git log "${IDXTR[@]}" --raw --no-renames', 'git log "${IDXTR[@]}" --raw'),
    ("cH15", "RC", "предфильтр: только первый родитель",
     'git log "${IDXTR[@]}" --raw', 'git log --first-parent "${IDXTR[@]}" --raw'),
    ("cH16", "RC", "предфильтр не строится вовсе",
     '  if [ "${#IDXTR[@]}" -gt 0 ]; then\n    (\n', '  if false; then\n    (\n'),
    ("cF1", "RC", "обход не зовётся",
     '    history_blobs_once "$BA_SHARED/ans/fb" "${IDXTR[@]}" > "$BA_SHARED/fb.n" 2>/dev/null &&',
     "    false &&"),
    ("cF2", "RC", "метка готовности обхода не ставится",
     '      : > "$BA_SHARED/fb.ok" &', '      : &'),
    ("cF3", "RC", "каталог ответов не создаётся заранее",
     '    mkdir -p "$BA_SHARED/ans/fb"\n', ""),
    ("cF4", "RC", "обход зовётся и без python3",
     ' && command -v python3 >/dev/null 2>&1; then\n    mkdir', '; then\n    mkdir'),
    ("cF5", "RC", "обход зовётся при пустом перечне стволов",
     '  if [ "${#IDXTR[@]}" -gt 0 ] && command -v python3', '  if command -v python3'),
    ("cF6", "RC", "обход — лишь по первому стволу перечня",
     '"$BA_SHARED/ans/fb" "${IDXTR[@]}" >', '"$BA_SHARED/ans/fb" "${IDXTR[0]}" >'),
    # --- RB: отступление
    ("bC1", "RB", "файлы кандидатов не обнуляются между заданиями",
     '    : > "$BA_TMP/fo.cand"; : > "$BA_TMP/fo.hit"', '    :'),
    ("bC2", "RB", "удалённый файл (пустой блоб) — тоже кандидат",
     '      [ -n "${BBV[$f]}" ] || continue\n', ""),
    ("bC3", "RB", "ключ ответа не пересчитывается по файлу",
     '      ba_key_of "$f"\n', ""),
    ("bC4", "RB", "в кандидате блоб пуст",
     "printf '%s\\t%s\\t%s\\n' \"$f\" \"${BBV[$f]}\" \"$BA_KEY\"", "printf '%s\\t%s\\t%s\\n' \"$f\" \"\" \"$BA_KEY\""),
    ("bC5", "RB", "отступление без стволов",
     'local -a idxtr=(${IDXTR[@]+"${IDXTR[@]}"})', "local -a idxtr=()"),
    ("bF1", "RB", "предфильтр: пары не учитываются",
     '((($1 "\\t" $2) in pr) || (($1 in di) && ($2 in oi)))', '((($1 in di) && ($2 in oi)))'),
    ("bF2", "RB", "предфильтр: каталоги не учитываются",
     '((($1 "\\t" $2) in pr) || (($1 in di) && ($2 in oi)))', '((($1 "\\t" $2) in pr))'),
    ("bF3", "RB", "предфильтр: каталог без проверки блоба",
     '(($1 in di) && ($2 in oi))', '($1 in di)'),
    ("bF4", "RB", "предфильтр: блоб без проверки каталога",
     '(($1 in di) && ($2 in oi))', '($2 in oi)'),
    ("bF5", "RB", "предфильтр есть — но не применяется (все кандидаты)",
     '    if [ -e "$BA_SHARED/hist.ok" ]; then', '    if false; then'),
    ("bF6", "RB", "предфильтра нет — кандидатов ноль",
     '      cp "$BA_TMP/fo.cand" "$BA_TMP/fo.hit"', '      :'),
    ("bF7", "RB", "предфильтр: файлы пар и каталогов перепутаны",
     '"$BA_SHARED/hist.pairs" "$BA_SHARED/hist.oids" "$BA_SHARED/hist.dirs" "$BA_TMP/fo.cand"',
     '"$BA_SHARED/hist.dirs" "$BA_SHARED/hist.oids" "$BA_SHARED/hist.pairs" "$BA_TMP/fo.cand"'),
    ("bF8", "RB", "предфильтр: пары читаются как блобы",
     "        FILENAME == ARGV[1] { pr[$0] = 1; next }", "        FILENAME == ARGV[1] { oi[$0] = 1; next }"),
    ("bF9", "RB", "предфильтр: блобы не читаются",
     "        FILENAME == ARGV[2] { oi[$0] = 1; next }", "        FILENAME == ARGV[2] { next }"),
    ("bF10", "RB", "предфильтр: каталоги не читаются",
     "        FILENAME == ARGV[3] { di[$0] = 1; next }", "        FILENAME == ARGV[3] { next }"),
    ("bQ1", "RB", "вопросы без отсева повторов (cat вместо sort -u)",
     '    LC_ALL=C sort -u "$BA_TMP/fo.hit" > "$BA_TMP/fo.q"', '    cat "$BA_TMP/fo.hit" > "$BA_TMP/fo.q"'),
    ("bQ2", "RB", "вопросы не задаются",
     '    if [ -s "$BA_TMP/fo.q" ]; then', '    if false; then'),
    ("bN1", "RB", "путь с ответом тоже спрашивается поштучно",
     '        [ -e "$BA_SHARED/ans/fb/$key.b" ] || { need+=("$f"); needk+=("$key"); }',
     '        need+=("$f"); needk+=("$key")'),
    ("bN2", "RB", "путь без ответа поштучно не спрашивается",
     '        [ -e "$BA_SHARED/ans/fb/$key.b" ] || { need+=("$f"); needk+=("$key"); }', '        :'),
    ("bN3", "RB", "поштучных вопросов нет вовсе",
     '      if [ "${#need[@]}" -gt 0 ]; then', '      if false; then'),
    ("bN4", "RB", "каталоги ответов поштучной формы не перечисляются",
     '        for key in "${needk[@]}"; do case "$key" in */*) dirs+=("$BA_SHARED/ans/fb/${key%/*}") ;; esac; done\n', ""),
    ("bN5", "RB", "каталог ответа — сам ключ, а не его каталог",
     'dirs+=("$BA_SHARED/ans/fb/${key%/*}")', 'dirs+=("$BA_SHARED/ans/fb/$key")'),
    ("bN6", "RB", "каталоги ответов не создаются",
     '        mkdir -p "$BA_SHARED/ans/fb" ${dirs[@]+"${dirs[@]}"} 2>/dev/null || true\n', ""),
    ("bN7", "RB", "поштучно — лишь первый путь",
     '        for i in "${!need[@]}"; do', '        for i in 0; do'),
    ("bN8", "RB", "путь — от соседнего ключа (сдвиг индекса)",
     '          f=${need[$i]}; key=${needk[$i]}', '          f=${need[$i]}; key=${needk[$((i + 1))]}'),
    ("bN9", "RB", "готовый ответ спрашивается повторно",
     '          [ ! -e "$BA_SHARED/ans/fb/$key.b" ] || continue\n', ""),
    ("bN10", "RB", "счёт поштучных вопросов не ведётся (история пути)",
     '          FO_CALLS=$((FO_CALLS + 1))\n          # Имя', '          # Имя'),
    ("bN11", "RB", "временный файл ответа — общий для всех заданий",
     '          t="$BA_SHARED/ans/fb/$key.b.$BASHPID"', '          t="$BA_SHARED/ans/fb/tmp.b"'),
    ("bN12", "RB", "поштучно — упрощение истории по пути (без --full-history)",
     'git log "${idxtr[@]}" --full-history --raw', 'git log "${idxtr[@]}" --raw'),
    ("bN13", "RB", "поштучно — только первый ствол",
     'git log "${idxtr[@]}" --full-history', 'git log "${idxtr[0]}" --full-history'),
    ("bN14", "RB", "поштучно — с поиском переименований",
     '--full-history --raw --no-abbrev --no-renames --format=', '--full-history --raw --no-abbrev --find-renames --format='),
    ("bN15", "RB", "поштучно — сокращённые блобы",
     '--full-history --raw --no-abbrev --no-renames', '--full-history --raw --no-renames'),
    ("bN16", "RB", "поштучно — дифф слияния против каждого родителя",
     '--full-history --raw --no-abbrev --no-renames --format= -- "$f"', '--full-history -m --raw --no-abbrev --no-renames --format= -- "$f"'),
    ("bN17", "RB", "поштучно — только первый родитель",
     '--full-history --raw --no-abbrev --no-renames --format= -- "$f"', '--full-history --first-parent --raw --no-abbrev --no-renames --format= -- "$f"'),
    ("bN18", "RB", "ответ поштучной формы не публикуется",
     '            mv -f -T "$t" "$BA_SHARED/ans/fb/$key.b" 2>/dev/null || rm -f "$t"', '            rm -f "$t"'),
    ("bN19", "RB", "отказ git log публикуется как ответ",
     '            rm -f "$t" 2>/dev/null || true\n', '            mv -f -T "$t" "$BA_SHARED/ans/fb/$key.b" 2>/dev/null || true\n'),
    ("bR1", "RB", "найденный по ответу не отмечается",
     '        if [ "$t" = + ]; then FOUND["$f"]=1; continue; fi', '        if [ "$t" = + ]; then continue; fi'),
    ("bR2", "RB", "найденный по ответу ещё и спрашивается по стволам",
     '        if [ "$t" = + ]; then FOUND["$f"]=1; continue; fi', '        if [ "$t" = + ]; then FOUND["$f"]=1; fi'),
    ("bR3", "RB", "счёт промахов не ведётся",
     '        FO_MISS=$((FO_MISS + 1))\n', ""),
    ("bR4", "RB", "по стволам — лишь первый",
     '        for tr in "${idxtr[@]}"; do\n          FO_CALLS', '        for tr in "${idxtr[0]}"; do\n          FO_CALLS'),
    ("bR5", "RB", "счёт вопросов по стволам не ведётся",
     '          FO_CALLS=$((FO_CALLS + 1))\n          if [ -n "$(git log', '          if [ -n "$(git log'),
    ("bR6", "RB", "вопрос по стволу без --find-object (любой коммит пути)",
     '--format=%H --find-object="$bb" -- "$f"', '--format=%H -- "$f"'),
    ("bR7", "RB", "вопрос по стволу без пути",
     '--find-object="$bb" -- "$f" 2>/dev/null', '--find-object="$bb" 2>/dev/null'),
    ("bR8", "RB", "найденный по стволу не отмечается",
     '            FOUND["$f"]=1; break', '            break'),
    ("bR9", "RB", "после находки по стволу перебор продолжается",
     '            FOUND["$f"]=1; break', '            FOUND["$f"]=1'),
    ("bR10", "RB", "вопрос по стволу: пустой ответ — находка",
     'if [ -n "$(git log "$tr"', 'if [ -z "$(git log "$tr"'),
    ("bA1", "RB", "читатель ответа: только пост-образ",
     "if (a[3] == bb || a[4] == bb)", "if (a[4] == bb)"),
    ("bA2", "RB", "читатель ответа: только пре-образ",
     "if (a[3] == bb || a[4] == bb)", "if (a[3] == bb)"),
    ("bA3", "RB", "читатель ответа: поле режима вместо пре-образа",
     "if (a[3] == bb || a[4] == bb)", "if (a[1] == bb || a[4] == bb)"),
    ("bA4", "RB", "читатель ответа: строки без ':' не отсеиваются",
     '              if (substr(line, 1, 1) != ":") continue\n', ""),
    ("bA5", "RB", "читатель ответа: найденное не прерывает чтение",
     "{ hit = 1; break }", "{ hit = 1 }"),
    ("bA6", "RB", "читатель ответа: файл не закрывается",
     "            close(p)\n", ""),
    ("bA7", "RB", "читатель ответа: «?» и для прочитанного ответа без находки",
     'else if (r < 0) print "?\\t" f "\\t" bb', 'else print "?\\t" f "\\t" bb'),
    ("bA8", "RB", "читатель ответа: путь без ответа — не найден, без вопроса",
     'else if (r < 0) print "?\\t" f "\\t" bb', 'else if (0) print "?\\t" f "\\t" bb'),
    ("bA9", "RB", "читатель ответа: находка не печатается",
     'if (hit) print "+\\t" f;', 'if (0) print "+\\t" f;'),
    ("bA10", "RB", "читатель ответа: ключ — путь, а не ключ файла",
     '{ f = $1; bb = $2; p = d $3 ".b"; hit = 0', '{ f = $1; bb = $2; p = d $1 ".b"; hit = 0'),
    ("bA11", "RB", "читатель ответа: блоб — из колонки ключа",
     '{ f = $1; bb = $2; p = d $3 ".b"; hit = 0', '{ f = $1; bb = $3; p = d $3 ".b"; hit = 0'),
    ("bA12", "RB", "читатель ответа: только первая строка ответа",
     "            while ((r = (getline line < p)) > 0) {", "            if ((r = (getline line < p)) > 0) {"),
    ("bL1", "RB", "найденные не снимаются с остатка",
     '    for f in "${REM[@]}"; do [ -n "${FOUND[$f]+x}" ] || left+=("$f"); done', '    left=("${REM[@]}")'),
    ("bL2", "RB", "остаток обнуляется",
     '    for f in "${REM[@]}"; do [ -n "${FOUND[$f]+x}" ] || left+=("$f"); done', '    :'),
    ("bL3", "RB", "остаток не переписывается",
     '    REM=(${left[@]+"${left[@]}"})', '    :'),
    # --- строки, которым порча нужна сверх перечисленных выше
    ("mA1", "RA", "обход получает лишь каталог ответов (стволов нет — история HEAD)",
     """  python3 - "$@" <<'PY'""", """  python3 - "$1" <<'PY'"""),
    ("cI3", "RC", "в перечне стволов изначально HEAD",
     "IDXTR=()", "IDXTR=(HEAD)"),
    ("cH17", "RC", "предфильтр: разбор не в C-локали",
     "      git log \"${IDXTR[@]}\" --raw --no-renames --no-abbrev --format= -z 2>/dev/null |\n        LC_ALL=C awk",
     "      git log \"${IDXTR[@]}\" --raw --no-renames --no-abbrev --format= -z 2>/dev/null |\n        awk"),
    ("cH18", "RC", "предфильтр: записи разделяются переводом строки",
     'BEGIN { RS = "\\0" }', 'BEGIN { RS = "\\n" }'),
    ("cH19", "RC", "предфильтр: счётчик путей записи не убывает",
     "left > 0 { left--; p = $0", "left > 0 { p = $0"),
    ("cH20", "RC", "предфильтр: подъём начинается с пустого пути",
     "                 q = p\n", "                 q = \"\"\n"),
    ("bC6", "RB", "кандидат — лишь первый файл остатка",
     '    for f in "${REM[@]}"; do\n      [ -n', '    for f in "${REM[0]}"; do\n      [ -n'),
    ("bF11", "RB", "предфильтр отступления: разбор не в C-локали",
     "    if [ -e \"$BA_SHARED/hist.ok\" ]; then\n      LC_ALL=C awk", "    if [ -e \"$BA_SHARED/hist.ok\" ]; then\n      awk"),
    ("bN20", "RB", "поля вопроса перепутаны (ключ ↔ блоб)",
     "      while IFS=$'\\t' read -r f bb key; do", "      while IFS=$'\\t' read -r f key bb; do"),
    ("bN21", "RB", "вопросы не читаются",
     '      done < "$BA_TMP/fo.q"', '      done < /dev/null'),
    ("bR11", "RB", "поля ответа читателя перепутаны (путь ↔ блоб)",
     "      while IFS=$'\\t' read -r t f bb; do", "      while IFS=$'\\t' read -r t bb f; do"),
    ("bA13", "RB", "читатель ответа: разбор не в C-локали",
     "        LC_ALL=C awk -F'\\t' -v d=", "        awk -F'\\t' -v d="),
    ("bA14", "RB", "читатель ответа: поля строки — по табуляции",
     '              split(line, a, " ")', '              split(line, a, "\\t")'),
    ("bL4", "RB", "остаток начинается со всего прежнего остатка",
     "    local -a left=()", '    local -a left=("${REM[@]}")'),
]


def regions(src):
    """→ {имя: (начало, конец)} — смещения строк в списке строк исходника."""
    lines = src.split("\n")
    out = {}
    for name, start, end in REGIONS:
        s = [i for i, ln in enumerate(lines) if ln == start]
        if len(s) != 1:
            raise SystemExit(f"mutants: ПРЕДПОСЫЛКА — начало участка {name} встречается {len(s)} раз")
        e = next((i for i in range(s[0] + 1, len(lines)) if lines[i] == end), None)
        if e is None:
            raise SystemExit(f"mutants: ПРЕДПОСЫЛКА — конца участка {name} нет")
        out[name] = (s[0], e)
    return lines, out


def is_code(name, ln):
    t = ln.strip()
    if not t or t.startswith("#"):
        return False
    if STRUCTURAL.match(t):
        return False
    if name == "RC" and RC_FOREIGN.search(t):
        return False
    return True


def auto_mutants(lines, reg):
    """По каждой строке кода RA (тело python): снятие / отрицание / пустой перебор."""
    s, e = reg["RA"]
    body = [(i, lines[i]) for i in range(s, e + 1)]
    out = []
    in_py = False
    cont = False
    for i, ln in body:
        if ln.startswith("  python3 - ") and ln.endswith("<<'PY'"):
            in_py = True
            continue
        if ln == "PY":
            in_py = False
            continue
        if not in_py:
            continue
        t = ln.strip()
        ind = ln[: len(ln) - len(ln.lstrip())]
        if cont:  # продолжение многострочной инструкции порчу получает вместе с началом
            cont = ln.rstrip().endswith(",")
            continue
        if not t or t.startswith("#") or STRUCTURAL.match(t) or t == "pass":
            continue
        tag = f"RA{i - s}"
        m = re.match(r"(if|elif|while) (.*):$", t)
        if m:
            out.append((tag + "-neg", "RA", f"условие отрицается: {t}", ln, f"{ind}{m.group(1)} not ({m.group(2)}):", i))
            continue
        m = re.match(r"for (.*) in (.*):$", t)
        if m:
            out.append((tag + "-empty", "RA", f"перебор пуст: {t}", ln, f"{ind}for {m.group(1)} in ():", i))
            continue
        if t.startswith(("def ", "with ", "try:", "except", "else:")):
            continue
        if ln.rstrip().endswith(","):  # многострочная инструкция: снимается целиком
            j = i
            while lines[j].rstrip().endswith(","):
                j += 1
            whole = "\n".join(lines[i: j + 1])
            lhs = t.split("=", 1)[0].strip() if "=" in t.split("(", 1)[0] else None
            repl = f"{ind}{lhs} = b''" if lhs else f"{ind}pass"
            out.append((tag + "-del", "RA", f"снята инструкция: {t[:60]}…", whole, repl, i))
            cont = True
            continue
        if t.startswith("return "):
            out.append((tag + "-del", "RA", f"снята инструкция: {t}", ln, f"{ind}return None", i))
            continue
        out.append((tag + "-del", "RA", f"снята инструкция: {t}", ln, f"{ind}pass", i))
    return out


def apply(src, lines, reg, m):
    """→ испорченный исходник и номера тронутых строк (0-based) либо исключение."""
    mid, rname, _, frag, repl, at = m
    s, e = reg[rname]
    if at is not None:  # авто-порча — по номеру строки: одинаковые строки не путаются
        k = frag.count("\n") + 1
        if "\n".join(lines[at: at + k]) != frag:
            raise ValueError(f"{mid}: строка {at + 1} не та, что выведена")
        out = "\n".join(lines[:at] + [repl] + lines[at + k:])
        return out, set(range(at, at + k))
    region = "\n".join(lines[s: e + 1])
    n = region.count(frag)
    if n != 1:
        raise ValueError(f"{mid}: фрагмент встречается в участке {rname} {n} раз")
    new_region = region.replace(frag, repl, 1)
    if new_region == region:
        raise ValueError(f"{mid}: порча ничего не меняет")
    off = region.index(frag)
    first = s + region[:off].count("\n")
    last = first + frag.count("\n") - (1 if frag.endswith("\n") else 0)
    out = "\n".join(lines[:s] + [new_region] + lines[e + 1:])
    return out, set(range(first, last + 1))


# Набор против НЕиспорченного скрипта идёт ~2 мин (под нагрузкой машины — до
# ~10). Порча, зациклившая обход, набор не завершает: такой набор снимается по
# пределу всей группой процессов и считается УБИВШИМ порчу с меткой
# «зависание» — зависший CI виден так же, как красный, но это иной исход, и он
# назван отдельно, а не смешан с кодом 1.
INJECT_LIMIT = int(os.environ.get("BRANCH_AUDIT_MUTANTS_LIMIT", "1200"))


def run_inject(path, tmp, failfast=False):
    env = dict(os.environ, TMPDIR=tmp)
    if failfast:
        env["BRANCH_AUDIT_INJECT_FAILFAST"] = "1"
    p = subprocess.Popen(["bash", INJECT, path], env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=INJECT_LIMIT)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        return "hang", ["зависание"], f"набор не завершился за {INJECT_LIMIT} с"
    reds = sorted({ln.split()[1] for ln in out.splitlines() if ln.startswith("❌ ")})
    tail = out.strip().splitlines()[-1] if out.strip() else ""
    return p.returncode, reds, tail


FILTER = re.compile(r"^branch-audit: (замер|параллельных заданий|время прогона|ускорение|дольше всех)")


def audit_on(script, snap, prs, env_extra, tmp):
    env = dict(os.environ, TMPDIR=tmp, BRANCH_AUDIT_ALL_FILES="1", BRANCH_AUDIT_NO_FETCH="1",
               BRANCH_AUDIT_FRESH_MIN="0", BRANCH_AUDIT_PR_STATE_FILE=prs, **env_extra)
    env.pop("GH_TOKEN", None)
    p = subprocess.run(["bash", script, snap], cwd=snap, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=6 * 3600)
    text = b"\n".join(ln for ln in p.stdout.split(b"\n") if not FILTER.match(ln.decode("utf-8", "replace")))
    return p.returncode, text


def snapshot(clone, work):
    """Замороженный снимок клона: heads/remotes/tags через alternates, рабочее дерево main."""
    clone = os.path.abspath(clone)
    name = os.path.basename(clone.rstrip("/"))
    gd = subprocess.run(["git", "-C", clone, "rev-parse", "--absolute-git-dir"], stdout=subprocess.PIPE,
                        text=True, check=True).stdout.strip()
    common = subprocess.run(["git", "-C", clone, "rev-parse", "--git-common-dir"], stdout=subprocess.PIPE,
                            text=True, check=True).stdout.strip()
    common = os.path.join(clone, common) if not os.path.isabs(common) else common
    snap = os.path.join(work, "snap-" + name)
    prs = snap + ".prs.tsv"
    if not os.path.isdir(snap):
        subprocess.run(["git", "init", "-q", "-b", "main", snap], check=True)
        with open(os.path.join(snap, ".git/objects/info/alternates"), "w") as f:
            f.write(os.path.join(common, "objects") + "\n")
        subprocess.run(["git", "-C", snap, "fetch", "-q", "--no-tags", "--update-head-ok", clone,
                        "+refs/heads/*:refs/heads/*", "+refs/remotes/origin/*:refs/remotes/origin/*",
                        "+refs/tags/*:refs/tags/*"], check=True)
        subprocess.run(["git", "-C", snap, "remote", "add", "origin", "/nonexistent/" + name + ".git"], check=True)
        subprocess.run(["git", "-C", snap, "checkout", "-q", "-f", "main"], check=True)
        with open(prs, "w") as f:
            subprocess.run(["gh", "pr", "list", "--state", "all", "--limit", "5000", "--json",
                            "number,state,headRefName,isCrossRepository,baseRefName", "--jq",
                            '.[]|"\\(.headRefName)\\t\\(.number)\\t\\(.state)\\t\\(.isCrossRepository)\\t\\(.baseRefName)"'],
                           cwd=clone, stdout=f, check=True)
    del gd
    refs = subprocess.run(["git", "-C", snap, "for-each-ref", "--format=%(objectname) %(refname)"],
                          stdout=subprocess.PIPE, check=True).stdout
    nrefs = refs.count(b"\n")
    return name, snap, prs, hashlib.sha256(refs + open(prs, "rb").read()).hexdigest()[:16], nrefs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=4, help="наборов инъекции одновременно")
    ap.add_argument("--clone", action="append", default=[], help="клон для доказательства эквивалентности")
    ap.add_argument("--frozen", action="append", default=[],
                    help="готовый снимок <каталог>:<файл состояний PR> (как делает --clone) — "
                         "чтобы повторный прогон сверял с тем же эталоном")
    ap.add_argument("--work", default=None, help="каталог снимков и эталонов (кэш)")
    ap.add_argument("--list", action="store_true", help="перечень порч и покрытие, без прогона")
    ap.add_argument("--no-control", action="store_true", help="не гнать контрольный набор (только для отладки)")
    ap.add_argument("--full", action="store_true",
                    help="весь набор на каждую порчу (все красные метки), а не до первого красного")
    ap.add_argument("--no-confirm", action="store_true",
                    help="не повторять набор у убитой порчи (только для отладки)")
    ap.add_argument("ids", nargs="*")
    a = ap.parse_args()

    src = open(AUDIT, encoding="utf-8").read()
    lines, reg = regions(src)
    allm = [m + (None,) for m in MANUAL] + auto_mutants(lines, reg)
    ids = [m[0] for m in allm]
    dup = {x for x in ids if ids.count(x) > 1}
    if dup:
        print("mutants: ПРЕДПОСЫЛКА — повтор имени порчи: " + ", ".join(sorted(dup)))
        return 1

    # Полнота: каждая строка кода участков тронута хотя бы одной порчей.
    covered = {}
    broken = []
    built = {}
    for m in allm:
        try:
            out, touched = apply(src, lines, reg, m)
        except ValueError as ex:
            broken.append(str(ex))
            continue
        built[m[0]] = out
        for t in touched:
            covered.setdefault(t, []).append(m[0])
    if broken:
        print("mutants: ПРЕДПОСЫЛКА — порча не легла:\n  " + "\n  ".join(broken))
        return 1
    uncovered = []
    ncode = 0
    for name, (s, e) in reg.items():
        for i in range(s, e + 1):
            if is_code(name, lines[i]):
                ncode += 1
                if i not in covered:
                    uncovered.append(f"{name} строка {i + 1}: {lines[i].strip()[:100]}")
    print(f"mutants: участков {len(reg)}, строк кода {ncode}, порч {len(allm)} "
          f"(ручных {len(MANUAL)}, авто {len(allm) - len(MANUAL)}), строк без порчи {len(uncovered)}")
    if uncovered:
        print("mutants: ОБХОД НЕПОЛОН — строки кода без порчи:\n  " + "\n  ".join(uncovered))
        return 1
    if a.list:
        for m in allm:
            print(f"{m[0]}\t{m[1]}\t{m[2]}")
        return 0

    todo = [m for m in allm if not a.ids or m[0] in a.ids]
    if not todo:
        print("mutants: порч ноль — проверено ничего")
        return 2

    root = tempfile.mkdtemp(prefix="branch-audit-mutants-")
    work = os.path.abspath(a.work) if a.work else os.path.join(root, "work")
    os.makedirs(work, exist_ok=True)
    try:
        if not a.no_control:
            rc, reds, tail = run_inject(AUDIT, tempfile.mkdtemp(dir=root))
            print(f"контроль: код {rc} · {tail}")
            if rc != 0:
                print("mutants: ПРЕДПОСЫЛКА — набор против НЕиспорченного скрипта не зелёный: " + " ".join(reds))
                return 1

        def one(m):
            d = tempfile.mkdtemp(prefix=f"mut-{m[0]}-", dir=root)
            path = os.path.join(d, "branch-audit.sh")
            with open(path, "w", encoding="utf-8") as f:
                f.write(built[m[0]])
            os.chmod(path, 0o755)
            rc, reds, tail = run_inject(path, d, failfast=not a.full)
            if rc in (1, "hang") and not a.no_confirm:
                # Убийство подтверждается повтором: красное от пробы, зависящей
                # от часов или нагрузки, порчу не убивает (так AE «убивал» порчи,
                # его не касавшиеся, пока окно FRESH_MIN не было снято).
                rc2, reds2, tail2 = run_inject(path, d, failfast=not a.full)
                if rc2 not in (1, "hang"):
                    return m, path, "flaky", reds + ["повтор зелёный"], tail2
                reds = reds + [x for x in reds2 if x not in reds]
            return m, path, rc, reds, tail

        res = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.j)) as ex:
            for fut in concurrent.futures.as_completed([ex.submit(one, m) for m in todo]):
                m, path, rc, reds, tail = fut.result()
                state = ("убита" if rc == 1 else "убита (зависание)" if rc == "hang"
                         else "НЕУСТОЙЧИВО" if rc == "flaky"
                         else "ВЫЖИЛА" if rc == 0 else f"набор кодом {rc}")
                print(f"{m[0]}\t{state}\t{' '.join(reds[:12])}{' …' if len(reds) > 12 else ''}\t{m[2]}", flush=True)
                res.append((m, path, rc, reds))

        survivors = [r for r in res if r[2] not in (1, "hang")]
        print(f"\nmutants: порч {len(res)}, убито {len(res) - len(survivors)}, выжило {len(survivors)}")
        if not survivors:
            return 0
        if not a.clone and not a.frozen:
            print("mutants: выжившие без доказательства эквивалентности (нет --clone): "
                  + ", ".join(r[0][0] for r in survivors))
            return 1

        snaps = [snapshot(c, work) for c in a.clone]
        for fz in a.frozen:
            snap, prs = (os.path.abspath(x) for x in fz.split(":", 1))
            refs_ = subprocess.run(["git", "-C", snap, "for-each-ref", "--format=%(objectname) %(refname)"],
                                   stdout=subprocess.PIPE, check=True).stdout
            snaps.append((os.path.basename(snap), snap, prs,
                          hashlib.sha256(refs_ + open(prs, "rb").read()).hexdigest()[:16], refs_.count(b"\n")))
        sha = hashlib.sha256(src.encode()).hexdigest()[:16]
        refs = {}
        for name, snap, prs, key, nrefs in snaps:
            ref = os.path.join(work, f"exact-{name}-{sha}-{key}.out")
            if not os.path.exists(ref):
                rc, text = audit_on(AUDIT, snap, prs, {"BRANCH_AUDIT_EXACT": "1"}, work)
                with open(ref + ".tmp", "wb") as f:
                    f.write(text)
                os.replace(ref + ".tmp", ref)
                with open(ref + ".rc", "w") as f:
                    f.write(str(rc))
            fast = os.path.join(work, f"fast-{name}-{sha}-{key}.out")
            if not os.path.exists(fast):
                rc, text = audit_on(AUDIT, snap, prs, {}, work)
                with open(fast, "wb") as f:
                    f.write(text)
            same = open(ref, "rb").read() == open(fast, "rb").read()
            print(f"снимок {name}: ссылок {nrefs}, эталон {ref}; ускоренный НЕиспорченный "
                  f"{'cmp-равен эталону' if same else 'РАСХОДИТСЯ с эталоном'}")
            if not same:
                print("mutants: ПРЕДПОСЫЛКА — ускоренный режим без порчи не равен эталону; сверять не с чем")
                return 1
            refs[name] = ref

        def eq(r):
            m, path = r[0], r[1]
            verdict = []
            for name, snap, prs, key, nrefs in snaps:
                rc, text = audit_on(path, snap, prs, {}, os.path.dirname(path))
                same = text == open(refs[name], "rb").read()
                verdict.append((name, same, rc))
            return m, verdict

        bad = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(a.j, 2))) as ex:
            for m, verdict in ex.map(eq, survivors):
                ok = all(v[1] for v in verdict)
                bad += 0 if ok else 1
                desc = " · ".join(f"{n} {'cmp равны' if s else 'РАЗЛИЧАЮТСЯ'} (код {c})" for n, s, c in verdict)
                print(f"{m[0]}\t{'эквивалентна' if ok else 'НЕ ЭКВИВАЛЕНТНА'}\t{desc}\t{m[2]}", flush=True)
        print(f"\nmutants: выживших {len(survivors)}, эквивалентных {len(survivors) - bad}, "
              f"без доказательства {bad}")
        return 0 if bad == 0 else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
