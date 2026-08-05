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
# Проба обязана быть СПОСОБНОЙ упасть, и это проверяется наведением её на
# ревизию ДО починки — иначе «зелено» доказывает лишь, что проба существует.
# Отсюда единственная точка подмены исполняемого хука; она ГРОМКАЯ, потому что
# молча наведённый на чужую ревизию набор доказывал бы не то, что читают.
if [ -n "${DOCFRESH_PROVE_HOOK:-}" ]; then
  HOOK="$DOCFRESH_PROVE_HOOK"
  echo "!! ВНИМАНИЕ: набор наведён на ПОДМЕНЁННЫЙ хук: $HOOK"
  echo "!! Вердикт относится к нему, а не к тому, что провязан в settings.json."
fi
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
echo "== A''. записка хранилища судится по ОБЪЯВЛЕННОМУ состоянию =="
# Записка vault обязана нести `status:` из закрытого словаря, и первое ведро словаря
# определено как «предмет есть в дереве СЕГОДНЯ». Значит записка, объявившая себя
# историей или работой, утверждения о нынешнем дереве не делает — обвинять её нельзя.
# Пара доказывается на ОДНОМ И ТОМ ЖЕ теле: меняется только объявленное состояние,
# поэтому проба меряет именно его, а не форму текста.
note() { # note <status> → тело записки, называющей снятый скрипт
  printf -- '---\ntitle: проба\ncategory: packages\nstatus: %s\n---\n\n' "$1"
  printf '%s\n' 'Копии генерирует `sync-tooling.sh`.'
}
expect_fires "живая записка (stable) — координата судится" \
  obsidian/kacho/packages/p-live.md "$(note stable)" 'sync-tooling.sh'
expect_silent "та же координата в записке-истории (deprecated)" \
  obsidian/kacho/packages/p-hist.md "$(note deprecated)" 'sync-tooling.sh'
expect_silent "та же координата в записке «в работе» (planned)" \
  obsidian/kacho/edges/p-plan.md "$(note planned)" 'sync-tooling.sh'
# fail-closed: неизвестное значение НЕ выводит записку из-под проверки. Иначе опечатка
# в статусе становилась бы способом снять проверку молча, а `check-03` мог бы в этот
# момент не гоняться вовсе.
expect_fires "неизвестное состояние не освобождает (fail-closed)" \
  obsidian/kacho/rpc/p-typo.md "$(note deprecatd)" 'sync-tooling.sh'
# граница послабления: оно про записки хранилища, а не про любой документ с frontmatter.
expect_fires "то же поле в НЕ-записке освобождения не даёт" \
  .claude/rules/p-rule.md "$(note deprecated)" 'sync-tooling.sh'

echo
echo "== B. маршрут =="
expect_fires "маршрут, снятый вместе с доменом размещения" c1.md \
  'Internal admin-ресурсы: `/compute/v1/regions`, `/compute/v1/zones`.' '/compute/v1/regions'
expect_silent "тот же ресурс по нынешнему домену" c2.md \
  'Каталог размещения: `/geo/v1/regions`, `/geo/v1/zones`.' '/geo/v1/zones'
# Вход (−) этой пары ЖИВЁТ В КОДЕ КРАЯ, а не в proto, поэтому он и проверяет, что
# основание читает строковые литералы Go. Он же и портится молча, когда край снимает
# ручной маршрут: прежняя редакция называла `/iam/v1/auth/login`, которого в дереве
# больше нет, — и проба падала «ложным срабатом» на координате, по которой хук был ПРАВ.
# Поэтому живость входа устанавливается по дереву, а «предмета больше нет» — третий исход.
HAND_ROUTE="/iam/v1/auth/me"
if git -C "$WS/project/kacho" grep -qF -- "\"$HAND_ROUTE\"" -- '*.go' 2>/dev/null; then
  expect_silent "маршрут, зарегистрированный шлюзом РУКАМИ (не из proto)" c3.md \
    "Личность сессии — \`$HAND_ROUTE\`." "$HAND_ROUTE"
else
  notrun "рукописный маршрут '$HAND_ROUTE' в коде края не найден — близнец (−) не настоящий, заменить вход"
fi

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
# Пара на РЕФЕРЕНТ-ПРЕФИКС: настоящее имя на одну букву длиннее. Подстрочный поиск
# засчитал бы несуществующую ручку за живую; на этой самой паре имён уже разошлись
# две переписи корпуса.
expect_silent "настоящее имя (на букву длиннее) молчит" f4.md \
  'Гейт `KACHO_API_GATEWAY_AUTHZ_ENABLED=false` снимает фильтр.' 'KACHO_API_GATEWAY_AUTHZ_ENABLED'

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

# ПУСТОЙ КОРПУС. `preconditions` исполняется ДО сборки индекса и объём корпуса
# видеть не может, поэтому промах шаблонов LIVE давал код 0 и «осмотрено
# документов 0» — ноль прочитанного, выданный за ноль находок. Шаблоны зашиты
# путями, а корпус переезжает, так что промах — не гипотеза.
out="$(python3 - "$GUARD" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dfp", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("ПУСТО:", "\n".join(m.corpus_preconditions({"docs": {}, "reverse": {}})))
print("БЕЗ-КООРДИНАТ:", "\n".join(m.corpus_preconditions({"docs": {"a.md": 1}, "reverse": {}})))
print("ЗДОРОВЫЙ:", "\n".join(m.corpus_preconditions({"docs": {"a.md": 1}, "reverse": {"x": 1}})) or "<молчит>")
PY
)"
if printf '%s' "$out" | grep -qF 'ни один документ не опознан как LIVE'; then
  echo "  ✔ (+) пустой корпус — ОТКАЗ, а не «находок нет»"; PASS=$((PASS+1))
else
  echo "  ✘ (+) пустой корпус прошёл молча — ноль прочитанного выдан за ноль находок"; FAIL=$((FAIL+1))
fi
if printf '%s' "$out" | grep -qF 'ни одной координаты из них не извлечено'; then
  echo "  ✔ (+) корпус есть, координат ноль — тоже ОТКАЗ"; PASS=$((PASS+1))
else
  echo "  ✘ (+) корпус без координат прошёл молча"; FAIL=$((FAIL+1))
fi
# ЗАКОННЫЙ БЛИЗНЕЦ: здоровый индекс обязан молчать, иначе отказ сработает на
# каждом прогоне и его снимут первым же коммитом.
if printf '%s' "$out" | grep -qF 'ЗДОРОВЫЙ: <молчит>'; then
  echo "  ✔ (−) здоровый индекс проходит — отказ не срабатывает всегда"; PASS=$((PASS+1))
else
  echo "  ✘ (−) отказ сработал на здоровом индексе — гейт краснеет всегда"; FAIL=$((FAIL+1))
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
# Документ-производитель входа пишется ПРОБОЙ, а не берётся из корпуса. Прежняя
# редакция опиралась на то, что снятый скрипт называет какой-нибудь живой документ
# воркспейса, — и умерла в тот день, когда это утверждение оттуда законно убрали:
# проба падала «ось удалений мертва», хотя мертва была её собственная подпорка.
mkdir -p "$DOCS"
printf '%s\n' 'Копии генерируются `sync-tooling.sh`.' > "$DOCS/j1.md"
seed_snapshot "sync-tooling.sh"
out="$(printf '{"hook_event_name":"Stop"}' | DOCFRESH_DOC_ROOT="$DOCS" DOCFRESH_STATE="$ST" bash "$HOOK" 2>&1)"
# Сверяются ОБА: и координата в отчёте, и счётчик в переписи. Одной координаты
# мало — она могла бы прийти другой полосой (затронутый за ход документ).
if printf '%s' "$out" | grep -qF 'sync-tooling.sh' && printf '%s' "$out" | grep -qE 'исчезло из дерева 1'; then
  echo "  ✔ (+) исчезнувший путь поднял документ, который его называет"; PASS=$((PASS+1))
else
  echo "  ✘ (+) исчезновение пути не поймано — ось удалений мертва"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /' | head -4
fi
printf '%s\n' 'Рабочие копии обновляет `sync-all.sh`.' > "$DOCS/j1.md"
seed_snapshot "sync-all.sh"
out="$(printf '{"hook_event_name":"Stop"}' | DOCFRESH_DOC_ROOT="$DOCS" DOCFRESH_STATE="$ST" bash "$HOOK" 2>&1)"
if printf '%s' "$out" | grep -qE 'исчезло из дерева 0'; then
  echo "  ✔ (−) путь, оставшийся в дереве, исчезновением не считается"; PASS=$((PASS+1))
else
  echo "  ✘ (−) живой путь засчитан за исчезнувший"; FAIL=$((FAIL+1))
fi
rm -f "$DOCS/j1.md"

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

# РЕВИЗИЯ ВЕРДИКТА. Резолв идёт по рабочему дереву; когда оно отстаёт от ствола,
# живая на стволе координата читается мёртвой, и читатель чинит ВЕРНОЕ
# утверждение в ложное. Проверено вживую 2026-08-04: четыре координаты одного
# документа названы мёртвыми при отставании дерева на 147 коммитов — все четыре
# существуют на стволе. Поэтому вердикт обязан нести свою ревизию.
if printf '%s' "$out" | grep -qF 'дерево продукта '; then
  echo "  ✔ перепись называет РЕВИЗИЮ, относительно которой вынесен вердикт"; PASS=$((PASS+1))
else
  echo "  ✘ вердикт без ревизии — неотличим от вердикта о продукте"; FAIL=$((FAIL+1))
fi
# Предупреждение об отставании обязано появляться ТОЛЬКО когда отставание есть,
# иначе оно шум и его перестанут читать.
behind="$(git -C "$WS/project/kacho" rev-list --count HEAD..redesign/integration 2>/dev/null || echo 0)"
if [ "${behind:-0}" -gt 0 ]; then
  if printf '%s' "$out" | grep -qF 'ОТСТАЁТ от'; then
    echo "  ✔ (+) дерево отстаёт на $behind — перепись предупреждает"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) дерево отстаёт на $behind, а перепись молчит"; FAIL=$((FAIL+1))
  fi
else
  if printf '%s' "$out" | grep -qF 'ОТСТАЁТ от'; then
    echo "  ✘ (−) дерево не отстаёт, а перепись предупреждает — предупреждение всегда"; FAIL=$((FAIL+1))
  else
    echo "  ✔ (−) дерево не отстаёт — предупреждения нет"; PASS=$((PASS+1))
  fi
fi

echo
echo "== M. полоса ствола: живое на стволе — НЕ находка (обе стороны) =="
# Резолв идёт по ВЫПИСАННОЙ копии, а у продукта их много — worktree на задачу.
# Копия в `project/kacho` может стоять на сотню коммитов позади линии интеграции,
# и тогда путь, живущий в стволе, читается как несуществующий: гейт краснеет
# ровно на свежей работе. Пара обязана быть двусторонней — иначе «молчит» было бы
# неотличимо от мёртвого предиката.
TRUNK_ALIVE="tools/knownfailingsubject/unsupervised.go"   # есть в стволе, нет в копии
DEAD_BOTH="sync-tooling.sh"                                # нет ни там, ни там
trunk_ref="$(cd "$WS/project/kacho" && for r in redesign/integration main master; do
  git rev-parse --verify --quiet "$r" >/dev/null && { echo "$r"; break; }; done)"
if [ -z "$trunk_ref" ]; then
  notrun "в дереве продукта нет ни одного кандидата ствола — полосу проверять не на чем"
elif ! (cd "$WS/project/kacho" && git cat-file -e "$trunk_ref:$TRUNK_ALIVE" 2>/dev/null); then
  notrun "'$TRUNK_ALIVE' исчез из ствола — вход (−) больше не настоящий, заменить"
elif [ -e "$WS/project/kacho/$TRUNK_ALIVE" ]; then
  notrun "'$TRUNK_ALIVE' появился в выписанной копии — расхождения копии со стволом больше нет, вход (−) не настоящий"
elif (cd "$WS/project/kacho" && git cat-file -e "$trunk_ref:$DEAD_BOTH" 2>/dev/null); then
  notrun "'$DEAD_BOTH' появился в стволе — вход (+) больше не настоящий, заменить"
else
  expect_silent "путь, живой на стволе, при отставшей копии" m1.md \
    "Гейт держит \`$TRUNK_ALIVE\`." "$TRUNK_ALIVE"
  expect_fires "путь, которого нет НИ в копии, НИ в стволе" m2.md \
    "Копии генерируются \`$DEAD_BOTH\`." "$DEAD_BOTH"
  out="$(run_doc m3.md "Гейт держит \`$TRUNK_ALIVE\`.")"
  if printf '%s' "$out" | grep -qE 'резолвится только в стволе [1-9]'; then
    echo "  ✔ живое-на-стволе СЧИТАЕТСЯ отдельным исходом, а не прячется"; PASS=$((PASS+1))
  else
    echo "  ✘ живое-на-стволе не попало в перепись — молчание неотличимо от чистоты"; FAIL=$((FAIL+1))
  fi
  if printf '%s' "$out" | grep -qF '+ствол: путей'; then
    echo "  ✔ перепись называет ОБЪЁМ полосы ствола"; PASS=$((PASS+1))
  else
    echo "  ✘ объём полосы ствола не назван — ноль находок неотличим от непрогнанной полосы"; FAIL=$((FAIL+1))
  fi
fi

echo
echo "== N. находка воспроизводится по НЫНЕШНЕМУ содержимому документа =="
# Решающая проба на дефект, ради которого писался этот раздел: кэш индекса
# ключуется КОММИТОМ, поэтому правку рабочего дерева он не видит вовсе. Путь
# записи (`PostToolUse`) читал документ заново, путь конца хода (`Stop`) — из
# кэша, и они расходились в том, что читают: хук докладывал координату, снятую
# в этом же ходу. Гейт, повторяющий починенное, учит читателя себя игнорировать.
#
# Инъекция детерминирована и не зависит от того, что кто-то трогал в этот ход:
# свой каталог документов, своё состояние, свой журнал хода. МЕТКА ВРЕМЕНИ
# ДОКУМЕНТА ВОЗВРАЩАЕТСЯ после правки — так проба воспроизводит условие
# НАСТОЯЩЕГО корпуса, где ключ кэша от содержимого документа не зависит совсем.
NDOCS="$TMP/ndocs"; NST="$TMP/nstate"; mkdir -p "$NDOCS" "$NST"
report_has_pair() { # <вывод> <документ> <координата> — ищет ПАРУ, а не строку
  printf '%s\n' "$1" | awk -v d="║ $2" -v c="$3" '
    $0==d { inblk=1; next }
    inblk && /^║     / { if (index($0,c)) found=1; next }
    inblk { inblk=0 }
    END { exit found?0:1 }'
}
n_run() { # n_run <событие-json> → вывод хука
  printf '%s' "$1" | DOCFRESH_DOC_ROOT="$NDOCS" DOCFRESH_STATE="$NST" bash "$HOOK" 2>&1
}
# Документ несёт ДВЕ координаты: мёртвую и живую. Живая нужна, чтобы свежий
# разбор остался НЕПУСТЫМ — иначе сработал бы другой подслучай (ниже, N4).
printf 'Копии генерируются `%s`. Обновить — `sync-all.sh`.\n' "$DEAD_BOTH" > "$NDOCS/n1.md"
touch -r "$NDOCS/n1.md" "$TMP/n1.stamp"
ev_a="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/n1.md"}}' "$NDOCS")"
out="$(n_run "$ev_a")"
if report_has_pair "$out" n1.md "$DEAD_BOTH"; then
  echo "  ✔ (+) исходное расхождение видно — кэш прогрет настоящей находкой"; PASS=$((PASS+1))
else
  echo "  ✘ (+) исходное расхождение не найдено — проба ниже ничего не докажет"; FAIL=$((FAIL+1))
fi
# Снимаем утверждение из документа и ВОЗВРАЩАЕМ метку времени.
printf 'Копии генерируются механизмом, которого больше нет. Обновить — `sync-all.sh`.\n' > "$NDOCS/n1.md"
touch -r "$TMP/n1.stamp" "$NDOCS/n1.md"
printf '{"p":"n1.md","t":1}\n' > "$NST/turn.jsonl"
out="$(n_run '{"hook_event_name":"Stop"}')"
if report_has_pair "$out" n1.md "$DEAD_BOTH"; then
  echo "  ✘ (−) РЕШАЮЩАЯ: конец хода доложил координату, снятую из документа"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | sed 's/^/      /' | head -5
else
  echo "  ✔ (−) РЕШАЮЩАЯ: снятая координата на конце хода НЕ докладывается"; PASS=$((PASS+1))
fi
if printf '%s' "$out" | grep -qE 'снято утверждение [1-9]'; then
  echo "  ✔ закрытие названо ПРИЧИНОЙ «снято утверждение», а не общим числом"; PASS=$((PASS+1))
else
  echo "  ✘ причина закрытия не названа — «починили дерево» и «убрали упоминание» слиты"; FAIL=$((FAIL+1))
fi
# N4 — подслучай, который прятался за ложью пустого словаря: правка сняла
# ПОСЛЕДНЮЮ координату документа. Пустой свежий разбор ложен как значение, и
# `or` проваливался в кэш — то есть путь записи тоже отвечал по прошлому.
printf 'Копии генерируются `%s`.\n' "$DEAD_BOTH" > "$NDOCS/n4.md"
touch -r "$NDOCS/n4.md" "$TMP/n4.stamp"
ev4="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/n4.md"}}' "$NDOCS")"
n_run "$ev4" >/dev/null
printf 'Копии генерируются механизмом, которого больше нет.\n' > "$NDOCS/n4.md"
touch -r "$TMP/n4.stamp" "$NDOCS/n4.md"
out="$(n_run "$ev4")"
if report_has_pair "$out" n4.md "$DEAD_BOTH"; then
  echo "  ✘ (−) снята ПОСЛЕДНЯЯ координата — путь записи ответил по кэшу"; FAIL=$((FAIL+1))
else
  echo "  ✔ (−) снята ПОСЛЕДНЯЯ координата — путь записи молчит"; PASS=$((PASS+1))
fi
# ЗАКОННЫЙ БЛИЗНЕЦ: документ, который координату НЕ снимал, обязан краснеть по-прежнему.
# Без него «молчит» доказывало бы лишь, что предикат умер целиком.
printf 'Копии генерируются `%s`.\n' "$DEAD_BOTH" > "$NDOCS/n5.md"
out="$(n_run "$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/n5.md"}}' "$NDOCS")")"
if report_has_pair "$out" n5.md "$DEAD_BOTH"; then
  echo "  ✔ (+) документ, не снимавший координату, краснеет по-прежнему"; PASS=$((PASS+1))
else
  echo "  ✘ (+) предикат замолчал целиком — отрицание выше ничего не доказывает"; FAIL=$((FAIL+1))
fi
rm -f "$NDOCS/n4.md" "$NDOCS/n5.md"

echo
echo "== N'. переносимое состояние самоистекает, и ЧЕМ закрыто — названо =="
# Запись, которой нечего переносить, — закрытая позиция, а не находка. Два
# основания закрытия проверяются РАЗДЕЛЬНО: слить их в одно число значило бы
# потерять, «убрали упоминание» или «предмет появился».
carry_probe() { # carry_probe <документ> <тело> <ожидаемая-причина>
  printf '%s\n' "$2" > "$NDOCS/$1"
  printf '[["%s","path","%s"]]' "$1" "$DEAD_BOTH" > "$NST/pending.json"
  n_run "$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$NDOCS" "$1")"
}
out="$(carry_probe p1.md 'Документ утверждения больше не несёт.')"
if printf '%s' "$out" | grep -qE 'закрыто 1 \(снято утверждение 1'; then
  echo "  ✔ (+) перенос закрыт основанием «снято утверждение»"; PASS=$((PASS+1))
else
  echo "  ✘ (+) перенос не закрылся снятием утверждения — список не истекает"; FAIL=$((FAIL+1))
  printf '%s\n' "$out" | tr '·' '\n' | grep -aF 'с прошлого хода' | sed 's/^/      /'
fi
if [ -f "$NST/pending.json" ] && ! grep -qF "$DEAD_BOTH" "$NST/pending.json"; then
  echo "  ✔ (+) закрытая позиция ВЫЧЕРКНУТА из состояния, а не только не показана"; PASS=$((PASS+1))
else
  echo "  ✘ (+) закрытая позиция осталась в состоянии — повторится следующим ходом"; FAIL=$((FAIL+1))
fi
# ЗЕРКАЛЬНАЯ проба: утверждение НЕ снималось, но предмет появился в дереве.
# Предмет заводится в игнорируемом каталоге состояния — общий клон не пачкается,
# и чужие полосы этого файла не увидят.
APPEAR="$WS/.claude/hooks/docfresh/.state/docfresh-probe-appeared.md"
APPEAR_COORD=".claude/hooks/docfresh/.state/docfresh-probe-appeared.md"
if [ -e "$APPEAR" ]; then
  notrun "'$APPEAR_COORD' уже существует — зеркальная проба не может отличить появление от наличия"
else
  printf '%s\n' "Документ по-прежнему называет \`$APPEAR_COORD\`." > "$NDOCS/p2.md"
  printf '[["p2.md","path","%s"]]' "$APPEAR_COORD" > "$NST/pending.json"
  ev2="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s/p2.md"}}' "$NDOCS")"
  out="$(n_run "$ev2")"
  if printf '%s' "$out" | grep -qE 'не закрыто 1'; then
    echo "  ✔ (+) пока предмета нет — позиция ОТКРЫТА (контроль зеркальной пробы)"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) позиция закрылась без появления предмета — зеркало ничего не покажет"; FAIL=$((FAIL+1))
  fi
  : > "$APPEAR"
  printf '[["p2.md","path","%s"]]' "$APPEAR_COORD" > "$NST/pending.json"
  out="$(n_run "$ev2")"
  rm -f "$APPEAR"
  if printf '%s' "$out" | grep -qE 'закрыто 1 \(снято утверждение 0, появилось в дереве 1'; then
    echo "  ✔ (−) ЗЕРКАЛЬНАЯ: закрыто ДРУГИМ основанием — «появилось в дереве»"; PASS=$((PASS+1))
  else
    echo "  ✘ (−) ЗЕРКАЛЬНАЯ: основания закрытия неразличимы"; FAIL=$((FAIL+1))
    printf '%s\n' "$out" | tr '·' '\n' | grep -aF 'с прошлого хода' | sed 's/^/      /'
  fi
fi
rm -f "$NDOCS/n1.md" "$NDOCS/p1.md" "$NDOCS/p2.md"

echo
echo "== O. перепись называет ТУ ревизию, на которой вынесен вердикт =="
# У ветки в `.git/HEAD` лежит ИМЯ ссылки, и коммит его не меняет — ключ кэша,
# читающий байты этого файла, коммит переживал. Тогда строка, чья единственная
# работа — сказать «по чему судили», сама подавалась из кэша и называла чужую
# ревизию. Пара двусторонняя: совпадение проверяется, и проверяется, что предикат
# вообще способен различать ревизии.
head_now="$(git -C "$WS" rev-parse --short=8 HEAD 2>/dev/null || echo '')"
if [ -z "$head_now" ]; then
  notrun "воркспейс не отдаёт HEAD — сверять перепись не с чем"
else
  out="$(run_doc o1.md 'Живой путь — `sync-all.sh`.')"
  if printf '%s' "$out" | grep -qF "воркспейс $head_now@"; then
    echo "  ✔ (+) перепись называет НЫНЕШНИЙ HEAD ($head_now)"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) перепись называет НЕ ту ревизию — вердикт приписан чужому состоянию"; FAIL=$((FAIL+1))
    printf '%s\n' "$out" | tr '·' '\n' | grep -aF 'воркспейс ' | sed 's/^/      /'
  fi
  # ЗАКОННЫЙ БЛИЗНЕЦ: предикат обязан ОТВЕРГАТЬ заведомо чужую ревизию, иначе
  # утверждение выше зеленело бы на любой строке.
  if printf '%s' "$out" | grep -qF "воркспейс 00000000@"; then
    echo "  ✘ (−) перепись совпала с выдуманной ревизией — сверка ничего не значит"; FAIL=$((FAIL+1))
  else
    echo "  ✔ (−) выдуманная ревизия не совпадает — сверка различает"; PASS=$((PASS+1))
  fi
fi

echo
echo "== P. канал Stop по ИСХОДУ: находка впрыскивается, перепись — НЕТ =="
# Предмет этой пары — КАНАЛ, поэтому потоки читаются РАЗДЕЛЬНО. Все соседние
# пробы склеивают `2>&1` и по построению не способны отличить `additionalContext`
# от текста в stderr: на живом дефекте набор оставался 61/61, то есть зелёным при
# сломанном свойстве. Это и есть причина писать пробу с раздельными потоками, а
# не переиспользовать `n_run`/`run_doc`.
#
# Класс: `additionalContext` — впрыск в контекст, он поднимает агента заново.
# Перепись, отданная им на КАЖДОМ конце хода, замыкает петлю «ход → впрыск →
# ход», и ход перестаёт заканчиваться вообще (наблюдалось семь ходов подряд с
# одинаковым текстом и «за ход затронуто 0», 2026-08-04). Отменить перепись при
# этом нельзя — «ноль находок» обязано быть отличимо от «ноль прочитанного», —
# поэтому пара утверждает ОБЕ стороны: канал впрыска молчит, а сама перепись
# существует и переживает ход.
PDOCS="$TMP/pdocs"; PST="$TMP/pstate"; mkdir -p "$PDOCS" "$PST"
p_run() { # p_run <событие-json> <файл-stdout> <файл-stderr> → код возврата хука
  printf '%s' "$1" | DOCFRESH_DOC_ROOT="$PDOCS" DOCFRESH_STATE="$PST" \
    bash "$HOOK" >"$2" 2>"$3"
}

# (−) ЧИСТЫЙ ход: документов нет, journal пуст ⇒ сказать нечего.
rm -f "$PST/turn.jsonl" "$PST/census.log"
p_run '{"hook_event_name":"Stop"}' "$TMP/p1.out" "$TMP/p1.err"; prc=$?
if grep -q '╔══ docfresh' "$TMP/p1.err" 2>/dev/null; then
  # Ход оказался НЕ чистым — утверждать по нему нечего. Третий исход, не успех.
  notrun "(−) ход не был чистым: хук нашёл расхождение, канал молчания непроверяем"
else
  if [ ! -s "$TMP/p1.out" ]; then
    echo "  ✔ (−) чистый конец хода: stdout МОЛЧИТ — агент не поднимается заново"; PASS=$((PASS+1))
  else
    echo "  ✘ (−) чистый конец хода печатает в stdout — петля «ход → впрыск → ход»"; FAIL=$((FAIL+1))
    head -c 200 "$TMP/p1.out" | sed 's/^/      /'
  fi
  if grep -q 'additionalContext' "$TMP/p1.out" 2>/dev/null; then
    echo "  ✘ (−) перепись отдана каналом additionalContext — это и есть петля"; FAIL=$((FAIL+1))
  else
    echo "  ✔ (−) канал впрыска на чистом ходу НЕ задействован"; PASS=$((PASS+1))
  fi
  # Вторая сторона того же: молчание канала не должно означать молчание ВООБЩЕ.
  if grep -q 'осмотрено документов' "$TMP/p1.err" 2>/dev/null; then
    echo "  ✔ (−) перепись жива в stderr — «ноль находок» отличимо от «ноль прочитанного»"; PASS=$((PASS+1))
  else
    echo "  ✘ (−) перепись пропала: канал сменён ценой утверждения об объёме"; FAIL=$((FAIL+1))
  fi
  if [ -s "$PST/census.log" ]; then
    echo "  ✔ (−) перепись переживает ход — журнал .state/census.log пополнен"; PASS=$((PASS+1))
  else
    echo "  ✘ (−) журнал переписи пуст — наблюдаемость держится на одном stderr"; FAIL=$((FAIL+1))
  fi
fi

# (+) ход С НАХОДКОЙ: тот же канал обязан РАБОТАТЬ, иначе фикс выхолостил хук.
if absent_path "$DEAD_BOTH"; then
  printf 'Копии генерируются `%s`.\n' "$DEAD_BOTH" > "$PDOCS/p1.md"
  printf '{"p":"p1.md","t":1}\n' > "$PST/turn.jsonl"
  p_run '{"hook_event_name":"Stop"}' "$TMP/p2.out" "$TMP/p2.err"; prc2=$?
  if grep -q 'additionalContext' "$TMP/p2.out" 2>/dev/null \
     && grep -qF -- "$DEAD_BOTH" "$TMP/p2.out"; then
    echo "  ✔ (+) находка ПО-ПРЕЖНЕМУ впрыскивается и называет координату"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) находка не доехала до агента — смена канала выхолостила хук"; FAIL=$((FAIL+1))
    head -c 200 "$TMP/p2.out" | sed 's/^/      /'
  fi
  if [ "$prc2" -eq 0 ]; then
    echo "  ✔ (+) код 0 и при находке — конец хода не блокируется"; PASS=$((PASS+1))
  else
    echo "  ✘ (+) код $prc2 при находке — хук мешает работе и будет снят"; FAIL=$((FAIL+1))
  fi
  rm -f "$PDOCS/p1.md"
else
  notrun "'$DEAD_BOTH' появился в дереве — вход (+) пробы P больше не настоящий"
fi
if [ "$prc" -eq 0 ]; then
  echo "  ✔ код 0 на чистом ходу — конец хода не блокируется"; PASS=$((PASS+1))
else
  echo "  ✘ код $prc на чистом ходу — хук мешает работе"; FAIL=$((FAIL+1))
fi

echo
echo "══ проб: $((PASS+FAIL)) · сошлось: $PASS · разошлось: $FAIL · НЕ ВЫПОЛНИЛОСЬ: $NOTRUN ══"
# «Не выполнилось» НЕ вычитается из вердикта и НЕ засчитывается за успех:
# проба, чей вход перестал быть настоящим, ничего не доказала.
[ "$FAIL" -eq 0 ] && [ "$NOTRUN" -eq 0 ]
