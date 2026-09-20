#!/usr/bin/env bash
# Stop hook — проверка vault state перед окончанием session.
#
# `Stop` — событие ГЛАВНОГО ПОТОКА: вывод читает диспетчер, у которого нет ни Read, ни
# Edit, ни Bash. Ни перевести status, ни обновить узкий файл он не может — он ставит
# полосу. Поэтому каждая находка ниже названа АГЕНТОМ (`vault-scribe` — единственный,
# кто пишет в `obsidian/kacho/**`; `scout` — состояние PR и веток), а не императивом.
#
# Корень workspace берём из $CLAUDE_PROJECT_DIR (выставляет Claude Code в hook-env);
# fallback — каталог на 2 уровня выше скрипта (.claude/hooks/ → workspace root).
#
# # Каждый из трёх разделов — СВОЙ сигнал (2026-09-20)
#
# Разделы независимы: активные записки, счётчик правок за час и открытые PR живут
# разными предметами и снимаются разными полосами. Поэтому у каждого свой id, свой
# адресат и свой предикат снятия — общая свёртка одного не вправе свернуть другой.
# До этой правки все три печатались каждый конец хода, включая ходы без единой правки.
# Оболочка признака дельты. Провал `source` ОБЯЗАН быть слышен и НЕ вправе проглотить
# находку: замер 2026-09-20 — при неверном имени файла хук напечатал НОЛЬ строк, то
# есть находки исчезли молча, а это ровно тот мягкий проход, который оснастка и ловит.
# Заглушки объявлены ЗДЕСЬ, а не в общем файле, по причине начальной загрузки: они
# страхуют отсутствие того самого файла, в котором иначе бы лежали.
_sig="$(dirname "${BASH_SOURCE[0]}")/lib/hook_signal.sh"
# shellcheck source=lib/hook_signal.sh
. "$_sig" 2>/dev/null || {
  echo "[сигнал] признак дельты НЕ применён: не найден $_sig. Тело печатается ПОЛНОСТЬЮ каждый ход. → tooling-maintainer" >&2
  signal_stdin() { :; }
  signal_sha() { echo "ревизия не читается"; }
  signal_emit() { cat; echo "[сигнал \`$1\`] признак дельты НЕ применён (нет $_sig) · адресат: $2 · предикат снятия предмета: $3"; }
}
signal_stdin

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VAULT="$ROOT/obsidian/kacho"
PROJ="$ROOT/project"

# 1. Активные записки задач в vault — напоминание про status update
INPROG=$(grep -rlE "^status: (in-progress|test)" "$VAULT/KAC/" 2>/dev/null | head -5)
if [ -n "$INPROG" ]; then
  signal_emit vault-active-notes "scout (влит ли PR) · vault-scribe (перевод состояния)" \
    'grep -rlE "^status: (in-progress|test)" obsidian/kacho/KAC/ не даёт ни одного файла' \
    "$(signal_sha "$ROOT")" <<EOF

⚠️  АКТИВНЫЕ ЗАДАЧИ В VAULT (status: in-progress|test):
$(echo "$INPROG" | xargs -I{} basename {} .md | sed 's/^/   • /')
   → scout: влит ли PR каждой из них (этот хук читает только поле status).
   → vault-scribe: с PR-URL и списком затронутых сущностей — перевод состояния
     и «Затронутые сущности vault» в KAC/issue-<N>.md.
EOF
fi

# 2. Активность за последний час: код-changes vs vault-changes
RECENT_CODE=$(find "$PROJ" \( -name "*.go" -o -name "*.sql" -o -name "*.proto" \) -mmin -60 2>/dev/null | wc -l)
RECENT_VAULT=$(find "$VAULT" -name "*.md" -mmin -60 2>/dev/null | wc -l)
if [ "$RECENT_CODE" -gt 0 ] && [ "$RECENT_VAULT" -eq 0 ]; then
  signal_emit vault-code-without-notes "vault-scribe (по строкам «затронуто в vault» возвратов полос)" \
    'find obsidian/kacho -name "*.md" -mmin -60 даёт больше нуля файлов, либо правок кода за час нет' \
    "$(signal_sha "$ROOT")" <<EOF

⚠️  $RECENT_CODE code-files изменено за час, $RECENT_VAULT vault-файлов.
   → vault-scribe, если затронут ресурс/RPC/пакет/runtime-edge. Предмет берётся
     из строк «затронуто в vault» возвратов полос, а не из этого счётчика:
     счётчик говорит о времени правки файла, а не о том, что в ней изменилось.
EOF
fi

# 3. Open PR'ы по KAC-эпикам — есть ли чей trail обновлять.
#
# Каталог ОДИН: разработка идёт в монорепо продукта, клонируемом в `project/kacho`
# (CLAUDE.md §«Топология»). Здесь стоял перечень прежнего полирепо — семь каталогов
# `kacho-vpc` · `kacho-deploy` · `kacho-compute` · `kacho-iam` · `kacho-api-gateway` ·
# `kacho-corelib` · `kacho-proto`; предикат `ls -d project/kacho-* 2>/dev/null` не даёт
# НИ ОДНОГО из них (2026-09-18), то есть цикл обходил имена, которых в дереве нет, и
# «ноль открытых PR» означало «некуда было смотреть».
#
# УСЛОВИЕ `-d` ОСТАВЛЕНО КАК БЫЛО — и вот чего оно стоит, чтобы молчание не читалось
# как «открытых PR нет». В рабочей копии-worktree `.git` — РЕГУЛЯРНЫЙ ФАЙЛ со строкой
# `gitdir:`, а не каталог; предикат `stat -c '%F' project/kacho/.git` в этом дереве
# даёт `regular file` (2026-09-18), значит раздел здесь НЕ СРАБАТЫВАЕТ. В обычном
# клоне `.git` — каталог, и раздел работает. Соседи различают оба вида
# (`branches-clean.sh`: `-d … || -f …`; `hooks-wired.sh` спрашивает у git
# `rev-parse --git-common-dir`). Расширить признак здесь — смена УСЛОВИЯ
# СРАБАТЫВАНИЯ, а не адресата, поэтому этой правкой оно не делается:
# → tooling-maintainer, отдельной полосой.
REPO="kacho"
if command -v gh >/dev/null 2>&1; then
  if [ -d "$PROJ/$REPO/.git" ]; then
    OPEN=$(cd "$PROJ/$REPO" && gh pr list --state open --json number,title 2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for p in d:
    if 'KAC-' in p.get('title',''):
      n=p.get('number','?'); t=p.get('title','')[:60]
      print(f'   • $REPO#{n}: {t}')
except: pass
" 2>/dev/null)
    if [ -n "$OPEN" ]; then
      signal_emit vault-open-task-prs "scout (состояние каждого PR) · vault-scribe (по влитым)" \
        'gh pr list --state open не даёт ни одного PR с KAC- в заголовке' \
        "$(signal_sha "$ROOT")" <<EOF

📂 OPEN PR'Ы С ЗАДАЧАМИ:
$OPEN
   → scout: состояние каждого (база, headSha, проверок всего/зелёных/красных).
   → vault-scribe по влитым: PR-URL и затронутые сущности в KAC/issue-<N>.md.
EOF
    fi
  fi
fi

exit 0
