#!/usr/bin/env bash
# sync-tooling.sh — раскатывает каноническую AI-оснастку из workspace в рабочие копии
# репозиториев продукта.
#
# Модель: kacho-workspace/.claude — ЕДИНСТВЕННЫЙ источник истины. Каждая рабочая копия
# получает копию оснастки, чтобы репозиторий был самодостаточен при standalone-клоне
# (CI, свежий checkout, отдельный контрибьютор) — settings.json и hooks вообще не делают
# parent-walkup, поэтому без физической копии в репозитории их нет вовсе.
#
# Перечень целей ВЫВОДИТСЯ ИЗ ДЕРЕВА (repos.sh), а не выписывается руками: рукописный
# перечень был причиной того, что инвариант самодостаточности не выполнялся ни разу и это
# было ненаблюдаемо — одиннадцать имён полирепо не пересекались ни с одним склонированным
# каталогом, скрипт печатал одиннадцать «skip» и выходил с успехом.
#
# Domain-агенты и domain-скилы — НАТИВНЫЕ в своём репозитории, скрипт их не трогает.
# Устаревшие generic-копии (которых больше нет в workspace и которые не domain-*) удаляются.
# Идемпотентно: гонять сколько угодно раз.
#
# Правишь generic-оснастку → ТОЛЬКО в kacho-workspace/.claude, затем ./sync-tooling.sh.
#
# Режимы:
#   ./sync-tooling.sh           — применить (по умолчанию)
#   ./sync-tooling.sh --check   — ничего не писать; расхождение копии с источником, репозиторий
#                                 без оснастки и раскатка в ноль целей — ненулевой код возврата.
#                                 Оба режима строят ОДНО И ТО ЖЕ промежуточное дерево, поэтому
#                                 «проверено» и «применено» не могут разъехаться.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/.claude"
# Каталог с рабочими копиями. Переопределяется, чтобы гейт мог прогоняться на
# сконструированном дереве, а раскатку можно было направить в клон, лежащий не под
# project/ (общий клон бывает занят другим писателем). Предикат при этом НЕ ослабляется:
# что является рабочей копией продукта, решает repos.sh, а не путь.
PROJECT_DIR="${KACHO_PROJECT_DIR:-$SCRIPT_DIR/project}"

# shellcheck source=repos.sh
. "$SCRIPT_DIR/repos.sh"

MODE=apply
case "${1:-}" in
  --check) MODE=check ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

# ─────────────────────────────────────────────────────────────────────────────────────
# ЧТО ИМЕННО ЕДЕТ — решение по существу, а не «всё, потому что проще».
#
# Разделяющий вопрос один: есть ли у ассета ПРЕДМЕТ в репозитории продукта. Ассет, чей
# предмет там отсутствует, приезжает мёртвым — он не «про запас», он тихо ничего не делает
# и при этом выглядит работающим. Это ровно тот класс, который мы ловим в продуктовом коде
# (проверка с формой без содержания), и завозить его собственной оснасткой нельзя.
#
# Замерено исполнением, а не чтением (ревизия дерева монорепо b49f579):
#   • предмет class-guard (файлы .go/.sql/.proto)     — 3314 отслеживаемых файлов;
#   • предмет vault-хуков и vault.md (obsidian/kacho) — 0 отслеживаемых файлов;
#   • vault-stop-check.sh на воркспейсе               — 614 байт вывода (предмет есть);
#     он же на монорепо                               — 0 байт (предмет отсутствует).
#
# Поэтому НЕ едут — и у каждого исключения есть предикат снятия, внешний по отношению к
# самой раскатке (появление предмета в целевом дереве раскатка не создаёт):
WORKSPACE_ONLY_RULES="vault.md"
WORKSPACE_ONLY_HOOKS="vault-reminder.sh vault-stop-check.sh"
# Предмет этих трёх — obsidian-vault, который живёт ТОЛЬКО в workspace. vault-reminder.sh
# печатал бы на каждый промпт указание читать каталог, которого в клоне нет; vault.md был бы
# единственным правилом в наборе, ни одну строку которого невозможно исполнить. Предикат
# снятия: в целевом репозитории появился obsidian/kacho — исключение потеряло предмет и
# обязано быть снято (проверяется ниже, класс STALE-EXCLUSION).
STALE_EXCLUSION_SUBJECT="obsidian/kacho"

# Агенты (15) и скилы (11) едут ПОЛНОСТЬЮ: предмет каждого — продуктовый код, тесты,
# миграции, чарты и приёмка, и всё это в репозитории есть. Часть из них ссылается на
# docs/specs воркспейса — это кросс-репозиторная ссылка, а не их предмет: агент, ревьюящий
# Go-файлы, остаётся работоспособным независимо от того, где лежит приёмочный документ.
#
# settings.json едет БЕЗ блока permissions. `defaultMode: bypassPermissions` — решение про
# КОНКРЕТНУЮ машину («локальная dev-машина», как и записано в CLAUDE.md воркспейса), а
# закоммиченный файл в ПУБЛИЧНОМ репозитории — это то же решение, принятое за каждого, кто
# сделает свежий клон, без его ведома. Место такого выбора — .claude/settings.local.json,
# который git игнорирует. Портируемая часть — провязка хуков — едет.
SETTINGS_DROP_HOOKS_JSON="$(printf '%s\n' $WORKSPACE_ONLY_HOOKS | jq -R . | jq -sc .)"

# --- sanity: источник истины на месте ---
for d in rules agents skills hooks; do
  [ -d "$SRC/$d" ] || { echo "FATAL: нет $SRC/$d" >&2; exit 1; }
done
[ -f "$SRC/settings.json" ] || { echo "FATAL: нет $SRC/settings.json" >&2; exit 1; }
command -v jq >/dev/null || { echo "FATAL: нет jq — settings.json не вывести" >&2; exit 1; }

# generic-наборы = то, что воркспейс ОТСЛЕЖИВАЕТ, а не то, что лежит на диске. Раньше здесь
# стоял `ls -1d */`, и раскатывалось всё содержимое каталога, включая скилы, которые
# .gitignore прямо объявляет чужими проекту — объявление и поведение расходились, и
# расхождение было ненаблюдаемо. Единица теперь одна и та же у обоих.
GEN_RULES=""
for f in $(cd "$SRC" && git ls-files rules/ 2>/dev/null | cut -d/ -f2 | sort -u); do
  case " $WORKSPACE_ONLY_RULES " in *" $f "*) continue ;; esac
  GEN_RULES="$GEN_RULES$f "
done
GEN_AGENTS="$(cd "$SRC" && git ls-files agents/ 2>/dev/null | cut -d/ -f2 | sort -u | tr '\n' ' ')"
GEN_SKILLS="$(cd "$SRC" && git ls-files skills/ 2>/dev/null | cut -d/ -f2 | sort -u | tr '\n' ' ')"

for set_name in GEN_RULES GEN_AGENTS GEN_SKILLS; do
  v="${!set_name}"
  [ -n "${v// /}" ] || { echo "FATAL: git не вернул ни одного отслеживаемого элемента для $set_name — раскатка без предмета" >&2; exit 1; }
done

# stage_tooling <staging_dir> — материализует ЖЕЛАЕМОЕ состояние .claude репозитория.
# Единственное место, где решается «что и в каком виде едет»; apply и check оба зовут его,
# поэтому проверенное и применённое совпадают by construction.
stage_tooling() {
  local stage="$1" f s
  mkdir -p "$stage/agents" "$stage/skills" "$stage/rules" "$stage/hooks"

  for f in $GEN_RULES;  do cp "$SRC/rules/$f"  "$stage/rules/$f"; done
  for f in $GEN_AGENTS; do cp "$SRC/agents/$f" "$stage/agents/$f"; done
  for s in $GEN_SKILLS; do cp -R "$SRC/skills/$s" "$stage/skills/$s"; done

  # hooks — только те, у кого есть предмет в репозитории продукта.
  for f in $(cd "$SRC/hooks" && ls -1); do
    case " $WORKSPACE_ONLY_HOOKS " in *" $f "*) continue ;; esac
    cp -R "$SRC/hooks/$f" "$stage/hooks/$f"
  done
  # …но НЕ рантайм-состояние. Счётчик срабатываний существует затем, чтобы «ноль за всю
  # жизнь» было заметно; унаследованный от чужой копии счётчик отвечает на этот вопрос
  # чужой историей, то есть отменяет собственный смысл.
  rm -rf "$stage/hooks/class-guard/.state"
  find "$stage/hooks" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null

  # settings.json — выводится из воркспейсного: без permissions, без провязки невезомых хуков.
  # `$d` здесь именованный, а не `.`: в `$c | contains(.)` точка успевает перепривязаться к
  # самому $c, предикат становится тождественно истинным и вычёркивает ВСЕ хуки. Первая
  # редакция так и сделала — репозиторий получил `{"hooks":{}}`, то есть провязку, не
  # включающую ничего, при внешне корректном файле. Ловится только чтением результата.
  jq --argjson drop "$SETTINGS_DROP_HOOKS_JSON" '
      def keep: (.command // "") as $c | ([$drop[] as $d | select($c | contains($d))] | length) == 0;
      del(.permissions)
      | (.hooks // {}) as $h
      | .hooks = ( $h
          | with_entries(.value |= ( map(.hooks |= map(select(keep))) | map(select((.hooks | length) > 0)) ))
          | with_entries(select((.value | length) > 0)) )
    ' "$SRC/settings.json" > "$stage/settings.json"
}

# managed_paths — что именно скрипт считает своим в целевом .claude. Всё остальное там
# (worktrees, domain-нативные агенты и скилы, локальный settings.local.json) — не его дело.
managed_paths() { printf '%s\n' rules agents skills hooks settings.json; }

failures=0
synced=0
declare -a REPORT=()

while IFS=$'\t' read -r repo identity; do
  [ -n "$repo" ] || continue
  dst="$repo/.claude"

  stage="$(mktemp -d)"
  stage_tooling "$stage"

  # Домены, чьи нативные ассеты нельзя вычищать. У полирепо это часть имени после kacho-;
  # у монорепо доменов столько, сколько сервисов в дереве — перечень тоже выводится, а не
  # выписывается, иначе он разойдётся с services/ ровно так же, как разошёлся REPOS.
  name="${identity##*/}"
  if [ "$name" = "kacho" ]; then
    domains="$(cd "$repo" && ls -1d services/*/ 2>/dev/null | sed 's:services/::;s:/$::' | tr '\n' ' ')"
  else
    domains="${name#kacho-} "
  fi

  is_domain_native() {   # <basename без расширения, либо имя каталога>
    local x="$1" d
    for d in $domains; do
      [ -n "$d" ] || continue
      case "$x" in "$d"-*) return 0 ;; esac
    done
    return 1
  }

  # Исключение живёт, пока у него есть предмет.
  if [ -e "$repo/$STALE_EXCLUSION_SUBJECT" ]; then
    echo "[$identity] НАХОДКА STALE-EXCLUSION: в репозитории появился $STALE_EXCLUSION_SUBJECT," >&2
    echo "           значит исключения ($WORKSPACE_ONLY_RULES $WORKSPACE_ONLY_HOOKS) потеряли предмет и обязаны быть сняты." >&2
    failures=$((failures + 1))
  fi

  if [ "$MODE" = check ]; then
    drift=0
    if [ ! -d "$dst" ]; then
      echo "[$identity] НАХОДКА NO-TOOLING: нет $dst — репозиторий продукта без оснастки; standalone-клон несамодостаточен." >&2
      drift=1
    else
      for p in $(managed_paths); do
        if [ ! -e "$dst/$p" ]; then
          echo "[$identity] НАХОДКА NO-TOOLING: нет $dst/$p" >&2
          drift=1
          continue
        fi
        # Расхождение копии с источником. Сравниваются только управляемые пути; всё, что
        # скрипт в репозитории не создаёт (domain-нативное), из сравнения исключено — иначе
        # гейт краснел бы на законном и был бы отключён первым же ложным срабатыванием.
        excl=()
        if [ "$p" = agents ] || [ "$p" = skills ]; then
          for x in $(cd "$dst/$p" && ls -1 2>/dev/null); do
            is_domain_native "${x%.md}" && excl+=(--exclude="$x")
          done
        fi
        if ! diff -r "${excl[@]}" "$stage/$p" "$dst/$p" >/dev/null 2>&1; then
          echo "[$identity] НАХОДКА DRIFT: $dst/$p разошёлся с источником:" >&2
          diff -r "${excl[@]}" "$stage/$p" "$dst/$p" 2>&1 | sed 's/^/           /' | head -15 >&2
          drift=1
        fi
      done
    fi

    # Самодостаточность: точка входа обязана подтягивать ровно те правила, которые приехали.
    if [ ! -f "$repo/CLAUDE.md" ]; then
      echo "[$identity] НАХОДКА NO-ENTRYPOINT: нет $repo/CLAUDE.md — приехавшие правила ничем не загружаются." >&2
      drift=1
    else
      for f in $GEN_RULES; do
        grep -qF "@.claude/rules/$f" "$repo/CLAUDE.md" || {
          echo "[$identity] НАХОДКА NO-IMPORT: CLAUDE.md не импортирует .claude/rules/$f" >&2
          drift=1
        }
      done
      while read -r imported; do
        [ -n "$imported" ] || continue
        case " $GEN_RULES " in
          *" $imported "*) ;;
          *) echo "[$identity] НАХОДКА DANGLING-IMPORT: CLAUDE.md импортирует .claude/rules/$imported, которого раскатка не везёт" >&2
             drift=1 ;;
        esac
      done < <(grep -oE '@\.claude/rules/[A-Za-z0-9._-]+\.md' "$repo/CLAUDE.md" | sed 's:.*/::' | sort -u)
    fi

    if [ "$drift" -eq 0 ]; then
      REPORT+=("[$identity] ok — rules($(echo "$GEN_RULES" | wc -w)) agents($(echo "$GEN_AGENTS" | wc -w)) skills($(echo "$GEN_SKILLS" | wc -w)) hooks settings CLAUDE.md")
    else
      failures=$((failures + 1))
    fi
  else
    mkdir -p "$dst"
    rm -rf "$dst/rules" "$dst/hooks"
    cp -R "$stage/rules" "$dst/rules"
    cp -R "$stage/hooks" "$dst/hooks"
    cp "$stage/settings.json" "$dst/settings.json"

    mkdir -p "$dst/agents" "$dst/skills"
    for f in $GEN_AGENTS; do cp "$stage/agents/$f" "$dst/agents/$f"; done
    for f in $(cd "$dst/agents" && ls -1 *.md 2>/dev/null); do
      case " $GEN_AGENTS " in *" $f "*) continue ;; esac
      is_domain_native "${f%.md}" && continue
      rm -f "$dst/agents/$f"; echo "[$identity] removed stale agent: $f"
    done
    for s in $GEN_SKILLS; do rm -rf "$dst/skills/$s"; cp -R "$stage/skills/$s" "$dst/skills/$s"; done
    for s in $(cd "$dst/skills" && ls -1d */ 2>/dev/null | sed 's:/$::'); do
      case " $GEN_SKILLS " in *" $s "*) continue ;; esac
      is_domain_native "$s" && continue
      rm -rf "$dst/skills/$s"; echo "[$identity] removed stale skill: $s"
    done

    REPORT+=("[$identity] synced — rules($(ls -1 "$dst/rules"/*.md | wc -l)) agents($(ls -1 "$dst/agents"/*.md | wc -l)) skills($(ls -1d "$dst/skills"/*/ | wc -l)) hooks settings")
  fi

  rm -rf "$stage"
  synced=$((synced + 1))
  unset -f is_domain_native
done < <(kacho_discover_worktrees "$PROJECT_DIR")

[ "${#REPORT[@]}" -eq 0 ] || printf '%s\n' "${REPORT[@]}"
echo "──────────────────────────────────────────────"

# «Раскатано в 0» — это НЕ успех на пустом множестве, а отсутствие предмета, и два исхода
# обязаны различаться. Ровно на этом инвариант и держался невыполненным: перечень из
# одиннадцати имён полирепо не пересекался ни с одним склонированным каталогом, и «нечего
# рассматривать» печаталось как «всё синхронно». Гейт, которому нечего рассматривать,
# обязан это сказать, а не отчитаться нулём находок.
if [ "$synced" -eq 0 ]; then
  {
    echo "ОТКАЗ: в $PROJECT_DIR не найдено ни одной рабочей копии репозитория продукта."
    echo "       Это НЕ «всё уже синхронно»: раскатывать не во что."
    echo "       Осмотрено каталогов: $(ls -1d "$PROJECT_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')."
    echo "       Предикат: собственный корень git + основная (не присоединённая) рабочая копия"
    echo "       + origin вида $KACHO_REPO_OWNER/kacho[-<part>]. См. repos.sh."
  } >&2
  exit 1
fi

repos_distinct="$(kacho_discover_worktrees "$PROJECT_DIR" | cut -f2 | sort -u | wc -l | tr -d ' ')"
dirs_examined="$(ls -1d "$PROJECT_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')"

if [ "$MODE" = check ]; then
  echo "проверено рабочих копий: $synced (различных репозиториев: $repos_distinct; осмотрено каталогов: $dirs_examined)"
  if [ "$failures" -gt 0 ]; then
    echo "НАХОДОК: $failures. Оснастка в репозитории не соответствует источнику — standalone-клон несамодостаточен." >&2
    exit 1
  fi
  echo "находок нет."
else
  echo "tooling раскатан в $synced рабочих копий (различных репозиториев: $repos_distinct; осмотрено каталогов: $dirs_examined)."
  echo "Источник истины — kacho-workspace/.claude."
  [ "$failures" -eq 0 ] || exit 1
fi
