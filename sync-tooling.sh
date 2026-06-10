#!/usr/bin/env bash
# sync-tooling.sh — раскатывает каноническую AI-оснастку из workspace во все репо.
#
# Модель: kacho-workspace/.claude — ЕДИНСТВЕННЫЙ источник истины. Каждый
# project/<repo>/.claude получает полную копию (rules + generic agents + generic
# skills + hooks + settings.json), чтобы репо был самодостаточен при standalone-клоне
# (CI/свежий checkout) — settings.json/hooks вообще не делают parent-walkup.
#
# Domain-агенты и domain-скилы (<domain>-*, где domain = имя репо без префикса
# kacho-) — НАТИВНЫЕ в своём репо, скрипт их не трогает и не перетирает.
# Устаревшие generic-копии (которых больше нет в workspace и которые не domain-*)
# удаляются. Идемпотентно: гонять сколько угодно раз.
#
# Правишь generic-оснастку → ТОЛЬКО в kacho-workspace/.claude, затем ./sync-tooling.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/.claude"
PROJECT_DIR="$SCRIPT_DIR/project"

REPOS=(
  kacho-proto
  kacho-corelib
  kacho-api-gateway
  kacho-iam
  kacho-vpc
  kacho-compute
  kacho-nlb
  kacho-ui
  kacho-deploy
  kacho-vpc-operator
)

# --- sanity: источник истины на месте ---
for d in rules agents skills hooks; do
  [ -d "$SRC/$d" ] || { echo "FATAL: нет $SRC/$d" >&2; exit 1; }
done
[ -f "$SRC/settings.json" ] || { echo "FATAL: нет $SRC/settings.json" >&2; exit 1; }

# generic-наборы = ровно то, что лежит в workspace (space-separated для membership-теста)
GEN_AGENTS="$(cd "$SRC/agents" && ls -1 *.md 2>/dev/null | tr '\n' ' ')"
GEN_SKILLS="$(cd "$SRC/skills" && ls -1d */ 2>/dev/null | sed 's:/$::' | tr '\n' ' ')"

synced=0
for r in "${REPOS[@]}"; do
  repo="$PROJECT_DIR/$r"
  if [ ! -d "$repo/.git" ]; then
    echo "[$r] не склонирован, skip"
    continue
  fi
  domain="${r#kacho-}"          # vpc | compute | api-gateway | vpc-operator | ...
  dst="$repo/.claude"
  mkdir -p "$dst/agents" "$dst/skills"

  # rules — 100% generic: полное зеркало
  rm -rf "$dst/rules"
  cp -R "$SRC/rules" "$dst/rules"

  # hooks — generic: полное зеркало
  rm -rf "$dst/hooks"
  cp -R "$SRC/hooks" "$dst/hooks"

  # settings.json — generic (портируемо через $CLAUDE_PROJECT_DIR)
  cp "$SRC/settings.json" "$dst/settings.json"

  # agents — копируем generic; чистим устаревшие generic (не в наборе и не domain-*)
  for f in $GEN_AGENTS; do
    cp "$SRC/agents/$f" "$dst/agents/$f"
  done
  for f in $(cd "$dst/agents" && ls -1 *.md 2>/dev/null); do
    case " $GEN_AGENTS " in *" $f "*) continue ;; esac   # generic — оставляем
    case "$f" in "$domain"-*) continue ;; esac            # domain-нативный — оставляем
    rm -f "$dst/agents/$f"
    echo "[$r] removed stale agent: $f"
  done

  # skills — зеркалим каждую generic-директорию; чистим устаревшие generic
  for s in $GEN_SKILLS; do
    rm -rf "$dst/skills/$s"
    cp -R "$SRC/skills/$s" "$dst/skills/$s"
  done
  for s in $(cd "$dst/skills" && ls -1d */ 2>/dev/null | sed 's:/$::'); do
    case " $GEN_SKILLS " in *" $s "*) continue ;; esac
    case "$s" in "$domain"-*) continue ;; esac
    rm -rf "$dst/skills/$s"
    echo "[$r] removed stale skill: $s"
  done

  echo "[$r] synced — rules($(ls -1 "$dst/rules"/*.md 2>/dev/null | wc -l | tr -d ' ')) agents($(ls -1 "$dst/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')) skills($(ls -1d "$dst/skills"/*/ 2>/dev/null | wc -l | tr -d ' ')) hooks settings"
  synced=$((synced + 1))
done

echo "──────────────────────────────────────────────"
echo "tooling раскатан в $synced репо. Источник истины — kacho-workspace/.claude."
