# Распознаватель комментария-доказательства DoD — ЕДИНСТВЕННЫЙ в дереве.
#
# Форма (`git-issues.md#gi-closes-last-line`): строка `DoD-proof @<ревизия>` в
# НАЧАЛЕ строки комментария, ревизия — 7–40 шестнадцатеричных знаков. Начало
# строки допускает необязательный заголовок markdown (`#`…`######` и пробел) и
# выделение `**` перед маркером (ws#1140: `## DoD-proof @<sha>` четырежды отказал
# Closes). Доказательством НЕ являются: маркер посреди прозы («см. DoD-proof @… у
# соседа»), в цитате `>` и внутри блока кода (``` или ~~~) — это чужие слова и
# вывод, а не заявление автора комментария.
#
# Судят по нему пятеро, и каждый подключает этот файл, а не держит свою копию
# выражения: `scripts/merge-readiness.sh` (Closes PR), `scripts/landing-precheck.sh`
# (пункт (ж), Closes посадки), `scripts/cascade-census.sh --proof` (каскад влитой
# волны), `scripts/lane-precheck.sh` (полоса и предусловие `proof`) и
# `scripts/rituals/rituals.py` (тело PR, закрытие волны, trail). Копии одной
# нормы разъезжаются молча: так было с ws#930 и с копиями в landing-precheck и
# lane-precheck, отказавшими `## DoD-proof @<sha>` (ws#1140).
#
# Подключение: `jq -L <каталог scripts/lib> 'include "dod_proof"; …'`.

# Строки текста вне блоков кода, по порядку. Блок открывает строка из трёх и
# более ` либо ~ (отступ до трёх пробелов, дальше — строка сведений), закрывает
# строка из того же знака не короче открывшей и без иного текста; незакрытый блок
# длится до конца текста. Строки забора и строки внутри блока отброшены; `\r`
# конца строки снят.
def _dod_lines_outside_code:
  foreach (split("\n")[] | rtrimstr("\r")) as $line (
    {fence: null, out: null};
    ($line | [match("^ {0,3}(`{3,}|~{3,})")] | if length > 0 then .[0].captures[0].string else null end) as $f
    | if .fence == null then
        if $f == null then {fence: null, out: $line} else {fence: $f, out: null} end
      elif $f != null and $f[0:1] == .fence[0:1] and ($f | length) >= (.fence | length)
           and ($line | test("^ {0,3}[`~]+[ \t]*$")) then
        {fence: null, out: null}
      else
        .out = null
      end;
    .out // empty
  );

# Ревизии всех строк-доказательств текста, по порядку; пустой массив — доказательства нет.
def dod_proof_revisions:
  [_dod_lines_outside_code | capture("^([#]{1,6} +)?([*]{2})?DoD-proof @(?<rev>[0-9a-f]{7,40})") | .rev];

# Есть ли в тексте строка-доказательство.
def dod_proof: dod_proof_revisions | length > 0;
