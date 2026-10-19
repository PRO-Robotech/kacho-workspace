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
# ПРИВЯЗКА РЕВИЗИИ К ДИАПАЗОНУ ЗАПРОСА — тоже здесь и тоже одна (ws#1162): ею судят
# `merge-readiness.sh`, `landing-precheck.sh` (пункт (ж)) и `rituals.py` (тело PR). До
# ws#1162 merge-readiness засчитывал любую распознанную ревизию (`DoD-proof @deadbeef1` —
# тоже), а двое других сверяли с диапазоном каждый своим кодом: демон вливания получал на
# одном PR два исхода. Согласие троих держит `scripts/rituals/check-05-dod-judges-agree.py`.
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

# ЧАСТИЧНОЕ доказательство (ws#1242) — строка, чей остаток после ревизии ЛИБО следующая непустая
# строка (не другая строка-доказательство) несёт признак объёма меньше задачи: «частичн…»;
# «только» перед «пункт…», «п.», «пп.»; «пункт…/п./пп. <номера> из <N>»; «<K> из <N> пункт…»
# (`DoD-proof @<sha> — частично: пункт 0`, `— только п. 0`, `— пп. 1–5 из 6`, на строке ниже —
# `частично: пункт 2`). Доказательством DoD задачи оно НЕ является ни у одного из пяти судей —
# иначе тело PR ставило Closes задаче пачки по первому пункту (#1241 → «Closes #1242»).
def _dod_partial_tail:
  test("частичн|только\\s+(пункт|пп?\\.)|(пункт[[:alpha:]]*|пп?\\.)\\s*[0-9][^\n]*?\\sиз\\s+[0-9]|[0-9]+\\s+из\\s+[0-9]+\\s+пункт"; "i");
def _dod_mark_re: "^([#]{1,6} +)?([*]{2})?DoD-proof @(?<rev>[0-9a-f]{7,40})(?<rest>.*)$";
def _dod_marks:
  [_dod_lines_outside_code] as $l
  | [range(0; $l | length) as $i
     | $l[$i] | capture(_dod_mark_re)
     | . + {next: ([$l[$i + 1:][] | select(test("\\S"))][0] // "")}
     | .next |= (if test(_dod_mark_re) then "" else . end)
     | .partial = ((.rest + "\n" + .next) | _dod_partial_tail)];

# Ревизии всех строк-доказательств текста, по порядку; пустой массив — доказательства нет.
def dod_proof_revisions: [_dod_marks[] | select(.partial | not) | .rev];

# Ревизии частичных строк — только для текста отказа («частичное, не Closes»).
def dod_proof_partial_revisions: [_dod_marks[] | select(.partial) | .rev];

# Есть ли в тексте строка-доказательство.
def dod_proof: dod_proof_revisions | length > 0;

# Привязана ли ревизия-вход (из `dod_proof_revisions`) к диапазону запроса: `$range` —
# массив полных sha коммитов `база...голова`, ревизия — начало sha одного из них.
# Не привязаны: ревизия базы (предок головы, не коммит диапазона), коммит с тем же деревом
# вне диапазона, ревизия, которой нет. Судят коммит, на котором гнали проверки, а не дерево.
def dod_proof_bound($range): . as $rev | any($range[]; startswith($rev));

# Ревизии строк-доказательств текста, привязанные к диапазону `$range`, по порядку.
def dod_proof_revisions_in($range): [dod_proof_revisions[] | select(dod_proof_bound($range))];
