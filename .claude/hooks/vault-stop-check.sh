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
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VAULT="$ROOT/obsidian/kacho"
PROJ="$ROOT/project"

# 1. Активные записки задач в vault — напоминание про status update
INPROG=$(grep -rlE "^status: (in-progress|test)" "$VAULT/KAC/" 2>/dev/null | head -5)
if [ -n "$INPROG" ]; then
  echo
  echo "⚠️  АКТИВНЫЕ ЗАДАЧИ В VAULT (status: in-progress|test):"
  echo "$INPROG" | xargs -I{} basename {} .md | sed 's/^/   • /'
  echo "   → scout: влит ли PR каждой из них (этот хук читает только поле status)."
  echo "   → vault-scribe: с PR-URL и списком затронутых сущностей — перевод состояния"
  echo "     и «Затронутые сущности vault» в KAC/issue-<N>.md."
fi

# 2. Активность за последний час: код-changes vs vault-changes
RECENT_CODE=$(find "$PROJ" \( -name "*.go" -o -name "*.sql" -o -name "*.proto" \) -mmin -60 2>/dev/null | wc -l)
RECENT_VAULT=$(find "$VAULT" -name "*.md" -mmin -60 2>/dev/null | wc -l)
if [ "$RECENT_CODE" -gt 0 ] && [ "$RECENT_VAULT" -eq 0 ]; then
  echo
  echo "⚠️  $RECENT_CODE code-files изменено за час, $RECENT_VAULT vault-файлов."
  echo "   → vault-scribe, если затронут ресурс/RPC/пакет/runtime-edge. Предмет берётся"
  echo "     из строк «затронуто в vault» возвратов полос, а не из этого счётчика:"
  echo "     счётчик говорит о времени правки файла, а не о том, что в ней изменилось."
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
      echo
      echo "📂 OPEN PR'Ы С ЗАДАЧАМИ:"
      echo "$OPEN"
      echo "   → scout: состояние каждого (база, headSha, прогонов на голове всего/зелёных/красных)."
      echo "   → vault-scribe по влитым: PR-URL и затронутые сущности в KAC/issue-<N>.md."
    fi
  fi
fi

exit 0
