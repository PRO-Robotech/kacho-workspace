#!/usr/bin/env bash
# Доказательство docfresh ИНЪЕКЦИЕЙ, в обе стороны — по каждому предикату.
#
# Запрет стоит чего-то, только если проверен с двух сторон:
#   (+) верни НАСТОЯЩЕЕ расхождение → хук КРАСНЕЕТ и НАЗЫВАЕТ координату;
#   (−) поставь рядом ЗАКОННУЮ конструкцию той же формы → хук МОЛЧИТ.
# Без (−) хук ловит форму, а не существо, и первый же ложный срабат его отключит.
#
# Вход обеих сторон — НАСТОЯЩИЕ фрагменты дерева, а не выдуманные строки. Пробные
# ДОКУМЕНТЫ пишутся во временный каталог (DOCFRESH_DOC_ROOT), рабочее дерево не
# трогается; ОСНОВАНИЕ ИСТИНЫ при этом остаётся настоящим — подменённое основание
# доказывало бы лишь, что регулярное выражение совпадает само с собой.
#
# Запуск: bash .claude/hooks/docfresh/prove.sh    (код 0 — все пары сошлись)
#
# shellcheck disable=SC2016
# Одинарные кавычки в телах проб — НАМЕРЕННЫЕ и снимать их нельзя. Тело пробы
# состоит из координат в обратных кавычках; в двойных кавычках shell исполнил бы
# их как подстановку команды, и проба ушла бы в хук уже без координаты, оставаясь
# при этом зелёной на стороне (−). Класс известен по журналу корпуса: обратные
# кавычки в сообщении коммита исполнялись, идентификатор исчезал молча.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docfresh.sh"
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docfresh.py"
export CLAUDE_PROJECT_DIR="$WS"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DOCS="$TMP/docs"; mkdir -p "$DOCS"

PASS=0; FAIL=0; NOTRUN=0

# --- предмет проб: живость входа проверяется ПЕРЕД пробами ------------------
#
# Инъекция «настоящим расхождением» перестаёт быть настоящей в тот день, когда
# расхождение починят. Тогда проба (+) начнёт зеленеть на исправленном дереве и
# будет молча доказывать не то. Поэтому вход каждой (+)-пробы проверяется
# отдельно, и «предмета больше нет» — ТРЕТИЙ исход, а не успех.
absent_path() { [ ! -e "$WS/$1" ] && [ ! -e "$WS/project/kacho/$1" ]; }
present_path() { [ -e "$WS/$1" ] || [ -e "$WS/project/kacho/$1" ]; }

run_doc() { # run_doc <относительный путь пробы> <содержимое> → stderr+stdout хука
  local body="$2" abs="$DOCS/$1"
  mkdir -p "$(dirname "$abs")"
  printf '%s\n' "$body" > "$abs"
  DOCFRESH_DOC_ROOT="$DOCS" printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$abs" \
    | DOCFRESH_DOC_ROOT="$DOCS" bash "$HOOK" 2>&1
  rm -f "$abs"
}

expect_fires() { # expect_fires <метка> <проба-путь> <тело> <искомая координата>
  local label="$1" out
  out="$(run_doc "$2" "$3")"
  if printf '%s' "$out" | grep -qF -- "$4"; then
    echo "  ✔ (+) $label — краснеет и называет координату"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) $label — НЕ сработал на настоящем расхождении"; FAIL=$((FAIL+1))
    printf '%s\n' "$out" | sed 's/^/      /' | head -6
  fi
}

expect_silent() { # expect_silent <метка> <проба-путь> <тело> <координата-близнец>
  local label="$1" out
  out="$(run_doc "$2" "$3")"
  if printf '%s' "$out" | grep -qF -- "$4"; then
    echo "  ✘ (−) $label — ЛОЖНЫЙ СРАБАТ на законной конструкции той же формы"; FAIL=$((FAIL+1))
    printf '%s\n' "$out" | sed 's/^/      /' | head -6
  else
    echo "  ✔ (−) $label — молчит"; PASS=$((PASS+1))
  fi
}

notrun() { echo "  ⊘ НЕ ВЫПОЛНИЛОСЬ: $1"; NOTRUN=$((NOTRUN+1)); }

echo "== предпосылки проб (живость входа) =="
for dead in sync-tooling.sh tests/sync-tooling.bats; do
  if absent_path "$dead"; then echo "  ✔ вход (+) жив: '$dead' в дереве отсутствует"
  else notrun "'$dead' появился в дереве — проба (+) по нему больше не настоящая, заменить вход"; fi
done
for alive in sync-all.sh .claude/rules/vault.md pkg/ids/ids.go; do
  if present_path "$alive"; then echo "  ✔ вход (−) жив: '$alive' в дереве присутствует"
  else notrun "'$alive' исчез из дерева — близнец (−) больше не законный, заменить вход"; fi
done

echo
echo "== A. путь =="
expect_fires "снятый скрипт раскатки" a1.md \
  'Копии генерируются `sync-tooling.sh`, гейт `tests/sync-tooling.bats` в CI.' 'sync-tooling.sh'
expect_silent "живой скрипт того же каталога" a2.md \
  'Обновить рабочие копии — `sync-all.sh`.' 'sync-all.sh'
# Пара отличается ОДНОЙ буквой расширения — обе формы реальны, обе встречаются в
# конвейерах, и различить их можно только обращением к дереву.
expect_fires "workflow с расширением, которого в дереве нет" a3.md \
  'Конвейер — `.github/workflows/ci.yml`.' '.github/workflows/ci.yml'
expect_silent "тот же workflow с нынешним расширением" a4.md \
  'Конвейер — `.github/workflows/ci.yaml`.' '.github/workflows/ci.yaml'

echo
echo "== A'. регрессии нормализации пути =="
# `lstrip("./")` снимает точку КАК СИМВОЛ КЛАССА и превращает `.claude/rules/x`
# в `claude/rules/x`. Воспроизведено трижды подряд при написании предиката,
# поэтому проба стоит отдельно и с обеих сторон.
expect_silent "ведущая точка каталога оснастки не съедена" b1.md \
  'Полные правила — `.claude/rules/vault.md`.' '.claude/rules/vault.md'
expect_silent "маркер импорта @ не часть пути" b2.md \
  'Модуль подключается как `@.claude/rules/security.md`.' '.claude/rules/security.md'
expect_silent "относительная ссылка вверх — от каталога документа" \
  services/vpc/docs/architecture/b3.md \
  'Соседняя глава — `../ARCHITECTURE.md`.' 'ARCHITECTURE.md'
expect_silent "относительный путь под подразумеваемым корнем" b4.md \
  'Хук напоминания — `hooks/vault-reminder.sh`.' 'hooks/vault-reminder.sh'
expect_fires "тот же хвост под НЕВЕРНЫМ корнем всё равно краснеет" b5.md \
  'Скрипт `bin/sync-tooling.sh` синхронизирует копии.' 'sync-tooling.sh'

echo
echo "== B. маршрут =="
expect_fires "маршрут, снятый вместе с доменом размещения" c1.md \
  'Internal admin-ресурсы: `/compute/v1/regions`, `/compute/v1/zones`.' '/compute/v1/regions'
expect_silent "тот же ресурс по нынешнему домену" c2.md \
  'Каталог размещения: `/geo/v1/regions`, `/geo/v1/zones`.' '/geo/v1/zones'
expect_silent "маршрут, зарегистрированный шлюзом РУКАМИ (не из proto)" c3.md \
  'Вход пользователя — `/iam/v1/auth/login`.' '/iam/v1/auth/login'

echo
echo "== C. метод =="
expect_fires "метод, которого нет ни в одном service" d1.md \
  'Доверия читает `FederationService.ListTrustPolicies`.' 'FederationService.ListTrustPolicies'
expect_silent "живой метод того же вида" d2.md \
  'Зона резолвится через `ZoneService.Get`.' 'ZoneService.Get'

echo
echo "== D. цель make =="
expect_fires "цель, которой нет ни в одном Makefile" e1.md \
  'Синхронизация — `make sync-migrations`.' 'sync-migrations'
expect_silent "живая цель стенда" e2.md \
  'Поднять стенд — `make dev-up`.' 'dev-up'

echo
echo "== E. переменная окружения =="
expect_fires "ручка без единого читателя в дереве" f1.md \
  'Фильтр включается `KACHO_API_GATEWAY_AUTHZ_ENABLE=1`.' 'KACHO_API_GATEWAY_AUTHZ_ENABLE'
expect_silent "ручка, определённая в bootstrap ВОРКСПЕЙСА, а не монорепо" f2.md \
  'Легаси клонируются по `KACHO_CLONE_LEGACY_POLYREPOS=1`.' 'KACHO_CLONE_LEGACY_POLYREPOS'
expect_silent "обрезанное семейство — не имя" f3.md \
  'Группа `KACHO_VPC_TLS_SERVER_` задаёт сертификаты.' 'KACHO_VPC_TLS_SERVER_'

echo
echo "== F. исполняемая часть документа: пример ≠ утверждение =="
# Огороженный блок — иллюстрация. Утверждение о дереве живёт вне блока. Гейт,
# читающий сырой текст, нашёл бы координату ВНУТРИ примера, который её объясняет.
expect_silent "координата внутри огороженного блока не утверждение" g1.md \
  '# Пример устаревшей ссылки

```bash
./sync-tooling.sh --check
```
' 'sync-tooling.sh'
expect_silent "координата в HTML-комментарии не утверждение" g2.md \
  '<!-- было: `sync-tooling.sh` -->
Текст.' 'sync-tooling.sh'
expect_fires "она же вне блока — утверждение" g3.md \
  'Гейт `sync-tooling.sh` держит копии.' 'sync-tooling.sh'

echo
echo "== G. граница покрытия: чужое не приравнивается к отсутствующему =="
expect_silent "путь в полирепо, которого нет в дереве, — не находка" h1.md \
  'Идентификаторы — `kacho-corelib/ids/ids.go`.' 'kacho-corelib/ids/ids.go'
expect_silent "квалифицированный символ Go — предикат gosym отказан" h2.md \
  'Маппер — `internal/apps/kacho/shared/serviceerr.MapRepoErr`.' 'serviceerr.MapRepoErr'
expect_silent "чужой домен REST не судится" h3.md \
  'Обмен токена — `/oauth/v2/authorize`.' '/oauth/v2/authorize'
out="$(run_doc h4.md 'Идентификаторы — `kacho-corelib/ids/ids.go`.')"
if printf '%s' "$out" | grep -qE 'вне покрытия основания [1-9]'; then
  echo "  ✔ непокрытое СЧИТАЕТСЯ и печатается, а не прячется"; PASS=$((PASS+1))
else
  echo "  ✘ непокрытое не попало в перепись — молчание неотличимо от чистоты"; FAIL=$((FAIL+1))
fi

echo
echo "== H. послабление самоистекает =="
ALLOWDIR="$TMP/allow"; mkdir -p "$ALLOWDIR"
cat > "$ALLOWDIR/live.json" <<'JSON'
{"version":1,"entries":[{"kind":"path","coordinate":"sync-tooling.sh","reason":"проба","ground":"проба"}]}
JSON
cat > "$ALLOWDIR/stale.json" <<'JSON'
{"version":1,"entries":[{"kind":"path","coordinate":"нечего-исключать.go","reason":"проба","ground":"проба"}]}
JSON
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$DOCS/i1.md" \
  | { mkdir -p "$DOCS"; echo 'Копии генерируются `sync-tooling.sh`.' > "$DOCS/i1.md"; \
      DOCFRESH_DOC_ROOT="$DOCS" DOCFRESH_ALLOW="$ALLOWDIR/live.json" bash "$HOOK" 2>&1; })"
if printf '%s' "$out" | grep -qF 'sync-tooling.sh'; then
  echo "  ✘ послабление с предметом не подавило находку"; FAIL=$((FAIL+1))
else
  echo "  ✔ послабление с предметом подавляет находку"; PASS=$((PASS+1))
fi
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$DOCS/i1.md" \
  | DOCFRESH_DOC_ROOT="$DOCS" DOCFRESH_ALLOW="$ALLOWDIR/stale.json" bash "$HOOK" 2>&1)"
rm -f "$DOCS/i1.md"
if printf '%s' "$out" | grep -qF 'ПОСЛАБЛЕНИЕ БЕЗ ПРЕДМЕТА'; then
  echo "  ✔ послабление, которому нечего исключать, — находка"; PASS=$((PASS+1))
else
  echo "  ✘ послабление без предмета прошло молча — список не истекает"; FAIL=$((FAIL+1))
fi

echo
echo "== I. предпосылка самого хука =="
BARE="$TMP/bare"; mkdir -p "$BARE/.claude"
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s/x.md"}}' "$BARE" \
  | CLAUDE_PROJECT_DIR="$BARE" bash "$HOOK" 2>&1)"
rc=$?
if printf '%s' "$out" | grep -qF 'ОТКАЗЫВАЕТСЯ РАБОТАТЬ'; then
  echo "  ✔ без дерева продукта хук ОТКАЗЫВАЕТСЯ, а не отвечает «находок нет»"; PASS=$((PASS+1))
else
  echo "  ✘ без дерева продукта хук промолчал — ноль прочитанного выдан за ноль находок"; FAIL=$((FAIL+1))
fi
out="$(python3 - "$GUARD" <<'PY' 2>&1
import importlib.util, sys, pathlib
spec = importlib.util.spec_from_file_location("dfp", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.ROOT_SEGMENTS.add("каталога-с-таким-именем-в-дереве-нет")
ws = pathlib.Path(sys.argv[1]).resolve().parent.parent.parent.parent
print("\n".join(m.preconditions(ws, m.monorepo_root(ws))))
PY
)"
if printf '%s' "$out" | grep -qF 'каталога-с-таким-именем-в-дереве-нет'; then
  echo "  ✔ словарь корневых сегментов сверяется с деревом и называет осиротевшее имя"; PASS=$((PASS+1))
else
  echo "  ✘ осиротевшее имя словаря прошло молча — извлечение молча разошлось с деревом"; FAIL=$((FAIL+1))
fi

echo
echo "== J. ловушка момента: правка КОДА находит документ, который его называет =="
# Обратный индекс — единственное, что связывает правку в одном месте с
# утверждением в другом. Без этой пары хук ловил бы только «правлю документ»,
# то есть удобный подслучай.
mkdir -p "$DOCS"
echo 'Идентификаторы живут в `pkg/ids/ids.go`.' > "$DOCS/j1.md"
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/project/kacho/pkg/ids/ids.go"}}' "$WS" \
  | DOCFRESH_DOC_ROOT="$DOCS" bash "$HOOK" 2>&1)"
if printf '%s' "$out" | grep -qE 'называющих его, [1-9]'; then
  echo "  ✔ (+) правка кода подняла документ, который его называет"; PASS=$((PASS+1))
else
  echo "  ✘ (+) правка кода документ не подняла — обратный индекс не работает"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /' | head -4
fi
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/project/kacho/go.sum"}}' "$WS" \
  | DOCFRESH_DOC_ROOT="$DOCS" bash "$HOOK" 2>&1)"
if printf '%s' "$out" | grep -qE 'называющих его, 0'; then
  echo "  ✔ (−) правка неназванного файла — названо 0, и это НАПЕЧАТАНО"; PASS=$((PASS+1))
else
  echo "  ✘ (−) молчание на неназванном файле неотличимо от неработающего хука"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /' | head -4
fi
# Разбуженный документ НАЗЫВАЕТСЯ, но его собственные расхождения в ответ на
# ЧУЖУЮ правку не печатаются: совет, который не про сделанное, читается как шум.
out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/project/kacho/pkg/ids/ids.go"}}' "$WS" \
  | bash "$HOOK" 2>&1)"
if printf '%s' "$out" | grep -qF 'не резолвится'; then
  echo "  ✘ (−) правка кода вывалила чужие находки разбуженных документов"; FAIL=$((FAIL+1))
else
  echo "  ✔ (−) правка кода называет документы, но не их посторонние находки"; PASS=$((PASS+1))
fi
rm -f "$DOCS/j1.md"

echo
echo "== J'. ось удалений: путь исчез из дерева, документ его называет =="
# Удаление и переименование не приходят НИ ОДНИМ событием инструмента — их ловит
# только сверка снимка дерева с нынешним состоянием. Инъекция ведётся ЧЕРЕЗ СНИМОК
# (состояние хука), а не удалением файла из общего клона.
ST="$TMP/state"; mkdir -p "$ST"
seed_snapshot() { # seed_snapshot <строка-путь>
  git -C "$WS" ls-files > "$ST/tracked-snapshot.txt"
  git -C "$WS/project/kacho" ls-files | sed 's#^#project/kacho/#' >> "$ST/tracked-snapshot.txt"
  printf '%s\n' "$1" >> "$ST/tracked-snapshot.txt"
  rm -f "$ST/turn.jsonl"
}
seed_snapshot "sync-tooling.sh"
out="$(printf '{"hook_event_name":"Stop"}' | DOCFRESH_STATE="$ST" bash "$HOOK" 2>&1)"
# Сверяются ОБА: и координата в отчёте, и счётчик в переписи. Одной координаты
# мало — она могла бы прийти другой полосой (затронутый за ход документ).
if printf '%s' "$out" | grep -qF 'sync-tooling.sh' && printf '%s' "$out" | grep -qE 'исчезло из дерева 1'; then
  echo "  ✔ (+) исчезнувший путь поднял документ, который его называет"; PASS=$((PASS+1))
else
  echo "  ✘ (+) исчезновение пути не поймано — ось удалений мертва"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /' | head -4
fi
seed_snapshot "sync-all.sh"
out="$(printf '{"hook_event_name":"Stop"}' | DOCFRESH_STATE="$ST" bash "$HOOK" 2>&1)"
if printf '%s' "$out" | grep -qE 'исчезло из дерева 0'; then
  echo "  ✔ (−) путь, оставшийся в дереве, исчезновением не считается"; PASS=$((PASS+1))
else
  echo "  ✘ (−) живой путь засчитан за исчезнувший"; FAIL=$((FAIL+1))
fi

echo
echo "== K. Stop не блокирует конец хода =="
echo 'Копии генерируются `sync-tooling.sh`.' > "$DOCS/k1.md"
printf '{"hook_event_name":"Stop","transcript_path":"/dev/null"}' \
  | DOCFRESH_DOC_ROOT="$DOCS" DOCFRESH_STATE="$TMP/state" bash "$HOOK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "  ✔ Stop возвращает 0 даже при находках — ход не блокируется"; PASS=$((PASS+1))
else
  echo "  ✘ Stop вернул $rc — хук мешает работе и будет снят"; FAIL=$((FAIL+1))
fi
rm -f "$DOCS/k1.md"

echo
echo "== L. самоописание: перепись называет объём =="
out="$(run_doc l1.md 'Живой путь — `sync-all.sh`.')"
for token in 'осмотрено документов' 'координат рассмотрено' 'предикатов прогнано' 'основание:'; do
  if printf '%s' "$out" | grep -qF -- "$token"; then
    echo "  ✔ перепись несёт «$token»"; PASS=$((PASS+1))
  else
    echo "  ✘ перепись не несёт «$token» — ноль находок неотличим от ноля прочитанного"; FAIL=$((FAIL+1))
  fi
done

echo
echo "══ проб: $((PASS+FAIL)) · сошлось: $PASS · разошлось: $FAIL · НЕ ВЫПОЛНИЛОСЬ: $NOTRUN ══"
# «Не выполнилось» НЕ вычитается из вердикта и НЕ засчитывается за успех:
# проба, чей вход перестал быть настоящим, ничего не доказала.
[ "$FAIL" -eq 0 ] && [ "$NOTRUN" -eq 0 ]
