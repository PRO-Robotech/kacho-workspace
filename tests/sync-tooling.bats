#!/usr/bin/env bats
# Гейт на класс «объявленная модель распространения не выполняется, и это ненаблюдаемо».
#
# Предмет гейта — ОТСУТСТВИЕ (оснастки в репозитории, целей у раскатки, соответствия копии
# источнику). Гейт, чей предмет — отсутствие, зеленеет легче всех: ему достаточно ничего не
# найти. Поэтому здесь у КАЖДОГО запрета есть пара: инъекция настоящим дефектом (обязан
# покраснеть и НАЗВАТЬ координату) и законный близнец той же формы (обязан молчать).
#
# Перепись — отдельное утверждение: «ноль находок» обязано быть отличимо от «ноль
# осмотренного», поэтому проверяется, что скрипт печатает число осмотренных рабочих копий.

load 'test_helper'

setup() {
  WS="$(mktemp -d)"
  export WS
  # Воркспейс-источник: копируем реальную оснастку и реальные скрипты — гейт обязан
  # прогоняться на том, что поедет, а не на синтетическом наборе.
  #
  # Только ОТСЛЕЖИВАЕМОЕ: `cp -R .claude` утащил бы и `.claude/worktrees/` — 9.8 ГБ
  # агентских рабочих копий, git-ignored. Единица здесь та же, что у самой раскатки
  # (отслеживаемый git-элемент), иначе фикстура шире продукта и меряет не то.
  mkdir -p "$WS/.claude"
  ( cd "$BATS_TEST_DIRNAME/.." && git ls-files -z .claude/ | tar --null -T - -cf - ) \
    | tar -xf - -C "$WS"
  cp "$BATS_TEST_DIRNAME/../repos.sh" "$BATS_TEST_DIRNAME/../sync-tooling.sh" "$WS/"
  chmod +x "$WS/sync-tooling.sh"
  ( cd "$WS" && git init -q . && git add -A .claude >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm tooling >/dev/null 2>&1 )
  mkdir -p "$WS/proj"
  export KACHO_PROJECT_DIR="$WS/proj"
  export KACHO_REPO_OWNER="fake-owner"
}

teardown() { [ -n "${WS:-}" ] && rm -rf "$WS"; }

# make_workcopy <имя-каталога> <owner/name> — рабочая копия с заданной идентичностью origin.
make_workcopy() {
  local dir="$KACHO_PROJECT_DIR/$1" id="$2"
  mkdir -p "$dir" && git init -q "$dir"
  git -C "$dir" remote add origin "https://example.invalid/${id}.git"
  mkdir -p "$dir/services/vpc" "$dir/services/compute"
  ( cd "$dir" && echo x > f && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}

entrypoint_for() {   # <каталог> — CLAUDE.md, импортирующий ровно приехавшие правила
  local dir="$KACHO_PROJECT_DIR/$1" f n=0
  : > "$dir/CLAUDE.md"
  # Пathspec — от корня репозитория фикстуры (.claude/rules/), а не `rules/`. С неверным
  # путём список выходил ПУСТЫМ, CLAUDE.md — тоже, и все проверки, ожидающие КРАСНОГО,
  # оставались зелёными: они краснели по несуществующим импортам, а не по инъекции.
  # Поймали это только парные положительные. Отсюда контроль непустоты ниже.
  for f in $(git -C "$WS" ls-files .claude/rules/ | cut -d/ -f3 | sort -u); do
    [ "$f" = "vault.md" ] && continue
    echo "@.claude/rules/$f" >> "$dir/CLAUDE.md"
    n=$((n + 1))
  done
  [ "$n" -ge 5 ] || { echo "фикстура сломана: собрано $n импортов" >&2; return 1; }
}

# ── Раскатка в ноль целей — ОТКАЗ, а не успех ────────────────────────────────────────
@test "ZERO: пустое множество целей — отказ, а не «всё синхронно»" {
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ОТКАЗ"* ]]
  [[ "$output" == *"раскатывать не во что"* ]] || [[ "$output" == *"обновлять нечего"* ]] || [[ "$output" == *"не найдено ни одной рабочей копии"* ]]
}

@test "ZERO: отказ называет ОБЪЁМ ОСМОТРЕННОГО — «ноль находок» отличимо от «ноль прочитанного»" {
  mkdir -p "$KACHO_PROJECT_DIR/not-a-repo" "$KACHO_PROJECT_DIR/another-non-repo"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"Осмотрено каталогов: 2"* ]]
}

# ── Предикат «рабочая копия репозитория продукта» — контроль в обе стороны ───────────
@test "ПРЕДИКАТ+: клон продукта в каталоге с ПОСТОРОННИМ именем — принимается (опознание по origin)" {
  make_workcopy "zzz-unrelated-name" "fake-owner/kacho"
  entrypoint_for "zzz-unrelated-name"
  run "$WS/sync-tooling.sh"
  [ "$status" -eq 0 ]
  [ -f "$KACHO_PROJECT_DIR/zzz-unrelated-name/.claude/settings.json" ]
}

@test "ПРЕДИКАТ-: каталог, НАЗВАННЫЙ как репозиторий продукта, но с чужим origin — отвергается" {
  make_workcopy "kacho-compute" "someone-else/kacho-compute"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ОТКАЗ"* ]]
  [ ! -e "$KACHO_PROJECT_DIR/kacho-compute/.claude" ]
}

@test "ПРЕДИКАТ-: другой продукт того же владельца — отвергается" {
  make_workcopy "beget-hbf" "fake-owner/beget-hbf"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ОТКАЗ"* ]]
}

@test "ПРЕДИКАТ-: каталог БЕЗ git внутри git-родителя не опознаётся как рабочая копия" {
  # Классический промах: `git -C <dir> rev-parse` делает walkup и отвечает про РОДИТЕЛЯ.
  mkdir -p "$KACHO_PROJECT_DIR/plain-files/sub" && echo x > "$KACHO_PROJECT_DIR/plain-files/sub/a"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ОТКАЗ"* ]]
}

@test "ПРЕДИКАТ-: присоединённая рабочая копия (git worktree) не считается отдельной целью" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  git -C "$KACHO_PROJECT_DIR/kacho" worktree add -q -b wt "$KACHO_PROJECT_DIR/kacho-wt" >/dev/null 2>&1
  run "$WS/sync-tooling.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"раскатан в 1 рабочих копий"* ]]
  [ ! -e "$KACHO_PROJECT_DIR/kacho-wt/.claude" ]
}

# ── Репозиторий продукта БЕЗ оснастки — находка ──────────────────────────────────────
@test "NO-TOOLING: репозиторий продукта без .claude — красное с координатой" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА NO-TOOLING"* ]]
  [[ "$output" == *"kacho/.claude"* ]]
}

@test "NO-ENTRYPOINT: оснастка приехала, но грузить её нечем — красное" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  rm -f "$KACHO_PROJECT_DIR/kacho/CLAUDE.md"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА NO-ENTRYPOINT"* ]]
}

# ── Расхождение копии с источником ───────────────────────────────────────────────────
@test "DRIFT: правило в копии разошлось с источником — красное с координатой" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  echo "правка по месту" >> "$KACHO_PROJECT_DIR/kacho/.claude/rules/security.md"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА DRIFT"* ]]
  [[ "$output" == *"rules"* ]]
}

@test "DRIFT: подменённая провязка хука в settings.json — красное" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  sed -i 's/class-guard.sh/nope.sh/' "$KACHO_PROJECT_DIR/kacho/.claude/settings.json"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА DRIFT"* ]]
}

@test "КОНТРОЛЬ: domain-нативные агент и скил — законный близнец, гейт МОЛЧИТ" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  # services/ содержит vpc и compute ⇒ vpc-* и compute-* здесь нативные, не «устаревшее generic»
  echo native > "$KACHO_PROJECT_DIR/kacho/.claude/agents/vpc-cidr-specialist.md"
  mkdir -p "$KACHO_PROJECT_DIR/kacho/.claude/skills/compute-load-testing"
  echo native > "$KACHO_PROJECT_DIR/kacho/.claude/skills/compute-load-testing/SKILL.md"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"находок нет"* ]]
  # и раскатка их не сносит
  "$WS/sync-tooling.sh" >/dev/null
  [ -f "$KACHO_PROJECT_DIR/kacho/.claude/agents/vpc-cidr-specialist.md" ]
  [ -f "$KACHO_PROJECT_DIR/kacho/.claude/skills/compute-load-testing/SKILL.md" ]
}

@test "STALE: устаревший generic-агент (не нативный домену) вычищается" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  echo old > "$KACHO_PROJECT_DIR/kacho/.claude/agents/some-retired-agent.md"
  run "$WS/sync-tooling.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$KACHO_PROJECT_DIR/kacho/.claude/agents/some-retired-agent.md" ]
}

# ── Импорты: приехавшее грузится, загружаемое приехало ───────────────────────────────
@test "NO-IMPORT: приехавшее правило не подтягивается точкой входа — красное" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  sed -i '/security.md/d' "$KACHO_PROJECT_DIR/kacho/CLAUDE.md"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА NO-IMPORT"* ]]
}

@test "DANGLING-IMPORT: точка входа грузит правило, которого раскатка не везёт — красное" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  echo "@.claude/rules/vault.md" >> "$KACHO_PROJECT_DIR/kacho/CLAUDE.md"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА DANGLING-IMPORT"* ]]
}

# ── Исключение живёт, пока у него есть предмет ───────────────────────────────────────
@test "STALE-EXCLUSION: у исключения появился предмет — находка, исключение обязано быть снято" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  mkdir -p "$KACHO_PROJECT_DIR/kacho/obsidian/kacho"
  run "$WS/sync-tooling.sh" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"НАХОДКА STALE-EXCLUSION"* ]]
}

# ── Провязка не может указывать в пустоту ────────────────────────────────────────────
@test "СОДЕРЖАНИЕ: каждый провязанный в settings.json хук существует, и хотя бы один есть" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  local dst="$KACHO_PROJECT_DIR/kacho/.claude"
  # Отрицание («невезомых нет») в паре с положительным («провязано не пусто») — иначе
  # утверждение зеленеет сильнее всего ровно тогда, когда провязка пуста целиком.
  local n
  n="$(grep -oE '[a-z-]+\.sh' "$dst/settings.json" | sort -u | wc -l)"
  [ "$n" -ge 1 ]
  for h in $(grep -oE '[a-z-]+\.sh' "$dst/settings.json" | sort -u); do
    [ -f "$dst/hooks/$h" ]
  done
  ! grep -q 'vault-reminder.sh\|vault-stop-check.sh' "$dst/settings.json"
  [ ! -e "$dst/hooks/vault-reminder.sh" ]
  [ ! -e "$dst/rules/vault.md" ]
}

@test "СОДЕРЖАНИЕ: раскатанный settings.json не навязывает посадку прав репозиторию" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  run jq -e '.permissions' "$KACHO_PROJECT_DIR/kacho/.claude/settings.json"
  [ "$status" -ne 0 ]
  # ...при том что в источнике он есть — иначе утверждение пусто
  run jq -e '.permissions' "$WS/.claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "ИДЕМПОТЕНТНОСТЬ: повторная раскатка — no-op, гейт остаётся зелёным" {
  make_workcopy "kacho" "fake-owner/kacho"
  entrypoint_for "kacho"
  "$WS/sync-tooling.sh" >/dev/null
  "$WS/sync-tooling.sh" >/dev/null
  run "$WS/sync-tooling.sh" --check
  [ "$status" -eq 0 ]
}
